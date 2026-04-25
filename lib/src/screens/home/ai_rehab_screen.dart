import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../data/splits_catalog.dart';
import '../../models/app_user.dart';
import '../../models/gym_split.dart';
import '../../models/training_session.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';

enum _MovementKey { bench, pull, legPress, overhead }

enum _BodyZone { shoulders, torso, legs }

class _LiftSnapshot {
  const _LiftSnapshot({
    required this.weight,
    required this.reps,
    required this.source,
  });

  final double weight;
  final int reps;
  final String source;

  double get estimated1Rm => weight * (1 + (reps / 30));
}

class _ImbalanceReport {
  const _ImbalanceReport({
    required this.pushPullRatio,
    required this.lowerUpperRatio,
    required this.overheadBenchRatio,
    required this.weaknesses,
    required this.zones,
    required this.status,
    required this.coachTip,
  });

  final double pushPullRatio;
  final double lowerUpperRatio;
  final double overheadBenchRatio;
  final List<String> weaknesses;
  final Set<_BodyZone> zones;
  final String status;
  final String coachTip;
}

class _RehabExerciseRecommendation {
  const _RehabExerciseRecommendation({
    required this.exercise,
    required this.reason,
  });

  final ExerciseEntry exercise;
  final String reason;
}

class AIRehabScreen extends StatefulWidget {
  const AIRehabScreen({
    required this.profile,
    required this.sessions,
    super.key,
  });

  final AppUser profile;
  final List<TrainingSession> sessions;

  @override
  State<AIRehabScreen> createState() => _AIRehabScreenState();
}

class _AIRehabScreenState extends State<AIRehabScreen> {
  final _service = SupabaseService.instance;
  late final Map<_MovementKey, _LiftSnapshot> _historyMaxes;
  late final Map<String, ExerciseEntry> _exerciseLibrary;

  final Map<_MovementKey, TextEditingController> _manualWeight =
      <_MovementKey, TextEditingController>{};
  final Map<_MovementKey, TextEditingController> _manualReps =
      <_MovementKey, TextEditingController>{};
  final _painAreaController = TextEditingController();
  final _symptomDurationController = TextEditingController();
  final _analysisGoalController = TextEditingController();
  final _analysisNotesController = TextEditingController();

  double _painLevel = 4;
  bool _detailsConfirmed = false;

  Map<_MovementKey, _LiftSnapshot> _storedMetrics =
      <_MovementKey, _LiftSnapshot>{};

  bool _loadingStoredMetrics = true;
  bool _savingMissingMetrics = false;
  bool _analyzing = false;

  String? _error;
  String? _aiCoachLine;
  _ImbalanceReport? _report;
  List<_RehabExerciseRecommendation> _recommendations =
      <_RehabExerciseRecommendation>[];

  static const List<_MovementKey> _requiredMetrics = <_MovementKey>[
    _MovementKey.bench,
    _MovementKey.pull,
    _MovementKey.legPress,
    _MovementKey.overhead,
  ];

  @override
  void initState() {
    super.initState();
    _historyMaxes = _extractHistoryMaxes(widget.sessions);
    _exerciseLibrary = _buildExerciseLibrary();

    for (final key in _requiredMetrics) {
      _manualWeight[key] = TextEditingController();
      _manualReps[key] = TextEditingController(text: '5');
    }

    _loadStoredMetrics();
  }

  @override
  void dispose() {
    for (final controller in _manualWeight.values) {
      controller.dispose();
    }
    for (final controller in _manualReps.values) {
      controller.dispose();
    }
    _painAreaController.dispose();
    _symptomDurationController.dispose();
    _analysisGoalController.dispose();
    _analysisNotesController.dispose();
    super.dispose();
  }

  String _normalizeExerciseKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _movementStorageKey(_MovementKey key) {
    return switch (key) {
      _MovementKey.bench => 'bench',
      _MovementKey.pull => 'pull',
      _MovementKey.legPress => 'leg_press',
      _MovementKey.overhead => 'overhead',
    };
  }

  Map<String, ExerciseEntry> _buildExerciseLibrary() {
    final library = <String, ExerciseEntry>{};
    for (final splitList in splitsCatalog.values) {
      for (final split in splitList) {
        for (final day in split.days) {
          for (final exercise in day.exercises) {
            final key = _normalizeExerciseKey(exercise.name);
            if (key.isNotEmpty) {
              library.putIfAbsent(key, () => exercise);
            }
            for (final variation in exercise.variations) {
              final variationKey = _normalizeExerciseKey(variation);
              if (variationKey.isNotEmpty) {
                library.putIfAbsent(variationKey, () => exercise);
              }
            }
          }
        }
      }
    }
    return library;
  }

  Future<void> _loadStoredMetrics() async {
    setState(() {
      _loadingStoredMetrics = true;
      _error = null;
    });

    try {
      final raw = await _service.fetchRehabMetrics(widget.profile.id);
      if (!mounted) {
        return;
      }

      setState(() {
        _storedMetrics = _parseStoredMetrics(raw);
        _hydrateAnalysisIntake(raw);
        _loadingStoredMetrics = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingStoredMetrics = false;
        _error = context.appSettings.tx(
          'Could not load stored rehab inputs. You can still enter them now.',
          'مقدرناش نحمّل مدخلات التأهيل المحفوظة، تقدر تدخلها دلوقتي.',
        );
      });
    }
  }

  Map<_MovementKey, _LiftSnapshot> _parseStoredMetrics(
    Map<String, dynamic> raw,
  ) {
    final output = <_MovementKey, _LiftSnapshot>{};
    for (final key in _requiredMetrics) {
      final storageKey = _movementStorageKey(key);
      final candidate = raw[storageKey];
      if (candidate is! Map) {
        continue;
      }

      final metric = Map<String, dynamic>.from(candidate);
      final weight = _asDouble(metric['weight']);
      final reps = _asInt(metric['reps']);
      if (weight == null || reps == null || weight <= 0 || reps < 1) {
        continue;
      }

      output[key] = _LiftSnapshot(weight: weight, reps: reps, source: 'stored');
    }
    return output;
  }

  Map<String, dynamic> _serializeStoredMetrics(
    Map<_MovementKey, _LiftSnapshot> metrics,
  ) {
    final payload = <String, dynamic>{};
    final now = DateTime.now().toIso8601String();

    for (final key in _requiredMetrics) {
      final snapshot = metrics[key];
      if (snapshot == null) {
        continue;
      }

      payload[_movementStorageKey(key)] = {
        'weight': double.parse(snapshot.weight.toStringAsFixed(2)),
        'reps': snapshot.reps,
        'source': snapshot.source,
        'updated_at': now,
      };
    }

    return payload;
  }

  void _hydrateAnalysisIntake(Map<String, dynamic> raw) {
    final intakeRaw = raw['analysis_intake'];
    if (intakeRaw is! Map) {
      return;
    }

    final intake = Map<String, dynamic>.from(intakeRaw);
    final painArea = (intake['pain_area'] ?? '').toString().trim();
    final duration = (intake['symptom_duration'] ?? '').toString().trim();
    final goal = (intake['analysis_goal'] ?? '').toString().trim();
    final notes = (intake['notes'] ?? '').toString().trim();
    final level = _asDouble(intake['pain_level']);

    _painAreaController.text = painArea;
    _symptomDurationController.text = duration;
    _analysisGoalController.text = goal;
    _analysisNotesController.text = notes;
    _painLevel = (level == null || level.isNaN)
        ? _painLevel
        : level.clamp(0, 10).toDouble();
    _detailsConfirmed =
        painArea.isNotEmpty && duration.isNotEmpty && goal.isNotEmpty;
  }

  bool get _hasRequiredIntakeDetails {
    return _painAreaController.text.trim().isNotEmpty &&
        _symptomDurationController.text.trim().isNotEmpty &&
        _analysisGoalController.text.trim().isNotEmpty;
  }

  Map<String, dynamic> _intakePayload() {
    return {
      'pain_area': _painAreaController.text.trim(),
      'pain_level': double.parse(_painLevel.toStringAsFixed(1)),
      'symptom_duration': _symptomDurationController.text.trim(),
      'analysis_goal': _analysisGoalController.text.trim(),
      'notes': _analysisNotesController.text.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _saveIntakeDetails() async {
    final settings = context.appSettings;
    if (_loadingStoredMetrics || _savingMissingMetrics || _analyzing) {
      return;
    }

    if (!_hasRequiredIntakeDetails) {
      setState(() {
        _detailsConfirmed = false;
        _error = settings.tx(
          'Please add pain area, symptom duration, and rehab goal before analysis.',
          'من فضلك ادخل منطقة الألم، مدة الأعراض، وهدف التأهيل قبل التحليل.',
        );
      });
      return;
    }

    setState(() {
      _error = null;
    });

    try {
      await _service.upsertRehabMetrics(
        userId: widget.profile.id,
        metrics: {'analysis_intake': _intakePayload()},
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _detailsConfirmed = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _detailsConfirmed = false;
        _error = settings.tx(
          'Could not save rehab intake details. Please try again.',
          'مقدرناش نحفظ تفاصيل التأهيل. حاول مرة تانية.',
        );
      });
    }
  }

  int? _asInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value.toString());
  }

  double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  Map<_MovementKey, _LiftSnapshot> _extractHistoryMaxes(
    List<TrainingSession> sessions,
  ) {
    final best = <_MovementKey, _LiftSnapshot>{};
    for (final session in sessions) {
      for (final lift in session.lifts) {
        final key = _movementForExercise(lift.name);
        if (key == null) {
          continue;
        }

        final candidate = _LiftSnapshot(
          weight: lift.weight,
          reps: math.max(1, lift.reps),
          source: 'history',
        );
        final current = best[key];
        if (current == null || candidate.estimated1Rm > current.estimated1Rm) {
          best[key] = candidate;
        }
      }
    }
    return best;
  }

  _MovementKey? _movementForExercise(String raw) {
    final name = _normalizeExerciseKey(raw);
    if (name.contains('bench')) {
      return _MovementKey.bench;
    }
    if (name.contains('row') ||
        name.contains('pulldown') ||
        name.contains('pull up') ||
        name.contains('pullup') ||
        name.contains('chin up') ||
        name.contains('chinup')) {
      return _MovementKey.pull;
    }
    if (name.contains('leg press') ||
        name.contains('squat') ||
        name.contains('lunge')) {
      return _MovementKey.legPress;
    }
    if (name.contains('overhead') || name.contains('shoulder press')) {
      return _MovementKey.overhead;
    }
    return null;
  }

  String _movementLabel(_MovementKey key, AppSettings settings) {
    return switch (key) {
      _MovementKey.bench => settings.tx('Bench Press', 'البنش برس'),
      _MovementKey.pull => settings.tx('Pull Strength', 'قوة السحب'),
      _MovementKey.legPress => settings.tx(
        'Leg Press / Squat',
        'الليج برس / السكوات',
      ),
      _MovementKey.overhead => settings.tx('Overhead Press', 'الأوفرهيد برس'),
    };
  }

  _LiftSnapshot? _manualSnapshot(_MovementKey key) {
    final weight = double.tryParse(_manualWeight[key]!.text.trim());
    final reps = int.tryParse(_manualReps[key]!.text.trim());
    if (weight == null || reps == null || weight <= 0 || reps < 1) {
      return null;
    }

    return _LiftSnapshot(weight: weight, reps: reps, source: 'manual');
  }

  Map<_MovementKey, _LiftSnapshot> _analysisSnapshots() {
    final merged = <_MovementKey, _LiftSnapshot>{..._historyMaxes};
    for (final entry in _storedMetrics.entries) {
      final current = merged[entry.key];
      if (current == null || entry.value.estimated1Rm > current.estimated1Rm) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  List<_MovementKey> _missingMetrics(Map<_MovementKey, _LiftSnapshot> merged) {
    return _requiredMetrics.where((key) => merged[key] == null).toList();
  }

  _ImbalanceReport _buildReport(
    Map<_MovementKey, _LiftSnapshot> merged,
    AppSettings settings,
  ) {
    final bench = merged[_MovementKey.bench]!.estimated1Rm;
    final pull = merged[_MovementKey.pull]!.estimated1Rm;
    final legPress = merged[_MovementKey.legPress]!.estimated1Rm;
    final overhead = merged[_MovementKey.overhead]!.estimated1Rm;

    final pushPullRatio = pull <= 0 ? 1.0 : bench / pull;
    final upperAvg = (bench + pull) / 2;
    final lowerUpperRatio = upperAvg <= 0 ? 1.0 : legPress / upperAvg;
    final overheadBenchRatio = bench <= 0 ? 1.0 : overhead / bench;

    final weaknesses = <String>[];
    final zones = <_BodyZone>{};

    if (pushPullRatio > 1.15) {
      weaknesses.add(
        settings.tx(
          'Upper back is lagging behind pressing strength.',
          'الظهر العلوي أقل من قوة الدفع عندك.',
        ),
      );
      zones.add(_BodyZone.torso);
    } else if (pushPullRatio < 0.85) {
      weaknesses.add(
        settings.tx(
          'Pressing chain is lagging behind pulling strength.',
          'سلسلة الدفع أقل من قوة السحب.',
        ),
      );
      zones.add(_BodyZone.torso);
    }

    if (lowerUpperRatio < 1.20) {
      weaknesses.add(
        settings.tx(
          'Lower body output is below upper-body benchmark.',
          'قوة الجزء السفلي أقل من معيار الجزء العلوي.',
        ),
      );
      zones.add(_BodyZone.legs);
    }

    if (overheadBenchRatio < 0.55) {
      weaknesses.add(
        settings.tx(
          'Shoulder pressing endurance looks underdeveloped.',
          'تحمل ضغط الكتف محتاج شغل أكتر.',
        ),
      );
      zones.add(_BodyZone.shoulders);
    }

    if (weaknesses.isEmpty) {
      weaknesses.add(
        settings.tx(
          'No critical imbalance detected from your current data.',
          'مفيش خلل حرج ظاهر من بياناتك الحالية.',
        ),
      );
    }

    final status = weaknesses.length > 2
        ? settings.tx('High imbalance', 'اختلال عالي')
        : weaknesses.length == 1 &&
              weaknesses.first.contains(
                settings.isArabic ? 'مفيش خلل' : 'No critical imbalance',
              )
        ? settings.tx('Balanced', 'متوازن')
        : settings.tx('Manageable imbalance', 'اختلال قابل للتعديل');

    final coachTip =
        weaknesses.first.contains('back') || weaknesses.first.contains('الظهر')
        ? settings.tx(
            'Run two pull-focused sessions this week and keep pressing volume stable.',
            'اعمل حصتين سحب الأسبوع ده وخلي حجم الدفع ثابت.',
          )
        : weaknesses.first.contains('Lower body') ||
              weaknesses.first.contains('الجزء السفلي')
        ? settings.tx(
            'Add heavy leg press and squat accessory volume for three weeks.',
            'زوّد الليج برس الثقيل مع حجم سكوات إضافي لمدة 3 أسابيع.',
          )
        : weaknesses.first.contains('Shoulder') ||
              weaknesses.first.contains('الكتف')
        ? settings.tx(
            'Use controlled overhead work plus face pulls at the end of each upper session.',
            'اشتغل أوفرهيد كنترول مع فيس بولز في نهاية كل تمرين علوي.',
          )
        : settings.tx(
            'Stay balanced and reassess after two weeks of consistent logging.',
            'استمر على التوازن وأعد التقييم بعد أسبوعين تسجيل منتظم.',
          );

    return _ImbalanceReport(
      pushPullRatio: pushPullRatio,
      lowerUpperRatio: lowerUpperRatio,
      overheadBenchRatio: overheadBenchRatio,
      weaknesses: weaknesses,
      zones: zones,
      status: status,
      coachTip: coachTip,
    );
  }

  ExerciseEntry? _findLibraryExercise(String candidateName) {
    final normalized = _normalizeExerciseKey(candidateName);
    if (normalized.isEmpty) {
      return null;
    }

    final exact = _exerciseLibrary[normalized];
    if (exact != null) {
      return exact;
    }

    for (final entry in _exerciseLibrary.entries) {
      if (entry.key.contains(normalized) || normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  List<_RehabExerciseRecommendation> _buildRecommendations(
    _ImbalanceReport report,
    AppSettings settings,
  ) {
    final output = <_RehabExerciseRecommendation>[];
    final seenNames = <String>{};

    void addExercise(String name, String reason) {
      final exercise = _findLibraryExercise(name);
      if (exercise == null || exercise.playbackUrl == null) {
        return;
      }
      if (!seenNames.add(exercise.name)) {
        return;
      }
      output.add(
        _RehabExerciseRecommendation(exercise: exercise, reason: reason),
      );
    }

    if (report.pushPullRatio > 1.15) {
      final reason = settings.tx(
        'Boost upper-back output to close the push/pull gap.',
        'زوّد إنتاج الظهر العلوي لتقفل فجوة الدفع/السحب.',
      );
      addExercise('Barbell Row', reason);
      addExercise('Lat Pulldown', reason);
      addExercise('Face Pulls', reason);
    } else if (report.pushPullRatio < 0.85) {
      final reason = settings.tx(
        'Raise pressing strength so pushing catches up with pulling.',
        'ارفع قوة الدفع عشان تلحق قوة السحب.',
      );
      addExercise('Bench Press (Barbell)', reason);
      addExercise('Incline Bench Press', reason);
      addExercise('Triceps Pushdown', reason);
    }

    if (report.lowerUpperRatio < 1.20) {
      final reason = settings.tx(
        'Prioritize lower-body force production and unilateral control.',
        'ركّز على إنتاج القوة في الجزء السفلي والتحكم الأحادي.',
      );
      addExercise('Leg Press', reason);
      addExercise('Barbell Squat', reason);
      addExercise('Walking Lunges', reason);
    }

    if (report.overheadBenchRatio < 0.55) {
      final reason = settings.tx(
        'Build shoulder pressing endurance and scapular stability.',
        'ابني تحمّل ضغط الكتف وثبات لوح الكتف.',
      );
      addExercise('Overhead Press (Barbell)', reason);
      addExercise('Lateral Raises', reason);
      addExercise('Face Pulls', reason);
    }

    if (output.isEmpty) {
      final reason = settings.tx(
        'Balanced status: rotate these to maintain symmetry.',
        'حالة متوازنة: دوّر التمارين دي للحفاظ على التناسق.',
      );
      addExercise('Bench Press (Barbell)', reason);
      addExercise('Barbell Row', reason);
      addExercise('Romanian Deadlift', reason);
    }

    return output.take(5).toList();
  }

  Future<void> _openExerciseVideo(
    _RehabExerciseRecommendation recommendation,
    AppSettings settings,
  ) async {
    final url = recommendation.exercise.playbackUrl;
    if (url == null) {
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            settings.tx(
              'Could not open the video right now.',
              'مقدرناش نفتح الفيديو دلوقتي.',
            ),
          ),
        ),
      );
    }
  }

  Future<String?> _buildAiCoachLine(
    _ImbalanceReport report,
    Map<_MovementKey, _LiftSnapshot> merged,
    AppSettings settings,
  ) async {
    const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (geminiApiKey.isEmpty) {
      return null;
    }

    final prompt =
        '''
Athlete gender: ${widget.profile.gender.name}
Bench 1RM estimate: ${merged[_MovementKey.bench]!.estimated1Rm.toStringAsFixed(1)} kg
Pull 1RM estimate: ${merged[_MovementKey.pull]!.estimated1Rm.toStringAsFixed(1)} kg
Leg 1RM estimate: ${merged[_MovementKey.legPress]!.estimated1Rm.toStringAsFixed(1)} kg
Overhead 1RM estimate: ${merged[_MovementKey.overhead]!.estimated1Rm.toStringAsFixed(1)} kg
Push/Pull ratio: ${report.pushPullRatio.toStringAsFixed(2)}
Lower/Upper ratio: ${report.lowerUpperRatio.toStringAsFixed(2)}
Overhead/Bench ratio: ${report.overheadBenchRatio.toStringAsFixed(2)}

Give one short rehab coach line (max 22 words), practical and motivating.
Language: ${settings.isArabic ? 'Egyptian Arabic' : 'English'}.
''';

    try {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$geminiApiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 80},
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        return null;
      }

      final first = candidates.first;
      if (first is! Map<String, dynamic>) {
        return null;
      }

      final content = first['content'];
      if (content is! Map<String, dynamic>) {
        return null;
      }

      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) {
        return null;
      }

      final firstPart = parts.first;
      if (firstPart is! Map<String, dynamic>) {
        return null;
      }

      final text = firstPart['text']?.toString().trim();
      if (text == null || text.isEmpty) {
        return null;
      }

      return text;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveMissingMetrics() async {
    final settings = context.appSettings;
    final merged = _analysisSnapshots();
    final missing = _missingMetrics(merged);

    if (missing.isEmpty || _savingMissingMetrics) {
      return;
    }

    for (final key in missing) {
      final manual = _manualSnapshot(key);
      if (manual == null) {
        setState(() {
          _error = settings.tx(
            'Please enter valid kg + reps for ${_movementLabel(key, settings)}.',
            'من فضلك ادخل وزن + عدات صحيحة لـ ${_movementLabel(key, settings)}.',
          );
        });
        return;
      }
    }

    setState(() {
      _savingMissingMetrics = true;
      _error = null;
    });

    try {
      final updatedStored = <_MovementKey, _LiftSnapshot>{..._storedMetrics};
      for (final key in missing) {
        updatedStored[key] = _manualSnapshot(key)!;
      }

      await _service.upsertRehabMetrics(
        userId: widget.profile.id,
        metrics: _serializeStoredMetrics(updatedStored),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _storedMetrics = updatedStored;
        _savingMissingMetrics = false;
      });

      await _runAnalysis();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savingMissingMetrics = false;
        _error = settings.tx(
          'Failed to save missing metrics. Please try again.',
          'فشل حفظ البيانات الناقصة، حاول تاني.',
        );
      });
    }
  }

  Future<void> _runAnalysis() async {
    final settings = context.appSettings;
    if (_loadingStoredMetrics || _savingMissingMetrics || _analyzing) {
      return;
    }

    final merged = _analysisSnapshots();
    final missing = _missingMetrics(merged);

    if (missing.isNotEmpty) {
      setState(() {
        _error = settings.tx(
          'Save the missing movement metrics first to start analysis.',
          'احفظ بيانات الحركات الناقصة الأول عشان نبدأ التحليل.',
        );
      });
      return;
    }

    if (!_hasRequiredIntakeDetails || !_detailsConfirmed) {
      setState(() {
        _error = settings.tx(
          'Please complete and save rehab intake details before running analysis.',
          'كمّل واحفظ تفاصيل التأهيل الأول قبل تشغيل التحليل.',
        );
      });
      return;
    }

    setState(() {
      _analyzing = true;
      _error = null;
      _aiCoachLine = null;
    });

    final report = _buildReport(merged, settings);
    final coachLine = await _buildAiCoachLine(report, merged, settings);
    final recommendations = _buildRecommendations(report, settings);

    if (!mounted) {
      return;
    }

    setState(() {
      _report = report;
      _aiCoachLine = coachLine;
      _recommendations = recommendations;
      _analyzing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    final danger = Theme.of(context).colorScheme.error;

    final merged = _analysisSnapshots();
    final missing = _missingMetrics(merged);
    final bench1Rm = merged[_MovementKey.bench]?.estimated1Rm ?? 0;
    final pull1Rm = merged[_MovementKey.pull]?.estimated1Rm ?? 0;
    final pushPullRatio = pull1Rm > 0 ? bench1Rm / pull1Rm : 1.0;
    final ratioLine = _report != null
        ? '${_report!.pushPullRatio.toStringAsFixed(2)} : 1.0'
        : '${pushPullRatio.toStringAsFixed(2)} : 1.0';
    final statusText =
        _report?.status ?? settings.tx('Awaiting analysis', 'بانتظار التحليل');

    Widget ratioBar({
      required String label,
      required double value,
      required Color color,
    }) {
      final normalized = (value / 180).clamp(0.08, 1.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                '${value.toStringAsFixed(0)}kg',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: normalized,
              minHeight: 4,
              backgroundColor: AppColors.surfaceHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  AppColors.surfaceLow,
                  AppColors.surfaceHighest.withValues(alpha: 0.95),
                ],
              ),
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        settings.tx(
                          'LIVE DIAGNOSIS ACTIVE',
                          'التشخيص المباشر شغال',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  settings.tx('MUSCLE\nIMBALANCE', 'اختلال\nعضلي'),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    height: 0.92,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.tx('CURRENT STATUS', 'الحالة الحالية'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusText.toUpperCase(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _report == null
                              ? primary
                              : (_report!.weaknesses.length > 2
                                    ? danger
                                    : secondary),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.surfaceLow.withValues(alpha: 0.92),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 48,
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settings.tx(
                                'PUSH/PULL RATIO',
                                'نسبة الدفع/السحب',
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                            ),
                            Text(
                              ratioLine,
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            settings.tx('ANALYZED SESSIONS', 'الجلسات المحللة'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                          ),
                          Text(
                            '${widget.sessions.length} ${settings.tx('Last lifts', 'آخر تسجيلات')}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLow.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: primary.withValues(alpha: 0.48),
                            ),
                          ),
                          child: Text(
                            settings.tx(
                              'Anterior Head\nOveractive',
                              'أمام الكتف\nنشط زيادة',
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLow.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: secondary.withValues(alpha: 0.48),
                            ),
                          ),
                          child: Text(
                            settings.tx(
                              'Lower Traps\nUnder-engaged',
                              'أسفل الترابيس\nتفعيل أقل',
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.surfaceLow.withValues(alpha: 0.92),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.tx(
                      'Bench vs. Row Disparity',
                      'فارق البنش مقابل السحب',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  ratioBar(
                    label: settings.tx(
                      'Bench Press (Max 1RM)',
                      'بنش برس (أقصى 1RM)',
                    ),
                    value: bench1Rm,
                    color: primary,
                  ),
                  const SizedBox(height: 10),
                  ratioBar(
                    label: settings.tx(
                      'Bent Row / Pull (Max 1RM)',
                      'سحب ظهر (أقصى 1RM)',
                    ),
                    value: pull1Rm,
                    color: secondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    settings.tx(
                      'Your structural balance insight updates after every rehab analysis run.',
                      'تحديث توازن الجسم بيحصل بعد كل تشغيل لتحليل التأهيل.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.surfaceLow.withValues(alpha: 0.92),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.tx(
                      'Before analysis, tell us more details',
                      'قبل التحليل، احكي لنا تفاصيل أكثر',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    settings.tx(
                      'AI rehab needs pain context and your target to generate safer corrective guidance.',
                      'تحليل التأهيل يحتاج سياق الألم وهدفك عشان يطلع توصيات أدق وأأمن.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _painAreaController,
                    onChanged: (_) {
                      if (_detailsConfirmed) {
                        setState(() {
                          _detailsConfirmed = false;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: settings.tx('Pain area*', 'منطقة الألم*'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _symptomDurationController,
                    onChanged: (_) {
                      if (_detailsConfirmed) {
                        setState(() {
                          _detailsConfirmed = false;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: settings.tx(
                        'Symptom duration* (e.g. 3 weeks)',
                        'مدة الأعراض* (مثال: 3 أسابيع)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _analysisGoalController,
                    onChanged: (_) {
                      if (_detailsConfirmed) {
                        setState(() {
                          _detailsConfirmed = false;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: settings.tx('Rehab goal*', 'هدف التأهيل*'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _analysisNotesController,
                    maxLines: 2,
                    onChanged: (_) {
                      if (_detailsConfirmed) {
                        setState(() {
                          _detailsConfirmed = false;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: settings.tx('Extra notes', 'ملاحظات إضافية'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    settings.tx(
                      'Pain level: ${_painLevel.toStringAsFixed(1)} / 10',
                      'مستوى الألم: ${_painLevel.toStringAsFixed(1)} / 10',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Slider(
                    value: _painLevel,
                    min: 0,
                    max: 10,
                    divisions: 20,
                    label: _painLevel.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        _painLevel = value;
                        _detailsConfirmed = false;
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _saveIntakeDetails,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          settings.tx('SAVE DETAILS', 'احفظ التفاصيل'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _detailsConfirmed
                              ? settings.tx(
                                  'Details saved. Analysis unlocked.',
                                  'تم حفظ التفاصيل. التحليل متاح الآن.',
                                )
                              : settings.tx(
                                  'Save these details to unlock rehab analysis.',
                                  'احفظ التفاصيل عشان تفتح تحليل التأهيل.',
                                ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _detailsConfirmed
                                    ? primary
                                    : AppColors.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!_loadingStoredMetrics && missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: AppColors.surfaceLow.withValues(alpha: 0.9),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.tx(
                        'Required first: complete missing metrics',
                        'مطلوب أولاً: كمل البيانات الناقصة',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      settings.tx(
                        'Enter max set (kg + reps) once, and we save it to your profile for future rehab checks.',
                        'ادخل أعلى مجموعة (كجم + عدات) مرة واحدة، وهنحفظها في ملفك لتحليلات التأهيل القادمة.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...missing.map((key) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _movementLabel(key, settings),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller: _manualWeight[key],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: settings.tx('kg', 'كجم'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _manualReps[key],
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: settings.tx('reps', 'عدات'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    ElevatedButton.icon(
                      onPressed: _savingMissingMetrics
                          ? null
                          : _saveMissingMetrics,
                      icon: _savingMissingMetrics
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        settings.tx(
                          'SAVE REQUIRED DATA',
                          'احفظ البيانات المطلوبة',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ElevatedButton.icon(
            onPressed:
                _loadingStoredMetrics ||
                    _savingMissingMetrics ||
                    _analyzing ||
                    missing.isNotEmpty ||
                    !_detailsConfirmed
                ? null
                : _runAnalysis,
            icon: _analyzing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.psychology_alt_outlined),
            label: Text(
              settings.tx('RUN AI REHAB ANALYSIS', 'شغل تحليل التأهيل الذكي'),
            ),
          ),
          if (_report != null) ...[
            const SizedBox(height: 14),
            Card(
              color: AppColors.surfaceLow.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.tx('Current status', 'الحالة الحالية'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _report!.status,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: secondary),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            label: settings.tx('Push / Pull', 'دفع / سحب'),
                            value: _report!.pushPullRatio.toStringAsFixed(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Metric(
                            label: settings.tx('Lower / Upper', 'سفلي / علوي'),
                            value: _report!.lowerUpperRatio.toStringAsFixed(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Metric(
                            label: settings.tx('OH / Bench', 'كتف / بنش'),
                            value: _report!.overheadBenchRatio.toStringAsFixed(
                              2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _WeakMusclePreviewPanel(
                      weakZones: _report!.zones,
                    ),
                    const SizedBox(height: 10),
                    ..._report!.weaknesses.map((line) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: secondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(line)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Text(
                      _aiCoachLine ?? _report!.coachTip,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_recommendations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: AppColors.surfaceLow.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.tx('Correction Log', 'سجل التصحيح'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      settings.tx(
                        'Session starts with mobility, then corrective exercises with video explainers.',
                        'الروتين يبدأ بالموبيلتي وبعدها تمارين تصحيح مع فيديو توضيحي.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline, color: primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              settings.tx(
                                'PRE-ROUTINE MOBILITY: Focus on thoracic extension and pec minor release before corrective work.',
                                'موبيلتي قبل الروتين: ركّز على تمديد العمود الصدري وتحرير عضلة الصدر الصغيرة قبل تمارين التصحيح.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._recommendations.asMap().entries.map((entry) {
                      final index = entry.key;
                      final recommendation = entry.value;
                      final exercise = recommendation.exercise;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighest.withValues(
                            alpha: 0.58,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.outline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'EXERCISE ${(index + 1).toString().padLeft(2, '0')}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: primary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                      ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    settings.tx(
                                      'REHAB PRIORITY',
                                      'أولوية تأهيل',
                                    ),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: primary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              exercise.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              recommendation.reason,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 88,
                                    height: 62,
                                    child: exercise.previewThumbnailUrl == null
                                        ? Container(
                                            color: AppColors.surfaceLow,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.play_circle_fill,
                                            ),
                                          )
                                        : Image.network(
                                            exercise.previewThumbnailUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) {
                                              return Container(
                                                color: AppColors.surfaceLow,
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.play_circle_fill,
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _openExerciseVideo(
                                      recommendation,
                                      settings,
                                    ),
                                    icon: const Icon(
                                      Icons.ondemand_video_outlined,
                                    ),
                                    label: Text(
                                      settings.tx(
                                        'Watch Explainer',
                                        'شاهد الشرح',
                                      ),
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
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.surfaceLow,
                    AppColors.surfaceHighest.withValues(alpha: 0.9),
                  ],
                ),
                border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.tx('Finish Routine?', 'نُنهي الروتين؟'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    settings.tx(
                      'AI will recalculate your imbalance ratio based on your logged rehab work.',
                      'الذكاء الاصطناعي هيعيد حساب الاختلال بناءً على تسجيلات التأهيل.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _runAnalysis,
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        settings.tx(
                          'SUBMIT REHAB SESSION',
                          'إرسال جلسة التأهيل',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeakMusclePreviewPanel extends StatelessWidget {
  const _WeakMusclePreviewPanel({
    required this.weakZones,
  });

  final Set<_BodyZone> weakZones;

  _BodyZone _primaryZone() {
    if (weakZones.contains(_BodyZone.legs)) {
      return _BodyZone.legs;
    }
    if (weakZones.contains(_BodyZone.shoulders)) {
      return _BodyZone.shoulders;
    }
    if (weakZones.contains(_BodyZone.torso)) {
      return _BodyZone.torso;
    }
    return _BodyZone.torso;
  }

  String _zoneLabel(_BodyZone zone, AppSettings settings) {
    return switch (zone) {
      _BodyZone.shoulders => settings.tx('Shoulders', 'الكتف'),
      _BodyZone.torso => settings.tx('Torso', 'الجذع'),
      _BodyZone.legs => settings.tx('Legs', 'الرجل'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final danger = Theme.of(context).colorScheme.error;
    final zone = _primaryZone();
    final zoneLabel = _zoneLabel(zone, settings);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: 0.16),
            AppColors.surfaceHighest.withValues(alpha: 0.85),
            danger.withValues(alpha: 0.11),
          ],
        ),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settings.tx('Weak muscle focus', 'العضلة الأضعف حاليًا'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Text(
            settings.tx(
              'Focus zone based on your current imbalance profile: $zoneLabel',
              'منطقة التركيز حسب تحليل الاختلال الحالي: $zoneLabel',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLow.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                Icon(Icons.fitness_center, color: danger, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    settings.tx(
                      'Image preview removed. Keep extra rehab volume and activation drills focused on $zoneLabel.',
                      'تم إزالة عرض الصور. حافظ على زيادة حجم تمارين التأهيل وتمارين التفعيل لمنطقة $zoneLabel.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
