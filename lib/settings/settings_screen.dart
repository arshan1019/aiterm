import 'package:flutter/material.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../linux/linux_environment.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.linux]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Appearance', children: [
            SwitchListTile(
              title: const Text('Dark theme', style: TextStyle(fontSize: 14)),
              value: s.settings.dark,
              onChanged: (v) => s.settings.dark = v,
            ),
            ListTile(
              title: const Text('Terminal text size', style: TextStyle(fontSize: 14)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.remove_rounded, size: 18, color: c.textMuted),
                    onPressed: () => s.settings.stepFontSize(-1),
                  ),
                  SizedBox(
                    width: 28,
                    child: AnimatedSwitcher(
                      duration: Motion.quick,
                      child: Text(
                        '${s.settings.fontSize.round()}',
                        key: ValueKey(s.settings.fontSize),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_rounded, size: 18, color: c.textMuted),
                    onPressed: () => s.settings.stepFontSize(1),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _Section(title: 'Environment', children: [
            ListTile(
              title: const Text('Linux', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                switch (s.linux.status) {
                  _ when s.linux.usesAndroidShell => "Using Android's shell for this session.",
                  LinuxStatus.ready => 'Alpine Linux via proot. Install packages with apk.',
                  LinuxStatus.installing => 'Installing…',
                  LinuxStatus.missing => 'Not installed. Set it up from the Terminal tab.',
                },
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _Section(title: 'About', children: [
            ListTile(
              title: const Text('aiterm', style: TextStyle(fontSize: 14)),
              subtitle: Text('A minimal terminal and file explorer for your phone.',
                  style: TextStyle(color: c.textMuted, fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(color: c.textMuted, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
