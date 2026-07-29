class Post {
  final String id;
  final String title;
  final String description;
  final List<String> mediaUrls;
  final List<String> tags;
  final String authorId;
  final DateTime createdAt;
  final int commentCount;

  const Post({
    required this.id,
    required this.title,
    required this.description,
    required this.mediaUrls,
    required this.tags,
    required this.authorId,
    required this.createdAt,
    this.commentCount = 0,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['_id'] ?? json['id'],
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    mediaUrls: List<String>.from(json['media_urls'] ?? const []),
    tags: List<String>.from(json['tags'] ?? const []),
    authorId: json['author_id'],
    createdAt: DateTime.parse(json['created_at']),
    commentCount: json['comment_count'] ?? 0,
  );
}
