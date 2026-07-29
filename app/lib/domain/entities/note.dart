class Note {
  final String id;
  final String body;
  final String authorId;
  final DateTime createdAt;

  const Note({
    required this.id,
    required this.body,
    required this.authorId,
    required this.createdAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['_id'] ?? json['id'],
    body: json['body'],
    authorId: json['author_id'],
    createdAt: DateTime.parse(json['created_at']),
  );
}
