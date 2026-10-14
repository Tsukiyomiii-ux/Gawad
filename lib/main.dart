// MERGE: Gawad UI is now the app. The old scan-and-list home screen was replaced:
// its online/offline scanner routing moved to Scanner/id_capture.dart and its
// PDF templates are opened from Documents (Templates/gawad_pdf.dart).

import 'package:flutter/material.dart';

import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/screens/auth/auth_page.dart';

void main() => runApp(const GawadApp());

class GawadApp extends StatelessWidget {
  const GawadApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // Rebuild everything when the language or text size changes.
        listenable: Listenable.merge([appLang, textSize]),
        builder: (context, _) => MaterialApp(
          title: 'Gawad',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: C.mist,
            colorScheme: ColorScheme.fromSeed(seedColor: C.blue),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textSize.value)),
            child: child!,
          ),
          home: const AuthPage(),
        ),
      );
}
