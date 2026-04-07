import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../models/project_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_button.dart';

class CreateProjectScreen extends ConsumerStatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  ConsumerState<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends ConsumerState<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _budgetController = TextEditingController();
  final _typeController = TextEditingController();
  String? _selectedOwnerId;
  bool _isLoading = false;

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = ref.read(authStateChangesProvider).value;
      if (user == null) return;

      final project = ProjectModel(
        projectId: const Uuid().v4(),
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        startDate: DateTime.now(),
        expectedEndDate: DateTime.now().add(const Duration(days: 365)),
        status: ProjectStatus.planning,
        createdBy: user.uid,
        teamMembers: [user.uid],
        plannedBudget: double.parse(_budgetController.text),
        projectType: _typeController.text.trim(),
        cadFileUrl: '',
        estimationStatus: EstimationStatus.pending,
        createdAt: DateTime.now(),
        ownerUserId: _selectedOwnerId,
      );

      await ref.read(projectServiceProvider).createProject(project);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: DFColors.criticalBg,
        )
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        backgroundColor: DFColors.background,
        elevation: 0,
        leading: const BackButton(color: DFColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: DFSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Create Project', style: DFTextStyles.screenTitle.copyWith(fontSize: 22)),
              const SizedBox(height: DFSpacing.xs),
              Text('Initialize a new construction mission.', style: DFTextStyles.caption),
              const SizedBox(height: DFSpacing.xl),
              
              _sectionHeader('BASIC INFORMATION'),
              _buildField('Project Name', _nameController, 'e.g. Skyline Tower'),
              const SizedBox(height: DFSpacing.md),
              _buildField('Location', _locationController, 'City, Site Address'),
              
              const SizedBox(height: DFSpacing.xl),
              _sectionHeader('PROJECT METADATA'),
              Row(
                children: [
                   Expanded(child: _buildField('Budget (₹)', _budgetController, '0.00', isNumber: true)),
                   const SizedBox(width: DFSpacing.md),
                   Expanded(child: _buildField('Type', _typeController, 'e.g. Infrastructure')),
                ],
              ),
              
              const SizedBox(height: DFSpacing.xl),
              _sectionHeader('PROJECT OWNER'),
              _buildOwnerDropdown(),
              
              const SizedBox(height: DFSpacing.xxl),
              DFButton(
                label: 'Initialize Project',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
              SizedBox(height: DFSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: DFSpacing.sm),
      child: Text(
        title,
        style: DFTextStyles.caption.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: DFColors.primary,
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
        SizedBox(height: DFSpacing.xs),
        TextFormField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          validator: (v) => (v == null || v.isEmpty) ? 'Field required' : null,
          style: DFTextStyles.body,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: DFTextStyles.caption.copyWith(color: DFColors.textCaption),
            filled: true,
            fillColor: DFColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.all(DFSpacing.md),
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerDropdown() {
    final ownersAsync = ref.watch(allOwnersProvider);
    
    return ownersAsync.when(
      loading: () => const Center(child: LinearProgressIndicator()),
      error: (e, _) => Text('Failed to load owners: $e', style: DFTextStyles.caption.copyWith(color: DFColors.critical)),
      data: (owners) {
        if (owners.isEmpty) {
          return Text('No registered owners found. Please ask client to sign up first.', style: DFTextStyles.caption.copyWith(color: DFColors.outline));
        }
        return Container(
          padding: EdgeInsets.symmetric(horizontal: DFSpacing.md),
          decoration: BoxDecoration(
            color: DFColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedOwnerId,
              isExpanded: true,
              hint: Text('Select Project Owner', style: DFTextStyles.caption),
              items: owners.map((o) => DropdownMenuItem(
                value: o.uid,
                child: Text(o.name, style: DFTextStyles.body),
              )).toList(),
              onChanged: (val) => setState(() => _selectedOwnerId = val),
            ),
          ),
        );
      },
    );
  }
}
