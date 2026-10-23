import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:construction_app/screens/ai/project_analyst_screen.dart';

void main() {
  const textScales = [1.0, 1.3, 1.6, 2.0];

  group('Phase 1.5 TextScaler Sweep for UI Overflows', () {
    for (final factor in textScales) {
      testWidgets('ProjectAnalystScreen renders without overflow at factor $factor',
          (WidgetTester tester) async {
        // Set standard phone viewport size
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(factor),
                size: const Size(411, 731),
              ),
              child: const ProjectAnalystScreen(
                projectId: 'test_proj',
                projectName: 'Test Hospital Remodel',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow occurred at textScaler $factor');
      });
    }
  });
}
