enum StrengthTier { beginner, novice, intermediate, advanced, elite }

enum _MovementType { bench, squat, deadlift, overhead, pull, accessory }

class StrengthEvaluation {
  const StrengthEvaluation({
    required this.tier,
    required this.ratio,
    required this.forceNewtons,
    this.animalCode,
  });

  final StrengthTier tier;
  final double ratio;
  final double forceNewtons;
  final String? animalCode;
}

class StrengthEvaluator {
  static const Map<
    _MovementType,
    ({double novice, double intermediate, double advanced, double elite})
  >
  _thresholds = {
    _MovementType.bench: (
      novice: 0.65,
      intermediate: 0.90,
      advanced: 1.20,
      elite: 1.50,
    ),
    _MovementType.squat: (
      novice: 0.85,
      intermediate: 1.15,
      advanced: 1.50,
      elite: 1.90,
    ),
    _MovementType.deadlift: (
      novice: 1.00,
      intermediate: 1.35,
      advanced: 1.75,
      elite: 2.20,
    ),
    _MovementType.overhead: (
      novice: 0.45,
      intermediate: 0.60,
      advanced: 0.80,
      elite: 1.00,
    ),
    _MovementType.pull: (
      novice: 0.60,
      intermediate: 0.85,
      advanced: 1.10,
      elite: 1.35,
    ),
    _MovementType.accessory: (
      novice: 0.40,
      intermediate: 0.60,
      advanced: 0.80,
      elite: 1.00,
    ),
  };

  static StrengthEvaluation evaluate({
    required String exerciseName,
    required double liftedKg,
    required double bodyweightKg,
    required bool includeAnimal,
  }) {
    final movement = _movementType(exerciseName);
    final thresholds =
        _thresholds[movement] ?? _thresholds[_MovementType.accessory]!;
    final safeBodyweight = bodyweightKg > 0 ? bodyweightKg : 75.0;
    final safeLifted = liftedKg > 0 ? liftedKg : 0.0;
    final ratio = safeBodyweight == 0 ? 0.0 : (safeLifted / safeBodyweight);
    final force = safeLifted * 9.81;
    final tier = _tierFromRatio(ratio, thresholds);

    return StrengthEvaluation(
      tier: tier,
      ratio: ratio,
      forceNewtons: force,
      animalCode: includeAnimal ? _animalCode(force) : null,
    );
  }

  static StrengthTier? parseTierCode(String? code) {
    return switch (code) {
      'beginner' => StrengthTier.beginner,
      'novice' => StrengthTier.novice,
      'intermediate' => StrengthTier.intermediate,
      'advanced' => StrengthTier.advanced,
      'elite' => StrengthTier.elite,
      _ => null,
    };
  }

  static String tierCode(StrengthTier tier) => tier.name;

  static String strengthLine({
    required String? tierCode,
    required double? ratio,
    required bool isArabic,
  }) {
    final tier = parseTierCode(tierCode);
    if (tier == null || ratio == null) {
      return isArabic
          ? 'مستوى القوة: جاري الحساب.'
          : 'Strength level: calculating.';
    }

    final label = isArabic ? _tierLabelAr(tier) : _tierLabelEn(tier);
    final ratioText = ratio.toStringAsFixed(2);
    return isArabic
        ? 'مستوى القوة: $label (${ratioText}x من وزن جسمك).'
        : 'Your strength level: $label (${ratioText}x bodyweight).';
  }

  static String? animalLine({
    required String? animalCode,
    required double? forceNewtons,
    required bool isArabic,
  }) {
    if (animalCode == null || forceNewtons == null || forceNewtons <= 0) {
      return null;
    }

    final label = isArabic
        ? _animalLabelAr(animalCode)
        : _animalLabelEn(animalCode);
    if (label == null) {
      return null;
    }

    final forceText = forceNewtons.toStringAsFixed(0);
    return isArabic
        ? 'مقارنة للمتعة: قوة قريبة من $label (~$forceText نيوتن).'
        : 'Fun comparison: force close to $label (~$forceText N).';
  }

  static _MovementType _movementType(String exerciseName) {
    final normalized = exerciseName.toLowerCase();

    if (normalized.contains('deadlift') || normalized.contains('rdl')) {
      return _MovementType.deadlift;
    }
    if (normalized.contains('squat') ||
        normalized.contains('leg press') ||
        normalized.contains('lunge')) {
      return _MovementType.squat;
    }
    if (normalized.contains('bench') ||
        normalized.contains('dip') ||
        normalized.contains('push up') ||
        normalized.contains('push-up')) {
      return _MovementType.bench;
    }
    if (normalized.contains('overhead') ||
        normalized.contains('shoulder press') ||
        normalized.contains('arnold')) {
      return _MovementType.overhead;
    }
    if (normalized.contains('row') ||
        normalized.contains('pull up') ||
        normalized.contains('pull-up') ||
        normalized.contains('chin up') ||
        normalized.contains('chin-up') ||
        normalized.contains('pulldown')) {
      return _MovementType.pull;
    }

    return _MovementType.accessory;
  }

  static StrengthTier _tierFromRatio(
    double ratio,
    ({double novice, double intermediate, double advanced, double elite})
    thresholds,
  ) {
    if (ratio < thresholds.novice) {
      return StrengthTier.beginner;
    }
    if (ratio < thresholds.intermediate) {
      return StrengthTier.novice;
    }
    if (ratio < thresholds.advanced) {
      return StrengthTier.intermediate;
    }
    if (ratio < thresholds.elite) {
      return StrengthTier.advanced;
    }
    return StrengthTier.elite;
  }

  static String _animalCode(double forceNewtons) {
    if (forceNewtons < 450) {
      return 'border_collie_tug';
    }
    if (forceNewtons < 800) {
      return 'gray_wolf_bite';
    }
    if (forceNewtons < 1200) {
      return 'leopard_swipe';
    }
    if (forceNewtons < 1700) {
      return 'male_lion_strike';
    }
    if (forceNewtons < 2300) {
      return 'siberian_tiger_strike';
    }
    return 'young_horse_kick';
  }

  static String _tierLabelEn(StrengthTier tier) {
    return switch (tier) {
      StrengthTier.beginner => 'Beginner',
      StrengthTier.novice => 'Novice',
      StrengthTier.intermediate => 'Intermediate',
      StrengthTier.advanced => 'Advanced',
      StrengthTier.elite => 'Elite',
    };
  }

  static String _tierLabelAr(StrengthTier tier) {
    return switch (tier) {
      StrengthTier.beginner => 'مبتدئ',
      StrengthTier.novice => 'لسه بتثبت نفسك',
      StrengthTier.intermediate => 'متوسط جامد',
      StrengthTier.advanced => 'متقدم قوي',
      StrengthTier.elite => 'نخبوي',
    };
  }

  static String? _animalLabelEn(String code) {
    return switch (code) {
      'border_collie_tug' => 'a border collie tug pull',
      'gray_wolf_bite' => 'a gray wolf bite pull',
      'leopard_swipe' => 'a leopard forelimb swipe',
      'male_lion_strike' => 'a male lion forelimb strike',
      'siberian_tiger_strike' => 'a Siberian tiger forelimb strike',
      'young_horse_kick' => 'a young horse kick impact',
      _ => null,
    };
  }

  static String? _animalLabelAr(String code) {
    return switch (code) {
      'border_collie_tug' => 'سحبة كلب بوردر كولي',
      'gray_wolf_bite' => 'قوة عضة ذئب رمادي',
      'leopard_swipe' => 'ضربة رجل أمامية لنمر',
      'male_lion_strike' => 'ضربة رجل أمامية لأسد ذكر',
      'siberian_tiger_strike' => 'ضربة رجل أمامية لنمر سيبيري',
      'young_horse_kick' => 'رفسة حصان صغير',
      _ => null,
    };
  }
}
