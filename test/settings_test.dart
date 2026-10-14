import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/settings/settings.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('settings'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Settings> loadWith(Map<String, Object?> json) async {
    File('${dir.path}/settings.json').writeAsStringSync(jsonEncode(json));
    return Settings.load(dir.path);
  }

  test('a new install follows the system theme, everything else off', () async {
    final s = await Settings.load(dir.path);
    expect(s.theme, ThemeChoice.system);
    expect([s.wallpaperColors, s.blackTerminal, s.darkTerminal, s.compact, s.highContrast, s.blocks, s.showThinking],
        everyElement(isFalse));
    expect(s.blocksFor('claude'), isFalse); // agents keep their own UI by default
  });

  test('the old dark switch carries over as a theme choice', () async {
    expect((await loadWith({'dark': true})).theme, ThemeChoice.dark);
    expect((await loadWith({'dark': false})).theme, ThemeChoice.light);
  });

  test('appearance choices survive a restart', () async {
    final s = await Settings.load(dir.path);
    s
      ..theme = ThemeChoice.light
      ..wallpaperColors = true
      ..blackTerminal = true
      ..darkTerminal = true
      ..compact = true
      ..highContrast = true
      ..blocks = true
      ..showThinking = true;
    s.setBlocksFor('codex', false);
    s.setAgentOption('claude', 'mode', 'acceptEdits');
    await s.saved;
    final again = await Settings.load(dir.path);
    expect(again.theme, ThemeChoice.light);
    expect([again.wallpaperColors, again.blackTerminal, again.darkTerminal, again.compact, again.highContrast, again.showThinking],
        everyElement(isTrue));
    expect(again.blocksFor('claude'), isTrue);
    expect(again.blocksFor('codex'), isFalse);
    expect(again.agentOption('claude', 'mode'), 'acceptEdits');
  });
}
