class GymNewsItem {
  const GymNewsItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.imageUrl,
    required this.tag,
    required this.createdAt,
    required this.createdBy,
  });

  final String id;
  final String title;
  final String summary;
  final String imageUrl;
  final String tag;
  final DateTime createdAt;
  final String createdBy;

  factory GymNewsItem.fromMap(Map<String, dynamic> map) {
    final createdRaw = map['created_at']?.toString();
    final parsedDate = DateTime.tryParse(createdRaw ?? '');

    return GymNewsItem(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      summary: (map['summary'] ?? '').toString(),
      imageUrl: (map['image_url'] ?? '').toString(),
      tag: (map['tag'] ?? '').toString(),
      createdAt: parsedDate ?? DateTime.now(),
      createdBy: (map['created_by'] ?? '').toString(),
    );
  }
}
