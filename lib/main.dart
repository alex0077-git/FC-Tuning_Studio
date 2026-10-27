import 'package:flutter/material.dart';
import 'screens/shell_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const FcTuningStudioApp());
}

class FcTuningStudioApp extends StatelessWidget {
  const FcTuningStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FC Tuning Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ShellScreen(),
    );
  }
}