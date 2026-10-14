import 'dart:io';
import 'package:flutter/material.dart';
import '../app/services.dart';
import '../app/theme.dart';
import 'format.dart';
import 'name_dialog.dart';
import '../app/icons.dart';

/// Picks a folder in Linux. Returns its guest path (as the shell sees it).
Future<String?> pickLinuxFolder(BuildContext context, {required String title, String? start, String action = 'Select'}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => _FolderPicker(title: title, start: start, action: action),
    ));

class _FolderPicker extends StatefulWidget {
  const _FolderPicker({required this.title, required this.start, required this.action});

  final String title, action;
  final String? start;

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late final _linux = context.services.linux;
  late String _guest = widget.start ?? '/root';
  List<String> _folders = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _list();
  }

  Future<void> _list() async {
    final names = <String>[];
    try {
      await for (final e in Directory(_linux.hostPath(_guest)).list(followLinks: false)) {
        if (e is Directory) {
          final name = e.path.split('/').last;
          if (!name.startsWith('.')) names.add(name);
        }
      }
    } on FileSystemException {
      // unreadable: show it as empty
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (mounted) {
      setState(() {
        _folders = names;
        _loaded = true;
      });
    }
  }

  void _go(String guest) {
    setState(() {
      _guest = guest;
      _loaded = false;
    });
    _list();
  }

  String get _parent {
    final i = _guest.lastIndexOf('/');
    return i <= 0 ? '/' : _guest.substring(0, i);
  }

  Future<void> _newFolder() async {
    final name = await showNameDialog(context, title: 'New folder', action: 'Create', hint: 'name');
    if (name == null) return;
    final guest = _guest == '/' ? '/$name' : '$_guest/$name';
    await Directory(_linux.hostPath(guest)).create(recursive: true);
    _go(guest);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: _guest == '/' || _guest == (widget.start ?? '/root'),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_parent);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title),
              Text(shortPath(_guest), style: codeStyle(c.textMuted, size: 12)),
            ],
          ),
          actions: [
            IconButton(tooltip: 'New folder', icon: const Icon(AppIcons.folderNew), onPressed: _newFolder),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: !_loaded
                  ? const SizedBox.expand()
                  : ListView(
                      children: [
                        if (_guest != '/')
                          ListTile(
                            leading: Icon(AppIcons.arrowUpward, color: c.textMuted),
                            title: const Text('..', style: TextStyle(fontSize: 14)),
                            onTap: () => _go(_parent),
                          ),
                        for (final name in _folders)
                          ListTile(
                            leading: Icon(AppIcons.folder, fill: 1, color: c.accent),
                            title: Text(name, style: const TextStyle(fontSize: 14)),
                            onTap: () => _go(_guest == '/' ? '/$name' : '$_guest/$name'),
                          ),
                        if (_folders.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(child: Text('No folders here', style: TextStyle(color: c.textMuted))),
                          ),
                      ],
                    ),
            ),
            Material(
              color: c.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _guest),
                      child: Text('${widget.action} ${shortPath(_guest)}', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
