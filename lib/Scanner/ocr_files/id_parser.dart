import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'id_image_tools.dart' show NormPoint;

enum IdField { firstName, lastName, middleInitial, birthDate, address }

class ScannedIdData {
  String firstName;
  String lastName;
  String middleInitial;
  String birthDate; // MERGE: as printed on the card, e.g. "JANUARY 15, 1990"
  String address;   // MERGE: full address line(s)

  /// MERGE: split out of [address] so the templates can group by barangay.
  /// Not flagged/merged like the other fields; always editable on screen.
  String barangay;
  String municipality;

  /// Fields the tanod should double-check (the two readings disagreed,
  /// or only the less reliable offline reading found them).
  final Set<IdField> needsCheck = {};

  ScannedIdData({
    this.firstName = '',
    this.lastName = '',
    this.middleInitial = '',
    this.birthDate = '',
    this.address = '',
    this.barangay = '',
    this.municipality = '',
  });

  String get(IdField f) => switch (f) {
        IdField.firstName => firstName,
        IdField.lastName => lastName,
        IdField.middleInitial => middleInitial,
        IdField.birthDate => birthDate,
        IdField.address => address,
      };

  void set(IdField f, String v) {
    switch (f) {
      case IdField.firstName: firstName = v;
      case IdField.lastName: lastName = v;
      case IdField.middleInitial: middleInitial = v;
      case IdField.birthDate: birthDate = v;
      case IdField.address: address = v;
    }
  }

  bool get isEmpty => IdField.values.every((f) => get(f).isEmpty);
}

/// What Gemini says about the photo itself (not the names).
class ScanCheck {
  final bool isPhilId;     // right card, right side
  final bool readable;     // text sharp and legible
  final String issue;      // short reason when not readable

  /// The card's 4 corners in the card's own reading order:
  /// top-left, top-right, bottom-right, bottom-left (0-1000 scale).
  /// Used to cut out and straighten the card.
  final List<NormPoint>? corners;

  const ScanCheck({
    required this.isPhilId,
    required this.readable,
    this.issue = '',
    this.corners,
  });

  factory ScanCheck.fromJson(Map<String, dynamic> json, String idKey) {
    return ScanCheck(
      isPhilId: json[idKey] == true,
      readable: json['readable'] == true,
      issue: (json['issue'] ?? '').toString().trim(),
      corners: _parseCorners(json['cardCorners']),
    );
  }

  static List<NormPoint>? _parseCorners(dynamic c) {
    if (c is! Map) return null;
    final out = <NormPoint>[];
    for (final key in const ['topLeft', 'topRight', 'bottomRight', 'bottomLeft']) {
      final p = c[key];
      if (p is! Map || p['x'] is! num || p['y'] is! num) return null;
      out.add(((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
    }
    return out;
  }
}

/// Result of the "was this scanned properly?" check for one side of the card.
class SideQuality {
  final List<String> passed = [];
  final List<String> problems = [];
  bool get ok => problems.isEmpty;
}

class IdSanitizer {
  /// Cleans OCR misreads (e.g. 'PANAGUIT0N' -> 'PANAGUITON', removes garbage chars)
  static String cleanName(String raw) {
    if (raw.isEmpty) return '';
    String cleaned = raw.toUpperCase().trim();

    // Replace numbers accidentally misread in names
    cleaned = cleaned
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('5', 'S')
        .replaceAll('8', 'B')
        .replaceAll('3', 'E');

    // Keep only letters, spaces, hyphens and Ñ
    cleaned = cleaned.replaceAll(RegExp(r'[^A-ZÑ\s\-]'), '');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// MERGE: for addresses and dates. Unlike [cleanName] this keeps digits
  /// (house no., purok, year) and , . / # punctuation.
  static String cleanText(String raw) {
    if (raw.isEmpty) return '';
    String cleaned = raw.toUpperCase().trim();
    cleaned = cleaned.replaceAll(RegExp(r'[^A-ZÑ0-9\s,./#\-]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*,\s*'), ', ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// MERGE: best guess of barangay & municipality from a PhilID address.
  /// Handles "PUROK 2, BRGY. ARIPDIP, SAN RAFAEL, ILOILO" and
  /// "ARIPDIP, SAN RAFAEL, ILOILO". Returns '' for anything it can't find.
  static ({String barangay, String municipality}) splitAddress(String address) {
    // Drop trailing extras some cards print: ZIP code, country, region
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    while (parts.isNotEmpty &&
        RegExp(r'^\d{4}$|PHILIPPINES|VISAYAS|REGION|^VI$').hasMatch(parts.last)) {
      parts.removeLast();
    }
    if (parts.isEmpty) return (barangay: '', municipality: '');

    String strip(String p) => p
        .replaceAll(RegExp(r'^(BRGY\.?|BARANGAY|BGY\.?)\s*', caseSensitive: false), '')
        .trim();

    // 1) A part that says BRGY / BARANGAY: the municipality comes right after it
    final i = parts.indexWhere((p) => RegExp(r'^(BRGY|BARANGAY|BGY)\b', caseSensitive: false).hasMatch(p));
    if (i != -1) {
      return (
        barangay: strip(parts[i]),
        municipality: i + 1 < parts.length ? _stripCity(parts[i + 1]) : '',
      );
    }

    // 2) Otherwise count from the end: ..., barangay, municipality, province
    final hasProvince = parts.length >= 3 && parts.last.contains('ILOILO') && !parts.last.contains('CITY');
    final end = hasProvince ? parts.length - 1 : parts.length;
    if (end >= 2) {
      return (barangay: strip(parts[end - 2]), municipality: _stripCity(parts[end - 1]));
    }
    return (barangay: '', municipality: end == 1 ? _stripCity(parts[0]) : '');
  }

  static String _stripCity(String p) =>
      p.replaceAll(RegExp(r'^(MUNICIPALITY OF|MUN\. OF)\s*', caseSensitive: false), '').trim();

  /// Takes the first letter of the (full) middle name
  static String extractMiddleInitial(String raw) {
    final cleaned = cleanName(raw);
    return cleaned.isEmpty ? '' : cleaned[0];
  }
}

class IdParser {
  // Never hardcode the key. Run with:
  //   flutter run --dart-define=GEMINI_API_KEY=your_key
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  // Alias that always points to Google's current Flash model,
  // so the app doesn't break when a specific version is retired.
  static const String _modelName = 'gemini-flash-latest';

  /// Below this sharpness score the photo is treated as blurry.
  /// Watch "sharpness score" in the console on a few good and bad photos
  /// and adjust if needed.
  static const double sharpnessThreshold = 60;

  static const String _photoCheckRules = '''
Also report on the photo itself:
- readable: true only if the text that matters is sharp and fully legible (no blur, glare, shadow or cut-off over it).
- issue: if readable is false, a short reason such as "glare over last name" or "photo is blurry"; otherwise "".
- cardCorners: the 4 physical corners of the ID card in the photo, each as x (left to right)
  and y (top to bottom) normalized to 0-1000 of the photo's width and height.
  Name the corners by the CARD's own orientation, as if the card were upright and readable
  (topLeft is next to the start of the top line of the card's printed text),
  even if the photo is rotated or upside down.
  Place each point exactly on the card's corner; for rounded corners, use the spot where the
  two straight edges would meet. Do not include any background.
''';

  static const String _frontPrompt = '''
This photo shows the FRONT of a Philippine National ID (PhilSys / PhilID) card.
The card may be tilted, off-center, glared or shadowed, with background around it.

Each value is printed in bold capital letters directly BELOW its bilingual label:
- "Apelyido/Last Name"            -> lastName
- "Mga Pangalan/Given Names"      -> givenNames (often two or more words, e.g. "MARIA CLARA"; include a suffix like JR or III if printed there)
- "Gitnang Apelyido/Middle Name"  -> middleName (the FULL middle name, not just the initial)
- "Petsa ng Kapanganakan/Date of Birth" -> dateOfBirth, copied exactly as printed (e.g. "JANUARY 15, 1990")
- "Tirahan/Address" -> address. Its label is printed in very small text and is easy to miss:
  the address is the text BELOW the place of birth, near the bottom of the card.
  It may wrap onto two or three lines; join them with ", " in reading order.
  Then also split it:
    - barangay: the barangay name only, without "BRGY." or "BARANGAY" (and without purok/street/house no.)
    - municipality: the city or municipality name only, without the province

Rules:
- Copy each value letter by letter exactly as printed. Do not correct spelling, do not "fix" names to more common spellings, and do not guess.
- Keep Ñ as Ñ.
- Ignore the tiny repeating background microtext (e.g. REPUBLIKANGPILIPINAS, PHILIPPINESTATISTICSAUTHORITY).
- Never return the label words themselves.
- If a value is missing or unreadable, return an empty string for it (some people have no middle name).
- Set isPhilId to false if this is not the front of a Philippine National ID.

$_photoCheckRules
For readable, "the text that matters" is the last name, given names, middle name, date of birth and address.
''';

  static const String _backPrompt = '''
This photo should show the BACK of a Philippine National ID (PhilSys / PhilID) card.
The card may be tilted, off-center, glared or shadowed, with background around it.

- isPhilIdBack: true if this is the back of a Philippine National ID.
- Do not transcribe any of the text.

$_photoCheckRules
For readable, "the text that matters" is all the printed text on the back of the card.
''';

  static Schema _point() => Schema.object(
        properties: {'x': Schema.integer(), 'y': Schema.integer()},
        requiredProperties: ['x', 'y'],
      );

  static Schema _corners() => Schema.object(
        properties: {
          'topLeft': _point(),
          'topRight': _point(),
          'bottomRight': _point(),
          'bottomLeft': _point(),
        },
        requiredProperties: ['topLeft', 'topRight', 'bottomRight', 'bottomLeft'],
      );

  static final Schema _frontSchema = Schema.object(
    properties: {
      'isPhilId': Schema.boolean(),
      'lastName': Schema.string(),
      'givenNames': Schema.string(),
      'middleName': Schema.string(),
      'dateOfBirth': Schema.string(),
      'address': Schema.string(),
      'barangay': Schema.string(),
      'municipality': Schema.string(),
      'readable': Schema.boolean(),
      'issue': Schema.string(),
      'cardCorners': _corners(),
    },
    requiredProperties: [
      'isPhilId', 'lastName', 'givenNames', 'middleName', 'dateOfBirth', 'address',
      'barangay', 'municipality', 'readable', 'issue', 'cardCorners',
    ],
  );

  static final Schema _backSchema = Schema.object(
    properties: {
      'isPhilIdBack': Schema.boolean(),
      'readable': Schema.boolean(),
      'issue': Schema.string(),
      'cardCorners': _corners(),
    },
    requiredProperties: ['isPhilIdBack', 'readable', 'issue', 'cardCorners'],
  );

  /// Sends one photo + prompt to Gemini and returns the JSON answer,
  /// or null if Gemini could not be used (no key, no internet, error...).
  static Future<Map<String, dynamic>?> _askGemini(
      String prompt, Schema schema, Uint8List photo) async {
    if (_apiKey.isEmpty) {
      print('Gemini skipped: no GEMINI_API_KEY provided');
      return null;
    }

    try {
      final model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
        generationConfig: GenerationConfig(
          temperature: 0,
          responseMimeType: 'application/json',
          responseSchema: schema,
        ),
      );

      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', photo),
        ]),
      ]).timeout(const Duration(seconds: 25));

      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        print('Gemini Error: empty response');
        return null;
      }
      print('--- GEMINI RESPONSE ---\n$text');
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (e) {
      // Read this line in the debug console when something goes wrong
      // (wrong key, no internet, model name, quota...)
      print('Gemini Error: $e');
      return null;
    }
  }

  /// FRONT: reads the names and checks the photo in one Gemini call.
  /// Returns null if Gemini could not be used.
  static Future<({ScannedIdData data, ScanCheck check})?> readWithGemini(Uint8List photo) async {
    final json = await _askGemini(_frontPrompt, _frontSchema, photo);
    if (json == null) return null;

    final check = ScanCheck.fromJson(json, 'isPhilId');
    if (!check.isPhilId) {
      print('Gemini: photo is not the front of a PhilID');
      return (data: ScannedIdData(), check: check);
    }

    final data = ScannedIdData(
      lastName: IdSanitizer.cleanName(json['lastName']?.toString() ?? ''),
      firstName: IdSanitizer.cleanName(json['givenNames']?.toString() ?? ''),
      middleInitial: IdSanitizer.extractMiddleInitial(json['middleName']?.toString() ?? ''),
      birthDate: IdSanitizer.cleanText(json['dateOfBirth']?.toString() ?? ''),
      address: IdSanitizer.cleanText(json['address']?.toString() ?? ''),
      barangay: IdSanitizer.cleanText(json['barangay']?.toString() ?? ''),
      municipality: IdSanitizer.cleanText(json['municipality']?.toString() ?? ''),
    );
    return (data: data, check: check);
  }

  /// BACK: only checks the photo (right card, readable, where the card is).
  static Future<ScanCheck?> checkBackWithGemini(Uint8List photo) async {
    final json = await _askGemini(_backPrompt, _backSchema, photo);
    return json == null ? null : ScanCheck.fromJson(json, 'isPhilIdBack');
  }

  /// SECOND OPINION (offline): uses ML Kit line POSITIONS.
  /// Finds each label, then takes the closest line directly below it.
  static ScannedIdData readOffline(RecognizedText recognized) {
    final data = ScannedIdData();
    final lines = <TextLine>[for (final b in recognized.blocks) ...b.lines];
    if (lines.isEmpty) return data;

    // MERGE (debug): every line ML Kit saw, with its position. If a field isn't
    // picked up, copy this block from the debug console to tune the rules.
    print('--- ML KIT LINES (top, left, height: text) ---');
    for (final l in [...lines]..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top))) {
      final r = l.boundingBox;
      print('${r.top.round()}, ${r.left.round()}, ${r.height.round()}: ${l.text}');
    }

    TextLine? findLabel(bool Function(String t) test) {
      for (final l in lines) {
        if (test(l.text.toLowerCase())) return l;
      }
      return null;
    }

    // "Gitnang Apelyido" also contains "apelyido",
    // so the last-name label explicitly excludes "gitna".
    final middleLabel = findLabel((t) => t.contains('middle') || t.contains('gitna'));
    final lastLabel = findLabel((t) =>
        !t.contains('gitna') && !t.contains('middle') &&
        (t.contains('last n') || t.contains('apel')));
    final givenLabel = findLabel((t) => t.contains('given') || t.contains('pangalan'));

    data.lastName = IdSanitizer.cleanName(_valueBelow(lastLabel, lines));
    data.firstName = IdSanitizer.cleanName(_valueBelow(givenLabel, lines));
    data.middleInitial = IdSanitizer.extractMiddleInitial(_valueBelow(middleLabel, lines));

    // MERGE: "birth" is in both labels, so tell date and place apart
    final dobLabel = findLabel((t) =>
        t.contains('petsa') || t.contains('date of b') ||
        (t.contains('kapanganakan') && !t.contains('lugar')));
    final pobLabel = findLabel((t) => t.contains('lugar') || t.contains('place of b'));
    data.birthDate = IdSanitizer.cleanText(_valueBelow(dobLabel, lines));

    // MERGE: the "Address" label is tiny and often not detected.
    // Use it if found; otherwise take the lines under the place of birth value.
    final addrLabel = findLabel((t) => t.contains('tirahan') || t.contains('address'));
    // (_addressBelow skips the small "Address" label row if it sits in between)
    final TextLine? anchor =
        addrLabel ?? (pobLabel == null ? null : _lineBelow(pobLabel, lines));
    data.address = IdSanitizer.cleanText(_addressBelow(anchor, lines));
    return data;
  }

  /// MERGE: the address can wrap onto 2-3 lines, so collect every line
  /// stacked directly under [anchor] until there's a gap.
  static String _addressBelow(TextLine? anchor, List<TextLine> lines) {
    if (anchor == null) return '';
    final out = <String>[];
    TextLine current = anchor;
    for (int i = 0; i < 3; i++) {
      final next = _lineBelow(current, lines, skipLabels: true);
      if (next == null) break;
      out.add(next.text.trim());
      current = next;
    }
    return out.join(', ');
  }

  /// Closest line under [label] that lines up with it (no size filter, so it
  /// also works under the tiny "Address" label). Watermark lines are skipped.
  static TextLine? _lineBelow(TextLine label, List<TextLine> lines, {bool skipLabels = false}) {
    final Rect lb = label.boundingBox;
    TextLine? best;
    double bestGap = double.infinity;
    for (final l in lines) {
      if (identical(l, label)) continue;
      final Rect r = l.boundingBox;
      final gapY = r.top - lb.bottom;
      if (r.center.dy <= lb.center.dy) continue;              // must be below
      if (gapY > math.max(lb.height, r.height) * 2.0) continue; // too far down
      if ((r.left - lb.left).abs() > math.max(lb.width, r.width) * 0.6) continue;
      if (RegExp(r'^[A-Za-z]{16,}$').hasMatch(l.text.replaceAll(' ', ''))) continue; // microtext
      if (skipLabels && _isAddressLabel(l.text)) continue;
      if (gapY < bestGap) {
        bestGap = gapY;
        best = l;
      }
    }
    return best;
  }

  static bool _isAddressLabel(String text) {
    final t = text.toLowerCase();
    return t.contains('tirahan') || t.contains('address');
  }

  /// Offline readability hint: how many lines contain a real word (3+ letters).
  static int countReadableLines(RecognizedText recognized) {
    final word = RegExp(r'[A-Za-z]{3,}');
    return recognized.blocks
        .expand((b) => b.lines)
        .where((l) => word.hasMatch(l.text))
        .length;
  }

  /// Combines both readings. Gemini's value wins, but any field where the two
  /// readings disagree (or only the offline one found it) is flagged for checking.
  static ScannedIdData merge(ScannedIdData? ai, ScannedIdData ocr) {
    final out = ScannedIdData();
    // MERGE: barangay/municipality — Gemini's split if it gave one,
    // otherwise split whichever address we ended up with (below).
    out.barangay = ai?.barangay ?? '';
    out.municipality = ai?.municipality ?? '';
    for (final f in IdField.values) {
      final a = ai?.get(f) ?? '';
      final o = ocr.get(f);

      if (a.isEmpty && o.isEmpty) continue;

      if (a.isEmpty) {
        out.set(f, o);
        out.needsCheck.add(f); // only the weaker reading found it
      } else {
        out.set(f, a);
        if (o.isNotEmpty && !_similar(a, o)) out.needsCheck.add(f);
      }
    }
    if (out.barangay.isEmpty || out.municipality.isEmpty) {
      final split = IdSanitizer.splitAddress(out.address);
      if (out.barangay.isEmpty) out.barangay = split.barangay;
      if (out.municipality.isEmpty) out.municipality = split.municipality;
    }
    return out;
  }

  /// Was the FRONT scanned properly?
  static SideQuality assessFront({
    required ScanCheck? check,
    required ScannedIdData merged,
    required ScannedIdData ocr,
    required double sharpness,
  }) {
    final q = SideQuality();

    if (check != null) {
      if (check.isPhilId) {
        q.passed.add('PhilID front detected');
      } else {
        q.problems.add('This does not look like the front of a PhilID');
      }
      if (check.readable) {
        q.passed.add('Names are clearly readable');
      } else {
        q.problems.add(check.issue.isEmpty ? 'Names are hard to read' : 'Hard to read: ${check.issue}');
      }
    } else {
      // Offline: judge by whether the on-device OCR found the names
      final found = [ocr.firstName, ocr.lastName, ocr.middleInitial].where((s) => s.isNotEmpty).length;
      if (found >= 2) {
        q.passed.add('ID text detected (offline check)');
      } else {
        q.problems.add('ID text could not be detected');
      }
    }

    if (sharpness >= sharpnessThreshold) {
      q.passed.add('Image is sharp');
    } else {
      q.problems.add('Image looks blurry');
    }

    if (merged.firstName.isNotEmpty && merged.lastName.isNotEmpty) {
      q.passed.add('First and last name captured');
    } else {
      q.problems.add('First or last name is missing');
    }

    if (check != null && check.isPhilId) {
      if (merged.needsCheck.isEmpty) {
        q.passed.add('Both readings agree');
      } else {
        final n = merged.needsCheck.length;
        q.problems.add('$n field${n == 1 ? '' : 's'} need checking');
      }
    }
    return q;
  }

  /// Was the BACK scanned properly?
  static SideQuality assessBack({
    required ScanCheck? check,
    required int ocrLines,
    required double sharpness,
  }) {
    final q = SideQuality();

    if (check != null) {
      if (check.isPhilId) {
        q.passed.add('PhilID back detected');
      } else {
        q.problems.add('This does not look like the back of a PhilID');
      }
      if (check.readable) {
        q.passed.add('Text is clearly readable');
      } else {
        q.problems.add(check.issue.isEmpty ? 'Text is hard to read' : 'Hard to read: ${check.issue}');
      }
    } else {
      if (ocrLines >= 5) {
        q.passed.add('Text detected (offline check)');
      } else {
        q.problems.add('Little or no text detected');
      }
    }

    if (sharpness >= sharpnessThreshold) {
      q.passed.add('Image is sharp');
    } else {
      q.problems.add('Image looks blurry');
    }
    return q;
  }

  /// True if two readings are the same apart from a small OCR slip.
  static bool _similar(String a, String b) {
    final x = a.replaceAll(RegExp(r'[^A-ZÑ0-9]'), '');
    final y = b.replaceAll(RegExp(r'[^A-ZÑ0-9]'), '');
    if (x == y) return true;
    // MERGE: long fields (addresses) allow a few more OCR slips
    final allowed = x.length > 20 ? 4 : (x.length > 6 ? 2 : 1);
    return _levenshtein(x, y) <= allowed;
  }

  static int _levenshtein(String s, String t) {
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    List<int> prev = List.generate(t.length + 1, (i) => i);
    for (int i = 0; i < s.length; i++) {
      final cur = List<int>.filled(t.length + 1, 0);
      cur[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = s[i] == t[j] ? 0 : 1;
        cur[j + 1] = [cur[j] + 1, prev[j + 1] + 1, prev[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      prev = cur;
    }
    return prev[t.length];
  }

  /// Closest line that sits under the label, starts near the label's left edge,
  /// and is not smaller than the label (the watermark microtext is much smaller).
  static String _valueBelow(TextLine? label, List<TextLine> lines) {
    if (label == null) return '';
    final Rect lb = label.boundingBox;

    TextLine? best;
    double bestGap = double.infinity;

    for (final l in lines) {
      if (identical(l, label)) continue;
      final Rect r = l.boundingBox;

      final gapY = r.center.dy - lb.center.dy;
      if (gapY <= 0) continue;                                 // must be below the label
      if (gapY > lb.height * 3.5) continue;                    // too far down
      if ((r.left - lb.left).abs() > lb.width * 0.6) continue; // not lined up under it
      if (r.height < lb.height * 0.8) continue;                // background microtext
      if (_isLabelOrNoise(l.text)) continue;

      if (gapY < bestGap) {
        bestGap = gapY;
        best = l;
      }
    }
    return best?.text ?? '';
  }

  static bool _isLabelOrNoise(String text) {
    final t = text.toLowerCase();
    const noise = [
      'apel', 'last name', 'given', 'pangalan', 'gitna', 'middle',
      'tirahan', 'addres', 'petsa', 'kapanganakan', 'birth',
      'republik', 'pilipinas', 'philippine', 'statistics', 'authority',
    ];
    if (noise.any(t.contains)) return true;

    // One long unbroken word = watermark microtext (e.g. "GPILIPINASREPUBL")
    return RegExp(r'^[A-Za-z]{16,}$').hasMatch(text.replaceAll(' ', ''));
  }
}