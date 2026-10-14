import 'package:flutter/material.dart';

import '../app/navigation.dart';
import '../app/services.dart';
import 'terminal_deck.dart';

/// The Terminal tab: shells that aren't part of a project (a project's
/// agents and terminals live in its workspace). Setup happens before the
/// tabs appear (HomeShell), never here.
class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.linux, s.navigation]),
      builder: (context, _) => s.linux.installed || s.linux.usesAndroidShell
          ? TerminalDeck(
              showing: s.navigation.tab == AppTab.terminal && s.navigation.atTabs,
              onNew: () => s.tabs.open(),
            )
          : const SizedBox.shrink(),
    );
  }
}
