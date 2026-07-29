import 'package:alma/core/theme/app_theme.dart';
import 'package:alma/presentation/screens/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LoginScreen renders brand, inputs and actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.neo(), home: const LoginScreen()),
      ),
    );

    expect(find.text('ALMA'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
    // Two fields: email + password.
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
