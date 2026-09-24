import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements KeyValueStore {
  _Store([this.failing = false]);
  final bool failing;
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async {
    if (failing) throw Exception('storage unavailable');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failing) throw Exception('storage unavailable');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  test(
    'follows the phone until the user picks, then remembers the pick',
    () async {
      final store = _Store();
      final first = await ThemeController.load(store);
      expect(first.value, ThemeMode.system);

      await first.set(ThemeMode.dark);
      // The next launch reads it back.
      expect((await ThemeController.load(store)).value, ThemeMode.dark);
    },
  );

  test(
    'a storage failure never blocks the app: system at start, choice still applied',
    () async {
      final c = await ThemeController.load(_Store(true));
      expect(c.value, ThemeMode.system);
      await c.set(ThemeMode.light);
      expect(c.value, ThemeMode.light);
    },
  );

  testWidgets('the Appearance sheet switches the theme when tapped', (
    tester,
  ) async {
    final c = ThemeController(_Store());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showAppearanceSheet(ctx, c),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Same as phone'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(c.value, ThemeMode.dark);
  });
}
