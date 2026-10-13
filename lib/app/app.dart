import 'package:flutter/material.dart';
import 'home_shell.dart';
import 'services.dart';
import 'theme.dart';

class AiTermApp extends StatelessWidget {
  const AiTermApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) => MaterialApp(
          title: 'aiterm',
          navigatorKey: services.navigation.navigatorKey,
          debugShowCheckedModeBanner: false,
          // MaterialApp animates between themes; AppColors interpolates, so
          // light/dark cross-fades.
          theme: buildTheme(dark: services.settings.dark),
          themeAnimationDuration: Motion.standard,
          themeAnimationCurve: Motion.move,
          home: const HomeShell(),
        ),
      ),
    );
  }
}
