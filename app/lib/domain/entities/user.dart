class User {
  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final String? coupleId;
  final String? currentStatus;
  final DateTime? coupleStartedAt;

  const User({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.coupleId,
    this.currentStatus,
    this.coupleStartedAt,
  });

  /// User-facing name: prefers `displayName`, falls back to the local-part of
  /// the email so we never render an empty bond graphic label.
  String get prettyName {
    final n = (displayName ?? '').trim();
    if (n.isNotEmpty) return n;
    return email.split('@').first;
  }

  User copyWith({
    String? displayName,
    String? avatarUrl,
    String? coupleId,
    String? currentStatus,
    DateTime? coupleStartedAt,
  }) => User(
    id: id,
    email: email,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    coupleId: coupleId ?? this.coupleId,
    currentStatus: currentStatus ?? this.currentStatus,
    coupleStartedAt: coupleStartedAt ?? this.coupleStartedAt,
  );

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: (json['_id'] ?? json['id']).toString(),
    email: json['email'] as String? ?? '',
    displayName: json['display_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    coupleId: json['couple_id'] as String?,
    currentStatus: json['current_status'] as String?,
    coupleStartedAt: json['couple_started_at'] != null
        ? DateTime.tryParse(json['couple_started_at'].toString())
        : null,
  );
}
