import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/core/error_fixes.dart';

void main() {
  String? fix(String out, {bool alpine = true}) => detectFix(out, alpine: alpine)?.command;

  test('node and python missing modules', () {
    expect(fix("Error: Cannot find module 'express'\nRequire stack:"), 'npm install express');
    expect(fix("Error: Cannot find module '@vitejs/plugin-react/dist/x.js'"), 'npm install @vitejs/plugin-react');
    expect(fix("Error: Cannot find module './routes'"), isNull);
    expect(fix("ModuleNotFoundError: No module named 'requests'"),
        'pip install --break-system-packages requests');
    expect(fix("ModuleNotFoundError: No module named 'cv2'", alpine: false), 'pip install opencv-python');
  });

  test('missing commands in each shell', () {
    expect(fix('sh: rg: not found'), 'apk add ripgrep');
    expect(fix('bash: python: command not found'), 'apk add python3');
    expect(fix('zsh: command not found: jq'), 'apk add jq');
    expect(fix('/bin/sh: line 1: gcc: not found'), 'apk add gcc');
    expect(fix('sh: claude: not found'), 'install-claude && claude');
    expect(fix('Error: claude native binary not installed.\nEither postinstall did not run'),
        'install-claude && claude');
    expect(fix('sh: rg: not found', alpine: false), isNull);
  });

  test('permissions, ports and git', () {
    expect(fix('sh: ./run.sh: Permission denied'), 'chmod +x ./run.sh && ./run.sh');
    expect(fix('Error: listen EADDRINUSE: address already in use :::3000'), 'fuser -k 3000/tcp');
    expect(fix('fatal: not a git repository (or any of the parent directories): .git'), 'git init');
    expect(fix('fatal: The current branch main has no upstream branch.'), 'git push -u origin HEAD');
    expect(detectFix('*** Please tell me who you are.', alpine: true)?.needsInput, isTrue);
  });

  test('ignores ANSI colours and picks the newest error', () {
    final out = "sh: rg: not found\n\x1B[31mError: Cannot find module 'lodash'\x1B[0m\n\$ ";
    expect(fix(out), 'npm install lodash');
  });

  test('no false positives on normal output', () {
    expect(fix('added 52 packages in 3s\n\$ '), isNull);
    expect(fix('total 12\ndrwxr-xr-x 2 root root 4096 src\n'), isNull);
    expect(fix('grep: not found in this text, just words'), isNull);
  });
}
