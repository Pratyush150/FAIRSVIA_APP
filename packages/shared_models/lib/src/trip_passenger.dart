import 'package:equatable/equatable.dart';

/// Who is actually travelling, when the ride was booked by somebody else.
///
/// The booker stays the account that pays and tracks the ride; this names the
/// person the driver collects. Null on an ordinary ride, where the two are the
/// same person.
///
/// The phone is required by the backend whenever a passenger is set, because
/// everything the passenger needs runs through it: the driver calls them, and
/// the start code is texted to them — they may never have installed the app.
class TripPassenger extends Equatable {
  const TripPassenger({required this.phone, this.name});

  /// Their name, if the booker gave one. A phone with no name is allowed.
  final String? name;

  /// Their number. Always present.
  final String phone;

  /// What to call them on screen when no name was given.
  String get displayName => (name == null || name!.trim().isEmpty)
      ? 'Your passenger'
      : name!.trim();

  static TripPassenger? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final phone = (raw['phone'] as String?)?.trim();
    if (phone == null || phone.isEmpty) return null;
    final name = (raw['name'] as String?)?.trim();
    return TripPassenger(
      phone: phone,
      name: (name == null || name.isEmpty) ? null : name,
    );
  }

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        'phone': phone,
      };

  @override
  List<Object?> get props => [name, phone];
}
