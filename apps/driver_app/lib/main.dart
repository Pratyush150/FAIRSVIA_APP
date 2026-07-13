import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  runGuarded(() async {
    await configureCoreDependencies();
    runApp(const DriverApp());
  });
}
