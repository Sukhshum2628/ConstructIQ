import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  final _nameController = TextEditingController();
  final _accessKeyController = TextEditingController();
  UserRole _selectedRole = UserRole.engineer;
  bool _isLoading = false;

  void _submit() async {
    if (_nameController.text.isEmpty || _accessKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name and access key')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).completeUserProfile(
            name: _nameController.text.trim(),
            role: _selectedRole,
            accessKey: _accessKeyController.text.trim(),
          );
      // Riverpod will trigger a rebuild and Router will redirect to Dashboard
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Your Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Finalize Registration',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Please select your professional role and provide the authorization key.'),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Professional Role', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(value: UserRole.admin, label: Text('Admin'), icon: Icon(Icons.admin_panel_settings)),
                  ButtonSegment(value: UserRole.manager, label: Text('Manager'), icon: Icon(Icons.business_center)),
                  ButtonSegment(value: UserRole.engineer, label: Text('Engineer'), icon: Icon(Icons.engineering)),
                ],
                selected: {_selectedRole},
                onSelectionChanged: (set) => setState(() => _selectedRole = set.first),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _accessKeyController,
              decoration: InputDecoration(
                labelText: '${_selectedRole.toString().split('.').last.toUpperCase()} Access Key',
                hintText: 'Enter secret key',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.vpn_key, color: Colors.orange),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text('Access Dashboard', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
