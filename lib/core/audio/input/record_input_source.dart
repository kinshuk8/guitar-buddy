// Raw-input flags are passed explicitly even when equal to the defaults;
// see the comment at RecordConfig below.
// ignore_for_file: avoid_redundant_argument_values
import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:fretlight/core/audio/input/audio_input_source.dart';
import 'package:fretlight/core/audio/session/app_audio_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// [AudioInputSource] on the `record` plugin, with this app owning the audio
/// session so the mic is as raw as each platform allows.
///
/// * iOS: `record` would set `.playAndRecord` in default mode, which applies
///   voice processing. We turn its session management off and set
///   `.measurement` mode ourselves (no AGC, flat frequency response).
///   `.playAndRecord` (not `.record`) so the metronome and chord playback
///   can sound while the mic is open in later milestones.
/// * Android: `UNPROCESSED` only where the device declares support (asked
///   through a small method channel in MainActivity); otherwise
///   `VOICE_RECOGNITION`, which Android's CDD requires to have AGC off.
final class RecordInputSource implements AudioInputSource {
  RecordInputSource();

  static const _caps = MethodChannel('fretlight/audio_caps');
  static const _sampleRate = 48000;

  final _recorder = AudioRecorder();
  final _events = StreamController<InputEvent>.broadcast();
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  bool _sessionConfigured = false;

  @override
  Stream<InputEvent> get events => _events.stream;

  @override
  Future<MicPermission> permission() async => _map(await Permission.microphone.status);

  @override
  Future<MicPermission> requestPermission() async => _map(await Permission.microphone.request());

  @override
  Future<void> openSettings() => openAppSettings();

  MicPermission _map(PermissionStatus s) => switch (s) {
    PermissionStatus.granted ||
    PermissionStatus.limited ||
    PermissionStatus.provisional => MicPermission.granted,
    PermissionStatus.permanentlyDenied ||
    PermissionStatus.restricted => MicPermission.permanentlyDenied,
    PermissionStatus.denied => MicPermission.denied,
  };

  Future<void> _configureSession() async {
    if (_sessionConfigured) return;
    if (Platform.isIOS) await _recorder.ios?.manageAudioSession(false);
    await AppAudioSession.ensureCapture();
    final session = await AudioSession.instance;
    await _interruptions?.cancel();
    // iOS only. There a call or Siri deactivates the session and capture
    // really stops. On Android the events are audio focus, which governs
    // playback, not recording: a notification sound "takes focus" for a
    // second while the mic carries on fine. Treating that as an
    // interruption paused the mic, and having let go of the session, the
    // app was never told focus came back.
    if (Platform.isIOS) {
      _interruptions = session.interruptionEventStream.listen((e) {
        _events.add(e.begin ? const InterruptionBegan() : const InterruptionEnded());
      });
    }
    _sessionConfigured = true;
  }

  Future<bool> _supportsUnprocessed() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _caps.invokeMethod<bool>('supportsUnprocessed') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<({InputDescription description, Stream<Uint8List> pcm})> start() async {
    await _configureSession();
    final session = await AudioSession.instance;
    await session.setActive(true);
    final unprocessed = await _supportsUnprocessed();
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        // Spelled out even where they match today's defaults: raw input is
        // the whole point, and a changed default must not silently undo it.
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        // We handle interruptions through audio_session so the UI can say so.
        audioInterruption: AudioInterruptionMode.none,
        androidConfig: AndroidRecordConfig(
          audioSource: unprocessed
              ? AndroidAudioSource.unprocessed
              : AndroidAudioSource.voiceRecognition,
        ),
      ),
    );
    final description = InputDescription(
      sampleRate: _sampleRate,
      raw: Platform.isIOS || unprocessed,
      label: Platform.isIOS
          ? 'Measurement mode'
          : unprocessed
          ? 'Unprocessed mic'
          : 'Voice-recognition mic',
    );
    return (description: description, pcm: stream);
  }

  @override
  Future<void> stop() async {
    if (await _recorder.isRecording()) await _recorder.stop();
    final session = await AudioSession.instance;
    await session.setActive(false);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _interruptions?.cancel();
    await _events.close();
    await _recorder.dispose();
  }
}
