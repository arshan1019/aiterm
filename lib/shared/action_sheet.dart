import 'package:flutter/material.dart';
import '../app/theme.dart';
import 'sheet.dart';

/// One row of an [showActionSheet].
class SheetAction {
  const SheetAction(this.icon, this.label, this.onTap, {this.danger = false, this.accent = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool accent;
}

/// The app's one action menu: a bottom sheet titled with what it acts on,
/// groups separated by dividers (pass `null` between them), scrolling
/// when long. The sheet closes before the chosen action runs.
Future<void> showActionSheet(BuildContext context, {required String title, required List<SheetAction?> actions}) =>
    showAppSheet<void>(
      context,
      title: title,
      inset: false,
      builder: (sheet) {
        final c = sheet.colors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              if (a == null)
                Divider(height: 8, color: c.border)
              else
                ListTile(
                  leading: Icon(a.icon, size: 20, color: a.danger ? c.danger : (a.accent ? c.accent : c.textMuted)),
                  title: Text(a.label, style: TextStyle(fontSize: 14, color: a.danger ? c.danger : c.text)),
                  onTap: () {
                    Navigator.pop(sheet);
                    a.onTap();
                  },
                ),
          ],
        );
      },
    );
