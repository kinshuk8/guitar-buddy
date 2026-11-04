import 'package:fretlight/core/music/chord.dart';
import 'package:fretlight/core/music/pitch.dart';

/// Transposition and capo arithmetic.
///
/// Two separate ideas that are easy to conflate:
/// * *Transpose* changes the key the song **sounds** in.
/// * *Capo* keeps the sounding key and changes the **shapes** you finger.
///   With a capo on fret N, a shape sounds N semitones higher, so the shape
///   to finger is the sounding chord moved down N.
abstract final class Transposer {
  /// Chord that sounds after transposing [chord] by [semitones].
  static Chord transpose(Chord chord, int semitones) => chord.transpose(semitones);

  /// Shape to finger with a capo at [capoFret] to sound [sounding].
  static Chord shapeForCapo(Chord sounding, int capoFret) => sounding.transpose(-capoFret);

  /// What a [shape] sounds like with a capo at [capoFret].
  static Chord soundingFromShape(Chord shape, int capoFret) => shape.transpose(capoFret);

  /// Transposes a chord symbol string, keeping text it cannot parse (N.C., x, %).
  ///
  /// Pass a [spelling] from [Spelling.forKey] to spell for the target key
  /// (Bb in F major, A# in B major); otherwise each root gets its
  /// conventional chart spelling.
  static String transposeSymbol(String symbol, int semitones, {Spelling? spelling}) {
    final chord = Chord.tryParse(symbol);
    if (chord == null) return symbol;
    return chord.transpose(semitones).symbol(spelling);
  }

  /// The capo fret (0..[maxCapo]) that lets [chords] be played with the
  /// most open-position shapes. Ties go to the lowest fret.
  static int suggestCapo(Iterable<Chord> chords, {int maxCapo = 7}) {
    var best = 0;
    var bestScore = -1;
    for (var capo = 0; capo <= maxCapo; capo++) {
      final score = chords.where((c) => isOpenShape(shapeForCapo(c, capo))).length;
      if (score > bestScore) {
        best = capo;
        bestScore = score;
      }
    }
    return best;
  }

  /// Whether a beginner can play [chord] as a common open-position shape.
  static bool isOpenShape(Chord chord) {
    if (chord.bass != null) return false;
    final name = chord.symbol(Spelling.sharps);
    return const {
      'C',
      'A',
      'G',
      'E',
      'D',
      'Am',
      'Em',
      'Dm',
      'A7',
      'B7',
      'C7',
      'D7',
      'E7',
      'G7',
      'Am7',
      'Em7',
      'Dm7',
      'Cmaj7',
      'Fmaj7',
      'Amaj7',
      'Dmaj7',
      'Asus2',
      'Asus4',
      'Dsus2',
      'Dsus4',
      'Esus4',
      'E5',
      'A5',
      'D5',
    }.contains(name);
  }
}
