// ignore_for_file: avoid_print, avoid_relative_lib_imports
// End-to-end smoke test of the Flutter networking layer against the live
// backend. Runs on the Dart VM (no Flutter deps), so it can drive the real
// AuthRemoteDataSource without an emulator.
//
//   dart run tool/backend_smoke.dart [baseUrl]
//
// Requires the backend running (cd infra && docker compose up -d).
import 'package:dio/dio.dart';

import '../lib/src/auth/auth_remote_data_source.dart';

Future<void> main(List<String> args) async {
  final baseUrl =
      args.isNotEmpty ? args.first : 'http://localhost:3000/api/v1';
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));
  final ds = AuthRemoteDataSource(dio);

  // Unique phone per run so we exercise first-login user creation.
  final phone = '+9199${DateTime.now().millisecondsSinceEpoch % 100000000}';
  print('› base=$baseUrl phone=$phone');

  final otp = await ds.requestOtp(phone);
  print('✓ requestOtp  devCode=${otp.devCode}');
  if (otp.devCode == null) {
    throw StateError('Backend did not return a devCode — is it in dev mode?');
  }

  final session = await ds.verifyOtp(phone, otp.devCode!);
  print('✓ verifyOtp   user=${session.user.phone} '
      'accessLen=${session.tokens.accessToken.length}');

  // Attach the token and read the profile back.
  dio.options.headers['Authorization'] =
      'Bearer ${session.tokens.accessToken}';
  final me = await ds.getMe();
  print('✓ getMe       phone=${me.phone} role=${me.role} id=${me.id}');

  if (me.phone != phone) {
    throw StateError('getMe returned the wrong user');
  }
  print('SMOKE OK — Flutter client ↔ backend verified end-to-end');
}
