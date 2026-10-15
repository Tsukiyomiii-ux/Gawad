// MERGE: Gawad UI is now the app. The old scan-and-list home screen was replaced:
// its online/offline scanner routing moved to Scanner/id_capture.dart and its
// PDF templates are opened from Documents (Templates/gawad_pdf.dart).

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:tanod_incentives/firebase_options.dart'; // made by `flutterfire configure`
import 'package:tanod_incentives/data/cloud.dart' show firebaseReady;
import 'package:tanod_incentives/theme.dart';
import 'package:tanod_incentives/screens/auth/auth_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TEMP: print layout (overflow) errors in full. Remove before the demo.
  FlutterError.onError = (details) => FlutterError.dumpErrorToConsole(details, forceReport: true);

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Offline mode (same as the team's setup): keep a copy of the data on the
    // device and queue saves until internet returns.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    firebaseReady = true; // if Firebase fails, the app still opens with the demo data
    debugPrint('✅ Firebase connected: ${Firebase.app().options.projectId}');
  } catch (e) {
    debugPrint('⚠️ Firebase not connected, using demo data: $e');
  }

  runApp(const GawadApp());
}

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