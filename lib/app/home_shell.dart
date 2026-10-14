import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../files/files_screen.dart';
import '../projects/projects_screen.dart';
import '../settings/settings_screen.dart';
import '../shared/fade_indexed_stack.dart';
import '../shared/bottom_tabs.dart';
import '../terminal/terminal_screen.dart';
import 'navigation.dart';
import 'services.dart';
import 'theme.dart';

/// The top-level layout: the four screens, with their tabs at the bottom.
/// All screens stay mounted, so terminals keep running and Files keeps its
/// place.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _screens = [ProjectsScreen(), TerminalScreen(), FilesScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nav = context.services.navigation;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: c.surface,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !nav.handleBack()) SystemNavigator.pop();
        },
        child: Scaffold(
          bottomNavigationBar: ListenableBuilder(
            listenable: nav,
            builder: (context, _) => BottomTabs(
              tabs: const [
                BottomTab('Projects', Icons.folder_special_outlined, Icons.folder_special_rounded),
                BottomTab('Terminal', Icons.terminal_outlined, Icons.terminal_rounded),
                BottomTab('Files', Icons.folder_outlined, Icons.folder_rounded),
                BottomTab('Settings', Icons.settings_outlined, Icons.settings_rounded),
              ],
              selected: nav.tab.index,
              onSelect: (i) => nav.open(AppTab.values[i]),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: ListenableBuilder(
              listenable: nav,
              builder: (context, _) => FadeIndexedStack(index: nav.tab.index, rise: 6, children: _screens),
            ),
          ),
        ),
      ),
    );
  }
}
