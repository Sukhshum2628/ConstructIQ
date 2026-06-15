import 'package:flutter/material.dart';
import '../../services/ai_service.dart';

/// Step 4 — UI for the stateful Project Analyst agent. Unlike the RAG chat,
/// this calls the LangGraph agent which gathers schedule + cost + logs across
/// sources and returns one synthesised answer with recommendations.
class ProjectAnalystScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  const ProjectAnalystScreen({
    super.key,
    required this.projectId,
    this.projectName = 'Project',
  });

  @override
  State<ProjectAnalystScreen> createState() => _ProjectAnalystScreenState();
}

class _ProjectAnalystScreenState extends State<ProjectAnalystScreen> {
  final AiService _ai = AiService();
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = false;
  String? _answer;
  List<String> _tools = [];
  String? _error;

  static const _suggestions = [
    'Is the project on track?',
    'What is my cost overrun risk?',
    'Summarise recent site activity',
    'What are the biggest risks right now?',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _answer = null;
      _error = null;
      _tools = [];
    });
    try {
      final res = await _ai.analyzeProject(widget.projectId, question.trim());
      setState(() {
        _answer = (res['answer'] as String?)?.trim() ?? 'No answer returned.';
        _tools = ((res['tools_used'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _toolLabel(String t) {
    switch (t) {
      case 'get_milestone_status':
        return 'Schedule';
      case 'get_cost_deviation':
        return 'Cost';
      case 'get_recent_logs':
        return 'Logs';
      case 'get_weather_impact':
        return 'Weather';
      default:
        return t;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Project Analyst')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.projectName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Ask about schedule, cost, risks or activity — the analyst '
                  'checks multiple sources and answers with recommendations.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestions
                      .map((s) => ActionChip(
                            label: Text(s),
                            onPressed: _loading ? null : () => _ask(s),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Analysing across schedule, cost and logs…',
                          style: TextStyle(color: Colors.grey)),
                    ]),
                  ),
                if (_error != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!,
                          style: TextStyle(color: Colors.red.shade900)),
                    ),
                  ),
                if (_answer != null) ...[
                  if (_tools.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6,
                        children: [
                          const Text('Sources:',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          ..._tools.map((t) => Chip(
                                label: Text(_toolLabel(t),
                                    style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              )),
                        ],
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_answer!,
                          style: const TextStyle(fontSize: 15, height: 1.4)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                        hintText: 'Ask the analyst…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _loading ? null : () => _ask(_ctrl.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
