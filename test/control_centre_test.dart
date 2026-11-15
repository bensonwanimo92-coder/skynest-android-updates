import 'package:chuka/control_centre/control_centre_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Control Centre saves visible modules and their order', (tester) async {
    List<String>? savedOrder;
    Set<String>? savedHidden;

    await tester.pumpWidget(MaterialApp(
      home: ControlCentreScreen(
        moduleTitles: const ['Houses', 'Payments', 'Reports'],
        initialOrder: const ['Payments', 'Houses', 'Reports'],
        initialHidden: const {'Reports'},
        onSave: (order, hidden) async {
          savedOrder = List<String>.from(order);
          savedHidden = Set<String>.from(hidden);
        },
        onOpenNotifications: () {},
        onOpenActivityLog: () {},
        onOpenAutomations: () {},
      ),
    ));

    expect(find.text('SkyNest Control Centre'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);

    await tester.tap(find.text('Save dashboard layout'));
    await tester.pumpAndSettle();

    expect(savedOrder, ['Payments', 'Houses', 'Reports']);
    expect(savedHidden, {'Reports'});
    expect(find.byType(ControlCentreScreen), findsNothing);
  });

  testWidgets('Control Centre quick access opens notification management', (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: ControlCentreScreen(
        moduleTitles: const ['Houses'],
        initialOrder: const [],
        initialHidden: const {},
        onSave: (_, __) async {},
        onOpenNotifications: () => opened = true,
        onOpenActivityLog: () {},
        onOpenAutomations: () {},
      ),
    ));

    await tester.tap(find.text('Notification centre'));
    expect(opened, isTrue);
  });
}
