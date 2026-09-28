/// Result of POST /chat/media — the shared upload pipeline used for chat
/// attachments (images, videos, audio, documents, GIFs) and MetricAi image
/// context. Shape (backend `services/media-upload.ts`):
/// `{ url, name, filename, mimeType, size, attachmentType }`.
class ChatMediaUpload {
  final String url;
  final String? name;
  final String? filename;
  final String? mimeType;
  final int? size;
  final String? attachmentType;

  const ChatMediaUpload({
    required this.url,
    this.name,
    this.filename,
    this.mimeType,
    this.size,
    this.attachmentType,
  });

  factory ChatMediaUpload.fromJson(Map<String, dynamic> json) {
    final rawSize = json['size'];
    return ChatMediaUpload(
      url: (json['url'] ?? '').toString(),
      name: json['name']?.toString(),
      filename: (json['filename'] ?? json['name'])?.toString(),
      mimeType: json['mimeType']?.toString(),
      size: rawSize is num ? rawSize.toInt() : int.tryParse('$rawSize'),
      attachmentType: json['attachmentType']?.toString(),
    );
  }
}
