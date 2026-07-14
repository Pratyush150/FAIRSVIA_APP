import 'package:core/src/account/widgets/async_content.dart';
import 'package:core/src/network/api_exception.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows a spinner while the future is pending', (tester) async {
    await tester.pumpWidget(_host(AsyncContent<int>(
      load: () => Future.delayed(const Duration(seconds: 1), () => 1),
      builder: (_, _, _) => const Text('done'),
    )));
    await tester.pump(); // let the FutureBuilder subscribe
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('done'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('renders builder content once loaded', (tester) async {
    await tester.pumpWidget(_host(AsyncContent<String>(
      load: () async => 'hello',
      builder: (_, data, _) => ListView(children: [Text(data)]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('shows the empty state when isEmpty is true', (tester) async {
    await tester.pumpWidget(_host(AsyncContent<List<int>>(
      load: () async => <int>[],
      isEmpty: (l) => l.isEmpty,
      emptyTitle: 'Nothing yet',
      builder: (_, _, _) => const Text('should not show'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Nothing yet'), findsOneWidget);
    expect(find.text('should not show'), findsNothing);
  });

  testWidgets('shows the error message and retries on tap', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(_host(AsyncContent<String>(
      load: () async {
        attempts++;
        if (attempts == 1) {
          throw const ApiException('Boom failed');
        }
        return 'recovered';
      },
      builder: (_, data, _) => ListView(children: [Text(data)]),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Boom failed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('recovered'), findsOneWidget);
    expect(find.text('Boom failed'), findsNothing);
    expect(attempts, 2);
  });
}
