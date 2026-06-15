/// Phase 3 — project-level cost adjustments applied to the detailed BOQ:
/// material wastage (inflates quantities), overhead & profit, and contingency
/// (added on the materials subtotal). Persisted per project.
class CostAdjustments {
  final double wastePercent; // applied to material quantities
  final double overheadProfitPercent; // OH&P on the subtotal
  final double contingencyPercent; // contingency on the subtotal

  const CostAdjustments({
    this.wastePercent = 5,
    this.overheadProfitPercent = 15,
    this.contingencyPercent = 3,
  });

  double get wasteFactor => 1 + wastePercent / 100;

  /// Final total from a pre-waste materials subtotal that ALREADY includes
  /// wastage (i.e. lines were inflated by [wasteFactor]).
  double finalTotal(double subtotalInclWaste) =>
      subtotalInclWaste *
      (1 + overheadProfitPercent / 100) *
      (1 + contingencyPercent / 100);

  double overheadAmount(double subtotalInclWaste) =>
      subtotalInclWaste * overheadProfitPercent / 100;

  double contingencyAmount(double subtotalInclWaste) =>
      (subtotalInclWaste + overheadAmount(subtotalInclWaste)) *
      contingencyPercent /
      100;

  CostAdjustments copyWith({
    double? wastePercent,
    double? overheadProfitPercent,
    double? contingencyPercent,
  }) =>
      CostAdjustments(
        wastePercent: wastePercent ?? this.wastePercent,
        overheadProfitPercent:
            overheadProfitPercent ?? this.overheadProfitPercent,
        contingencyPercent: contingencyPercent ?? this.contingencyPercent,
      );

  Map<String, dynamic> toJson() => {
        'wastePercent': wastePercent,
        'overheadProfitPercent': overheadProfitPercent,
        'contingencyPercent': contingencyPercent,
      };

  factory CostAdjustments.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const CostAdjustments();
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    return CostAdjustments(
      wastePercent: d('wastePercent', 5),
      overheadProfitPercent: d('overheadProfitPercent', 15),
      contingencyPercent: d('contingencyPercent', 3),
    );
  }
}
