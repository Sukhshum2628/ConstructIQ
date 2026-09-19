import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/invite_code_model.dart';
import '../../models/user_model.dart';
import '../../services/company_service.dart';
import '../../utils/design_tokens.dart';

final companyServiceProvider = Provider<CompanyService>((ref) => CompanyService());

final inviteCodesStreamProvider = StreamProvider.autoDispose<List<InviteCodeModel>>((ref) {
  return ref.watch(companyServiceProvider).streamCompanyInviteCodes();
});

class InviteCodesScreen extends ConsumerStatefulWidget {
  const InviteCodesScreen({super.key});

  @override
  ConsumerState<InviteCodesScreen> createState() => _InviteCodesScreenState();
}

class _InviteCodesScreenState extends ConsumerState<InviteCodesScreen> {
  UserRole _selectedRole = UserRole.engineer;
  int _maxUses = 1;
  int _expiryDays = 7;
  bool _isGenerating = false;

  void _generateCode() async {
    setState(() => _isGenerating = true);
    try {
      final expiryDate = DateTime.now().add(Duration(days: _expiryDays));
      final newCode = await ref.read(companyServiceProvider).generateInviteCode(
        role: _selectedRole,
        maxUses: _maxUses,
        expiresAt: expiryDate,
      );

      if (mounted) {
        _showSuccessDialog(newCode, _selectedRole);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: DFColors.criticalBg,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showSuccessDialog(String code, UserRole role) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DFColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DFColors.successBg.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle_rounded, color: DFColors.successBg, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Invite Code Ready', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share this authorization code with the team member to join your company as ${role.name.toUpperCase()}:',
              style: DFTextStyles.body.copyWith(color: DFColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: DFColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DFColors.primaryStitch.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: DFColors.primaryStitch,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: DFColors.primaryStitch),
                    tooltip: 'Copy to Clipboard',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invite code copied to clipboard!'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '• Max Uses: $_maxUses\n• Valid for: $_expiryDays days',
              style: DFTextStyles.caption.copyWith(color: DFColors.textSecondary, height: 1.4),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: DFColors.primaryStitch,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  void _deactivate(String code) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Invite Code?'),
        content: Text('Are you sure you want to revoke invite code $code? Anyone attempting to use it will be blocked.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DFColors.criticalBg),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DEACTIVATE'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(companyServiceProvider).deactivateInviteCode(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Code $code deactivated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: DFColors.criticalBg),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final codesAsync = ref.watch(inviteCodesStreamProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: AppBar(
        title: const Text('Company Invite Codes', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: DFColors.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Generator Card
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
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: DFColors.primaryStitch.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add_moderator_rounded, color: DFColors.primaryStitch, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GENERATE INVITATION CODE', style: DFTextStyles.labelSm.copyWith(letterSpacing: 1.5, color: DFColors.primaryStitch, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          const Text('Authorize New Team Member', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Target Role
                  Text('TARGET ROLE', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.w700, color: DFColors.primaryContainerStitch)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      ChoiceChip(
                        label: const Text('SITE ENGINEER'),
                        selected: _selectedRole == UserRole.engineer,
                        onSelected: (val) => setState(() => _selectedRole = UserRole.engineer),
                      ),
                      ChoiceChip(
                        label: const Text('MANAGER'),
                        selected: _selectedRole == UserRole.manager,
                        onSelected: (val) => setState(() => _selectedRole = UserRole.manager),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Options Row
                  Row(
                    children: [
                      // Max Uses
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MAX USES', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.w700, color: DFColors.primaryContainerStitch)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: _maxUses,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: DFColors.surfaceContainerHighest,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('1 Use (Single)')),
                                DropdownMenuItem(value: 5, child: Text('5 Uses')),
                                DropdownMenuItem(value: 10, child: Text('10 Uses')),
                                DropdownMenuItem(value: 50, child: Text('50 Uses (Batch)')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _maxUses = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Validity
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('VALIDITY', style: DFTextStyles.labelSm.copyWith(fontWeight: FontWeight.w700, color: DFColors.primaryContainerStitch)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: _expiryDays,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: DFColors.surfaceContainerHighest,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              items: const [
                                DropdownMenuItem(value: 3, child: Text('3 Days')),
                                DropdownMenuItem(value: 7, child: Text('7 Days')),
                                DropdownMenuItem(value: 30, child: Text('30 Days')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _expiryDays = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DFColors.primaryStitch,
                        foregroundColor: DFColors.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isGenerating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: DFColors.onPrimary, strokeWidth: 2))
                          : const Icon(Icons.key_rounded, size: 18),
                      label: Text(_isGenerating ? 'GENERATING...' : 'CREATE AUTHORIZATION CODE', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Active Codes List Section
            Text('ACTIVE COMPANY INVITATIONS', style: DFTextStyles.labelSm.copyWith(color: DFColors.primaryStitch, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            codesAsync.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: DFColors.criticalBg.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('Failed to load invite codes: $err', style: const TextStyle(color: DFColors.criticalBg)),
              ),
              data: (codes) {
                if (codes.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: DFColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.vpn_key_outlined, size: 40, color: DFColors.outline.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text('No invite codes generated yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        const Text('Generate codes above to invite site engineers and project managers to your workspace.', textAlign: TextAlign.center, style: TextStyle(color: DFColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: codes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = codes[index];
                    final isValid = item.isValid;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: DFColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isValid ? DFColors.primaryStitch.withValues(alpha: 0.1) : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isValid ? Icons.vpn_key_rounded : Icons.vpn_key_off_rounded,
                              color: isValid ? DFColors.primaryStitch : Colors.grey,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      item.code,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                        color: isValid ? DFColors.textPrimary : Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: DFColors.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item.role.name.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Uses: ${item.usesSoFar}/${item.maxUses} • ${isValid ? "Active" : (item.isExpired ? "Expired" : "Used / Inactive")}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isValid ? DFColors.textSecondary : DFColors.criticalBg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            tooltip: 'Copy Code',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: item.code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copied to clipboard!'), duration: Duration(seconds: 1)),
                              );
                            },
                          ),
                          if (isValid)
                            IconButton(
                              icon: const Icon(Icons.block_rounded, size: 20, color: DFColors.criticalBg),
                              tooltip: 'Deactivate',
                              onPressed: () => _deactivate(item.code),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
