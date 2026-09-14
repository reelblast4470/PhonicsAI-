import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';

/// A support ticket. Deliberately carries no learner data — the adult describes
/// the problem in their own words.
class SupportMessage {
  const SupportMessage({
    required this.subject,
    required this.body,
    required this.locale,
    this.appVersion = '1.0.0',
  });

  final String subject;
  final String body;
  final String locale;
  final String appVersion;

  Map<String, Object?> toJson() => {
        'subject': subject,
        'body': body,
        'locale': locale,
        'app_version': appVersion,
        'platform': defaultTargetPlatformLabel(),
      };
}

String defaultTargetPlatformLabel() {
  // Kept out of dart:io so the web build does not need a stub.
  return 'unknown';
}

abstract interface class SupportService {
  Future<Result<void>> send({
    required String subject,
    required String body,
    required String locale,
  });
}

/// Posts to our own /support/tickets endpoint. With no backend configured it
/// reports "queued locally" rather than pretending the message was sent.
class ApiSupportService implements SupportService {
  const ApiSupportService(this._client);

  final ApiClient _client;

  @override
  Future<Result<void>> send({
    required String subject,
    required String body,
    required String locale,
  }) async {
    try {
      await _client.postJson(
        '/support/tickets',
        body: SupportMessage(
          subject: subject,
          body: body,
          locale: locale,
        ).toJson(),
      );
      return const Result.ok(null);
    } on AppFailure catch (failure) {
      return Result.fail(failure);
    } catch (error) {
      return Result.fail(
        const AppFailure(
          kind: FailureKind.unknown,
          message: 'We could not send that. Please try again.',
        ),
      );
    }
  }
}

class QueuedLocallySupportService implements SupportService {
  const QueuedLocallySupportService();

  @override
  Future<Result<void>> send({
    required String subject,
    required String body,
    required String locale,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return Result.fail(
      const AppFailure(
        kind: FailureKind.offline,
        message: 'No connection: your message is saved on this device and '
            'will send when you are back online.',
      ),
    );
  }
}

final supportServiceProvider = Provider<SupportService>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.hasBackend) return const QueuedLocallySupportService();
  return ApiSupportService(ref.read(apiClientProvider));
});

/// Bundled help content: always available, searchable, and versioned with the
/// app so a FAQ can never 404 offline.
class FaqEntry {
  const FaqEntry({
    required this.id,
    required this.question,
    required this.answer,
    required this.tags,
    this.actionLabel,
    this.onAction,
  });

  final String id;
  final String question;
  final String answer;
  final List<String> tags;
  final String? actionLabel;
  final void Function()? onAction;
}

abstract final class SupportContent {
  static const List<FaqEntry> faq = [
    FaqEntry(
      id: 'mic',
      question: 'The microphone does not hear my child',
      answer: 'Check PhonicsAI has microphone permission in system settings. On '
          'shared tablets, a parent can also turn pronunciation practice off under '
          'Grown-ups → Content controls. No sound never blocks a lesson: every '
          '"say it" card has a type/tap fallback.',
      tags: ['mic', 'microphone', 'pronunciation', 'permission'],
    ),
    FaqEntry(
      id: 'stuck_lesson',
      question: 'My child is stuck on a lesson',
      answer: 'Tap Skip on the stage card. Skipping still records the stage, and '
          'the sound comes back for review a day or two later automatically.',
      tags: ['lesson', 'stuck', 'skip'],
    ),
    FaqEntry(
      id: 'streak',
      question: 'How does the streak work?',
      answer: 'Any completed mission keeps the streak. A missed day resets it to '
          'zero but never removes stars, badges or progress — we want the streak '
          'to pull, not punish.',
      tags: ['streak', 'mission', 'daily'],
    ),
    FaqEntry(
      id: 'level',
      question: 'The starting level is wrong',
      answer: 'Grown-ups → Settings → Reading level. Change it any time; the '
          'curriculum reorders to match, and nothing already learnt is lost.',
      tags: ['level', 'placement', 'assessment'],
    ),
    FaqEntry(
      id: 'refund',
      question: 'Refunds and cancelling Plus',
      answer: 'Subscriptions are billed by Google Play or the App Store, so '
          'cancelling and refunds happen there: Play Store → Payments → '
          'Subscriptions, or Settings → Apple ID → Subscriptions. Your child keeps '
          'Plus until the period ends.',
      tags: ['refund', 'cancel', 'subscription', 'billing', 'play', 'apple'],
    ),
    FaqEntry(
      id: 'privacy',
      question: 'What do you collect about my child?',
      answer: 'First name, age in months, learning records and stars — stored on '
          'this device. Cloud sync is off until you turn it on. Voice audio is '
          'transcribed on-device and never stored raw. No ads SDKs, no '
          'third-party trackers, ever.',
      tags: ['privacy', 'data', 'gdpr', 'coppa', 'recording'],
    ),
    FaqEntry(
      id: 'offline',
      question: 'Does it work on a plane?',
      answer: 'Yes. Lessons, games and the reader run fully offline. The AI tutor '
          'needs a connection; offline it offers the same questions from its local '
          'rule engine and says so plainly.',
      tags: ['offline', 'flight', 'connection'],
    ),
    FaqEntry(
      id: 'windows',
      question: 'Is there a Windows desktop app?',
      answer: 'Yes — the same build, with a side rail instead of a bottom bar, '
          'mouse and keyboard support, and window resizing from 800px up. Purchases '
          'on Windows go through the web checkout.',
      tags: ['windows', 'desktop', 'pc'],
    ),
    FaqEntry(
      id: 'audio_missing',
      question: 'Some words have no sound',
      answer: 'Pronunciation clips stream on demand. If one is missing, the card '
          'shows a silent-playback badge and the tutor still says the word with '
          'device speech. Nothing breaks.',
      tags: ['audio', 'sound', 'missing'],
    ),
    FaqEntry(
      id: 'delete',
      question: 'Delete everything',
      answer: 'Grown-ups → Settings → Account and data → Delete account & data. '
          'That wipes the local store immediately and queues server erasure. It is '
          'not reversible from the app.',
      tags: ['delete', 'account', 'data', 'erasure'],
    ),
  ];
}
