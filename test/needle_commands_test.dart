import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/core/needle_service.dart';

void main() {
  final n = NeedleService.instance;
  String? cmd(String tool, Map<String, dynamic> args, {bool alpine = true}) =>
      n.buildCommand(tool, args, alpine);

  test('maps common requests to the expected commands', () {
    expect(cmd('install_package', {'name': 'node'}), 'apk add nodejs npm');
    expect(cmd('find_files', {'type': 'python'}), "find . -type f -name '*.py'");
    expect(cmd('find_files', {'type': 'pdf'}), "find . -type f -name '*.pdf'");
    expect(cmd('find_files', {'type': 'config'}), "find . -iname '*config*'");
    expect(cmd('run_script', {'script': 'dev'}), 'npm run dev');
    expect(cmd('git_clone', {'url': 'https://github.com/a/b'}), 'git clone https://github.com/a/b');
    expect(cmd('find_big_files', {'path': 'Download'}),
        'du -ah Download 2>/dev/null | sort -rh | head -20');
  });

  test('quotes arguments so model output cannot inject shell syntax', () {
    expect(cmd('git_commit', {'message': "it's done; rm -rf ~"}),
        "git add -A && git commit -m 'it'\\''s done; rm -rf ~'");
    expect(cmd('search_text', {'query': r'$(reboot)'}), r"grep -rn '$(reboot)' .");
    expect(cmd('change_directory', {'path': 'my dir`id`'}), "cd 'my dir`id`'");
  });

  test('refuses calls it cannot turn into a safe command', () {
    expect(cmd('install_package', {'name': 'git'}, alpine: false), isNull);
    expect(cmd('git_commit', {'message': ''}), isNull);
    expect(cmd('unknown_tool', {}), isNull);
  });
}
