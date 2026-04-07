import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import '../../models/vendor_bill_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vendor_bill_provider.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';

class BillUploadScreen extends ConsumerStatefulWidget {
  final String projectId;
  const BillUploadScreen({super.key, required this.projectId});

  @override
  ConsumerState<BillUploadScreen> createState() => _BillUploadScreenState();
}

class _BillUploadScreenState extends ConsumerState<BillUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vendorController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedCategory = 'Cement';
  File? _selectedFile;
  String? _fileName;
  bool _isUploading = false;

  final List<String> _categories = [
    'Cement', 'Steel/Rebar', 'Sand/Aggregate', 
    'Bricks/Blocks', 'Equipment Rent', 'Labor Payment', 'Others'
  ];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _handleUpload() async {
    if (!_formKey.currentState!.validate() || _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a file'), backgroundColor: DFColors.warning),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      final user = ref.read(userProfileProvider).value;
      final bill = VendorBillModel(
        id: const Uuid().v4(),
        projectId: widget.projectId,
        vendorName: _vendorController.text.trim(),
        amount: double.parse(_amountController.text.trim()),
        date: DateTime.now(),
        category: _selectedCategory,
        fileUrl: '', // Will be updated by service
        uploadedBy: user?.name ?? 'Admin',
        createdAt: DateTime.now(),
      );

      await ref.read(vendorBillServiceProvider).uploadBill(
        bill: bill,
        file: _selectedFile!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill archived successfully!'), backgroundColor: DFColors.normal),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: \$e'), backgroundColor: DFColors.critical),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: const Text('Digital Archive: Bill'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BILL METADATA', style: DFTextStyles.labelSm),
              const SizedBox(height: 16),
              
              _buildTextField('Vendor / Supplier Name', _vendorController, Icons.business),
              const SizedBox(height: 16),
              
              _buildTextField('Amount (₹)', _amountController, Icons.payments_outlined, isNumeric: true),
              const SizedBox(height: 16),
              
              _buildCategoryDropdown(),
              const SizedBox(height: 32),
              
              Text('ATTACHMENT (PDF/IMAGE)', style: DFTextStyles.labelSm),
              const SizedBox(height: 16),
              _buildFilePicker(),
              const SizedBox(height: 48),
              
              _buildUploadButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {bool isNumeric = false}) {
    return DFCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          icon: Icon(icon, color: DFColors.primaryStitch, size: 20),
          labelText: label,
          labelStyle: DFTextStyles.caption,
          border: InputBorder.none,
        ),
        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return DFCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<String>(
        value: _selectedCategory,
        decoration: const InputDecoration(
          icon: Icon(Icons.category_outlined, color: DFColors.primaryStitch, size: 20),
          labelText: 'Material Category',
          border: InputBorder.none,
        ),
        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (v) => setState(() => _selectedCategory = v!),
      ),
    );
  }

  Widget _buildFilePicker() {
    return DFCard(
      onTap: _pickFile,
      padding: const EdgeInsets.all(24),
      color: _selectedFile == null ? DFColors.surfaceContainerLow : DFColors.normal.withValues(alpha: 0.05),
      child: Center(
        child: Column(
          children: [
            Icon(
              _selectedFile == null ? Icons.cloud_upload_outlined : Icons.check_circle_outline_rounded,
              size: 48,
              color: _selectedFile == null ? DFColors.primaryStitch : DFColors.normal,
            ),
            const SizedBox(height: 16),
            Text(
              _fileName ?? 'PICK INVOICE FILE',
              textAlign: TextAlign.center,
              style: DFTextStyles.body.copyWith(
                fontWeight: FontWeight.bold,
                color: _selectedFile == null ? DFColors.textPrimary : DFColors.normal,
              ),
            ),
            if (_selectedFile == null)
              Text('Supports PDF, JPG, PNG', style: DFTextStyles.caption),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadButton() {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: _isUploading ? null : _handleUpload,
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
                Text('ARCHIVE BILL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(width: 12),
                Icon(Icons.archive_outlined),
              ],
            ),
      ),
    );
  }
}
