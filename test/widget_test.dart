import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_v2/main.dart';

//**********************************************************************
// WIDGET SMOKE TEST FOR JARVIS PIXEL ENV                              *
// Verifies that JarvisV2OpenSourceApp mounts cleanly without errors.  *
//**********************************************************************

void main() {
  testWidgets('JarvisV2OpenSourceApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const JarvisV2OpenSourceApp());
    expect(find.text('AI Website Squads'), findsOneWidget);
  });
}