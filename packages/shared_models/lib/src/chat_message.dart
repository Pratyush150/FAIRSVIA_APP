import 'package:equatable/equatable.dart';

/// A single in-trip chat message between the rider and their driver.
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.tripId,
    required this.from,
    required this.text,
    required this.ts,
  });

  final String id;
  final String tripId;

  /// Sender user id. Compare with the local user id to align the bubble.
  final String from;
  final String text;

  /// Epoch milliseconds.
  final int ts;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        tripId: json['tripId'] as String? ?? '',
        from: json['from'] as String? ?? '',
        text: json['text'] as String? ?? '',
        ts: (json['ts'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [id, tripId, from, text, ts];
}
