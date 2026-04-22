import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/resource_log_model.dart';
import '../../providers/logging_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/project_model.dart';
import '../../providers/project_provider.dart';

class ResourceLoggingScreen extends ConsumerStatefulWidget {
  final String projectId;
  const ResourceLoggingScreen({super.key, required this.projectId});

  @override
  ConsumerState<ResourceLoggingScreen> createState() => _ResourceLoggingScreenState();
}

class _ResourceLoggingScreenState extends ConsumerState<ResourceLoggingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _laborController = TextEditingController();
  final _cementController = TextEditingController();
  final _sandController = TextEditingController();
  final _bricksController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    final project = ref.read(projectByIdProvider(widget.projectId)).value;
    if (project?.status == ProjectStatus.closed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot save log: Project is closed.')));
      }
      return;
    }

    final user = ref.read(userProfileProvider).value;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      final log = ResourceLogModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        projectId: widget.projectId,
        loggedBy: user.uid,
        date: DateTime.now(),
        materialUsage: {
          'cement': double.tryParse(_cementController.text) ?? 0.0,
          'sand': double.tryParse(_sandController.text) ?? 0.0,
          'bricks': double.tryParse(_bricksController.text) ?? 0.0,
        },
        equipmentList: [],
        laborHours: double.tryParse(_laborController.text) ?? 0.0,
        notes: _notesController.text,
        weatherCondition: 'Sunny',
        createdAt: DateTime.now(),
      );

      await ref.read(loggingServiceProvider).addLog(log);
      _clearForm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log saved successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save log: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _clearForm() {
    _laborController.clear();
    _cementController.clear();
    _sandController.clear();
    _bricksController.clear();
    _notesController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(projectLogsProvider(widget.projectId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Resource Logging'),
          bottom: const TabBar(
            tabs: [Tab(text: 'New Entry'), Tab(text: 'History')],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLogForm(),
            _buildLogHistory(logsAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildLogForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Consumer(
              builder: (context, ref, _) {
                final project = ref.watch(projectByIdProvider(widget.projectId)).value;
                if (project?.status == ProjectStatus.closed) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock, color: Colors.red, size: 18),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('PROJECT CLOSED. NO ENTRIES ALLOWED.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            _buildField(_laborController, 'Labor Hours', Icons.people),
            const SizedBox(height: 16),
            _buildField(_cementController, 'Cement (Bags)', Icons.inventory_2),
            const SizedBox(height: 16),
            _buildField(_sandController, 'Sand (m³)', Icons.layers),
            const SizedBox(height: 16),
            _buildField(_bricksController, 'Bricks (Pcs)', Icons.grid_view),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_isSaving || (ref.read(projectByIdProvider(widget.projectId)).value?.status == ProjectStatus.closed)) ? null : _handleSave,
                child: _isSaving ? const CircularProgressIndicator() : const Text('SUBMIT DAILY LOG'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      keyboardType: TextInputType.number,
      validator: (v) => v!.isEmpty ? 'Required' : null,
    );
  }

  Widget _buildLogHistory(AsyncValue<List<ResourceLogModel>> logsAsync) {
    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) return const Center(child: Text('No logs yet.'));
        return ListView.builder(
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text(DateFormat('EEE, MMM d, yyyy').format(log.date)),
                subtitle: Text('Cement: ${log.materialUsage['cement']} bags | Labor: ${log.laborHours}h'),
                trailing: const Icon(Icons.info_outline),
                onTap: () {
                  // Show detail dialog
                },
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
