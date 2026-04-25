import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/exercises.dart';
import '../../localization/egyptian_gym_lexicon.dart';
import '../../models/app_user.dart';
import '../../models/gym_split.dart';
import '../../models/lift_entry.dart';
import '../../models/training_session.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../utils/strength_evaluator.dart';

class AddLiftSheet extends StatefulWidget {
  const AddLiftSheet({
    required this.userId,
    required this.profile,
    required this.sessions,
    required this.onCreateSession,
    required this.onAppendSession,
    super.key,
  });

  final String userId;
  final AppUser profile;
  final List<TrainingSession> sessions;
  final Future<bool> Function(String sessionName, List<LiftEntry> lifts)
  onCreateSession;
  final Future<bool> Function(String sessionId, List<LiftEntry> lifts)
  onAppendSession;

  @override
  State<AddLiftSheet> createState() => _AddLiftSheetState();
}

enum _ExerciseSourceMode { split, different }

class _AddLiftSheetState extends State<AddLiftSheet> {
  final _uuid = const Uuid();
  final _service = SupabaseService.instance;
  final _sessionNameController = TextEditingController();
  final _searchController = TextEditingController();
  final _weightController = TextEditingController();
  final _repsController = TextEditingController();
  final _setsController = TextEditingController(text: '1');
  final _addedWeightController = TextEditingController(text: '0');

  final List<LiftEntry> _pendingLifts = <LiftEntry>[];
  String _selectedSessionId = 'new';
  String? _selectedExercise;
  bool _isBodyweight = false;
  bool _postToFeed = false;
  bool _saving = false;
  bool _isAnalyzing = false;
  bool _loadingTodayPlan = true;
  String? _currentAiInsight;
  String? _error;
  SplitScheduleEntry? _todaySplitEntry;
  _ExerciseSourceMode? _exerciseSourceMode;

  @override
  void initState() {
    super.initState();
    _loadTodaySplitPlan();
  }

  List<TrainingSession> get _todaySessions =>
      widget.sessions.where((session) => session.isToday).toList();

  bool get _hasAvailableSplitPlan => _todaySplitEntry != null;

  double get _bodyweight => widget.profile.weight ?? 75;

  String? get _resolvedExerciseName {
    final selected = _selectedExercise?.trim();
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }

    final typed = EgyptianGymLexicon.canonicalTerm(
      _searchController.text.trim(),
    );
    if (typed.isNotEmpty) {
      return typed;
    }

    return null;
  }

  String _exerciseLabel(String exerciseName, AppSettings settings) {
    return settings.isArabic
        ? EgyptianGymLexicon.term(exerciseName)
        : exerciseName;
  }

  double? _parseWeight(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  bool get _canGenerateInsight {
    final exercise = _resolvedExerciseName;
    final reps = int.tryParse(_repsController.text.trim());
    final sets = int.tryParse(_setsController.text.trim());
    if (exercise == null ||
        reps == null ||
        reps < 1 ||
        sets == null ||
        sets < 1) {
      return false;
    }

    if (_isBodyweight) {
      return true;
    }

    final weight = _parseWeight(_weightController.text);
    return weight != null && weight > 0;
  }

  bool get _canAddLift => _canGenerateInsight;

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _loadTodaySplitPlan() async {
    setState(() {
      _loadingTodayPlan = true;
    });

    try {
      final split = await _service.fetchSplitSchedule(widget.userId);
      if (!mounted) {
        return;
      }

      SplitScheduleEntry? entry;
      if (split != null && split.schedule.isNotEmpty) {
        final now = DateTime.now();
        for (final day in split.schedule) {
          if (_isSameDate(day.date, now) && !day.completed) {
            entry = day;
            break;
          }
        }

        entry ??= split.currentDayIndex >= 0 &&
                split.currentDayIndex < split.schedule.length
            ? split.schedule[split.currentDayIndex]
            : null;
      }

      setState(() {
        _todaySplitEntry = entry;
        if (entry == null) {
          _exerciseSourceMode = _ExerciseSourceMode.different;
        }
        _loadingTodayPlan = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _exerciseSourceMode ??= _ExerciseSourceMode.different;
        _loadingTodayPlan = false;
      });
    }
  }

  String _normalizeExercise(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
  }

  String _sectionKeyFromExercise(String exerciseName) {
    final n = _normalizeExercise(exerciseName);

    if (n.contains('bench') ||
        n.contains('dip') ||
        n.contains('push up') ||
        n.contains('pushup')) {
      return 'bench';
    }
    if (n.contains('squat') ||
        n.contains('leg press') ||
        n.contains('lunge')) {
      return 'squat';
    }
    if (n.contains('deadlift') || n.contains('rdl')) {
      return 'hinge';
    }
    if (n.contains('overhead') ||
        n.contains('shoulder press') ||
        n.contains('arnold')) {
      return 'press';
    }
    if (n.contains('row') ||
        n.contains('pull up') ||
        n.contains('pullup') ||
        n.contains('chin up') ||
        n.contains('chinup') ||
        n.contains('pulldown')) {
      return 'pull';
    }
    if (n.contains('curl')) {
      return 'biceps';
    }
    if (n.contains('tricep')) {
      return 'triceps';
    }

    return n;
  }

  bool _matchesPlannedExercise({
    required ExerciseEntry planned,
    required String selectedExercise,
  }) {
    final selected = _normalizeExercise(selectedExercise);
    if (selected == _normalizeExercise(planned.name)) {
      return true;
    }

    for (final variation in planned.variations) {
      if (selected == _normalizeExercise(variation)) {
        return true;
      }
    }

    return _sectionKeyFromExercise(selectedExercise) ==
        _sectionKeyFromExercise(planned.name);
  }

  int _recommendedReps(String range) {
    final match = RegExp(r'\d+').firstMatch(range);
    if (match == null) {
      return 8;
    }
    return int.tryParse(match.group(0) ?? '') ?? 8;
  }

  List<String> _aiAlternativesFor(ExerciseEntry planned) {
    final listed = planned.variations
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (listed.isNotEmpty) {
      return listed;
    }

    final key = _sectionKeyFromExercise(planned.name);
    return exerciseCatalog
        .where((candidate) {
          return candidate != planned.name &&
              _sectionKeyFromExercise(candidate) == key;
        })
        .take(3)
        .toList();
  }

  Future<void> _applyPlannedExercise(
    ExerciseEntry planned, {
    String? selectedName,
    bool openQuickEntry = false,
  }) async {
    final settings = context.appSettings;
    final chosen = (selectedName ?? planned.name).trim();
    if (chosen.isEmpty) {
      return;
    }

    setState(() {
      _selectedExercise = chosen;
      _searchController.text = _exerciseLabel(chosen, settings);
      _setsController.text = planned.sets.toString();
      _repsController.text = _recommendedReps(planned.reps).toString();
      _isBodyweight = bodyweightExercises.contains(chosen);
      if (!_isBodyweight) {
        _addedWeightController.text = '0';
      }
    });

    if (openQuickEntry && mounted) {
      await _showQuickEntryForPlannedExercise(
        planned: planned,
        chosenName: chosen,
      );
    }
  }

  Future<void> _showQuickEntryForPlannedExercise({
    required ExerciseEntry planned,
    required String chosenName,
  }) async {
    if (!mounted) {
      return;
    }

    final settings = context.appSettings;
    var addingWithAi = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                settings.tx('Quick Lift Entry', 'تسجيل سريع للرفعة'),
              ),
              content: SingleChildScrollView(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _weightController,
                    _addedWeightController,
                    _repsController,
                    _setsController,
                  ]),
                  builder: (context, _) {
                    final canAdd = _canAddLift;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          settings.tx(
                            'Selected from today split:',
                            'تم اختياره من سبليت النهارده:',
                          ),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _exerciseLabel(chosenName, settings),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${planned.sets} ${settings.tx('sets', 'جمل')} • ${planned.reps} ${settings.tx('target', 'مستهدف')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        if (bodyweightExercises.contains(chosenName))
                          SwitchListTile.adaptive(
                            value: _isBodyweight,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              settings.tx(
                                'Bodyweight mode',
                                'وضع وزن الجسم',
                              ),
                            ),
                            subtitle: Text(
                              settings.tx(
                                'Uses ${_bodyweight.toStringAsFixed(1)}kg base weight',
                                'هيستخدم ${_bodyweight.toStringAsFixed(1)} كجم كوزن أساسي',
                              ),
                            ),
                            onChanged: (enabled) {
                              setState(() {
                                _isBodyweight = enabled;
                              });
                              setDialogState(() {});
                            },
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _isBodyweight
                                    ? _addedWeightController
                                    : _weightController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: _isBodyweight
                                      ? settings.tx(
                                          'Added (kg)',
                                          'إضافي (كجم)',
                                        )
                                      : settings.tx('Weight (kg)', 'الوزن (كجم)'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _repsController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: settings.tx('Reps', 'العدات'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _setsController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText: settings.tx('Sets', 'الجمل'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (canAdd)
                          Text(
                            _equivalentNote(_effectiveWeight(), settings),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: canAdd && !addingWithAi
                                    ? () {
                                        _addLiftToPending();
                                        Navigator.of(dialogContext).pop();
                                      }
                                    : null,
                                child: Text(
                                  settings.tx('Quick Add', 'إضافة سريعة'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: canAdd && !addingWithAi
                                    ? () async {
                                        setDialogState(() {
                                          addingWithAi = true;
                                        });
                                        await _generateAiInsight();
                                        if (!mounted) {
                                          return;
                                        }
                                        _addLiftToPending();
                                        if (dialogContext.mounted) {
                                          Navigator.of(dialogContext).pop();
                                        }
                                      }
                                    : null,
                                child: addingWithAi
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      )
                                    : Text(
                                        settings.tx(
                                          'AI + Add',
                                          'الذكاء + إضافة',
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: addingWithAi
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(settings.tx('Close', 'إغلاق')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Set<String> _completedPlannedSections() {
    final plan = _todaySplitEntry;
    if (plan == null) {
      return const <String>{};
    }

    final completed = <String>{};
    for (final planned in plan.exercises) {
      final matched = _pendingLifts.any(
        (lift) => _matchesPlannedExercise(
          planned: planned,
          selectedExercise: lift.name,
        ),
      );
      if (matched) {
        completed.add(_sectionKeyFromExercise(planned.name));
      }
    }

    return completed;
  }

  ({String imageUrl, String en, String ar}) _animalVisual(String? animalCode) {
    return switch (animalCode) {
      'border_collie_tug' => (
        imageUrl:
            'https://images.unsplash.com/photo-1552053831-71594a27632d?auto=format&fit=crop&w=900&q=80',
        en: 'a border collie',
        ar: 'كلب بوردر كولي',
      ),
      'gray_wolf_bite' => (
        imageUrl:
            'https://images.unsplash.com/photo-1474511320723-9a56873867b5?auto=format&fit=crop&w=900&q=80',
        en: 'a wolf',
        ar: 'ذئب',
      ),
      'leopard_swipe' => (
        imageUrl:
            'https://images.unsplash.com/photo-1456926631375-92c8ce872def?auto=format&fit=crop&w=900&q=80',
        en: 'a leopard',
        ar: 'نمر',
      ),
      'male_lion_strike' => (
        imageUrl:
            'https://images.unsplash.com/photo-1546182990-dffeafbe841d?auto=format&fit=crop&w=900&q=80',
        en: 'a lion',
        ar: 'أسد',
      ),
      'siberian_tiger_strike' => (
        imageUrl:
            'https://images.unsplash.com/photo-1549480017-d76466a4b7e8?auto=format&fit=crop&w=900&q=80',
        en: 'a tiger',
        ar: 'نمر سيبيري',
      ),
      'young_horse_kick' => (
        imageUrl:
            'https://images.unsplash.com/photo-1553284965-83fd3e82fa5a?auto=format&fit=crop&w=900&q=80',
        en: 'a horse',
        ar: 'حصان',
      ),
      _ => (
        imageUrl:
            'https://images.unsplash.com/photo-1474511320723-9a56873867b5?auto=format&fit=crop&w=900&q=80',
        en: 'a wild animal',
        ar: 'حيوان مفترس',
      ),
    };
  }

  String _exerciseEquipmentTag(String exerciseName, AppSettings settings) {
    final normalized = exerciseName.toLowerCase();
    if (normalized.contains('dumbbell') || normalized.contains('db ')) {
      return settings.tx('Dumbbell', 'دمبل');
    }
    if (normalized.contains('barbell')) {
      return settings.tx('Barbell', 'بار');
    }
    if (normalized.contains('cable')) {
      return settings.tx('Cable', 'كيبل');
    }
    if (normalized.contains('machine')) {
      return settings.tx('Machine', 'ماكينة');
    }
    if (normalized.contains('bodyweight') ||
        normalized.contains('push up') ||
        normalized.contains('pull up') ||
        normalized.contains('chin up')) {
      return settings.tx('Bodyweight', 'وزن جسم');
    }
    return settings.tx('Strength', 'قوة');
  }

  String _exercisePatternTag(String exerciseName, AppSettings settings) {
    final normalized = exerciseName.toLowerCase();
    if (normalized.contains('bench') || normalized.contains('dip')) {
      return settings.tx('Primary Compound', 'مركب أساسي');
    }
    if (normalized.contains('overhead') || normalized.contains('shoulder')) {
      return settings.tx('Vertical Push', 'دفع رأسي');
    }
    if (normalized.contains('row') ||
        normalized.contains('pull') ||
        normalized.contains('lat')) {
      return settings.tx('Back Pull', 'سحب ظهر');
    }
    if (normalized.contains('squat') || normalized.contains('leg press')) {
      return settings.tx('Lower Body', 'جزء سفلي');
    }
    if (normalized.contains('deadlift') || normalized.contains('rdl')) {
      return settings.tx('Posterior Chain', 'سلسلة خلفية');
    }
    return settings.tx('Strength Builder', 'بناء قوة');
  }

  String _animalMetricTitle(String exerciseName, AppSettings settings) {
    final normalized = exerciseName.toLowerCase();
    if (normalized.contains('deadlift') || normalized.contains('rdl')) {
      return settings.tx('Deadlift Max', 'أقصى ديدليفت');
    }
    if (normalized.contains('bench') || normalized.contains('dip')) {
      return settings.tx('Bench Press Max', 'أقصى بنش برس');
    }
    if (normalized.contains('squat') || normalized.contains('leg press')) {
      return settings.tx('Back Squat Max', 'أقصى سكوات');
    }
    if (normalized.contains('overhead') || normalized.contains('shoulder')) {
      return settings.tx('Overhead Press Max', 'أقصى أوفرهيد برس');
    }
    return settings.tx('${_exerciseLabel(exerciseName, settings)} Max', 'أقصى ${_exerciseLabel(exerciseName, settings)}');
  }

  String _tierBadgeLabel(String? tierCode, AppSettings settings) {
    final tier = StrengthEvaluator.parseTierCode(tierCode);
    return switch (tier) {
      StrengthTier.elite => settings.tx('Elite Tier', 'فئة نخبوية'),
      StrengthTier.advanced => settings.tx('Advanced Tier', 'فئة متقدمة'),
      StrengthTier.intermediate =>
        settings.tx('Intermediate Tier', 'فئة متوسطة'),
      StrengthTier.novice => settings.tx('Novice Tier', 'فئة مبتدئ'),
      StrengthTier.beginner => settings.tx('Starter Tier', 'فئة البداية'),
      null => settings.tx('Power Tier', 'فئة القوة'),
    };
  }

  ({IconData icon, Color accent}) _animalBadgeStyle(String? animalCode) {
    return switch (animalCode) {
      'male_lion_strike' || 'siberian_tiger_strike' => (
        icon: Icons.volume_up_rounded,
        accent: AppColors.secondary,
      ),
      'young_horse_kick' => (
        icon: Icons.forest_rounded,
        accent: AppColors.primary,
      ),
      _ => (icon: Icons.pets_rounded, accent: AppColors.primary),
    };
  }

  Future<void> _copyComparisonSummary({
    required List<LiftEntry> lifts,
    required AppSettings settings,
  }) async {
    final lines = <String>[
      settings.tx('Animal Strength Comparison', 'مقارنة قوة الحيوانات'),
      ...lifts.map((lift) {
        final animal = _animalVisual(lift.animalCode);
        final title = _animalMetricTitle(lift.name, settings);
        return settings.tx(
          '$title: ${lift.weight.toStringAsFixed(0)}kg - ${animal.en}',
          '$title: ${lift.weight.toStringAsFixed(0)} كجم - ${animal.ar}',
        );
      }),
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          settings.tx(
            'Stats copied. Ready to share.',
            'تم نسخ النتائج. جاهزة للمشاركة.',
          ),
        ),
      ),
    );
  }

  Future<void> _showSessionPowerPopup() async {
    if (_pendingLifts.isEmpty || !mounted) {
      return;
    }

    final settings = context.appSettings;
    final spotlightLifts = [..._pendingLifts]
      ..sort(
        (a, b) =>
            (b.estimatedForceN ?? 0).compareTo(a.estimatedForceN ?? 0),
      );
    final comparisonLifts = spotlightLifts.take(3).toList();
    final topTier = _tierBadgeLabel(comparisonLifts.first.strengthTier, settings);
    final headingStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: -0.9,
      height: 1.05,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.92,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A0D12),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: AppColors.outline.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.secondary.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              settings.tx('TIER ASSESSMENT', 'تقييم المستوى'),
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.8,
                                  ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.onSurfaceVariant,
                          size: 34,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    settings.tx(
                      'ANIMAL STRENGTH\nCOMPARISON',
                      'مقارنة\nقوة الحيوانات',
                    ),
                    textAlign: TextAlign.center,
                    style: headingStyle,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                    child: Column(
                      children: comparisonLifts.asMap().entries.map((entry) {
                        final index = entry.key;
                        final lift = entry.value;
                        final animal = _animalVisual(lift.animalCode);
                        final badgeStyle = _animalBadgeStyle(lift.animalCode);
                        final cardTitle = _animalMetricTitle(lift.name, settings);
                        final insight = settings.tx(
                          'You\'re as strong as ${animal.en}!',
                          'قوتك زي ${animal.ar}!',
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceHigh.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: AppColors.outline.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            settings.isArabic
                                                ? cardTitle
                                                : cardTitle.toUpperCase(),
                                            style: Theme.of(dialogContext)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: index == 1
                                                      ? AppColors.secondary
                                                      : AppColors.primary,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.4,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                lift.weight.toStringAsFixed(0),
                                                style: Theme.of(dialogContext)
                                                    .textTheme
                                                    .displayMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              const SizedBox(width: 6),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                      bottom: 10,
                                                    ),
                                                child: Text(
                                                  'KG',
                                                  style: Theme.of(dialogContext)
                                                      .textTheme
                                                      .titleLarge
                                                      ?.copyWith(
                                                        color: AppColors
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            insight,
                                            style: Theme.of(dialogContext)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  color: AppColors
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceHighest,
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: badgeStyle.accent.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: badgeStyle.accent.withValues(
                                              alpha: 0.35,
                                            ),
                                            blurRadius: 22,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        badgeStyle.icon,
                                        color: badgeStyle.accent,
                                        size: 44,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (index == 0)
                                Positioned(
                                  top: -10,
                                  right: -4,
                                  child: Transform.rotate(
                                    angle: 0.08,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceBright.withValues(
                                          alpha: 0.9,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppColors.onSurfaceVariant
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Text(
                                        settings.isArabic
                                            ? topTier
                                            : topTier.toUpperCase(),
                                        style: Theme.of(dialogContext)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: AppColors.onSurface,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.0,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF81ECFF), Color(0xFF00DFF8)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () => _copyComparisonSummary(
                              lifts: comparisonLifts,
                              settings: settings,
                            ),
                            icon: const Icon(
                              Icons.share_outlined,
                              color: Color(0xFF004F5D),
                            ),
                            label: Text(
                              settings.tx('SHARE MY STATS', 'شارك نتائجي'),
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFF004F5D),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.4,
                                  ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(
                          settings.tx(
                            'CONTINUE TO DASHBOARD',
                            'العودة إلى الرئيسية',
                          ),
                          style: Theme.of(dialogContext)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                letterSpacing: 2,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sessionNameController.dispose();
    _searchController.dispose();
    _weightController.dispose();
    _repsController.dispose();
    _setsController.dispose();
    _addedWeightController.dispose();
    super.dispose();
  }

  void _selectExercise(String exercise) {
    final settings = context.appSettings;
    setState(() {
      _selectedExercise = exercise;
      _searchController.text = _exerciseLabel(exercise, settings);
      _isBodyweight = bodyweightExercises.contains(exercise);
    });
  }

  List<String> _exerciseSuggestions() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      final counts = <String, int>{};
      for (final session in widget.sessions) {
        for (final lift in session.lifts) {
          counts[lift.name] = (counts[lift.name] ?? 0) + 1;
        }
      }
      final ordered = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return ordered.map((entry) => entry.key).take(8).toList();
    }

    return exerciseCatalog
        .where((exercise) {
          final english = exercise.toLowerCase();
          final arabic = EgyptianGymLexicon.term(exercise).toLowerCase();
          return english.contains(query) || arabic.contains(query);
        })
        .take(10)
        .toList();
  }

  Map<String, double> _personalRecords() {
    final records = <String, double>{};
    for (final session in widget.sessions) {
      for (final lift in session.lifts) {
        final current = records[lift.name];
        if (current == null || lift.weight > current) {
          records[lift.name] = lift.weight;
        }
      }
    }
    return records;
  }

  double _effectiveWeight() {
    final manualWeight = _parseWeight(_weightController.text) ?? 0;
    final addedWeight = _parseWeight(_addedWeightController.text) ?? 0;

    return _isBodyweight ? (_bodyweight + addedWeight) : manualWeight;
  }

  ({double kg, String enLabel, String arLabel}) _nearestEquivalent(double kg) {
    const references = [
      (kg: 20.0, en: 'an Olympic barbell', ar: 'بار أولمبي'),
      (kg: 40.0, en: 'a medium suitcase', ar: 'شنطة سفر متوسطة'),
      (kg: 60.0, en: 'a loaded washing machine drum', ar: 'حلة غسالة مليانة'),
      (kg: 100.0, en: 'an adult giant panda', ar: 'باندا بالغة'),
      (kg: 140.0, en: 'a large sport motorcycle', ar: 'موتوسيكل رياضي كبير'),
      (kg: 190.0, en: 'an adult male lion', ar: 'أسد ذكر بالغ'),
      (kg: 260.0, en: 'a concert piano shell', ar: 'جزء من بيانو حفلات'),
    ];

    var nearest = references.first;
    var smallestGap = (kg - nearest.kg).abs();

    for (final reference in references.skip(1)) {
      final gap = (kg - reference.kg).abs();
      if (gap < smallestGap) {
        nearest = reference;
        smallestGap = gap;
      }
    }

    return (kg: nearest.kg, enLabel: nearest.en, arLabel: nearest.ar);
  }

  String _equivalentNote(double kg, AppSettings settings) {
    final eq = _nearestEquivalent(kg);
    return settings.tx(
      'Equivalent load: about ${eq.enLabel} (~${eq.kg.toStringAsFixed(0)}kg).',
      'يعادل تقريبًا وزن ${eq.arLabel} (~${eq.kg.toStringAsFixed(0)} كجم).',
    );
  }

  String _fallbackInsight({
    required String exercise,
    required double weight,
    required int reps,
    required bool isPr,
    required AppSettings settings,
  }) {
    final exerciseLabel = _exerciseLabel(exercise, settings);
    final ratio = _bodyweight > 0 ? (weight / _bodyweight) : 0;

    if (isPr) {
      return settings.tx(
        'New PR unlocked on $exerciseLabel. Keep this setup for the next peak set.',
        'رقم جديد في $exerciseLabel. نفس القفلة دي هتطلعك أعلى كمان.',
      );
    }

    if (ratio >= 1.6) {
      return settings.tx(
        'Elite strength zone. Add one back-off set to bank more volume.',
        'مستوى نخبوي. زوّد مجموعة باك أوف عشان تثبت القوة.',
      );
    }

    if (ratio >= 1.1) {
      return settings.tx(
        'Strong set. Slow the eccentric and pause to sharpen control.',
        'مجموعة قوية. نزّل الوزن أبطأ ووقف لحظة عشان كنترول أعلى.',
      );
    }

    if (reps >= 12) {
      return settings.tx(
        'Great hypertrophy range. Add 2.5kg next session if form stays clean.',
        'رينج عضلي ممتاز. زوّد 2.5 كجم الجلسة الجاية لو الفورم ثابت.',
      );
    }

    return settings.tx(
      'Solid work. Keep 1-2 reps in reserve and progress steadily.',
      'شغل ثابت. سيب عدّة أو اتنين احتياطي وزوّد تدريجي.',
    );
  }

  Future<void> _generateAiInsight() async {
    if (!_canGenerateInsight || _isAnalyzing) {
      return;
    }

    final settings = context.appSettings;
    final exercise = _resolvedExerciseName!;
    final reps = int.parse(_repsController.text.trim());
    final sets = int.tryParse(_setsController.text.trim()) ?? 1;
    final weight = _effectiveWeight();
    final prs = _personalRecords();
    final isPr = weight > (prs[exercise] ?? 0);

    setState(() {
      _isAnalyzing = true;
      _currentAiInsight = null;
      _error = null;
    });

    try {
      const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
      String? insight;

      if (geminiApiKey.isNotEmpty) {
        final weightLabel = _isBodyweight
            ? '${_bodyweight.toStringAsFixed(1)}kg bodyweight + ${(_parseWeight(_addedWeightController.text) ?? 0).toStringAsFixed(1)}kg'
            : '${weight.toStringAsFixed(1)}kg';

        final prompt =
            '''
Athlete profile: ${widget.profile.age ?? 22} years old, ${_bodyweight.toStringAsFixed(1)}kg bodyweight.
Exercise: $exercise
Load: $weightLabel
Sets: $sets
Reps: $reps
Language: ${settings.isArabic ? 'Egyptian Arabic dialect' : 'English'}

Give one short coaching insight (max 18 words), high-energy and practical.
''';

        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$geminiApiKey',
        );

        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 80},
          }),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            final candidates = decoded['candidates'];
            if (candidates is List && candidates.isNotEmpty) {
              final first = candidates.first;
              if (first is Map<String, dynamic>) {
                final content = first['content'];
                if (content is Map<String, dynamic>) {
                  final parts = content['parts'];
                  if (parts is List && parts.isNotEmpty) {
                    final part = parts.first;
                    if (part is Map<String, dynamic>) {
                      final text = part['text']?.toString().trim();
                      if (text != null && text.isNotEmpty) {
                        insight = text;
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      insight ??= _fallbackInsight(
        exercise: exercise,
        weight: weight,
        reps: reps,
        isPr: isPr,
        settings: settings,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentAiInsight = insight;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _currentAiInsight = _fallbackInsight(
          exercise: exercise,
          weight: weight,
          reps: reps,
          isPr: isPr,
          settings: settings,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  void _addLiftToPending() {
    if (!_canAddLift) {
      return;
    }

    final exercise = _resolvedExerciseName;
    if (exercise == null) {
      return;
    }

    final reps = int.parse(_repsController.text.trim());
    final sets = int.tryParse(_setsController.text.trim()) ?? 1;
    final addedWeight = _parseWeight(_addedWeightController.text) ?? 0;

    final effectiveWeight = _effectiveWeight();
    final prs = _personalRecords();
    final isPr = effectiveWeight > (prs[exercise] ?? 0);
    final strength = StrengthEvaluator.evaluate(
      exerciseName: exercise,
      liftedKg: effectiveWeight,
      bodyweightKg: _bodyweight,
      includeAnimal: true,
    );

    setState(() {
      _pendingLifts.add(
        LiftEntry(
          id: _uuid.v4(),
          name: exercise,
          weight: effectiveWeight,
          reps: reps,
          sets: sets,
          isPr: isPr,
          isBodyweight: _isBodyweight,
          addedWeight: _isBodyweight ? addedWeight : null,
          aiInsight: _currentAiInsight,
          strengthTier: StrengthEvaluator.tierCode(strength.tier),
          strengthRatio: strength.ratio,
          estimatedForceN: strength.forceNewtons,
          animalCode: strength.animalCode,
          splitGroup: _sectionKeyFromExercise(exercise),
        ),
      );
      _searchController.clear();
      _weightController.clear();
      _repsController.clear();
      _setsController.text = '1';
      _addedWeightController.text = '0';
      _selectedExercise = null;
      _isBodyweight = false;
      _currentAiInsight = null;
      _error = null;
    });
  }

  Future<void> _saveSession() async {
    if (_pendingLifts.isEmpty || _saving) {
      return;
    }

    final settings = context.appSettings;

    setState(() {
      _saving = true;
      _error = null;
    });

    var success = false;
    String? resolvedSessionName;

    try {
      if (_selectedSessionId == 'new') {
        final generatedName =
            '${settings.tx('Today Session', 'جلسة النهارده')} ${DateFormat('MMM d').format(DateTime.now())}';
        final sessionName = _sessionNameController.text.trim().isEmpty
            ? generatedName
            : _sessionNameController.text.trim();
        resolvedSessionName = sessionName;
        success = await widget.onCreateSession(sessionName, _pendingLifts);
      } else {
        for (final session in widget.sessions) {
          if (session.id == _selectedSessionId) {
            resolvedSessionName = session.name;
            break;
          }
        }
        success = await widget.onAppendSession(
          _selectedSessionId,
          _pendingLifts,
        );
      }
    } catch (error) {
      success = false;
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    }

    if (!mounted) {
      return;
    }

    if (success) {
      if (_postToFeed) {
        try {
          await _service.createSessionFeedPost(
            userId: widget.userId,
            sessionName:
                resolvedSessionName ??
                settings.tx('Workout Session', 'جلسة تمرين'),
            lifts: _pendingLifts,
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  settings.tx(
                    'Session saved, but feed post failed.',
                    'الجلسة اتحفظت، لكن النشر في الفيد فشل.',
                  ),
                ),
              ),
            );
          }
        }
      }

      await _showSessionPowerPopup();
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    setState(() {
      _error =
          _error ??
          settings.tx(
            'Failed to save session to the database.',
            'حفظ الجلسة في قاعدة البيانات فشل.',
          );
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final errorColor = Theme.of(context).colorScheme.error;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const actionAreaHeight = 88.0;
    final suggestions = _exerciseSuggestions();
    final resolvedExercise = _resolvedExerciseName;
    final completedSections = _completedPlannedSections();
    final showSplitSourceSelector =
      !_loadingTodayPlan && _hasAvailableSplitPlan;
    final showSplitExerciseMenu =
      showSplitSourceSelector &&
      _exerciseSourceMode == _ExerciseSourceMode.split;
    final showManualExerciseFlow =
      !_hasAvailableSplitPlan ||
      _exerciseSourceMode == _ExerciseSourceMode.different;
    final activeStep = _pendingLifts.isNotEmpty
        ? 4
        : resolvedExercise != null
        ? 3
        : (showSplitSourceSelector && _exerciseSourceMode != null)
        ? 2
        : 1;
    final flowSteps = <String>[
      settings.tx('Session', 'الجلسة'),
      settings.tx('Source', 'المصدر'),
      settings.tx('Exercise', 'التمرين'),
      settings.tx('Complete', 'إنهاء'),
    ];

    return FractionallySizedBox(
      heightFactor: 0.93,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.2)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF090C10), Color(0xFF050608)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 56,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.tx('Record Training', 'سجل الجلسة'),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          Text(
                            settings.tx(
                              '${_pendingLifts.length} lifts pending',
                              '${_pendingLifts.length} رفعة جاهزين',
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: onSurfaceVariant,
                                  letterSpacing: 2.2,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 34),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: errorColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: errorColor.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: errorColor),
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    16 + actionAreaHeight + bottomInset,
                  ),
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.26),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.outline.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < flowSteps.length; i++) ...[
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: activeStep >= (i + 1)
                                          ? primary
                                          : AppColors.surfaceHighest,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: activeStep >= (i + 1)
                                            ? primary
                                            : AppColors.outline.withValues(
                                                alpha: 0.45,
                                              ),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${i + 1}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: activeStep >= (i + 1)
                                                  ? Colors.black
                                                  : onSurfaceVariant,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      flowSteps[i],
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: activeStep >= (i + 1)
                                                ? primary
                                                : onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (i < flowSteps.length - 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Icon(
                                  Icons.chevron_right,
                                  color: onSurfaceVariant,
                                  size: 18,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    if (_todaySessions.isNotEmpty) ...[
                      Text(
                        settings.tx('Session Target', 'هتسجل فين؟'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(
                              settings.tx('New Session', 'جلسة جديدة'),
                            ),
                            selected: _selectedSessionId == 'new',
                            onSelected: (_) {
                              setState(() {
                                _selectedSessionId = 'new';
                              });
                            },
                          ),
                          ..._todaySessions.map(
                            (session) => ChoiceChip(
                              label: Text(session.name),
                              selected: _selectedSessionId == session.id,
                              onSelected: (_) {
                                setState(() {
                                  _selectedSessionId = session.id;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_selectedSessionId == 'new') ...[
                      Text(
                        settings.tx('SESSION NAME', 'اسم الجلسة'),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          letterSpacing: 2.0,
                          color: onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _sessionNameController,
                        decoration: InputDecoration(
                          hintText: settings.tx(
                            'e.g. Heavy Chest & Back',
                            'مثال: صدر وظهر تقيل',
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (showSplitSourceSelector) ...[
                      Text(
                        settings.tx(
                          'SOURCE',
                          'المصدر',
                        ),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.outline.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        _exerciseSourceMode ==
                                            _ExerciseSourceMode.split
                                        ? AppColors.surfaceHighest
                                        : Colors.transparent,
                                    foregroundColor:
                                        _exerciseSourceMode ==
                                            _ExerciseSourceMode.split
                                        ? primary
                                        : onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _exerciseSourceMode =
                                          _ExerciseSourceMode.split;
                                      _selectedExercise = null;
                                      _searchController.clear();
                                    });
                                  },
                                  child: Text(
                                    settings.tx(
                                      'From My Split',
                                      'من السبليت',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        _exerciseSourceMode ==
                                            _ExerciseSourceMode.different
                                        ? AppColors.surfaceHighest
                                        : Colors.transparent,
                                    foregroundColor:
                                        _exerciseSourceMode ==
                                            _ExerciseSourceMode.different
                                        ? onSurface
                                        : onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _exerciseSourceMode =
                                          _ExerciseSourceMode.different;
                                    });
                                  },
                                  child: Text(
                                    settings.tx(
                                      'Different Exercise',
                                      'تمرين مختلف',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_loadingTodayPlan)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              settings.tx(
                                'Loading today split options...',
                                'بنحمّل اختيارات تمرين النهارده...',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      )
                    else if (_todaySplitEntry != null && showSplitExerciseMenu) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    settings.tx(
                                      'Today split options',
                                      'اختيارات سبليت النهارده',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.4,
                                        ),
                                  ),
                                ),
                                Text(
                                  settings.tx(
                                    '${_todaySplitEntry!.exercises.length} exercises total',
                                    '${_todaySplitEntry!.exercises.length} تمارين',
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: onSurfaceVariant,
                                        letterSpacing: 1.4,
                                      ),
                                ),
                              ],
                            ),
                            Divider(
                              height: 20,
                              color: AppColors.outline.withValues(alpha: 0.2),
                            ),
                            ..._todaySplitEntry!.exercises.map((planned) {
                              final sectionKey = _sectionKeyFromExercise(
                                planned.name,
                              );
                              final completed = completedSections.contains(
                                sectionKey,
                              );
                              final alternatives = _aiAlternativesFor(planned);
                              final equipment = _exerciseEquipmentTag(
                                planned.name,
                                settings,
                              );
                              final pattern = _exercisePatternTag(
                                planned.name,
                                settings,
                              );
                              final metaLine = settings.isArabic
                                  ? '$equipment • $pattern'
                                  : '${equipment.toUpperCase()} • ${pattern.toUpperCase()}';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 18),
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                decoration: BoxDecoration(
                                  color: completed
                                      ? primary.withValues(alpha: 0.12)
                                      : AppColors.surfaceHigh.withValues(
                                          alpha: 0.92,
                                        ),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: completed
                                        ? primary.withValues(alpha: 0.55)
                                        : AppColors.outline.withValues(
                                            alpha: 0.22,
                                          ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _exerciseLabel(
                                                  planned.name,
                                                  settings,
                                                ),
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.headlineMedium?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: -0.45,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                metaLine,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                      color: onSurfaceVariant,
                                                      letterSpacing: 1.8,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceHighest,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: primary.withValues(
                                                alpha: 0.72,
                                              ),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                '${planned.sets} x ${planned.reps}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              Text(
                                                settings.tx(
                                                  'TARGET REP RANGE',
                                                  'رينج التكرار',
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      color: onSurfaceVariant,
                                                      letterSpacing: 1.2,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primaryContainer,
                                          foregroundColor: const Color(0xFF004F5D),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 17,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        onPressed: () => _applyPlannedExercise(
                                          planned,
                                          openQuickEntry: true,
                                        ),
                                        child: Text(
                                          settings.tx(
                                            'USE MAIN',
                                            'استخدم الأساسي',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: const Color(0xFF004F5D),
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      settings.tx(
                                        'AI ALTERNATIVES',
                                        'بدائل ذكية',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: onSurfaceVariant,
                                            letterSpacing: 1.5,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        ...alternatives.map(
                                          (alt) => OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.surfaceHighest,
                                              side: BorderSide(
                                                color: AppColors.outline
                                                    .withValues(alpha: 0.35),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 10,
                                                  ),
                                            ),
                                            onPressed: () =>
                                                _applyPlannedExercise(
                                                  planned,
                                                  selectedName: alt,
                                                  openQuickEntry: true,
                                                ),
                                            icon: Icon(
                                              Icons.bolt_rounded,
                                              size: 15,
                                              color: onSurfaceVariant,
                                            ),
                                            label: Text(
                                              _exerciseLabel(alt, settings),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                    if (showSplitSourceSelector &&
                        _exerciseSourceMode == null &&
                        !showSplitExerciseMenu)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          settings.tx(
                            'Choose split or different first to continue.',
                            'اختار الأول من السبليت أو تمرين مختلف علشان تكمل.',
                          ),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: primary),
                        ),
                      ),
                    if (_pendingLifts.isNotEmpty) ...[
                      Text(
                        settings.tx(
                          'Step 3 • Current Lifts',
                          'الخطوة ٣ • الرفعات الحالية',
                        ),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      ..._pendingLifts.map(
                        (lift) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: primary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _exerciseLabel(lift.name, settings),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    Text(
                                      '${lift.sets} ${settings.tx('sets', 'جملة')} • ${lift.weight.toStringAsFixed(1)}kg x ${lift.reps}${lift.isBodyweight ? settings.tx(' (bodyweight)', ' (وزن جسم)') : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: primary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      StrengthEvaluator.strengthLine(
                                        tierCode: lift.strengthTier,
                                        ratio: lift.strengthRatio,
                                        isArabic: settings.isArabic,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(fontSize: 10),
                                    ),
                                    if (settings.showAnimalComparison &&
                                        StrengthEvaluator.animalLine(
                                              animalCode: lift.animalCode,
                                              forceNewtons:
                                                  lift.estimatedForceN,
                                              isArabic: settings.isArabic,
                                            ) !=
                                            null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          StrengthEvaluator.animalLine(
                                            animalCode: lift.animalCode,
                                            forceNewtons: lift.estimatedForceN,
                                            isArabic: settings.isArabic,
                                          )!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(fontSize: 10),
                                        ),
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _equivalentNote(lift.weight, settings),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(fontSize: 10),
                                    ),
                                    if (lift.aiInsight != null &&
                                        lift.aiInsight!.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '${settings.tx('AI', 'الذكاء الاصطناعي')}: ${lift.aiInsight!}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: primary,
                                                fontSize: 10,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _pendingLifts.removeWhere(
                                      (item) => item.id == lift.id,
                                    );
                                  });
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (showManualExerciseFlow) ...[
                      Text(
                        settings.tx(
                          'Step 1 • Choose Exercise',
                          'الخطوة ١ • اختار التمرين',
                        ),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: settings.tx(
                            'Exercise name',
                            'اسم التمرين',
                          ),
                        ),
                        onChanged: (_) {
                          if (_selectedExercise != null) {
                            setState(() {
                              _selectedExercise = null;
                            });
                          } else {
                            setState(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 6),
                      if (_resolvedExerciseName != null &&
                          _selectedExercise == null &&
                          _searchController.text.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            settings.tx(
                              'Using custom exercise: ${_searchController.text.trim()}',
                              'هسجل تمرين جديد: ${_searchController.text.trim()}',
                            ),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: primary),
                          ),
                        ),
                      if (suggestions.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: suggestions
                                .map(
                                  (exercise) => ActionChip(
                                    backgroundColor: AppColors.surfaceHighest,
                                    side: const BorderSide(
                                      color: AppColors.outline,
                                    ),
                                    label: Text(
                                      _exerciseLabel(exercise, settings),
                                    ),
                                    onPressed: () => _selectExercise(exercise),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (resolvedExercise != null &&
                          bodyweightExercises.contains(resolvedExercise))
                        SwitchListTile.adaptive(
                          value: _isBodyweight,
                          title: Text(
                            settings.tx(
                              'Use bodyweight (${_bodyweight.toStringAsFixed(1)}kg)',
                              'استخدم وزن الجسم (${_bodyweight.toStringAsFixed(1)} كجم)',
                            ),
                          ),
                          onChanged: (enabled) {
                            setState(() {
                              _isBodyweight = enabled;
                            });
                          },
                        ),
                      const SizedBox(height: 6),
                      Text(
                        settings.tx(
                          'Step 2 • Enter Numbers',
                          'الخطوة ٢ • اكتب الأرقام',
                        ),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _isBodyweight
                                  ? _addedWeightController
                                  : _weightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: InputDecoration(
                                labelText: _isBodyweight
                                    ? settings.tx(
                                        'Added Weight (kg)',
                                        'وزن إضافي (كجم)',
                                      )
                                    : settings.tx('Weight (kg)', 'الوزن (كجم)'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _repsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: settings.tx('Reps', 'العدات'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 92,
                            child: TextField(
                              controller: _setsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                labelText: settings.tx('Sets', 'الجمل'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _searchController,
                          _weightController,
                          _repsController,
                          _setsController,
                          _addedWeightController,
                        ]),
                        builder: (context, _) {
                          final canGenerateInsight = _canGenerateInsight;
                          final canAddLift = _canAddLift;
                          final currentWeight = _effectiveWeight();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (canGenerateInsight)
                                Text(
                                  _equivalentNote(currentWeight, settings),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: canGenerateInsight
                                    ? _generateAiInsight
                                    : null,
                                icon: _isAnalyzing
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: primary,
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome),
                                label: Text(
                                  settings.tx(
                                    'AI Insight',
                                    'رأي الذكاء الاصطناعي',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                onPressed: canAddLift ? _addLiftToPending : null,
                                icon: const Icon(Icons.add),
                                label: Text(
                                  settings.tx(
                                    'ADD LIFT TO SESSION',
                                    'ضيف الرفعة للجلسة',
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      if (_currentAiInsight != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            _currentAiInsight!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      value: _postToFeed,
                      onChanged: (enabled) {
                        setState(() {
                          _postToFeed = enabled;
                        });
                      },
                      title: Text(
                        settings.tx(
                          'Post this session to feed',
                          'انشر الجلسة دي في الفيد',
                        ),
                      ),
                      subtitle: Text(
                        settings.tx(
                          'You can keep it private by turning this off.',
                          'تقدر تخليها خاصة لو قفلت الاختيار.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 16,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color: AppColors.surfaceHighest,
                          ),
                          child: Center(
                            child: Container(
                              width: 26,
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                color: primary,
                                boxShadow: [
                                  BoxShadow(
                                    color: primary.withValues(alpha: 0.6),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          settings.tx('READY TO SYNC', 'جاهز للمزامنة'),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: onSurfaceVariant,
                                letterSpacing: 2.2,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceHigh,
                          foregroundColor: onSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: AppColors.outline.withValues(alpha: 0.35),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onPressed: _pendingLifts.isEmpty || _saving
                            ? null
                            : _saveSession,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onSurface,
                                ),
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      settings.tx(
                                        'COMPLETE SESSION (${_pendingLifts.length})',
                                        'خلص الجلسة (${_pendingLifts.length})',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2,
                                          ),
                                    ),
                                  ),
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: Color(0xFF004F5D),
                                      size: 30,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
