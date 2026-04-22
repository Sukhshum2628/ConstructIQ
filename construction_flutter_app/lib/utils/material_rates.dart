class MaterialRates {
  /// Approximate CPWD/Market rates in INR (₹)
  static const Map<String, Map<String, dynamic>> defaultRates = {
    'cement': {'rate': 400.0, 'unit': 'Bag'}, 
    'bricks': {'rate': 12.0, 'unit': 'Nos'},  
    'steel': {'rate': 70.0, 'unit': 'Kg'},   
    'sand': {'rate': 95.0, 'unit': 'cu.ft'},  
    'aggregate': {'rate': 140.0, 'unit': 'cu.ft'}, 
    'painting': {'rate': 55.0, 'unit': 'sq.ft'},
    'flooring': {'rate': 210.0, 'unit': 'sq.ft'},
    'plastering': {'rate': 95.0, 'unit': 'sq.ft'},
  };

  static double getRateForMaterial(String materialName) {
    final nameNormalized = materialName.toLowerCase().trim();
    
    for (final entry in defaultRates.entries) {
      if (nameNormalized.contains(entry.key)) {
        return entry.value['rate'] as double;
      }
    }
    return 0.0;
  }

  static String getRateUnitForMaterial(String materialName) {
    final nameNormalized = materialName.toLowerCase().trim();
    for (final entry in defaultRates.entries) {
      if (nameNormalized.contains(entry.key)) {
        return entry.value['unit'] as String;
      }
    }
    return '';
  }

  static double calculateEstimatedCost(String materialName, double quantity) {
    final effectiveQty = getQuantityInRateUnit(materialName, quantity);
    final rate = getRateForMaterial(materialName);
    return rate * effectiveQty;
  }

  static double getQuantityInRateUnit(String materialName, double quantity) {
    final nameNormalized = materialName.toLowerCase().trim();
    
    // Conversion for materials where backend gives m3 but rates are per cu.ft
    if (nameNormalized.contains('sand') || nameNormalized.contains('aggregate')) {
      // 1 m3 = 35.3147 cubic feet
      return quantity * 35.3147;
    }
    
    return quantity;
  }
}
