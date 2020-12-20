import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stockfish_example/main.dart' as app;

/// As of 2020-12-20, Flutter dev channel is required to run this test
/// due to an issue with isolate being paused during testing
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('verify state', (tester) async {
    await tester.runAsync(() async {
      app.main();
      await tester.pumpAndSettle();

      // 5s should be enough for the engine to init itself
      // even on the slowest devices...
      await Future.delayed(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    final found = find.byKey(ValueKey('stockfish.state')).evaluate();
    expect(found.length, equals(1));

    final widget = found.first.widget as Text;
    expect(widget.data, 'stockfish.state=StockfishState.ready');
  });
}
