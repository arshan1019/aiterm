import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../keep_alive/keep_alive.dart';
import '../keep_alive/keep_alive_controller.dart';
import '../linux/linux_environment.dart';
import '../shared/name_dialog.dart';
import '../ssh/ssh_keys.dart';

import 'package:flutter/services.dart';

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
          _Section(
            title: 'Appearance',
            children: [
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
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Environment',
            children: [
              ListTile(
                title: const Text('Linux', style: TextStyle(fontSize: 14)),
                subtitle: Text(switch (s.linux.status) {
                  _ when s.linux.usesAndroidShell => "Using Android's shell for this session.",
                  LinuxStatus.ready => 'Alpine Linux via proot. Install packages with apk.',
                  LinuxStatus.installing => 'Installing…',
                  LinuxStatus.missing => 'Not installed. Set it up from the Terminal tab.',
                }, style: TextStyle(color: c.textMuted, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _KeepAliveSection(controller: s.keepAlive),
          const SizedBox(height: 20),
          _SshSection(keys: s.ssh),
          const SizedBox(height: 20),
          _Section(
            title: 'About',
            children: [
              ListTile(
                title: const Text('aiterm', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  'A minimal terminal and file explorer for your phone.',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
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
    // A Material (not a colored box) so the tiles' ink shows on the card.
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
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

class _KeepAliveSection extends StatelessWidget {
  const _KeepAliveSection({required this.controller});

  final KeepAliveController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _Section(
        title: 'Keep sessions alive',
        children: [
          for (final step in controller.steps)
            ListTile(
              title: Text(step.title, style: const TextStyle(fontSize: 14)),
              subtitle: Text(step.detail, style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.35)),
              trailing: AnimatedSwitcher(
                duration: Motion.standard,
                child: step.done
                    ? Icon(Icons.check_circle_rounded, key: const ValueKey('done'), color: c.accent)
                    : TextButton(
                        key: const ValueKey('fix'),
                        onPressed: controller.fixing && step.kind == StepKind.childProcesses
                            ? null
                            : () => _fix(step.kind),
                        child: Text(step.kind == StepKind.childProcesses ? 'Fix' : 'Allow'),
                      ),
              ),
            ),
          AnimatedSize(
            duration: Motion.standard,
            curve: Motion.move,
            alignment: Alignment.topCenter,
            child: controller.message == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(controller.message!, style: TextStyle(color: c.text, fontSize: 12, height: 1.4)),
                        if (controller.fixing)
                          Row(
                            children: [
                              TextButton(
                                onPressed: controller.openDeveloperOptions,
                                child: const Text('Open Wireless debugging'),
                              ),
                              TextButton(
                                onPressed: controller.cancelFix,
                                child: Text('Cancel', style: TextStyle(color: c.textMuted)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _fix(StepKind kind) => switch (kind) {
    StepKind.battery => controller.requestBattery(),
    StepKind.notifications => controller.requestNotifications(),
    StepKind.childProcesses => controller.fixChildProcesses(),
  };
}

class _SshSection extends StatelessWidget {
  const _SshSection({required this.keys});

  final SshKeys keys;

  Future<void> _create(BuildContext context) async {
    final name = await showNameDialog(context, title: 'New SSH key', action: 'Create', hint: 'e.g. github');
    if (name == null) return;
    final key = await keys.create(name);
    if (key != null && context.mounted) _copy(context, key);
  }

  void _copy(BuildContext context, SshKey key) {
    Clipboard.setData(ClipboardData(text: key.publicKey));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Public key copied. Add it on GitHub under Settings → SSH keys.')));
  }

  Future<void> _delete(BuildContext context, SshKey key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete “${key.name}”?', style: const TextStyle(fontSize: 16)),
        content: const Text('Servers that trust this key will stop accepting it. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await keys.delete(key.name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: keys,
      builder: (context, _) => _Section(
        title: 'SSH keys',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Stored in Android\'s keystore and never leave it. ssh and git in Linux use them '
              'after your fingerprint or screen lock.',
              style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.4),
            ),
          ),
          for (final key in keys.keys)
            ListTile(
              leading: Icon(Icons.key_rounded, color: c.accent, size: 20),
              title: Text(key.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                key.publicKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textMuted, fontSize: 11),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Copy public key',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => _copy(context, key),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: c.danger),
                    onPressed: () => _delete(context, key),
                  ),
                ],
              ),
            ),
          if (keys.error case final e?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(e, style: TextStyle(color: c.danger, fontSize: 12)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New key'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
