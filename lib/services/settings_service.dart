import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Voice commands the app listens for. Each has a configurable phrase
/// (what the doctor actually says) stored in a Hive settings box.
///
/// Commands fall into three groups:
///   - Navigation:  dashboard, newReport, openReports, openSettings, back
///   - Recording:   start, pause, resume, stop
///   - Report:      generate, save, discard, patientId, confirm, cancel
enum VoiceCommand {
  // Navigation
  dashboard,
  newReport,
  openReports,
  openSettings,
  back,
  // Recording
  start,
  pause,
  resume,
  stop,
  // Report
  generate,
  save,
  discard,
  patientId,
  confirm,
  cancel,
}

extension VoiceCommandKey on VoiceCommand {
  String get key => toString().split('.').last;

  String get label {
    switch (this) {
      case VoiceCommand.dashboard:
        return 'Go to Dashboard';
      case VoiceCommand.newReport:
        return 'New Report';
      case VoiceCommand.openReports:
        return 'Open Reports';
      case VoiceCommand.openSettings:
        return 'Open Settings';
      case VoiceCommand.back:
        return 'Go Back';
      case VoiceCommand.start:
        return 'Start Recording';
      case VoiceCommand.pause:
        return 'Pause Recording';
      case VoiceCommand.resume:
        return 'Resume Recording';
      case VoiceCommand.stop:
        return 'Stop Recording';
      case VoiceCommand.generate:
        return 'Generate Report';
      case VoiceCommand.save:
        return 'Save Report';
      case VoiceCommand.discard:
        return 'Discard';
      case VoiceCommand.patientId:
        return 'Set Patient ID (prefix)';
      case VoiceCommand.confirm:
        return 'Confirm / Yes';
      case VoiceCommand.cancel:
        return 'Cancel / No';
    }
  }
}

class SettingsService {
  static const String _boxName = 'settings';
  static const String _commandsKey = 'voice_commands';
  static const String _localeKey = 'speech_locale';
  static const String _pathologistNameKey = 'pathologist_name';
  static const String _pathologistRegKey = 'pathologist_registration';

  static Box get _box => Hive.box(_boxName);

  static Future<void> init() async {
    await Hive.openBox(_boxName);
    if (_box.get(_commandsKey) == null) {
      await _box.put(_commandsKey, defaults());
    }
  }

  /// Default spoken phrases — lower-cased, matched against the live transcript.
  /// Multiple synonyms per command are separated by '|'.
  static Map<String, String> defaults() => <String, String>{
        VoiceCommand.dashboard.key: 'home|dashboard|go home',
        VoiceCommand.newReport.key: 'new report|create report|start a report',
        VoiceCommand.openReports.key: 'show reports|open reports|list reports',
        VoiceCommand.openSettings.key: 'open settings|settings',
        VoiceCommand.back.key: 'go back|back',
        VoiceCommand.start.key: 'start dictation|start recording|begin',
        VoiceCommand.pause.key: 'pause',
        VoiceCommand.resume.key: 'resume|continue',
        VoiceCommand.stop.key: 'stop recording|stop dictation|end dictation',
        VoiceCommand.generate.key: 'generate report|create report now',
        VoiceCommand.save.key: 'save report|save it',
        VoiceCommand.discard.key: 'discard|delete this',
        VoiceCommand.patientId.key: 'patient id is|patient id',
        VoiceCommand.confirm.key: 'confirm|yes|correct',
        VoiceCommand.cancel.key: 'cancel|no',
      };

  static Map<String, String> getPhrases() {
    final raw = _box.get(_commandsKey) as Map?;
    if (raw == null) return defaults();
    return Map<String, String>.from(raw.map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    ));
  }

  static Future<void> setPhrase(VoiceCommand cmd, String phrase) async {
    final map = getPhrases();
    map[cmd.key] = phrase.trim().toLowerCase();
    await _box.put(_commandsKey, map);
    _notifier.value++;
  }

  static Future<void> resetDefaults() async {
    await _box.put(_commandsKey, defaults());
    _notifier.value++;
  }

  static String getLocale() => _box.get(_localeKey, defaultValue: 'en_US');
  static Future<void> setLocale(String v) => _box.put(_localeKey, v);

  static String getPathologistName() => _box.get(_pathologistNameKey,
      defaultValue: 'Dr. Komal D. Chippalkatti');
  static Future<void> setPathologistName(String v) =>
      _box.put(_pathologistNameKey, v);

  static String getPathologistRegistration() =>
      _box.get(_pathologistRegKey, defaultValue: 'KMC - 79367');
  static Future<void> setPathologistRegistration(String v) =>
      _box.put(_pathologistRegKey, v);

  // Notifier so widgets watching settings rebuild on change.
  static final ValueNotifier<int> _notifier = ValueNotifier<int>(0);
  static ValueNotifier<int> get changes => _notifier;
}
