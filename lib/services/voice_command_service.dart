import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'settings_service.dart';

/// A detected command plus optional payload.
class VoiceCommandEvent {
  final VoiceCommand command;
  final String payload;
  VoiceCommandEvent(this.command, {this.payload = ''});
}

/// One recognizer result — either a still-growing partial or a finalized chunk.
class TranscriptUpdate {
  final String text;
  final bool isFinal;
  TranscriptUpdate(this.text, {required this.isFinal});
}

/// One line of diagnostic log.
class VoiceLogLine {
  final DateTime time;
  final String level; // info, warn, error, match
  final String message;
  VoiceLogLine(this.level, this.message) : time = DateTime.now();

  @override
  String toString() {
    final t =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}.${time.millisecond.toString().padLeft(3, '0')}';
    return '$t [$level] $message';
  }
}

/// Continuous on-device speech recognizer.
///
/// On macOS the underlying `SFSpeechRecognizer` finalizes after ~60s of
/// silence and the audio engine drops out. To keep the live transcript
/// flowing without a visible seam this service uses a *proactive overlap*:
/// at the 45s mark we schedule a `_listenOnce()` that re-arms a fresh
/// recognizer task BEFORE the current one finalizes, so the listening pill
/// never blinks off.
class VoiceCommandService {
  VoiceCommandService._();
  static final VoiceCommandService instance = VoiceCommandService._();

  final stt.SpeechToText _stt = stt.SpeechToText();

  bool _available = false;
  bool _initialized = false;
  bool _shouldListen = false;
  bool _currentlyListening = false;
  // Re-entry guard: SFSpeechRecognizer owns a single AVAudioEngine input-node
  // singleton. Two `listen()` calls in flight at the same time crash with a
  // pointer-authentication failure on macOS (one engine tears down while
  // another grabs the input node). We serialize all listen attempts with this
  // flag — no overlap, ever.
  bool _listenInFlight = false;
  String _lastMatched = '';
  DateTime _lastMatchTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastError = '';
  String _lastStatus = '';

  final _commandController = StreamController<VoiceCommandEvent>.broadcast();
  final _transcriptController =
      StreamController<TranscriptUpdate>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _logController = StreamController<VoiceLogLine>.broadcast();

  static const int _maxLogLines = 200;
  final List<VoiceLogLine> _logBuffer = [];

  Stream<VoiceCommandEvent> get commands => _commandController.stream;
  Stream<TranscriptUpdate> get transcript => _transcriptController.stream;
  Stream<String> get status => _statusController.stream;
  Stream<VoiceLogLine> get logStream => _logController.stream;
  List<VoiceLogLine> get log => List.unmodifiable(_logBuffer);

  bool get isAvailable => _available;
  bool get isInitialized => _initialized;
  bool get isListening => _currentlyListening;
  String get lastError => _lastError;
  String get lastStatus => _lastStatus;

  String _sessionTranscript = '';
  String get sessionTranscript => _sessionTranscript;

  // ─── Public ────────────────────────────────────────────────

  Future<bool> init() async {
    if (_initialized) {
      _log('info',
          'init() called — already initialized, available=$_available');
      return _available;
    }
    _log('info',
        'Initializing speech_to_text · platform=${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    try {
      _available = await _stt.initialize(
        onError: (e) {
          _lastError = e.errorMsg;
          _log('error',
              'stt onError: ${e.errorMsg} (permanent=${e.permanent})');
          _statusController.add('error: ${e.errorMsg}');
          _currentlyListening = false;
          if (!e.permanent) _restartIfNeeded();
        },
        onStatus: (s) {
          _lastStatus = s;
          _log('info', 'stt onStatus: $s');
          _statusController.add(s);
          if (s == 'done' || s == 'notListening') {
            _currentlyListening = false;
            _restartIfNeeded();
          } else if (s == 'listening') {
            _currentlyListening = true;
          }
        },
        debugLogging: kDebugMode,
      );
      _initialized = true;
      bool hasPerm = false;
      try {
        hasPerm = await _stt.hasPermission;
      } catch (e) {
        _log('warn', 'hasPermission threw: $e');
      }
      _log('info',
          'initialize() returned available=$_available · hasPermission=$hasPerm');
      if (!_available) {
        // Compose a specific, platform-aware hint for the user.
        String hint;
        if (Platform.isWindows) {
          hint = !hasPerm
              ? 'Microphone access is blocked. Open Windows Settings → Privacy & security → Microphone, allow desktop apps, then tap Retry.'
              : 'Windows Speech Recognition is unavailable. Open Settings → Time & Language → Speech, install the en-US speech pack and turn on online speech recognition, then tap Retry.';
        } else if (Platform.isMacOS || Platform.isIOS) {
          hint = !hasPerm
              ? 'Missing Microphone or Speech Recognition permission. Open System Settings → Privacy & Security, enable both, then tap Retry.'
              : 'Recognizer unavailable even though permission is granted. This usually means the OS speech service has not installed the en_US model yet. Wait a minute and retry, or open System Settings → Keyboard → Dictation and enable Dictation once.';
        } else {
          hint =
              'Voice recognition is not supported on this platform. You can still use the app with touch and the on-screen keyboard.';
        }
        if (_lastError.isEmpty) _lastError = hint;
        _log('error', hint);
      } else {
        try {
          final locales = await _stt.locales();
          _log('info',
              'available locales (${locales.length}): ${locales.take(8).map((l) => l.localeId).join(", ")}${locales.length > 8 ? "…" : ""}');
        } catch (_) {}
      }
    } catch (e, st) {
      _log('error', 'initialize() threw: $e\n$st');
      _available = false;
      _initialized = true;
      _lastError = 'initialize() threw: $e';
    }
    return _available;
  }

  /// Fully tear down and re-create the recognizer. Use this from the
  /// "Retry" button in the UI after the user grants permission.
  Future<bool> reinit() async {
    _log('info', 'reinit() called — tearing down…');
    try {
      await _stt.stop();
    } catch (_) {}
    _initialized = false;
    _available = false;
    _currentlyListening = false;
    _shouldListen = false;
    _listenInFlight = false;
    _lastError = '';
    final ok = await init();
    if (ok) {
      _shouldListen = true;
      await _listenOnce();
    }
    return ok;
  }

  /// Open the macOS System Settings pane that hosts the permission the app
  /// most likely needs. No-op on other platforms.
  Future<void> openMacSystemSettings({String pane = 'speech'}) async {
    if (!Platform.isMacOS) return;
    String url;
    switch (pane) {
      case 'microphone':
        url =
            'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone';
        break;
      case 'dictation':
        url = 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension';
        break;
      default:
        url =
            'x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition';
    }
    _log('info', 'Opening System Settings: $url');
    try {
      await Process.run('open', [url]);
    } catch (e) {
      _log('warn', 'open System Settings failed: $e');
    }
  }

  Future<void> start() async {
    try {
      _log('info',
          'start() called · initialized=$_initialized · available=$_available');
      if (!_initialized) await init();
      if (!_available) {
        _log('error', 'Cannot start — recognizer unavailable.');
        return;
      }
      _shouldListen = true;
      await _listenOnce();
    } catch (e, st) {
      // Never let an unawaited start() take down the calling screen. The home
      // page fires this in initState without an await, so any throw here
      // becomes an unhandled async error that surfaces as a red-screen crash.
      _log('error', 'start() threw: $e\n$st');
      _currentlyListening = false;
    }
  }

  Future<void> stop() async {
    _log('info', 'stop() called');
    _shouldListen = false;
    try {
      await _stt.stop();
    } catch (e) {
      _log('warn', 'stop threw: $e');
    }
    _currentlyListening = false;
  }

  Future<void> clearSessionTranscript() async {
    _sessionTranscript = '';
  }

  /// One-shot listen — used by the "Test microphone" button to quickly verify
  /// the pipeline end-to-end. Returns the final transcript (or '').
  Future<String> testOnce({Duration duration = const Duration(seconds: 5)}) async {
    if (!_initialized) await init();
    if (!_available) return '';
    final wasListening = _shouldListen;
    _shouldListen = false;
    try {
      await _stt.stop();
    } catch (_) {}
    _log('info', 'testOnce: listening for ${duration.inSeconds}s');
    final completer = Completer<String>();
    try {
      await _stt.listen(
        onResult: (r) {
          _log('match', 'testOnce result: "${r.recognizedWords}" final=${r.finalResult}');
          if (r.finalResult && !completer.isCompleted) {
            completer.complete(r.recognizedWords);
          }
        },
        listenFor: duration,
        pauseFor: const Duration(seconds: 3),
        localeId: SettingsService.getLocale(),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          // Windows speech recognition is on-device only; iOS / macOS support
          // local recognition explicitly. Android falls back to cloud.
          onDevice: Platform.isMacOS || Platform.isIOS || Platform.isWindows,
          autoPunctuation: true,
          enableHapticFeedback: false,
        ),
      );
    } catch (e) {
      _log('error', 'testOnce listen threw: $e');
      if (!completer.isCompleted) completer.complete('');
    }
    Future.delayed(duration + const Duration(seconds: 1), () {
      if (!completer.isCompleted) completer.complete('');
    });
    final result = await completer.future;
    _log('info', 'testOnce finished: "$result"');
    if (wasListening) {
      _shouldListen = true;
      _listenOnce();
    }
    return result;
  }

  void dispose() {
    _shouldListen = false;
    _stt.stop();
    _commandController.close();
    _transcriptController.close();
    _statusController.close();
    _logController.close();
  }

  // ─── internals ─────────────────────────────────────────────

  Future<void> _listenOnce() async {
    if (!_available) {
      _log('warn', '_listenOnce: not available, skipping');
      return;
    }
    if (!_shouldListen) {
      _log('info', '_listenOnce: shouldListen=false, skipping');
      return;
    }
    // Re-entry guard. SFSpeechRecognizer crashes (PAC failure on the input
    // node singleton) when two `listen()` calls are in flight at the same
    // time — the original symptom was an immediate EXC_BAD_ACCESS in
    // AVAudioIONodeImpl::AUI() on macOS 26. We never overlap.
    if (_listenInFlight) {
      _log('info', '_listenOnce: another listen() is in flight, skipping');
      return;
    }
    if (_currentlyListening) {
      _log('info', '_listenOnce: already listening, skipping');
      return;
    }
    _listenInFlight = true;
    try {
      _log('info',
          '_listenOnce: calling stt.listen(locale=${SettingsService.getLocale()})');
      await _stt.listen(
        onResult: _onResult,
        // Long listen window — Apple removes the historical 1-minute server
        // cap when on-device recognition is enabled, so a 5-minute window is
        // safe and avoids forced restarts within a typical dictation.
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 10),
        localeId: SettingsService.getLocale(),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          // onDevice forces the local model on macOS / iOS — no network
          // round-trip per partial. Windows speech recognition is on-device
          // only, so request the local model there too.
          onDevice: Platform.isMacOS || Platform.isIOS || Platform.isWindows,
          autoPunctuation: true,
          enableHapticFeedback: false,
        ),
      );
      _currentlyListening = true;
      _log('info', 'stt.listen() succeeded — now listening');
    } catch (e, st) {
      _log('error', '_listenOnce threw: $e\n$st');
      _currentlyListening = false;
      _restartIfNeeded();
    } finally {
      _listenInFlight = false;
    }
  }

  /// Reactive restart: invoked from the recognizer's `done` / `notListening`
  /// status callback. We wait a beat to give the OS audio engine time to
  /// fully tear down before re-arming — this is the difference between a
  /// clean restart and the PAC-failure crash we used to see when restarting
  /// too eagerly.
  void _restartIfNeeded() {
    if (!_shouldListen) return;
    Future.delayed(const Duration(milliseconds: 600), _listenOnce);
  }

  void _onResult(SpeechRecognitionResult r) {
    final text = r.recognizedWords.trim();
    if (text.isEmpty) return;
    _log(r.finalResult ? 'info' : 'info',
        'onResult ${r.finalResult ? "final" : "partial"}: "$text"');
    _transcriptController
        .add(TranscriptUpdate(text, isFinal: r.finalResult));
    if (r.finalResult) {
      if (_sessionTranscript.isEmpty) {
        _sessionTranscript = text;
      } else {
        _sessionTranscript = '$_sessionTranscript $text';
      }
    }
    _detectCommands(text);
  }

  void _detectCommands(String text) {
    final lower = text.toLowerCase();
    final phrases = SettingsService.getPhrases();

    // Patient ID trigger
    final patientIdPhrase = phrases[VoiceCommand.patientId.key] ?? '';
    for (final alt in _split(patientIdPhrase)) {
      final idx = lower.lastIndexOf(alt);
      if (idx == -1) continue;
      final rest = lower.substring(idx + alt.length).trim();
      if (rest.isEmpty) continue;
      final tail = _trimAtAnyCommand(rest, phrases);
      final normalized = _normalizePatientId(tail);
      if (normalized.isEmpty) continue;
      _fire(VoiceCommand.patientId, payload: normalized, raw: '$alt $tail');
      return;
    }

    // Other commands
    for (final entry in phrases.entries) {
      if (entry.key == VoiceCommand.patientId.key) continue;
      final cmd = _commandFromKey(entry.key);
      if (cmd == null) continue;
      for (final alt in _split(entry.value)) {
        if (_tailContains(lower, alt)) {
          _fire(cmd, raw: alt);
          return;
        }
      }
    }
  }

  bool _tailContains(String lower, String phrase) {
    if (phrase.isEmpty) return false;
    final tail = lower.length > 60 ? lower.substring(lower.length - 60) : lower;
    return tail.contains(phrase);
  }

  void _fire(VoiceCommand cmd,
      {String payload = '', required String raw}) {
    final key = '${cmd.key}|$payload';
    final now = DateTime.now();
    if (_lastMatched == key &&
        now.difference(_lastMatchTime).inMilliseconds < 1500) {
      return;
    }
    _lastMatched = key;
    _lastMatchTime = now;
    _log('match',
        'COMMAND ${cmd.key}${payload.isNotEmpty ? " payload=\"$payload\"" : ""} · triggered by "$raw"');
    _commandController.add(VoiceCommandEvent(cmd, payload: payload));
  }

  VoiceCommand? _commandFromKey(String key) {
    for (final c in VoiceCommand.values) {
      if (c.key == key) return c;
    }
    return null;
  }

  List<String> _split(String phrases) => phrases
      .split('|')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String _trimAtAnyCommand(String text, Map<String, String> phrases) {
    int cut = text.length;
    for (final entry in phrases.entries) {
      if (entry.key == VoiceCommand.patientId.key) continue;
      for (final alt in _split(entry.value)) {
        final i = text.indexOf(alt);
        if (i != -1 && i < cut) cut = i;
      }
    }
    return text.substring(0, cut).trim();
  }

  /// Normalize a spoken number/id phrase into a compact identifier. Public
  /// so callers (e.g. the guided wizard for integer/decimal answers) can
  /// reuse the same digit/word mapping.
  static String normalizeSpokenId(String input) => _normalizePatientId(input);

  static String _normalizePatientId(String input) {
    const numberWords = {
      'zero': '0',
      'oh': '0',
      'o': '0',
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'for': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
      'ten': '10',
      'dash': '-',
      'hyphen': '-',
      'slash': '/',
      'point': '.',
      'dot': '.',
    };
    final out = StringBuffer();
    for (final raw in input.toLowerCase().split(RegExp(r'\s+'))) {
      final word = raw.replaceAll(RegExp(r'[^a-z0-9\-/.]'), '');
      if (word.isEmpty) continue;
      if (numberWords.containsKey(word)) {
        out.write(numberWords[word]);
      } else {
        out.write(word);
      }
    }
    return out.toString().toUpperCase();
  }

  void _log(String level, String message) {
    final line = VoiceLogLine(level, message);
    if (_logBuffer.length >= _maxLogLines) {
      _logBuffer.removeAt(0);
    }
    _logBuffer.add(line);
    if (!_logController.isClosed) _logController.add(line);
    debugPrint('[voice.$level] $message');
  }
}
