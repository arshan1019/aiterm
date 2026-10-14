import 'package:flutter/material.dart';

import '../agents/acp/acp_agents.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../platform/haptics.dart';
import '../backup/backup_controller.dart';
import '../git/git_actions.dart';
import '../git/github_auth.dart';
import '../git/github_button.dart';
import '../projects/projects_screen.dart';
import '../keep_alive/keep_alive_view.dart';
import '../keep_alive/keep_alive_controller.dart';
import '../linux/linux_environment.dart';
import '../shared/name_dialog.dart';
import '../shared/form.dart';
import '../shared/group.dart';
import 'settings.dart';
import '../ssh/ssh_keys.dart';

import 'package:flutter/services.dart';
import '../app/icons.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.linux, s.systemAccent, s.agents]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Appearance',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeChoice>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ThemeChoice.system, label: Text('System')),
                      ButtonSegment(value: ThemeChoice.light, label: Text('Light')),
                      ButtonSegment(value: ThemeChoice.dark, label: Text('Dark')),
                    ],
                    selected: {s.settings.theme},
                    onSelectionChanged: (v) {
                      Haptics.tick();
                      s.settings.theme = v.first;
                    },
                  ),
                ),
              ),
              // Android 12+ only: older phones have no wallpaper colors.
              if (s.systemAccent.value != null)
                _Switch('Wallpaper colors', s.settings.wallpaperColors, (v) => s.settings.wallpaperColors = v),
              _Switch('High contrast', s.settings.highContrast, (v) => s.settings.highContrast = v),
              _Switch('Compact lists', s.settings.compact, (v) => s.settings.compact = v),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Terminal',
            children: [
              ListTile(
                title: const Text('Text size', style: TextStyle(fontSize: 14)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Smaller text',
                      icon: Icon(AppIcons.remove, size: 18, color: c.textMuted),
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
                      tooltip: 'Larger text',
                      icon: Icon(AppIcons.add, size: 18, color: c.textMuted),
                      onPressed: () => s.settings.stepFontSize(1),
                    ),
                  ],
                ),
              ),
              if (s.settings.theme != ThemeChoice.dark)
                _Switch('Always dark', s.settings.darkTerminal, (v) => s.settings.darkTerminal = v),
              _Switch('Black background', s.settings.blackTerminal, (v) => s.settings.blackTerminal = v),
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
                  LinuxStatus.ready => 'Alpine Linux',
                  LinuxStatus.installing => 'Installing…',
                  LinuxStatus.missing => 'Not installed yet. Set it up from Projects.',
                }, style: TextStyle(color: c.textMuted, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Agent settings',
            children: [
              ListTile(
                title: const Text('AI agents', style: TextStyle(fontSize: 14)),
                trailing: Icon(AppIcons.chevronRight, color: c.textMuted),
                onTap: () => openAgents(context),
              ),
              // Off: each agent's own UI in a terminal, as it ships.
              _Switch('Blocks', s.settings.blocks, (v) => s.settings.blocks = v),
              if (s.settings.blocks) ...[
                for (final a in s.agents.installed)
                  if (AcpAgent.of(a.id) != null)
                    _Switch(a.name, s.settings.blocksFor(a.id), (v) => s.settings.setBlocksFor(a.id, v)),
                _Switch('Show thinking', s.settings.showThinking, (v) => s.settings.showThinking = v),
              ],
            ],
          ),
          if (s.linux.installed && !s.linux.usesAndroidShell) ...[
            const SizedBox(height: 20),
            const _GitHubSection(),
          ],
          const SizedBox(height: 20),
          _KeepAliveSection(controller: s.keepAlive),
          const SizedBox(height: 20),
          _SshSection(keys: s.ssh, github: s.github),
          const SizedBox(height: 20),
          _BackupSection(backup: s.backup, linuxInstalled: s.linux.installed),
          const SizedBox(height: 20),
          _Section(
            title: 'About',
            children: [
              ListTile(
                title: const Text('aiterm', style: TextStyle(fontSize: 14)),
                subtitle: Text('Version 1.0.0', style: TextStyle(color: c.textMuted, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An on/off setting, with the toggle's haptic.
class _Switch extends StatelessWidget {
  const _Switch(this.title, this.value, this.onChanged);

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        value: value,
        onChanged: (v) {
          Haptics.toggle(v);
          onChanged(v);
        },
      );
}

/// A settings group (the shared [Group]).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Group(title: title, children: children);
}

class _KeepAliveSection extends StatelessWidget {
  const _KeepAliveSection({required this.controller});

  final KeepAliveController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _Section(title: 'Keep sessions alive', children: [
          if (controller.steps.isEmpty)
            ListTile(
              title: const Text('Checking…', style: TextStyle(fontSize: 14)),
              subtitle: Text('Battery, notifications and Android\'s process limit',
                  style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
            )
          else
            KeepAliveSteps(controller: controller),
        ]),
      );
}

/// GitHub account: sign in once; git (HTTPS) and the clone picker use it.
class _GitHubSection extends StatelessWidget {
  const _GitHubSection();

  Future<void> _identity(BuildContext context) => askCommitIdentity(context);

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final c = context.colors;
    return ListenableBuilder(
      listenable: s.github,
      builder: (context, _) {
        final user = s.github.user;
        return _Section(
          title: 'GitHub',
          children: [
            if (user == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: GitHubButton(label: 'Sign in with GitHub', onPressed: () => signInToGitHub(context)),
              )
            else ...[
              ListTile(
                title: Text(user.name ?? user.login, style: const TextStyle(fontSize: 14)),
                subtitle: Text('Signed in as ${user.login}', style: TextStyle(color: c.textMuted, fontSize: 12)),
                trailing: TextButton(onPressed: s.github.signOut, child: const Text('Sign out')),
              ),
            ],
            ListTile(
              title: const Text('Commit name & email', style: TextStyle(fontSize: 14)),
              trailing: Icon(AppIcons.chevronRight, color: c.textMuted),
              onTap: () => _identity(context),
            ),
          ],
        );
      },
    );
  }
}

class _SshSection extends StatelessWidget {
  const _SshSection({required this.keys, required this.github});

  final SshKeys keys;
  final GitHubAuth github;

  Future<void> _addToGitHub(BuildContext context, SshKey key) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await github.addSshKey(key.publicKey, 'aiterm: ${key.name}');
    messenger.showSnackBar(SnackBar(
      content: Text(r.ok
          ? 'Added “${key.name}” to GitHub'
          : (r.stderr.contains('already') ? 'GitHub already has this key' : 'Couldn\'t add the key: ${r.stderr.trim()}')),
    ));
  }

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
    final ok = await confirmAction(context,
        title: 'Delete “${key.name}”?',
        message: 'Servers that trust this key will stop accepting it. This can\'t be undone.',
        action: 'Delete',
        danger: true);
    if (ok) await keys.delete(key.name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([keys, github]),
      builder: (context, _) => _Section(
        title: 'SSH keys',
        children: [
          for (final key in keys.keys)
            ListTile(
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
                  if (github.user != null)
                    IconButton(
                      tooltip: 'Add to GitHub',
                      icon: const Icon(AppIcons.cloudUpload, size: 18),
                      onPressed: () => _addToGitHub(context, key),
                    ),
                  IconButton(
                    tooltip: 'Copy public key',
                    icon: const Icon(AppIcons.copy, size: 18),
                    onPressed: () => _copy(context, key),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(AppIcons.delete, size: 18, color: c.danger),
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
              padding: const EdgeInsets.all(4),
              child: TextButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(AppIcons.add, size: 18),
                label: const Text('New key'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection({required this.backup, required this.linuxInstalled});

  final BackupController backup;
  final bool linuxInstalled;

  Future<void> _restore(BuildContext context) async {
    final ok = await confirmAction(context,
        title: 'Restore a backup?',
        message: 'This replaces Linux, your files in it, and aiterm\'s settings and tabs. '
            'Running sessions end and the app restarts.',
        action: 'Choose backup');
    if (ok == true) await backup.restore();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: backup,
      builder: (context, _) => _Section(
        title: 'Backup',
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            // Side by side; one under the other when large text needs it.
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: backup.busy || !linuxInstalled ? null : backup.backup,
                  icon: const Icon(AppIcons.save, size: 18),
                  label: const Text('Back up'),
                ),
                TextButton.icon(
                  onPressed: backup.busy ? null : () => _restore(context),
                  icon: const Icon(AppIcons.restore, size: 18),
                  label: const Text('Restore'),
                ),
                if (backup.busy) ...[
                  const SizedBox(width: 8),
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
          ),
          AnimatedSize(
            duration: Motion.standard,
            alignment: Alignment.topCenter,
            child: backup.message == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(backup.message!, style: TextStyle(color: c.text, fontSize: 12)),
                  ),
          ),
        ],
      ),
    );
  }
}
