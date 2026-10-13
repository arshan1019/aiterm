import 'dart:io';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/distro_manager.dart';
import '../core/file_system_service.dart';
import '../core/app_controller.dart';
import '../core/shell_env.dart';

class FileExplorerScreen extends StatefulWidget {
  final AppColors colors;
  const FileExplorerScreen({super.key, required this.colors});

  @override
  State<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

class _FileExplorerScreenState extends State<FileExplorerScreen> {
  final _fs = FileSystemService();
  String? _root;
  String _current = '';
  List<FsEntry> _entries = [];
  bool _loading = true;
  bool _showHidden = false;

  // Browser-style history: back pops onto forward and vice versa.
  final _back = <String>[];
  final _forward = <String>[];
  final _scroll = ScrollController();
  final _crumbScroll = ScrollController();
  final _offsets = <String, double>{};

  final _distro = DistroManager.instance;
  final _app = AppController.instance;

  @override
  void initState() {
    super.initState();
    _distro.addListener(_init);
    _app.addListener(_openPending);
    _app.filesBack = _handleSystemBack;
    _init();
  }

  @override
  void dispose() {
    _distro.removeListener(_init);
    _app.removeListener(_openPending);
    if (_app.filesBack == _handleSystemBack) _app.filesBack = null;
    _scroll.dispose();
    _crumbScroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _distro.init();
    final home = _distro.installed ? _distro.home : await ShellEnv.androidHome();
    if (!mounted || home == _root) return;
    _root = home;
    _back.clear();
    _forward.clear();
    _offsets.clear();
    await _show(home);
  }

  /// Opens a folder the assistant asked for ("show src in files"). Paths are
  /// relative to the home folder; absolute guest paths map into the rootfs.
  Future<void> _openPending() async {
    final requested = _app.pendingFilesPath;
    final root = _root;
    if (requested == null || root == null) return;
    _app.pendingFilesPath = null;
    String target;
    if (requested == '~' || requested.isEmpty) {
      target = root;
    } else if (requested.startsWith('/') && _distro.installed) {
      target = '${_distro.rootfs}$requested';
    } else {
      target = '$root/${requested.replaceFirst(RegExp(r'^~/'), '')}';
    }
    target = target.replaceAll(RegExp(r'/+$'), '');
    if (!await Directory(target).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No folder named $requested here')));
      }
      return;
    }
    await _goTo(target);
  }

  /// Loads [path] before switching to it, so the old listing stays on screen
  /// until the new one is ready (no spinner flash between folders).
  Future<void> _show(String path) async {
    if (_entries.isEmpty) setState(() => _loading = true);
    final entries = await _fs.list(path);
    if (!mounted) return;
    setState(() {
      _current = path;
      _entries = entries;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo((_offsets[path] ?? 0).clamp(0, _scroll.position.maxScrollExtent));
      }
      if (_crumbScroll.hasClients) {
        _crumbScroll.jumpTo(_crumbScroll.position.maxScrollExtent);
      }
    });
  }

  void _rememberOffset() {
    if (_scroll.hasClients) _offsets[_current] = _scroll.offset;
  }

  Future<void> _goTo(String path) async {
    if (path == _current) return;
    _rememberOffset();
    _back.add(_current);
    _forward.clear();
    await _show(path);
  }

  Future<void> _goBack() async {
    if (_back.isEmpty) return;
    _rememberOffset();
    _forward.add(_current);
    await _show(_back.removeLast());
  }

  Future<void> _goForward() async {
    if (_forward.isEmpty) return;
    _rememberOffset();
    _back.add(_current);
    await _show(_forward.removeLast());
  }

  String? get _parent {
    final base = _crumbs.first.path;
    if (_current == base) return null;
    return Directory(_current).parent.path;
  }

  Future<void> _goUp() async {
    final p = _parent;
    if (p != null) await _goTo(p);
  }

  /// Android back: history first, then the parent folder.
  bool _handleSystemBack() {
    if (_back.isNotEmpty) {
      _goBack();
      return true;
    }
    if (_parent != null) {
      _goUp();
      return true;
    }
    return false;
  }

  Future<void> _refresh() => _show(_current);

  void _open(FsEntry e) {
    if (e.kind == EntryKind.directory) {
      _goTo(e.path);
    } else if (_fs.looksLikeText(e.name)) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _TextViewerScreen(colors: widget.colors, entry: e, fs: _fs),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No viewer for this file type yet')),
      );
    }
  }

  /// Home-relative crumbs ("~ › src › lib"); folders outside home (opened via
  /// an absolute path) are shown from the distro root ("/ › etc").
  List<({String label, String path})> get _crumbs {
    final root = _root!;
    String base, label;
    if (_current == root || _current.startsWith('$root/')) {
      base = root;
      label = '~';
    } else if (_distro.installed && _current.startsWith(_distro.rootfs)) {
      base = _distro.rootfs;
      label = '/';
    } else {
      base = '/';
      label = '/';
    }
    final crumbs = [(label: label, path: base)];
    var path = base == '/' ? '' : base;
    for (final part in _current.substring(base.length).split('/')) {
      if (part.isEmpty) continue;
      path = '$path/$part';
      crumbs.add((label: part, path: path));
    }
    return crumbs;
  }

  List<FsEntry> get _visible =>
      _showHidden ? _entries : _entries.where((e) => !e.name.startsWith('.')).toList();

  Future<void> _newEntry(bool isFolder) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.colors.surface,
        title: Text(isFolder ? 'New folder' : 'New file',
            style: TextStyle(color: widget.colors.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: widget.colors.text),
          decoration: const InputDecoration(hintText: 'name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final path = '$_current/$name';
    if (isFolder) {
      await _fs.createFolder(path);
    } else {
      await _fs.createFile(path);
    }
    _refresh();
  }

  Future<void> _entryActions(FsEntry e) async {
    final c = widget.colors;
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline, color: c.textMuted),
              title: Text('Rename', style: TextStyle(color: c.text)),
              onTap: () async {
                Navigator.pop(ctx);
                final controller = TextEditingController(text: e.name);
                final newName = await showDialog<String>(
                  context: context,
                  builder: (ctx2) => AlertDialog(
                    backgroundColor: c.surface,
                    title: Text('Rename', style: TextStyle(color: c.text)),
                    content: TextField(controller: controller, style: TextStyle(color: c.text)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2, controller.text.trim()),
                        child: const Text('Rename'),
                      ),
                    ],
                  ),
                );
                if (newName != null && newName.isNotEmpty) {
                  await _fs.rename(e, newName);
                  _refresh();
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.danger),
              title: Text('Delete', style: TextStyle(color: c.danger)),
              onTap: () async {
                Navigator.pop(ctx);
                await _fs.delete(e);
                _refresh();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    if (_root == null) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    final crumbs = _crumbs;
    final visible = _visible;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
            child: Row(
              children: [
                _NavButton(icon: Icons.arrow_back, colors: c, onTap: _back.isEmpty ? null : _goBack),
                _NavButton(icon: Icons.arrow_forward, colors: c, onTap: _forward.isEmpty ? null : _goForward),
                _NavButton(icon: Icons.arrow_upward, colors: c, onTap: _parent == null ? null : _goUp),
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
                          if (i > 0) Icon(Icons.chevron_right, size: 14, color: c.textMuted),
                          InkWell(
                            onTap: last ? null : () => _goTo(crumbs[i].path),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                  color: c.surface,
                  iconSize: 18,
                  icon: Icon(Icons.more_vert, color: c.textMuted),
                  onSelected: (v) {
                    if (v == 'hidden') setState(() => _showHidden = !_showHidden);
                    if (v == 'home') _goTo(_root!);
                    if (v == 'refresh') _refresh();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'home', child: Text('Go home', style: TextStyle(color: c.text))),
                    CheckedPopupMenuItem(
                      value: 'hidden',
                      checked: _showHidden,
                      child: Text('Show hidden', style: TextStyle(color: c.text)),
                    ),
                    PopupMenuItem(value: 'refresh', child: Text('Refresh', style: TextStyle(color: c.text))),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: c.accent))
                : RefreshIndicator(
                    onRefresh: _refresh,
                    color: c.accent,
                    backgroundColor: c.surface,
                    child: visible.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 120),
                              Center(child: Text('Empty folder', style: TextStyle(color: c.textMuted))),
                            ],
                          )
                        : ListView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: visible.length,
                            itemBuilder: (context, i) {
                              final e = visible[i];
                              final isDir = e.kind == EntryKind.directory;
                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: Icon(
                                  isDir ? Icons.folder_outlined : Icons.description_outlined,
                                  color: isDir ? c.accent : c.textMuted,
                                ),
                                title: Text(e.name, style: TextStyle(color: c.text)),
                                subtitle: isDir
                                    ? null
                                    : Text(
                                        _formatSize(e.size),
                                        style: TextStyle(color: c.textMuted, fontSize: 12),
                                      ),
                                trailing: isDir ? Icon(Icons.chevron_right, size: 18, color: c.textMuted) : null,
                                onTap: () => _open(e),
                                onLongPress: () => _entryActions(e),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: PopupMenuButton<bool>(
        color: c.surface,
        onSelected: _newEntry,
        itemBuilder: (context) => [
          PopupMenuItem(value: false, child: Text('New file', style: TextStyle(color: c.text))),
          PopupMenuItem(value: true, child: Text('New folder', style: TextStyle(color: c.text))),
        ],
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          child: Icon(Icons.add, color: c.bg),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final AppColors colors;
  final VoidCallback? onTap;
  const _NavButton({required this.icon, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        onPressed: onTap,
        icon: Icon(icon, color: onTap == null ? colors.border : colors.text),
      ),
    );
  }
}

class _TextViewerScreen extends StatefulWidget {
  final AppColors colors;
  final FsEntry entry;
  final FileSystemService fs;
  const _TextViewerScreen({required this.colors, required this.entry, required this.fs});

  @override
  State<_TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<_TextViewerScreen> {
  late TextEditingController _controller;
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await widget.fs.readText(widget.entry.path);
      _controller.text = text;
    } catch (_) {
      _controller.text = '';
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    await widget.fs.writeText(widget.entry.path, _controller.text);
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_dirty)
            IconButton(icon: Icon(Icons.save_outlined, color: c.accent), onPressed: _save),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                onChanged: (_) => setState(() => _dirty = true),
                style: TextStyle(color: c.text, fontFamily: 'JetBrainsMono', fontSize: 13),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
    );
  }
}
