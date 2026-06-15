// Phase 2d — data-driven assemblies (PlanSwift-style recipes).
//
// An Assembly expands ONE geometry driver (e.g. net wall area) into several
// costed line items via per-driver coefficients. The default set encodes the
// exact coefficients of the legacy EstimationEngine.calculateMaterials (with
// column volume taken at the standard 3m storey height), so the assembly
// rollup reproduces the current quantities — then every coefficient becomes
// editable per project.

enum ComponentType { material, labour }

class AssemblyComponent {
  final String itemKey; // rate-library key (cement, steel, bricks_*, ...)
  final double coefficient; // quantity per 1 unit of the driver
  final ComponentType type;

  const AssemblyComponent(this.itemKey, this.coefficient,
      {this.type = ComponentType.material});

  AssemblyComponent copyWith({double? coefficient}) =>
      AssemblyComponent(itemKey, coefficient ?? this.coefficient, type: type);

  Map<String, dynamic> toJson() => {
        'itemKey': itemKey,
        'coefficient': coefficient,
        'type': type.name,
      };

  factory AssemblyComponent.fromJson(Map<String, dynamic> j) =>
      AssemblyComponent(
        j['itemKey'] as String,
        (j['coefficient'] as num).toDouble(),
        type: ComponentType.values
            .firstWhere((t) => t.name == j['type'], orElse: () => ComponentType.material),
      );
}

class Assembly {
  final String id;
  final String name;
  final String driver; // geometry driver key (see AssemblyEngine.drivers)
  final String driverLabel; // e.g. "Net wall area (m²)"
  final List<AssemblyComponent> components;

  const Assembly({
    required this.id,
    required this.name,
    required this.driver,
    required this.driverLabel,
    required this.components,
  });

  Assembly withComponents(List<AssemblyComponent> next) => Assembly(
        id: id,
        name: name,
        driver: driver,
        driverLabel: driverLabel,
        components: next,
      );
}

class AssemblySet {
  final List<Assembly> assemblies;
  const AssemblySet(this.assemblies);

  Assembly? byId(String id) {
    for (final a in assemblies) {
      if (a.id == id) return a;
    }
    return null;
  }

  AssemblySet withAssembly(Assembly updated) => AssemblySet([
        for (final a in assemblies) if (a.id == updated.id) updated else a,
      ]);

  /// Per-project overrides: only coefficients that differ from defaults, keyed
  /// `assemblyId.itemKey`.
  Map<String, dynamic> toOverridesJson() {
    final defaults = AssemblySet.defaults();
    final out = <String, dynamic>{};
    for (final a in assemblies) {
      final da = defaults.byId(a.id);
      for (final c in a.components) {
        final dc = da?.components
            .firstWhere((x) => x.itemKey == c.itemKey, orElse: () => c);
        if (dc == null || dc.coefficient != c.coefficient) {
          out['${a.id}.${c.itemKey}'] = c.coefficient;
        }
      }
    }
    return out;
  }

  factory AssemblySet.fromOverrides(Map<String, dynamic>? overrides) {
    final base = AssemblySet.defaults();
    if (overrides == null || overrides.isEmpty) return base;
    return AssemblySet([
      for (final a in base.assemblies)
        a.withComponents([
          for (final c in a.components)
            overrides.containsKey('${a.id}.${c.itemKey}')
                ? c.copyWith(
                    coefficient:
                        (overrides['${a.id}.${c.itemKey}'] as num).toDouble())
                : c,
        ]),
    ]);
  }

  /// Default recipes — coefficients collapsed from the legacy engine so the
  /// rollup matches existing quantities exactly.
  factory AssemblySet.defaults() {
    const m = ComponentType.material;
    return const AssemblySet([
      Assembly(
        id: 'brick_masonry',
        name: 'Brick Masonry',
        driver: 'netWallArea',
        driverLabel: 'Net wall area (m²)',
        components: [
          AssemblyComponent('bricks', 90, type: m), // brick type may override
          AssemblyComponent('cement', 0.85, type: m),
          AssemblyComponent('sand', 0.15, type: m),
        ],
      ),
      Assembly(
        id: 'rcc_slab',
        name: 'RCC Slab',
        driver: 'floorArea',
        driverLabel: 'Floor area (m²)',
        components: [
          AssemblyComponent('cement', 3.69, type: m),
          AssemblyComponent('sand', 0.2025, type: m),
          AssemblyComponent('aggregate', 0.3825, type: m),
          AssemblyComponent('steel', 33.75, type: m),
        ],
      ),
      Assembly(
        id: 'columns',
        name: 'Columns',
        driver: 'columnCount',
        driverLabel: 'Column count',
        components: [
          AssemblyComponent('cement', 1.272, type: m),
          AssemblyComponent('aggregate', 0.13356, type: m),
          AssemblyComponent('steel', 37.4445, type: m),
        ],
      ),
      Assembly(
        id: 'beams',
        name: 'Beams',
        driver: 'beamLength',
        driverLabel: 'Beam length (m)',
        components: [
          AssemblyComponent('cement', 0.552, type: m),
          AssemblyComponent('aggregate', 0.05796, type: m),
          AssemblyComponent('steel', 10.833, type: m),
        ],
      ),
      Assembly(
        id: 'plastering',
        name: 'Plastering',
        driver: 'wallArea',
        driverLabel: 'Gross wall area (m²)',
        components: [
          AssemblyComponent('cement', 0.198, type: m),
          AssemblyComponent('sand', 0.0396, type: m),
        ],
      ),
      Assembly(
        id: 'screed',
        name: 'Floor Screed',
        driver: 'floorArea',
        driverLabel: 'Floor area (m²)',
        components: [
          AssemblyComponent('cement', 0.044, type: m),
          AssemblyComponent('sand', 0.008, type: m),
        ],
      ),
      Assembly(
        id: 'staircase',
        name: 'Staircase',
        driver: 'stairArea',
        driverLabel: 'Stair area (m²)',
        components: [
          AssemblyComponent('cement', 1.6, type: m),
          AssemblyComponent('aggregate', 0.168, type: m),
        ],
      ),
    ]);
  }
}
