class StatusMessage {
  final String authorId;
  final String text;
  final DateTime updatedAt;

  const StatusMessage({
    required this.authorId,
    required this.text,
    required this.updatedAt,
  });

  factory StatusMessage.fromJson(Map<String, dynamic> json) => StatusMessage(
    authorId: json['author_id'],
    text: json['text'] ?? '',
    updatedAt: DateTime.parse(json['updated_at']),
  );
}
