import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'scanner/scanner_screen.dart';

class PriceLensApp extends StatelessWidget {
  const PriceLensApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PriceLens',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFCBF88B),
            brightness: Brightness.dark,
            primary: const Color(0xFFCBF88B),
            surface: const Color(0xFF171C20),
          ),
          scaffoldBackgroundColor: const Color(0xFF101518),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const ScannerScreen(
            demoRates: kDebugMode && bool.fromEnvironment('DEMO_RATES')),
      );
}
