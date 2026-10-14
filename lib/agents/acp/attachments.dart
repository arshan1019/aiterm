import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../app/services.dart';
import '../../phone/phone_files.dart';
import 'agent_chat.dart';

/// Where files sent to agents are copied, in Linux: outside the project so
/// git stays clean; the agent copies one in when asked.
const attachmentsDir = '/root/.cache/aiterm/attachments';

/// Images past this go to the agent scaled down (the API caps images at
/// 5 MB, base64 adds a third).
const _maxImageBytes = 3500000;

const _imageTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'bmp': 'image/bmp',
};

/// Picks files on the phone (the system picker: photos, downloads, Drive…)
/// and copies them into Linux for a message.
Future<List<ChatAttachment>> pickAttachments(AppServices s) async {
  final items = await s.phone.pickFiles(keep: false);
  if (items.isEmpty) return const [];
  final host = s.linux.hostPath(attachmentsDir);
  await Directory(host).create(recursive: true);
  final copied = await s.phone.importTo([for (final i in items) ?PhonePath.parse(i.path)], host);
  return [for (final path in copied) await attachmentFor(File(path), guestPath: s.linux.guestPath(path))];
}

/// [file] as an attachment; images get their (possibly scaled) data.
Future<ChatAttachment> attachmentFor(File file, {required String guestPath}) async {
  final name = file.uri.pathSegments.last;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  final type = _imageTypes[ext];
  final image = type == null ? null : await _imageData(file, type);
  return ChatAttachment(
    name: name,
    path: guestPath,
    hostPath: file.path,
    imageData: image?.$1,
    mimeType: image?.$2 ?? type,
  );
}

/// The image as base64 the agent takes: as is when small and in a format
/// models read (PNG, JPEG, GIF, WebP), else re-encoded as PNG, scaled to
/// 1568px on the long side (the size Claude recommends), or 1024px if that
/// is still too big. Null when it can't be decoded: it goes as a file.
Future<(String, String)?> _imageData(File file, String type) async {
  try {
    final bytes = await file.readAsBytes();
    const direct = {'image/png', 'image/jpeg', 'image/gif', 'image/webp'};
    if (direct.contains(type) && bytes.length <= _maxImageBytes) return (base64Encode(bytes), type);
    for (final edge in const [1568, 1024]) {
      final png = await _scaledPng(bytes, edge);
      if (png != null && png.length <= _maxImageBytes) return (base64Encode(png), 'image/png');
    }
  } catch (_) {
    // Unreadable or undecodable.
  }
  return null;
}

Future<Uint8List?> _scaledPng(Uint8List bytes, int edge) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final long = descriptor.width > descriptor.height ? descriptor.width : descriptor.height;
  final scale = long > edge ? edge / long : 1.0;
  final codec = await descriptor.instantiateCodec(
    targetWidth: (descriptor.width * scale).round(),
    targetHeight: (descriptor.height * scale).round(),
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return data?.buffer.asUint8List();
}
