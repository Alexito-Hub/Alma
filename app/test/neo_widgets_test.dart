import 'package:alma/core/theme/app_theme.dart';
import 'package:alma/core/theme/neo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] in the neo theme so widgets have Directionality + Theme.
Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.neo(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('NeoButton', () {
    testWidgets('renders its label and fires onPressed when tapped', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(NeoButton(label: 'Guardar', onPressed: () => taps++)),
      );

      expect(find.text('Guardar'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      expect(taps, 1);
    });

    testWidgets('does not fire when onPressed is null (disabled)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const NeoButton(label: 'Inerte')));
      // Tapping a disabled button must not throw and has no effect.
      await tester.tap(find.text('Inerte'));
      expect(find.text('Inerte'), findsOneWidget);
    });

    testWidgets('busy shows a spinner and suppresses the callback', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(NeoButton(label: 'X', busy: true, onPressed: () => taps++)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(NeoButton));
      expect(taps, 0);
    });
  });

  testWidgets('NeoErrorBanner shows its message', (tester) async {
    await tester.pumpWidget(
      _host(const NeoErrorBanner(message: 'Correo inválido')),
    );
    expect(find.text('Correo inválido'), findsOneWidget);
  });

  group('NeoChip', () {
    testWidgets('renders its label and fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(NeoChip(label: '#viaje', onTap: () => taps++)),
      );
      expect(find.text('#viaje'), findsOneWidget);
      await tester.tap(find.text('#viaje'));
      expect(taps, 1);
    });
  });
}
