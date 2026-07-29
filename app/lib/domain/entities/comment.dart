class Comment {
  final String id;
  final String postId;
  final String authorId;
  final String text;
  final DateTime createdAt;

  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: json['_id'] ?? json['id'],
    postId: json['post_id'],
    authorId: json['author_id'],
    text: json['text'],
    createdAt: DateTime.parse(json['created_at']),
  );
}
