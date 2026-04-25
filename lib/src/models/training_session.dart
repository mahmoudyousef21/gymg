import 'lift_entry.dart';

class TrainingSession {
  const TrainingSession({
    required this.id,
    required this.userId,
    required this.name,
    required this.sessionDate,
    required this.lifts,
  });

  final String id;
  final String userId;
  final String name;
  final DateTime sessionDate;
  final List<LiftEntry> lifts;

  bool get isToday {
    final now = DateTime.now();
    return now.year == sessionDate.year &&
        now.month == sessionDate.month &&
        now.day == sessionDate.day;
  }

  TrainingSession copyWith({
    String? id,
    String? userId,
    String? name,
    DateTime? sessionDate,
    List<LiftEntry>? lifts,
  }) {
    return TrainingSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      sessionDate: sessionDate ?? this.sessionDate,
      lifts: lifts ?? this.lifts,
    );
  }

  factory TrainingSession.fromMap(Map<String, dynamic> map) {
    final dynamicLifts = map['lifts'];
    final parsedLifts = dynamicLifts is List
        ? dynamicLifts.map(LiftEntry.fromDynamic).toList()
        : <LiftEntry>[];

    return TrainingSession(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      sessionDate:
          DateTime.tryParse((map['session_date'] ?? '').toString()) ??
          DateTime.now(),
      lifts: parsedLifts,
    );
  }
}
