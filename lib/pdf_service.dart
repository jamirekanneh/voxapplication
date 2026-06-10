import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

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

  /// Export a voice-note transcript as PDF and open the system share/save sheet.
  static Future<void> exportTranscriptPdf(
    BuildContext context,
    String title,
    String content,
  ) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transcript to download')),
        );
      }
      return;
    }

    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context pdfCtx) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF0A0E1A),
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              trimmed,
              style: const pw.TextStyle(
                fontSize: 13,
                lineSpacing: 5,
                color: PdfColors.black,
              ),
            ),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final safeName = title
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final file = File('${dir.path}/${safeName}_transcript.pdf');
      await file.writeAsBytes(await pdf.save());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          text: '$title transcript',
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF ready — choose Save or Share'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
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

  static Future<void> exportTextFile(
    BuildContext context,
    String title,
    String content,
    String prefix,
  ) async {
    try {
      final sanitizedName =
          '${prefix}_${title.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_')}';
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
        dir ??= await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      final file = File('${dir.path}/$sanitizedName.txt');
      await file.writeAsString(content);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
