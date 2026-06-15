import 'package:cloud_firestore/cloud_firestore.dart';

/// A schedule milestone for a project. `weight` is the milestone's relative
/// contribution to overall project completion; `progress` is its actual % done.
class MilestoneModel {
  final String id;
  final String projectId;
  final String name;
  final DateTime plannedStart;
  final DateTime plannedEnd;
  final double weight;
  final double progress; // 0..100
  final DateTime? completedAt;
  final int order;
  final DateTime createdAt;

  MilestoneModel({
    required this.id,
    required this.projectId,
    required this.name,
    required this.plannedStart,
    required this.plannedEnd,
    this.weight = 1.0,
    this.progress = 0.0,
    this.completedAt,
    this.order = 0,
    required this.createdAt,
  });

  bool get isComplete => progress >= 100;

  factory MilestoneModel.fromJson(Map<String, dynamic> json, [String? docId]) {
    return MilestoneModel(
      id: docId ?? json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      name: json['name'] as String? ?? 'Milestone',
      plannedStart:
          (json['plannedStart'] as Timestamp?)?.toDate() ?? DateTime.now(),
      plannedEnd: (json['plannedEnd'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 7)),
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      completedAt: (json['completedAt'] as Timestamp?)?.toDate(),
      order: json['order'] as int? ?? 0,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'name': name,
        'plannedStart': Timestamp.fromDate(plannedStart),
        'plannedEnd': Timestamp.fromDate(plannedEnd),
        'weight': weight,
        'progress': progress,
        'completedAt':
            completedAt != null ? Timestamp.fromDate(completedAt!) : null,
        'order': order,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  MilestoneModel copyWith({
    String? name,
    DateTime? plannedStart,
    DateTime? plannedEnd,
    double? weight,
    double? progress,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    int? order,
  }) =>
      MilestoneModel(
        id: id,
        projectId: projectId,
        name: name ?? this.name,
        plannedStart: plannedStart ?? this.plannedStart,
        plannedEnd: plannedEnd ?? this.plannedEnd,
        weight: weight ?? this.weight,
        progress: progress ?? this.progress,
        completedAt:
            clearCompletedAt ? null : (completedAt ?? this.completedAt),
        order: order ?? this.order,
        createdAt: createdAt,
      );
}

/// Pure schedule maths over a milestone set — planned vs actual % completion.
/// Kept here (not in the widget) so it's unit-testable and reusable.
class ScheduleMath {
  static double totalWeight(List<MilestoneModel> ms) =>
      ms.fold(0.0, (s, m) => s + (m.weight <= 0 ? 1.0 : m.weight));

  /// Current overall actual completion (weighted average of progress), 0..100.
  static double actualOverall(List<MilestoneModel> ms) {
    final tw = totalWeight(ms);
    if (tw == 0) return 0;
    final done = ms.fold(0.0, (s, m) => s + (m.weight <= 0 ? 1.0 : m.weight) * (m.progress / 100));
    return done / tw * 100;
  }

  /// Planned cumulative % at time [t]: each milestone ramps linearly across its
  /// planned window; the weighted sum is the planned S-curve.
  static double plannedAt(List<MilestoneModel> ms, DateTime t) {
    final tw = totalWeight(ms);
    if (tw == 0) return 0;
    double acc = 0;
    for (final m in ms) {
      final w = m.weight <= 0 ? 1.0 : m.weight;
      final span = m.plannedEnd.difference(m.plannedStart).inSeconds;
      double frac;
      if (span <= 0) {
        frac = t.isBefore(m.plannedStart) ? 0 : 1;
      } else {
        frac = t.difference(m.plannedStart).inSeconds / span;
        frac = frac.clamp(0.0, 1.0);
      }
      acc += w * frac;
    }
    return acc / tw * 100;
  }

  /// Actual cumulative % at [t] (only meaningful for t ≤ now): completed
  /// milestones count fully from their completion date; the partial progress of
  /// in-progress ones is reflected at "now".
  static double actualAt(List<MilestoneModel> ms, DateTime t, DateTime now) {
    final tw = totalWeight(ms);
    if (tw == 0) return 0;
    double acc = 0;
    for (final m in ms) {
      final w = m.weight <= 0 ? 1.0 : m.weight;
      if (m.completedAt != null && !t.isBefore(m.completedAt!)) {
        acc += w; // fully done by t
      } else if (!t.isBefore(now)) {
        acc += w * (m.progress / 100); // current partial, at "now"
      }
    }
    return acc / tw * 100;
  }
}
