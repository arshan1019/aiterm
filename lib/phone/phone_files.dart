import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where a phone document lives, as a path the Files browser can carry:
///
/// - `phone:` the folders and files the user chose,
/// - `phone:/t~<folder grant>[/<document id>…]` a chosen folder and what's in it,
/// - `phone:/f~<document uri>` a single chosen file.
///
/// Segments are base64url, since document ids and uris contain slashes.
class PhonePath {
  const PhonePath._({this.tree, this.doc, this.uri});

  static const root = 'phone:';

  /// A folder grant (tree uri), for folders and what's inside them.
  final String? tree;

  /// A document id inside [tree]; null for the chosen folder itself.
  final String? doc;

  /// A single chosen file's document uri.
  final String? uri;

  static bool isPhone(String path) => path == root || path.startsWith('$root/');

  static String _enc(String s) => base64Url.encode(utf8.encode(s));
  static String _dec(String s) => utf8.decode(base64Url.decode(s));

  static String ofTree(String treeUri) => '$root/t~${_enc(treeUri)}';
  static String ofFile(String docUri) => '$root/f~${_enc(docUri)}';
  static String child(String parent, String doc) => '$parent/${_enc(doc)}';

  /// Null for [root] (it isn't a document).
  static PhonePath? parse(String path) {
    if (!isPhone(path) || path == root) return null;
    final parts = path.substring(root.length + 1).split('/');
    final first = parts.first;
    if (first.startsWith('f~')) return PhonePath._(uri: _dec(first.substring(2)));
    final tree = _dec(first.substring(2));
    return PhonePath._(tree: tree, doc: parts.length > 1 ? _dec(parts.last) : null);
  }

  /// The containing folder's path, or null at [root].
  static String? parentOf(String path) {
    if (path == root) return null;
    final i = path.lastIndexOf('/');
    return i <= root.length ? root : path.substring(0, i);
  }

  /// Arguments naming this document for the native side.
  Map<String, String?> get args => {'tree': tree, 'doc': uri ?? doc};
}

/// A folder or file the user chose (or shared to aiterm).
class PhoneItem {
  const PhoneItem({required this.uri, required this.name, required this.isFolder, this.size = 0});

  final String uri;
  final String name;
  final bool isFolder;
  final int size;

  String get path => isFolder ? PhonePath.ofTree(uri) : PhonePath.ofFile(uri);

  static PhoneItem fromMap(Map m) =>
      PhoneItem(uri: m['uri'] as String, name: m['name'] as String, isFolder: m['tree'] == true, size: (m['size'] as num?)?.toInt() ?? 0);
}

class PhoneEntry {
  const PhoneEntry({required this.doc, required this.name, required this.isFolder, required this.size, required this.modified});
  final String doc;
  final String name;
  final bool isFolder;
  final int size;
  final DateTime modified;
}

/// Phone files through Android's own picker (android/.../PhoneFilesPlugin.kt):
/// only what the user chose is visible, and it stays chosen across restarts.
/// Also files shared to aiterm from other apps.
class PhoneFiles extends ChangeNotifier {
  PhoneFiles({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('aiterm/phone') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') await _takeShared();
    });
  }

  final MethodChannel _channel;

  List<PhoneItem> _grants = const [];

  /// What the user chose, folders first.
  List<PhoneItem> get grants => _grants;

  /// Files shared to aiterm, waiting to be put somewhere.
  final shared = ValueNotifier<List<PhoneItem>>(const []);

  Future<void> refresh() async {
    try {
      final list = await _channel.invokeListMethod<Map>('grants') ?? const [];
      _grants = [for (final m in list) PhoneItem.fromMap(m)]
        ..sort((a, b) => a.isFolder == b.isFolder ? a.name.toLowerCase().compareTo(b.name.toLowerCase()) : (a.isFolder ? -1 : 1));
    } on MissingPluginException {
      _grants = const [];
    }
    notifyListeners();
    await _takeShared();
  }

  Future<void> _takeShared() async {
    try {
      final list = await _channel.invokeListMethod<Map>('takeShared') ?? const [];
      if (list.isNotEmpty) shared.value = [for (final m in list) PhoneItem.fromMap(m)];
    } on MissingPluginException {
      // Tests and platforms without the plugin.
    }
  }

  /// Opens the system folder picker. [keep]: remember the folder (it shows
  /// in Files); otherwise access lasts only for this use.
  Future<PhoneItem?> pickFolder({bool keep = true}) async {
    final list = await _channel.invokeListMethod<Map>('pickFolder', {'persist': keep});
    if (keep) await refresh();
    return list == null || list.isEmpty ? null : PhoneItem.fromMap(list.first);
  }

  Future<List<PhoneItem>> pickFiles({bool keep = true}) async {
    final list = await _channel.invokeListMethod<Map>('pickFiles', {'persist': keep}) ?? const [];
    if (keep) await refresh();
    return [for (final m in list) PhoneItem.fromMap(m)];
  }

  Future<void> forget(PhoneItem item) async {
    await _channel.invokeMethod('release', {'uri': item.uri});
    await refresh();
  }

  Future<List<PhoneEntry>> list(PhonePath folder) async {
    final list = await _channel.invokeListMethod<Map>('list', folder.args) ?? const [];
    return [
      for (final m in list)
        PhoneEntry(
          doc: m['doc'] as String,
          name: m['name'] as String,
          isFolder: m['dir'] == true,
          size: (m['size'] as num?)?.toInt() ?? 0,
          modified: DateTime.fromMillisecondsSinceEpoch((m['modified'] as num?)?.toInt() ?? 0),
        ),
    ];
  }

  Future<void> create(PhonePath parent, String name, {required bool folder}) =>
      _channel.invokeMethod('create', {...parent.args, 'name': name, 'dir': folder});

  Future<void> delete(PhonePath doc) => _channel.invokeMethod('delete', doc.args);

  Future<void> rename(PhonePath doc, String name) => _channel.invokeMethod('rename', {...doc.args, 'name': name});

  Future<String> readText(PhonePath doc) async => await _channel.invokeMethod<String>('readText', doc.args) ?? '';

  Future<void> writeText(PhonePath doc, String text) => _channel.invokeMethod('writeText', {...doc.args, 'text': text});

  /// Copies phone documents (folders whole) into the local folder [dest];
  /// returns the new paths. Existing names get a numbered copy.
  Future<List<String>> importTo(List<PhonePath> docs, String dest) async =>
      await _channel.invokeListMethod<String>('importTo', {
        'dest': dest,
        'items': [for (final d in docs) d.args],
      }) ??
      const [];

  /// Copies local files or folders into the phone folder [folder].
  Future<List<String>> exportTo(List<String> paths, PhonePath folder) async =>
      await _channel.invokeListMethod<String>('exportTo', {...folder.args, 'paths': paths}) ?? const [];

  /// Items picked or shared (by uri) as documents.
  static List<PhonePath> docsOf(List<PhoneItem> items) => [for (final i in items) PhonePath.parse(i.path)!];

  @override
  void dispose() {
    shared.dispose();
    super.dispose();
  }
}
