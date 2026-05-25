import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/resource_log_model.dart';
import '../../providers/logging_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/project_model.dart';
import '../../providers/project_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../providers/resource_log_provider.dart';
import '../../providers/ml_cache_provider.dart';

class ResourceLoggingScreen extends ConsumerStatefulWidget {
  final String projectId;
  const ResourceLoggingScreen({super.key, required this.projectId});

  @override
  ConsumerState<ResourceLoggingScreen> createState() => _ResourceLoggingScreenState();
}

class _ResourceLoggingScreenState extends ConsumerState<ResourceLoggingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _steelController = TextEditingController();
  final _cementController = TextEditingController();
  final _sandController = TextEditingController();
  final _bricksController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;

  Future<Position?> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    final project = ref.read(projectByIdProvider(widget.projectId)).value;
    if (project?.status == ProjectStatus.closed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot save log: Project is closed.')));
      }
      return;
    }

    final user = ref.read(currentUserProfileProvider);
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      // Capture Geotag
      final position = await _determinePosition();
      Map<String, double>? location;
      if (position != null) {
        location = {'lat': position.latitude, 'lng': position.longitude};
      }

      // Enforce GPS must be turned on to verify site attendance
      if (location == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Submission Blocked: GPS must be turned on to verify site attendance.'),
            ),
          );
          setState(() => _isSaving = false);
          return;
        }
      }

      // Check distance in meters against project coordinate centroid
      double projectLat = 32.7266; // Default to Jammu centroid
      double projectLng = 74.8570;
      
      if (project != null) {
        final loc = project.location;
        if (loc.contains(',')) {
          final parts = loc.split(',');
          if (parts.length == 2) {
            final lat = double.tryParse(parts[0].trim());
            final lng = double.tryParse(parts[1].trim());
            if (lat != null && lng != null) {
              projectLat = lat;
              projectLng = lng;
            }
          }
        } else {
          final locLower = loc.toLowerCase();
          if (locLower.contains('noida')) {
            projectLat = 28.5355;
            projectLng = 77.3910;
          } else if (locLower.contains('delhi')) {
            projectLat = 28.6139;
            projectLng = 77.2090;
          } else if (locLower.contains('mumbai')) {
            projectLat = 19.0760;
            projectLng = 72.8777;
          } else if (locLower.contains('udhampur')) {
            projectLat = 32.9248;
            projectLng = 75.1433;
          }
        }
      }

      double distanceInMeters = Geolocator.distanceBetween(
        location['lat']!,
        location['lng']!,
        projectLat,
        projectLng,
      );

      // Max allowable distance: 1.0 km (1000m) for strict geofencing audit compliance
      const double maxDistanceMeters = 1000;
      
      if (distanceInMeters > maxDistanceMeters) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Geofence Violation: You are ${(distanceInMeters / 1000).toStringAsFixed(1)} km away from the project site. Log submission blocked.'),
            ),
          );
          setState(() => _isSaving = false);
          return;
        }
      }
      // Enforce One Log Per Day
      final today = DateTime.now();
      final logsSnap = await FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('resourceLogs')
          .get();
      
      bool alreadySubmitted = false;
      for (var doc in logsSnap.docs) {
        final data = doc.data();
        if (data['date'] != null) {
          final logDate = (data['date'] as Timestamp).toDate();
          if (logDate.year == today.year && logDate.month == today.month && logDate.day == today.day) {
            alreadySubmitted = true;
            break;
          }
        }
      }

      if (alreadySubmitted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submission Blocked: A daily log has already been submitted for today.')),
          );
          setState(() => _isSaving = false);
          return;
        }
      }

      final log = ResourceLogModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        projectId: widget.projectId,
        loggedBy: user.uid,
        date: DateTime.now(),
        materialUsage: {
          'cement': double.tryParse(_cementController.text) ?? 0.0,
          'sand': double.tryParse(_sandController.text) ?? 0.0,
          'bricks': double.tryParse(_bricksController.text) ?? 0.0,
          'rebar': double.tryParse(_steelController.text) ?? 0.0,
        },
        equipmentList: [],
        laborHours: 0.0,
        notes: _notesController.text,
        weatherCondition: 'Sunny',
        createdAt: DateTime.now(),
      );

      await ref.read(loggingServiceProvider).addLog(log);
      
      // Invalidate providers to force real-time calculation and updates across the app
      ref.read(mlCacheProvider.notifier).invalidate(widget.projectId);
      ref.invalidate(projectLogsProvider(widget.projectId));
      ref.invalidate(deviationProvider(widget.projectId));
      ref.invalidate(resourceLogsProvider(widget.projectId));
      ref.invalidate(sequentialDeviationsProvider);
      ref.invalidate(allDeviationsProvider);
      ref.invalidate(deviationSummaryProvider);

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
    _steelController.clear();
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
            _buildField(_steelController, 'Steel (kg)', Icons.architecture),
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
                subtitle: Text('Cement: ${log.materialUsage['cement'] ?? 0} bags | Bricks: ${log.materialUsage['bricks'] ?? 0} pcs | Steel: ${log.materialUsage['rebar'] ?? log.materialUsage['steel'] ?? 0} kg'),
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
