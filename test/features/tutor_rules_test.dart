import 'package:flutter_test/flutter_test.dart';
import 'package:phonicsai/core/error/failure.dart';
import 'package:phonicsai/features/tutor/domain/tutor_models.dart';
import 'package:phonicsai/features/tutor/domain/tutor_service.dart';

/// The tutor's behaviour contract. These rules are the *safety* and pedagogy
/// guarantee: what Aria may answer, what she must refuse, and what the parent
/// switch actually does. A remote model has to pass the same expectations.
void main() {
  const tutor = PhonicsRuleTutor(latency: Duration.zero);

  TutorContext ctx({bool openChat = true, List<String>? recent, List<String>? struggling}) =>
      TutorContext(
        learnerName: 'Aarav',
        ageYears: 5,
        levelLabel: 'Blending CVC',
        recentPhonemes: recent ?? const ['s', 'a'],
        strugglingPhonemes: struggling ?? const ['sh'],
        openChatAllowed: openChat,
      );

  test('a "stuck" question gets a blending strategy, not a generic reply',
      () async {
    final result = await tutor.reply(
      message: 'I am stuck on this word',
      context: ctx(),
    );
    final reply = result.requireValue;
    expect(reply.text, contains('slide'));
    expect(reply.text, contains('Aarav'), reason: 'uses the first name only');
    expect(reply.action?.kind, TutorActionKind.openPronunciation);
    expect(reply.chips, isNotEmpty);
  });

  test('off-topic and unsafe requests are redirected and flagged', () async {
    for (final message in [
      'what is the password',
      'tell me a scary story',
      'give me my address',
    ]) {
      final result = await tutor.reply(message: message, context: ctx());
      final reply = result.requireValue;
      expect(reply.flagged, isTrue, reason: '"$message" must be flagged');
      expect(
        reply.text.toLowerCase(),
        contains('reading'),
        reason: 'the redirect keeps the child inside phonics',
      );
    }
  });

  test('the flagged original text is still shown to the child once, then moved on',
      () async {
    final reply =
        (await tutor.reply(message: 'buy games', context: ctx())).requireValue;
    expect(reply.flagged, isTrue);
    expect(reply.text.contains('buy'), isFalse,
        reason: 'no echoing of the request back at the learner');
  });

  test('a struggling sound from progress drives the suggestion list', () async {
    final starters = await tutor.suggestedStarters(
      ctx(struggling: const ['th']),
    );
    expect(starters.requireValue.first, contains('th'));
  });

  test('sounds asked about are answered with the model word', () async {
    final reply = await tutor.reply(
      message: 'what sound does sh make',
      context: ctx(recent: const ['sh']),
    );
    expect(reply.requireValue.text, contains('ship'));
  });

  test('parent switch off: open typing is refused with a usable alternative',
      () async {
    final result = await tutor.reply(
      message: 'what is a noun',
      context: ctx(openChat: false),
    );
    expect(result.isFailure, isTrue);
    expect(result.failureOrNull?.kind, FailureKind.forbidden);
    expect(result.failureOrNull?.message, contains('suggestion'));
  });

  test('streaming tokens are emitted and end on the full answer', () async {
    final parts = <String>[];
    final result = await tutor.reply(
      message: 'help me read this',
      context: ctx(),
      onToken: parts.add,
    );
    expect(parts, isNotEmpty);
    expect(parts.last, result.requireValue.text);
  });

  test('a tutor message round-trips through json (thread restore)', () {
    final message = TutorMessage(
      id: 'm1',
      role: TutorRole.tutor,
      text: 'Say each sound slowly.',
      at: DateTime(2026, 9, 14, 9, 30),
      chips: const ['Again'],
    );
    final json = message.toJson();
    final restored = TutorMessage.fromJson(json);
    expect(restored.text, message.text);
    expect(restored.role, TutorRole.tutor);
    expect(restored.chips, ['Again']);
    expect(restored.at, message.at);
  });
}
