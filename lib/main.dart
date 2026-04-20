import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'theme/app_theme.dart';
import 'screens/desktop_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
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
