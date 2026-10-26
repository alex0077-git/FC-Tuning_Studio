import 'package:flutter/material.dart';
import 'screens/shell_screen.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1D21),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2F7BFF),
          surface: Color(0xFF252A30),
        ),
      ),
      home: const ShellScreen(),
    );
  }
}