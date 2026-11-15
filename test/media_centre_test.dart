import 'package:chuka/media/media_centre_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Media Centre exposes local, online and direct-download paths', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: MediaCentreScreen()));
    await tester.pumpAndSettle();

    expect(find.text('SkyNest Media Centre'), findsOneWidget);
    expect(find.text('Phone storage'), findsOneWidget);
    expect(find.text('ONLINE MEDIA'), findsOneWidget);
    expect(find.text('Play direct link'), findsOneWidget);
    expect(find.text('Open provider'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });
}
