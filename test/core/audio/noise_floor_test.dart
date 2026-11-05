import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/audio/listening.dart';

void main() {
  NoiseFloor floor() => NoiseFloor(marginDb: 10, frameSeconds: 0.085);

  test('digital silence while the mic opens is not mistaken for the room', () {
    final f = floor();
    for (var i = 0; i < 5; i++) {
      expect(f.update(-120), isFalse);
    }
    // A -40 dB room: learned straight away, not 20 s later.
    expect(f.update(-40), isFalse);
    expect(f.gateDb, closeTo(-30, 0.5));
    expect(f.update(-38), isFalse, reason: 'the room itself is not playing');
    expect(f.update(-22), isTrue, reason: 'a strum well above it is');
  });

  test('drops at once to a quieter room, rises slowly to a louder one', () {
    final f = floor()..update(-50);
    f.update(-62);
    expect(f.floorDb, -62);
    for (var i = 0; i < 12; i++) {
      f.update(-45); // about a second of louder background
    }
    expect(f.floorDb, closeTo(-62 + 3 * 12 * 0.085, 0.01));
  });

  test('long loud playing never becomes the floor', () {
    final f = floor()..update(-60);
    for (var i = 0; i < 2000; i++) {
      f.update(-15);
    }
    expect(f.floorDb, lessThanOrEqualTo(-38));
    expect(f.update(-15), isTrue);
  });
}
