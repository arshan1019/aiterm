import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const AiTermApp());
}

class AiTermApp extends StatefulWidget {
  const AiTermApp({super.key});

  @override
  State<AiTermApp> createState() => _AiTermAppState();
}

class _AiTermAppState extends State<AiTermApp> {
  bool _isDark = true;

  @override
  Widget build(BuildContext context) {
    final colors = _isDark ? AppColors.dark : AppColors.light;
    return MaterialApp(
      title: 'aiterm',
      debugShowCheckedModeBanner: false,
      theme: AiTermTheme.build(colors, _isDark ? Brightness.dark : Brightness.light),
      home: HomeShell(
        colors: colors,
        isDark: _isDark,
        onThemeChanged: (v) => setState(() => _isDark = v),
      ),
    );
  }
}
