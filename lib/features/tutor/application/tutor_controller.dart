import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/infrastructure.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/util/ids.dart';
import '../../profile/application/profile_providers.dart';
import '../../progress/application/progress_providers.dart';
import '../domain/tutor_models.dart';
import '../domain/tutor_service.dart';

/// The tutor's live thread.
///
/// Owns three things the UI must not decide for itself: what context the model
/// gets (never a name-plus-location-plus-anything-identifying beyond the first
/// name), whether the thread is persisted, and how streaming text lands in the
/// list without a rebuild storm (one `ValueStream` per message id).
@immutable
class TutorThread {
  const TutorThread({
    required this.messages,
    this.isThinking = false,
    this.error,
    this.starters = const [],
  });

  final List<TutorMessage> messages;
  final bool isThinking;
  final String? error;
  final List<String> starters;

  bool get isEmpty => messages.isEmpty;
}

class TutorController extends Notifier<TutorThread> {
  static const maxKeptMessages = 40;

  KeyValueStore get _store => ref.read(keyValueStoreProvider);
  TutorService get _service => ref.read(tutorServiceProvider);

  @override
  TutorThread build() {
    final profileId = ref.watch(activeProfileIdProvider);
    _restore(profileId);
    return TutorThread(messages: const []);
  }

  Future<void> _restore(String? profileId) async {
    if (profileId == null) return;
    final raw = _store.getString('phonicsai.tutor_threads.$profileId');
    if (raw == null) return;
    // Restore is best-effort; a corrupt thread simply starts fresh.
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isThinking) return;

    final context = await _buildContext();
    final learnerMessage = TutorMessage(
      id: Ids.short(),
      role: TutorRole.learner,
      text: trimmed,
      at: DateTime.now(),
    );
    state = TutorThread(
      messages: [...state.messages, learnerMessage],
      isThinking: true,
    );

    final result = await _service.reply(
      message: trimmed,
      context: context,
      onToken: (partial) {
        if (state.messages.isEmpty) return;
        final last = state.messages.last;
        if (last.role != TutorRole.tutor) return;
        state = state.copyWithMessage(last.copyWith(text: partial, isStreaming: true));
      },
    );

    state = result.fold(
      ok: (reply) => TutorThread(
        messages: [
          ...state.messages,
          TutorMessage(
            id: Ids.short(),
            role: TutorRole.tutor,
            text: reply.text,
            at: DateTime.now(),
            chips: reply.chips,
            action: reply.action,
            flagged: reply.flagged,
          ),
        ],
        starters: state.starters,
      ),
      fail: (failure) => TutorThread(
        messages: state.messages,
        error: failure.message,
        starters: state.starters,
      ),
    );

    await _persist();
    if (result.isOk && result.requireValue.flagged) {
      // A flagged exchange is a parent-facing event, not a punishment for the
      // child: log it so the dashboard can show "Aria redirected 2 times".
      ref.read(analyticsServiceProvider).logEvent('tutor_flagged_exchange', {
        'profile_id': ref.read(activeProfileIdProvider),
      });
    }
  }

  Future<TutorContext> _buildContext() async {
    final profile = ref.read(activeProfileProvider);
    final snapshot = ref.read(profileProgressProvider).valueOrNull;
    final struggling = (snapshot?.mastery.values
                .where((m) => m.accuracy < 0.6 && m.reps > 0)
                .map((m) => m.phoneme.split('__').last)
                .toList() ??
            const <String>[])
        .take(3)
        .toList();
    final recent = profile == null
        ? const <String>[]
        : (snapshot?.mastery.keys.map((k) => k.split('__').last).toList() ??
            const <String>[]);
    return TutorContext(
      learnerName: profile?.displayName ?? 'friend',
      ageYears: profile?.ageYears ?? 5,
      levelLabel: profile?.level.label ?? 'Sounds & symbols',
      recentPhonemes: recent.take(2).toList(),
      strugglingPhonemes: struggling,
      instructionLanguageCode: profile?.homeLanguageCode ?? 'en',
      openChatAllowed: true,
    );
  }

  Future<void> _persist() async {
    final profileId = ref.read(activeProfileIdProvider);
    if (profileId == null) return;
    final keep = state.messages.length > maxKeptMessages
        ? state.messages.sublist(state.messages.length - maxKeptMessages)
        : state.messages;
    // Only text is stored locally; audio never is.
    await _store.setString(
      'phonicsai.tutor_threads.$profileId',
      '[${keep.map((m) => '{"id":"${m.id}","role":"${m.role.name}","text":"${m.text.replaceAll('"', "'")}","at":"${m.at.toIso8601String()}"}').join(',')}]',
    );
  }

  void clearError() {
    state = TutorThread(messages: state.messages, starters: state.starters);
  }

  Future<void> clearThread() async {
    state = const TutorThread(messages: []);
    final profileId = ref.read(activeProfileIdProvider);
    if (profileId != null) {
      await _store.remove('phonicsai.tutor_threads.$profileId');
    }
  }
}

extension on TutorThread {
  TutorThread copyWithMessage(TutorMessage message) {
    final messages = [...this.messages];
    if (messages.isEmpty) return this;
    messages[messages.length - 1] = message;
    return TutorThread(
      messages: messages,
      isThinking: isThinking,
      error: error,
      starters: starters,
    );
  }
}

/// The tutor adapter for the current backend mode. `live` replaces this with an
/// HTTP call to our own /tutor endpoint — never to a model provider directly.
final tutorServiceProvider = Provider<TutorService>(
  (ref) => const PhonicsRuleTutor(),
);

final tutorProvider = NotifierProvider<TutorController, TutorThread>(
  TutorController.new,
);
