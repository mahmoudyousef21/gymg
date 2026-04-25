import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/splits_catalog.dart';
import '../models/app_user.dart';
import '../models/coach_hub.dart';
import '../models/gym_news.dart';
import '../models/gym_split.dart';
import '../models/leaderboard_athlete.dart';
import '../models/lift_entry.dart';
import '../models/social_post.dart';
import '../models/training_session.dart';

class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();
  final Uuid _uuid = const Uuid();
  static const _splitScheduleCachePrefix = 'cached_split_schedule.';

  SupabaseClient get _client => Supabase.instance.client;

  Future<AppUser?> fetchProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) {
      return null;
    }
    return AppUser.fromMap(data);
  }

  Future<void> upsertProfile(AppUser profile) async {
    await _client.from('profiles').upsert(profile.toUpsertMap());
  }

  Future<String> uploadProfileAvatar({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final cleanedExtension = extension
        .trim()
        .toLowerCase()
        .replaceAll('.', '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final resolvedExtension = cleanedExtension.isEmpty
        ? 'jpg'
        : cleanedExtension;

    final contentType = switch (resolvedExtension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    final path =
        '$userId/${DateTime.now().millisecondsSinceEpoch}.$resolvedExtension';

    await _client.storage.from('profile-avatars').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: contentType,
      ),
    );

    return _client.storage.from('profile-avatars').getPublicUrl(path);
  }

  Future<void> updateProfileAvatar({
    required String userId,
    required String avatarUrl,
  }) async {
    await _client
        .from('profiles')
        .update({
          'avatar_url': avatarUrl.trim().isEmpty ? null : avatarUrl.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  Future<void> upsertCoachProfile({
    required String coachId,
    required String whatsappNumber,
    required int yearsExperience,
    required int clientsCoached,
    required double subscriptionPrice,
    required List<String> paymentMethods,
    required String coachingSystem,
    required String bio,
  }) async {
    await _client.from('coach_profiles').upsert({
      'coach_id': coachId,
      'whatsapp_number': whatsappNumber,
      'years_experience': yearsExperience,
      'clients_coached': clientsCoached,
      'subscription_price': subscriptionPrice,
      'payment_methods': paymentMethods,
      'coaching_system': coachingSystem,
      'bio': bio,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<CoachProfileListing?> fetchCoachProfile(String coachId) async {
    final row = await _client
        .from('coach_profiles')
        .select(
          'coach_id, whatsapp_number, years_experience, clients_coached, subscription_price, payment_methods, coaching_system, bio, profile:profiles!coach_profiles_coach_id_fkey(id, name, avatar_url, location)',
        )
        .eq('coach_id', coachId)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    return CoachProfileListing.fromMap(row);
  }

  Future<List<CoachProfileListing>> fetchCoachMarketplace({
    required String currentUserId,
  }) async {
    final rows = await _client
        .from('coach_profiles')
        .select(
          'coach_id, whatsapp_number, years_experience, clients_coached, subscription_price, payment_methods, coaching_system, bio, profile:profiles!coach_profiles_coach_id_fkey(id, name, avatar_url, location)',
        )
        .neq('coach_id', currentUserId)
        .order('subscription_price', ascending: true);

    return (rows as List<dynamic>)
        .whereType<Map>()
        .map((row) => CoachProfileListing.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> assignCoachToTrainee({
    required String traineeId,
    required String coachId,
  }) async {
    await _client.from('coach_subscriptions').upsert({
      'trainee_id': traineeId,
      'coach_id': coachId,
      'status': 'active',
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<CoachProfileListing?> fetchAssignedCoachForTrainee(
    String traineeId,
  ) async {
    final row = await _client
        .from('coach_subscriptions')
        .select('coach_id')
        .eq('trainee_id', traineeId)
        .eq('status', 'active')
        .maybeSingle();

    if (row == null) {
      return null;
    }

    final coachId = (row['coach_id'] ?? '').toString();
    if (coachId.isEmpty) {
      return null;
    }

    return fetchCoachProfile(coachId);
  }

  Future<List<CoachTraineeSnapshot>> fetchCoachTrainees(
    String coachId,
  ) async {
    final subscriptionRows = await _client
        .from('coach_subscriptions')
        .select('trainee_id')
        .eq('coach_id', coachId)
        .eq('status', 'active');

    final traineeIds = (subscriptionRows as List<dynamic>)
        .whereType<Map>()
        .map((row) => (row['trainee_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (traineeIds.isEmpty) {
      return const <CoachTraineeSnapshot>[];
    }

    final profileRows = await _client
        .from('profiles')
        .select('*')
        .inFilter('id', traineeIds);

    final splitRows = await _client
        .from('user_split_schedules')
        .select('user_id, split_data')
        .inFilter('user_id', traineeIds);

    final sessionRows = await _client
        .from('training_sessions')
        .select('user_id, session_date')
        .inFilter('user_id', traineeIds);

    final splitNameByUser = <String, String>{};
    for (final row in (splitRows as List<dynamic>).whereType<Map>()) {
      final userId = (row['user_id'] ?? '').toString();
      final splitRaw = row['split_data'];
      final splitMap = _mapFromDynamic(splitRaw);
      final template = splitMap == null ? null : _localSplitTemplate(splitMap);
      final splitName = _firstNonEmpty([
        splitMap?['splitName']?.toString(),
        splitMap?['name']?.toString(),
        splitMap?['splitNameAr']?.toString(),
        template?.name,
        template?.nameAr,
      ]);
      if (userId.isNotEmpty && splitName.isNotEmpty) {
        splitNameByUser[userId] = splitName;
      }
    }

    final sessionCountByUser = <String, int>{};
    final lastSessionByUser = <String, DateTime>{};
    for (final row in (sessionRows as List<dynamic>).whereType<Map>()) {
      final userId = (row['user_id'] ?? '').toString();
      if (userId.isEmpty) {
        continue;
      }
      sessionCountByUser[userId] = (sessionCountByUser[userId] ?? 0) + 1;

      final parsedDate = DateTime.tryParse((row['session_date'] ?? '').toString());
      if (parsedDate == null) {
        continue;
      }
      final currentLast = lastSessionByUser[userId];
      if (currentLast == null || parsedDate.isAfter(currentLast)) {
        lastSessionByUser[userId] = parsedDate;
      }
    }

    final snapshots = <CoachTraineeSnapshot>[];
    for (final row in (profileRows as List<dynamic>).whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final profile = AppUser.fromMap(map);
      final metricsRaw = map['rehab_metrics'];
      final rehabMetrics = metricsRaw is Map<String, dynamic>
          ? metricsRaw
          : metricsRaw is Map
          ? Map<String, dynamic>.from(metricsRaw)
          : const <String, dynamic>{};

      snapshots.add(
        CoachTraineeSnapshot(
          profile: profile,
          currentSplitName: splitNameByUser[profile.id] ?? '',
          rehabMetrics: rehabMetrics,
          sessionCount: sessionCountByUser[profile.id] ?? 0,
          lastSessionAt: lastSessionByUser[profile.id],
        ),
      );
    }

    snapshots.sort((a, b) => a.profile.name.compareTo(b.profile.name));
    return snapshots;
  }

  Future<List<CoachMessage>> fetchCoachMessages({
    required String coachId,
    required String traineeId,
  }) async {
    final rows = await _client
        .from('coach_messages')
        .select('id, coach_id, trainee_id, sender_id, content, created_at')
        .eq('coach_id', coachId)
        .eq('trainee_id', traineeId)
        .order('created_at', ascending: true)
        .limit(100);

    return (rows as List<dynamic>)
        .whereType<Map>()
        .map((row) => CoachMessage.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> sendCoachMessage({
    required String coachId,
    required String traineeId,
    required String senderId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await _client.from('coach_messages').insert({
      'coach_id': coachId,
      'trainee_id': traineeId,
      'sender_id': senderId,
      'content': trimmed,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> createCoachSplitSuggestion({
    required String coachId,
    required String traineeId,
    required String systemName,
    required String note,
    required Map<String, dynamic> splitData,
  }) async {
    await _client.from('coach_split_suggestions').insert({
      'coach_id': coachId,
      'trainee_id': traineeId,
      'system_name': systemName,
      'note': note.trim(),
      'split_data': splitData,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> assignCoachCustomSplitToTrainee({
    required String coachId,
    required String traineeId,
    required SplitSchedule schedule,
    String note = '',
  }) async {
    try {
      await _client.rpc(
        'coach_assign_split_to_trainee',
        params: {
          'p_coach_id': coachId,
          'p_trainee_id': traineeId,
          'p_system_name': schedule.splitName,
          'p_note': note.trim(),
          'p_split_data': schedule.toMap(),
        },
      );
      return;
    } catch (error, stackTrace) {
      dev.log(
        'coach_assign_split_to_trainee RPC failed. Falling back to suggestion only.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
    }

    await createCoachSplitSuggestion(
      coachId: coachId,
      traineeId: traineeId,
      systemName: schedule.splitName,
      note: note,
      splitData: schedule.toMap(),
    );
  }

  Future<List<CoachSplitSuggestion>> fetchTraineeSplitSuggestions(
    String traineeId,
  ) async {
    final rows = await _client
        .from('coach_split_suggestions')
        .select('id, coach_id, trainee_id, system_name, note, split_data, created_at')
        .eq('trainee_id', traineeId)
        .order('created_at', ascending: false)
        .limit(20);

    return (rows as List<dynamic>)
        .whereType<Map>()
        .map(
          (row) => CoachSplitSuggestion.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<Map<String, dynamic>> fetchRehabMetrics(String userId) async {
    final row = await _client
        .from('profiles')
        .select('rehab_metrics')
        .eq('id', userId)
        .maybeSingle();

    if (row == null) {
      return <String, dynamic>{};
    }

    final metrics = row['rehab_metrics'];
    if (metrics is Map<String, dynamic>) {
      return metrics;
    }
    if (metrics is Map) {
      return Map<String, dynamic>.from(metrics);
    }

    return <String, dynamic>{};
  }

  Future<void> upsertRehabMetrics({
    required String userId,
    required Map<String, dynamic> metrics,
  }) async {
    final existing = await fetchRehabMetrics(userId);
    final merged = <String, dynamic>{...existing, ...metrics};

    await _client
        .from('profiles')
        .update({
          'rehab_metrics': merged,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  Future<List<TrainingSession>> fetchTrainingSessions(String userId) async {
    final rows = await _client
        .from('training_sessions')
        .select('id, user_id, name, session_date, lifts')
        .eq('user_id', userId)
        .order('session_date', ascending: false);

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(TrainingSession.fromMap)
        .toList();
  }

  Future<List<SocialPost>> fetchSocialFeed({int limit = 50}) async {
    throw UnimplementedError(
      'Use fetchSocialFeedWithContext(currentUserId: ...) instead.',
    );
  }

  Future<List<SocialPost>> fetchSocialFeedWithContext({
    required String currentUserId,
    int limit = 50,
  }) async {
    try {
      List<dynamic> rows;
      try {
        final richRows = await _client
            .from('social_posts')
            .select(
              'id, user_id, post_type, content, session_name, lifts, challenge_type, challenge_exercise, challenge_target_kg, created_at, profiles:user_id(name, avatar_url, tier, location), social_reactions(user_id, reaction_type), social_comments(id, user_id, content, created_at, profiles:user_id(name, avatar_url)), social_challenge_applications(applicant_user_id, coach_id, created_at, profiles:applicant_user_id(name, avatar_url))',
            )
            .order('created_at', ascending: false)
            .limit(limit);

        rows = (richRows as List<dynamic>);
      } catch (_) {
        final legacyRows = await _client
            .from('social_posts')
            .select(
              'id, user_id, post_type, content, session_name, lifts, challenge_type, challenge_exercise, challenge_target_kg, created_at, profiles:user_id(name, avatar_url, tier, location), social_reactions(user_id, reaction_type), social_comments(id, user_id, content, created_at, profiles:user_id(name, avatar_url))',
            )
            .order('created_at', ascending: false)
            .limit(limit);

        rows = (legacyRows as List<dynamic>);
      }

      final parsed = rows
          .whereType<Map>()
          .map(
            (row) => SocialPost.fromFeedMap(
              Map<String, dynamic>.from(row),
              currentUserId: currentUserId,
            ),
          )
          .toList();

      if (parsed.isNotEmpty) {
        return parsed;
      }
    } catch (error, stackTrace) {
      dev.log(
        'social_posts read failed, falling back to training_sessions feed.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final fallbackRows = await _client
        .from('training_sessions')
        .select(
          'id, user_id, name, session_date, lifts, profiles:user_id(name, avatar_url, tier, location)',
        )
        .order('session_date', ascending: false)
        .limit(limit);

    return (fallbackRows as List<dynamic>)
        .whereType<Map>()
        .map(
          (row) => SocialPost.fromTrainingSessionMap(
            Map<String, dynamic>.from(row),
            currentUserId: currentUserId,
          ),
        )
        .toList();
  }

  Future<void> createSessionFeedPost({
    required String userId,
    required String sessionName,
    required List<LiftEntry> lifts,
    String? content,
  }) async {
    final payload = _sanitizeLiftPayload(lifts);
    if (payload.isEmpty) {
      return;
    }

    await _client.from('social_posts').insert({
      'user_id': userId,
      'post_type': 'session',
      'content': content?.trim() ?? '',
      'session_name': sessionName,
      'lifts': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> createChallengePost({
    required String userId,
    required String challengeType,
    required String exerciseName,
    required double targetKg,
    String? content,
  }) async {
    await _client.from('social_posts').insert({
      'user_id': userId,
      'post_type': 'challenge',
      'content': content?.trim() ?? '',
      'challenge_type': challengeType,
      'challenge_exercise': exerciseName,
      'challenge_target_kg': targetKg,
      'lifts': <Map<String, dynamic>>[],
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> applyToChallenge({
    required String challengePostId,
    required String applicantUserId,
    required String coachId,
    String note = '',
  }) async {
    await _client.from('social_challenge_applications').upsert(
      {
        'challenge_post_id': challengePostId,
        'applicant_user_id': applicantUserId,
        'coach_id': coachId,
        'note': note.trim(),
        'created_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'challenge_post_id,applicant_user_id',
    );
  }

  Future<void> withdrawFromChallenge({
    required String challengePostId,
    required String applicantUserId,
  }) async {
    await _client
        .from('social_challenge_applications')
        .delete()
        .eq('challenge_post_id', challengePostId)
        .eq('applicant_user_id', applicantUserId);
  }

  Future<void> createTextFeedPost({
    required String userId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await _client.from('social_posts').insert({
      'user_id': userId,
      'post_type': 'text',
      'content': trimmed,
      'lifts': <Map<String, dynamic>>[],
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<GymNewsItem>> fetchGymNews({int limit = 8}) async {
    final rows = await _client
        .from('gym_news')
        .select('id, title, summary, image_url, tag, created_at, created_by')
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .whereType<Map>()
        .map((row) => GymNewsItem.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> createGymNews({
    required String title,
    required String summary,
    String? imageUrl,
    String? tag,
  }) async {
    await _client.from('gym_news').insert({
      'title': title.trim(),
      'summary': summary.trim(),
      'image_url': (imageUrl ?? '').trim(),
      'tag': (tag ?? '').trim(),
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> deleteSocialPost({required String postId}) async {
    await _client.from('social_posts').delete().eq('id', postId);
  }

  Future<void> adminDeleteUser({required String targetUserId}) async {
    await _client.rpc(
      'admin_delete_user_account',
      params: {'p_target_user_id': targetUserId},
    );
  }

  Future<void> setReaction({
    required String userId,
    required String postId,
    required String reactionType,
  }) async {
    await _client
        .from('social_reactions')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId);

    await _client.from('social_reactions').insert({
      'post_id': postId,
      'user_id': userId,
      'reaction_type': reactionType,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> clearReaction({
    required String userId,
    required String postId,
  }) async {
    await _client
        .from('social_reactions')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', userId);
  }

  Future<void> addComment({
    required String userId,
    required String postId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await _client.from('social_comments').insert({
      'post_id': postId,
      'user_id': userId,
      'content': trimmed,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<LeaderboardAthlete>> fetchLeaderboard({
    int limit = 100,
    ProfileGender? gender,
  }) async {
    try {
      final rows = await _client.rpc(
        'fetch_movement_leaderboard',
        params: {
          'p_gender': gender == null || gender == ProfileGender.unspecified
              ? null
              : gender.name,
          'p_limit': limit,
        },
      );

      final list = (rows as List<dynamic>).whereType<Map>().toList();
      if (list.isNotEmpty) {
        return list
            .asMap()
            .entries
            .map(
              (entry) => LeaderboardAthlete.fromMap(
                Map<String, dynamic>.from(entry.value),
                _asInt(entry.value['rank']) ?? entry.key + 1,
              ),
            )
            .toList();
      }
    } catch (error, stackTrace) {
      dev.log(
        'fetch_movement_leaderboard RPC failed. Falling back to profiles total_lifted ordering.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
    }

    var query = _client
        .from('profiles')
        .select('id, name, avatar_url, location, gender, tier, total_lifted');

    if (gender != null && gender != ProfileGender.unspecified) {
      query = query.eq('gender', gender.name);
    }

    final rows = await query.order('total_lifted', ascending: false).limit(limit);

    return (rows as List<dynamic>)
        .whereType<Map>()
        .toList()
        .asMap()
        .entries
        .map(
          (entry) => LeaderboardAthlete.fromMap(
            Map<String, dynamic>.from(entry.value),
            entry.key + 1,
          ),
        )
        .toList();
  }

  Future<int> bumpLoginStreak() async {
    final result = await _client.rpc('bump_login_streak');
    if (result is int) {
      return result;
    }
    if (result is num) {
      return result.toInt();
    }
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<SplitSchedule?> fetchSplitSchedule(String userId) async {
    final cached = await _readCachedSplitSchedule(userId);
    if (cached != null && cached.schedule.isNotEmpty) {
      unawaited(_refreshSplitScheduleCache(userId));
      return cached;
    }

    final remote = await _fetchAndCacheSplitSchedule(userId);
    return remote ?? cached;
  }

  Future<void> upsertSplitSchedule({
    required String userId,
    required SplitSchedule schedule,
  }) async {
    await _cacheSplitSchedule(userId, schedule);

    try {
      await _client.from('user_split_schedules').upsert({
        'user_id': userId,
        'split_data': schedule.toMap(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (error, stackTrace) {
      dev.log(
        'upsertSplitSchedule failed. Kept local cached split so offline mode still works.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> deleteSplitSchedule(String userId) async {
    await _removeCachedSplitSchedule(userId);

    try {
      await _client.from('user_split_schedules').delete().eq('user_id', userId);
    } catch (error, stackTrace) {
      dev.log(
        'deleteSplitSchedule failed. Local cache was still cleared.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<TrainingSession> createSessionWithLifts({
    required String userId,
    required String name,
    required DateTime sessionDate,
    required List<LiftEntry> lifts,
  }) async {
    final payload = _sanitizeLiftPayload(lifts);
    if (payload.isEmpty) {
      throw StateError('Cannot create a session without lifts.');
    }

    try {
      final rpcData = await _client.rpc(
        'create_training_session_with_lifts',
        params: {
          'p_name': name,
          'p_session_date': sessionDate.toIso8601String(),
          'p_lifts': payload,
        },
      );
      final row = _extractSingleRow(rpcData);
      if (row != null) {
        return TrainingSession.fromMap(row);
      }
    } catch (error, stackTrace) {
      dev.log(
        'create_training_session_with_lifts RPC failed. Falling back to direct insert.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final inserted = await _client
        .from('training_sessions')
        .insert({
          'user_id': userId,
          'name': name,
          'session_date': sessionDate.toIso8601String(),
          'lifts': payload,
        })
        .select('id, user_id, name, session_date, lifts')
        .single();

    return TrainingSession.fromMap(inserted);
  }

  Future<TrainingSession> appendLiftsToSession({
    required String userId,
    required String sessionId,
    required List<LiftEntry> lifts,
  }) async {
    final payload = _sanitizeLiftPayload(lifts);
    if (payload.isEmpty) {
      throw StateError('Cannot append an empty lifts list.');
    }

    try {
      final rpcData = await _client.rpc(
        'append_lifts_to_session',
        params: {'p_session_id': sessionId, 'p_new_lifts': payload},
      );
      final row = _extractSingleRow(rpcData);
      if (row != null) {
        return TrainingSession.fromMap(row);
      }
    } catch (error, stackTrace) {
      dev.log(
        'append_lifts_to_session RPC failed. Falling back to select + update.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final existing = await _client
        .from('training_sessions')
        .select('id, user_id, name, session_date, lifts')
        .eq('id', sessionId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing == null) {
      throw StateError('Session not found or not owned by this user.');
    }

    final currentLiftsRaw = existing['lifts'];
    final currentLifts = currentLiftsRaw is List
        ? currentLiftsRaw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
        : <Map<String, dynamic>>[];

    final merged = [...currentLifts, ...payload];

    final updated = await _client
        .from('training_sessions')
        .update({
          'lifts': merged,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId)
        .eq('user_id', userId)
        .select('id, user_id, name, session_date, lifts')
        .single();

    return TrainingSession.fromMap(updated);
  }

  Future<void> deleteSession({
    required String userId,
    required String sessionId,
  }) async {
    await _client
        .from('training_sessions')
        .delete()
        .eq('id', sessionId)
        .eq('user_id', userId);
  }

  Future<void> deleteLift({
    required String userId,
    required String sessionId,
    required String liftId,
  }) async {
    final existing = await _client
        .from('training_sessions')
        .select('id, user_id, name, session_date, lifts')
        .eq('id', sessionId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing == null) {
      throw StateError('Session not found.');
    }

    final session = TrainingSession.fromMap(existing);
    final remaining = session.lifts.where((lift) => lift.id != liftId).toList();

    if (remaining.isEmpty) {
      await deleteSession(userId: userId, sessionId: sessionId);
      return;
    }

    await _client
        .from('training_sessions')
        .update({
          'lifts': remaining.map((lift) => lift.toJson()).toList(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId)
        .eq('user_id', userId);
  }

  List<Map<String, dynamic>> _sanitizeLiftPayload(List<LiftEntry> lifts) {
    final output = <Map<String, dynamic>>[];

    for (final lift in lifts) {
      final exerciseName = lift.name.trim();
      if (exerciseName.isEmpty) {
        continue;
      }

      var weight = lift.weight;
      if (!weight.isFinite || weight < 0) {
        weight = 0;
      }

      var reps = lift.reps;
      if (reps < 1) {
        reps = 1;
      }

      var sets = lift.sets;
      if (sets < 1) {
        sets = 1;
      }

      var additionalWeight = lift.addedWeight;
      if (additionalWeight != null &&
          (!additionalWeight.isFinite || additionalWeight < 0)) {
        additionalWeight = 0;
      }

      final payload = <String, dynamic>{
        'id': lift.id.isEmpty ? _uuid.v4() : lift.id,
        'name': exerciseName,
        'weight': double.parse(weight.toStringAsFixed(2)),
        'reps': reps,
        'sets': sets,
        'isPR': lift.isPr,
        'isBodyweight': lift.isBodyweight,
      };

      if (additionalWeight != null) {
        payload['addedWeight'] = double.parse(
          additionalWeight.toStringAsFixed(2),
        );
      }
      if (lift.aiInsight != null && lift.aiInsight!.trim().isNotEmpty) {
        payload['aiInsight'] = lift.aiInsight!.trim();
      }
      if (lift.strengthTier != null && lift.strengthTier!.trim().isNotEmpty) {
        payload['strengthTier'] = lift.strengthTier!.trim();
      }
      if (lift.strengthRatio != null && lift.strengthRatio!.isFinite) {
        payload['strengthRatio'] = double.parse(
          lift.strengthRatio!.toStringAsFixed(3),
        );
      }
      if (lift.estimatedForceN != null && lift.estimatedForceN!.isFinite) {
        payload['estimatedForceN'] = double.parse(
          lift.estimatedForceN!.toStringAsFixed(1),
        );
      }
      if (lift.animalCode != null && lift.animalCode!.trim().isNotEmpty) {
        payload['animalCode'] = lift.animalCode!.trim();
      }
      if (lift.splitGroup != null && lift.splitGroup!.trim().isNotEmpty) {
        payload['splitGroup'] = lift.splitGroup!.trim();
      }

      output.add(payload);
    }

    return output;
  }

  Map<String, dynamic>? _extractSingleRow(dynamic data) {
    if (data == null) {
      return null;
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) {
        return first;
      }
      if (first is Map) {
        return Map<String, dynamic>.from(first);
      }
    }

    return null;
  }

  int? _asInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  Future<SplitSchedule?> _fetchAndCacheSplitSchedule(String userId) async {
    try {
      final row = await _client
          .from('user_split_schedules')
          .select('split_data')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) {
        return null;
      }

      final schedule = _splitScheduleFromDynamic(row['split_data']);
      if (schedule == null) {
        return null;
      }

      await _cacheSplitSchedule(userId, schedule);
      return schedule;
    } catch (error, stackTrace) {
      dev.log(
        'fetchSplitSchedule failed. Falling back to local cache if available.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
      return _readCachedSplitSchedule(userId);
    }
  }

  Future<void> _refreshSplitScheduleCache(String userId) async {
    await _fetchAndCacheSplitSchedule(userId);
  }

  Future<void> _cacheSplitSchedule(String userId, SplitSchedule schedule) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _splitScheduleCacheKey(userId),
      jsonEncode(schedule.toMap()),
    );
  }

  Future<SplitSchedule?> _readCachedSplitSchedule(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_splitScheduleCacheKey(userId));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      return _splitScheduleFromDynamic(decoded);
    } catch (error, stackTrace) {
      dev.log(
        'Cached split schedule is malformed. Ignoring local copy.',
        name: 'SupabaseService',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _removeCachedSplitSchedule(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_splitScheduleCacheKey(userId));
  }

  SplitSchedule? _splitScheduleFromDynamic(dynamic raw) {
    final splitMap = _mapFromDynamic(raw);
    if (splitMap == null || splitMap.isEmpty) {
      return null;
    }

    final parsed = SplitSchedule.fromMap(splitMap);
    final sanitized = _sanitizeSplitSchedule(parsed);
    if (sanitized.schedule.isNotEmpty) {
      return sanitized;
    }

    return _rebuildSplitSchedule(splitMap) ?? sanitized;
  }

  SplitSchedule _sanitizeSplitSchedule(SplitSchedule schedule) {
    final maxIndex = schedule.schedule.isEmpty ? 0 : schedule.schedule.length - 1;
    final currentDayIndex = schedule.currentDayIndex.clamp(0, maxIndex).toInt();
    final daysPerWeek = schedule.daysPerWeek > 0
        ? schedule.daysPerWeek
        : schedule.schedule.length;

    return schedule.copyWith(
      daysPerWeek: daysPerWeek,
      currentDayIndex: currentDayIndex,
    );
  }

  SplitSchedule? _rebuildSplitSchedule(Map<String, dynamic> splitMap) {
    final template = _localSplitTemplate(splitMap);
    if (template == null) {
      return null;
    }

    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    final schedule = template.days.asMap().entries.map((entry) {
      return SplitScheduleEntry(
        label: entry.value.label,
        labelAr: entry.value.labelAr,
        muscles: entry.value.muscles,
        musclesAr: entry.value.musclesAr,
        exercises: entry.value.exercises,
        date: base.add(Duration(days: entry.key)),
        completed: false,
      );
    }).toList();

    final currentDayIndex = _asInt(splitMap['currentDayIndex']) ?? 0;

    return SplitSchedule(
      splitId: template.id,
      splitName: template.name,
      splitNameAr: template.nameAr,
      daysPerWeek: template.daysPerWeek,
      currentDayIndex: schedule.isEmpty
          ? 0
          : currentDayIndex.clamp(0, schedule.length - 1).toInt(),
      schedule: schedule,
    );
  }

  GymSplit? _localSplitTemplate(Map<String, dynamic> splitMap) {
    final daysPerWeek = _asInt(splitMap['daysPerWeek']) ?? 0;
    final candidates = splitsCatalog[daysPerWeek];
    if (candidates == null || candidates.isEmpty) {
      return null;
    }

    final splitId = (splitMap['splitId'] ?? '').toString().trim();
    if (splitId.isNotEmpty) {
      for (final split in candidates) {
        if (split.id == splitId) {
          return split;
        }
      }
    }

    final splitName = _firstNonEmpty([
      splitMap['splitName']?.toString(),
      splitMap['name']?.toString(),
      splitMap['splitNameAr']?.toString(),
    ]);

    if (splitName.isNotEmpty) {
      for (final split in candidates) {
        if (split.name == splitName || split.nameAr == splitName) {
          return split;
        }
      }
    }

    return candidates.first;
  }

  Map<String, dynamic>? _mapFromDynamic(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  String _splitScheduleCacheKey(String userId) {
    return '$_splitScheduleCachePrefix$userId';
  }

  String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }
}
