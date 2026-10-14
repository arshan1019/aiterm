import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/navigation.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../shared/sheet.dart';
import '../shared/format.dart';
import '../git/github_button.dart';
import 'phone_files.dart';

/// Files shared to aiterm (Share → aiterm in any app): asks which project
/// they go into, copies them there, and shows them.
class ShareReceiver extends StatefulWidget {
  const ShareReceiver({super.key, required this.child});
  final Widget child;

  @override
  State<ShareReceiver> createState() => _ShareReceiverState();
}

class _ShareReceiverState extends State<ShareReceiver> {
  late final _s = context.services;

  @override
  void initState() {
    super.initState();
    _s.phone.shared.addListener(_onShared);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShared());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheGitHubMarks(context);
  }

  @override
  void dispose() {
    _s.phone.shared.removeListener(_onShared);
    super.dispose();
  }

  void _onShared() {
    final items = _s.phone.shared.value;
    final context = _s.navigation.navigatorKey.currentContext;
    if (items.isEmpty || context == null) return;
    _s.phone.shared.value = const [];
    if (!_s.linux.installed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set up aiterm first, then share again.')));
      return;
    }
    showAppSheet<void>(
      context,
      title: items.length == 1 ? 'Add ${items.single.name} to' : 'Add ${plural(items.length, 'file')} to',
      inset: false,
      builder: (sheet) => _ShareSheet(items: items),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.items});
  final List<PhoneItem> items;

  Future<void> _addTo(BuildContext context, String guestFolder, VoidCallback show) async {
    final s = context.services;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    try {
      final added = await s.phone.importTo(PhoneFiles.docsOf(items), s.linux.hostPath(guestFolder));
      show();
      messenger.showSnackBar(SnackBar(content: Text('Added ${plural(added.length, 'file')}')));
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Couldn\'t add the files')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final c = context.colors;
    final projects = s.projects.projects;
    return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in projects)
                    ListTile(
                      leading: Icon(Icons.folder_special_outlined, color: c.accent),
                      title: Text(p.name),
                      subtitle: Text(shortPath(p.path), style: codeStyle(c.textMuted, size: 12)),
                      onTap: () => _addTo(context, p.path, () => s.showProject(p, tab: WorkspaceTab.files)),
                    ),
                  ListTile(
                    leading: Icon(Icons.home_outlined, color: c.textMuted),
                    title: const Text('Home folder'),
                    subtitle: Text('~', style: TextStyle(color: c.textMuted, fontSize: 12)),
                    onTap: () => _addTo(context, '/root', () => s.navigation.showFolder('/root')),
                  ),
                ],
              );
  }
}
