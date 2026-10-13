import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/distro_manager.dart';

class SettingsScreen extends StatelessWidget {
  final AppColors colors;
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.colors,
    required this.isDark,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(colors: c, title: 'Appearance', children: [
          SwitchListTile(
            activeThumbColor: c.accent,
            title: Text('Dark theme', style: TextStyle(color: c.text)),
            value: isDark,
            onChanged: onThemeChanged,
          ),
        ]),
        const SizedBox(height: 24),
        _Section(colors: c, title: 'Environment', children: [
          ListenableBuilder(
            listenable: DistroManager.instance,
            builder: (context, _) => ListTile(
              title: Text('Linux distro', style: TextStyle(color: c.text)),
              subtitle: Text(
                DistroManager.instance.installed
                    ? 'Alpine Linux via proot. Install packages with apk.'
                    : 'Not installed. Set it up from the Terminal tab.',
                style: TextStyle(color: c.textMuted),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        _Section(colors: c, title: 'About', children: [
          ListTile(
            title: Text('aiterm', style: TextStyle(color: c.text)),
            subtitle: Text('A minimal terminal + file explorer for your phone.',
                style: TextStyle(color: c.textMuted)),
          ),
        ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final AppColors colors;
  final String title;
  final List<Widget> children;

  const _Section({required this.colors, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: c.textMuted,
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
