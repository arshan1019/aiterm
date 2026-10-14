import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:aiterm/editor/language_servers.dart';
import 'package:aiterm/editor/lsp_framing.dart';

void main() {
  group('LSP framing', () {
    test('messages are framed with their byte length (not characters)', () {
      const msg = '{"jsonrpc":"2.0","method":"x","params":{"t":"héllo ✓"}}';
      final framed = utf8.decode(encodeLspMessage(msg));
      expect(framed, 'Content-Length: ${utf8.encode(msg).length}\r\n\r\n$msg');
    });

    test('messages split across reads, and several in one read, come out whole', () {
      final out = <String>[];
      final reader = LspReader(out.add);
      const a = '{"id":1,"result":"ä"}';
      const b = '{"id":2,"result":null}';
      final bytes = [...encodeLspMessage(a), ...encodeLspMessage(b)];
      // Byte by byte, including through the middle of a UTF-8 character.
      for (final byte in bytes) {
        reader.add([byte]);
      }
      expect(out, [a, b]);
      out.clear();
      reader.add(bytes);
      expect(out, [a, b]);
    });

    test('extra headers are ignored', () {
      final out = <String>[];
      final reader = LspReader(out.add);
      reader.add(utf8.encode('Content-Length: 2\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n{}'));
      expect(out, ['{}']);
    });
  });

  group('language servers', () {
    test('files map to the LSP language and the server that handles it', () {
      expect(languageIdFor('src/app.tsx'), 'typescriptreact');
      expect(languageIdFor('main.py'), 'python');
      expect(languageIdFor('Makefile'), isNull);
      expect(serverFor('main.py')!.id, 'python');
      expect(serverFor('index.html')!.id, 'html');
      expect(serverFor('style.scss')!.id, 'css');
      expect(serverFor('run.sh')!.id, 'shell');
      expect(serverFor('notes.txt'), isNull);
    });

    test('every server installs with a script that stops at the first error', () {
      for (final s in languageServers) {
        expect(s.install, startsWith('set -e'), reason: s.id);
        expect(s.command, contains(s.binary), reason: s.id);
      }
    });
  });
}
