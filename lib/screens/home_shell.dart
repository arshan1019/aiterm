import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../core/app_controller.dart';
import 'file_explorer_screen.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

class HomeShell extends StatelessWidget {
  final AppColors colors;
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  const HomeShell({super.key, required this.colors, required this.isDark, required this.onThemeChanged});

  static const _tabs = ['terminal', 'files', 'settings'];

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final app = AppController.instance;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: c.bg,
        systemNavigationBarColor: c.surface,
      ),
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(
            children: [
              _TabRow(colors: c, tabs: _tabs, selected: app.tab, onSelect: app.openTab),
              Expanded(
                child: IndexedStack(
                  index: app.tab,
                  children: [
                    TerminalScreen(colors: c),
                    FileExplorerScreen(colors: c),
                    SettingsScreen(colors: c, isDark: isDark, onThemeChanged: onThemeChanged),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  final AppColors colors;
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  const _TabRow({required this.colors, required this.tabs, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            InkWell(
              onTap: () => onSelect(i),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tabs[i],
                      style: TextStyle(
                        color: i == selected ? c.text : c.textMuted,
                        fontSize: 13,
                        fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 2,
                      width: i == selected ? 16 : 0,
                      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(1)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
