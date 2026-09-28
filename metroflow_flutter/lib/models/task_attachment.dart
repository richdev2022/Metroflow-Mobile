/// A file attached to a task (POST /tasks/:id/attachments, GET
/// /tasks/:id/attachments and the `attachments` array now embedded on every
/// task returned by GET /tasks + the board endpoint).
///
/// Server shape: `{ id, fileName, fileType, fileSize, fileUrl, isImage,
/// uploadedBy, uploadedByName?, createdAt }`. Parsing is deliberately
/// tolerant: null/missing fields never throw, and legacy key variants
/// (`name`/`url`/`type`) are accepted so older cached payloads keep parsing.
class TaskAttachment {
  final String id;
  final String fileName;
  final String fileType;
  final num fileSize;
  final String fileUrl;
  final bool isImage;
  final String uploadedBy;
  final String? uploadedByName;
  final String createdAt;

  const TaskAttachment({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.fileUrl,
    required this.isImage,
    required this.uploadedBy,
    this.uploadedByName,
    required this.createdAt,
  });

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    String asString(dynamic v) => v == null ? '' : v.toString();
    return TaskAttachment(
      id: asString(json['id']),
      fileName: asString(json['fileName'] ?? json['name']),
      fileType: asString(json['fileType'] ?? json['type'] ?? json['mimeType']),
      fileSize: (json['fileSize'] is num)
          ? json['fileSize'] as num
          : num.tryParse('${json['fileSize']}') ?? 0,
      fileUrl: asString(json['fileUrl'] ?? json['url']),
      isImage: (json['isImage'] as bool?) ?? false,
      uploadedBy: asString(json['uploadedBy'] ?? json['uploaded_by']),
      uploadedByName: (json['uploadedByName'] ?? json['uploaded_by_name'])
              ?.toString(),
      createdAt: asString(json['createdAt'] ?? json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'fileUrl': fileUrl,
      'isImage': isImage,
      'uploadedBy': uploadedBy,
      'uploadedByName': uploadedByName,
      'createdAt': createdAt,
    };
  }

  /// Best-effort display name: fileName, else the URL's last path segment.
  String get displayName {
    if (fileName.trim().isNotEmpty) return fileName.trim();
    if (fileUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(fileUrl);
        final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
        final decoded = Uri.decodeComponent(last);
        if (decoded.isNotEmpty) return decoded;
      } catch (_) {}
    }
    return 'Attachment';
  }
}
