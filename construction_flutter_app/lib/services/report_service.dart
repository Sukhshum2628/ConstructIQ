import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/project_model.dart';
import '../models/estimate_model.dart';
import '../models/deviation_model.dart';

class ReportService {
  /// Generates the PDF Document but does NOT trigger printing/sharing immediately.
  /// This allows the Document to be passed to the preview screen.
  pw.Document generatePdfDocument(
    ProjectModel project,
    EstimateModel? estimate,
    DeviationModel deviation,
  ) {
    final pdf = pw.Document();

    // Color Palette
    const primaryColor = PdfColor.fromInt(0xFF003874);
    const criticalColor = PdfColor.fromInt(0xFFB10010);
    const warningColor = PdfColor.fromInt(0xFFCA8A04);
    const surfaceColor = PdfColor.fromInt(0xFFF3F4F6);
    const textPrimary = PdfColor.fromInt(0xFF111827);
    const textSecondary = PdfColor.fromInt(0xFF4B5563);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        header: (pw.Context context) => pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Container(width: 12, height: 12, color: primaryColor),
                        pw.SizedBox(width: 6),
                        pw.Text("ConstructIQ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: primaryColor)),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text("Project Analysis Report", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22, color: textPrimary)),
                    pw.SizedBox(height: 4),
                    pw.Text("${project.name} | Jan-Dec 2026", style: pw.TextStyle(fontSize: 12, color: textSecondary)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFDCFCE7), borderRadius: pw.BorderRadius.circular(12)),
                      child: pw.Text("ACTIVE", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF166534))),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text("Gen Date: ${_formatDate(DateTime.now())}", style: pw.TextStyle(fontSize: 9, color: textSecondary)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 24),
          ],
        ),
        footer: (pw.Context context) => pw.Column(
          children: [
            pw.SizedBox(height: 12),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("ConstructIQ Enterprise | Advanced Site Intelligence", style: pw.TextStyle(fontSize: 8, color: textSecondary)),
                pw.Text("Page ${context.pageNumber} of ${context.pagesCount}", style: pw.TextStyle(fontSize: 8, color: textSecondary)),
              ],
            ),
          ],
        ),
        build: (pw.Context context) {
          return [
            // 1. BENTO DATA GRID
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ML Risk
                pw.Expanded(
                  flex: 4,
                  child: pw.Container(
                    padding: pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(color: surfaceColor, borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.Column(
                      children: [
                        pw.Text("ML OVERRUN PROBABILITY", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: textSecondary)),
                        pw.SizedBox(height: 12),
                        pw.Text("${(deviation.mlOverrunProbability * 100).toStringAsFixed(0)}%", style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: deviation.mlOverrunProbability > 0.5 ? criticalColor : primaryColor)),
                        pw.SizedBox(height: 8),
                        pw.Container(
                          padding: pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: pw.BoxDecoration(color: deviation.mlOverrunProbability > 0.5 ? criticalColor : primaryColor, borderRadius: pw.BorderRadius.circular(12)),
                          child: pw.Text(deviation.mlOverrunProbability > 0.5 ? "HIGH RISK" : "NORMAL", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 16),
                // AI Insight
                pw.Expanded(
                  flex: 8,
                  child: pw.Container(
                    padding: pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(color: surfaceColor, borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("AI Risk Assessment Summary", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                        pw.SizedBox(height: 8),
                        pw.Text(deviation.aiInsightSummary, style: pw.TextStyle(fontSize: 10, color: textPrimary)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 32),

            // 2. MATERIAL TABLE
            pw.Text("Material Estimates vs Actuals", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              context: context,
              border: null,
              headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              rowDecoration: pw.BoxDecoration(color: surfaceColor),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: pw.TextStyle(fontSize: 9),
              headerAlignment: pw.Alignment.centerLeft,
              headers: ['RESOURCE TYPE', 'ESTIMATED', 'ACTUAL TO DATE', 'VARIANCE'],
              data: estimate?.estimatedMaterials.entries.map((e) {
                return [e.key.toUpperCase(), "${e.value['quantity']} ${e.value['unit']}", "--", "--"];
              }).toList() ?? [['No Data', '--', '--', '--']],
              columnWidths: {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(1),
              },
            ),
            pw.SizedBox(height: 32),

            // 3. DEVIATION SUMMARY
            pw.Text("Deviation Summary", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: primaryColor)),
            pw.SizedBox(height: 12),
            pw.Row(
              children: [
                _buildPdfDeviationCard(
                  "CRITICAL FLAG", 
                  "#9901", 
                  "Steel Grade Mismatch", 
                  "Batch #A4-22 fails to meet tensile specifications by 4%. Immediate stoppage on level 4.", 
                  criticalColor,
                ),
                pw.SizedBox(width: 16),
                _buildPdfDeviationCard(
                  "WARNING FLAG", 
                  "#8721", 
                  "Curing Timeline", 
                  "Humidity levels exceeding 85% on Sector 62 site causing 24hr curing lag.", 
                  warningColor,
                ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  pw.Widget _buildPdfDeviationCard(String label, String id, String title, String description, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF9FAFB),
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        // Use a Row with a colored stripe box + content box to mimic the left border
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 5,
              height: 48, // Slightly taller for detail text
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(8),
                  bottomLeft: pw.Radius.circular(8),
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Padding(
                padding: pw.EdgeInsets.all(12),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: color)),
                    pw.SizedBox(height: 4),
                    pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(description, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, lineSpacing: 1.2)),
                    pw.SizedBox(height: 4),
                    pw.Text("Incident ID: $id", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return "${d.day}/${d.month}/${d.year}";
  }

  /// Triggers the system Print UI for a generated Document.
  Future<void> exportPdf(pw.Document document) async {
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => document.save());
  }

  /// Triggers the system Share UI for a generated Document.
  Future<void> sharePdf(pw.Document document, String name) async {
    await Printing.sharePdf(bytes: await document.save(), filename: '$name.pdf');
  }
}
