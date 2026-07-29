enum CoupleRequestStatus { pending, accepted, rejected, cancelled, unknown }

CoupleRequestStatus _parseStatus(String? raw) {
  switch (raw) {
    case 'pending':
      return CoupleRequestStatus.pending;
    case 'accepted':
      return CoupleRequestStatus.accepted;
    case 'rejected':
      return CoupleRequestStatus.rejected;
    case 'cancelled':
      return CoupleRequestStatus.cancelled;
    default:
      return CoupleRequestStatus.unknown;
  }
}

class CoupleRequest {
  final String id;
  final String fromUserId;
  final String fromEmail;
  final String toUserId;
  final String toEmail;
  final String toCode;
  final DateTime? proposedStartedAt;
  final String? message;
  final CoupleRequestStatus status;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  const CoupleRequest({
    required this.id,
    required this.fromUserId,
    required this.fromEmail,
    required this.toUserId,
    required this.toEmail,
    required this.toCode,
    this.proposedStartedAt,
    this.message,
    required this.status,
    this.createdAt,
    this.respondedAt,
  });

  factory CoupleRequest.fromJson(Map<String, dynamic> json) {
    DateTime? date(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return CoupleRequest(
      id: (json['id'] ?? json['_id']).toString(),
      fromUserId: json['from_user_id']?.toString() ?? '',
      fromEmail: json['from_email']?.toString() ?? '',
      toUserId: json['to_user_id']?.toString() ?? '',
      toEmail: json['to_email']?.toString() ?? '',
      toCode: json['to_code']?.toString() ?? '',
      proposedStartedAt: date(json['proposed_started_at']),
      message: json['message'] as String?,
      status: _parseStatus(json['status'] as String?),
      createdAt: date(json['created_at']),
      respondedAt: date(json['responded_at']),
    );
  }
}
