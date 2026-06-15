import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/project_model.dart';

/// Global project search (by name or location). Operates on a snapshot of the
/// project list passed in when search is opened.
class ProjectSearchDelegate extends SearchDelegate<void> {
  final List<ProjectModel> projects;
  ProjectSearchDelegate(this.projects) : super(searchFieldLabel: 'Search projects');

  List<ProjectModel> _filter() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return projects;
    return projects
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.location.toLowerCase().contains(q))
        .toList();
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final items = _filter();
    if (items.isEmpty) {
      return const Center(child: Text('No matching projects'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final p = items[i];
        return ListTile(
          leading: const Icon(Icons.business_outlined),
          title: Text(p.name),
          subtitle: Text(p.location.isEmpty ? '—' : p.location),
          onTap: () {
            close(context, null);
            context.push('/projects/${p.projectId}');
          },
        );
      },
    );
  }
}
