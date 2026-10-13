import 'dart:io';

import 'package:flutter/material.dart';

import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../agents/agent_installer.dart';
import '../platform/android_env.dart';
import '../shared/name_dialog.dart';
import 'file_clipboard.dart';
import 'file_system_service.dart';
import 'files_browser.dart';
import 'text_editor_screen.dart';

/// The Files tab: browse the shell's home folder, open text files, and
/// create, rename or delete entries.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late final _services = context.services;
  static const _phoneRoot = '/storage/emulated/0';
  late final FilesBrowser _browser = FilesBrowser(
    root: _services.linux.home,
    rootfs: _services.linux.rootfs,
    locations: [FilesLocation.linux(_services.linux.home), const FilesLocation.phone(_phoneRoot)],
  );
  final _clipboard = FileClipboard();
  bool _phoneAccess = false;
  late final _lifecycle = AppLifecycleListener(onResume: _checkPhoneAccess);

  @override
  void initState() {
    super.initState();
    _browser.load();
    _lifecycle; // re-check phone access when back from system settings
    _checkPhoneAccess();
    _services.linux.addListener(_onLinuxChanged);
    _services.navigation.addListener(_openPending);
    _services.navigation.setBackHandler(AppTab.files, _browser.handleBack);
  }

  @override
  void dispose() {
    _services.linux.removeListener(_onLinuxChanged);
    _services.navigation.removeListener(_openPending);
    _services.navigation.setBackHandler(AppTab.files, null);
    _browser.dispose();
    _clipboard.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _checkPhoneAccess() async {
    bool access;
    try {
      access = await AndroidEnv.storageAccess();
    } catch (_) {
      access = false;
    }
    if (!mounted || access == _phoneAccess) return;
    setState(() => _phoneAccess = access);
    if (access && _browser.location.kind == LocationKind.phone) await _browser.refresh();
  }

  Future<void> _paste() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final done = await _clipboard.paste(_browser.current);
      await _browser.refresh();
      messenger.showSnackBar(
        SnackBar(content: Text(done.length == 1 ? 'Pasted 1 item' : 'Pasted ${done.length} items')),
      );
    } on FileSystemException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _onLinuxChanged() {
    final home = _services.linux.home;
    if (home != _browser.root) _browser.reset(home);
  }

  /// A folder the assistant asked to show ("show src in files").
  Future<void> _openPending() async {
    final nav = _services.navigation;
    final requested = nav.pendingFolder;
    if (requested == null) return;
    nav.pendingFolder = null;
    final target = _services.linux.hostPath(requested).replaceAll(RegExp(r'/+$'), '');
    if (await _browser.fs.isDirectory(target)) {
      await _browser.open(target);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No folder named $requested here')));
    }
  }

  void _open(FsEntry e) {
    if (e.kind == EntryKind.directory) {
      _browser.open(e.path);
    } else if (_browser.fs.looksLikeText(e.name)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TextEditorScreen(entry: e, fs: _browser.fs),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No viewer for this file type yet')));
    }
  }

  Future<String?> _askName(String title, String action, {String initial = ''}) =>
      showNameDialog(context, title: title, action: action, initial: initial, hint: 'name');

  Future<void> _create(bool folder) async {
    final name = await _askName(folder ? 'New folder' : 'New file', 'Create');
    if (name != null) await _browser.create(name, folder: folder);
  }

  /// A new terminal tab in [folder] (a host path; the current folder by
  /// default), shown right away.
  void _openTerminalHere([String? folder]) {
    final linux = _services.linux;
    _services.tabs.open(cwd: linux.guestPath(folder ?? _browser.current));
    _services.navigation.open(AppTab.terminal);
  }

  /// Opens [folder] (a host path; the current folder by default) in an
  /// installed AI agent's own tab.
  void _openInAgent(String id, [String? folder]) =>
      _services.agents.open(id, cwd: _services.linux.guestPath(folder ?? _browser.current));

  Future<bool> _confirmDelete(FsEntry e) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Delete “${e.name}”?', style: const TextStyle(fontSize: 16)),
          content: Text(
            e.kind == EntryKind.directory
                ? 'The folder and everything in it will be deleted. This can\'t be undone.'
                : 'This can\'t be undone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
          ],
        ),
      ) ??
      false;

  void _entryActions(FsEntry e) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        final c = sheet.colors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.kind == EntryKind.directory)
                ListTile(
                  leading: Icon(Icons.terminal_rounded, color: c.textMuted),
                  title: const Text('Open terminal here', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.pop(sheet);
                    _openTerminalHere(e.path);
                  },
                ),
              if (e.kind == EntryKind.directory)
                for (final agent in _services.agents.installed)
                  ListTile(
                    leading: Icon(Icons.auto_awesome_rounded, color: c.accent),
                    title: Text('Open in ${agent.name}', style: const TextStyle(fontSize: 14)),
                    onTap: () {
                      Navigator.pop(sheet);
                      _openInAgent(agent.id, e.path);
                    },
                  ),
              if (e.kind == EntryKind.directory) const Divider(height: 8),
              ListTile(
                leading: Icon(Icons.copy_rounded, color: c.textMuted),
                title: const Text('Copy', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(sheet);
                  _clipboard.copy([e]);
                },
              ),
              ListTile(
                leading: Icon(Icons.content_cut_rounded, color: c.textMuted),
                title: const Text('Move', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(sheet);
                  _clipboard.cut([e]);
                },
              ),
              ListTile(
                leading: Icon(Icons.drive_file_rename_outline_rounded, color: c.textMuted),
                title: const Text('Rename', style: TextStyle(fontSize: 14)),
                onTap: () async {
                  Navigator.pop(sheet);
                  final name = await _askName('Rename', 'Rename', initial: e.name);
                  if (name != null) await _browser.rename(e, name);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: c.danger),
                title: Text('Delete', style: TextStyle(color: c.danger, fontSize: 14)),
                onTap: () async {
                  Navigator.pop(sheet);
                  if (await _confirmDelete(e)) await _browser.delete(e);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: ListenableBuilder(
        listenable: _browser,
        builder: (context, _) => Column(
          children: [
            _LocationSwitcher(browser: _browser),
            _Header(
              browser: _browser,
              agents: _services.agents,
              onOpenTerminal: _openTerminalHere,
              onOpenAgent: _openInAgent,
            ),
            Expanded(
              child: _browser.location.kind == LocationKind.phone && !_phoneAccess
                  ? _PhoneAccessPrompt(onAllow: AndroidEnv.requestStorageAccess)
                  : !_browser.loaded
                  ? const SizedBox.expand()
                  : AnimatedSwitcher(
                      duration: Motion.standard,
                      switchInCurve: Motion.enter,
                      switchOutCurve: Motion.exit,
                      transitionBuilder: (child, animation) {
                        // Into a folder: the new listing comes from the right
                        // and the old one leaves left; back/up mirrors that.
                        final incoming = child.key == ValueKey(_browser.current);
                        final side = (_browser.movedDeeper ? 1 : -1) * (incoming ? 1 : -1);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(begin: Offset(0.06 * side, 0), end: Offset.zero).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _Listing(
                        key: ValueKey(_browser.current),
                        browser: _browser,
                        onOpen: _open,
                        onActions: _entryActions,
                      ),
                    ),
            ),
            _PasteBar(clipboard: _clipboard, onPaste: _paste),
          ],
        ),
      ),
      floatingActionButton: PopupMenuButton<bool>(
        onSelected: _create,
        offset: const Offset(0, -110),
        itemBuilder: (context) => const [
          PopupMenuItem(value: false, child: Text('New file')),
          PopupMenuItem(value: true, child: Text('New folder')),
        ],
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(16)),
          child: Icon(Icons.add_rounded, color: c.bg),
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({required this.browser, required this.agents, required this.onOpenTerminal, required this.onOpenAgent});

  final FilesBrowser browser;
  final VoidCallback onOpenTerminal;
  final void Function(String agentId) onOpenAgent;
  final AgentInstaller agents;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final _crumbScroll = ScrollController();

  @override
  void dispose() {
    _crumbScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_Header old) {
    super.didUpdateWidget(old);
    // Keep the current folder (the last crumb) in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_crumbScroll.hasClients) {
        _crumbScroll.animateTo(_crumbScroll.position.maxScrollExtent, duration: Motion.standard, curve: Motion.move);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = widget.browser;
    final crumbs = b.crumbs;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _NavButton(icon: Icons.arrow_back_rounded, onTap: b.canGoBack ? b.back : null),
          _NavButton(icon: Icons.arrow_forward_rounded, onTap: b.canGoForward ? b.forward : null),
          _NavButton(icon: Icons.arrow_upward_rounded, onTap: b.canGoUp ? b.up : null),
          const SizedBox(width: 4),
          Expanded(
            child: ListView.builder(
              controller: _crumbScroll,
              scrollDirection: Axis.horizontal,
              itemCount: crumbs.length,
              itemBuilder: (context, i) {
                final last = i == crumbs.length - 1;
                return Row(
                  children: [
                    if (i > 0) Icon(Icons.chevron_right_rounded, size: 14, color: c.border),
                    InkWell(
                      onTap: last ? null : () => b.open(crumbs[i].path),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                        child: Text(
                          crumbs[i].label,
                          style: TextStyle(
                            color: last ? c.text : c.textMuted,
                            fontSize: 13,
                            fontWeight: last ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Folder actions',
            icon: Icon(Icons.more_vert_rounded, color: c.textMuted, size: 20),
            onSelected: (v) => switch (v) {
              'terminal' => widget.onOpenTerminal(),
              final v when v.startsWith('agent:') => widget.onOpenAgent(v.substring(6)),
              'home' => b.open(b.root),
              'hidden' => b.toggleHidden(),
              _ => b.refresh(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'terminal', child: Text('Open terminal here')),
              for (final agent in widget.agents.installed)
                PopupMenuItem(value: 'agent:${agent.id}', child: Text('Open in ${agent.name}')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'home', child: Text('Go home')),
              CheckedPopupMenuItem(value: 'hidden', checked: b.showHidden, child: const Text('Show hidden')),
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 38,
      child: IconButton(
        iconSize: 19,
        onPressed: onTap,
        icon: AnimatedOpacity(
          duration: Motion.quick,
          opacity: onTap == null ? 0.35 : 1,
          child: Icon(icon, color: c.text),
        ),
      ),
    );
  }
}

/// One folder's entries. Each folder gets its own list (and scroll
/// position), so the old and new listings can animate side by side.
class _Listing extends StatefulWidget {
  const _Listing({super.key, required this.browser, required this.onOpen, required this.onActions});

  final FilesBrowser browser;
  final ValueChanged<FsEntry> onOpen;
  final ValueChanged<FsEntry> onActions;

  @override
  State<_Listing> createState() => _ListingState();
}

class _ListingState extends State<_Listing> {
  late final String _path = widget.browser.current;
  late final _scroll = ScrollController(initialScrollOffset: widget.browser.offsets[_path] ?? 0);

  @override
  void dispose() {
    if (_scroll.hasClients) widget.browser.offsets[_path] = _scroll.offset;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = widget.browser.entries;
    return RefreshIndicator(
      onRefresh: widget.browser.refresh,
      color: c.accent,
      backgroundColor: c.surface,
      child: entries.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 140),
                Center(
                  child: Text('Empty folder', style: TextStyle(color: c.textMuted)),
                ),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              itemCount: entries.length,
              itemExtent: 52,
              itemBuilder: (context, i) {
                final e = entries[i];
                final dir = e.kind == EntryKind.directory;
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    dir ? Icons.folder_rounded : Icons.description_outlined,
                    color: dir ? c.accent : c.textMuted,
                  ),
                  title: Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: dir ? null : Text(_size(e.size), style: TextStyle(color: c.textMuted, fontSize: 11)),
                  // Actions are always a visible tap away; long-press is
                  // only a shortcut to the same menu.
                  trailing: IconButton(
                    tooltip: 'Actions',
                    icon: Icon(Icons.more_vert_rounded, size: 18, color: c.textMuted),
                    onPressed: () => widget.onActions(e),
                  ),
                  onTap: () => widget.onOpen(e),
                  onLongPress: () => widget.onActions(e),
                );
              },
            ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Linux | Phone: which storage Files shows.
class _LocationSwitcher extends StatelessWidget {
  const _LocationSwitcher({required this.browser});

  final FilesBrowser browser;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<LocationKind>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(
              value: LocationKind.linux,
              icon: Icon(Icons.terminal_rounded, size: 16),
              label: Text('Linux'),
            ),
            ButtonSegment(
              value: LocationKind.phone,
              icon: Icon(Icons.smartphone_rounded, size: 16),
              label: Text('Phone'),
            ),
          ],
          selected: {browser.location.kind},
          onSelectionChanged: (s) => browser.switchTo(s.first),
        ),
      ),
    );
  }
}

class _PhoneAccessPrompt extends StatelessWidget {
  const _PhoneAccessPrompt({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_shared_rounded, size: 40, color: c.accent),
            const SizedBox(height: 12),
            Text(
              'Phone storage',
              style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Allow access to move files between Linux and your phone: '
              'downloads, photos, project assets. Linux also sees it at /sdcard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAllow, child: const Text('Allow access')),
          ],
        ),
      ),
    );
  }
}

/// Shown while something is copied or cut; stays across folders and
/// locations so it can be pasted anywhere.
class _PasteBar extends StatelessWidget {
  const _PasteBar({required this.clipboard, required this.onPaste});

  final FileClipboard clipboard;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: clipboard,
      builder: (context, _) => AnimatedSize(
        duration: Motion.standard,
        curve: Motion.move,
        child: !clipboard.hasItems
            ? const SizedBox(width: double.infinity)
            : Material(
                color: c.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    child: Row(
                      children: [
                        Icon(
                          clipboard.mode == ClipMode.cut ? Icons.content_cut_rounded : Icons.copy_rounded,
                          size: 16,
                          color: c.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${clipboard.mode == ClipMode.cut ? 'Move' : 'Copy'} '
                            '${clipboard.items.length == 1 ? clipboard.items.first.name : '${clipboard.items.length} items'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.text, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: clipboard.clear,
                          child: Text('Cancel', style: TextStyle(color: c.textMuted)),
                        ),
                        FilledButton(onPressed: onPaste, child: const Text('Paste here')),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
