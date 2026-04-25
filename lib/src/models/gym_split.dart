class ExerciseEntry {
  const ExerciseEntry({
    required this.name,
    required this.nameAr,
    required this.sets,
    required this.reps,
    required this.youtubeId,
    this.videoUrl = '',
    this.thumbnailUrl,
    required this.primaryMuscles,
    required this.primaryMusclesAr,
    required this.variations,
    required this.variationsAr,
  });

  final String name;
  final String nameAr;
  final int sets;
  final String reps;
  final String youtubeId;
  final String videoUrl;
  final String? thumbnailUrl;
  final List<String> primaryMuscles;
  final List<String> primaryMusclesAr;
  final List<String> variations;
  final List<String> variationsAr;

  bool get isYouTube => youtubeId.trim().isNotEmpty;

  String? get playbackUrl {
    if (isYouTube) {
      return 'https://www.youtube.com/watch?v=$youtubeId';
    }

    final hosted = videoUrl.trim();
    if (hosted.isEmpty) {
      return null;
    }
    return hosted;
  }

  String? get previewThumbnailUrl {
    final explicit = thumbnailUrl?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    if (isYouTube) {
      return 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';
    }

    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'nameAr': nameAr,
      'sets': sets,
      'reps': reps,
      'youtubeId': youtubeId,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'primaryMuscles': primaryMuscles,
      'primaryMusclesAr': primaryMusclesAr,
      'variations': variations,
      'variationsAr': variationsAr,
    };
  }

  factory ExerciseEntry.fromMap(Map<String, dynamic> map) {
    return ExerciseEntry(
      name: (map['name'] ?? '').toString(),
      nameAr: (map['nameAr'] ?? '').toString(),
      sets: _asInt(map['sets']) ?? 0,
      reps: (map['reps'] ?? '').toString(),
      youtubeId: (map['youtubeId'] ?? '').toString(),
      videoUrl: (map['videoUrl'] ?? '').toString(),
      thumbnailUrl: map['thumbnailUrl']?.toString(),
      primaryMuscles: _asStringList(map['primaryMuscles']),
      primaryMusclesAr: _asStringList(map['primaryMusclesAr']),
      variations: _asStringList(map['variations']),
      variationsAr: _asStringList(map['variationsAr']),
    );
  }
}

class GymSplitDay {
  const GymSplitDay({
    required this.label,
    required this.labelAr,
    required this.muscles,
    required this.musclesAr,
    required this.exercises,
  });

  final String label;
  final String labelAr;
  final List<String> muscles;
  final List<String> musclesAr;
  final List<ExerciseEntry> exercises;

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'labelAr': labelAr,
      'muscles': muscles,
      'musclesAr': musclesAr,
      'exercises': exercises.map((exercise) => exercise.toMap()).toList(),
    };
  }

  factory GymSplitDay.fromMap(Map<String, dynamic> map) {
    final exercisesRaw = map['exercises'];
    final exercises = exercisesRaw is List
        ? exercisesRaw
              .whereType<Map>()
              .map(
                (exercise) =>
                    ExerciseEntry.fromMap(Map<String, dynamic>.from(exercise)),
              )
              .toList()
        : <ExerciseEntry>[];

    return GymSplitDay(
      label: (map['label'] ?? '').toString(),
      labelAr: (map['labelAr'] ?? '').toString(),
      muscles: _asStringList(map['muscles']),
      musclesAr: _asStringList(map['musclesAr']),
      exercises: exercises,
    );
  }
}

class GymSplit {
  const GymSplit({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.description,
    required this.descriptionAr,
    required this.daysPerWeek,
    required this.days,
  });

  final String id;
  final String name;
  final String nameAr;
  final String description;
  final String descriptionAr;
  final int daysPerWeek;
  final List<GymSplitDay> days;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'nameAr': nameAr,
      'description': description,
      'descriptionAr': descriptionAr,
      'daysPerWeek': daysPerWeek,
      'days': days.map((day) => day.toMap()).toList(),
    };
  }

  factory GymSplit.fromMap(Map<String, dynamic> map) {
    final daysRaw = map['days'];
    final days = daysRaw is List
        ? daysRaw
              .whereType<Map>()
              .map((day) => GymSplitDay.fromMap(Map<String, dynamic>.from(day)))
              .toList()
        : <GymSplitDay>[];

    return GymSplit(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      nameAr: (map['nameAr'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      descriptionAr: (map['descriptionAr'] ?? '').toString(),
      daysPerWeek: _asInt(map['daysPerWeek']) ?? 0,
      days: days,
    );
  }
}

class SplitScheduleEntry {
  const SplitScheduleEntry({
    required this.label,
    required this.labelAr,
    required this.muscles,
    required this.musclesAr,
    required this.exercises,
    required this.date,
    required this.completed,
  });

  final String label;
  final String labelAr;
  final List<String> muscles;
  final List<String> musclesAr;
  final List<ExerciseEntry> exercises;
  final DateTime date;
  final bool completed;

  SplitScheduleEntry copyWith({
    String? label,
    String? labelAr,
    List<String>? muscles,
    List<String>? musclesAr,
    List<ExerciseEntry>? exercises,
    DateTime? date,
    bool? completed,
  }) {
    return SplitScheduleEntry(
      label: label ?? this.label,
      labelAr: labelAr ?? this.labelAr,
      muscles: muscles ?? this.muscles,
      musclesAr: musclesAr ?? this.musclesAr,
      exercises: exercises ?? this.exercises,
      date: date ?? this.date,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'labelAr': labelAr,
      'muscles': muscles,
      'musclesAr': musclesAr,
      'exercises': exercises.map((exercise) => exercise.toMap()).toList(),
      'date': date.toIso8601String(),
      'completed': completed,
    };
  }

  factory SplitScheduleEntry.fromMap(Map<String, dynamic> map) {
    final exercisesRaw = map['exercises'];
    final exercises = exercisesRaw is List
        ? exercisesRaw
              .whereType<Map>()
              .map(
                (exercise) =>
                    ExerciseEntry.fromMap(Map<String, dynamic>.from(exercise)),
              )
              .toList()
        : <ExerciseEntry>[];

    return SplitScheduleEntry(
      label: (map['label'] ?? '').toString(),
      labelAr: (map['labelAr'] ?? '').toString(),
      muscles: _asStringList(map['muscles']),
      musclesAr: _asStringList(map['musclesAr']),
      exercises: exercises,
      date: DateTime.tryParse((map['date'] ?? '').toString()) ?? DateTime.now(),
      completed: _asBool(map['completed']),
    );
  }
}

class SplitSchedule {
  const SplitSchedule({
    required this.splitId,
    required this.splitName,
    required this.splitNameAr,
    required this.daysPerWeek,
    required this.currentDayIndex,
    required this.schedule,
  });

  final String splitId;
  final String splitName;
  final String splitNameAr;
  final int daysPerWeek;
  final int currentDayIndex;
  final List<SplitScheduleEntry> schedule;

  SplitSchedule copyWith({
    String? splitId,
    String? splitName,
    String? splitNameAr,
    int? daysPerWeek,
    int? currentDayIndex,
    List<SplitScheduleEntry>? schedule,
  }) {
    return SplitSchedule(
      splitId: splitId ?? this.splitId,
      splitName: splitName ?? this.splitName,
      splitNameAr: splitNameAr ?? this.splitNameAr,
      daysPerWeek: daysPerWeek ?? this.daysPerWeek,
      currentDayIndex: currentDayIndex ?? this.currentDayIndex,
      schedule: schedule ?? this.schedule,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'splitId': splitId,
      'splitName': splitName,
      'splitNameAr': splitNameAr,
      'daysPerWeek': daysPerWeek,
      'currentDayIndex': currentDayIndex,
      'schedule': schedule.map((entry) => entry.toMap()).toList(),
    };
  }

  factory SplitSchedule.fromMap(Map<String, dynamic> map) {
    final scheduleRaw = map['schedule'];
    final schedule = scheduleRaw is List
        ? scheduleRaw
              .whereType<Map>()
              .map(
                (entry) => SplitScheduleEntry.fromMap(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .toList()
        : <SplitScheduleEntry>[];

    return SplitSchedule(
      splitId: (map['splitId'] ?? '').toString(),
      splitName: (map['splitName'] ?? '').toString(),
      splitNameAr: (map['splitNameAr'] ?? '').toString(),
      daysPerWeek: _asInt(map['daysPerWeek']) ?? 0,
      currentDayIndex: _asInt(map['currentDayIndex']) ?? 0,
      schedule: schedule,
    );
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

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return <String>[];
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  final normalized = value?.toString().toLowerCase();
  return normalized == 'true' || normalized == '1';
}
