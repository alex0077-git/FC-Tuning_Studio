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
      builder: (context, child) {
        // G20 bezel is a compact landscape “mini PC” — keep chrome dense.
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).size.shortestSide < 600 ? 0.92 : 1.0,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const ShellScreen(),
    );
  }
}