import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/vendor_bill_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vendor_bill_provider.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../utils/material_rates.dart';
import '../../services/estimation_service.dart';
import '../../providers/estimation_provider.dart';
import '../../models/project_model.dart';
import '../../providers/project_provider.dart';

class BillItemController {
  final description = TextEditingController();
  final quantity = TextEditingController();
  final unit = TextEditingController();
  final rate = TextEditingController();
  String? selectedMaterial;
  
  void dispose() {
    description.dispose();
    quantity.dispose();
    unit.dispose();
    rate.dispose();
  }

  double get amount {
    final q = double.tryParse(quantity.text) ?? 0.0;
    final r = double.tryParse(rate.text) ?? 0.0;
    return q * r;
  }
}

class BillUploadScreen extends ConsumerStatefulWidget {
  final String projectId;
  const BillUploadScreen({super.key, required this.projectId});

  @override
  ConsumerState<BillUploadScreen> createState() => _BillUploadScreenState();
}

class _BillUploadScreenState extends ConsumerState<BillUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vendorController = TextEditingController();
  final _amountController = TextEditingController(); // Now derived
  final List<BillItemController> _itemControllers = [];
  
  File? _selectedFile;
  String? _fileName;
  bool _isUploading = false;
  bool _isScanning = false;

  final List<String> _categories = [
    'Cement', 'Steel/Rebar', 'Sand/Aggregate', 
    'Bricks/Blocks', 'Equipment Rent', 'Labor Payment', 'Others'
  ];

  static const List<Map<String, String>> _materialOptions = [
    {'value': 'cement',    'label': 'Cement',    'unit': 'Bag'},
    {'value': 'bricks',    'label': 'Bricks',    'unit': 'Nos'},
    {'value': 'steel',     'label': 'Steel',     'unit': 'Kg'},
    {'value': 'sand',      'label': 'Sand',      'unit': 'cu.ft'},
    {'value': 'aggregate', 'label': 'Aggregate', 'unit': 'cu.ft'},
    {'value': 'other',     'label': 'Other',     'unit': 'units'},
  ];

  @override
  void initState() {
    super.initState();
    // Start with one item
    _addItem();
  }

  @override
  void dispose() {
    _vendorController.dispose();
    _amountController.dispose();
    for (var controller in _itemControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() {
      final controller = BillItemController();
      controller.quantity.addListener(_updateTotalAmount);
      controller.rate.addListener(_updateTotalAmount);
      _itemControllers.add(controller);
    });
  }

  void _removeItem(int index) {
    if (_itemControllers.length > 1) {
      setState(() {
        final controller = _itemControllers.removeAt(index);
        controller.dispose();
        _updateTotalAmount();
      });
    }
  }

  void _updateTotalAmount() {
    double total = 0;
    for (var controller in _itemControllers) {
      total += controller.amount;
    }
    _amountController.text = total.toStringAsFixed(2);
    setState(() {}); // Rebuild to show updated total in summary
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      setState(() {
        _selectedFile = file;
        _fileName = result.files.single.name;
        _isScanning = true;
      });

      try {
        final details = await ref.read(estimationServiceProvider).parseInvoiceLocal(file);
        
        setState(() {
          if (details['vendorName'] != null) {
            _vendorController.text = details['vendorName'];
          }
          
          if (details['lineItems'] != null && (details['lineItems'] as List).isNotEmpty) {
            // Clear initial item if it's empty
            if (_itemControllers.length == 1 && _itemControllers[0].selectedMaterial == null && _itemControllers[0].description.text.isEmpty) {
              _itemControllers[0].dispose();
              _itemControllers.clear();
            }
            
            for (var item in details['lineItems']) {
              final controller = BillItemController();
              controller.description.text = item['description'] ?? '';
              controller.quantity.text = (item['quantity'] ?? 0).toString();
              controller.unit.text = item['unit'] ?? 'Unit';
              controller.rate.text = (item['ratePerUnit'] ?? 0).toString();
              
              // Try to auto-match material dropdown
              final descLower = (item['description'] ?? '').toString().toLowerCase();
              final materialKey = item['material'] ?? '';
              
              // First try direct match from backend 'material' field
              bool found = false;
              for (var opt in _materialOptions) {
                if (opt['value'] == materialKey) {
                  controller.selectedMaterial = opt['value'];
                  found = true;
                  break;
                }
              }
              
              // Fallback to keyword search in description
              if (!found) {
                for (var opt in _materialOptions) {
                  if (descLower.contains(opt['value']!)) {
                    controller.selectedMaterial = opt['value'];
                    break;
                  }
                }
              }
              
              controller.quantity.addListener(_updateTotalAmount);
              controller.rate.addListener(_updateTotalAmount);
              _itemControllers.add(controller);
            }
            _updateTotalAmount();
          }

          if (details['warnings'] != null && (details['warnings'] as List).isNotEmpty) {
            final warnings = (details['warnings'] as List).join('\n');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Extraction Warnings:\n$warnings'),
                backgroundColor: DFColors.warning,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice parsed with local engine!'), backgroundColor: DFColors.normal),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e. You can still enter details manually.'), backgroundColor: DFColors.warning),
        );
      } finally {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _handleUpload() async {
    if (!_formKey.currentState!.validate() || _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a file'), backgroundColor: DFColors.warning),
      );
      return;
    }

    final project = ref.read(projectByIdProvider(widget.projectId)).value;
    if (project?.status == ProjectStatus.closed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot upload bill: Project is closed.'), backgroundColor: DFColors.critical),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      final user = ref.read(currentUserProfileProvider);
      
      final items = _itemControllers.map((c) => BillItem(
        description: c.description.text.trim(),
        quantity: double.tryParse(c.quantity.text.trim()) ?? 0.0,
        unit: c.unit.text.trim(),
        rate: double.tryParse(c.rate.text.trim()) ?? 0.0,
        amount: c.amount,
      )).toList();

      final totalAmount = items.fold(0.0, (sum, item) => sum + item.amount);

      final bill = VendorBillModel(
        id: const Uuid().v4(),
        projectId: widget.projectId,
        vendorName: _vendorController.text.trim(),
        amount: totalAmount,
        date: DateTime.now(),
        category: items.isNotEmpty ? (items.first.description.split(' - ').first) : 'General',
        fileUrl: '', 
        uploadedBy: user?.name ?? 'Admin',
        items: items,
        createdAt: DateTime.now(),
      );

      await ref.read(vendorBillServiceProvider).uploadBill(
        bill: bill,
        file: _selectedFile!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice itemized and archived!'), backgroundColor: DFColors.normal),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: DFColors.critical),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectByIdProvider(widget.projectId));
    
    return Stack(
      children: [
        Scaffold(
          backgroundColor: DFColors.background,
          appBar: AppBar(
            title: const Text('New Invoice Entry'),
            backgroundColor: Colors.white,
            elevation: 0,
          ),
          body: projectAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (project) {
              final isClosed = project?.status == ProjectStatus.closed;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isClosed)
                        Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: DFColors.critical.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_rounded, color: DFColors.critical, size: 18),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'PROJECT IS CLOSED. UPLOADS ARE DISABLED.',
                                  style: DFTextStyles.labelSm.copyWith(color: DFColors.critical, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text('GENERAL INFORMATION', style: DFTextStyles.labelSm),
                  const SizedBox(height: 16),
                  _buildTextField('Vendor / Supplier Name', _vendorController, Icons.business, hint: 'Vendor / Supplier name'),
                  const SizedBox(height: 32),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('LINE ITEMS', style: DFTextStyles.labelSm),
                      TextButton.icon(
                        onPressed: _addItem,
                        icon: const Icon( Icons.add_circle_outline, size: 18),
                        label: const Text('Add Item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._itemControllers.asMap().entries.map((entry) => _buildItemRow(entry.key, entry.value)),
                  
                  const SizedBox(height: 32),
                  Text('SUMMARY', style: DFTextStyles.labelSm),
                  const SizedBox(height: 16),
                  _buildTotalSummary(),
                  
                  const SizedBox(height: 32),
                  Text('DOCUMENT PROOF', style: DFTextStyles.labelSm),
                  const SizedBox(height: 16),
                  _buildFilePicker(),
                  const SizedBox(height: 48),
                  
                  _buildUploadButton(isClosed),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    ),
        if (_isScanning)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Material(
                type: MaterialType.transparency,
                child: DFCard(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: DFColors.primaryStitch),
                      SizedBox(height: 24),
                      Text('Scanning Invoice...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('AI is extracting itemized details', style: TextStyle(fontSize: 14, color: Colors.black54)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemRow(int index, BillItemController controller) {
    return DFCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Material and Delete
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: controller.selectedMaterial,
                  decoration: const InputDecoration(
                    labelText: 'Material',
                    labelStyle: TextStyle(fontSize: 10),
                    isDense: true,
                    border: UnderlineInputBorder(),
                  ),
                  items: _materialOptions.map((m) => DropdownMenuItem(
                    value: m['value'],
                    child: Text(m['label']!, style: const TextStyle(fontSize: 13)),
                  )).toList(),
                  onChanged: (val) {
                    setState(() {
                      controller.selectedMaterial = val;
                      if (val != null) {
                        final option = _materialOptions.firstWhere((o) => o['value'] == val);
                        controller.unit.text = option['unit']!;
                        controller.rate.text = MaterialRates.getRateForMaterial(val).toString();
                        if (controller.description.text.isEmpty) {
                          controller.description.text = option['label']!;
                        }
                        _updateTotalAmount();
                      }
                    });
                  },
                ),
              ),
              if (_itemControllers.length > 1)
                IconButton(
                  onPressed: () => _removeItem(index),
                  icon: const Icon(Icons.remove_circle) ,
                  color: DFColors.critical.withValues(alpha: 0.7),
                  iconSize: 22,
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Row 2: Qty, Unit, Rate
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildSmallField('Qty', controller.quantity, isNumeric: true, hint: 'Qty'),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildSmallField('Unit', controller.unit, hint: 'Unit'),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildSmallField('Rate (₹)', controller.rate, isNumeric: true, hint: 'Rate'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: controller.description,
            decoration: const InputDecoration(
              hintText: 'Description (OPC 43 Grade, Brand optional)',
              isDense: true,
              border: InputBorder.none,
              hintStyle: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total: ₹${NumberFormat('#,##,###.##').format(controller.amount)}',
              style: DFTextStyles.body.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallField(String label, TextEditingController controller, {bool isNumeric = false, String? hint}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: DFTextStyles.body.copyWith(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: DFTextStyles.caption.copyWith(fontSize: 10),
        isDense: true,
        border: const UnderlineInputBorder(),
      ),
      validator: (v) => v == null || v.isEmpty ? '' : null,
    );
  }

  Widget _buildTotalSummary() {
    final total = double.tryParse(_amountController.text) ?? 0.0;
    return DFCard(
      padding: const EdgeInsets.all(20),
      color: DFColors.primaryStitch.withValues(alpha: 0.05),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('TOTAL INVOICE AMOUNT', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold)),
          Text(
            '₹${NumberFormat('#,##,###.##').format(total)}',
            style: DFTextStyles.metricLarge.copyWith(fontSize: 22, color: DFColors.primaryStitch),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {String? hint}) {
    return DFCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          icon: Icon(icon, color: DFColors.primaryStitch, size: 20),
          labelText: label,
          hintText: hint,
          labelStyle: DFTextStyles.caption,
          border: InputBorder.none,
        ),
        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      ),
    );
  }


  Widget _buildFilePicker() {
    final project = ref.read(projectByIdProvider(widget.projectId)).value;
    final isClosed = project?.status == ProjectStatus.closed;

    return DFCard(
      onTap: isClosed ? null : _pickFile,
      padding: const EdgeInsets.all(24),
      color: isClosed ? DFColors.outlineVariant.withValues(alpha: 0.1) : (_selectedFile == null ? DFColors.surfaceContainerLow : DFColors.normal.withValues(alpha: 0.05)),
      child: Center(
        child: Column(
          children: [
            Icon(
              _selectedFile == null ? Icons.cloud_upload_outlined : Icons.check_circle_outline_rounded,
              size: 48,
              color: isClosed ? DFColors.outlineVariant : (_selectedFile == null ? DFColors.primaryStitch : DFColors.normal),
            ),
            const SizedBox(height: 16),
            Text(
              isClosed ? 'PROJECT CLOSED' : (_fileName ?? 'PICK INVOICE FILE'),
              textAlign: TextAlign.center,
              style: DFTextStyles.body.copyWith(
                fontWeight: FontWeight.bold,
                color: isClosed ? DFColors.textSecondary : (_selectedFile == null ? DFColors.textPrimary : DFColors.normal),
              ),
            ),
            if (!isClosed && _selectedFile == null)
              Text('Supports PDF, JPG, PNG', style: DFTextStyles.caption),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadButton(bool isClosed) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: (_isUploading || isClosed) ? null : _handleUpload,
        style: ElevatedButton.styleFrom(
          backgroundColor: DFColors.primaryStitch,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
        child: _isUploading 
          ? const CircularProgressIndicator(color: Colors.white)
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('ARCHIVE INVOICE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(width: 12),
                Icon(Icons.archive_outlined),
              ],
            ),
      ),
    );
  }
}
