import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('Voice Splitter app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const VoiceSplitterExampleApp());

    // Verify that our app renders the main header/title.
    expect(find.text('Voice Splitter AI'), findsOneWidget);
  });
}
