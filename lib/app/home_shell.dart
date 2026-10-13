import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../files/files_screen.dart';
import '../projects/projects_screen.dart';
import '../settings/settings_screen.dart';
import '../shared/fade_indexed_stack.dart';
import '../shared/text_tabs.dart';
import '../terminal/terminal_screen.dart';
import 'navigation.dart';
import 'services.dart';
import 'theme.dart';

/// The top-level layout: a row of text tabs over the four screens. All
/// screens stay mounted, so terminals keep running and Files keeps its place.
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
          body: SafeArea(
            child: ListenableBuilder(
              listenable: nav,
              builder: (context, _) => Column(
                children: [
                  TextTabs<AppTab>(tabs: AppTab.values, label: (t) => t.name, selected: nav.tab, onSelect: nav.open),
                  Expanded(
                    child: FadeIndexedStack(index: nav.tab.index, rise: 6, children: _screens),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
