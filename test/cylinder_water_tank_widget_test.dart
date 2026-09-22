import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pigeonpro_app/widgets/cylinder_water_tank_widget.dart';

void main() {
  testWidgets('CylinderWaterTankWidget renders empty/dry state correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CylinderWaterTankWidget(
            progress: 0.0,
            phase: 0,
            phaseText: 'DRINKER BOWL DRY',
            remainingSec: 0,
            currentMl: 0,
            pumpName: 'Main Drinker',
          ),
        ),
      ),
    );

    // Verify 0 mL and empty bowl status are displayed
    expect(find.text('0 mL'), findsOneWidget);
    expect(find.text('DRINKER BOWL DRY (0 mL)'), findsOneWidget);
    expect(find.text('⚠️ Drinker Bowl Empty (0 mL)'), findsOneWidget);
  });

  testWidgets('CylinderWaterTankWidget renders drain phase correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CylinderWaterTankWidget(
            progress: 0.5,
            phase: 1,
            phaseText: 'DRAINING BOWL TO EMPTY...',
            remainingSec: 0,
            currentMl: 750,
            pumpName: 'Drain Pump #1',
          ),
        ),
      ),
    );

    // Verify draining status
    expect(find.text('750 mL'), findsOneWidget);
    expect(find.text('DRAINING BOWL TO EMPTY...'), findsAtLeastNWidgets(1));
    expect(find.text('💧 Draining: 750 mL in bowl'), findsOneWidget);
  });
}
