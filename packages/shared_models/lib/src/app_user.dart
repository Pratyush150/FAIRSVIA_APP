import 'package:equatable/equatable.dart';

/// A platform user. `role` is one of `rider`, `driver`, `admin`.
///
/// Plain immutable value type (Equatable). We deliberately avoid code
/// generation here in Phase 0; freezed can be introduced later for the
/// trip-state unions where sealed unions carry their weight.
class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.phone,
    required this.role,
    this.email,
    this.fullName,
    this.photoUrl,
    this.ratingAvg = 5.0,
    this.ratingCount = 0,
  });

  final String id;
  final String phone;
  final String role;
  final String? email;
  final String? fullName;
  final String? photoUrl;
  final double ratingAvg;
  final int ratingCount;

  bool get isDriver => role == 'driver';
  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      phone: json['phone'] as String,
      role: json['role'] as String? ?? 'rider',
      email: json['email'] as String?,
      fullName: json['fullName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      ratingAvg: (json['ratingAvg'] as num?)?.toDouble() ?? 5.0,
      ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'role': role,
        'email': email,
        'fullName': fullName,
        'photoUrl': photoUrl,
        'ratingAvg': ratingAvg,
        'ratingCount': ratingCount,
      };

  AppUser copyWith({
    String? email,
    String? fullName,
    String? photoUrl,
  }) {
    return AppUser(
      id: id,
      phone: phone,
      role: role,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      photoUrl: photoUrl ?? this.photoUrl,
      ratingAvg: ratingAvg,
      ratingCount: ratingCount,
    );
  }

  @override
  List<Object?> get props =>
      [id, phone, role, email, fullName, photoUrl, ratingAvg, ratingCount];
}
