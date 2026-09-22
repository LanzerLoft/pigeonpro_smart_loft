import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pigeonpro_app/models/drinker_preset.dart';
import 'package:pigeonpro_app/screens/pump_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'Tapping Set Empty defaults to 10sec drain when no last fill is recorded',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'drinker_current_water_level_ml': 1500,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PumpScreen(
              status: null,
              deviceUrl: 'http://192.168.1.100',
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump(const Duration(milliseconds: 200));

    // Verify initial state: 1500 mL and "Set Empty (0 mL)" button exists
    expect(find.text('Set Empty (0 mL)'), findsOneWidget);
    expect(find.text('1500 mL'), findsWidgets);

    // Tap "Set Empty (0 mL)"
    await tester.ensureVisible(find.text('Set Empty (0 mL)'));
    await tester.tap(find.text('Set Empty (0 mL)'));
    await tester.pump();

    // Drain animation should be running with 10s default countdown
    expect(find.text('Draining Bowl (10s)...'), findsOneWidget);
    expect(find.text('DRAINING BOWL TO EMPTY (10s)'), findsWidgets);

    // Advance 5 seconds (halfway through 10s default)
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Draining Bowl (5s)...'), findsOneWidget);

    // Advance remaining 5 seconds + buffer to finish
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));

    // Now bowl is empty (0 mL)
    expect(find.text('Bowl is Empty (0 mL)'), findsOneWidget);
    expect(find.text('0 mL'), findsWidgets);
    expect(find.text('DRINKER BOWL DRY (0 mL)'), findsOneWidget);

    // Verify completion SnackBar is displayed with clearly visible white text
    final snackBarTextFinder = find.text(
        'Drinker bowl drained & marked Empty (0 mL • 10s). Next flush will skip draining.');
    expect(snackBarTextFinder, findsOneWidget);
    final Text snackBarText = tester.widget(snackBarTextFinder);
    expect(snackBarText.style?.color, equals(Colors.white));
  });

  testWidgets(
      'Tapping Set Empty uses last fill record drainSec when available',
      (WidgetTester tester) async {
    final record = LastRefillRecord(
      timestamp: DateTime.now(),
      volumeMl: 2000,
      liters: 2.0,
      presetName: '2 Liters Preset',
      presetChipLabel: '2.0L',
      drainSec: 25,
      fillSec: 40,
    );

    SharedPreferences.setMockInitialValues({
      'drinker_current_water_level_ml': 2000,
      'drinker_last_refill_json': jsonEncode(record.toJson()),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PumpScreen(
              status: null,
              deviceUrl: 'http://192.168.1.100',
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    // Tap "Set Empty (0 mL)"
    await tester.ensureVisible(find.text('Set Empty (0 mL)'));
    await tester.tap(find.text('Set Empty (0 mL)'));
    await tester.pump();

    // Drain animation should use last fill record's drainSec (25s)
    expect(find.text('Draining Bowl (25s)...'), findsOneWidget);
    expect(find.text('DRAINING BOWL TO EMPTY (25s)'), findsWidgets);

    // Advance 15 seconds
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Draining Bowl (10s)...'), findsOneWidget);

    // Advance remaining 10 seconds + buffer
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 300));

    // Completed
    expect(find.text('Bowl is Empty (0 mL)'), findsOneWidget);
    expect(find.text('0 mL'), findsWidgets);
  });

  test('1 Liter Preset calculates exactly 1.0 Liters and 1000 mL without 988 mL drift', () {
    final preset1L = DrinkerPreset.defaultPresets().firstWhere(
      (p) => p.volumeMl == 1000,
    );

    // Even with a calibrated flow rate like 3.12 LPM, calculatedLiters must be 1.0 and volumeMl 1000
    expect(preset1L.volumeMl, equals(1000));
    expect(preset1L.calculatedLiters, equals(1.0));
    expect(preset1L.volumeChipLabel, equals('1L'));
  });


  testWidgets(
      'Stop Draining Early stops drain animation and preserves remaining water',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'drinker_current_water_level_ml': 1000,
      'drinker_active_preset_id': 'preset_1l',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PumpScreen(
              status: null,
              deviceUrl: 'http://192.168.1.100',
              onRefresh: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    // Start draining
    await tester.ensureVisible(find.text('Set Empty (0 mL)'));
    await tester.tap(find.text('Set Empty (0 mL)'));
    await tester.pump();

    // Advance 3 seconds (draining underway)
    await tester.pump(const Duration(seconds: 3));

    // Stop button is visible on main action button
    final stopButton = find.textContaining('Stop Draining Early');
    expect(stopButton, findsOneWidget);

    // Tap stop draining early
    await tester.ensureVisible(stopButton);
    await tester.tap(stopButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Draining stopped, draining banner is gone, refill is available
    expect(find.textContaining('DRAINING BOWL TO EMPTY'), findsNothing);
    expect(find.textContaining('Refill'), findsOneWidget);
  });
}
