import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

enum RecordingState { idle, recording, paused }

class AudioService {
  final Record _recorder = Record();
  RecordingState _state = RecordingState.idle;
  String? _currentFilePath;
  DateTime? _recordingStartTime;
  Timer? _durationTimer;
  Duration _currentDuration = Duration.zero;
  bool _streamingSession = false;

  RecordingState get state => _state;
  String? get currentFilePath => _currentFilePath;
  Duration get currentDuration => _currentDuration;

  // Stream for duration updates
  final _durationController = StreamController<Duration>.broadcast();
  Stream<Duration> get durationStream => _durationController.stream;

  // Stream for amplitude (waveform visualization)
  final _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      // record_windows / record_linux can throw MissingPluginException when
      // the host machine has no working audio capture stack. Treat that as
      // "no permission" so the caller surfaces a clean error instead of
      // crashing the screen.
      return false;
    }
  }

  Future<String?> startRecording({String? label}) async {
    try {
      if (!await hasPermission()) {
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = p.join(dir.path, 'pathology_recordings');
      final recordingsDirObj = Directory(recordingsDir);
      if (!await recordingsDirObj.exists()) {
        await recordingsDirObj.create(recursive: true);
      }

      final fileName = '${const Uuid().v4()}.m4a';
      _currentFilePath = p.join(recordingsDir, fileName);

      await _recorder.start(path: _recorderPathFor(_currentFilePath!));

      _state = RecordingState.recording;
      _recordingStartTime = DateTime.now();
      _currentDuration = Duration.zero;

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _currentDuration = DateTime.now().difference(_recordingStartTime!);
        _durationController.add(_currentDuration);
      });

      // Start amplitude monitoring
      _startAmplitudeMonitoring();

      return _currentFilePath;
    } catch (e) {
      _state = RecordingState.idle;
      return null;
    }
  }

  void _startAmplitudeMonitoring() {
    Timer.periodic(const Duration(milliseconds: 150), (timer) async {
      if (_state != RecordingState.recording) {
        timer.cancel();
        return;
      }
      try {
        final amplitude = await _recorder.getAmplitude();
        // Normalize: amplitude.current is in dBFS (typically -160 to 0)
        final normalized = ((amplitude.current + 50) / 50).clamp(0.0, 1.0);
        _amplitudeController.add(normalized);
      } catch (_) {
        timer.cancel();
      }
    });
  }

  Future<void> pauseRecording() async {
    if (_state == RecordingState.recording) {
      await _recorder.pause();
      _state = RecordingState.paused;
      _durationTimer?.cancel();
    }
  }

  Future<void> resumeRecording() async {
    if (_state == RecordingState.paused) {
      await _recorder.resume();
      _state = RecordingState.recording;
      final pausedDuration = _currentDuration;
      _recordingStartTime = DateTime.now().subtract(pausedDuration);
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _currentDuration = DateTime.now().difference(_recordingStartTime!);
        _durationController.add(_currentDuration);
      });
      _startAmplitudeMonitoring();
    }
  }

  Future<String?> stopRecording() async {
    _durationTimer?.cancel();
    if (_state != RecordingState.idle) {
      await _recorder.stop();
      _state = RecordingState.idle;
      _streamingSession = false;
      return _currentFilePath;
    }
    return null;
  }

  /// Start a streaming session. Behaves like [startRecording] but marks the
  /// session so [rotateRecording] keeps the duration timer running across
  /// chunk boundaries.
  Future<String?> startStreamRecording() async {
    final path = await startRecording();
    if (path != null) _streamingSession = true;
    return path;
  }

  /// Stop the current chunk, immediately start a new chunk, and return the
  /// finished chunk's file path. Duration / amplitude streams keep ticking
  /// as if one continuous recording.
  Future<String?> rotateRecording() async {
    if (_state != RecordingState.recording || !_streamingSession) return null;

    final finishedPath = _currentFilePath;
    try {
      await _recorder.stop();
    } catch (_) {
      return finishedPath;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = p.join(dir.path, 'pathology_recordings');
      final fileName = '${const Uuid().v4()}.m4a';
      _currentFilePath = p.join(recordingsDir, fileName);
      await _recorder.start(path: _recorderPathFor(_currentFilePath!));
      // Duration timer keeps running — cumulative duration across chunks.
    } catch (_) {
      _state = RecordingState.idle;
      _streamingSession = false;
    }

    return finishedPath;
  }

  // macOS requires `file:///` URLs; Windows/Linux need native paths.
  String _recorderPathFor(String nativePath) {
    if (Platform.isMacOS) return Uri.file(nativePath).toString();
    return nativePath;
  }

  void dispose() {
    _durationTimer?.cancel();
    _durationController.close();
    _amplitudeController.close();
    _recorder.dispose();
  }
}
