import 'package:flutter/material.dart';
import '../app/theme.dart';

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
Future<void> showActionSheet(BuildContext context, {required String title, required List<SheetAction?> actions}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.colors;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.8),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
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
          ),
        ),
      );
    },
  );
}
