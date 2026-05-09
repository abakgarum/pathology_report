import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Voice commands the app listens for. Each has a configurable phrase
/// (what the doctor actually says) stored in a Hive settings box.
///
/// Commands fall into four groups:
///   - Navigation:  dashboard, newReport, openReports, openSettings, back
///   - Recording:   start, pause, resume, stop
///   - Report:      generate, save, discard, patientId, confirm, cancel
///   - Wizard:      next, previous, skip (used by the guided template flow)
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
  // Guided wizard
  next,
  previous,
  skip,
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
      case VoiceCommand.next:
        return 'Next Question';
      case VoiceCommand.previous:
        return 'Previous Question';
      case VoiceCommand.skip:
        return 'Skip Question';
    }
  }
}

class SettingsService {
  static const String _boxName = 'settings';
  static const String _commandsKey = 'voice_commands';
  static const String _localeKey = 'speech_locale';
  static const String _pathologistNameKey = 'pathologist_name';
  static const String _pathologistRegKey = 'pathologist_registration';
  static const String _pathologistTitleKey = 'pathologist_title';
  static const String _activeTemplateIdKey = 'active_template_id';

  // Branding
  static const String _clinicNameKey = 'clinic_name';
  static const String _clinicAddressKey = 'clinic_address';
  static const String _clinicPhoneKey = 'clinic_phone';
  static const String _clinicEmailKey = 'clinic_email';
  static const String _clinicWebsiteKey = 'clinic_website';
  static const String _clinicLogoPathKey = 'clinic_logo_path';
  static const String _watermarkTextKey = 'pdf_watermark_text';
  static const String _printLinearBarcodeKey = 'print_linear_barcode';

  // Dual sign-out (admin-controlled). When enabled, every report is
  // snapshotted with both pathologists' name + registration so the printed
  // report carries two signature blocks side-by-side.
  static const String _dualSignatureEnabledKey = 'dual_signature_enabled';
  static const String _pathologist2NameKey = 'pathologist2_name';
  static const String _pathologist2RegKey = 'pathologist2_registration';
  static const String _pathologist2TitleKey = 'pathologist2_title';

  static Box get _box => Hive.box(_boxName);

  static Future<void> init() async {
    await Hive.openBox(_boxName);
    if (_box.get(_commandsKey) == null) {
      await _box.put(_commandsKey, defaults());
    } else {
      // Merge in any commands that did not exist when the user's settings were
      // first written (so upgrades pick up `next` / `previous` / `skip`
      // automatically without resetting custom phrases).
      final stored = Map<String, String>.from(
        (_box.get(_commandsKey) as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );
      var changed = false;
      for (final entry in defaults().entries) {
        if (!stored.containsKey(entry.key)) {
          stored[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed) {
        await _box.put(_commandsKey, stored);
      }
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
        VoiceCommand.next.key: 'next|next question|move on',
        VoiceCommand.previous.key: 'previous|go back one|previous question',
        VoiceCommand.skip.key: 'skip|skip this|leave blank',
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
  static Future<void> setPathologistName(String v) async {
    await _box.put(_pathologistNameKey, v);
    _notifier.value++;
  }

  static String getPathologistRegistration() =>
      _box.get(_pathologistRegKey, defaultValue: 'KMC - 79367');
  static Future<void> setPathologistRegistration(String v) async {
    await _box.put(_pathologistRegKey, v);
    _notifier.value++;
  }

  static String getPathologistTitle() => _box.get(_pathologistTitleKey,
      defaultValue: 'Consultant & Head - Histopathology & Laboratory Medicine');
  static Future<void> setPathologistTitle(String v) async {
    await _box.put(_pathologistTitleKey, v);
    _notifier.value++;
  }

  /// Active report template id. Empty string means "no template" — the
  /// generator will fall back to its internal structure.
  static String getActiveTemplateId() =>
      _box.get(_activeTemplateIdKey, defaultValue: '');
  static Future<void> setActiveTemplateId(String v) async {
    await _box.put(_activeTemplateIdKey, v);
    _notifier.value++;
  }

  // ─── Branding ────────────────────────────────────────────────────────

  static String getClinicName() => _box.get(_clinicNameKey,
      defaultValue: 'DEPARTMENT OF LABORATORY MEDICINE');
  static Future<void> setClinicName(String v) async {
    await _box.put(_clinicNameKey, v);
    _notifier.value++;
  }

  static String getClinicAddress() =>
      _box.get(_clinicAddressKey, defaultValue: '');
  static Future<void> setClinicAddress(String v) async {
    await _box.put(_clinicAddressKey, v);
    _notifier.value++;
  }

  static String getClinicPhone() =>
      _box.get(_clinicPhoneKey, defaultValue: '');
  static Future<void> setClinicPhone(String v) async {
    await _box.put(_clinicPhoneKey, v);
    _notifier.value++;
  }

  static String getClinicEmail() =>
      _box.get(_clinicEmailKey, defaultValue: '');
  static Future<void> setClinicEmail(String v) async {
    await _box.put(_clinicEmailKey, v);
    _notifier.value++;
  }

  static String getClinicWebsite() =>
      _box.get(_clinicWebsiteKey, defaultValue: '');
  static Future<void> setClinicWebsite(String v) async {
    await _box.put(_clinicWebsiteKey, v);
    _notifier.value++;
  }

  /// Absolute path to the user-uploaded logo PNG (under app support dir).
  /// Empty string means "no logo configured".
  static String getClinicLogoPath() =>
      _box.get(_clinicLogoPathKey, defaultValue: '');
  static Future<void> setClinicLogoPath(String v) async {
    await _box.put(_clinicLogoPathKey, v);
    _notifier.value++;
  }

  static String getPdfWatermarkText() => _box.get(_watermarkTextKey,
      defaultValue: 'Powered by PathLab Pro');
  static Future<void> setPdfWatermarkText(String v) async {
    await _box.put(_watermarkTextKey, v);
    _notifier.value++;
  }

  static bool getPrintLinearBarcode() =>
      _box.get(_printLinearBarcodeKey, defaultValue: false);
  static Future<void> setPrintLinearBarcode(bool v) async {
    await _box.put(_printLinearBarcodeKey, v);
    _notifier.value++;
  }

  // ─── Dual sign-out ───────────────────────────────────────────────────

  static bool getDualSignatureEnabled() =>
      _box.get(_dualSignatureEnabledKey, defaultValue: false);
  static Future<void> setDualSignatureEnabled(bool v) async {
    await _box.put(_dualSignatureEnabledKey, v);
    _notifier.value++;
  }

  static String getPathologist2Name() =>
      _box.get(_pathologist2NameKey, defaultValue: '');
  static Future<void> setPathologist2Name(String v) async {
    await _box.put(_pathologist2NameKey, v);
    _notifier.value++;
  }

  static String getPathologist2Registration() =>
      _box.get(_pathologist2RegKey, defaultValue: '');
  static Future<void> setPathologist2Registration(String v) async {
    await _box.put(_pathologist2RegKey, v);
    _notifier.value++;
  }

  static String getPathologist2Title() =>
      _box.get(_pathologist2TitleKey, defaultValue: '');
  static Future<void> setPathologist2Title(String v) async {
    await _box.put(_pathologist2TitleKey, v);
    _notifier.value++;
  }

  // Notifier so widgets watching settings rebuild on change.
  static final ValueNotifier<int> _notifier = ValueNotifier<int>(0);
  static ValueNotifier<int> get changes => _notifier;
}
