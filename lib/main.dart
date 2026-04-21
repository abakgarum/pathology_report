import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/hive_storage_service.dart';
import 'services/settings_service.dart';
import 'services/voice_command_service.dart';
import 'theme/app_theme.dart';
import 'screens/desktop_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env optional in release — report generation will show a clear error if missing.
  }
  await HiveStorageService.init();
  await SettingsService.init();
  // Kick off voice initialization asynchronously; the shell will call
  // start() once the recognizer reports ready.
  unawaited(VoiceCommandService.instance.init());

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const PathologyReportApp());
}

class PathologyReportApp extends StatelessWidget {
  const PathologyReportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PathLab Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const DesktopShell(),
    );
  }
}
