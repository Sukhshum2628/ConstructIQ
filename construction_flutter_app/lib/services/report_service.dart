import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/project_model.dart';
import '../models/estimate_model.dart';
import '../models/deviation_model.dart';
import '../models/vendor_bill_model.dart';
import '../models/resource_log_model.dart';
import '../utils/material_rates.dart';

class ReportService {
  // Color Palette Constants
  static const _primaryColor = PdfColor.fromInt(0xFF003874);
  static const _criticalColor = PdfColor.fromInt(0xFFB10010);
  static const _surfaceColor = PdfColor.fromInt(0xFFF3F4F6);
  static const _textPrimary = PdfColor.fromInt(0xFF111827);
  static const _textSecondary = PdfColor.fromInt(0xFF4B5563);

  /// Generates the PDF Document including financial and log history.
  pw.Document generatePdfDocument({
    required ProjectModel project,
    required EstimateModel? estimate,
    required DeviationModel deviation,
    required List<VendorBillModel> bills,
    required List<ResourceLogModel> logs,
  }) {
    final pdf = pw.Document();
    final currencyFormat = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 0, locale: 'en_IN');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
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
                        pw.Container(width: 12, height: 12, color: _primaryColor),
                        pw.SizedBox(width: 6),
                        pw.Text("ConstructIQ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: _primaryColor)),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text("Project Status Report", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24, color: _textPrimary)),
                    pw.SizedBox(height: 4),
                    pw.Text("${project.name} | Site Analysis", style: pw.TextStyle(fontSize: 12, color: _textSecondary)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFDCFCE7), borderRadius: pw.BorderRadius.circular(12)),
                      child: pw.Text(project.status.name.toUpperCase(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF166534))),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text("Date: ${_formatDate(DateTime.now())}", style: pw.TextStyle(fontSize: 9, color: _textSecondary)),
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
                pw.Text("ConstructIQ Pro | Confidential Site Data", style: pw.TextStyle(fontSize: 8, color: _textSecondary)),
                pw.Text("Ref: CQ-${DateTime.now().year}-${project.projectId.substring(0, 4).toUpperCase()} | Page ${context.pageNumber} of ${context.pagesCount}", style: pw.TextStyle(fontSize: 8, color: _textSecondary)),
              ],
            ),
          ],
        ),
        build: (pw.Context context) {
          final totalSpent = bills.fold(0.0, (sum, b) => sum + b.amount);
          
          double materialCost = 0.0;
          if (estimate != null) {
            estimate.estimatedMaterials.forEach((name, data) {
              if (name == 'metadata') return;
              final qty = (data['quantity'] as num).toDouble();
              materialCost += MaterialRates.calculateEstimatedCost(name, qty);
            });
          }
          
          final contractorShare = materialCost * 1.5;
          final totalEstimate = materialCost * 2.5;
          
          return [
            // 1. FINANCIAL SUMMARY
            pw.Text("Summary of Accounts", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
            pw.SizedBox(height: 12),
            pw.Row(
              children: [
                _buildReportStatCard("CAD MATERIALS", currencyFormat.format(materialCost), _textSecondary),
                pw.SizedBox(width: 16),
                _buildReportStatCard("CONTRACTOR ESTIMATE", currencyFormat.format(contractorShare), _textSecondary),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              children: [
                _buildReportStatCard("TOTAL PROJECT EST.", currencyFormat.format(totalEstimate), _primaryColor),
                pw.SizedBox(width: 16),
                _buildReportStatCard(
                  "ACTUAL EXPENDITURE", 
                  currencyFormat.format(totalSpent), 
                  totalSpent > totalEstimate ? _criticalColor : _primaryColor
                ),
              ],
            ),
            pw.SizedBox(height: 32),

            // 2. MATERIAL BREAKDOWN (CAD ESTIMATES)
            pw.Text("Resource Quantity Estimates (CAD-Derived)", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
            pw.SizedBox(height: 12),
            if (estimate == null)
              pw.Text("No CAD estimation data available.", style: pw.TextStyle(fontSize: 10, color: _textSecondary))
            else
              pw.TableHelper.fromTextArray(
                context: context,
                border: null,
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: _primaryColor),
                rowDecoration: const pw.BoxDecoration(color: _surfaceColor),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerAlignment: pw.Alignment.centerLeft,
                headers: ['MATERIAL', 'QUANTITY', 'UNIT RATE', 'SUBTOTAL'],
                data: estimate.estimatedMaterials.entries.where((e) => e.key != 'metadata').map((entry) {
                  final name = entry.key;
                  final data = entry.value;
                  final qty = (data['quantity'] as num).toDouble();
                  
                  final effectiveQty = MaterialRates.getQuantityInRateUnit(name, qty);
                  final rateUnit = MaterialRates.getRateUnitForMaterial(name);
                  final rate = MaterialRates.getRateForMaterial(name);
                  final subtotal = MaterialRates.calculateEstimatedCost(name, qty);
                  
                  return [
                    name.toUpperCase(),
                    '${effectiveQty.toStringAsFixed(1)} $rateUnit',
                    rate > 0 ? 'Rs. $rate / $rateUnit' : 'N/A',
                    currencyFormat.format(subtotal),
                  ];
                }).toList(),
              ),
            pw.SizedBox(height: 32),

            // 3. RESOURCE LOGS OVERVIEW
            pw.Text("Site Execution Logs (Recent)", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
            pw.SizedBox(height: 12),
            if (logs.isEmpty)
              pw.Text("No execution logs found for this period.", style: pw.TextStyle(fontSize: 10, color: _textSecondary))
            else
              pw.TableHelper.fromTextArray(
                context: context,
                border: null,
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: _primaryColor),
                rowDecoration: const pw.BoxDecoration(color: _surfaceColor),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headers: ['DATE', 'ENGINEER', 'LABOR HOURS', 'EQUIPMENT'],
                data: logs.take(10).map((l) {
                  return [
                    _formatDate(l.date),
                    l.loggedBy,
                    "${l.laborHours.toInt()} Hours",
                    "${l.equipmentList.length} Units Used",
                  ];
                }).toList(),
              ),
            pw.SizedBox(height: 32),

            // 4. INVOICE LEDGER
            pw.Text("Invoicing Ledger", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
            pw.SizedBox(height: 12),
            if (bills.isEmpty)
              pw.Text("No invoices archived.", style: pw.TextStyle(fontSize: 10, color: _textSecondary))
            else
              pw.TableHelper.fromTextArray(
                context: context,
                border: null,
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: _primaryColor),
                rowDecoration: const pw.BoxDecoration(color: _surfaceColor),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headers: ['DATE', 'VENDOR', 'CATEGORY', 'AMOUNT'],
                data: bills.map((b) {
                  return [
                    _formatDate(b.date),
                    b.vendorName,
                    b.category,
                    currencyFormat.format(b.amount),
                  ];
                }).toList(),
              ),
            pw.SizedBox(height: 32),

            // 5. ML RISK ANALYSIS
            pw.Text("Predictive Intelligence", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(color: _surfaceColor, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("ML OVERRUN RISK PROBABILITY", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _textSecondary)),
                      pw.Text("${(deviation.mlOverrunProbability * 100).toInt()}%", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: deviation.mlOverrunProbability > 0.5 ? _criticalColor : _primaryColor)),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text("AI ASSESSMENT:", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
                  pw.SizedBox(height: 4),
                  pw.Text(deviation.aiInsightSummary.isNotEmpty ? deviation.aiInsightSummary : "No AI assessment available.", style: pw.TextStyle(fontSize: 10, color: _textPrimary, lineSpacing: 1.4)),
                ],
              ),
            ),
            pw.SizedBox(height: 32),

            // 6. ANOMALY REPORT
            if (deviation.breakdown.containsKey('anomalies')) ...[
              pw.Text("Anomaly Report", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _primaryColor)),
              pw.SizedBox(height: 12),
              ...((deviation.breakdown['anomalies'] as List? ?? []).map((anomaly) {
                if (anomaly is! Map<String, dynamic>) return pw.SizedBox();
                final isCritical = anomaly['severity']?.toString().toLowerCase() == 'critical';
                
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: _surfaceColor,
                    border: pw.Border(left: pw.BorderSide(color: isCritical ? _criticalColor : PdfColors.orange, width: 3)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(anomaly['title']?.toString().toUpperCase() ?? "RESOURCE ANOMALY", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: isCritical ? _criticalColor : _primaryColor)),
                          pw.Text("ID: ${anomaly['id'] ?? 'N/A'}", style: pw.TextStyle(fontSize: 8, color: _textSecondary)),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(anomaly['description']?.toString() ?? "", style: pw.TextStyle(fontSize: 9, color: _textPrimary)),
                    ],
                  ),
                );
              })),
            ],
          ];
        },
      ),
    );

    return pdf;
  }

  pw.Widget _buildReportStatCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: _surfaceColor,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
            pw.SizedBox(height: 8),
            pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color)),
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
