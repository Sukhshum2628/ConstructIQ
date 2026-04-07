import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../models/user_model.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: DFColors.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              // Get user role from data for fallback redirection
              final profile = ref.read(userProfileProvider).value;
              if (profile?.role == UserRole.manager || profile?.role == UserRole.admin) {
                context.go('/dashboard');
              } else {
                context.go('/engineer-home');
              }
            }
          },
        ),
        title: Text('Account Settings', style: DFTextStyles.cardTitle),
      ),
      body: SafeArea(
        child: userAsync.when(
          data: (profile) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          color: DFColors.primaryStitch.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: DFColors.primaryStitch.withValues(alpha: 0.2), width: 4),
                        ),
                        child: const Icon(Icons.person_rounded, size: 50, color: DFColors.primaryStitch),
                      ),
                      const SizedBox(height: 16),
                      Text(profile?.name ?? 'ConstructIQ Member', 
                        style: DFTextStyles.screenTitle.copyWith(fontSize: 22, fontWeight: FontWeight.w900)),
                      Text(profile?.designation ?? 'Site Staff', 
                        style: DFTextStyles.caption.copyWith(color: DFColors.primaryStitch, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _showEditProfileSheet(context, ref, profile),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text('Edit Profile', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DFColors.primaryStitch,
                          side: BorderSide(color: DFColors.primaryStitch.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                
                _sectionHeader('PERSONAL INFORMATION'),
                _buildInfoTile('Full Name', profile?.name ?? '-'),
                const SizedBox(height: 12),
                _buildInfoTile('Email', profile?.email ?? '-'),
                const SizedBox(height: 12),
                _buildInfoTile('Phone', profile?.phone ?? 'Not set'),
                const SizedBox(height: 12),
                _buildInfoTile('Designation', profile?.designation ?? 'Not set'),
                
                const SizedBox(height: 32),
                _sectionHeader('SECURITY & SESSION'),
                _buildSettingTile(
                  icon: Icons.logout_rounded,
                  title: 'Sign Out Account',
                  onTap: () => _showSignOutDialog(context, ref),
                ),
                
                const SizedBox(height: 48),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator(color: DFColors.primaryStitch)),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: DFTextStyles.labelSm.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: DFColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return DFCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: DFTextStyles.labelSm.copyWith(color: DFColors.textSecondary, fontWeight: FontWeight.w500)),
          Text(value, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: DFColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildSettingTile({required IconData icon, required String title, VoidCallback? onTap}) {
    return DFCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: DFColors.critical, size: 22),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w600, color: DFColors.critical))),
          const Icon(Icons.chevron_right, color: DFColors.textCaption, size: 20),
        ],
      ),
    );
  }

  void _showEditProfileSheet(BuildContext context, WidgetRef ref, UserModel? profile) {
    final nameController = TextEditingController(text: profile?.name);
    final phoneController = TextEditingController(text: profile?.phone);
    final designationController = TextEditingController(text: profile?.designation);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: DFColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24, left: 24, right: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Edit Profile', style: DFTextStyles.screenTitle.copyWith(fontSize: 20)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 24),
            _buildEditField('Full Name', nameController),
            const SizedBox(height: 16),
            _buildEditField('Phone Number', phoneController, keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            _buildEditField('Designation', designationController),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await ref.read(authServiceProvider).updateProfile(
                      name: nameController.text.trim(),
                      phone: phoneController.text.trim(),
                      designation: designationController.text.trim(),
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: DFColors.critical));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: DFColors.primaryStitch,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('SAVE CHANGES', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, fontSize: 10, color: DFColors.textSecondary, letterSpacing: 1.0)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: DFTextStyles.body,
          decoration: InputDecoration(
            filled: true,
            fillColor: DFColors.surfaceContainerLow,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  void _showSignOutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DFColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Sign Out', style: DFTextStyles.cardTitle),
        content: Text('Are you sure you want to terminate the current session? Unsaved changes may be lost.', style: DFTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              ref.read(authServiceProvider).signOut();
              Navigator.pop(context);
              context.go('/login');
            },
            child: Text('SIGN OUT', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.bold, color: DFColors.critical)),
          ),
        ],
      ),
    );
  }
}
