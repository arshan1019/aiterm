import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/app.dart';
import 'app/services.dart';

/// Map of the code (each folder is one feature):
///
///   app/        bootstrap, theme + motion tokens, navigation, home shell
///   platform/   method/event channels to the Android side
///   linux/      Alpine under proot (set up like Termux's proot-distro)
///   terminal/   sessions and tabs (models), terminal widgets
///   files/      file browser model and screens
///   assistant/  rules + Needle model, command templates, error fixes
///   settings/   persisted preferences and their screen
///   shared/     small reusable widgets and helpers
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Settings and paths load before the first frame (the native splash is
  // still up), so the app opens in the right theme with nothing popping in.
  final services = await AppServices.load();
  // The bundled fonts' licences (SIL OFL 1.1) on the licences page.
  LicenseRegistry.addLicense(() async* {
    for (final (font, file) in const [('IBM Plex Sans', 'IBMPlexSans-OFL.txt'), ('JetBrains Mono', 'JetBrainsMono-OFL.txt')]) {
      yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
  runApp(AiTermApp(services: services));
}
