import 'package:chuka/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SkyNest root widget builds the application shell', (tester) async {
    await tester.pumpWidget(const SkynestApp());

    expect(find.byType(SkynestApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('SkyNest'), findsOneWidget);
  });
}
