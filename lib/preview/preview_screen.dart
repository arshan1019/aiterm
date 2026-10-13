import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../app/theme.dart';
import '../platform/android_env.dart';
import 'preview_controller.dart';

/// An in-app browser for a dev server running in Linux.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.port});

  final int port;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final WebViewController _web;
  double _progress = 0;
  String? _title;

  Uri get _url => previewUrl(widget.port);

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p / 100) : null,
        onPageFinished: (_) async {
          final t = await _web.getTitle();
          if (mounted) setState(() => _title = t);
        },
      ))
      ..loadRequest(_url);
  }

  Future<void> _openExternally() async {
    try {
      await AndroidEnv.openUrl('$_url');
    } on PlatformException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Could not open')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: false,
      // Back steps through the page's own history first.
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title?.isNotEmpty == true ? _title! : 'Preview', overflow: TextOverflow.ellipsis),
              Text('localhost:${widget.port}', style: TextStyle(color: c.textMuted, fontSize: 11)),
            ],
          ),
          actions: [
            IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh_rounded), onPressed: _web.reload),
            IconButton(tooltip: 'Open in browser', icon: const Icon(Icons.open_in_new_rounded), onPressed: _openExternally),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: AnimatedOpacity(
              duration: Motion.standard,
              opacity: _progress < 1 ? 1 : 0,
              child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 2),
            ),
          ),
        ),
        body: WebViewWidget(controller: _web),
      ),
    );
  }
}
