import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_provider.dart';
import '../../models/chat_message.dart';
import '../../utils/design_tokens.dart';
import '../../widgets/df_card.dart';
import '../../widgets/df_button.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  final String? projectId;
  const AiChatScreen({super.key, this.projectId});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    ref.read(chatProvider.notifier).sendMessage(_controller.text.trim());
    _controller.clear();
    // Auto scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);

    return Scaffold(
      backgroundColor: DFColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                top: 120, // Adjusted for glass app bar
                left: DFSpacing.lg,
                right: DFSpacing.lg,
                bottom: 8,
              ),
              itemCount: messages.length,
              itemBuilder: (context, index) => _MessageItem(message: messages[index]),
            ),
          ),
          _buildSuggestedChips(),
          _buildCommandBar(),
        ],
      ),
    );
  }

  Widget _buildSuggestedChips() {
    final suggestions = widget.projectId != null 
      ? [
          'Analyze this project',
          'Current budget risk',
          'Timeline prediction',
          'Material summary',
        ]
      : [
          'Show cement deviations',
          'Material forecast',
          'Cost overrun probability',
          'Current risk level',
        ];

    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: DFSpacing.lg),
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ActionChip(
          label: Text(suggestions[index], style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
          backgroundColor: DFColors.surface,
          padding: const EdgeInsets.all(0),
          side: const BorderSide(color: DFColors.divider, width: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onPressed: () {
            _controller.text = suggestions[index];
            _send();
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final statusText = widget.projectId != null 
      ? 'PROJECT CONTEXT: ${widget.projectId!.substring(0, 8).toUpperCase()}'
      : 'SYSTEM STATUS: OPTIMAL';
    final statusColor = widget.projectId != null ? DFColors.primary : DFColors.normal;

    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 40),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AppBar(
            backgroundColor: DFColors.background.withValues(alpha: 0.8),
            elevation: 0,
            centerTitle: false,
            leading: const BackButton(color: DFColors.textPrimary),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI ASSISTANT', 
                  style: DFTextStyles.caption.copyWith(
                    color: DFColors.primary, 
                    fontWeight: FontWeight.bold, 
                    letterSpacing: 2.0
                  )
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(statusText, 
                      style: DFTextStyles.caption.copyWith(fontSize: 9, color: DFColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommandBar() {
    return Container(
      padding: const EdgeInsets.all(DFSpacing.md),
      decoration: BoxDecoration(
        color: DFColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: DFColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DFColors.divider, width: 0.5),
                ),
                child: TextField(
                  controller: _controller,
                  style: DFTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'INPUT COMMAND OR QUERY...',
                    prefixIcon: const Icon(Icons.flash_on_rounded, color: DFColors.primary, size: 18),
                    hintStyle: DFTextStyles.caption.copyWith(color: DFColors.textCaption),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DFButton(
              label: '',
              icon: Icons.send_rounded,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  final ChatMessage message;
  const _MessageItem({required this.message});

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: DFCard(
          padding: const EdgeInsets.all(12),
          color: isUser ? DFColors.primary.withValues(alpha: 0.1) : DFColors.surface,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUser ? 'YOU' : 'FOREMAN AI',
                  style: DFTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold, 
                    color: isUser ? DFColors.primary : DFColors.textSecondary,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.text,
                  style: DFTextStyles.body.copyWith(
                    color: DFColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
