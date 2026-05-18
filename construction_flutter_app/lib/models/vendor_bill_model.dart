import 'package:cloud_firestore/cloud_firestore.dart';

class BillItem {
  final String description;
  final double quantity;
  final String unit;
  final double rate;
  final double amount;

  BillItem({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.rate,
    required this.amount,
  });

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      description: json['description'] as String? ?? json['material'] as String? ?? '',
      quantity: (json['quantity'] as num? ?? 0.0).toDouble(),
      unit: json['unit'] as String? ?? 'Unit',
      rate: (json['rate'] as num? ?? json['ratePerUnit'] as num? ?? 0.0).toDouble(),
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'rate': rate,
      'amount': amount,
    };
  }
}

class VendorBillModel {
  final String id;
  final String projectId;
  final String vendorName;
  final double amount;
  final DateTime date;
  final String category;
  final String fileUrl;
  final String uploadedBy;
  final List<BillItem> items;
  final DateTime createdAt;

  VendorBillModel({
    required this.id,
    required this.projectId,
    required this.vendorName,
    required this.amount,
    required this.date,
    required this.category,
    required this.fileUrl,
    required this.uploadedBy,
    required this.items,
    required this.createdAt,
  });

  factory VendorBillModel.fromJson(Map<String, dynamic> json, [String? docId]) {
    return VendorBillModel(
      id: docId ?? json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      vendorName: json['vendorName'] as String? ?? 'Miscellaneous',
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      date: (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: json['category'] as String? ?? 'Other',
      fileUrl: json['fileUrl'] as String? ?? '',
      uploadedBy: json['uploadedBy'] as String? ?? 'Admin',
      items: json['items'] != null
          ? (json['items'] as List).map((i) => BillItem.fromJson(i as Map<String, dynamic>)).toList()
          : [],
      createdAt: (json['createdAt'] as Timestamp? ?? Timestamp.now()).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'vendorName': vendorName,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'category': category,
      'fileUrl': fileUrl,
      'uploadedBy': uploadedBy,
      'items': items.map((i) => i.toJson()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
