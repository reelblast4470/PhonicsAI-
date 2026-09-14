import 'dart:async';

/// Model-agnostic audio door for the whole learning experience:
/// phoneme clips, word playback, TTS rewards, tutor speech.
///
/// Implementations: [AssetAudioService] (bundled clips — works fully offline,
/// which matters for the low-end Android devices this app targets), and a
/// cloud-TTS adapter added later behind the same interface.
abstract interface class AudioService {
  Future<void> speak(String text, {String? voiceId, double rate = 0.85});
  Future<void> playAsset(String assetPath);
  Future<void> playFeedback(AudioCue cue);
  void stop();
  Stream<bool> get isPlaying;
}

enum AudioCue {
  correct,
  incorrect,
  hint,
  starEarned,
  levelUnlocked,
  celebrate,
  tap,
}

/// Audio is optional for correctness: on emulators, CI and when assets are not
/// bundled yet, playback degrades to cues-without-sound instead of throwing.
class NoopAudioService implements AudioService {
  NoopAudioService({this.onCue});

  final void Function(AudioCue cue)? onCue;
  final _playing = StreamController<bool>.broadcast();

  @override
  Future<void> speak(String text, {String? voiceId, double rate = 0.85}) async {}

  @override
  Future<void> playAsset(String assetPath) async {}

  @override
  Future<void> playFeedback(AudioCue cue) async {
    onCue?.call(cue);
  }

  @override
  void stop() => _playing.add(false);

  @override
  Stream<bool> get isPlaying => _playing.stream;

  Future<void> dispose() => _playing.close();
}
