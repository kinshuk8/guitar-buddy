import 'package:flutter_test/flutter_test.dart';
import 'package:fretlight/core/widgets/music_text.dart';

void main() {
  test('cents are rounded before the sign: no "−0¢"', () {
    expect(formatCents(-0.3), '0¢');
    expect(formatCents(0.4), '0¢');
    expect(formatCents(3.6), '+4¢');
    expect(formatCents(-12.2), '−12¢');
  });
}
