import '../utils/material_rates.dart';
import 'rate_library.dart';

/// Phase 4 — a finish package (quality tier) and a regional rate profile.
/// Both compose onto a project's rate library: the package scales interior
/// finish rates and suggests brick/tile specs; the region scales all rates.

class FinishPackage {
  final String key;
  final String label;
  final double interiorFactor; // multiplier on interior/finish rates
  final String brickType; // suggested brick spec
  final String tileSize; // suggested tile spec
  const FinishPackage(
      this.key, this.label, this.interiorFactor, this.brickType, this.tileSize);
}

class RegionProfile {
  final String key;
  final String label;
  final double factor; // multiplier on all rates
  const RegionProfile(this.key, this.label, this.factor);
}

class EstimationCatalog {
  static const Map<String, FinishPackage> packages = {
    'economy': FinishPackage('economy', 'Economy', 0.7, 'flyash', '300x300'),
    'standard': FinishPackage('standard', 'Standard', 1.0, 'modular_mix', '600x600'),
    'premium': FinishPackage('premium', 'Premium', 1.8, 'wirecut', '800x800'),
  };

  static const Map<String, RegionProfile> regions = {
    'metro': RegionProfile('metro', 'Metro', 1.15),
    'tier1': RegionProfile('tier1', 'Tier-1 City', 1.05),
    'tier2': RegionProfile('tier2', 'Tier-2 / Standard', 1.0),
    'rural': RegionProfile('rural', 'Rural', 0.88),
  };

  static const FinishPackage _stdPackage =
      FinishPackage('standard', 'Standard', 1.0, 'modular_mix', '600x600');
  static const RegionProfile _stdRegion =
      RegionProfile('tier2', 'Tier-2 / Standard', 1.0);
}

class EstimationProfile {
  final String packageKey;
  final String regionKey;

  const EstimationProfile({
    this.packageKey = 'standard',
    this.regionKey = 'tier2',
  });

  FinishPackage get package =>
      EstimationCatalog.packages[packageKey] ?? EstimationCatalog._stdPackage;
  RegionProfile get region =>
      EstimationCatalog.regions[regionKey] ?? EstimationCatalog._stdRegion;

  /// Compose this profile onto a base rate library: interior rates × package
  /// factor, then all rates × region factor.
  RateLibrary apply(RateLibrary base) {
    final interiorKeys = MaterialRates.interiorRates.keys.toSet();
    final pf = package.interiorFactor;
    final rf = region.factor;
    final items = base.items.map((k, it) {
      var rate = it.materialRate;
      if (interiorKeys.contains(k)) rate *= pf;
      rate *= rf;
      return MapEntry(k, it.copyWith(materialRate: rate));
    });
    return RateLibrary(items);
  }

  EstimationProfile copyWith({String? packageKey, String? regionKey}) =>
      EstimationProfile(
        packageKey: packageKey ?? this.packageKey,
        regionKey: regionKey ?? this.regionKey,
      );

  Map<String, dynamic> toJson() =>
      {'packageKey': packageKey, 'regionKey': regionKey};

  factory EstimationProfile.fromJson(Map<String, dynamic>? j) => EstimationProfile(
        packageKey: (j?['packageKey'] as String?) ?? 'standard',
        regionKey: (j?['regionKey'] as String?) ?? 'tier2',
      );
}
