import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../utils/design_tokens.dart';

enum RegisterMode { createCompany, joinCompany }

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  RegisterMode _mode = RegisterMode.joinCompany;

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _companyNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showError('Please fill in all required personal credentials.');
      return;
    }

    if (password != confirmPassword) {
      _showError('Passwords do not match.');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters long.');
      return;
    }

    if (_mode == RegisterMode.createCompany) {
      final companyName = _companyNameController.text.trim();
      if (companyName.isEmpty) {
        _showError('Company name is required to create a new company workspace.');
        return;
      }

      setState(() => _isLoading = true);
      try {
        await ref.read(authServiceProvider).registerCompanyAndAdmin(
          companyName: companyName,
          adminName: name,
          email: email,
          password: password,
        );
        if (mounted) context.pop();
      } catch (e) {
        _showError(e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      final inviteCode = _inviteCodeController.text.trim().toUpperCase();
      if (inviteCode.isEmpty) {
        _showError('Please enter the 12-character company invite code.');
        return;
      }

      setState(() => _isLoading = true);
      try {
        await ref.read(authServiceProvider).joinCompanyWithCode(
          inviteCode: inviteCode,
          name: name,
          email: email,
          password: password,
        );
        if (mounted) context.pop();
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
      body: Stack(
        children: [
          // Background Blur Orbs
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: DFColors.primaryStitch.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: DFColors.primaryStitch.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Main Layout
          SafeArea(
            child: Row(
              children: [
                // Left Brand Column (Large Screen only)
                if (MediaQuery.of(context).size.width > 900)
                  Expanded(
                    flex: 5,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: DFColors.primaryContainerStitch,
                      ),
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: DFColors.onPrimary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.architecture_rounded, color: DFColors.primaryContainerStitch, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text('CONSTRUCTIQ', style: DFTextStyles.headline.copyWith(color: DFColors.onPrimary, letterSpacing: 2, fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            'ENTERPRISE MULTI-TENANCY',
                            style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryFixed, letterSpacing: 3, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Isolated workspaces for developers, contractors, and project teams.',
                            style: DFTextStyles.headline.copyWith(color: DFColors.onPrimary, fontSize: 32, fontWeight: FontWeight.w700, height: 1.2),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Strict row-level isolation guarantees company data, daily logs, QTO estimates, and site finances remain completely confidential.',
                            style: DFTextStyles.body.copyWith(color: DFColors.onPrimary.withValues(alpha: 0.8), fontSize: 15, height: 1.6),
                          ),
                          const Spacer(),
                          Text(
                            'HIGH-PRECISION CONSTRUCTION RESOURCE INTELLIGENCE',
                            style: DFTextStyles.labelSm.copyWith(color: DFColors.outlineVariant.withValues(alpha: 0.5), fontSize: 11, letterSpacing: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Right Registration Column
                Expanded(
                  flex: 6,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 540),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Text(
                              'START YOUR ONBOARDING',
                              style: DFTextStyles.labelSm.copyWith(
                                color: DFColors.primaryStitch,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create or Join a Company',
                              style: DFTextStyles.headline.copyWith(fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Choose whether you want to set up an enterprise workspace or join an existing organization with an invite code.',
                              style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, fontSize: 14),
                            ),
                            const SizedBox(height: 28),

                            // Segmented Switcher Card
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
                                      isSelected: _mode == RegisterMode.joinCompany,
                                      onTap: () => setState(() => _mode = RegisterMode.joinCompany),
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildSegmentButton(
                                      title: 'CREATE COMPANY',
                                      icon: Icons.business_outlined,
                                      isSelected: _mode == RegisterMode.createCompany,
                                      onTap: () => setState(() => _mode = RegisterMode.createCompany),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Form Card
                            Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: DFColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.15)),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0A191C1E),
                                    blurRadius: 24,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Dynamic Section: Create vs Join
                                  if (_mode == RegisterMode.createCompany) ...[
                                    _buildLabel('ORGANIZATION / COMPANY NAME'),
                                    _buildTextField(
                                      controller: _companyNameController,
                                      hintText: 'e.g. Apex Construction & Infra Ltd.',
                                      prefixIcon: const Icon(Icons.apartment_rounded, size: 20, color: DFColors.outline),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'You will become the workspace Administrator with invite code management rights.',
                                      style: DFTextStyles.caption.copyWith(fontSize: 11, fontStyle: FontStyle.italic, color: DFColors.textSecondary),
                                    ),
                                    const SizedBox(height: 20),
                                  ] else ...[
                                    _buildLabel('12-CHARACTER INVITE CODE'),
                                    _buildTextField(
                                      controller: _inviteCodeController,
                                      hintText: 'e.g. XKQM-7B3N-P2WR',
                                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20, color: DFColors.outline),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Enter the invitation code provided by your company Administrator.',
                                      style: DFTextStyles.caption.copyWith(fontSize: 11, fontStyle: FontStyle.italic, color: DFColors.textSecondary),
                                    ),
                                    const SizedBox(height: 20),
                                  ],

                                  // Personal Info
                                  _buildLabel('YOUR FULL NAME'),
                                  _buildTextField(
                                    controller: _nameController,
                                    hintText: 'Marcus Aurelius',
                                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: DFColors.outline),
                                  ),
                                  const SizedBox(height: 20),

                                  _buildLabel('WORK EMAIL ADDRESS'),
                                  _buildTextField(
                                    controller: _emailController,
                                    hintText: 'm.aurelius@constructiq.com',
                                    keyboardType: TextInputType.emailAddress,
                                    prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20, color: DFColors.outline),
                                  ),
                                  const SizedBox(height: 20),

                                  // Passwords
                                  _buildLabel('PASSWORD'),
                                  _buildTextField(
                                    controller: _passwordController,
                                    hintText: '••••••••',
                                    obscureText: _obscurePassword,
                                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: DFColors.outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: DFColors.outline, size: 18),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  _buildLabel('CONFIRM PASSWORD'),
                                  _buildTextField(
                                    controller: _confirmPasswordController,
                                    hintText: '••••••••',
                                    obscureText: _obscureConfirmPassword,
                                    prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20, color: DFColors.outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: DFColors.outline, size: 18),
                                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                    ),
                                  ),
                                  const SizedBox(height: 32),

                                  // Action Button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _register,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: DFColors.primaryStitch,
                                        foregroundColor: DFColors.onPrimary,
                                        elevation: 4,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: DFColors.onPrimary, strokeWidth: 2))
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  _mode == RegisterMode.createCompany ? 'CREATE COMPANY & ADMIN' : 'JOIN WORKSPACE',
                                                  style: DFTextStyles.body.copyWith(color: DFColors.onPrimary, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                                ),
                                                const SizedBox(width: 8),
                                                const Icon(Icons.arrow_forward_rounded, size: 18, color: DFColors.onPrimary),
                                              ],
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // Footer Sign In link
                                  Center(
                                    child: InkWell(
                                      onTap: () => context.pop(),
                                      child: RichText(
                                        text: TextSpan(
                                          text: 'Already have an account? ',
                                          style: DFTextStyles.body.copyWith(color: DFColors.textSecondary),
                                          children: [
                                            TextSpan(
                                              text: 'Sign In',
                                              style: DFTextStyles.body.copyWith(
                                                color: DFColors.primaryStitch,
                                                fontWeight: FontWeight.bold,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 36),

                            // Meta Information Cards
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetaCard(
                                    Icons.shield_outlined,
                                    'DATA ISOLATION',
                                    'Database rules enforce zero cross-company access.',
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildMetaCard(
                                    Icons.vpn_key_outlined,
                                    'ONE-TIME CODES',
                                    'Automated consumption prevents unauthorized usage.',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 36),

                            Text(
                              '© 2026 CONSTRUCTIQ ENTERPRISE. ADVANCED AI PLATFORM.',
                              style: DFTextStyles.labelSm.copyWith(
                                color: DFColors.outline,
                                fontSize: 10,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    Widget? prefixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: DFTextStyles.body.copyWith(fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: DFTextStyles.body.copyWith(color: DFColors.outline, fontSize: 13),
        filled: true,
        fillColor: DFColors.surfaceContainerHighest,
        suffixIcon: suffixIcon,
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
      ),
    );
  }

  Widget _buildMetaCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: DFColors.primaryStitch),
              const SizedBox(width: 6),
              Text(
                title,
                style: DFTextStyles.labelSm.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: DFColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: DFTextStyles.body.copyWith(
              fontSize: 11,
              color: DFColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
