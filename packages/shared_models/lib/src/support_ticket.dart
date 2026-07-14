import 'package:equatable/equatable.dart';

/// One message in a support-ticket thread.
class SupportMessage extends Equatable {
  const SupportMessage({
    required this.id,
    required this.authorRole,
    required this.body,
    this.createdAt,
  });

  final String id;

  /// 'user' (the rider/driver) or 'admin' (support agent).
  final String authorRole;
  final String body;
  final DateTime? createdAt;

  bool get isFromAdmin => authorRole == 'admin';

  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
        id: json['id'] as String,
        authorRole: json['authorRole'] as String? ?? 'user',
        body: json['body'] as String? ?? '',
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)?.toLocal()
            : null,
      );

  @override
  List<Object?> get props => [id, authorRole, body, createdAt];
}

/// A support ticket. [messages] is populated only when fetching a single
/// ticket's thread; the list view leaves it empty.
class SupportTicket extends Equatable {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    this.tripId,
    this.createdAt,
    this.updatedAt,
    this.messages = const [],
  });

  final String id;
  final String subject;
  final String category;

  /// 'open' | 'active' | 'resolved' | 'closed'.
  final String status;
  final String? tripId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<SupportMessage> messages;

  bool get isClosed => status == 'closed';

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        id: json['id'] as String,
        subject: json['subject'] as String? ?? '',
        category: json['category'] as String? ?? 'other',
        status: json['status'] as String? ?? 'open',
        tripId: json['tripId'] as String?,
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)?.toLocal()
            : null,
        updatedAt: json['updatedAt'] is String
            ? DateTime.tryParse(json['updatedAt'] as String)?.toLocal()
            : null,
        messages: (json['messages'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SupportMessage.fromJson)
            .toList(),
      );

  @override
  List<Object?> get props =>
      [id, subject, category, status, tripId, createdAt, updatedAt, messages];
}
