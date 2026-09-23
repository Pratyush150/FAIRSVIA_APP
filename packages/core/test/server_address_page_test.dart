import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  late _MemStore store;
  setUp(() => store = _MemStore());

  Future<void> pump(WidgetTester tester, {required bool serverUp}) =>
      tester.pumpWidget(MaterialApp(
        home: ServerAddressPage(
          store: store,
          current: 'https://old.example.com/api/v1',
          probe: (_) async => serverUp,
        ),
      ));

  Future<void> submit(WidgetTester tester, String url) async {
    await tester.enterText(find.byType(TextField), url);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Check and save'));
    await tester.pumpAndSettle();
  }

  testWidgets('saves a checked https address and says how to apply it', (tester) async {
    await pump(tester, serverUp: true);
    await submit(tester, 'https://new-tunnel.trycloudflare.com/api/v1/');
    expect(store.data[AppConfig.serverOverrideKey],
        'https://new-tunnel.trycloudflare.com/api/v1');
    expect(find.textContaining('open it again'), findsOneWidget);
  });

  testWidgets('refuses an address with no server behind it', (tester) async {
    await pump(tester, serverUp: false);
    await submit(tester, 'https://typo.trycloudflare.com/api/v1');
    expect(store.data, isEmpty);
    expect(find.textContaining('No RideVela server answered'), findsOneWidget);
  });

  testWidgets('refuses plain http and half addresses without calling anything',
      (tester) async {
    await pump(tester, serverUp: true);
    for (final bad in ['http://192.168.1.69:3000/api/v1', 'https://x.com']) {
      await submit(tester, bad);
      expect(store.data, isEmpty);
      expect(find.textContaining('full https address'), findsOneWidget);
    }
  });

  testWidgets('can go back to the built-in address', (tester) async {
    store.data[AppConfig.serverOverrideKey] = 'https://a.example.com/api/v1';
    await pump(tester, serverUp: true);
    await tester.tap(find.text('Use the built-in address'));
    await tester.pumpAndSettle();
    expect(store.data, isEmpty);
  });
}
