import 'package:shared_preferences/shared_preferences.dart';

import '../localization/egyptian_gym_lexicon.dart';

const List<String> _seedExerciseCatalog = [
  'Bench Press (Barbell)',
  'Incline Bench Press (Barbell)',
  'Decline Bench Press (Barbell)',
  'Dumbbell Bench Press',
  'Squat (High Bar)',
  'Squat (Low Bar)',
  'Front Squat',
  'Deadlift (Conventional)',
  'Deadlift (Sumo)',
  'Romanian Deadlift',
  'Overhead Press (Barbell)',
  'Dumbbell Shoulder Press',
  'Barbell Row',
  'Pull Ups',
  'Chin Ups',
  'Dips',
  'Push Ups',
  'Diamond Push Ups',
  'Pike Push Ups',
  'Bodyweight Squat',
  'Pistol Squat',
  'Lat Pulldown',
  'Leg Press',
  'Bicep Curls (Dumbbell)',
  'Tricep Extensions',
  'Lateral Raises',
  'Face Pulls',
];

const Set<String> _seedBodyweightExercises = {
  'Pull Ups',
  'Chin Ups',
  'Dips',
  'Push Ups',
  'Diamond Push Ups',
  'Pike Push Ups',
  'Bodyweight Squat',
  'Pistol Squat',
};

class ExerciseDatabase {
  ExerciseDatabase._();

  static final ExerciseDatabase instance = ExerciseDatabase._();

  static const _catalogKey = 'exercise_database.catalog';
  static const _bodyweightKey = 'exercise_database.bodyweight';

  List<String> _catalog = List.unmodifiable(_seedExerciseCatalog);
  Set<String> _bodyweightExercises = Set.unmodifiable(_seedBodyweightExercises);
  bool _hydrated = false;

  List<String> get catalog => _catalog;

  Set<String> get bodyweightExercises => _bodyweightExercises;

  bool get hydrated => _hydrated;

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();

    final storedCatalog = prefs.getStringList(_catalogKey);
    final storedBodyweight = prefs.getStringList(_bodyweightKey);

    final catalog = _normalizeCatalog(storedCatalog);
    final bodyweight = _normalizeBodyweight(storedBodyweight);

    _catalog = List.unmodifiable(catalog);
    _bodyweightExercises = Set.unmodifiable(bodyweight);
    _hydrated = true;

    if (storedCatalog == null || storedCatalog.isEmpty) {
      await prefs.setStringList(_catalogKey, catalog);
    }

    if (storedBodyweight == null || storedBodyweight.isEmpty) {
      await prefs.setStringList(
        _bodyweightKey,
        bodyweight.toList()..sort(),
      );
    }
  }

  List<String> suggestions(String query, {int limit = 10}) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return _catalog.take(limit).toList();
    }

    return _catalog
        .where((exercise) {
          final english = exercise.toLowerCase();
          final arabic = EgyptianGymLexicon.term(exercise).toLowerCase();
          return english.contains(normalized) || arabic.contains(normalized);
        })
        .take(limit)
        .toList();
  }

  bool isBodyweight(String exercise) => _bodyweightExercises.contains(exercise);

  List<String> _normalizeCatalog(List<String>? raw) {
    final source = raw == null || raw.isEmpty ? _seedExerciseCatalog : raw;
    return source
        .map((exercise) => exercise.trim())
        .where((exercise) => exercise.isNotEmpty)
        .toList(growable: false);
  }

  Set<String> _normalizeBodyweight(List<String>? raw) {
    final source =
        raw == null || raw.isEmpty ? _seedBodyweightExercises.toList() : raw;
    return source
        .map((exercise) => exercise.trim())
        .where((exercise) => exercise.isNotEmpty)
        .toSet();
  }
}

List<String> get exerciseCatalog => ExerciseDatabase.instance.catalog;

Set<String> get bodyweightExercises => ExerciseDatabase.instance.bodyweightExercises;
