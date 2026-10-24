import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_001/main.dart';

void main() {
  testWidgets('UltronNeuralApp mounts cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(const UltronNeuralApp());
    expect(find.textContaining('ULTRON'), findsWidgets);
  });
}