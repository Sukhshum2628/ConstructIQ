import 'package:firebase_auth/firebase_auth.dart';
import '../models/project_model.dart';
import '../models/workforce_model.dart';
import '../models/vendor_bill_model.dart';
import '../models/deviation_model.dart';
import '../models/resource_log_model.dart';

// All demo data used when running in demo mode.
// No Firestore reads occur in demo mode — this is the entire local dataset.

const kDemoUserName = 'Demo User';
const kDemoUserEmail = 'demo@constructiq.app';
const kDemoCompanyName = 'Apex Constructions (Demo)';
const kDemoCompanyId = 'DEMO-COMPANY';
const kDemoRole = 'admin'; // demo user sees all features

String get _currentDemoUid => FirebaseAuth.instance.currentUser?.uid ?? 'demo_user';

List<ProjectModel> get kDemoProjectModels {
  final uid = _currentDemoUid;
  return [
    ProjectModel(
      projectId: 'demo_project_1',
      name: 'Apex Commercial Tower',
      location: 'Mumbai, Maharashtra',
      startDate: DateTime(2026, 1, 15),
      expectedEndDate: DateTime(2026, 12, 30),
      status: ProjectStatus.active,
      createdBy: uid,
      teamMembers: [uid],
      plannedBudget: 45000000.0,
      projectType: 'Commercial',
      cadFileUrl: '',
      estimationStatus: EstimationStatus.completed,
      companyId: kDemoCompanyId,
      createdAt: DateTime(2026, 1, 15),
      durationDays: 350,
      totalWallLength: 1450.0,
      totalFloorArea: 28000.0,
      floorCount: 14,
    ),
    ProjectModel(
      projectId: 'demo_project_2',
      name: 'Green Valley Residential',
      location: 'Pune, Maharashtra',
      startDate: DateTime(2026, 3, 1),
      expectedEndDate: DateTime(2026, 11, 20),
      status: ProjectStatus.planning,
      createdBy: uid,
      teamMembers: [uid],
      plannedBudget: 12000000.0,
      projectType: 'Residential',
      cadFileUrl: '',
      estimationStatus: EstimationStatus.completed,
      companyId: kDemoCompanyId,
      createdAt: DateTime(2026, 3, 1),
      durationDays: 260,
      totalWallLength: 620.0,
      totalFloorArea: 9500.0,
      floorCount: 4,
    ),
    ProjectModel(
      projectId: 'demo_project_3',
      name: 'NH-48 Bridge Expansion',
      location: 'Delhi NCR',
      startDate: DateTime(2025, 6, 10),
      expectedEndDate: DateTime(2026, 2, 28),
      status: ProjectStatus.completed,
      createdBy: uid,
      teamMembers: [uid],
      plannedBudget: 8500000.0,
      projectType: 'Infrastructure',
      cadFileUrl: '',
      estimationStatus: EstimationStatus.completed,
      companyId: kDemoCompanyId,
      createdAt: DateTime(2025, 6, 10),
      durationDays: 260,
      totalWallLength: 310.0,
      totalFloorArea: 4200.0,
      floorCount: 1,
    ),
  ];
}

final List<WorkerModel> kDemoWorkforce = [
  WorkerModel(
    id: 'worker_1',
    name: 'Rajesh Kumar',
    trade: WorkerTrade.fitter,
    assignedProjectId: 'demo_project_1',
    status: WorkerStatus.active,
    dailyRate: 1200.0,
  ),
  WorkerModel(
    id: 'worker_2',
    name: 'Priya Sharma',
    trade: WorkerTrade.laborer,
    assignedProjectId: 'demo_project_1',
    status: WorkerStatus.active,
    dailyRate: 1800.0,
  ),
  WorkerModel(
    id: 'worker_3',
    name: 'Mohammed Iqbal',
    trade: WorkerTrade.helper,
    assignedProjectId: 'demo_project_1',
    status: WorkerStatus.active,
    dailyRate: 1100.0,
  ),
  WorkerModel(
    id: 'worker_4',
    name: 'Suresh Verma',
    trade: WorkerTrade.mason,
    assignedProjectId: 'demo_project_1',
    status: WorkerStatus.active,
    dailyRate: 850.0,
  ),
];

final List<Map<String, dynamic>> kDemoInventory = [
  {'item': 'Cement (OPC 53)', 'quantity': 450, 'unit': 'bags', 'status': 'Sufficient'},
  {'item': 'TMT Steel Bars', 'quantity': 12, 'unit': 'tonnes', 'status': 'Low Stock'},
  {'item': 'River Sand', 'quantity': 85, 'unit': 'cubic ft', 'status': 'Sufficient'},
];

List<VendorBillModel> get kDemoBills {
  final uid = _currentDemoUid;
  return [
    VendorBillModel(
      id: 'demo_bill_1',
      projectId: 'demo_project_1',
      vendorName: 'UltraTech Cement Depot',
      amount: 145000.0,
      date: DateTime(2026, 2, 10),
      category: 'Materials',
      fileUrl: '',
      uploadedBy: uid,
      createdAt: DateTime(2026, 2, 10),
      items: [
        BillItem(description: 'OPC 53 Grade Cement', quantity: 350, unit: 'bags', rate: 400.0, amount: 140000.0),
        BillItem(description: 'Delivery & Handling', quantity: 1, unit: 'trip', rate: 5000.0, amount: 5000.0),
      ],
    ),
    VendorBillModel(
      id: 'demo_bill_2',
      projectId: 'demo_project_1',
      vendorName: 'Tata Steel Rebar Solutions',
      amount: 320000.0,
      date: DateTime(2026, 2, 22),
      category: 'Materials',
      fileUrl: '',
      uploadedBy: uid,
      createdAt: DateTime(2026, 2, 22),
      items: [
        BillItem(description: '16mm TMT Steel Rods', quantity: 5, unit: 'tonnes', rate: 64000.0, amount: 320000.0),
      ],
    ),
  ];
}

List<ResourceLogModel> get kDemoResourceLogs {
  final uid = _currentDemoUid;
  return [
    ResourceLogModel(
      id: 'demo_log_1',
      projectId: 'demo_project_1',
      loggedBy: uid,
      date: DateTime(2026, 2, 20),
      laborHours: 192.0,
      notes: 'Ground floor slab casting completed on schedule.',
      weatherCondition: 'Clear',
      equipmentList: [
        EquipmentEntry(name: 'Transit Mixer', usedHours: 6.0, idleHours: 1.0),
        EquipmentEntry(name: 'Concrete Pump', usedHours: 5.5, idleHours: 0.5),
      ],
      materialUsage: {'cement': 120.0, 'sand': 22.0, 'steel': 1.8},
      createdAt: DateTime(2026, 2, 20),
    ),
    ResourceLogModel(
      id: 'demo_log_2',
      projectId: 'demo_project_1',
      loggedBy: uid,
      date: DateTime(2026, 2, 19),
      laborHours: 224.0,
      notes: 'Rebar binding and framework inspection.',
      weatherCondition: 'Clear',
      equipmentList: [
        EquipmentEntry(name: 'Bar Bending Machine', usedHours: 7.0, idleHours: 1.0),
      ],
      materialUsage: {'steel': 2.4},
      createdAt: DateTime(2026, 2, 19),
    ),
  ];
}

DeviationResult createDemoDeviationResult(String projectId) {
  return DeviationResult(
    projectId: projectId,
    deviationId: 'demo_dev_$projectId',
    perMaterial: {
      'cement': MaterialDeviation(estimated: 2500, actual: 2620, unit: 'bags', deviationPct: 4.8),
      'steel': MaterialDeviation(estimated: 42, actual: 44.5, unit: 'tonnes', deviationPct: 5.9),
      'bricks': MaterialDeviation(estimated: 45000, actual: 44200, unit: 'nos', deviationPct: -1.7),
    },
    overallSeverity: 'normal',
    flagged: false,
    mlOverrunProbability: 0.14,
    aiInsightSummary: 'EXCELLENT STATUS: The project is running smoothly within planned cost constraints (ML Overrun Risk: 14.0%). Material deviations are well within 6% tolerance.',
    logCount: 18,
    computedAt: DateTime.now(),
  );
}
