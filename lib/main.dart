import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tanod_incentives/Scanner/philsys_scanner.dart';
import 'package:tanod_incentives/Scanner/ocr_files/id_scanner_screen.dart';
import 'package:tanod_incentives/Templates/payroll_template.dart';
import 'package:tanod_incentives/Templates/template_PDF.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tanod Payroll System',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PayrollHomePage(),
    );
  }
}

class PayrollHomePage extends StatefulWidget {
  const PayrollHomePage({super.key});

  @override
  State<PayrollHomePage> createState() => _PayrollHomePageState();
}

class _PayrollHomePageState extends State<PayrollHomePage> {
  // Masterlist of all scanned tanods across the municipality
  final List<TanodPerson> _scannedTanods = [];

  bool _checkingConnection = false;

  /// MERGE: quick internet check (no extra package needed).
  /// Online → QR scanner, offline → OCR scanner.
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _scanId() async {
    setState(() => _checkingConnection = true);
    final online = await _hasInternet();
    if (!mounted) return;
    setState(() => _checkingConnection = false);

    if (online) {
      await _openScanner();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No internet — using offline OCR scan'),
          duration: Duration(seconds: 2),
        ),
      );
      await _openOcrScanner();
    }
  }

  /// MERGE: OCR scanner returns a ready-made TanodPerson (with ID photos).
  Future<void> _openOcrScanner() async {
    final TanodPerson? newPerson = await Navigator.push<TanodPerson>(
      context,
      MaterialPageRoute(
        builder: (context) => const IdScannerScreen(),
      ),
    );

    if (newPerson != null && mounted) {
      setState(() {
        _scannedTanods.add(newPerson);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${newPerson.fullName} (${newPerson.barangay}) via OCR'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openScanner() async {
    final String? rawResult = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const PhilsysScannerView(),
      ),
    );

    if (rawResult != null && mounted) {
      final newPerson = TanodPerson.fromJsonString(rawResult);

      setState(() {
        _scannedTanods.add(newPerson);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${newPerson.fullName} (${newPerson.barangay})'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openPdfPreview() {
    if (_scannedTanods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please scan at least one ID before exporting.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TemplatePdfScreen(
          scannedTanods: _scannedTanods,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group scanned tanods by barangay for clean UI display
    final Map<String, List<TanodPerson>> groupedTanods = {};
    for (final person in _scannedTanods) {
      groupedTanods.putIfAbsent(person.barangay, () => []).add(person);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barangay Tanod Masterlist'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // MERGE: manual override, handy for testing the offline flow
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Scan method',
            onSelected: (value) {
              if (value == 'qr') _openScanner();
              if (value == 'ocr') _openOcrScanner();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'qr', child: Text('Scan with QR (online)')),
              PopupMenuItem(value: 'ocr', child: Text('Scan with OCR (offline)')),
            ],
          ),
          if (_scannedTanods.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear All',
              onPressed: () {
                setState(() => _scannedTanods.clear());
              },
            ),
        ],
      ),
      body: _scannedTanods.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, size: 70, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'No Tanods Scanned Yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap "Scan PhilSys ID" below. Uses QR when online,\nOCR photo scan when offline.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 90, top: 10),
              children: groupedTanods.entries.map((entry) {
                final barangay = entry.key;
                final members = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barangay Section Header
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B0F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'BARANGAY $barangay (${members.length})',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    // List of Tanods under this Barangay
                    ...members.map((person) {
                      final overallIndex = _scannedTanods.indexOf(person) + 1;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        elevation: 1.5,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple.shade100,
                            foregroundColor: Colors.deepPurple,
                            child: Text(
                              '$overallIndex',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            person.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            person.scannedByOcr
                                ? 'DOB: ${person.dob} | via OCR (offline)\nID photos attached'
                                : 'Sex: ${person.sex} | DOB: ${person.dob}\nPCN: ${person.pcn}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                            tooltip: 'Remove',
                            onPressed: () {
                              setState(() => _scannedTanods.remove(person));
                            },
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
      bottomNavigationBar: _scannedTanods.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _openPdfPreview,
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(
                  'Generate Payroll Masterlist (${_scannedTanods.length} Tanods)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _checkingConnection ? null : _scanId,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: _checkingConnection
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.qr_code_scanner),
        label: Text(_checkingConnection ? 'Checking connection...' : 'Scan PhilSys ID'),
      ),
    );
  }
}