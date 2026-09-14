import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/features/onboarding/presentation/onboarding_language_screen.dart';
import 'package:phonicsai/features/profile/presentation/profile_setup_screen.dart';

import '../harness/screen_harness.dart';

/// Every screen is pumped at four window sizes. This is the gate for "no
/// overflow errors" and "no hard-coded screen sizes".
void main() {
  for (final size in ScreenSize.all) {
    group(size.name, () {
      testWidgets('language step renders and is tappable', (tester) async {
        await pumpScreen(tester, const OnboardingLanguageScreen(), size: size);
        expect(
          find.text('Which language helps you learn best?'),
          findsOneWidget,
        );
        expect(find.text('Continue'), findsOneWidget);
        await tester.tap(find.text('🇪🇸  Español'));
        await tester.pump();
        expectNoOverflow(tester);
      });

      testWidgets('profile creation form renders', (tester) async {
        await pumpScreen(tester, const ProfileSetupScreen(), size: size);
        expect(find.text('Who is learning?'), findsWidgets);
        expect(find.text('Pick a buddy'), findsOneWidget);
        expect(find.text('🦊'), findsOneWidget,
            reason: 'the buddy catalog must be reachable at every size');
        expectNoOverflow(tester);
      });
    });
  }
}
