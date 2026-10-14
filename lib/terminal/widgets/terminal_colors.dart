import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/theme.dart';

/// The terminal's colors: the app's, or the dark ones in the light theme
/// when "Always dark terminal" is on, on pure black when "Black terminal"
/// is on and it's dark (OLED screens).
class TerminalColors extends StatelessWidget {
  const TerminalColors({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    return ListenableBuilder(
      listenable: s.settings,
      builder: (context, _) {
        var theme = Theme.of(context);
        if (s.settings.darkTerminal && theme.brightness == Brightness.light) theme = s.theme(dark: true);
        if (s.settings.blackTerminal && theme.brightness == Brightness.dark) {
          final c = theme.extension<AppColors>()!.copyWith(bg: Colors.black);
          theme = theme.copyWith(scaffoldBackgroundColor: c.bg, canvasColor: c.bg, extensions: [c]);
        }
        // Always wrapped, so switching keeps the terminal's state.
        return Theme(data: theme, child: child);
      },
    );
  }
}
