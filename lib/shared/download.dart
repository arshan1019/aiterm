import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Downloads [url] to [dest], verifying its SHA-256. Writes to a `.part`
/// file and renames on success, so [dest] only ever holds a verified file.
/// [onProgress] gets 0..1, or null when the size is unknown or verifying.
Future<void> downloadVerified(
  Uri url,
  File dest, {
  required String sha256Hex,
  void Function(double? progress)? onProgress,
}) async {
  final part = File('${dest.path}.part');
  final client = http.Client();
  try {
    final resp = await client.send(http.Request('GET', url));
    if (resp.statusCode != 200) throw HttpException('Download failed: HTTP ${resp.statusCode}', uri: url);
    final total = resp.contentLength;
    var received = 0;
    final sink = part.openWrite();
    try {
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total == null ? null : received / total);
      }
    } finally {
      await sink.close();
    }
  } finally {
    client.close();
  }
  onProgress?.call(null);
  final actual = (await sha256.bind(part.openRead()).first).toString();
  if (actual != sha256Hex) {
    await part.delete();
    throw StateError('Checksum mismatch for ${url.pathSegments.last}');
  }
  await part.rename(dest.path);
}
