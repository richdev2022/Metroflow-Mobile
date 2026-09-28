/// A single GIF entry from GET /chat/gifs (Tenor proxy).
class GifObject {
  final String id;
  final String description;
  final String url;
  final String? previewUrl;

  const GifObject({
    required this.id,
    required this.description,
    required this.url,
    this.previewUrl,
  });

  factory GifObject.fromJson(Map<String, dynamic> json) {
    return GifObject(
      id: (json['id'] ?? '').toString(),
      description: (json['description'] ?? 'GIF').toString(),
      url: (json['url'] ?? '').toString(),
      previewUrl: json['previewUrl']?.toString(),
    );
  }
}

/// Response envelope of GET /chat/gifs:
/// `{ configured: bool, gifs: [...] }`. `configured == false` means the
/// server has no TENOR_API_KEY — clients hide the GIF tab.
class ChatGifsResult {
  final bool configured;
  final List<GifObject> gifs;

  const ChatGifsResult({required this.configured, required this.gifs});
}
