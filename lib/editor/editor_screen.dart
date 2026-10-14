import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../files/file_system_service.dart';
import '../phone/phone_files.dart';
import '../shared/form.dart';
import 'language_servers.dart';
import 'lsp_process.dart';
import '../app/icons.dart';

enum _Server { none, missing, installing, starting, running, failed }

/// The file editor: CodeMirror 6 in a WebView (assets/editor, built from
/// editor/), with syntax highlighting for most languages, search, folding,
/// and, for files in Linux, a real language server for errors as you type,
/// completion and hover. The same architecture as Acode's editor; the
/// language server's stdio is bridged here instead of over a WebSocket.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.entry, required this.fs});

  final FsEntry entry;
  final FileSystemService fs;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final _s = context.services;
  late final WebViewController _web;
  String? _text;
  bool _dirty = false;
  bool _ready = false;
  bool _opened = false;

  LanguageServer? _server;
  _Server _serverState = _Server.none;
  LspProcess? _lsp;

  String get _path => widget.entry.path;

  /// The file as Linux sees it, or null (phone files have no language server).
  String? get _guestPath =>
      !PhonePath.isPhone(_path) && _path.startsWith('${_s.linux.rootfs}/') ? _s.linux.guestPath(_path) : null;

  /// The project folder containing the file, else the file's folder.
  String get _root {
    final file = _guestPath!;
    final project = _s.projects.projects.where((p) => file.startsWith('${p.path}/')).firstOrNull;
    return project?.path ?? file.substring(0, file.lastIndexOf('/'));
  }

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('AitermBridge', onMessageReceived: (m) => _onMessage(m.message));
    _s.settings.addListener(_applyTheme);
    _load();
  }

  AppColors? _colors;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The theme changed (light/dark, the system's choice, wallpaper colors).
    if (_colors != context.colors) {
      _colors = context.colors;
      _web.setBackgroundColor(_colors!.bg);
      _applyTheme();
    }
  }

  @override
  void dispose() {
    _s.settings.removeListener(_applyTheme);
    _lsp?.stop();
    super.dispose();
  }

  Future<void> _load() async {
    String text;
    try {
      text = await widget.fs.readText(_path);
    } catch (_) {
      text = '';
    }
    _text = text;
    _server = _guestPath == null ? null : serverFor(_path);
    if (_server != null) await _startServer(installIfMissing: false);
    await _web.loadFlutterAsset('assets/editor/index.html');
  }

  // ---- Bridge ----------------------------------------------------------------

  Future<void> _js(String code) async {
    try {
      await _web.runJavaScript(code);
    } catch (_) {
      // The page is gone (screen closing).
    }
  }

  Map<String, Object?> _themeOptions() {
    final c = context.colors;
    String hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return {
      'colors': {
        'bg': hex(c.bg),
        'surface': hex(c.surface),
        'surfaceAlt': hex(c.surfaceAlt),
        'border': hex(c.border),
        'text': hex(c.text),
        'textMuted': hex(c.textMuted),
        'accent': hex(c.accent),
        'danger': hex(c.danger),
        'warning': hex(c.warning),
      },
      'dark': Theme.of(context).brightness == Brightness.dark,
      'fontSize': _s.settings.fontSize,
    };
  }

  void _applyTheme() {
    if (!_opened || !mounted) return;
    // The theme animates; read the new colours after it settles.
    Future<void>.delayed(Motion.standard * 2, () {
      if (mounted) _js('aiterm.setTheme(${jsonEncode(_themeOptions())})');
    });
  }

  void _onMessage(String raw) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'ready':
        _ready = true;
        _open();
      case 'changed':
        if (mounted) setState(() => _dirty = m['dirty'] == true);
      case 'save':
        _save();
      case 'text':
        _write(m['text'] as String? ?? '');
      case 'lsp':
        _lsp?.send(m['message'] as String);
    }
  }

  Future<void> _open() async {
    if (!_ready || _text == null || !mounted) return;
    final guest = _guestPath;
    await _js('aiterm.open(${jsonEncode({
      'text': _text,
      'path': widget.entry.name,
      'uri': guest == null ? null : Uri.file(guest).toString(),
      'rootUri': guest == null ? null : Uri.directory(_root).toString(),
      'languageId': languageIdFor(_path),
      'lsp': _serverState == _Server.running,
      ..._themeOptions(),
    })})');
    _opened = true;
  }

  // ---- Language server -----------------------------------------------------

  Future<void> _startServer({required bool installIfMissing}) async {
    final server = _server!;
    final (_, found) = await _s.linux.runScript('command -v ${server.binary} >/dev/null');
    if (!mounted) return;
    if (found != 0) {
      if (!installIfMissing) return setState(() => _serverState = _Server.missing);
      setState(() => _serverState = _Server.installing);
      final code = await _s.linux.runScriptStreaming(server.install, (_) {});
      if (!mounted) return;
      if (code != 0) return setState(() => _serverState = _Server.failed);
    }
    setState(() => _serverState = _Server.starting);
    try {
      final lsp = await LspProcess.start(_s.linux, server, _root, (json) {
        if (mounted) _js('aiterm.lspReceive(${jsonEncode(json)})');
      });
      if (!mounted) {
        lsp.stop();
        return;
      }
      _lsp = lsp;
      setState(() => _serverState = _Server.running);
      if (_opened) await _js('aiterm.lspStart()');
      lsp.exitCode.then((_) {
        if (!mounted || _lsp != lsp) return;
        _lsp = null;
        setState(() => _serverState = _Server.failed);
        _js('aiterm.lspStop()');
      });
    } catch (_) {
      if (mounted) setState(() => _serverState = _Server.failed);
    }
  }

  // ---- Saving ----------------------------------------------------------------

  void _save() => _js('aiterm.requestText()');

  Future<void> _write(String text) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.fs.writeText(_path, text);
      await _js('aiterm.markSaved()');
      _s.git.touched(_guestPath ?? '');
      messenger.showSnackBar(const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn\'t save: $e')));
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await confirmAction(context,
        title: 'Discard changes?', message: 'Your edits to this file will be lost.', action: 'Discard', danger: true);
    if (discard && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'Undo', icon: const Icon(AppIcons.undo), onPressed: () => _js('aiterm.undo()')),
            IconButton(tooltip: 'Redo', icon: const Icon(AppIcons.redo), onPressed: () => _js('aiterm.redo()')),
            IconButton(tooltip: 'Find', icon: const Icon(AppIcons.search), onPressed: () => _js('aiterm.search()')),
            IconButton(
              tooltip: 'Save',
              icon: Icon(AppIcons.check, color: _dirty ? c.accent : null),
              onPressed: _dirty ? _save : null,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: WebViewWidget(controller: _web)),
            _serverBar(context),
            if (keyboard) _KeyRow(onKey: (k) => _js('aiterm.key(${jsonEncode(k)})'), onText: (t) => _js('aiterm.insert(${jsonEncode(t)})')),
          ],
        ),
      ),
    );
  }

  Widget _serverBar(BuildContext context) {
    final c = context.colors;
    final server = _server;
    final Widget? child = switch (_serverState) {
      _ when server == null => null,
      _Server.missing => TextButton.icon(
          onPressed: () => _startServer(installIfMissing: true),
          icon: const Icon(AppIcons.download, size: 18),
          label: Text('Install ${server.name} support'),
        ),
      _Server.installing || _Server.starting => Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(_serverState == _Server.installing ? 'Installing ${server.name} support…' : 'Starting ${server.name}…',
                style: TextStyle(color: c.textMuted, fontSize: 12)),
          ],
        ),
      _Server.failed => TextButton.icon(
          onPressed: () => _startServer(installIfMissing: true),
          icon: Icon(AppIcons.refresh, size: 18, color: c.danger),
          label: Text('Restart ${server.name} support', style: TextStyle(color: c.danger)),
        ),
      _ => null,
    };
    return AnimatedSize(
      duration: Motion.standard,
      curve: Motion.move,
      child: child == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border, width: 0.5))),
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
    );
  }
}

/// Keys phone keyboards lack, above the keyboard while it's open.
class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.onKey, required this.onText});

  final ValueChanged<String> onKey;
  final ValueChanged<String> onText;

  static const _keys = [('tab', '⇥', 'Tab'), ('left', '←', 'Left'), ('up', '↑', 'Up'), ('down', '↓', 'Down'), ('right', '→', 'Right')];
  static const _symbols = ['{', '}', '(', ')', '[', ']', '<', '>', ';', '=', '"', "'", '/', '\\', '|', '&', '\$', '#'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget key(String label, VoidCallback onTap, [String? spoken]) => Semantics(
          button: true,
          label: spoken ?? label,
          excludeSemantics: spoken != null,
          child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(label, style: TextStyle(color: c.text, fontSize: 15)),
          ),
        ),
        );
    return Container(
      height: 42,
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border, width: 0.5))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (name, label, spoken) in _keys) key(label, () => onKey(name), spoken),
          Container(width: 0.5, margin: const EdgeInsets.symmetric(vertical: 10), color: c.border),
          for (final s in _symbols) key(s, () => onText(s)),
        ],
      ),
    );
  }
}
