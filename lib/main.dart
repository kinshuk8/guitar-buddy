import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/app/app.dart';
import 'package:fretlight/core/storage/app_database.dart';
import 'package:fretlight/core/storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled assets carry their own licences; register them so they appear
  // alongside package licences on the in-app licence page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter (font)',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'chords-db (chord shapes)',
    ], await rootBundle.loadString('assets/chords/chords-db-LICENSE.txt'));
    // Optional pack: listed only when it's in the build.
    try {
      yield LicenseEntryWithLineBreaks([
        'Chordonomicon (progression pack)',
      ], await rootBundle.loadString('assets/packs/chordonomicon/ATTRIBUTION.txt'));
    } on Object {
      // Pack removed from this build.
    }
  });
  // A few kilobytes of settings: read before the first frame so screens
  // never flash defaults.
  final store = await LocalStore.open(AppDatabase.device());
  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const FretlightApp(),
    ),
  );
}
