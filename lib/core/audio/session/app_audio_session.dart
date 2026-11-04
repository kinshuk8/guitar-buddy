import 'package:audio_session/audio_session.dart';

/// The one place the app's audio session is configured, shared by the mic
/// (tuner, identifier) and playback (chords, metronome).
///
/// Two levels, only ever upgraded:
/// * playback: `.playback` on iOS, so chords and clicks sound even with the
///   silent switch on (this is an instrument app) without touching the mic.
///   A record-capable category is avoided here because it can surface the
///   microphone prompt when you've only tapped "play".
/// * capture: `.playAndRecord` in `.measurement` mode (no AGC, flat
///   response), which still plays audio, so a chord can sound while the
///   tuner listens.
abstract final class AppAudioSession {
  static _Level _level = _Level.none;

  static Future<void> ensurePlayback() async {
    if (_level == _Level.none) {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidWillPauseWhenDucked: true,
        ),
      );
      _level = _Level.playback;
    }
    await (await AudioSession.instance).setActive(true);
  }

  static Future<void> ensureCapture() async {
    if (_level == _Level.capture) return;
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetoothA2dp,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidWillPauseWhenDucked: true,
      ),
    );
    _level = _Level.capture;
  }
}

enum _Level { none, playback, capture }
