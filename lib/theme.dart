// App colors, text styles and the shared input look.
import 'package:flutter/material.dart';

// ---------------- Colors ----------------
class C {
  static const navy = Color(0xFF0E2A47);
  static const blue = Color(0xFF1D5FA6);
  static const blueSoft = Color(0xFFE8F0F9);
  static const mist = Color(0xFFF2F6FB);
  static const yellow = Color(0xFFF6C945);
  static const yellowDark = Color(0xFFDDAE26);
  static const green = Color(0xFF1E9E6A);
  static const greenSoft = Color(0xFFE3F5EC);
  static const red = Color(0xFFC8372D);
  static const ink = Color(0xFF16273A);
  static const muted = Color(0xFF5B6B7D);
  static const line = Color(0xFFD3DDE8);
}

// Built-in fonts only: no packages needed.
TextStyle serif(double size, {Color color = C.navy}) => TextStyle(
    fontFamily: 'serif',
    fontFamilyFallback: const ['Georgia', 'Times New Roman'],
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color,
    height: 1.15);

TextStyle sans(double size,
        {FontWeight w = FontWeight.w400, Color color = C.ink, double? h}) =>
    TextStyle(fontSize: size, fontWeight: w, color: color, height: h);

// ---------------- Display settings ----------------
// Changed from the Account page. The whole app rebuilds when they change.
final appLang = ValueNotifier<String>('en'); // 'en', 'fil' or 'hil'
final textSize = ValueNotifier<double>(1.0); // 1.0 normal, 1.15 large, 1.3 larger

// Pick the English, Filipino or Hiligaynon wording. When a line has no
// Hiligaynon version yet, the Filipino one is shown.
// Filipino and Hiligaynon lines are first drafts: have native speakers check them.
String tr(String en, String fil, [String? hil]) => switch (appLang.value) {
      'fil' => fil,
      'hil' => hil ?? fil,
      _ => en,
    };

InputDecoration fieldDecoration(String hint, IconData icon) {
  OutlineInputBorder b(Color c, [double w = 1.5]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    hintStyle: sans(15, color: const Color(0xFF97A5B5)),
    prefixIcon: Icon(icon, size: 18, color: const Color(0xFF7C8EA3)),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    isDense: false,
    enabledBorder: b(C.line),
    disabledBorder: b(C.line),
    focusedBorder: b(C.blue, 2),
    errorBorder: b(C.red),
    focusedErrorBorder: b(C.red, 2),
    errorStyle: sans(13, w: FontWeight.w500, color: C.red),
  );
}
