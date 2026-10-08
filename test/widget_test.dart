import 'package:flutter_test/flutter_test.dart';
import 'package:flowflix_app/main.dart';

void main() {
  testWidgets('FlowflixApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FlowflixApp());
    expect(find.byType(FlowflixApp), findsOneWidget);
  });
}
