import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/features/curriculum/presentation/lesson_player_screen.dart';
import 'package:phonicsai/features/games/presentation/game_play_screen.dart';
import 'package:phonicsai/features/home/presentation/home_screen.dart';
import 'package:phonicsai/features/parent/presentation/parent_gate_screen.dart';
import 'package:phonicsai/features/progress/presentation/progress_screen.dart';
import 'package:phonicsai/features/subscription/presentation/subscription_screen.dart';
import 'package:phonicsai/features/tutor/presentation/tutor_screen.dart';

import '../harness/screen_harness.dart';

/// The whole-app gate: every primary route is opened on a real router at four
/// window sizes. If navigation breaks or a layout overflows, this fails.
void main() {
  for (final size in ScreenSize.all) {
    testWidgets('learner tabs all render at ${size.name}', (tester) async {
      await pumpApp(tester, size: size);
      expect(find.byType(HomeScreen), findsOneWidget);
      expectNoOverflow(tester);

      for (final tab in ['Learn', 'Games', 'Tutor', 'Progress']) {
        await tapAndSettle(tester, find.text(tab).last);
        expectNoOverflow(tester);
      }
    });

    testWidgets('a lesson opens, plays a stage and can be left at ${size.name}',
        (tester) async {
      await pumpApp(tester, size: size);
      final startButton = find.textContaining('Start').first;
      await tester.ensureVisible(startButton);
      await tester.pump();
      await tapAndSettle(tester, startButton);
      expect(find.byType(LessonPlayerScreen), findsOneWidget);
      expectNoOverflow(tester);

      // Advance once through the loop.
      await tapAndSettle(tester, find.text('Next').first);
      expectNoOverflow(tester);

      // Leaving asks first (progress is already saved).
      await tapAndSettle(tester, find.byTooltip('Close'));
      expect(find.text('Leave the lesson?'), findsOneWidget);
      await tapAndSettle(tester, find.text('Finish for now'));
      expect(find.byType(HomeScreen), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('a game round is playable at ${size.name}', (tester) async {
      await pumpApp(tester, size: size);
      await tapAndSettle(tester, find.text('Games').last);
      await tapAndSettle(tester, find.text('Sound Match'));
      expect(find.byType(GamePlayScreen), findsOneWidget);
      expectNoOverflow(tester);

      // Tap any two board choices; the engine handles right/wrong.
      final tiles = find.byType(InkWell, skipOffstage: false);
      expect(tiles, findsWidgets);
      await tapAndSettle(tester, tiles.at(2));
      await tapAndSettle(tester, tiles.at(3));
      expectNoOverflow(tester);
    });

    testWidgets('the parent area is gated, then usable at ${size.name}',
        (tester) async {
      await pumpApp(tester, size: size);
      await tester.ensureVisible(find.byTooltip('Grown-up area'));
      await tapAndSettle(tester, find.byTooltip('Grown-up area'));
      expect(find.byType(ParentGateScreen), findsOneWidget);

      // First run creates the code: 1-2-3-4, then confirm it.
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit).last);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 600));
      expectNoOverflow(tester);

      // Inside: dashboard → subscription → settings → help.
      expect(find.textContaining('Grown-up'), findsWidgets);
      await tapAndSettle(tester, find.byTooltip('Manage subscription'));
      expect(find.byType(SubscriptionScreen), findsOneWidget);
      expectNoOverflow(tester);

      await tapAndSettle(tester, find.text('Settings').last);
      expectNoOverflow(tester);
    });

    testWidgets('tutor answers a question at ${size.name}', (tester) async {
      await pumpApp(tester, size: size);
      await tapAndSettle(tester, find.text('Tutor').last);
      expect(find.byType(TutorScreen), findsOneWidget);
      final stuck = find.text("I'm stuck on a word");
      await tester.ensureVisible(stuck);
      await tapAndSettle(tester, stuck);
      // The mock tutor streams word by word; pump through the reply.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(find.textContaining('break it up'), findsWidgets);
      expectNoOverflow(tester);
    });

    testWidgets('progress and rewards render with data at ${size.name}',
        (tester) async {
      await pumpApp(tester, size: size);
      await tapAndSettle(tester, find.text('Progress').last);
      expect(find.byType(ProgressScreen), findsOneWidget);
      expectNoOverflow(tester);
    });
  }

  testWidgets('wide layouts use a rail, phones use a bar', (tester) async {
    await pumpApp(tester, size: ScreenSize.tablet);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expectNoOverflow(tester);

    await pumpApp(tester, size: ScreenSize.phoneSmall);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expectNoOverflow(tester);
  });
}
