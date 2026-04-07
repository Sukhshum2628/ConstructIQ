enum WorkerTrade { mason, laborer, helper, carpenter, electrician, plumber, fitter, steelFixer }

enum WorkerStatus { active, inactive }

class WorkerModel {
  final String id;
  final String name;
  final WorkerTrade trade;
  final String? contact;
  final WorkerStatus status;
  final String assignedProjectId;
  final double? dailyRate;

  WorkerModel({
    required this.id,
    required this.name,
    required this.trade,
    this.contact,
    required this.status,
    required this.assignedProjectId,
    this.dailyRate,
  });

  factory WorkerModel.fromJson(Map<String, dynamic> json) {
    return WorkerModel(
      id: json['id'] as String,
      name: json['name'] as String,
      trade: WorkerTrade.values.firstWhere((e) => e.name == (json['trade'] ?? 'laborer')),
      contact: json['contact'] as String?,
      status: WorkerStatus.values.firstWhere((e) => e.name == (json['status'] ?? 'active')),
      assignedProjectId: json['assignedProjectId'] as String,
      dailyRate: (json['dailyRate'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trade': trade.name,
      'contact': contact,
      'status': status.name,
      'assignedProjectId': assignedProjectId,
      'dailyRate': dailyRate,
    };
  }
}
