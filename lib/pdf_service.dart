import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';

class PdfService {
  static Future<void> exportSummaryPdf(BuildContext context, String title, String summary) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0A0E1A))),
            ),
            pw.Paragraph(
              text: 'AI Generated Summary\n\n',
              style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            pw.Paragraph(
              text: summary,
              style: const pw.TextStyle(fontSize: 14, lineSpacing: 2.0),
            ),
          ];
        },
      ),
    );

    await _savePdfAndNotify(context, pdf, 'Summary_$title');
  }

  static Future<void> exportAssessmentPdf(BuildContext context, String title, List<Map<String, String>> questions) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [
            pw.Header(
              level: 0,
              child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Paragraph(
              text: 'AI Generated Q&A - ${questions.length} Questions\n\n',
              style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
          ];

          for (int i = 0; i < questions.length; i++) {
            widgets.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Q${i + 1}: ${questions[i]['question']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.SizedBox(height: 6),
                  pw.Text('A: ${questions[i]['answer']}', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey800)),
                  pw.Divider(color: PdfColors.grey400),
                  pw.SizedBox(height: 12),
                ],
              ),
            );
          }

          return widgets;
        },
      ),
    );

    await _savePdfAndNotify(context, pdf, 'QnA_$title');
  }

  static Future<void> _savePdfAndNotify(BuildContext context, pw.Document pdf, String fileNameBase) async {
    try {
      final sanitizedName = fileNameBase.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      
      // Get directory
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory(); // Android
        dir ??= await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory(); // iOS / Windows
      }

      final file = File('${dir.path}/$sanitizedName.pdf');
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved as PDF to ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
