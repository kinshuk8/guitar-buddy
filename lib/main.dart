import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fretlight/app/app.dart';

void main() {
  // Bundled assets carry their own licences; register them so they appear
  // alongside package licences on the in-app licence page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Inter (font)',
    ], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
  });
  runApp(const ProviderScope(child: FretlightApp()));
}
