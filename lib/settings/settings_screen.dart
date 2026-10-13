import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../backup/backup_controller.dart';
import '../git/git_actions.dart';
import '../git/github_auth.dart';
import '../projects/projects_screen.dart';
import '../keep_alive/keep_alive_view.dart';
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
                  LinuxStatus.missing => 'Not installed yet. Set it up from Projects.',
                }, style: TextStyle(color: c.textMuted, fontSize: 12)),
              ),
              if (s.linux.status == LinuxStatus.missing && !s.linux.usesAndroidShell)
                ListTile(
                  title: const Text("Use Android's shell", style: TextStyle(fontSize: 14)),
                  subtitle: Text('A plain terminal without Linux. Agents and git need Linux.',
                      style: TextStyle(color: c.textMuted, fontSize: 12)),
                  trailing: TextButton(onPressed: s.linux.useAndroidShell, child: const Text('Use')),
                ),
              ListTile(
                title: const Text('AI agents', style: TextStyle(fontSize: 14)),
                subtitle: Text('Install or open Claude Code, Gemini CLI, Codex CLI',
                    style: TextStyle(color: c.textMuted, fontSize: 12)),
                trailing: Icon(Icons.chevron_right_rounded, color: c.textMuted),
                onTap: () => openAgents(context),
              ),
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
                subtitle: Text(
                  'AI coding agents on your phone: projects, git, terminal and files.',
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
  Widget build(BuildContext context) =>
      _Section(title: 'Keep sessions alive', children: [KeepAliveSteps(controller: controller)]);
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
              ListTile(
                leading: Icon(Icons.login_rounded, color: c.accent, size: 20),
                title: const Text('Sign in to GitHub', style: TextStyle(fontSize: 14)),
                subtitle: Text('Clone, push and pull without passwords', style: TextStyle(color: c.textMuted, fontSize: 12)),
                onTap: () => signInToGitHub(context),
              )
            else ...[
              ListTile(
                leading: Icon(Icons.account_circle_outlined, color: c.accent, size: 20),
                title: Text(user.name ?? user.login, style: const TextStyle(fontSize: 14)),
                subtitle: Text('Signed in as ${user.login}', style: TextStyle(color: c.textMuted, fontSize: 12)),
                trailing: TextButton(onPressed: s.github.signOut, child: const Text('Sign out')),
              ),
            ],
            ListTile(
              leading: Icon(Icons.badge_outlined, color: c.textMuted, size: 20),
              title: const Text('Commit name & email', style: TextStyle(fontSize: 14)),
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
      listenable: Listenable.merge([keys, github]),
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
                  if (github.user != null)
                    IconButton(
                      tooltip: 'Add to GitHub',
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      onPressed: () => _addToGitHub(context, key),
                    ),
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

class _BackupSection extends StatelessWidget {
  const _BackupSection({required this.backup, required this.linuxInstalled});

  final BackupController backup;
  final bool linuxInstalled;

  Future<void> _restore(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restore a backup?', style: TextStyle(fontSize: 16)),
        content: const Text(
          'This replaces Linux, your files in it, and aiterm\'s settings and tabs. '
          'Running sessions end and the app restarts.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Choose backup')),
        ],
      ),
    );
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Everything in Linux (installed tools, your files) plus settings and tabs, '
              'in one file. Save it to your phone or Google Drive; restore it on any phone.',
              style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: backup.busy || !linuxInstalled ? null : backup.backup,
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  label: const Text('Back up'),
                ),
                TextButton.icon(
                  onPressed: backup.busy ? null : () => _restore(context),
                  icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
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
