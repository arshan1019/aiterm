import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/navigation.dart';
import '../app/services.dart';
import '../phone/phone_files.dart';
import '../shared/action_sheet.dart';
import '../shared/folder_picker.dart';
import '../shared/form.dart';
import '../shared/format.dart';
import '../shared/name_dialog.dart';
import 'project.dart';
import '../app/icons.dart';

/// A project's actions, from its card on Projects and from its workspace:
/// open, rename, copy to the phone, remove from the list, delete.
void showProjectActions(BuildContext context, Project p, {bool showOpen = true}) {
  final s = context.services;
  showActionSheet(context, title: p.name, actions: [
    if (showOpen) SheetAction(AppIcons.openInNew, 'Open', () => s.showProject(p), accent: true),
    SheetAction(AppIcons.rename, 'Rename', () async {
      final name = await showNameDialog(context, title: 'Rename project', action: 'Rename', initial: p.name);
      if (name != null) await s.projects.rename(p, name);
    }),
    if (!onPhoneStorage(p.path)) SheetAction(AppIcons.exportFile, 'Export to phone', () => _export(context, p)),
    null,
    SheetAction(AppIcons.removeFromList, 'Remove from projects', () => _remove(context, p)),
    SheetAction(AppIcons.delete, 'Delete project and files', () => _delete(context, p), danger: true),
  ]);
}

/// Leaves the project's workspace if it's open (it's going away).
void _leave(AppServices s, Project p) {
  if (s.navigation.openProject?.id == p.id) s.navigation.open(AppTab.projects);
}

/// Copies the project folder to a phone folder the user picks.
Future<void> _export(BuildContext context, Project p) async {
  final s = context.services;
  final messenger = ScaffoldMessenger.of(context);
  final folder = await s.phone.pickFolder(keep: false);
  if (folder == null) return;
  messenger.showSnackBar(const SnackBar(content: Text('Exporting…')));
  try {
    await s.phone.exportTo([s.linux.hostPath(p.path)], PhonePath.parse(folder.path)!);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Exported to ${folder.name}')));
  } on PlatformException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Couldn\'t copy')));
  }
}

/// Leaves the list right away, with Undo (it's reversible, so no
/// "Are you sure?"); the folder stays and its terminals move to the
/// Terminal tab.
Future<void> _remove(BuildContext context, Project p) async {
  final s = context.services;
  final messenger = ScaffoldMessenger.of(context);
  _leave(s, p);
  await s.projects.remove(p);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text('Removed ${p.name}'),
    action: SnackBarAction(label: 'Undo', onPressed: () => s.projects.restore(p)),
  ));
}

Future<void> _delete(BuildContext context, Project p) async {
  final s = context.services;
  final ok = await confirmAction(context,
      title: 'Delete “${p.name}”?',
      message: 'The folder ${shortPath(p.path)} and everything in it, including unpushed commits, will be deleted. '
          'This can\'t be undone.',
      action: 'Delete',
      danger: true);
  if (!ok) return;
  _leave(s, p);
  for (final t in s.tabs.inScope(p.path)) {
    s.tabs.close(t);
  }
  await s.projects.remove(p);
  try {
    await Directory(s.linux.hostPath(p.path)).delete(recursive: true);
  } on FileSystemException catch (_) {}
}

Future<void> openLinuxFolderAsProject(BuildContext context) async {
  final s = context.services;
  final messenger = ScaffoldMessenger.of(context);
  final path = await pickLinuxFolder(context, title: 'Open a folder', action: 'Open');
  if (path == null) return;
  if (onPhoneStorage(path)) {
    messenger.showSnackBar(const SnackBar(content: Text('That folder is on phone storage. Use Import from phone.')));
    return;
  }
  s.showProject(await s.projectService.openExisting(path));
}

/// Copies a phone folder (picked with Android's picker) into Linux, where
/// every tool works, and opens it. The phone copy stays as it was; Export to
/// phone sends the project back.
Future<void> importProjectFromPhone(BuildContext context) async {
  final s = context.services;
  final messenger = ScaffoldMessenger.of(context);
  final folder = await s.phone.pickFolder(keep: false);
  if (folder == null) return;
  messenger.showSnackBar(SnackBar(content: Text('Importing ${folder.name}…')));
  try {
    final parent = s.linux.hostPath(projectsFolder);
    await Directory(parent).create(recursive: true);
    final copied = await s.phone.importTo([PhonePath.parse(folder.path)!], parent);
    messenger.hideCurrentSnackBar();
    if (copied.isEmpty) return;
    s.showProject(await s.projectService.openExisting(s.linux.guestPath(copied.single), name: folder.name));
  } on PlatformException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Couldn\'t copy')));
  }
}
