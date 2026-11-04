import 'dart:io';

import 'package:camera_android/camera_android.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Camera2 supplies the single-plane NV21 buffer expected by this ML Kit bridge.
  if (Platform.isAndroid) AndroidCamera.registerWith();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PriceLensApp());
}
