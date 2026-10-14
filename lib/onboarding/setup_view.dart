import 'package:flutter/material.dart';
import '../agents/agent_catalog.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../git/git_actions.dart';
import '../keep_alive/keep_alive.dart';
import '../keep_alive/keep_alive_view.dart';
import 'setup_pipeline.dart';

/// First run, as one screen and one wait: pick agents, tap Set up, and
/// Linux, git and the agents install back to back. What's worth doing
/// meanwhile (keep-alive, GitHub sign-in) is offered under the progress.
class SetupView extends StatefulWidget {
  const SetupView({super.key});

  @override
  State<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<SetupView> {
  final _agents = {agentCatalog.first.id};

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return ListenableBuilder(
      listenable: s.setup,
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: s.setup.steps.isEmpty ? _intro(context) : _progress(context, s.setup),
          ),
        ),
      ),
    );
  }

  List<Widget> _intro(BuildContext context) {
    final c = context.colors;
    return [
      Text('Set up aiterm', style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 20),
      _Card(
        title: 'Agents',
        children: [
          for (final a in agentCatalog)
            CheckboxListTile(
              value: _agents.contains(a.id),
              onChanged: (on) => setState(() => on == true ? _agents.add(a.id) : _agents.remove(a.id)),
              title: Text(a.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(a.vendor, style: TextStyle(color: c.textMuted, fontSize: 12)),
            ),
        ],
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => context.services.setup.start([for (final a in agentCatalog) if (_agents.contains(a.id)) a.id]),
        child: const Text('Set up'),
      ),
    ];
  }

  List<Widget> _progress(BuildContext context, SetupPipeline setup) {
    final c = context.colors;
    final s = context.services;
    final failed = setup.failed && !setup.running;
    return [
      Text(failed ? 'Some steps didn\'t finish' : 'Setting up',
          style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      _Card(children: [for (final step in setup.steps) _StepRow(step: step)]),
      if (failed) ...[
        const SizedBox(height: 12),
        FilledButton(onPressed: setup.retry, child: const Text('Retry')),
        if (setup.canSkip)
          TextButton(onPressed: setup.skip, child: Text('Continue without them', style: TextStyle(color: c.textMuted))),
      ],
      const SizedBox(height: 20),
      ListenableBuilder(
        listenable: Listenable.merge([s.keepAlive, s.gitTools, s.github]),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.keepAlive.steps.isNotEmpty && !allDone(s.keepAlive.steps)) ...[
              _Card(
                title: 'Keep agents running',
                children: [
                  KeepAliveSteps(controller: s.keepAlive),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (s.gitTools.ready)
              _Card(
                title: 'GitHub',
                children: [
                  if (s.github.user case final user?)
                    ListTile(
                      leading: Icon(Icons.check_circle_rounded, color: c.accent),
                      title: Text('Signed in as ${user.login}', style: const TextStyle(fontSize: 14)),
                    )
                  else
                    ListTile(
                      title: const Text('Sign in to GitHub', style: TextStyle(fontSize: 14)),
                      trailing: TextButton(onPressed: () => signInToGitHub(context), child: const Text('Sign in')),
                    ),
                ],
              ),
          ],
        ),
      ),
    ];
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});
  final SetupStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = step.error ?? step.detail;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: switch (step.state) {
                  SetupState.running => const Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2)),
                  SetupState.done => Icon(Icons.check_circle_rounded, size: 20, color: c.accent),
                  SetupState.failed => Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
                  SetupState.waiting => Icon(Icons.circle_outlined, size: 20, color: c.border),
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(step.label,
                    style: TextStyle(color: step.state == SetupState.waiting ? c.textMuted : c.text, fontSize: 14)),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Text(note,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: step.error != null ? c.danger : c.textMuted, fontSize: 12)),
            ),
          if (step.state == SetupState.running && step.progress != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: step.progress, minHeight: 3),
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                child: Text(title!.toUpperCase(),
                    style: TextStyle(color: c.textMuted, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}
