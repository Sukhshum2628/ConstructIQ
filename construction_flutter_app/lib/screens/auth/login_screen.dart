import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../utils/design_tokens.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()), 
            backgroundColor: DFColors.criticalBg,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()), 
            backgroundColor: DFColors.criticalBg,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DFColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0), // Reduced vertical pad
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448), // max-w-md
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 56, height: 56, // Fixed dimensions for perfect circle
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: DFColors.primaryStitch.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.architecture_rounded, color: DFColors.primaryContainerStitch, size: 32),
                      ),
                      const SizedBox(height: 16),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ConstructIQ', 
                            style: DFTextStyles.screenTitle.copyWith(
                              color: DFColors.primaryContainerStitch, 
                              fontSize: 28, 
                              letterSpacing: -1.0,
                              fontWeight: FontWeight.w900,
                            )
                          ),
                          const SizedBox(height: 2), // 1-2 pixel gap
                          Container(
                            width: 140, // Match text width
                            height: 1.5,
                            color: DFColors.primaryContainerStitch.withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16), // Gap before subheader
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: DFColors.primaryStitch.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: DFColors.primaryStitch.withValues(alpha: 0.15)),
                    ),
                    child: Text('Sign in to your account', 
                      style: DFTextStyles.body.copyWith(
                        color: DFColors.primaryStitch, 
                        fontSize: 12, 
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      )
                    ),
                  ),
                  const SizedBox(height: 12), // Sitting right on top of the box

                  // Form Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: DFColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.15)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F191C1E), // rgba(25,28,30,0.06)
                          blurRadius: 32,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email Field
                        Text('EMAIL ADDRESS', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 56, // h-14
                          child: TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: DFTextStyles.body,
                            decoration: InputDecoration(
                              hintText: 'name@company.com',
                              hintStyle: DFTextStyles.body.copyWith(color: DFColors.outline),
                              suffixIcon: const Icon(Icons.mail_outline, color: DFColors.outline, size: 20),
                              filled: true,
                              fillColor: DFColors.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: DFColors.primaryStitch, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Password Field
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('PASSWORD', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                            InkWell(
                              onTap: () {
                                _showForgotPasswordDialog();
                              },
                              child: Text('Forgot Password?', style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryStitch, fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 56, // h-14
                          child: TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: DFTextStyles.body,
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              hintStyle: DFTextStyles.body.copyWith(color: DFColors.outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: DFColors.outline, size: 20),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: DFColors.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: DFColors.primaryStitch, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Sign In Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: DFColors.primaryStitch,
                              foregroundColor: DFColors.onPrimary,
                              elevation: 2, // shadow-md
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _isLoading 
                                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: DFColors.onPrimary, strokeWidth: 2))
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Sign In', style: DFTextStyles.body.copyWith(color: DFColors.onPrimary, fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.login_rounded, size: 20, color: DFColors.onPrimary),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 20), // Balanced space above

                        // Divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: DFColors.outlineVariant.withValues(alpha: 0.3))),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text('OR', style: DFTextStyles.labelSm.copyWith(color: DFColors.outline, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                            ),
                            Expanded(child: Divider(color: DFColors.outlineVariant.withValues(alpha: 0.3))),
                          ],
                        ),

                        const SizedBox(height: 20), // Balanced space below

                        // Google Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: _signInWithGoogle,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: DFColors.surface,
                              side: const BorderSide(color: DFColors.outlineVariant),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                                  child: const Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text('Continue with Google', 
                                    style: DFTextStyles.body.copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24), // Reduced from 20
                  
                  // Register Capsule Link
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: DFColors.surface,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Don't have an account?", style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, fontSize: 12)),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => context.push('/register'),
                          child: Text("Register", style: DFTextStyles.body.copyWith(color: DFColors.primaryStitch, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32), // Reduced from 48

                  // Footer Security Badges
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12, // Reduced from 16
                    runSpacing: 8,
                    children: [
                      _buildSecurityBadge(Icons.lock_outline, 'SECURE 256-BIT SSL ENCRYPTION'),
                      Container(width: 3, height: 3, decoration: BoxDecoration(color: DFColors.outlineVariant.withValues(alpha: 0.3), shape: BoxShape.circle)),
                      _buildSecurityBadge(Icons.verified_user_outlined, 'ISO 27001 PRO'),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityBadge(IconData icon, String label) {
    return Opacity(
      opacity: 0.6,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: DFColors.outline),
          const SizedBox(width: 8),
          Text(label, style: DFTextStyles.labelSm.copyWith(color: DFColors.outline, fontSize: 10, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DFColors.surface,
        title: Text('Password Recovery', style: DFTextStyles.cardTitle),
        content: Text("A password recovery link would be sent to your email address in a production environment. For this demo, please use your existing credentials or sign in with Google.", style: DFTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Understood', style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: DFColors.primaryStitch)),
          ),
        ],
      ),
    );
  }
}
