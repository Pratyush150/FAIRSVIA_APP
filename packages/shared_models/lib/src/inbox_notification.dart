import 'package:equatable/equatable.dart';

/// A persisted in-app notification (the inbox).
class InboxNotification extends Equatable {
  const InboxNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.read,
    this.kind,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final bool read;
  final String? kind;
  final DateTime? createdAt;

  factory InboxNotification.fromJson(Map<String, dynamic> json) =>
      InboxNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        read: json['read'] as bool? ?? false,
        kind: json['kind'] as String?,
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)?.toLocal()
            : null,
      );

  @override
  List<Object?> get props => [id, title, body, read, kind, createdAt];
}
