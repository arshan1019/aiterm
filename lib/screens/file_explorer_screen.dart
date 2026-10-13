import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/distro_manager.dart';
import '../core/file_system_service.dart';
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
  late String _current;
  List<FsEntry> _entries = [];
  bool _loading = true;

  final _distro = DistroManager.instance;

  @override
  void initState() {
    super.initState();
    _distro.addListener(_init);
    _init();
  }

  @override
  void dispose() {
    _distro.removeListener(_init);
    super.dispose();
  }

  Future<void> _init() async {
    await _distro.init();
    final home = _distro.installed ? _distro.home : await ShellEnv.androidHome();
    if (!mounted) return;
    _root = home;
    _current = home;
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final entries = await _fs.list(_current);
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _open(FsEntry e) {
    if (e.kind == EntryKind.directory) {
      setState(() => _current = e.path);
      _refresh();
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

  List<String> get _crumbs {
    final root = _root!;
    if (_current == root) return ['home'];
    final rel = _current.substring(root.length).replaceAll(RegExp(r'^/'), '');
    return ['home', ...rel.split('/')];
  }

  void _goToCrumb(int index) {
    final root = _root!;
    if (index == 0) {
      setState(() => _current = root);
    } else {
      final parts = _crumbs.sublist(1, index + 1);
      setState(() => _current = '$root/${parts.join('/')}');
    }
    _refresh();
  }

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
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: c.surfaceAlt,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < _crumbs.length; i++)
                  Row(
                    children: [
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.chevron_right, size: 16, color: c.textMuted),
                        ),
                      InkWell(
                        onTap: () => _goToCrumb(i),
                        child: Center(
                          child: Text(
                            _crumbs[i],
                            style: TextStyle(
                              color: i == _crumbs.length - 1 ? c.text : c.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: c.accent))
                : _entries.isEmpty
                    ? Center(
                        child: Text('Empty', style: TextStyle(color: c.textMuted)))
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        color: c.accent,
                        backgroundColor: c.surface,
                        child: ListView.separated(
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: c.border),
                          itemBuilder: (context, i) {
                            final e = _entries[i];
                            final isDir = e.kind == EntryKind.directory;
                            return ListTile(
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
          width: 56,
          height: 56,
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
                style: TextStyle(color: c.text, fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
    );
  }
}
