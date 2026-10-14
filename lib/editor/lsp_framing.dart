import 'dart:convert';
import 'dart:typed_data';

/// A JSON-RPC message with its LSP header (`Content-Length: <bytes>`).
List<int> encodeLspMessage(String json) {
  final body = utf8.encode(json);
  return [...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
}

/// Splits a language server's output into messages. Lengths are in bytes,
/// so the stream is buffered as bytes and only whole bodies are decoded.
class LspReader {
  LspReader(this._onMessage);

  final void Function(String json) _onMessage;
  final _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  void add(List<int> chunk) {
    _buffer.add(_pending);
    _buffer.add(chunk);
    var data = _buffer.takeBytes();
    var start = 0;
    while (true) {
      final headerEnd = _indexOf(data, const [13, 10, 13, 10], start);
      if (headerEnd < 0) break;
      final length = _contentLength(ascii.decode(data.sublist(start, headerEnd), allowInvalid: true));
      final bodyStart = headerEnd + 4;
      if (length == null) {
        start = bodyStart; // malformed header: skip it
        continue;
      }
      if (data.length - bodyStart < length) break;
      _onMessage(utf8.decode(data.sublist(bodyStart, bodyStart + length), allowMalformed: true));
      start = bodyStart + length;
    }
    _pending = Uint8List.sublistView(data, start);
  }

  static int? _contentLength(String header) {
    for (final line in header.split('\r\n')) {
      final i = line.indexOf(':');
      if (i > 0 && line.substring(0, i).trim().toLowerCase() == 'content-length') {
        return int.tryParse(line.substring(i + 1).trim());
      }
    }
    return null;
  }

  static int _indexOf(Uint8List data, List<int> pattern, int from) {
    outer:
    for (var i = from; i <= data.length - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
