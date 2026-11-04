import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Decoded audio: mono floats in −1..1.
@immutable
final class WavAudio {
  const WavAudio(this.samples, this.sampleRate);

  final Float32List samples;
  final int sampleRate;
}

/// Minimal RIFF/WAVE reader for test fixtures: PCM 16/24/32-bit and IEEE
/// float 32-bit, any channel count (mixed down to mono). Not used at
/// runtime; the app never records or stores audio.
WavAudio decodeWav(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }
  int? format;
  int? channels;
  int? rate;
  int? bits;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = d.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      format = d.getUint16(body, Endian.little);
      channels = d.getUint16(body + 2, Endian.little);
      rate = d.getUint32(body + 4, Endian.little);
      bits = d.getUint16(body + 14, Endian.little);
      if (format == 0xFFFE && size >= 26) {
        // WAVE_FORMAT_EXTENSIBLE: the real format is the sub-format GUID's first two bytes.
        format = d.getUint16(body + 24, Endian.little);
      }
    } else if (id == 'data') {
      if (format == null || channels == null || rate == null || bits == null) {
        throw const FormatException('data chunk before fmt chunk');
      }
      final bytesPerSample = bits ~/ 8;
      final frames = size ~/ (bytesPerSample * channels);
      final out = Float32List(frames);
      for (var f = 0; f < frames; f++) {
        var sum = 0.0;
        for (var ch = 0; ch < channels; ch++) {
          final o = body + (f * channels + ch) * bytesPerSample;
          sum += switch ((format, bits)) {
            (1, 16) => d.getInt16(o, Endian.little) / 32768,
            (1, 24) =>
              (((bytes[o + 2] << 24) | (bytes[o + 1] << 16) | (bytes[o] << 8)).toSigned(32)) /
                  2147483648,
            (1, 32) => d.getInt32(o, Endian.little) / 2147483648,
            (3, 32) => d.getFloat32(o, Endian.little),
            _ => throw FormatException('Unsupported WAV format $format/$bits-bit'),
          };
        }
        out[f] = sum / channels;
      }
      return WavAudio(out, rate);
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('No data chunk');
}

/// Encodes mono floats as 16-bit PCM WAV (for tests and tools).
Uint8List encodeWav16(Float32List samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final b = ByteData(44 + dataSize);
  void str(int o, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataSize, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}
