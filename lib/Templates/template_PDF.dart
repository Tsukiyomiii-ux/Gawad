import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'payroll_template.dart';
import 'masterlist_template.dart';
import 'certification_template.dart';
import 'id_photocopy.dart';

enum DocumentTemplate { payroll, masterlist, certification, idPhotocopy }

class TemplatePdfScreen extends StatefulWidget {
  final List<TanodPerson> scannedTanods;

  const TemplatePdfScreen({super.key, required this.scannedTanods});

  @override
  State<TemplatePdfScreen> createState() => _TemplatePdfScreenState();
}

class _TemplatePdfScreenState extends State<TemplatePdfScreen> {
  DocumentTemplate _selectedTemplate = DocumentTemplate.payroll;

  String get _title {
    switch (_selectedTemplate) {
      case DocumentTemplate.payroll:
        return 'Payroll Masterlist';
      case DocumentTemplate.masterlist:
        return 'Masterlist of Tanods';
      case DocumentTemplate.certification:
        return 'Barangay Certification';
      case DocumentTemplate.idPhotocopy:
        return 'ID Photocopy';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DocumentTemplate>(
                value: _selectedTemplate,
                dropdownColor: Colors.deepPurple,
                iconEnabledColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(
                    value: DocumentTemplate.payroll,
                    child: Text('Template 1: Payroll'),
                  ),
                  DropdownMenuItem(
                    value: DocumentTemplate.masterlist,
                    child: Text('Template 2: Masterlist'),
                  ),
                  DropdownMenuItem(
                    value: DocumentTemplate.certification,
                    child: Text('Template 3: Certification'),
                  ),
                  DropdownMenuItem(
                    value: DocumentTemplate.idPhotocopy,
                    child: Text('Template 4: ID Photocopy'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedTemplate = val);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: PdfPreview(
        // Key forces the preview to rebuild when the template changes
        key: ValueKey(_selectedTemplate),
        build: (format) {
          switch (_selectedTemplate) {
            case DocumentTemplate.payroll:
              return generatePayrollPdf(tanodList: widget.scannedTanods);
            case DocumentTemplate.masterlist:
              return generateMasterlistPdf(tanodList: widget.scannedTanods);
            case DocumentTemplate.certification:
              // dateOfServiceRendered & punongBarangay will come from the UI later
              return generateCertificationPdf(tanodList: widget.scannedTanods);
            case DocumentTemplate.idPhotocopy:
              // Card photos only exist for OCR scans; QR scans are listed on a note page
              return IdPhotocopy.buildAll(tanodList: widget.scannedTanods);
          }
        },
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
      ),
    );
  }
}