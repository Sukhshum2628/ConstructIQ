import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vendor_bill_model.dart';

class VendorBillService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> uploadBill({
    required VendorBillModel bill,
    dynamic file,
  }) async {
    try {
      // Save Metadata to Firestore
      final billData = bill.toJson();
      billData['fileUrl'] = '';

      await _db
          .collection('projects')
          .doc(bill.projectId)
          .collection('vendorBills')
          .doc(bill.id)
          .set(billData);
          
      // Success: Bill archived in firestore
    } catch (e) {
      throw Exception('Archive failed: $e');
    }
  }

  Stream<List<VendorBillModel>> getProjectBills(String projectId) {
    return _db
        .collection('projects')
        .doc(projectId)
        .collection('vendorBills')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => VendorBillModel.fromJson(doc.data(), doc.id)).toList());
  }

  // To show 'Recent Bills' across multiple projects on Owner Dashboard
  Stream<List<VendorBillModel>> getRecentBillsAcrossProjects(List<String> projectIds) {
    if (projectIds.isEmpty) return Stream.value([]);
    
    return _db
        .collectionGroup('vendorBills')
        .where('projectId', whereIn: projectIds)
        .orderBy('date', descending: true)
        .limit(10)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => VendorBillModel.fromJson(doc.data(), doc.id)).toList());
  }
}
