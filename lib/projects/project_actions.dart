import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/navigation.dart';
import '../app/services.dart';
import '../phone/phone_files.dart';
import '../platform/android_env.dart';
import '../shared/action_sheet.dart';
import '../shared/folder_picker.dart';
import '../shared/form.dart';
import '../shared/format.dart';
import '../shared/name_dialog.dart';
import 'project.dart';

/// A project's actions, from its card on Projects and from its workspace:
/// open, rename, copy to the phone, remove from the list, delete.
void showProjectActions(BuildContext context, Project p, {bool showOpen = true}) {
  final s = context.services;
  showActionSheet(context, title: p.name, actions: [
    if (showOpen) SheetAction(Icons.open_in_new_rounded, 'Open', () => s.showProject(p), accent: true),
    SheetAction(Icons.drive_file_rename_outline_rounded, 'Rename', () async {
      final name = await showNameDialog(context, title: 'Rename project', action: 'Rename', initial: p.name);
      if (name != null) await s.projects.rename(p, name);
    }),
    SheetAction(Icons.smartphone_rounded, 'Copy to phone', () => _export(context, p)),
    null,
    SheetAction(Icons.playlist_remove_rounded, 'Remove from projects', () => _remove(context, p)),
    SheetAction(Icons.delete_outline_rounded, 'Delete project and files', () => _delete(context, p), danger: true),
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
  messenger.showSnackBar(const SnackBar(content: Text('Copying to phone…')));
  try {
    await s.phone.exportTo([s.linux.hostPath(p.path)], PhonePath.parse(folder.path)!);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Copied to ${folder.name}')));
  } on PlatformException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Couldn\'t copy')));
  }
}

/// Leaves the list; its folder stays and its terminals move to the Terminal tab.
Future<void> _remove(BuildContext context, Project p) async {
  final s = context.services;
  final ok = await confirmAction(context,
      title: 'Remove “${p.name}”?',
      message: 'Its folder ${shortPath(p.path)} stays as it is.',
      action: 'Remove');
  if (!ok) return;
  _leave(s, p);
  await s.projects.remove(p);
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

/// "Open a folder": one in Linux, or one on the phone.
void showOpenFolder(BuildContext context) {
  showActionSheet(context, title: 'Open a folder', actions: [
    SheetAction(Icons.terminal_rounded, 'Folder in Linux', () => openLinuxFolderAsProject(context)),
    SheetAction(Icons.smartphone_rounded, 'Folder on phone', () => openPhoneFolderAsProject(context)),
  ]);
}

Future<void> openLinuxFolderAsProject(BuildContext context) async {
  final s = context.services;
  final path = await pickLinuxFolder(context, title: 'Open a folder', action: 'Open');
  if (path == null) return;
  s.showProject(await s.projectService.openExisting(path));
}

/// A project from phone storage: worked on where it is (with all-files
/// access, Linux sees the phone at /sdcard), or copied into Linux, where
/// every tool works (phone storage has no symlinks or executables).
Future<void> openPhoneFolderAsProject(BuildContext context) async {
  var allFiles = false;
  try {
    allFiles = await AndroidEnv.storageAccess();
  } catch (_) {}
  if (!context.mounted) return;
  showActionSheet(context, title: 'Folder on phone', actions: [
    if (allFiles) SheetAction(Icons.smartphone_rounded, 'Open in place', () => _openInPlace(context), accent: true),
    SheetAction(Icons.download_rounded, 'Copy into Linux', () => _copyIn(context), accent: !allFiles),
    if (!allFiles) SheetAction(Icons.folder_open_rounded, 'Allow all files to open in place', AndroidEnv.requestStorageAccess),
  ]);
}

Future<void> _openInPlace(BuildContext context) async {
  final s = context.services;
  final path = await pickLinuxFolder(context, title: 'Folder on phone', start: '/sdcard', action: 'Open');
  if (path == null) return;
  s.showProject(await s.projectService.openExisting(path));
}

Future<void> _copyIn(BuildContext context) async {
  final s = context.services;
  final messenger = ScaffoldMessenger.of(context);
  final folder = await s.phone.pickFolder(keep: false);
  if (folder == null) return;
  messenger.showSnackBar(SnackBar(content: Text('Copying ${folder.name}…')));
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
