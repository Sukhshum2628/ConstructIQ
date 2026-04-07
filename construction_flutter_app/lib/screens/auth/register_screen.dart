import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/design_tokens.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _accessKeyController = TextEditingController();
  
  UserRole _selectedRole = UserRole.engineer;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  void _register() async {
    if (_emailController.text.isEmpty || 
        _passwordController.text.isEmpty || 
        _nameController.text.isEmpty || 
        _accessKeyController.text.isEmpty) {
      _showError('All fields including Access Key are required.');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).register(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        role: _selectedRole,
        accessKey: _accessKeyController.text.trim(),
      );
      if (mounted) context.pop(); 
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message), 
          backgroundColor: DFColors.criticalBg,
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background, // F4F6F9 originally in Register html
      body: Stack(
        children: [
          // Background Aesthetic Blur Elements
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
                color: DFColors.primaryContainerStitch.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Top Navigation Anchor
                Container(
                  height: 64, // h-16
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: DFColors.surface.withValues(alpha: 0.8), // simulated backdrop-blur
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ConstructIQ', 
                        style: DFTextStyles.screenTitle.copyWith(
                          color: DFColors.primaryStitch, 
                          fontWeight: FontWeight.bold, 
                          letterSpacing: -0.5,
                          fontSize: 20,
                        )
                      ),
                      Text('v2.4.0', 
                        style: DFTextStyles.labelSm.copyWith(
                          fontSize: 12, 
                          fontWeight: FontWeight.w500, 
                          letterSpacing: 1.5,
                        )
                      ),
                    ],
                  ),
                ),

                // Expanded Body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 576), // max-w-xl
                        child: Column(
                          children: [
                            // Header Section
                            Text('Create Account', 
                              style: DFTextStyles.screenTitle.copyWith(
                                fontSize: 30, 
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: DFColors.textPrimary,
                              )
                            ),
                            const SizedBox(height: 8),
                            Text('Join the industrial ecosystem where engineering precision meets editorial data clarity.', 
                              textAlign: TextAlign.center,
                              style: DFTextStyles.body.copyWith(
                                color: DFColors.textSecondary,
                                fontSize: 15,
                              )
                            ),
                            const SizedBox(height: 40),

                            // Registration Card
                            Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: DFColors.surface, // surface-container-lowest
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.10)),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0F191C1E),
                                    blurRadius: 32,
                                    offset: Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Personal Info Grid
                                  _buildLabel('FULL NAME'),
                                  _buildTextField(
                                    controller: _nameController,
                                    hintText: 'e.g. Marcus Aurelius',
                                  ),
                                  const SizedBox(height: 20),

                                  _buildLabel('EMAIL ADDRESS'),
                                  _buildTextField(
                                    controller: _emailController,
                                    hintText: 'm.aurelius@constructiq.com',
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                  const SizedBox(height: 20),

                                  Wrap(
                                    spacing: 20,
                                    runSpacing: 20,
                                    children: [
                                      SizedBox(
                                        width: (MediaQuery.of(context).size.width - 68) / 2 > 200 ? null : double.infinity,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildLabel('PASSWORD'),
                                            _buildTextField(
                                              controller: _passwordController,
                                              hintText: '••••••••',
                                              obscureText: _obscurePassword,
                                              suffixIcon: IconButton(
                                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: DFColors.outline, size: 18),
                                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: (MediaQuery.of(context).size.width - 68) / 2 > 200 ? null : double.infinity,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildLabel('CONFIRM PASSWORD'),
                                            _buildTextField(
                                              controller: _confirmPasswordController,
                                              hintText: '••••••••',
                                              obscureText: _obscureConfirmPassword,
                                              suffixIcon: IconButton(
                                                icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: DFColors.outline, size: 18),
                                                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),

                                  // Role Selector
                                  _buildLabel('SELECT YOUR ROLE'),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _buildRolePill(UserRole.engineer, 'ENGINEER'),
                                      _buildRolePill(UserRole.manager, 'MANAGER'),
                                      _buildRolePill(UserRole.admin, 'ADMIN'),
                                    ],
                                  ),
                                  const SizedBox(height: 24),

                                  // Access Key
                                  _buildLabel('ROLE ACCESS KEY'),
                                  _buildTextField(
                                    controller: _accessKeyController,
                                    hintText: 'Enter your team access key',
                                    prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20, color: DFColors.outline),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Access keys are provided by your site supervisor or system administrator.', 
                                    style: DFTextStyles.caption.copyWith(fontSize: 10, fontStyle: FontStyle.italic, color: DFColors.textSecondary)
                                  ),
                                  
                                  const SizedBox(height: 32),

                                  // Action Button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56, // py-4 approximately
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _register,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: DFColors.primaryStitch,
                                        foregroundColor: DFColors.onPrimary,
                                        elevation: 8,
                                        shadowColor: DFColors.primaryStitch.withValues(alpha: 0.15),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: DFColors.onPrimary, strokeWidth: 2))
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text('CREATE ACCOUNT', style: DFTextStyles.body.copyWith(color: DFColors.onPrimary, fontWeight: FontWeight.bold)),
                                                const SizedBox(width: 8),
                                                const Icon(Icons.arrow_forward, size: 20, color: DFColors.onPrimary),
                                              ],
                                            ),
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  // Footer Sign In link
                                  Center(
                                    child: InkWell(
                                      onTap: () => context.pop(),
                                      child: RichText(
                                        text: TextSpan(
                                          text: 'Already registered? ',
                                          style: DFTextStyles.body.copyWith(color: DFColors.textSecondary),
                                          children: [
                                            TextSpan(
                                              text: 'Sign In',
                                              style: DFTextStyles.body.copyWith(color: DFColors.primaryStitch, decoration: TextDecoration.underline, decorationThickness: 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 48),

                            // Meta Info
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetaCard(
                                    Icons.verified_user_rounded, 
                                    'SECURITY', 
                                    'End-to-end encrypted industrial data protocols.'
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildMetaCard(
                                    Icons.cloud_sync_rounded, 
                                    'SYNC', 
                                    'Real-time collaboration across site locations.'
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 48),

                            // Bottom Footer
                            Text('© 2024 CONSTRUCTIQ SYSTEMS CORP. PRECISION ENGINEERING.',
                              style: DFTextStyles.labelSm.copyWith(
                                color: DFColors.outline,
                                fontSize: 11,
                                letterSpacing: 2.0,
                                fontWeight: FontWeight.w500,
                              )
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

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, 
        style: DFTextStyles.labelSm.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DFColors.primaryContainerStitch,
          letterSpacing: 0.5,
        )
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
        hintStyle: DFTextStyles.body.copyWith(color: DFColors.outline, fontSize: 14),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildRolePill(UserRole role, String label) {
    bool isSelected = _selectedRole == role;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedRole = role),
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? DFColors.primaryContainerStitch : DFColors.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isSelected ? DFColors.primaryContainerStitch : DFColors.primaryStitch, 
              width: 1
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ] : null,
          ),
          alignment: Alignment.center,
          child: Text(label, 
            style: DFTextStyles.labelSm.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: isSelected ? DFColors.onPrimary : DFColors.primaryStitch,
            )
          ),
        ),
      ),
    );
  }

  Widget _buildMetaCard(IconData icon, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DFColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: DFColors.primaryStitch),
              const SizedBox(width: 8),
              Text(title, 
                style: DFTextStyles.labelSm.copyWith(
                  fontSize: 10, 
                  fontWeight: FontWeight.bold, 
                  color: DFColors.textSecondary,
                  letterSpacing: 1.5,
                )
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, 
            style: DFTextStyles.body.copyWith(
              fontSize: 12, 
              color: DFColors.textSecondary,
              height: 1.5,
            )
          ),
        ],
      ),
    );
  }
}
