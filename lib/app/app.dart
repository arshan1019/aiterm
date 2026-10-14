import 'package:flutter/material.dart';
import '../projects/project_screen.dart';
import '../phone/share_receiver.dart';
import '../settings/settings.dart';
import '../platform/haptics.dart';
import 'home_shell.dart';
import 'services.dart';
import 'theme.dart';

class AiTermApp extends StatelessWidget {
  const AiTermApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    services.navigation.projectRoute ??= projectRoute;
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: Listenable.merge([services.settings, services.systemAccent]),
        builder: (context, _) => MaterialApp(
          title: 'aiterm',
          navigatorKey: services.navigation.navigatorKey,
          navigatorObservers: [services.navigation.observer],
          debugShowCheckedModeBanner: false,
          // MaterialApp animates between themes; AppColors interpolates, so
          // light/dark cross-fades.
          theme: services.theme(dark: false),
          darkTheme: services.theme(dark: true),
          themeMode: switch (services.settings.theme) {
            ThemeChoice.system => ThemeMode.system,
            ThemeChoice.light => ThemeMode.light,
            ThemeChoice.dark => ThemeMode.dark,
          },
          themeAnimationDuration: Motion.standard,
          themeAnimationCurve: Motion.move,
          home: const ShareReceiver(child: HomeShell()),
          // Follow the system's "Remove animations" setting.
          builder: (context, child) {
            Motion.reduced = MediaQuery.disableAnimationsOf(context);
            Haptics.enabled = services.settings.haptics;
            return child!;
          },
        ),
      ),
    );
  }
}
