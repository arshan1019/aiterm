import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'core/app_controller.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const AiTermApp());
}

class AiTermApp extends StatelessWidget {
  const AiTermApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppController.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final colors = app.isDark ? AppColors.dark : AppColors.light;
        return MaterialApp(
          title: 'aiterm',
          debugShowCheckedModeBanner: false,
          theme: AiTermTheme.build(colors, app.isDark ? Brightness.dark : Brightness.light),
          home: HomeShell(colors: colors, isDark: app.isDark, onThemeChanged: app.setDark),
        );
      },
    );
  }
}
