import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/project_model.dart';
import '../models/deviation_model.dart';

class ReportGenerator {
  static Future<void> generateProjectReport({
    required ProjectModel project,
    required String managerName,
    required double estimatedCost,
    required double invoicedTotal,
    required DeviationResult deviation,
  }) async {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0, locale: 'en_IN');

    // Brand colors
    final primaryColor = PdfColor.fromHex('#003E7E');
    final secondaryColor = PdfColor.fromHex('#424751');
    final criticalColor = PdfColor.fromHex('#DC2626');
    final successColor = PdfColor.fromHex('#16A34A');
    final warningColor = PdfColor.fromHex('#D97706');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F2F4F7'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: primaryColor, width: 2),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ConstructIQ Financial Report',
                        style: pw.TextStyle(color: primaryColor, fontSize: 20, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Generated: ${DateFormat('MMM dd, yyyy - hh:mm a').format(DateTime.now())}', style: pw.TextStyle(color: secondaryColor, fontSize: 10)),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: primaryColor,
                      borderRadius: pw.BorderRadius.circular(20),
                    ),
                    child: pw.Text(
                      project.status.name.toUpperCase(),
                      style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Project Details
            pw.Text('PROJECT OVERVIEW', style: pw.TextStyle(color: primaryColor, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(color: primaryColor),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Name: ${project.name}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Location: ${project.location}'),
                      pw.Text('Manager: $managerName'),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Start Date: ${DateFormat('MMM dd, yyyy').format(project.startDate)}'),
                      pw.Text('End Date: ${DateFormat('MMM dd, yyyy').format(project.expectedEndDate)}'),
                      pw.Text('Est. Budget: ${currencyFormat.format(project.plannedBudget)}'),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Financial Summary
            pw.Text('FINANCIAL SUMMARY', style: pw.TextStyle(color: primaryColor, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(color: primaryColor),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPdfMetric('CAD Estimations', currencyFormat.format(estimatedCost), primaryColor),
                  pw.Container(width: 1, height: 40, color: PdfColors.grey300),
                  _buildPdfMetric('Actual Invoiced', currencyFormat.format(invoicedTotal), invoicedTotal > estimatedCost ? criticalColor : successColor),
                  pw.Container(width: 1, height: 40, color: PdfColors.grey300),
                  _buildPdfMetric('Variance', currencyFormat.format((estimatedCost - invoicedTotal).abs()), secondaryColor),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // AI Insights
            pw.Text('AI DEVIATION INSIGHTS', style: pw.TextStyle(color: primaryColor, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(color: primaryColor),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: deviation.overallSeverity == 'normal' ? PdfColor.fromHex('#DCFCE7') : PdfColor.fromHex('#FEE2E2'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Status: ${deviation.overallSeverity.toUpperCase()}',
                    style: pw.TextStyle(
                      color: deviation.overallSeverity == 'normal' ? successColor : criticalColor,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    deviation.aiInsightSummary.isEmpty ? 'No significant insights generated yet.' : deviation.aiInsightSummary,
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Material Deviations Table
            pw.Text('MATERIAL USAGE DEVIATIONS', style: pw.TextStyle(color: primaryColor, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(color: primaryColor),
            pw.SizedBox(height: 8),
            if (deviation.perMaterial.isEmpty)
              pw.Text('No material logs available yet.', style: pw.TextStyle(color: secondaryColor, fontStyle: pw.FontStyle.italic))
            else
              pw.TableHelper.fromTextArray(
                context: context,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                cellAlignment: pw.Alignment.centerLeft,
                data: [
                  ['Material', 'Unit', 'CAD Estimate', 'Actual Logged', 'Deviation %'],
                  ...deviation.perMaterial.entries.map((entry) {
                    final mat = entry.value;
                    final devPct = mat.deviationPct;
                    final devStr = devPct > 0 ? '+${devPct.toStringAsFixed(1)}%' : '${devPct.toStringAsFixed(1)}%';
                    
                    return [
                      entry.key.toUpperCase(),
                      mat.unit,
                      mat.estimated.toStringAsFixed(2),
                      mat.actual.toStringAsFixed(2),
                      devStr,
                    ];
                  }),
                ],
              ),
          ];
        },
      ),
    );

    // Show print preview
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: '${project.name}_Report');
  }

  static pw.Widget _buildPdfMetric(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
        pw.SizedBox(height: 4),
        pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#424751'))),
      ],
    );
  }
}
