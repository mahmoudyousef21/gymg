import 'dart:math' as math;

import 'lift_entry.dart';

enum FeedPostType { session, challenge, text }

class SocialComment {
  const SocialComment({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String content;
  final DateTime createdAt;

  factory SocialComment.fromMap(Map<String, dynamic> map) {
    final profileRaw = map['profiles'];
    final profile = profileRaw is List
        ? (profileRaw.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(profileRaw.first as Map))
        : profileRaw is Map<String, dynamic>
        ? profileRaw
        : profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : <String, dynamic>{};

    return SocialComment(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      userName: (profile['name'] ?? 'Athlete').toString(),
      userAvatar: (profile['avatar_url'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class ChallengeApplication {
  const ChallengeApplication({
    required this.applicantUserId,
    required this.coachId,
    required this.applicantName,
    required this.applicantAvatar,
    required this.createdAt,
  });

  final String applicantUserId;
  final String coachId;
  final String applicantName;
  final String applicantAvatar;
  final DateTime createdAt;

  factory ChallengeApplication.fromMap(Map<String, dynamic> map) {
    final profileRaw = map['profiles'];
    final profile = profileRaw is List
        ? (profileRaw.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(profileRaw.first as Map))
        : profileRaw is Map<String, dynamic>
        ? profileRaw
        : profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : <String, dynamic>{};

    return ChallengeApplication(
      applicantUserId: (map['applicant_user_id'] ?? '').toString(),
      coachId: (map['coach_id'] ?? '').toString(),
      applicantName: (profile['name'] ?? 'Athlete').toString(),
      applicantAvatar: (profile['avatar_url'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class SocialPost {
  const SocialPost({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.userTier,
    required this.postType,
    required this.content,
    required this.sessionName,
    required this.location,
    required this.timestamp,
    required this.lifts,
    required this.volume,
    required this.durationMinutes,
    required this.sets,
    required this.intensity,
    required this.reactionCounts,
    required this.comments,
    required this.challengeApplicants,
    this.myReaction,
    this.challengeType,
    this.challengeExercise,
    this.challengeTargetKg,
  });

  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String userTier;
  final FeedPostType postType;
  final String content;
  final String sessionName;
  final String location;
  final DateTime timestamp;
  final List<LiftEntry> lifts;
  final double volume;
  final int durationMinutes;
  final int sets;
  final double intensity;
  final Map<String, int> reactionCounts;
  final List<SocialComment> comments;
  final List<ChallengeApplication> challengeApplicants;
  final String? myReaction;
  final String? challengeType;
  final String? challengeExercise;
  final double? challengeTargetKg;

  int get hypeCount => reactionCounts['hype'] ?? 0;
  int get chalkCount => comments.length;
  int get fireCount => reactionCounts['fire'] ?? 0;
  int get respectCount => reactionCounts['respect'] ?? 0;
  int get beastCount => reactionCounts['beast'] ?? 0;

  bool get isChallenge => postType == FeedPostType.challenge;
  bool get isText => postType == FeedPostType.text;
  bool get isSession => postType == FeedPostType.session;
  int get challengeApplicantCount => challengeApplicants.length;

  bool hasApplied(String userId) {
    return challengeApplicants.any(
      (application) => application.applicantUserId == userId,
    );
  }

  static FeedPostType _parsePostType(String raw) {
    return switch (raw) {
      'challenge' => FeedPostType.challenge,
      'text' => FeedPostType.text,
      _ => FeedPostType.session,
    };
  }

  static Map<String, int> _reactionCounts(dynamic rows) {
    final counts = <String, int>{};
    if (rows is! List) {
      return counts;
    }

    for (final row in rows) {
      if (row is! Map) {
        continue;
      }
      final type = (row['reaction_type'] ?? '').toString().trim().toLowerCase();
      if (type.isEmpty) {
        continue;
      }
      counts[type] = (counts[type] ?? 0) + 1;
    }

    return counts;
  }

  static String? _myReaction(dynamic rows, String currentUserId) {
    if (rows is! List) {
      return null;
    }

    for (final row in rows) {
      if (row is! Map) {
        continue;
      }
      final userId = (row['user_id'] ?? '').toString();
      if (userId != currentUserId) {
        continue;
      }
      final reaction = (row['reaction_type'] ?? '').toString().trim();
      if (reaction.isEmpty) {
        return null;
      }
      return reaction;
    }
    return null;
  }

  static List<SocialComment> _comments(dynamic rows) {
    if (rows is! List) {
      return const <SocialComment>[];
    }
    return rows
        .whereType<Map>()
        .map((row) => SocialComment.fromMap(Map<String, dynamic>.from(row)))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static List<ChallengeApplication> _challengeApplicants(dynamic rows) {
    if (rows is! List) {
      return const <ChallengeApplication>[];
    }

    return rows
        .whereType<Map>()
        .map(
          (row) => ChallengeApplication.fromMap(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static List<LiftEntry> _lifts(dynamic rows) {
    if (rows is! List) {
      return const <LiftEntry>[];
    }
    return rows.map(LiftEntry.fromDynamic).toList();
  }

  factory SocialPost.fromFeedMap(
    Map<String, dynamic> map, {
    required String currentUserId,
  }) {
    final profileRaw = map['profiles'];
    final profile = profileRaw is List
        ? (profileRaw.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(profileRaw.first as Map))
        : profileRaw is Map<String, dynamic>
        ? profileRaw
        : profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : <String, dynamic>{};

    final lifts = _lifts(map['lifts']);
    final volume = lifts.fold<double>(
      0,
      (sum, lift) => sum + (lift.weight * lift.reps * lift.sets),
    );
    final totalSets = lifts.fold<int>(0, (sum, lift) => sum + lift.sets);
    final averageWeight = lifts.isEmpty
        ? 0
        : lifts.fold<double>(0, (sum, lift) => sum + lift.weight) /
              lifts.length;

    final postType = _parsePostType((map['post_type'] ?? 'session').toString());

    return SocialPost(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      userName: (profile['name'] ?? 'Athlete').toString(),
      userAvatar: (profile['avatar_url'] ?? '').toString(),
      userTier: (profile['tier'] ?? 'IRON').toString(),
      postType: postType,
      content: (map['content'] ?? '').toString(),
      sessionName: (map['session_name'] ?? map['name'] ?? 'Workout Session')
          .toString(),
      location: (profile['location'] ?? 'Global').toString(),
      timestamp:
          DateTime.tryParse(
            (map['created_at'] ?? map['session_date'] ?? '').toString(),
          ) ??
          DateTime.now(),
      lifts: lifts,
      volume: volume,
      durationMinutes: math.max(20, lifts.length * 4),
      sets: totalSets,
      intensity: averageWeight == 0
          ? 5
          : (averageWeight / 20).clamp(5, 10).toDouble(),
      reactionCounts: _reactionCounts(map['social_reactions']),
      comments: _comments(map['social_comments']),
      challengeApplicants: _challengeApplicants(
        map['social_challenge_applications'],
      ),
      myReaction: _myReaction(map['social_reactions'], currentUserId),
      challengeType: map['challenge_type']?.toString(),
      challengeExercise: map['challenge_exercise']?.toString(),
      challengeTargetKg: _asDouble(map['challenge_target_kg']),
    );
  }

  factory SocialPost.fromTrainingSessionMap(
    Map<String, dynamic> map, {
    required String currentUserId,
  }) {
    final profileRaw = map['profiles'];
    final profile = profileRaw is List
        ? (profileRaw.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(profileRaw.first as Map))
        : profileRaw is Map<String, dynamic>
        ? profileRaw
        : profileRaw is Map
        ? Map<String, dynamic>.from(profileRaw)
        : <String, dynamic>{};

    final lifts = _lifts(map['lifts']);
    final volume = lifts.fold<double>(
      0,
      (sum, lift) => sum + (lift.weight * lift.reps * lift.sets),
    );
    final totalSets = lifts.fold<int>(0, (sum, lift) => sum + lift.sets);
    final averageWeight = lifts.isEmpty
        ? 0
        : lifts.fold<double>(0, (sum, lift) => sum + lift.weight) /
              lifts.length;

    return SocialPost(
      id: (map['id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      userName: (profile['name'] ?? 'Athlete').toString(),
      userAvatar: (profile['avatar_url'] ?? '').toString(),
      userTier: (profile['tier'] ?? 'IRON').toString(),
      postType: FeedPostType.session,
      content: '',
      sessionName: (map['name'] ?? 'Workout Session').toString(),
      location: (profile['location'] ?? 'Global').toString(),
      timestamp:
          DateTime.tryParse((map['session_date'] ?? '').toString()) ??
          DateTime.now(),
      lifts: lifts,
      volume: volume,
      durationMinutes: math.max(20, lifts.length * 4),
      sets: totalSets,
      intensity: averageWeight == 0
          ? 5
          : (averageWeight / 20).clamp(5, 10).toDouble(),
      reactionCounts: <String, int>{
        'hype': math.max(1, (volume / 100).round()),
        'fire': math.max(1, (averageWeight / 10).round()),
      },
      comments: const <SocialComment>[],
      challengeApplicants: const <ChallengeApplication>[],
      myReaction: null,
      challengeType: null,
      challengeExercise: null,
      challengeTargetKg: null,
    );
  }

  static double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
