import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/design_tokens.dart';
import '../../services/ai_service.dart';
import '../../providers/project_provider.dart';
import '../../providers/deviation_provider.dart';
import '../../models/deviation_model.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  final String? projectId;
  const AiChatScreen({super.key, this.projectId});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _messageController = TextEditingController();
  final _aiService = AiService();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  String get _effectiveProjectId => widget.projectId ?? 'general';

  Future<void> _handleSend([String? presetText]) async {
    final text = presetText ?? _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({"role": "user", "text": text});
      _messageController.clear();
      _isLoading = true;
    });

    try {
      final response = await _aiService.getChatResponse(
        text,
        projectId: _effectiveProjectId,
      );

      setState(() {
        _messages.add({"role": "ai", "text": response});
      });
    } catch (e) {
      setState(() {
        _messages.add({"role": "ai", "text": "I'm having trouble connecting to the AI backend. Please ensure the service is running.\n\nError: $e"});
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch project data for context header
    final projectAsync = widget.projectId != null
        ? ref.watch(projectByIdProvider(widget.projectId!))
        : const AsyncValue<dynamic>.data(null);

    // Watch deviation data for quick metrics
    final deviationAsync = widget.projectId != null
        ? ref.watch(latestDeviationProvider(widget.projectId!))
        : const AsyncValue<DeviationResult?>.data(null);

    final projectName = (projectAsync.whenOrNull(data: (p) => p?.name) as String?) ?? 'General Query Mode';

    return Scaffold(
      backgroundColor: DFColors.background,
      appBar: _buildAppBar(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DFSpacing.lg, vertical: DFSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildContextHeader(projectName),
                    const SizedBox(height: DFSpacing.xl),
                    // High-End Bento Chat Container
                    Container(
                      constraints: const BoxConstraints(minHeight: 400),
                      decoration: BoxDecoration(
                        color: DFColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(25, 28, 30, 0.06),
                            blurRadius: 32,
                            offset: Offset(0, 12),
                          )
                        ],
                      ),
                      child: Column(
                        children: [
                          if (_messages.isEmpty) _buildEmptyState(),
                          if (_messages.isNotEmpty) _buildChatList(),
                          _buildInputBar(),
                        ],
                      ),
                    ),
                    const SizedBox(height: DFSpacing.xxl),
                    _buildQuickMetricsGrid(deviationAsync),
                    const SizedBox(height: DFSpacing.xxl),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: DFColors.background,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: DFColors.textPrimary),
        onPressed: () => context.pop(),
      ),
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: DFColors.primaryFixed,
              shape: BoxShape.circle,
              border: Border.all(color: DFColors.outlineVariant),
            ),
            child: const Icon(Icons.person, size: 20, color: DFColors.primary),
          ),
          const SizedBox(width: DFSpacing.sm),
          Text('AI Assistant', style: DFTextStyles.headline.copyWith(fontSize: 18, fontWeight: FontWeight.bold, color: DFColors.textPrimary)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: DFColors.primary),
          onPressed: () => context.push('/notifications'),
        ),
        const SizedBox(width: DFSpacing.sm),
      ],
    );
  }

  Widget _buildContextHeader(String projectName) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text('AI Intelligence Hub', style: DFTextStyles.headline.copyWith(fontSize: 22, fontWeight: FontWeight.bold))),
                  const SizedBox(width: 8),
                  const Icon(Icons.info_outline, color: DFColors.primary, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              RichText(
                text: TextSpan(
                  text: 'Answering for: ',
                  style: DFTextStyles.caption.copyWith(fontSize: 13, color: DFColors.textSecondary),
                  children: [
                    TextSpan(
                      text: projectName,
                      style: DFTextStyles.caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: DFColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: DFColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('Online', style: DFTextStyles.caption.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(DFSpacing.xl),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(color: DFColors.surfaceContainerLow, borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.smart_toy_outlined, size: 40, color: DFColors.primaryContainer),
          ),
          const SizedBox(height: DFSpacing.lg),
          Text('Your Project Intelligence Assistant', style: DFTextStyles.headline.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: DFSpacing.sm),
          Text(
            'Analyze site deviations, summarize logs, and predict overruns with natural language.',
            textAlign: TextAlign.center,
            style: DFTextStyles.body.copyWith(fontSize: 13, color: DFColors.textSecondary),
          ),
          const SizedBox(height: DFSpacing.xl),
          Row(
            children: [
              Expanded(child: _buildPromptPill('INVENTORY INSIGHT', 'What is causing our cement deviation?', DFColors.primary)),
              const SizedBox(width: DFSpacing.sm),
              Expanded(child: _buildPromptPill('WEEKLY RECAP', "Summarise this week's usage", DFColors.secondaryContainer)),
            ],
          ),
          const SizedBox(height: DFSpacing.sm),
          Row(
            children: [
              Expanded(child: _buildPromptPill('RISK ANALYSIS', 'What is our overrun risk?', DFColors.critical)),
              const SizedBox(width: DFSpacing.sm),
              Expanded(child: _buildPromptPill('FLEET MANAGEMENT', 'Which equipment has the highest idle time?', DFColors.primary)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPromptPill(String category, String prompt, Color catColor) {
    return InkWell(
      onTap: () => _handleSend(prompt),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(DFSpacing.md),
        decoration: BoxDecoration(
          color: DFColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category, style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold, color: catColor, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(prompt, style: DFTextStyles.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.symmetric(horizontal: DFSpacing.xl, vertical: DFSpacing.lg),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final m = _messages[index];
          final isUser = m['role'] == 'user';
          if (isUser) {
            return Align(
              alignment: Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.only(bottom: DFSpacing.md),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                decoration: const BoxDecoration(
                  color: DFColors.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Text(m['text']!, style: DFTextStyles.body.copyWith(color: Colors.white)),
              ),
            );
          } else {
            return _buildAiBubble(m['text']!);
          }
        },
      ),
    );
  }

  Widget _buildAiBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DFSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: DFColors.primaryContainer, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.smart_toy, color: Colors.white, size: 16),
          ),
          const SizedBox(width: DFSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('CONSTRUCTIQ AI', style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text('Just now', style: DFTextStyles.caption.copyWith(fontSize: 10, color: DFColors.outline)),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: DFColors.surfaceContainerLow,
                    border: Border.all(color: DFColors.outlineVariant),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Text(text, style: DFTextStyles.body.copyWith(height: 1.5)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(DFSpacing.lg),
      decoration: const BoxDecoration(
        color: DFColors.surfaceContainerLow,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: DFColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Color.fromRGBO(0,0,0,0.02), blurRadius: 4, offset: Offset(0,2))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          style: DFTextStyles.body,
                          decoration: InputDecoration(
                            hintText: 'Ask about your project...',
                            hintStyle: DFTextStyles.caption.copyWith(fontSize: 14, color: DFColors.outlineVariant),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _handleSend(),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.attach_file, color: DFColors.outline, size: 20), onPressed: () {}),
                      IconButton(icon: const Icon(Icons.mic_none, color: DFColors.outline, size: 20), onPressed: () {}),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: DFSpacing.md),
              InkWell(
                onTap: _isLoading ? null : () => _handleSend(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(color: DFColors.primary, shape: BoxShape.circle),
                  child: _isLoading
                      ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: DFSpacing.sm),
          Text('Intelligence Core: Connected to ConstructIQ AI Service', style: DFTextStyles.caption.copyWith(fontSize: 9, letterSpacing: 0.5, color: DFColors.outline))
        ],
      ),
    );
  }

  Widget _buildQuickMetricsGrid(AsyncValue<DeviationResult?> deviationAsync) {
    // Extract deviation data if available
    final devData = deviationAsync.whenOrNull(data: (d) => d as DeviationResult?);
    final mlProb = devData?.mlOverrunProbability;
    final severity = devData?.overallSeverity;
    final aiSummary = devData?.aiInsightSummary;

    // Get equipment idle ratio if available
    final perMaterial = devData?.perMaterial ?? {};
    final equipIdleRatio = perMaterial['equipment_idle_ratio']?.deviationPct;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(DFSpacing.lg),
                decoration: BoxDecoration(
                  color: DFColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DFColors.outlineVariant.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: Text('PROJECT HEALTH', style: DFTextStyles.caption.copyWith(fontSize: 11, fontWeight: FontWeight.bold, color: DFColors.primary, letterSpacing: 1.0))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: severity == 'critical' ? DFColors.critical.withValues(alpha: 0.1) : severity == 'warning' ? DFColors.warning.withValues(alpha: 0.1) : const Color(0xFF16A34A).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            severity?.toUpperCase() ?? 'N/A',
                            style: DFTextStyles.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold,
                              color: severity == 'critical' ? DFColors.critical : severity == 'warning' ? DFColors.warning : const Color(0xFF16A34A)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DFSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 100,
                            padding: const EdgeInsets.all(DFSpacing.md),
                            decoration: BoxDecoration(
                              color: DFColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mlProb != null ? '${(mlProb * 100).toStringAsFixed(0)}%' : '--',
                                  style: DFTextStyles.headline.copyWith(fontSize: 22, fontWeight: FontWeight.w900, color: DFColors.primary),
                                ),
                                Text('OVERRUN PROBABILITY', style: DFTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: DFSpacing.md),
                        Expanded(
                          child: Container(
                            height: 100,
                            padding: const EdgeInsets.all(DFSpacing.md),
                            decoration: BoxDecoration(
                              color: DFColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.engineering, color: DFColors.secondary),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      equipIdleRatio != null ? '${(equipIdleRatio * 100).toStringAsFixed(0)}%' : '--',
                                      style: DFTextStyles.body.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text('EQUIP IDLE RATIO', style: DFTextStyles.caption.copyWith(fontSize: 9, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DFSpacing.md),
        // Active Alert card
        if (severity == 'critical' || severity == 'warning')
          Container(
            padding: const EdgeInsets.all(DFSpacing.lg),
            decoration: BoxDecoration(
              color: severity == 'critical' ? DFColors.critical : DFColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color.fromRGBO(0,0,0,0.1), blurRadius: 10, offset: Offset(0,4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ACTIVE ALERT', style: DFTextStyles.caption.copyWith(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1.0)),
                const SizedBox(height: DFSpacing.md),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                      child: const Center(child: Text('!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontStyle: FontStyle.italic))),
                    ),
                    const SizedBox(width: DFSpacing.md),
                    Expanded(
                      child: Text(
                        aiSummary != null && aiSummary.length > 120 ? '${aiSummary.substring(0, 120)}...' : (aiSummary ?? 'No recent insights'),
                        style: DFTextStyles.body.copyWith(fontSize: 12, color: Colors.white, height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DFSpacing.md),
                LinearProgressIndicator(
                  value: mlProb ?? 0.0,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  color: DFColors.secondaryContainer,
                ),
                const SizedBox(height: DFSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      if (widget.projectId != null) {
                        context.push('/projects/${widget.projectId}');
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('View Project Details', style: DFTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
