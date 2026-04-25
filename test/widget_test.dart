import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/src/app.dart';

void main() {
  testWidgets('shows setup notice when Supabase is not configured', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const LiftTierFlutterApp(supabaseConfigured: false),
    );

    expect(find.text('Supabase Configuration Required'), findsOneWidget);
  });
}
