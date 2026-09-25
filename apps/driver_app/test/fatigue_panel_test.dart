import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/fatigue/fatigue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _h = 3600;

FatigueStatus _status({
  required int online,
  bool overLimit = false,
  bool resting = false,
  int restLeft = 0,
}) =>
    FatigueStatus(
      onlineSeconds: online,
      limitSeconds: 12 * _h,
      remainingSeconds: (12 * _h - online).clamp(0, 12 * _h),
      warnAtSeconds: 12 * _h - 30 * 60,
      restBreakSeconds: 6 * _h,
      online: !resting,
      overLimit: overLimit,
      resting: resting,
      restSecondsLeft: restLeft,
    );

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('shows "Online today: 9h 40m of 12h" and no warning', (t) async {
    await t.pumpWidget(_host(FatigueStatusBar(
      load: () async => _status(online: 9 * _h + 40 * 60),
    )));
    await t.pump();
    expect(find.text('Online today: 9h 40m of 12h'), findsOneWidget);
    expect(find.byType(FatigueWarningBanner), findsNothing);
    expect(find.byType(FatigueRestCard), findsNothing);
  });

  testWidgets('warning banner in the last 30 minutes', (t) async {
    await t.pumpWidget(_host(FatigueStatusBar(
      load: () async => _status(online: 11 * _h + 40 * 60),
    )));
    await t.pump();
    expect(find.byType(FatigueWarningBanner), findsOneWidget);
    expect(find.text('20m left before a 6h rest'), findsOneWidget);
  });

  testWidgets('over the limit mid-trip: "Driving limit reached"', (t) async {
    await t.pumpWidget(_host(FatigueStatusBar(
      load: () async => _status(online: 12 * _h + 60, overLimit: true),
    )));
    await t.pump();
    expect(find.text('Driving limit reached'), findsOneWidget);
  });

  testWidgets('locked out: rest card counts down and the rest screen opens',
      (t) async {
    FatigueStatus? locked;
    await t.pumpWidget(_host(FatigueStatusBar(
      load: () async => _status(
          online: 12 * _h, overLimit: true, resting: true, restLeft: 3725),
      onLocked: (s) => locked = s,
    )));
    await t.pump();
    expect(locked, isNotNull);
    expect(find.text('You can go online in 1:02:05'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(find.text('You can go online in 1:02:03'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // stop the timers
  });

  testWidgets('re-reads on a server fatigue event', (t) async {
    var online = 11 * _h;
    final events = StreamController<Map<String, dynamic>>.broadcast();
    await t.pumpWidget(_host(FatigueStatusBar(
      load: () async => _status(online: online),
      events: [events.stream],
    )));
    await t.pump();
    expect(find.byType(FatigueWarningBanner), findsNothing);
    online = 11 * _h + 45 * 60;
    events.add({'remainingSeconds': 900});
    await t.pump();
    await t.pump();
    expect(find.byType(FatigueWarningBanner), findsOneWidget);
    await events.close();
  });

  testWidgets('break reminder shows a non-blocking snackbar', (t) async {
    final reminders = StreamController<Map<String, dynamic>>.broadcast();
    await t.pumpWidget(_host(FatigueStatusBar(
      load: () async => _status(online: 4 * _h),
      reminders: reminders.stream,
    )));
    await t.pump();
    reminders.add({'sessionSeconds': 4 * _h + 60});
    await t.pump();
    expect(find.textContaining("You've been online 4h 1m straight"),
        findsOneWidget);
    await reminders.close();
  });

  testWidgets('rest page shows a big countdown', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: DriverRestPage(
        status: _status(
            online: 12 * _h, overLimit: true, resting: true, restLeft: 65),
      ),
    ));
    expect(find.text('01:05'), findsOneWidget);
    expect(find.text('Rest before your next ride'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('01:04'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
