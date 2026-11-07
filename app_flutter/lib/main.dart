import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_bootstrap.dart';
import 'data/ffi/gbm_bindings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    await bootstrapApp(
      openBindings: GbmBindings.open,
      loadPrefs: SharedPreferences.getInstance,
    ),
  );
}
