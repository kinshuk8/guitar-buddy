// Rebuilds assets/chords/guitar.json and docs/chord-data-report.md.
//
//   git clone https://github.com/tombatossals/chords-db /tmp/chords-db
//   dart run tool/chords_db/convert.dart /tmp/chords-db
//
// Runs on a developer machine only; the app never touches the network.
// It's a CLI, so printing is its output.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'convert_lib.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/chords_db/convert.dart <path to chords-db checkout>');
    exit(64);
  }
  final repo = args.single;
  final source = File('$repo/lib/guitar.json');
  if (!source.existsSync()) {
    stderr.writeln('No lib/guitar.json in $repo');
    exit(66);
  }
  final git = Process.runSync('git', ['-C', repo, 'rev-parse', 'HEAD']);
  final commit = git.exitCode == 0 ? (git.stdout as String).trim() : 'unknown';

  final db = (jsonDecode(source.readAsStringSync()) as Map).cast<String, Object?>();
  final result = convert(db);

  File('assets/chords/guitar.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(toAssetJson(result, commit: commit)));
  File('docs/chord-data-report.md').writeAsStringSync(report(result, commit: commit));

  print(
    '${result.chords.length} chords, ${result.keptVoicings} voicings bundled; '
    '${result.issues.length} rejected, ${result.mergedDuplicates} duplicates merged '
    '(from ${result.sourcePositions}).',
  );
}
