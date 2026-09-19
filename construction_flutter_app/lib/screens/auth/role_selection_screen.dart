import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/auth_provider.dart';
import '../../utils/design_tokens.dart';

enum OnboardingMode { joinCompany, createCompany }

class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  OnboardingMode _mode = OnboardingMode.joinCompany;
  final _nameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser?.displayName != null && currentUser!.displayName!.isNotEmpty) {
      _nameController.text = currentUser.displayName!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Please enter your full name');
      return;
    }

    if (_mode == OnboardingMode.createCompany) {
      final companyName = _companyNameController.text.trim();
      if (companyName.isEmpty) {
        _showError('Please enter your organization or company name');
        return;
      }

      setState(() => _isLoading = true);
      try {
        await ref.read(authServiceProvider).completeUserProfileWithCompany(
          name: name,
          isCreatingCompany: true,
          companyName: companyName,
        );
      } catch (e) {
        _showError(e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      final code = _inviteCodeController.text.trim().toUpperCase();
      if (code.isEmpty) {
        _showError('Please enter the 12-character invite code');
        return;
      }

      setState(() => _isLoading = true);
      try {
        await ref.read(authServiceProvider).completeUserProfileWithCompany(
          name: name,
          isCreatingCompany: false,
          inviteCode: code,
        );
      } catch (e) {
        _showError(e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: DFColors.criticalBg,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: const Text('Company Onboarding', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: DFColors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () => ref.read(authServiceProvider).logout(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FINALIZE YOUR WORKSPACE',
                  style: DFTextStyles.labelSm.copyWith(
                    color: DFColors.primaryStitch,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Assign Your Enterprise Organization',
                  style: DFTextStyles.headline.copyWith(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'ConstructIQ requires all active accounts to belong to an isolated company workspace. Select an option below to continue.',
                  style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Selector Switcher
                Container(
                  decoration: BoxDecoration(
                    color: DFColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSegmentButton(
                          title: 'JOIN COMPANY',
                          icon: Icons.group_add_outlined,
                          isSelected: _mode == OnboardingMode.joinCompany,
                          onTap: () => setState(() => _mode = OnboardingMode.joinCompany),
                        ),
                      ),
                      Expanded(
                        child: _buildSegmentButton(
                          title: 'CREATE COMPANY',
                          icon: Icons.business_outlined,
                          isSelected: _mode == OnboardingMode.createCompany,
                          onTap: () => setState(() => _mode = OnboardingMode.createCompany),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: DFColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.15)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x08191C1E),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('YOUR FULL NAME'),
                      TextField(
                        controller: _nameController,
                        style: DFTextStyles.body.copyWith(fontSize: 14),
                        decoration: _inputDecoration(
                          hintText: 'Marcus Aurelius',
                          prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: DFColors.outline),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_mode == OnboardingMode.createCompany) ...[
                        _buildLabel('ORGANIZATION / COMPANY NAME'),
                        TextField(
                          controller: _companyNameController,
                          style: DFTextStyles.body.copyWith(fontSize: 14),
                          decoration: _inputDecoration(
                            hintText: 'Apex Construction & Infrastructure',
                            prefixIcon: const Icon(Icons.apartment_rounded, size: 20, color: DFColors.outline),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'You will be registered as Administrator of this company.',
                          style: DFTextStyles.caption.copyWith(fontSize: 11, fontStyle: FontStyle.italic, color: DFColors.textSecondary),
                        ),
                      ] else ...[
                        _buildLabel('INVITATION CODE'),
                        TextField(
                          controller: _inviteCodeController,
                          style: DFTextStyles.body.copyWith(fontSize: 14),
                          decoration: _inputDecoration(
                            hintText: 'e.g. XKQM-7B3N-P2WR',
                            prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20, color: DFColors.outline),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Enter the 12-character invite code given to you by your Administrator.',
                          style: DFTextStyles.caption.copyWith(fontSize: 11, fontStyle: FontStyle.italic, color: DFColors.textSecondary),
                        ),
                      ],

                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DFColors.primaryStitch,
                            foregroundColor: DFColors.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: DFColors.onPrimary, strokeWidth: 2))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _mode == OnboardingMode.createCompany ? 'CREATE WORKSPACE' : 'JOIN WORKSPACE',
                                      style: DFTextStyles.body.copyWith(color: DFColors.onPrimary, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward_rounded, size: 18, color: DFColors.onPrimary),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? DFColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? DFColors.primaryStitch : DFColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: DFTextStyles.labelSm.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? DFColors.primaryStitch : DFColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        text,
        style: DFTextStyles.labelSm.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: DFColors.primaryContainerStitch,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: DFTextStyles.body.copyWith(color: DFColors.outline, fontSize: 13),
      filled: true,
      fillColor: DFColors.surfaceContainerHighest,
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DFColors.primaryStitch, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
