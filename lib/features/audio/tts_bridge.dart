import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/di/infrastructure.dart';
import '../../app/state/app_settings_controller.dart';
import '../../core/audio/audio_service.dart';
import '../../core/speech/speech_service.dart';

/// Thin bridge between "the tutor should say this" and the two audio doors
/// (playback + recognition). Features use *only* this class, so no screen ever
/// imports `core/audio` or `core/speech`, and a cloud TTS/ASR adapter can be
/// dropped in behind it without touching the UI layer.
class TtsBridge {
  const TtsBridge({
    required this.audio,
    required this.speech,
    this.isEnabled = true,
  });

  final AudioService audio;
  final SpeechService speech;

  /// Parents can mute effects; read-aloud still works.
  final bool isEnabled;

  Future<void> say(String text, {String? voiceId}) {
    if (!isEnabled) return Future<void>.value();
    return audio.speak(text, voiceId: voiceId);
  }

  Future<void> cue(bool isCorrect) => audio
      .playFeedback(isCorrect ? AudioCue.correct : AudioCue.incorrect);

  Future<void> celebrate() => audio.playFeedback(AudioCue.celebrate);

  Future<void> star() => audio.playFeedback(AudioCue.starEarned);

  /// Read-aloud of a single phoneme. Letters are ambiguous out of context
  /// ("a" could be the name or the sound), so the hint table keeps it honest.
  Future<void> sayPhoneme(String phoneme) =>
      audio.speak(phonemeAudioHint(phoneme));

  static String phonemeAudioHint(String phoneme) => switch (phoneme) {
    'sh' => 'shhh',
    'ch' => 'chch',
    'th' => 'thhh',
    'ph' => 'fff',
    'wh' => 'whuh',
    'ck' => 'k',
    _ => phoneme,
  };
}

final ttsBridgeProvider = Provider<TtsBridge>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return TtsBridge(
    audio: ref.watch(audioServiceProvider),
    speech: ref.watch(speechServiceProvider),
    isEnabled: settings.soundEnabled,
  );
});
