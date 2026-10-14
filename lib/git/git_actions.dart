import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../shared/sheet.dart';
import '../platform/android_env.dart';
import 'git_repo.dart';
import 'git_tools.dart';
import 'github_auth.dart';
import '../shared/form.dart';
import '../app/icons.dart';

/// The git flows every screen shares: one-time tool install, GitHub
/// sign-in, commit identity, and git errors turned into a next step.

/// Makes sure git, GitHub's CLI and ssh are in Linux (installing them the
/// first time, with progress). True when ready.
Future<bool> ensureGitTools(BuildContext context) async {
  final tools = context.services.gitTools;
  if (tools.status == ToolsStatus.unknown) await tools.refresh();
  if (tools.ready) return true;
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ToolsDialog(tools: tools),
      ) ??
      false;
}

class _ToolsDialog extends StatefulWidget {
  const _ToolsDialog({required this.tools});
  final GitTools tools;

  @override
  State<_ToolsDialog> createState() => _ToolsDialogState();
}

class _ToolsDialogState extends State<_ToolsDialog> {
  @override
  void initState() {
    super.initState();
    _install();
  }

  Future<void> _install() async {
    if (await widget.tools.ensure() && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.tools,
      builder: (context, _) {
        final failed = widget.tools.status == ToolsStatus.failed;
        return AlertDialog(
          title: Text(failed ? 'Couldn\'t install git' : 'Setting up git', style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                failed
                    ? widget.tools.error ?? 'Check your connection and try again.'
                    : 'Installing git and GitHub\'s CLI in Linux. This happens once.',
                style: TextStyle(color: failed ? c.danger : c.textMuted, fontSize: 13, height: 1.4),
              ),
              if (!failed) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(minHeight: 3),
              ],
            ],
          ),
          actions: failed
              ? [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
                  TextButton(onPressed: _install, child: const Text('Retry')),
                ]
              : null,
        );
      },
    );
  }
}

/// Signs in to GitHub with the device code flow. True when signed in.
/// The first sign-in also sets the commit identity if there is none.
Future<bool> signInToGitHub(BuildContext context) async {
  final s = context.services;
  if (s.github.user != null) return true;
  if (!await ensureGitTools(context) || !context.mounted) return false;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final ok = await showAppSheet<bool>(
        context,
        title: 'Sign in with GitHub',
        leading: Image.asset(
          dark ? 'assets/github/GitHub_Invertocat_White.png' : 'assets/github/GitHub_Invertocat_Black.png',
          width: 24,
          height: 24,
          excludeFromSemantics: true,
        ),
        dismissible: false,
        builder: (_) => _SignInSheet(auth: s.github),
      ) ??
      false;
  final user = s.github.user;
  if (ok && user != null && await s.git.identity() == null) {
    final (name, email) = identityFor(user);
    await s.git.setIdentity(name, email);
  }
  return ok;
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet({required this.auth});
  final GitHubAuth auth;

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_changed);
    widget.auth.signIn();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (widget.auth.state is SignedIn && mounted) Navigator.pop(context, true);
  }

  void _cancel() {
    widget.auth.cancel();
    Navigator.pop(context, false);
  }

  Future<void> _copyAndOpen(AwaitingCode s) async {
    await Clipboard.setData(ClipboardData(text: s.code));
    try {
      await AndroidEnv.openUrl(s.url);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        final state = widget.auth.state;
        return AnimatedSize(
              duration: Motion.standard,
              curve: Motion.move,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...switch (state) {
                    AwaitingCode() => [
                        Text('Copy this code, then paste it on the GitHub page that opens.',
                            style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.4)),
                        const SizedBox(height: 18),
                        SelectableText(
                          state.code,
                          textAlign: TextAlign.center,
                          style: codeStyle(c.text, size: 30, weight: FontWeight.w600),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: () => _copyAndOpen(state),
                          icon: const Icon(AppIcons.openInNew, size: 18),
                          label: const Text('Copy code & open GitHub'),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                            const SizedBox(width: 8),
                            Text('Waiting for GitHub…', style: TextStyle(color: c.textMuted, fontSize: 12)),
                          ],
                        ),
                      ],
                    SignInFailed(:final message) => [
                        Text(message, style: TextStyle(color: c.danger, fontSize: 13, height: 1.4)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: widget.auth.signIn, child: const Text('Try again')),
                      ],
                    _ => [
                        Text('Connecting to GitHub…', style: TextStyle(color: c.textMuted, fontSize: 13)),
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(minHeight: 3),
                      ],
                  },
                  const SizedBox(height: 4),
                  TextButton(onPressed: _cancel, child: Text('Cancel', style: TextStyle(color: c.textMuted))),
                ],
              ),
            );
      },
    );
  }
}

/// Asks for the name and email commits are signed with (prefilled from
/// GitHub when signed in). True when saved.
Future<bool> askCommitIdentity(BuildContext context) async {
  final s = context.services;
  if (!await ensureGitTools(context) || !context.mounted) return false;
  final current = await s.git.identity();
  final user = s.github.user;
  final (name, email) = current ?? (user != null ? identityFor(user) : ('', ''));
  if (!context.mounted) return false;
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _IdentityDialog(name: name, email: email),
  );
  if (result == null) return false;
  await s.git.setIdentity(result.$1, result.$2);
  return true;
}

class _IdentityDialog extends StatefulWidget {
  const _IdentityDialog({required this.name, required this.email});
  final String name, email;

  @override
  State<_IdentityDialog> createState() => _IdentityDialogState();
}

class _IdentityDialogState extends State<_IdentityDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _email = TextEditingController(text: widget.email);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _email.text.contains('@');

  void _save() => Navigator.pop(context, (_name.text.trim(), _email.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Who\'s committing?',
      message: 'Commits carry a name and email. Set once for all projects.',
      fields: [
        LabeledField(
          label: 'Name',
          child: TextField(
            controller: _name,
            autofocus: widget.name.isEmpty,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'Your name'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        LabeledField(
          label: 'Email',
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'you@example.com'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _valid ? _save() : null,
          ),
        ),
      ],
      action: 'Save',
      onAction: _valid ? _save : null,
    );
  }
}

/// What came of a git action, for screens that show it in place (a card
/// that stays until dismissed) instead of a passing snackbar.
class GitOutcome {
  const GitOutcome(this.message, {this.isError = false, this.action, this.onAction});

  final String message;
  final bool isError;

  /// The next step ("Pull", "Details"), if there is one.
  final String? action;
  final VoidCallback? onAction;
}

/// Runs a git [action]; when it fails, offers the fix (set identity, sign
/// in, install git, pull first) and retries once fixed. True on success.
/// The result ([done] on success, the error otherwise) goes to [onOutcome]
/// if given, else a snackbar.
Future<bool> runGit(BuildContext context, Future<void> Function() action,
    {GitRepo? repo, String? done, void Function(GitOutcome outcome)? onOutcome}) async {
  final messenger = ScaffoldMessenger.of(context);
  void show(GitOutcome o) {
    if (onOutcome != null) return onOutcome(o);
    messenger.showSnackBar(SnackBar(
      content: Text(o.message),
      action: o.action == null ? null : SnackBarAction(label: o.action!, onPressed: o.onAction ?? () {}),
    ));
  }

  try {
    await action();
    if (done != null) show(GitOutcome(done));
    return true;
  } on GitError catch (e) {
    if (!context.mounted) return false;
    Future<bool> fix() async {
      switch (e.kind) {
        case GitErrorKind.identity:
          return askCommitIdentity(context);
        case GitErrorKind.notInstalled:
          return ensureGitTools(context);
        case GitErrorKind.auth:
          if (!await _confirm(context, 'Sign in to sync', e.message, 'Sign in') || !context.mounted) return false;
          return signInToGitHub(context);
        default:
          return false;
      }
    }

    final fixed = await fix();
    if (fixed && context.mounted) return runGit(context, action, repo: repo, done: done, onOutcome: onOutcome);
    if (!context.mounted || e.kind == GitErrorKind.identity || e.kind == GitErrorKind.notInstalled) return false;
    if (e.kind == GitErrorKind.auth) return false;
    show(e.kind == GitErrorKind.pullFirst && repo != null
        ? GitOutcome(e.message, isError: true, action: 'Pull', onAction: () {
            if (context.mounted) runGit(context, repo.pull, repo: repo, done: 'Up to date', onOutcome: onOutcome);
          })
        : GitOutcome(e.message, isError: true, action: 'Details', onAction: () {
            if (context.mounted) showGitDetails(context, e.detail);
          }));
    return false;
  } catch (e) {
    show(GitOutcome('$e', isError: true));
    return false;
  }
}

Future<bool> _confirm(BuildContext context, String title, String message, String action) =>
    confirmAction(context, title: title, message: message, action: action);

/// git's own output, for when the plain-language message isn't enough.
void showGitDetails(BuildContext context, String detail) {
  showAppSheet<void>(
    context,
    title: 'Details',
    builder: (sheet) => SelectableText(detail.trim(), style: codeStyle(sheet.colors.text, size: 12)),
  );
}
