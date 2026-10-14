import 'package:flutter/material.dart';
import '../app/services.dart';
import '../app/theme.dart';
import 'keep_alive.dart';
import 'keep_alive_controller.dart';

/// The keep-alive checklist: each step with its Allow / Fix button, and
/// the Wireless debugging walkthrough when fixing the child process limit.
/// Shown in Settings, during first-run setup, and after Android kills a
/// session.
class KeepAliveSteps extends StatelessWidget {
  const KeepAliveSteps({super.key, required this.controller});

  final KeepAliveController controller;

  void _fix(StepKind kind) => switch (kind) {
        StepKind.battery => controller.requestBattery(),
        StepKind.notifications => controller.requestNotifications(),
        StepKind.childProcesses => controller.fixChildProcesses(),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in controller.steps)
            ListTile(
              title: Text(step.title, style: const TextStyle(fontSize: 14)),
              trailing: AnimatedSwitcher(
                duration: Motion.standard,
                child: step.done
                    ? Icon(Icons.check_circle_rounded, key: const ValueKey('done'), color: c.accent)
                    : TextButton(
                        key: const ValueKey('fix'),
                        onPressed: controller.fixing && step.kind == StepKind.childProcesses ? null : () => _fix(step.kind),
                        child: Text(step.kind == StepKind.childProcesses ? 'Fix' : 'Allow'),
                      ),
              ),
            ),
          AnimatedSize(
            duration: Motion.standard,
            curve: Motion.move,
            alignment: Alignment.topCenter,
            child: controller.message == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(controller.message!, style: TextStyle(color: c.text, fontSize: 12, height: 1.4)),
                        if (controller.fixing)
                          Row(
                            children: [
                              TextButton(onPressed: controller.openDeveloperOptions, child: const Text('Open Wireless debugging')),
                              TextButton(
                                onPressed: controller.cancelFix,
                                child: Text('Cancel', style: TextStyle(color: c.textMuted)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The checklist as a sheet, from "Android stopped this session".
void showKeepAlive(BuildContext context) {
  final controller = context.services.keepAlive;
  controller.refresh().ignore();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Keep agents running',
                  style: TextStyle(color: sheet.colors.text, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            KeepAliveSteps(controller: controller),
          ],
        ),
      ),
    ),
  );
}
