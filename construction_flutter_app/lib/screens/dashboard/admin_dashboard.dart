import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/project_provider.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(userProjectsProvider);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Manager Command Center', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_active, color: Colors.red), onPressed: () {}),
          const CircleAvatar(backgroundColor: Colors.blue, child: Text('JD')),
          const SizedBox(width: 16),
        ],
      ),
      body: projectsAsync.when(
        data: (projects) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModernStatsHeader(),
              const SizedBox(height: 32),
              const Text('Global Resource Footprint', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildGlobalResourceChart(),
              const SizedBox(height: 32),
              const Text('Active Project Health', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...projects.map((p) => _buildProjectHealthCard(p)),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildModernStatsHeader() {
    return Row(
      children: [
        _buildStatCard('Projects', '12', Icons.business, Colors.blue),
        const SizedBox(width: 16),
        _buildStatCard('Efficiency', '92%', Icons.speed, Colors.green),
        const SizedBox(width: 16),
        _buildStatCard('Overruns', '2 Sites', Icons.warning, Colors.orange),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalResourceChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: BarChart(
        BarChartData(
          barGroups: [
            _makeGroup(0, 15, Colors.blue), // Cement
            _makeGroup(1, 40, Colors.orange), // Sand
            _makeGroup(2, 60, Colors.green), // Bricks
            _makeGroup(3, 25, Colors.red), // Steel
          ],
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
        ),
      ),
    );
  }

  BarChartGroupData _makeGroup(int x, double y, Color color) {
    return BarChartGroupData(x: x, barRods: [BarChartRodData(toY: y, color: color, width: 25, borderRadius: BorderRadius.circular(4))]);
  }

  Widget _buildProjectHealthCard(dynamic project) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.blueGrey, child: Icon(Icons.apartment, color: Colors.white)),
        title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Status: Active • Deviation: +4%'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
          child: const Text('HEALTHY', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }
}
