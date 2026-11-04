import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  // Flutter drive may reinstall the APK and reset runtime permissions.
  // Grant after installation, before the driver resumes the test isolate.
  final serial = Platform.environment['ANDROID_SERIAL'];
  if (serial != null) {
    final sdk = File('android/local.properties')
        .readAsLinesSync()
        .firstWhere((line) => line.startsWith('sdk.dir='))
        .substring(8)
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\:', ':');
    final result = await Process.run(
      '$sdk/platform-tools/adb${Platform.isWindows ? '.exe' : ''}',
      [
        '-s',
        serial,
        'shell',
        'pm',
        'grant',
        'app.pricelens.pricelens',
        'android.permission.CAMERA'
      ],
    );
    if (result.exitCode != 0) {
      throw StateError('Camera permission grant failed: ${result.stderr}');
    }
  }
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final directory = Directory('docs/evidence')..createSync(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
