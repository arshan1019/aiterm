import 'package:flutter/material.dart';
import '../../app/services.dart';
import '../../app/theme.dart';

/// First run: install Alpine, or use Android's shell.
class SetupView extends StatefulWidget {
  const SetupView({super.key});

  @override
  State<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<SetupView> {
  String? _status;
  double? _progress;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _error = null;
      _status = 'Starting';
      _progress = null;
    });
    try {
      await context.services.linux.install((status, progress) {
        if (mounted) {
          setState(() {
            _status = status;
            _progress = progress;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = _status != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: AnimatedSize(
            duration: Motion.standard,
            curve: Motion.move,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Set up Linux', style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  'Downloads Alpine Linux (~4 MB) and runs it with proot. '
                  'You get apk, so you can install node, git, python, and tools like Claude Code.',
                  style: TextStyle(color: c.textMuted, height: 1.45),
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: Motion.standard,
                  child: busy
                      ? Column(
                          key: const ValueKey('progress'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_status!, style: TextStyle(color: c.text, fontSize: 13)),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(value: _progress, minHeight: 4),
                            ),
                          ],
                        )
                      : Column(
                          key: const ValueKey('actions'),
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(onPressed: _install, child: const Text('Install Alpine')),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: context.services.linux.useAndroidShell,
                              child: Text('Use Android shell instead', style: TextStyle(color: c.textMuted)),
                            ),
                          ],
                        ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: c.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
