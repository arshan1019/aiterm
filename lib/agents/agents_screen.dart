import 'package:flutter/material.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../onboarding/setup_view.dart';
import '../projects/projects_screen.dart';
import 'agent_catalog.dart';
import 'agent_installer.dart';

/// AI coding agents, installed in one tap. Open asks which project to work
/// on (agents work in projects); the agent's tab handles sign-in.
class AgentsScreen extends StatelessWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return ListenableBuilder(
      listenable: Listenable.merge([s.linux, s.agents]),
      builder: (context, _) => AnimatedSwitcher(
        duration: Motion.standard,
        child: s.linux.installed
            ? _AgentList(key: const ValueKey('agents'), installer: s.agents)
            : const SetupView(key: ValueKey('setup')),
      ),
    );
  }
}

class _AgentList extends StatelessWidget {
  const _AgentList({super.key, required this.installer});

  final AgentInstaller installer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RefreshIndicator(
      onRefresh: installer.refresh,
      color: c.accent,
      backgroundColor: c.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final agent in agentCatalog) ...[
            _AgentCard(agent: agent, installer: installer),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent, required this.installer});

  final AgentRecipe agent;
  final AgentInstaller installer;

  void _details(BuildContext context, AgentState state) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(state.log, style: TextStyle(color: sheet.colors.text, fontSize: 11, height: 1.4)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = installer.stateOf(agent.id);
    final installing = state.status == AgentStatus.installing;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: AnimatedSize(
          duration: Motion.standard,
          curve: Motion.move,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(agent.name, style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(agent.vendor,
                            style: TextStyle(color: c.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(duration: Motion.quick, child: _action(context, state)),
                ],
              ),
              if (installing) ...[
                const SizedBox(height: 12),
                Text('${state.step}…', style: TextStyle(color: c.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: const LinearProgressIndicator(minHeight: 3),
                ),
              ],
              if (state.status == AgentStatus.failed) ...[
                const SizedBox(height: 10),
                Text(state.message ?? 'Install failed.', style: TextStyle(color: c.danger, fontSize: 12)),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => _details(context, state),
                  child: const Text('Show details'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(BuildContext context, AgentState state) {
    switch (state.status) {
      case AgentStatus.installed:
        return FilledButton(
          key: const ValueKey('open'),
          onPressed: () => openAgentInProject(context, agent.id),
          child: const Text('Open'),
        );
      case AgentStatus.installing:
        return const SizedBox(
          key: ValueKey('busy'),
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case AgentStatus.failed:
        return OutlinedButton(
          key: const ValueKey('retry'),
          onPressed: installer.busy ? null : () => installer.install(agent.id),
          child: const Text('Retry'),
        );
      case AgentStatus.unknown:
      case AgentStatus.notInstalled:
        return OutlinedButton(
          key: const ValueKey('install'),
          onPressed: installer.busy ? null : () => installer.install(agent.id),
          child: const Text('Install'),
        );
    }
  }
}
