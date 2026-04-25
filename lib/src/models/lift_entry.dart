class LiftEntry {
  const LiftEntry({
    required this.id,
    required this.name,
    required this.weight,
    required this.reps,
    this.sets = 1,
    this.aiInsight,
    this.isPr = false,
    this.isBodyweight = false,
    this.addedWeight,
    this.strengthTier,
    this.strengthRatio,
    this.estimatedForceN,
    this.animalCode,
    this.splitGroup,
  });

  final String id;
  final String name;
  final double weight;
  final int reps;
  final int sets;
  final String? aiInsight;
  final bool isPr;
  final bool isBodyweight;
  final double? addedWeight;
  final String? strengthTier;
  final double? strengthRatio;
  final double? estimatedForceN;
  final String? animalCode;
  final String? splitGroup;

  LiftEntry copyWith({
    String? id,
    String? name,
    double? weight,
    int? reps,
    int? sets,
    String? aiInsight,
    bool? isPr,
    bool? isBodyweight,
    double? addedWeight,
    String? strengthTier,
    double? strengthRatio,
    double? estimatedForceN,
    String? animalCode,
    String? splitGroup,
  }) {
    return LiftEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      weight: weight ?? this.weight,
      reps: reps ?? this.reps,
      sets: sets ?? this.sets,
      aiInsight: aiInsight ?? this.aiInsight,
      isPr: isPr ?? this.isPr,
      isBodyweight: isBodyweight ?? this.isBodyweight,
      addedWeight: addedWeight ?? this.addedWeight,
      strengthTier: strengthTier ?? this.strengthTier,
      strengthRatio: strengthRatio ?? this.strengthRatio,
      estimatedForceN: estimatedForceN ?? this.estimatedForceN,
      animalCode: animalCode ?? this.animalCode,
      splitGroup: splitGroup ?? this.splitGroup,
    );
  }

  factory LiftEntry.fromDynamic(dynamic raw) {
    final map = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw as Map);
    return LiftEntry(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      weight: _asDouble(map['weight']) ?? 0,
      reps: _asInt(map['reps']) ?? 1,
      sets: _asInt(map['sets']) ?? 1,
      aiInsight: map['aiInsight']?.toString(),
      isPr: _asBool(map['isPR']),
      isBodyweight: _asBool(map['isBodyweight']),
      addedWeight: _asDouble(map['addedWeight']),
      strengthTier: map['strengthTier']?.toString(),
      strengthRatio: _asDouble(map['strengthRatio']),
      estimatedForceN: _asDouble(map['estimatedForceN']),
      animalCode: map['animalCode']?.toString(),
      splitGroup: map['splitGroup']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'id': id,
      'name': name,
      'weight': weight,
      'reps': reps,
      'sets': sets,
      'isPR': isPr,
      'isBodyweight': isBodyweight,
    };
    if (aiInsight != null && aiInsight!.trim().isNotEmpty) {
      payload['aiInsight'] = aiInsight;
    }
    if (addedWeight != null) {
      payload['addedWeight'] = addedWeight;
    }
    if (strengthTier != null && strengthTier!.trim().isNotEmpty) {
      payload['strengthTier'] = strengthTier;
    }
    if (strengthRatio != null) {
      payload['strengthRatio'] = strengthRatio;
    }
    if (estimatedForceN != null) {
      payload['estimatedForceN'] = estimatedForceN;
    }
    if (animalCode != null && animalCode!.trim().isNotEmpty) {
      payload['animalCode'] = animalCode;
    }
    if (splitGroup != null && splitGroup!.trim().isNotEmpty) {
      payload['splitGroup'] = splitGroup;
    }
    return payload;
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }
}
