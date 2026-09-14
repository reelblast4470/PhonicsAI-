import 'dart:async';

import 'audio_service.dart';

/// Bundled-audio implementation.
///
/// Sound files are addressed by a deterministic key (`/s/{phoneme}.mp3`,
/// `/word/{word}.mp3`, `/cue/correct.mp3`) so content authors can add clips
/// without touching code. Missing clips fall back to haptic/visual feedback and
/// are reported to the telemetry sink, so a missing asset can never look like
/// a broken lesson.
class AssetAudioService implements AudioService {
  AssetAudioService({
    required this.loader,
    this.onMissingAsset,
  });

  final AudioClipLoader loader;
  final void Function(String assetPath)? onMissingAsset;

  final _playing = StreamController<bool>.broadcast();
  ClipHandle? _current;

  @override
  Stream<bool> get isPlaying => _playing.stream;

  @override
  Future<void> speak(String text, {String? voiceId, double rate = 0.85}) {
    // Word/sentence playback is expressed as an asset key so the cloud-TTS
    // adapter can implement the same method later without UI changes.
    return playAsset('/tts/${_slug(text)}.mp3');
  }

  @override
  Future<void> playAsset(String assetPath) async {
    await _current?.stop();
    final clip = await loader.load(assetPath);
    if (clip == null) {
      onMissingAsset?.call(assetPath);
      return;
    }
    _current = clip;
    _playing.add(true);
    unawaited(
      clip.finished.whenComplete(() {
        _playing.add(false);
        if (_current == clip) _current = null;
      }),
    );
  }

  @override
  Future<void> playFeedback(AudioCue cue) =>
      playAsset('/cue/${cue.name}.mp3');

  @override
  void stop() {
    unawaited(_current?.stop() ?? Future<void>.value());
    _current = null;
    _playing.add(false);
  }

  Future<void> dispose() async {
    stop();
    await _playing.close();
  }

  static String _slug(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

abstract interface class AudioClipLoader {
  /// Returns null when the asset is not present.
  Future<ClipHandle?> load(String key);
}

abstract interface class ClipHandle {
  Future<void> get finished;
  Future<void> stop();
}

/// Adapter used until a real player (`just_audio` / `audioplayers`) is linked:
/// it resolves the asset path, reports it as missing, and the UI stays correct.
class UnlinkedAudioClipLoader implements AudioClipLoader {
  const UnlinkedAudioClipLoader();

  @override
  Future<ClipHandle?> load(String key) async => null;
}
