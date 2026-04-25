import 'app_user.dart';

class CoachProfileListing {
  const CoachProfileListing({
    required this.coachId,
    required this.name,
    required this.avatarUrl,
    required this.location,
    required this.whatsappNumber,
    required this.yearsExperience,
    required this.clientsCoached,
    required this.subscriptionPrice,
    required this.paymentMethods,
    required this.coachingSystem,
    required this.bio,
  });

  final String coachId;
  final String name;
  final String avatarUrl;
  final String location;
  final String whatsappNumber;
  final int yearsExperience;
  final int clientsCoached;
  final double subscriptionPrice;
  final List<String> paymentMethods;
  final String coachingSystem;
  final String bio;

  factory CoachProfileListing.fromMap(Map<String, dynamic> map) {
    final profileRaw = map['profile'];
    final profile = profileRaw is Map<String, dynamic>
        ? profileRaw
        : profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : <String, dynamic>{};

    return CoachProfileListing(
      coachId: (map['coach_id'] ?? profile['id'] ?? '').toString(),
      name: (profile['name'] ?? '').toString(),
      avatarUrl: (profile['avatar_url'] ?? '').toString(),
      location: (profile['location'] ?? '').toString(),
      whatsappNumber: (map['whatsapp_number'] ?? '').toString(),
      yearsExperience: _asInt(map['years_experience']) ?? 0,
      clientsCoached: _asInt(map['clients_coached']) ?? 0,
      subscriptionPrice: _asDouble(map['subscription_price']) ?? 0,
      paymentMethods: _asStringList(map['payment_methods']),
      coachingSystem: (map['coaching_system'] ?? '').toString(),
      bio: (map['bio'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toUpsertMap() {
    return {
      'coach_id': coachId,
      'whatsapp_number': whatsappNumber,
      'years_experience': yearsExperience,
      'clients_coached': clientsCoached,
      'subscription_price': subscriptionPrice,
      'payment_methods': paymentMethods,
      'coaching_system': coachingSystem,
      'bio': bio,
      'updated_at': DateTime.now().toIso8601String(),
    };
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

  static List<String> _asStringList(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw.map((item) => item.toString()).toList();
  }
}

class CoachMessage {
  const CoachMessage({
    required this.id,
    required this.coachId,
    required this.traineeId,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String coachId;
  final String traineeId;
  final String senderId;
  final String content;
  final DateTime createdAt;

  bool isFrom(String userId) => senderId == userId;

  factory CoachMessage.fromMap(Map<String, dynamic> map) {
    return CoachMessage(
      id: (map['id'] ?? '').toString(),
      coachId: (map['coach_id'] ?? '').toString(),
      traineeId: (map['trainee_id'] ?? '').toString(),
      senderId: (map['sender_id'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class CoachSplitSuggestion {
  const CoachSplitSuggestion({
    required this.id,
    required this.coachId,
    required this.traineeId,
    required this.systemName,
    required this.note,
    required this.createdAt,
    required this.splitData,
  });

  final String id;
  final String coachId;
  final String traineeId;
  final String systemName;
  final String note;
  final DateTime createdAt;
  final Map<String, dynamic> splitData;

  factory CoachSplitSuggestion.fromMap(Map<String, dynamic> map) {
    final splitRaw = map['split_data'];
    final splitData = splitRaw is Map<String, dynamic>
        ? splitRaw
        : splitRaw is Map
        ? Map<String, dynamic>.from(splitRaw)
        : <String, dynamic>{};

    return CoachSplitSuggestion(
      id: (map['id'] ?? '').toString(),
      coachId: (map['coach_id'] ?? '').toString(),
      traineeId: (map['trainee_id'] ?? '').toString(),
      systemName: (map['system_name'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
      splitData: splitData,
    );
  }
}

class CoachTraineeSnapshot {
  const CoachTraineeSnapshot({
    required this.profile,
    required this.currentSplitName,
    required this.rehabMetrics,
    required this.sessionCount,
    required this.lastSessionAt,
  });

  final AppUser profile;
  final String currentSplitName;
  final Map<String, dynamic> rehabMetrics;
  final int sessionCount;
  final DateTime? lastSessionAt;
}
