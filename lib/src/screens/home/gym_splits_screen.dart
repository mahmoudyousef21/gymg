import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/splits_catalog.dart';
import '../../localization/egyptian_gym_lexicon.dart';
import '../../models/gym_split.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';

enum _SplitView { days, select, schedule }

class GymSplitsScreen extends StatefulWidget {
  const GymSplitsScreen({required this.userId, super.key});

  final String userId;

  @override
  State<GymSplitsScreen> createState() => _GymSplitsScreenState();
}

class _GymSplitsScreenState extends State<GymSplitsScreen> {
  final _service = SupabaseService.instance;
  final _notificationService = NotificationService.instance;

  bool _loading = true;
  String? _error;
  _SplitView _view = _SplitView.days;
  int _daysPerWeek = 3;
  SplitSchedule? _activeSplit;
  Set<int> _expandedSessions = <int>{};
  bool _customSplitLockedByCoach = false;
  String? _assignedCoachName;

  @override
  void initState() {
    super.initState();
    _loadSavedSplit();
  }

  Future<void> _loadSavedSplit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final savedFuture = _service.fetchSplitSchedule(widget.userId);
      final assignedCoachFuture = _service.fetchAssignedCoachForTrainee(
        widget.userId,
      );

      final saved = await savedFuture;
      final assignedCoach = await assignedCoachFuture;

      if (!mounted) {
        return;
      }

      setState(() {
        _activeSplit = saved;
        _customSplitLockedByCoach = assignedCoach != null;
        _assignedCoachName = assignedCoach?.name;
        if (saved != null && saved.schedule.isNotEmpty) {
          _view = _SplitView.schedule;
          _daysPerWeek = saved.daysPerWeek;
        } else {
          _view = _SplitView.days;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<SplitScheduleEntry> _generateSchedule(GymSplit split) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);

    return split.days
        .asMap()
        .entries
        .map(
          (entry) => SplitScheduleEntry(
            label: entry.value.label,
            labelAr: entry.value.labelAr,
            muscles: entry.value.muscles,
            musclesAr: entry.value.musclesAr,
            exercises: entry.value.exercises,
            date: base.add(Duration(days: entry.key)),
            completed: false,
          ),
        )
        .toList();
  }

  List<SplitScheduleEntry> _deferFromIndex(
    List<SplitScheduleEntry> schedule,
    int fromIndex,
  ) {
    return schedule.asMap().entries.map((entry) {
      if (entry.key < fromIndex) {
        return entry.value;
      }
      return entry.value.copyWith(
        date: entry.value.date.add(const Duration(days: 1)),
      );
    }).toList();
  }

  bool _isDatePast(DateTime date) {
    final today = DateTime.now();
    final current = DateTime(today.year, today.month, today.day);
    final compare = DateTime(date.year, date.month, date.day);
    return compare.isBefore(current);
  }

  bool _isDateToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  String _formatDate(DateTime date) {
    final settings = context.appSettings;

    if (_isDateToday(date)) {
      return settings.tx('Today', 'النهارده');
    }

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    if (date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day) {
      return settings.tx('Tomorrow', 'بكره');
    }

    return DateFormat('EEE, MMM d').format(date);
  }

  String _term(String value, AppSettings settings) {
    return settings.isArabic ? EgyptianGymLexicon.term(value) : value;
  }

  String _exerciseName(ExerciseEntry exercise, AppSettings settings) {
    if (!settings.isArabic) {
      return exercise.name;
    }

    final fromCatalog = exercise.nameAr.trim();
    if (fromCatalog.isNotEmpty && fromCatalog != exercise.name) {
      return fromCatalog;
    }

    return EgyptianGymLexicon.term(exercise.name);
  }

  String _splitName(GymSplit split, AppSettings settings) {
    if (!settings.isArabic) {
      return split.name;
    }

    final fromCatalog = split.nameAr.trim();
    if (fromCatalog.isNotEmpty && fromCatalog != split.name) {
      return fromCatalog;
    }

    return EgyptianGymLexicon.term(split.name);
  }

  String _splitDescription(GymSplit split, AppSettings settings) {
    if (!settings.isArabic) {
      return split.description;
    }

    final fromCatalog = split.descriptionAr.trim();
    if (fromCatalog.isNotEmpty && fromCatalog != split.description) {
      return fromCatalog;
    }

    return EgyptianGymLexicon.term(split.description);
  }

  Future<void> _openExerciseVideo(ExerciseEntry exercise) async {
    final playbackUrl = exercise.playbackUrl;
    if (playbackUrl == null || playbackUrl.trim().isEmpty) {
      return;
    }

    final uri = Uri.parse(playbackUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _searchAlternativeVideo(String exerciseName) async {
    final query = Uri.encodeComponent('$exerciseName exercise tutorial');
    final uri = Uri.parse(
      'https://www.youtube.com/results?search_query=$query',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _persistSplit(SplitSchedule split) async {
    setState(() {
      _activeSplit = split;
      _error = null;
    });

    try {
      await _service.upsertSplitSchedule(
        userId: widget.userId,
        schedule: split,
      );
      if (!mounted) {
        return;
      }
      await _notificationService.updateSplitReminders(
        splitSchedule: split,
        isArabic: context.appSettings.isArabic,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  Future<void> _selectSplit(GymSplit split) async {
    final next = SplitSchedule(
      splitId: split.id,
      splitName: split.name,
      splitNameAr: split.nameAr,
      daysPerWeek: split.daysPerWeek,
      currentDayIndex: 0,
      schedule: _generateSchedule(split),
    );

    _expandedSessions = <int>{};

    await _persistSplit(next);

    if (!mounted) {
      return;
    }

    setState(() {
      _view = _SplitView.schedule;
    });
  }

  List<ExerciseEntry> _catalogExercises() {
    final unique = <String, ExerciseEntry>{};
    for (final splitList in splitsCatalog.values) {
      for (final split in splitList) {
        for (final day in split.days) {
          for (final exercise in day.exercises) {
            unique.putIfAbsent(exercise.name, () => exercise);
          }
        }
      }
    }

    final ordered = unique.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return ordered;
  }

  String _normalizeExerciseKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _sectionKeyFromExercise(String exerciseName) {
    final n = _normalizeExerciseKey(exerciseName);

    if (n.contains('bench') ||
        n.contains('dip') ||
        n.contains('push up') ||
        n.contains('pushup')) {
      return 'push';
    }
    if (n.contains('squat') || n.contains('leg press') || n.contains('lunge')) {
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

    return n;
  }

  ExerciseEntry? _findExerciseFromCatalog(String candidateName) {
    final needle = _normalizeExerciseKey(candidateName);
    if (needle.isEmpty) {
      return null;
    }

    for (final exercise in _catalogExercises()) {
      if (_normalizeExerciseKey(exercise.name) == needle ||
          _normalizeExerciseKey(exercise.nameAr) == needle) {
        return exercise;
      }

      for (final variation in exercise.variations) {
        if (_normalizeExerciseKey(variation) == needle) {
          return exercise;
        }
      }

      for (final variation in exercise.variationsAr) {
        if (_normalizeExerciseKey(variation) == needle) {
          return exercise;
        }
      }
    }

    return null;
  }

  List<ExerciseEntry> _swapAlternativesFor(ExerciseEntry exercise) {
    final alternatives = <ExerciseEntry>[];
    final seen = <String>{_normalizeExerciseKey(exercise.name)};

    void addAlternative(ExerciseEntry candidate) {
      final key = _normalizeExerciseKey(candidate.name);
      if (key.isEmpty || seen.contains(key)) {
        return;
      }
      seen.add(key);
      alternatives.add(candidate);
    }

    for (final variation in exercise.variations) {
      final found = _findExerciseFromCatalog(variation);
      if (found != null) {
        addAlternative(found);
      }
    }

    if (alternatives.length < 3) {
      final sectionKey = _sectionKeyFromExercise(exercise.name);
      for (final candidate in _catalogExercises()) {
        if (_sectionKeyFromExercise(candidate.name) == sectionKey) {
          addAlternative(candidate);
        }
        if (alternatives.length >= 3) {
          break;
        }
      }
    }

    return alternatives.take(3).toList();
  }

  String _variationLevelLabel(int index, AppSettings settings) {
    return switch (index) {
      0 => settings.tx('LEVEL 1: BASIC', 'المستوى 1: أساسي'),
      1 => settings.tx('LEVEL 2: ADVANCED', 'المستوى 2: متقدم'),
      _ => settings.tx('LEVEL 3: ELITE', 'المستوى 3: نخبة'),
    };
  }

  Color _variationLevelColor(int index) {
    return switch (index) {
      0 => AppColors.primary,
      1 => AppColors.secondary,
      _ => AppColors.yellow,
    };
  }

  ExerciseEntry _replacementWithPlannedVolume({
    required ExerciseEntry current,
    required ExerciseEntry replacement,
  }) {
    return ExerciseEntry(
      name: replacement.name,
      nameAr: replacement.nameAr,
      sets: current.sets,
      reps: current.reps,
      youtubeId: replacement.youtubeId,
      videoUrl: replacement.videoUrl,
      thumbnailUrl: replacement.thumbnailUrl,
      primaryMuscles: replacement.primaryMuscles,
      primaryMusclesAr: replacement.primaryMusclesAr,
      variations: replacement.variations,
      variationsAr: replacement.variationsAr,
    );
  }

  Future<void> _replaceSplitExercise({
    required int dayIndex,
    required int exerciseIndex,
    required ExerciseEntry replacement,
  }) async {
    final active = _activeSplit;
    if (active == null) {
      return;
    }

    if (dayIndex < 0 || dayIndex >= active.schedule.length) {
      return;
    }

    final entry = active.schedule[dayIndex];
    if (exerciseIndex < 0 || exerciseIndex >= entry.exercises.length) {
      return;
    }

    final current = entry.exercises[exerciseIndex];
    final nextExercises = [...entry.exercises];
    nextExercises[exerciseIndex] = _replacementWithPlannedVolume(
      current: current,
      replacement: replacement,
    );

    final nextSchedule = [...active.schedule];
    nextSchedule[dayIndex] = entry.copyWith(exercises: nextExercises);

    await _persistSplit(active.copyWith(schedule: nextSchedule));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.appSettings.tx(
            'Split exercise swapped to ${replacement.name}.',
            'تم تبديل تمرين السبليت إلى ${replacement.nameAr}.',
          ),
        ),
      ),
    );
  }

  Future<void> _openSwapVariationSheet({
    required int dayIndex,
    required int exerciseIndex,
  }) async {
    final active = _activeSplit;
    if (active == null) {
      return;
    }

    if (dayIndex < 0 || dayIndex >= active.schedule.length) {
      return;
    }

    final entry = active.schedule[dayIndex];
    if (exerciseIndex < 0 || exerciseIndex >= entry.exercises.length) {
      return;
    }

    final settings = context.appSettings;
    final current = entry.exercises[exerciseIndex];
    final alternatives = _swapAlternativesFor(current);

    if (alternatives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            settings.tx(
              'No alternatives found for this exercise yet.',
              'لسه مفيش بدائل جاهزة للتمرين ده.',
            ),
          ),
        ),
      );
      return;
    }

    var applying = false;
    var selectedIndex = -1;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);

        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF07090D),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    border: Border.all(
                      color: AppColors.outline.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      12 + media.padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                settings.tx(
                                  'SWAP VARIATION',
                                  'تبديل التمرين',
                                ),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            IconButton(
                              onPressed: applying
                                  ? null
                                  : () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          settings.tx('Current exercise', 'التمرين الحالي'),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _exerciseName(current, settings),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (current.previewThumbnailUrl != null) ...[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Image.network(
                                current.previewThumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: AppColors.surfaceHighest,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                settings.tx(
                                  'Alternatives',
                                  'البدائل المتاحة',
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              settings.tx(
                                '${alternatives.length} options',
                                '${alternatives.length} خيارات',
                              ),
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.separated(
                            itemCount: alternatives.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final option = alternatives[index];
                              final levelColor = _variationLevelColor(index);
                              final inFlight =
                                  applying && selectedIndex == index;

                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceHigh,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: levelColor.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 92,
                                        height: 62,
                                        child: option.previewThumbnailUrl == null
                                            ? Container(
                                                color: AppColors.surfaceHighest,
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.play_circle_fill,
                                                ),
                                              )
                                            : Image.network(
                                                option.previewThumbnailUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) {
                                                  return Container(
                                                    color: AppColors
                                                        .surfaceHighest,
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
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _exerciseName(option, settings),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: levelColor.withValues(
                                                alpha: 0.16,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _variationLevelLabel(
                                                index,
                                                settings,
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    color: levelColor,
                                                    letterSpacing: 1,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: applying
                                                  ? null
                                                  : () async {
                                                      setSheetState(() {
                                                        applying = true;
                                                        selectedIndex = index;
                                                      });
                                                      await _replaceSplitExercise(
                                                        dayIndex: dayIndex,
                                                        exerciseIndex:
                                                            exerciseIndex,
                                                        replacement: option,
                                                      );
                                                      if (!mounted) {
                                                        return;
                                                      }
                                                      if (sheetContext.mounted) {
                                                        Navigator.of(
                                                          sheetContext,
                                                        ).pop();
                                                      }
                                                    },
                                              icon: inFlight
                                                  ? const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : const Icon(
                                                      Icons.bolt_rounded,
                                                    ),
                                              label: Text(
                                                settings.tx(
                                                  'SELECT TO SWAP',
                                                  'اختار للتبديل',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCustomSplitBuilder() async {
    if (_customSplitLockedByCoach) {
      final settings = context.appSettings;
      final coachLabel = _assignedCoachName?.trim().isNotEmpty == true
          ? _assignedCoachName!
          : settings.tx('your captain', 'الكابتن بتاعك');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            settings.tx(
              'Custom split is locked while $coachLabel manages your plan.',
              'السبليت المخصص متقفل طالما $coachLabel مسؤول عن خطتك.',
            ),
          ),
        ),
      );
      return;
    }

    final settings = context.appSettings;
    final exercises = _catalogExercises();
    final splitNameController = TextEditingController(
      text: settings.tx('Custom Split', 'سبليت مخصص'),
    );
    final searchController = TextEditingController();
    final selectedByDay = List<Set<String>>.generate(
      _daysPerWeek,
      (_) => <String>{},
    );

    var activeDay = 0;
    var query = '';

    try {
      final customSplit = await showModalBottomSheet<GymSplit>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final filtered = exercises.where((exercise) {
                if (query.isEmpty) {
                  return true;
                }
                final text =
                    '${exercise.name} ${exercise.primaryMuscles.join(' ')}'
                        .toLowerCase();
                return text.contains(query);
              }).toList();

              final canSave =
                  splitNameController.text.trim().isNotEmpty &&
                  selectedByDay.every((selection) => selection.isNotEmpty);

              return SafeArea(
                child: DraggableScrollableSheet(
                  initialChildSize: 0.92,
                  minChildSize: 0.7,
                  maxChildSize: 0.96,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLow,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        border: Border.all(
                          color: AppColors.outline.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          MediaQuery.of(sheetContext).viewInsets.bottom + 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 48,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: AppColors.outline,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              settings.tx(
                                'Build Your Own Split',
                                'ابني السبليت بتاعك',
                              ),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              settings.tx(
                                'Pick exercises from the current library and assign them to each day.',
                                'اختار تمارين من المكتبة الحالية ووزعها على أيامك.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: splitNameController,
                              onChanged: (_) => setSheetState(() {}),
                              decoration: InputDecoration(
                                labelText: settings.tx(
                                  'Split name',
                                  'اسم السبليت',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 38,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemBuilder: (context, index) {
                                  final selected = index == activeDay;
                                  final count = selectedByDay[index].length;
                                  return ChoiceChip(
                                    selected: selected,
                                    label: Text(
                                      settings.tx(
                                        'Day ${index + 1} ($count)',
                                        'يوم ${index + 1} ($count)',
                                      ),
                                    ),
                                    onSelected: (_) {
                                      setSheetState(() {
                                        activeDay = index;
                                      });
                                    },
                                  );
                                },
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemCount: _daysPerWeek,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: searchController,
                              onChanged: (value) {
                                setSheetState(() {
                                  query = value.trim().toLowerCase();
                                });
                              },
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                labelText: settings.tx(
                                  'Search exercises',
                                  'دوّر على تمرين',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final exercise = filtered[index];
                                  final selected = selectedByDay[activeDay]
                                      .contains(exercise.name);

                                  return CheckboxListTile(
                                    value: selected,
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    title: Text(
                                      _exerciseName(exercise, settings),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      settings.tx(
                                        '${exercise.sets} sets x ${exercise.reps} reps • ${exercise.primaryMuscles.join(', ')}',
                                        '${exercise.sets} جمل x ${exercise.reps} عدة • ${exercise.primaryMuscles.join('، ')}',
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onChanged: (checked) {
                                      setSheetState(() {
                                        if (checked ?? false) {
                                          selectedByDay[activeDay].add(
                                            exercise.name,
                                          );
                                        } else {
                                          selectedByDay[activeDay].remove(
                                            exercise.name,
                                          );
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: canSave
                                    ? () {
                                        final byName = {
                                          for (final exercise in exercises)
                                            exercise.name: exercise,
                                        };
                                        final days = selectedByDay
                                            .asMap()
                                            .entries
                                            .map((entry) {
                                              final dayIndex = entry.key;
                                              final selection = entry.value
                                                  .map((name) => byName[name])
                                                  .whereType<ExerciseEntry>()
                                                  .toList();

                                              final muscles = <String>{};
                                              final musclesAr = <String>{};
                                              for (final exercise
                                                  in selection) {
                                                muscles.addAll(
                                                  exercise.primaryMuscles,
                                                );
                                                musclesAr.addAll(
                                                  exercise.primaryMusclesAr,
                                                );
                                              }

                                              return GymSplitDay(
                                                label: 'Day ${dayIndex + 1}',
                                                labelAr: 'يوم ${dayIndex + 1}',
                                                muscles: muscles.isEmpty
                                                    ? <String>['Mixed']
                                                    : muscles.toList(),
                                                musclesAr: musclesAr.isEmpty
                                                    ? <String>['متنوع']
                                                    : musclesAr.toList(),
                                                exercises: selection,
                                              );
                                            })
                                            .toList();

                                        final splitName = splitNameController
                                            .text
                                            .trim();
                                        Navigator.of(context).pop(
                                          GymSplit(
                                            id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                                            name: splitName,
                                            nameAr: splitName,
                                            description: settings.tx(
                                              'Your custom split built from the exercise library.',
                                              'سبليت مخصص مبني من مكتبة التمارين الحالية.',
                                            ),
                                            descriptionAr: settings.tx(
                                              'Your custom split built from the exercise library.',
                                              'سبليت مخصص مبني من مكتبة التمارين الحالية.',
                                            ),
                                            daysPerWeek: _daysPerWeek,
                                            days: days,
                                          ),
                                        );
                                      }
                                    : null,
                                icon: const Icon(Icons.check_circle_outline),
                                label: Text(
                                  settings.tx(
                                    'CREATE CUSTOM SPLIT',
                                    'أنشئ السبليت المخصص',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      );

      if (customSplit != null) {
        await _selectSplit(customSplit);
      }
    } finally {
      splitNameController.dispose();
      searchController.dispose();
    }
  }

  Future<void> _toggleDay(int index) async {
    final active = _activeSplit;
    if (active == null) {
      return;
    }

    final entry = active.schedule[index];
    if (entry.completed) {
      final shifted = _deferFromIndex(active.schedule, index);
      final updated = shifted
          .asMap()
          .entries
          .map(
            (item) => item.key == index
                ? item.value.copyWith(completed: false)
                : item.value,
          )
          .toList();

      await _persistSplit(
        active.copyWith(schedule: updated, currentDayIndex: index),
      );
      return;
    }

    final updated = active.schedule
        .asMap()
        .entries
        .map(
          (item) => item.key == index
              ? item.value.copyWith(completed: true)
              : item.value,
        )
        .toList();

    var nextPending = -1;
    for (var i = index + 1; i < updated.length; i++) {
      if (!updated[i].completed) {
        nextPending = i;
        break;
      }
    }

    await _persistSplit(
      active.copyWith(
        schedule: updated,
        currentDayIndex: nextPending == -1 ? updated.length - 1 : nextPending,
      ),
    );
  }

  Future<void> _deferDay(int index) async {
    final active = _activeSplit;
    if (active == null) {
      return;
    }

    final updated = _deferFromIndex(active.schedule, index);
    await _persistSplit(
      active.copyWith(schedule: updated, currentDayIndex: index),
    );
  }

  Future<void> _resetSplit() async {
    setState(() {
      _activeSplit = null;
      _expandedSessions = <int>{};
      _view = _SplitView.days;
    });

    try {
      await _service.deleteSplitSchedule(widget.userId);
      if (!mounted) {
        return;
      }
      await _notificationService.updateSplitReminders(
        splitSchedule: null,
        isArabic: context.appSettings.isArabic,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: primary));
    }

    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.tx(
                      'Split schedule issue',
                      'في مشكلة في جدول السبليت',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(_error!),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadSavedSplit,
                    child: Text(settings.tx('TRY AGAIN', 'حاول تاني')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: switch (_view) {
        _SplitView.days => _buildDaysPicker(context),
        _SplitView.select => _buildSplitSelector(context),
        _SplitView.schedule => _buildSchedule(context),
      },
    );
  }

  Widget _buildDaysPicker(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final frequencyOptions = List<int>.generate(6, (index) => index + 1);

    return SingleChildScrollView(
      key: const ValueKey('days_picker'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  settings.tx('KINETIC CYBERNETICS', 'الاختيار الذكي للسبليت'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...List.generate(4, (index) {
                final active = index == 1;
                return Container(
                  margin: const EdgeInsets.only(left: 4),
                  width: 28,
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: active
                        ? primary
                        : AppColors.surfaceHighest.withValues(alpha: 0.9),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 24),
          Text.rich(
            TextSpan(
              text: settings.tx(
                'How many days per week ',
                'بتقدر تتمرن كام يوم ',
              ),
              children: [
                TextSpan(
                  text: settings.tx('can you train?', 'في الأسبوع؟'),
                  style: TextStyle(color: primary),
                ),
              ],
            ),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            settings.tx(
              'Consistency builds momentum. Pick a frequency you can sustain every week.',
              'الاستمرارية هي مفتاح التطور. اختار عدد أيام ثابت يناسب وقتك فعلا.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          ...frequencyOptions.map((day) {
            final selected = _daysPerWeek == day;
            final highlight = day == 4;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    setState(() {
                      _daysPerWeek = day;
                    });
                  },
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: selected
                            ? [
                                AppColors.surfaceBright.withValues(alpha: 0.95),
                                AppColors.surfaceHigh.withValues(alpha: 0.92),
                              ]
                            : [
                                AppColors.surfaceLow.withValues(alpha: 0.9),
                                AppColors.surfaceLow.withValues(alpha: 0.86),
                              ],
                      ),
                      border: Border.all(
                        color: selected
                            ? primary.withValues(alpha: 0.9)
                            : AppColors.outline.withValues(alpha: 0.45),
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.28),
                                blurRadius: 22,
                                spreadRadius: 0.5,
                                offset: const Offset(0, 10),
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 16,
                          top: 10,
                          bottom: 10,
                          child: Text(
                            '$day',
                            style: Theme.of(context).textTheme.displayMedium
                                ?.copyWith(
                                  color: selected
                                      ? primary.withValues(alpha: 0.95)
                                      : Colors.white.withValues(alpha: 0.12),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        if (highlight)
                          Positioned(
                            right: 12,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                settings.tx('RECOMMENDED', 'مقترح'),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Colors.black,
                                      letterSpacing: 1.2,
                                    ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(86, 18, 16, 18),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _frequencyTierLabel(day, settings),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _frequencyTierSubtitle(day, settings),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: AppColors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: selected
                                    ? primary
                                    : AppColors.onSurfaceVariant,
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
          }),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.secondary.withValues(alpha: 0.1),
              border: Border.all(
                color: AppColors.secondary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info, color: AppColors.secondary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    settings.tx(
                      'You can change your frequency any time from Settings. Your split will recalibrate automatically.',
                      'تقدر تغيّر عدد الأيام في أي وقت من الإعدادات، والسبليت هيتحدث تلقائيا.',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildNeonCta(
            context: context,
            label: settings.tx('NEXT PHASE', 'المرحلة التالية'),
            icon: Icons.arrow_forward,
            onTap: () {
              setState(() {
                _view = _SplitView.select;
              });
            },
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _view = _SplitView.select;
                });
              },
              child: Text(
                settings.tx('SKIP FOR NOW', 'تخطى الآن'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 2,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitSelector(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final splits = splitsCatalog[_daysPerWeek] ?? <GymSplit>[];
    final customSplitLocked = _customSplitLockedByCoach;

    return ListView(
      key: const ValueKey('split_selector'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _view = _SplitView.days;
                });
              },
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.tx('PROTOCOL SELECTION', 'اختيار البروتوكول'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: primary,
                      letterSpacing: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    settings.tx('Choose Your Split', 'اختار السبليت المناسب'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    settings.tx(
                      '$_daysPerWeek days per week',
                      '$_daysPerWeek يوم في الأسبوع',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          color: AppColors.surfaceLow.withValues(alpha: 0.94),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.tx('BUILD YOUR OWN SPLIT', 'ابني السبليت بتاعك'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: customSplitLocked ? AppColors.onSurfaceVariant : primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  customSplitLocked
                      ? settings.tx(
                          'Your captain currently controls your split. Custom creation is disabled.',
                          'الكابتن مسؤول حاليًا عن السبليت بتاعك. إنشاء سبليت مخصص متوقف.',
                        )
                      : settings.tx(
                          'Choose from current exercises and craft your own weekly plan.',
                          'اختار من التمارين الحالية وصمّم خطة أسبوعك بنفسك.',
                        ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (customSplitLocked && _assignedCoachName?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    settings.tx(
                      'Assigned captain: ${_assignedCoachName!}',
                      'الكابتن الحالي: ${_assignedCoachName!}',
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: customSplitLocked ? null : _openCustomSplitBuilder,
                    icon: const Icon(Icons.tune),
                    label: Text(
                      settings.tx('MAKE MY OWN SPLIT', 'اعمل السبليت بتاعي'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...splits.asMap().entries.map((entry) {
          final index = entry.key;
          final split = entry.value;
          final focusTags = _splitFocusTags(split, settings);
          final cardAccent = _cardAccent(index);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.surfaceLow.withValues(alpha: 0.95),
                    AppColors.surfaceHigh.withValues(alpha: 0.9),
                  ],
                ),
                border: Border.all(
                  color: index == 0
                      ? primary.withValues(alpha: 0.8)
                      : AppColors.outline.withValues(alpha: 0.34),
                ),
                boxShadow: index == 0
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _selectSplit(split),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cardAccent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: cardAccent.withValues(alpha: 0.55),
                                  ),
                                ),
                                child: Text(
                                  _splitTierLabel(split, settings),
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: cardAccent),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  settings.tx(
                                    '${split.daysPerWeek} DAYS / WEEK',
                                    '${split.daysPerWeek} أيام / الأسبوع',
                                  ),
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(color: primary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _splitName(split, settings),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _splitDescription(split, settings),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: focusTags
                                .map(
                                  (tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceHighest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      tag,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: AppColors.onSurface,
                                            letterSpacing: 0.8,
                                          ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: index == 0
                                    ? primary
                                    : Colors.transparent,
                                foregroundColor: index == 0
                                    ? Colors.black
                                    : AppColors.onSurface,
                                side: index == 0
                                    ? BorderSide.none
                                    : BorderSide(
                                        color: primary.withValues(alpha: 0.7),
                                      ),
                              ),
                              onPressed: () => _selectSplit(split),
                              child: Text(
                                settings.tx('SELECT PLAN', 'اختار الخطة'),
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
        }),
        if (splits.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                settings.tx(
                  'No split templates found for this day count.',
                  'مفيش قوالب سبليت لعدد الأيام ده.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        if (splits.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MetricPillar(
                value: '100+',
                label: settings.tx('Custom Exercises', 'تمارين مخصصة'),
              ),
              _MetricPillar(
                value: 'Dynamic',
                label: settings.tx('Rest Management', 'إدارة الراحة'),
              ),
              _MetricPillar(
                value: 'Real-Time',
                label: settings.tx('PR Tracking', 'متابعة الإنجاز'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSchedule(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final active = _activeSplit;
    if (active == null) {
      return _buildDaysPicker(context);
    }

    final completed = active.schedule.where((entry) => entry.completed).length;
    final progress = active.schedule.isEmpty
        ? 0.0
        : completed / active.schedule.length;
    final focusIndex = active.currentDayIndex.clamp(
      0,
      active.schedule.length - 1,
    );
    final currentFocus = active.schedule[focusIndex];

    return ListView(
      key: const ValueKey('split_schedule'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
      children: [
        Row(
          children: [
            Text(
              settings.tx('CURRENT SPLIT', 'السبليت الحالي'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _resetSplit,
              tooltip: settings.tx('Change split', 'غيّر السبليت'),
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          settings.tx('CURRENT FOCUS', 'التركيز الحالي'),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: primary),
        ),
        const SizedBox(height: 4),
        Text(
          _term(currentFocus.label, settings),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaChip(
              icon: Icons.schedule,
              label: settings.tx(
                '${_estimatedSessionMinutes(currentFocus)} MIN',
                '${_estimatedSessionMinutes(currentFocus)} دقيقة',
              ),
            ),
            _MetaChip(
              icon: Icons.flash_on,
              label: _sessionIntensityLabel(currentFocus, settings),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.surfaceLow.withValues(alpha: 0.9),
            border: Border.all(
              color: AppColors.outline.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.tx(
                  '${_term(active.splitName, settings)} • $completed/${active.schedule.length}',
                  '${_term(active.splitName, settings)} • $completed/${active.schedule.length}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress,
                  backgroundColor: AppColors.surfaceHighest,
                  valueColor: AlwaysStoppedAnimation(primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...active.schedule.asMap().entries.map((item) {
          final index = item.key;
          final entry = item.value;
          final isExpanded = _expandedSessions.contains(index);
          final isCurrent = index == active.currentDayIndex && !entry.completed;
          final isPast = _isDatePast(entry.date);
          final hasExercises = entry.exercises.isNotEmpty;
          final topExercise = hasExercises ? entry.exercises.first : null;
          final cardBorder = entry.completed
              ? primary.withValues(alpha: 0.65)
              : isCurrent
              ? primary.withValues(alpha: 0.8)
              : isPast
              ? Colors.amber.withValues(alpha: 0.6)
              : AppColors.outline.withValues(alpha: 0.4);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.surfaceLow.withValues(alpha: 0.95),
                    AppColors.surfaceHigh.withValues(alpha: 0.9),
                  ],
                ),
                border: Border.all(color: cardBorder),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.22),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (topExercise != null)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          child: _ExerciseVideoPreview(
                            thumbnailUrl: topExercise.previewThumbnailUrl,
                            onTap: topExercise.playbackUrl == null
                                ? null
                                : () => _openExerciseVideo(topExercise),
                            playLabel: settings.tx(
                              'Watch demo video',
                              'افتح فيديو التمرين',
                            ),
                          ),
                        ),
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              settings.tx('FORM PREVIEW', 'مراجعة الأداء'),
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _term(entry.label, settings),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _entrySetsReps(entry, settings),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: primary),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _formatDate(entry.date),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: hasExercises
                                  ? () {
                                      setState(() {
                                        if (isExpanded) {
                                          _expandedSessions.remove(index);
                                        } else {
                                          _expandedSessions.add(index);
                                        }
                                      });
                                    }
                                  : null,
                              icon: Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighest.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.secondary.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.tips_and_updates,
                                    color: AppColors.secondary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    settings.tx("COACH'S TIP", 'نصيحة المدرب'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: AppColors.secondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _coachTip(topExercise, settings),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: hasExercises
                                    ? () => _openSwapVariationSheet(
                                        dayIndex: index,
                                        exerciseIndex: 0,
                                      )
                                    : null,
                                child: Text(
                                  settings.tx('SWAP VARIATION', 'بدل التمرين'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: settings.tx('Mark done', 'تم الإنجاز'),
                              onPressed: () => _toggleDay(index),
                              icon: Icon(
                                entry.completed
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: entry.completed
                                    ? primary
                                    : AppColors.onSurfaceVariant,
                              ),
                            ),
                            if (!entry.completed)
                              IconButton(
                                onPressed: () => _deferDay(index),
                                tooltip: settings.tx(
                                  'Push this day by 1 day',
                                  'أجل اليوم ده ليوم كمان',
                                ),
                                icon: const Icon(Icons.fast_forward, size: 20),
                              ),
                          ],
                        ),
                        if (isExpanded && hasExercises) ...[
                          const SizedBox(height: 8),
                          ...entry.exercises.asMap().entries.map((
                            exerciseItem,
                          ) {
                            final exercise = exerciseItem.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHighest.withValues(
                                  alpha: 0.48,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.outline.withValues(
                                    alpha: 0.5,
                                  ),
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
                                          _exerciseName(exercise, settings),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          settings.tx(
                                            '${exercise.sets} sets of ${exercise.reps} reps',
                                            '${exercise.sets} جمل ${exercise.reps} عدة',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: primary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: settings.tx(
                                      'Watch demo video',
                                      'شوف فيديو التمرين',
                                    ),
                                    onPressed: exercise.playbackUrl == null
                                        ? null
                                        : () => _openExerciseVideo(exercise),
                                    icon: const Icon(Icons.play_circle_fill),
                                  ),
                                  IconButton(
                                    tooltip: settings.tx(
                                      'Search alternative',
                                      'دوّر على بديل',
                                    ),
                                    onPressed: exercise.variations.isEmpty
                                        ? null
                                        : () => _openSwapVariationSheet(
                                            dayIndex: index,
                                            exerciseIndex: exerciseItem.key,
                                          ),
                                    icon: const Icon(Icons.swap_horiz),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 6),
        _buildNeonCta(
          context: context,
          label: settings.tx('START TRAINING', 'ابدأ التمرين'),
          icon: Icons.play_circle_fill,
          onTap: () => _toggleDay(focusIndex),
        ),
      ],
    );
  }

  String _frequencyTierLabel(int day, AppSettings settings) {
    return switch (day) {
      <= 2 => settings.tx('MINIMALIST', 'الحد الأدنى'),
      3 => settings.tx('STANDARD', 'قياسي'),
      4 => settings.tx('OPTIMAL', 'مثالي'),
      5 => settings.tx('PERFORMANCE', 'أداء'),
      _ => settings.tx('ELITE', 'احترافي'),
    };
  }

  String _frequencyTierSubtitle(int day, AppSettings settings) {
    return switch (day) {
      <= 2 => settings.tx(
        'Perfect for maintaining base conditioning.',
        'مناسب للحفاظ على اللياقة الأساسية.',
      ),
      3 => settings.tx(
        'Balanced approach for strength and recovery.',
        'توازن ممتاز بين القوة والاستشفاء.',
      ),
      4 => settings.tx(
        'Maximum efficiency for hypertrophy and power.',
        'أفضل كفاءة للبناء العضلي والقوة.',
      ),
      5 => settings.tx(
        'High-volume protocols for advanced athletes.',
        'حجم تمرين عالي للمستويات المتقدمة.',
      ),
      _ => settings.tx(
        'Intensive split. Recovery discipline required.',
        'سبليت مكثف ويحتاج انضباط قوي في الاستشفاء.',
      ),
    };
  }

  String _splitTierLabel(GymSplit split, AppSettings settings) {
    return switch (split.daysPerWeek) {
      <= 2 => settings.tx('FOUNDATIONAL', 'أساسي'),
      3 => settings.tx('BALANCED', 'متوازن'),
      4 => settings.tx('ELITE PROTOCOL', 'بروتوكول احترافي'),
      5 => settings.tx('VOLUME KING', 'حجم تدريبي مرتفع'),
      _ => settings.tx('PERFORMANCE MAX', 'أقصى أداء'),
    };
  }

  List<String> _splitFocusTags(GymSplit split, AppSettings settings) {
    final tags = <String>[];

    for (final day in split.days) {
      for (final muscle in day.muscles) {
        final translated = _term(muscle, settings);
        if (!tags.contains(translated)) {
          tags.add(translated.toUpperCase());
        }

        if (tags.length >= 3) {
          return tags;
        }
      }
    }

    return tags;
  }

  Color _cardAccent(int index) {
    const accents = [
      AppColors.blue,
      AppColors.lime,
      AppColors.secondary,
      AppColors.yellow,
    ];
    return accents[index % accents.length];
  }

  String _entrySetsReps(SplitScheduleEntry entry, AppSettings settings) {
    if (entry.exercises.isEmpty) {
      return settings.tx('No exercises assigned', 'لا يوجد تمارين لهذا اليوم');
    }

    final first = entry.exercises.first;
    return settings.tx(
      '${first.sets} sets of ${first.reps} reps',
      '${first.sets} جمل ${first.reps} عدة',
    );
  }

  int _estimatedSessionMinutes(SplitScheduleEntry entry) {
    if (entry.exercises.isEmpty) {
      return 30;
    }
    return (entry.exercises.length * 15).clamp(30, 110);
  }

  String _sessionIntensityLabel(
    SplitScheduleEntry entry,
    AppSettings settings,
  ) {
    final count = entry.exercises.length;
    if (count >= 5) {
      return settings.tx('HIGH INTENSITY', 'شدة عالية');
    }
    if (count >= 3) {
      return settings.tx('MODERATE', 'متوسطة');
    }
    return settings.tx('LOW VOLUME', 'حجم منخفض');
  }

  String _coachTip(ExerciseEntry? exercise, AppSettings settings) {
    if (exercise == null) {
      return settings.tx(
        'Control your tempo and prioritize full range of motion for each rep.',
        'ركز على التحكم في الحركة والمدى الكامل لكل عدة.',
      );
    }

    final mainTarget = exercise.primaryMuscles.isNotEmpty
        ? _term(exercise.primaryMuscles.first, settings)
        : settings.tx('target muscle', 'العضلة المستهدفة');

    return settings.tx(
      'Drive hard on the concentric, then control a 3-second eccentric to keep tension on $mainTarget.',
      'ادفع بقوة في الرفع ثم انزل ببطء 3 ثواني للحفاظ على الشد على $mainTarget.',
    );
  }

  Widget _buildNeonCta({
    required BuildContext context,
    required String label,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: 0.95),
            AppColors.primaryContainer.withValues(alpha: 0.95),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.38),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(icon, color: Colors.black),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onSurface,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPillar extends StatelessWidget {
  const _MetricPillar({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseVideoPreview extends StatelessWidget {
  const _ExerciseVideoPreview({
    required this.thumbnailUrl,
    required this.onTap,
    required this.playLabel,
  });

  final String? thumbnailUrl;
  final VoidCallback? onTap;
  final String playLabel;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: AppColors.surfaceHigh,
        child: InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailUrl != null)
                  Image.network(
                    thumbnailUrl!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    cacheWidth: 640,
                    errorBuilder: (context, error, stackTrace) =>
                        _PreviewFallback(iconColor: primary, text: playLabel),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }
                      return Container(
                        color: AppColors.surfaceHighest,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primary,
                          ),
                        ),
                      );
                    },
                  )
                else
                  _PreviewFallback(iconColor: primary, text: playLabel),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.44),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 44,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback({required this.iconColor, required this.text});

  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceHighest,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.ondemand_video_rounded, color: iconColor, size: 28),
          const SizedBox(height: 6),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
