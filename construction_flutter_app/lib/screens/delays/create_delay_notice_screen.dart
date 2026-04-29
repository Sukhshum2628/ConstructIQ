import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_button.dart';
import '../../services/delay_notice_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/team_provider.dart';
import '../../models/delay_notice_model.dart';

class CreateDelayNoticeScreen extends ConsumerStatefulWidget {
  final String projectId;

  const CreateDelayNoticeScreen({super.key, required this.projectId});

  @override
  ConsumerState<CreateDelayNoticeScreen> createState() => _CreateDelayNoticeScreenState();
}

class _CreateDelayNoticeScreenState extends ConsumerState<CreateDelayNoticeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  DelayNoticeType _selectedType = DelayNoticeType.materialDelivery;
  DateTime? _expectedDate;
  final List<String> _selectedMaterials = [];
  bool _isSubmitting = false;

  final List<String> _availableMaterials = ['Cement', 'Bricks', 'Steel', 'Sand', 'Aggregate'];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate ?? DateTime.now().subtract(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().subtract(const Duration(days: 1)), // Must be in past
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: DFColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _expectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _expectedDate == null) {
      if (_expectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select the expected delivery date')),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authState = ref.read(authStateChangesProvider);
      final uid = authState.value?.uid;
      if (uid == null) throw 'User not authenticated';

      final currentUser = await ref.read(userByIdProvider(uid).future);
      final creatorName = currentUser?.name ?? 'Engineer';

      // Fetch all engineers on the project
      final teamMembers = await ref.read(teamMembersProvider(widget.projectId).future);
      final otherEngineerUids = teamMembers
          .where((u) => u.role == 'engineer' && u.uid != uid)
          .map((u) => u.uid)
          .toList();

      await DelayNoticeService().createNotice(
        projectId: widget.projectId,
        type: _selectedType.name.replaceAll(RegExp(r'(?=[A-Z])'), '_').toLowerCase(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        affectedMaterials: _selectedMaterials,
        expectedDeliveryDate: _expectedDate!,
        creatorName: creatorName,
        otherEngineerUids: otherEngineerUids,
      );

      if (!mounted) return;

      final message = otherEngineerUids.isEmpty
          ? 'Notice automatically approved (you are the only engineer)'
          : 'Notice sent to ${otherEngineerUids.length} engineers for review';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: DFColors.success),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: DFColors.critical),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: Text('File Delay Notice', style: DFTextStyles.sectionHeader.copyWith(color: Colors.white)),
        backgroundColor: DFColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(DFSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Delay Category'),
              const SizedBox(height: DFSpacing.sm),
              _buildTypeDropdown(),
              
              const SizedBox(height: DFSpacing.md),
              _buildSectionTitle('Notice Title'),
              const SizedBox(height: DFSpacing.sm),
              TextFormField(
                controller: _titleController,
                decoration: _inputDecoration('e.g. Cement delivery 3 days overdue'),
                style: DFTextStyles.body,
                validator: (v) => (v == null || v.length < 10) ? 'Min 10 characters required' : null,
              ),

              if (_selectedType == DelayNoticeType.materialDelivery) ...[
                const SizedBox(height: DFSpacing.md),
                _buildSectionTitle('Affected Materials'),
                const SizedBox(height: DFSpacing.sm),
                Wrap(
                  spacing: 8,
                  children: _availableMaterials.map((m) {
                    final isSelected = _selectedMaterials.contains(m.toLowerCase());
                    return FilterChip(
                      label: Text(m, style: DFTextStyles.labelSm.copyWith(
                        color: isSelected ? Colors.white : DFColors.textSecondary,
                      )),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          if (val) _selectedMaterials.add(m.toLowerCase());
                          else _selectedMaterials.remove(m.toLowerCase());
                        });
                      },
                      selectedColor: DFColors.primary,
                      checkmarkColor: Colors.white,
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: DFSpacing.md),
              _buildSectionTitle('Expected Delivery Date'),
              const SizedBox(height: DFSpacing.sm),
              InkWell(
                onTap: _selectDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: DFColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DFColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 20, color: DFColors.primary),
                      const SizedBox(width: 12),
                      Text(
                        _expectedDate == null 
                          ? 'Select Date' 
                          : DateFormat('MMM dd, yyyy').format(_expectedDate!),
                        style: DFTextStyles.body.copyWith(
                          color: _expectedDate == null ? DFColors.textCaption : DFColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: DFSpacing.md),
              _buildSectionTitle('Detailed Description'),
              const SizedBox(height: DFSpacing.sm),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: _inputDecoration('Explain the impact on site work...'),
                style: DFTextStyles.body,
                validator: (v) => (v == null || v.length < 30) ? 'Min 30 characters required' : null,
              ),

              const SizedBox(height: DFSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: DFButton(
                  label: 'Send for Team Review',
                  onPressed: _isSubmitting ? null : _submit,
                  isLoading: _isSubmitting,
                  icon: Icons.send_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold));
  }

  Widget _buildTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: DFColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DFColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DelayNoticeType>(
          value: _selectedType,
          isExpanded: true,
          onChanged: (val) => setState(() => _selectedType = val!),
          items: DelayNoticeType.values.map((t) {
            String label = switch (t) {
              DelayNoticeType.materialDelivery => 'Material Delivery',
              DelayNoticeType.equipment        => 'Equipment / Machinery',
              DelayNoticeType.labour           => 'Labour Shortage',
              DelayNoticeType.other            => 'Other Site Issue',
            };
            return DropdownMenuItem(value: t, child: Text(label, style: DFTextStyles.body));
          }).toList(),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: DFTextStyles.caption,
      filled: true,
      fillColor: DFColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DFColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DFColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DFColors.primary, width: 1.5),
      ),
    );
  }
}
