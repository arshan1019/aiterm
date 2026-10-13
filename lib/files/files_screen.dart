import 'package:flutter/material.dart';

import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../shared/name_dialog.dart';
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
  late final FilesBrowser _browser = FilesBrowser(root: _services.linux.home, rootfs: _services.linux.rootfs);

  @override
  void initState() {
    super.initState();
    _browser.load();
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
    super.dispose();
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

  Future<void> _backgroundMenu(Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'terminal', child: Text('Open terminal here')),
        PopupMenuItem(value: 'file', child: Text('New file')),
        PopupMenuItem(value: 'folder', child: Text('New folder')),
      ],
    );
    switch (choice) {
      case 'terminal':
        _openTerminalHere();
      case 'file':
        await _create(false);
      case 'folder':
        await _create(true);
    }
  }

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
                onTap: () {
                  Navigator.pop(sheet);
                  _browser.delete(e);
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
            _Header(browser: _browser, onOpenTerminal: _openTerminalHere),
            Expanded(
              child: !_browser.loaded
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
                        onBackgroundMenu: _backgroundMenu,
                      ),
                    ),
            ),
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
  const _Header({required this.browser, required this.onOpenTerminal});

  final FilesBrowser browser;
  final VoidCallback onOpenTerminal;

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
            icon: Icon(Icons.more_vert_rounded, color: c.textMuted, size: 20),
            onSelected: (v) => switch (v) {
              'terminal' => widget.onOpenTerminal(),
              'home' => b.open(b.root),
              'hidden' => b.toggleHidden(),
              _ => b.refresh(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'terminal', child: Text('Open terminal here')),
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
  const _Listing({
    super.key,
    required this.browser,
    required this.onOpen,
    required this.onActions,
    required this.onBackgroundMenu,
  });

  final FilesBrowser browser;
  final ValueChanged<FsEntry> onOpen;
  final ValueChanged<FsEntry> onActions;

  /// Long-press on empty space, at this global position.
  final ValueChanged<Offset> onBackgroundMenu;

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
    // Entries take their own long-press; one on empty space reaches here.
    return GestureDetector(
      onLongPressStart: (d) => widget.onBackgroundMenu(d.globalPosition),
      child: RefreshIndicator(
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
                    trailing: dir ? Icon(Icons.chevron_right_rounded, size: 18, color: c.border) : null,
                    onTap: () => widget.onOpen(e),
                    onLongPress: () => widget.onActions(e),
                  );
                },
              ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
