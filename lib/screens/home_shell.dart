import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'terminal_screen.dart';
import 'file_explorer_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  final AppColors colors;
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  const HomeShell({
    super.key,
    required this.colors,
    required this.isDark,
    required this.onThemeChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['aiterm', 'Files', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(
        index: _index,
        children: [
          TerminalScreen(colors: c),
          FileExplorerScreen(colors: c),
          SettingsScreen(
            colors: c,
            isDark: widget.isDark,
            onThemeChanged: widget.onThemeChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.terminal), label: 'Terminal'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
