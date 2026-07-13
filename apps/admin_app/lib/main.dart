import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/admin_api.dart';

Future<void> main() async {
  runGuarded(() async {
    await configureCoreDependencies();
    // Admin-only data source, layered on the shared authenticated Dio.
    sl.registerSingleton<AdminApi>(
      AdminApi(sl<DioClient>().authenticatedDio),
    );
    runApp(const AdminApp());
  });
}
