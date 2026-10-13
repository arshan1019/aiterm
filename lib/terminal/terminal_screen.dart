import 'package:flutter/material.dart';

import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../onboarding/setup_view.dart';
import 'terminal_deck.dart';

/// The Terminal tab: shells that aren't part of a project (a project's
/// agents and terminals live in its workspace). First-run setup until
/// Linux is ready.
class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.linux, s.navigation]),
      builder: (context, _) => AnimatedSwitcher(
        duration: Motion.standard,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        child: s.linux.installed || s.linux.usesAndroidShell
            ? TerminalDeck(
                key: const ValueKey('deck'),
                showing: s.navigation.tab == AppTab.terminal && s.navigation.atTabs,
                onNew: () => s.tabs.open(),
              )
            : const SetupView(key: ValueKey('setup')),
      ),
    );
  }
}
