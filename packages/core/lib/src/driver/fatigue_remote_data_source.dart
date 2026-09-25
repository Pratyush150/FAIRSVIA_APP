import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// Where the driver stands against the fatigue limit
/// (`GET /drivers/me/fatigue`). The rule (Uber's): online time adds up across
/// sessions and resets only after one continuous break of [restBreakSeconds]
/// (6 h by default); at [limitSeconds] (12 h) the driver must rest.
class FatigueStatus {
  const FatigueStatus({
    required this.onlineSeconds,
    required this.limitSeconds,
    required this.remainingSeconds,
    required this.warnAtSeconds,
    required this.restBreakSeconds,
    this.online = false,
    this.overLimit = false,
    this.resting = false,
    this.restSecondsLeft = 0,
    this.restUntil,
  });

  final int onlineSeconds;
  final int limitSeconds;
  final int remainingSeconds;
  final int warnAtSeconds;
  final int restBreakSeconds;
  final bool online;
  final bool overLimit;

  /// Offline and still inside the required break: going online is refused.
  final bool resting;
  final int restSecondsLeft;
  final DateTime? restUntil;

  /// Inside the last stretch before the limit (30 min by default).
  bool get nearLimit => !overLimit && onlineSeconds >= warnAtSeconds;

  factory FatigueStatus.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.round() ?? 0;
    return FatigueStatus(
      onlineSeconds: n('onlineSeconds'),
      limitSeconds: n('limitSeconds'),
      remainingSeconds: n('remainingSeconds'),
      warnAtSeconds: n('warnAtSeconds'),
      restBreakSeconds: n('restBreakSeconds'),
      online: j['online'] == true,
      overLimit: j['overLimit'] == true,
      resting: j['resting'] == true,
      restSecondsLeft: n('restSecondsLeft'),
      restUntil: j['restUntil'] is String
          ? DateTime.tryParse(j['restUntil'] as String)?.toLocal()
          : null,
    );
  }

  /// "9h 40m", "12h", "25m" — compact, for the online-time line.
  static String hm(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

/// `/drivers/me/fatigue`.
class FatigueRemoteDataSource {
  FatigueRemoteDataSource(this._dio);

  final Dio _dio;

  Future<FatigueStatus> get() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/drivers/me/fatigue');
      return FatigueStatus.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
