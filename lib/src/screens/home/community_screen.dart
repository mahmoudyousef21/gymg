import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/exercises.dart';
import '../../localization/egyptian_gym_lexicon.dart';
import '../../models/app_user.dart';
import '../../models/gym_news.dart';
import '../../models/leaderboard_athlete.dart';
import '../../models/social_post.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';

enum _SocialFilter { today, week }
enum _ComposerType { post, challenge }
enum _LeaderboardGenderFilter { all, male, female }
enum _CommunityTab { social, leaderboard, news }

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    required this.profile,
    required this.currentUserId,
    super.key,
  });

  final AppUser profile;
  final String currentUserId;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  static const String _adminEmail = 'devilg5701@gmail.com';

  final _service = SupabaseService.instance;
  final _postController = TextEditingController();
  final _challengeExerciseController = TextEditingController();
  final _challengeTargetController = TextEditingController();
  final _newsTitleController = TextEditingController();
  final _newsSummaryController = TextEditingController();
  final _newsImageController = TextEditingController();
  final _newsTagController = TextEditingController();
  final Map<String, TextEditingController> _commentControllers =
      <String, TextEditingController>{};

  bool _loadingFeed = true;
  bool _loadingLeaderboard = true;
  bool _loadingNews = true;
  bool _submittingPost = false;
  bool _submittingChallenge = false;
  bool _submittingNews = false;
  bool _refreshingFeed = false;
  bool _isAdminAccount = false;
  String? _feedError;
  String? _leaderboardError;
  String? _newsError;
  String? _composerError;
  String? _applyingChallengeId;
  _SocialFilter _filter = _SocialFilter.week;
  _ComposerType _composerType = _ComposerType.post;
  late _LeaderboardGenderFilter _genderFilter;
  List<SocialPost> _posts = <SocialPost>[];
  List<LeaderboardAthlete> _athletes = <LeaderboardAthlete>[];
  List<GymNewsItem> _newsItems = <GymNewsItem>[];
  String _challengeType = 'weight_goal';
  String? _selectedChallengeExercise;
  _CommunityTab _activeTab = _CommunityTab.social;
  RealtimeChannel? _socialRealtimeChannel;
  Timer? _feedRefreshDebounce;

  @override
  void initState() {
    super.initState();
    final currentEmail =
        Supabase.instance.client.auth.currentUser?.email?.toLowerCase().trim();
    _isAdminAccount = currentEmail == _adminEmail;
    _genderFilter = switch (widget.profile.gender) {
      ProfileGender.male => _LeaderboardGenderFilter.male,
      ProfileGender.female => _LeaderboardGenderFilter.female,
      ProfileGender.unspecified => _LeaderboardGenderFilter.all,
    };
    unawaited(_loadCommunity(initialLoad: true));
    _subscribeToSocialRealtime();
  }

  @override
  void didUpdateWidget(covariant CommunityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.gender != widget.profile.gender) {
      _genderFilter = switch (widget.profile.gender) {
        ProfileGender.male => _LeaderboardGenderFilter.male,
        ProfileGender.female => _LeaderboardGenderFilter.female,
        ProfileGender.unspecified => _LeaderboardGenderFilter.all,
      };
      unawaited(_loadLeaderboard(initialLoad: true));
    }
  }

  @override
  void dispose() {
    _feedRefreshDebounce?.cancel();
    unawaited(_socialRealtimeChannel?.unsubscribe());
    _socialRealtimeChannel = null;
    _postController.dispose();
    _challengeExerciseController.dispose();
    _challengeTargetController.dispose();
    _newsTitleController.dispose();
    _newsSummaryController.dispose();
    _newsImageController.dispose();
    _newsTagController.dispose();
    for (final controller in _commentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _commentController(String postId) {
    return _commentControllers.putIfAbsent(postId, TextEditingController.new);
  }

  Future<void> _loadCommunity({bool initialLoad = false}) async {
    await Future.wait([
      _loadFeed(initialLoad: initialLoad),
      _loadLeaderboard(initialLoad: initialLoad),
      _loadNews(initialLoad: initialLoad),
    ]);
  }

  Future<void> _loadFeed({bool initialLoad = false}) async {
    if (initialLoad) {
      setState(() {
        _loadingFeed = true;
        _feedError = null;
      });
    }

    try {
      final posts = await _service.fetchSocialFeedWithContext(
        currentUserId: widget.currentUserId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = posts;
        _loadingFeed = false;
        _feedError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingFeed = false;
        _feedError = error.toString();
      });
    }
  }

  Future<void> _refreshFeedSilently() async {
    if (_refreshingFeed) {
      return;
    }

    _refreshingFeed = true;
    try {
      final posts = await _service.fetchSocialFeedWithContext(
        currentUserId: widget.currentUserId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _posts = posts;
        _loadingFeed = false;
        _feedError = null;
      });
    } catch (_) {
      // Keep current UI state when background refresh fails.
    } finally {
      _refreshingFeed = false;
    }
  }

  void _scheduleFeedRefresh() {
    _feedRefreshDebounce?.cancel();
    _feedRefreshDebounce = Timer(
      const Duration(milliseconds: 220),
      () {
        unawaited(_refreshFeedSilently());
      },
    );
  }

  void _subscribeToSocialRealtime() {
    final channel = Supabase.instance.client.channel(
      'social-feed-${widget.currentUserId}',
    );

    void onAnyChange(PostgresChangePayload payload) {
      if (!mounted) {
        return;
      }
      _scheduleFeedRefresh();
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'social_posts',
      callback: onAnyChange,
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'social_reactions',
      callback: onAnyChange,
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'social_comments',
      callback: onAnyChange,
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'social_challenge_applications',
      callback: onAnyChange,
    );

    channel.subscribe();
    _socialRealtimeChannel = channel;
  }

  bool _canDeletePost(SocialPost post) {
    return post.userId == widget.currentUserId || _isAdminAccount;
  }

  bool _canDeleteUserAccount(SocialPost post) {
    return _isAdminAccount && post.userId != widget.currentUserId;
  }

  bool _hasPostActions(SocialPost post) {
    return _canDeletePost(post) || _canDeleteUserAccount(post);
  }

  Future<void> _deletePost(SocialPost post) async {
    final settings = context.appSettings;
    if (!_canDeletePost(post)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(settings.tx('Delete post?', 'تحذف البوست؟')),
          content: Text(
            settings.tx(
              'This action cannot be undone.',
              'الإجراء ده لا يمكن التراجع عنه.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(settings.tx('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(settings.tx('Delete', 'حذف')),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.deleteSocialPost(postId: post.id);
      await _refreshFeedSilently();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${settings.tx('Delete failed', 'الحذف فشل')}: $error',
          ),
        ),
      );
    }
  }

  Future<void> _deleteUserAccount(SocialPost post) async {
    final settings = context.appSettings;
    if (!_canDeleteUserAccount(post)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(settings.tx('Remove user account?', 'تحذف حساب المستخدم؟')),
          content: Text(
            settings.tx(
              'This permanently removes the account and all related data.',
              'ده هيحذف الحساب وكل بياناته نهائيًا.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(settings.tx('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(settings.tx('Remove user', 'حذف المستخدم')),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.adminDeleteUser(targetUserId: post.userId);
      await _refreshFeedSilently();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${settings.tx('User removal failed', 'حذف المستخدم فشل')}: $error',
          ),
        ),
      );
    }
  }

  Future<void> _showPostActions(SocialPost post) async {
    final settings = context.appSettings;
    if (!_hasPostActions(post)) {
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_canDeletePost(post))
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(settings.tx('Delete post', 'حذف البوست')),
                  onTap: () => Navigator.of(sheetContext).pop('delete_post'),
                ),
              if (_canDeleteUserAccount(post))
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: Text(
                    settings.tx('Remove user account', 'حذف حساب المستخدم'),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('delete_user'),
                ),
            ],
          ),
        );
      },
    );

    if (action == 'delete_post') {
      await _deletePost(post);
      return;
    }
    if (action == 'delete_user') {
      await _deleteUserAccount(post);
    }
  }

  List<String> _challengeSuggestions() {
    final query = _challengeExerciseController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return exerciseCatalog.take(10).toList();
    }

    return exerciseCatalog
        .where((exercise) {
          final en = exercise.toLowerCase();
          final ar = EgyptianGymLexicon.term(exercise).toLowerCase();
          return en.contains(query) || ar.contains(query);
        })
        .take(8)
        .toList();
  }

  Future<void> _publishTextPost() async {
    final settings = context.appSettings;
    final text = _postController.text.trim();
    if (text.isEmpty || _submittingPost) {
      return;
    }

    setState(() {
      _submittingPost = true;
      _composerError = null;
    });

    try {
      await _service.createTextFeedPost(userId: widget.currentUserId, content: text);
      _postController.clear();
      await _refreshFeedSilently();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${settings.tx('Post failed', 'النشر فشل')}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingPost = false;
        });
      }
    }
  }

  Future<void> _publishChallenge() async {
    final settings = context.appSettings;
    if (widget.profile.role != UserRole.coach) {
      setState(() {
        _composerError = settings.tx(
          'Only coaches can publish challenges.',
          'الكوتش بس يقدر ينشر تحدي.',
        );
      });
      return;
    }

    final exercise = _selectedChallengeExercise ??
        _challengeExerciseController.text.trim();
    final targetKg = double.tryParse(
      _challengeTargetController.text.trim().replaceAll(',', '.'),
    );

    if (exercise.trim().isEmpty || targetKg == null || targetKg <= 0) {
      setState(() {
        _composerError = settings.tx(
          'Challenge requires exercise + valid target weight.',
          'التحدي محتاج تمرين + وزن هدف صحيح.',
        );
      });
      return;
    }

    if (_submittingChallenge) {
      return;
    }

    setState(() {
      _submittingChallenge = true;
      _composerError = null;
    });

    try {
      await _service.createChallengePost(
        userId: widget.currentUserId,
        challengeType: _challengeType,
        exerciseName: exercise,
        targetKg: targetKg,
        content: settings.tx(
          'Challenge open: $exercise at ${targetKg.toStringAsFixed(1)}kg. Who is in?',
          'تحدي مفتوح: $exercise على ${targetKg.toStringAsFixed(1)} كجم. مين داخل؟',
        ),
      );
      _challengeExerciseController.clear();
      _challengeTargetController.clear();
      _selectedChallengeExercise = null;
      await _refreshFeedSilently();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${settings.tx('Challenge publish failed', 'نشر التحدي فشل')}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingChallenge = false;
        });
      }
    }
  }

  Future<void> _toggleChallengeApplication(SocialPost challenge) async {
    final settings = context.appSettings;
    if (_applyingChallengeId != null) {
      return;
    }

    if (widget.profile.role != UserRole.trainee) {
      setState(() {
        _composerError = settings.tx(
          'Only trainees can apply to challenges.',
          'المتدرب بس يقدر يقدم على التحدي.',
        );
      });
      return;
    }

    if (challenge.userId == widget.currentUserId) {
      return;
    }

    setState(() {
      _applyingChallengeId = challenge.id;
      _composerError = null;
    });

    try {
      if (challenge.hasApplied(widget.currentUserId)) {
        await _service.withdrawFromChallenge(
          challengePostId: challenge.id,
          applicantUserId: widget.currentUserId,
        );
      } else {
        await _service.applyToChallenge(
          challengePostId: challenge.id,
          applicantUserId: widget.currentUserId,
          coachId: challenge.userId,
        );
      }
      await _refreshFeedSilently();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${settings.tx('Challenge action failed', 'إجراء التحدي فشل')}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _applyingChallengeId = null;
        });
      }
    }
  }

  Future<void> _toggleReaction(SocialPost post, String reactionType) async {
    final settings = context.appSettings;
    try {
      if (post.myReaction == reactionType) {
        await _service.clearReaction(
          userId: widget.currentUserId,
          postId: post.id,
        );
      } else {
        await _service.setReaction(
          userId: widget.currentUserId,
          postId: post.id,
          reactionType: reactionType,
        );
      }
      await _refreshFeedSilently();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${settings.tx('Reaction failed', 'التفاعل فشل')}: $error',
          ),
        ),
      );
    }
  }

  Future<void> _addComment(SocialPost post) async {
    final settings = context.appSettings;
    final controller = _commentController(post.id);
    final text = controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    try {
      await _service.addComment(
        userId: widget.currentUserId,
        postId: post.id,
        content: text,
      );
      controller.clear();
      await _refreshFeedSilently();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${settings.tx('Comment failed', 'التعليق فشل')}: $error',
          ),
        ),
      );
    }
  }

  SocialPost? get _latestChallenge {
    for (final post in _posts) {
      if (post.isChallenge) {
        return post;
      }
    }
    return null;
  }

  List<SocialPost> get _filteredPosts {
    if (_filter == _SocialFilter.today) {
      final now = DateTime.now();
      return _posts
          .where(
            (post) =>
                post.timestamp.year == now.year &&
                post.timestamp.month == now.month &&
                post.timestamp.day == now.day,
          )
          .toList();
    }
    return _posts;
  }

  String _formatRelative(DateTime date, AppSettings settings) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return settings.tx('Just now', 'حالًا');
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return settings.tx(
        '$hours hour${hours > 1 ? 's' : ''} ago',
        'من $hours ساعة',
      );
    }

    final days = diff.inDays;
    return settings.tx('$days day${days > 1 ? 's' : ''} ago', 'من $days يوم');
  }

  String _challengeTypeLabel(String type, AppSettings settings) {
    return switch (type) {
      'weight_goal' => settings.tx('Weight Goal', 'هدف وزن'),
      'rep_goal' => settings.tx('Rep Goal', 'هدف عدات'),
      'volume_goal' => settings.tx('Volume Goal', 'هدف حجم'),
      _ => settings.tx('Challenge', 'تحدي'),
    };
  }

  ProfileGender? _selectedGenderForQuery() {
    return switch (_genderFilter) {
      _LeaderboardGenderFilter.all => null,
      _LeaderboardGenderFilter.male => ProfileGender.male,
      _LeaderboardGenderFilter.female => ProfileGender.female,
    };
  }

  LeaderboardAthlete? _currentAthlete() {
    for (final athlete in _athletes) {
      if (athlete.id == widget.currentUserId) {
        return athlete;
      }
    }
    return null;
  }

  Future<void> _loadLeaderboard({bool initialLoad = false}) async {
    if (initialLoad) {
      setState(() {
        _loadingLeaderboard = true;
        _leaderboardError = null;
      });
    }

    try {
      final rows = await _service.fetchLeaderboard(
        gender: _selectedGenderForQuery(),
      );
      final mutable = rows.toList();
      final profileGenderMatchesFilter =
          _genderFilter == _LeaderboardGenderFilter.all ||
          (_genderFilter == _LeaderboardGenderFilter.male &&
              widget.profile.gender == ProfileGender.male) ||
          (_genderFilter == _LeaderboardGenderFilter.female &&
              widget.profile.gender == ProfileGender.female);
      final hasCurrentUser = mutable.any(
        (athlete) => athlete.id == widget.currentUserId,
      );

      if (!hasCurrentUser && profileGenderMatchesFilter) {
        mutable.add(
          LeaderboardAthlete(
            id: widget.currentUserId,
            name: widget.profile.name,
            avatarUrl: widget.profile.avatarUrl,
            location: widget.profile.location,
            gender: widget.profile.gender.name,
            profileTier: widget.profile.tier,
            movementTier: widget.profile.tier,
            highestLift: widget.profile.totalLifted,
            dominantMovement: 'General',
            rank: mutable.length + 1,
          ),
        );
      }

      mutable.sort((a, b) => b.highestLift.compareTo(a.highestLift));
      final ranked = mutable
          .asMap()
          .entries
          .map((entry) => entry.value.copyWith(rank: entry.key + 1))
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _athletes = ranked;
        _loadingLeaderboard = false;
        _leaderboardError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _leaderboardError = error.toString();
        _loadingLeaderboard = false;
      });
    }
  }

  ({String label, double progress, double remaining}) _tierProgress(
    AppSettings settings,
  ) {
    const tierOrder = [
      'IRON',
      'BRONZE',
      'SILVER',
      'GOLD',
      'PLATINUM',
      'DIAMOND',
      'ELITE',
      'LEGENDARY',
    ];

    const thresholds = {
      'IRON': 0.0,
      'BRONZE': 45.0,
      'SILVER': 60.0,
      'GOLD': 75.0,
      'PLATINUM': 90.0,
      'DIAMOND': 110.0,
      'ELITE': 140.0,
      'LEGENDARY': 180.0,
    };

    final currentAthlete = _currentAthlete();
    final highestLift = currentAthlete?.highestLift ?? widget.profile.totalLifted;
    final tier =
        currentAthlete?.movementTier.toUpperCase() ?? widget.profile.tier.toUpperCase();

    final index = tierOrder.indexOf(tier);
    if (index == -1 || index == tierOrder.length - 1) {
      return (
        label: settings.tx('Legendary Status Achieved', 'وصلت حالة أسطورية'),
        progress: 100,
        remaining: 0,
      );
    }

    final currentTarget = thresholds[tier] ?? 0;
    final nextTier = tierOrder[index + 1];
    final nextTarget = thresholds[nextTier] ?? currentTarget;
    final clamped = highestLift.clamp(currentTarget, nextTarget);
    final ratio = nextTarget == currentTarget
        ? 1.0
        : (clamped - currentTarget) / (nextTarget - currentTarget);

    return (
      label: settings.tx('Road to $nextTier', 'الطريق لـ $nextTier'),
      progress: ratio * 100,
      remaining: (nextTarget - highestLift).clamp(
        0,
        double.infinity,
      ),
    );
  }

  Future<void> _loadNews({bool initialLoad = false}) async {
    if (initialLoad) {
      setState(() {
        _loadingNews = true;
        _newsError = null;
      });
    }

    try {
      final items = await _service.fetchGymNews(limit: 8);
      if (!mounted) {
        return;
      }
      setState(() {
        _newsItems = items;
        _loadingNews = false;
        _newsError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingNews = false;
        _newsError = error.toString();
      });
    }
  }

  Future<void> _publishNews() async {
    final settings = context.appSettings;
    if (!_isAdminAccount) {
      return;
    }

    final title = _newsTitleController.text.trim();
    final summary = _newsSummaryController.text.trim();
    final imageUrl = _newsImageController.text.trim();
    final tag = _newsTagController.text.trim();

    if (title.isEmpty || summary.isEmpty) {
      setState(() {
        _newsError = settings.tx(
          'News needs a title and summary.',
          'الخبر محتاج عنوان ووصف مختصر.',
        );
      });
      return;
    }

    if (_submittingNews) {
      return;
    }

    setState(() {
      _submittingNews = true;
      _newsError = null;
    });

    try {
      await _service.createGymNews(
        title: title,
        summary: summary,
        imageUrl: imageUrl.isEmpty ? null : imageUrl,
        tag: tag.isEmpty ? null : tag,
      );
      _newsTitleController.clear();
      _newsSummaryController.clear();
      _newsImageController.clear();
      _newsTagController.clear();
      await _loadNews(initialLoad: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _newsError = settings.tx(
          'News publish failed: $error',
          'نشر الخبر فشل: $error',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _submittingNews = false;
        });
      }
    }
  }

  Future<void> _refreshCommunity() async {
    await Future.wait([
      _refreshFeedSilently(),
      _loadLeaderboard(initialLoad: true),
      _loadNews(initialLoad: true),
    ]);
  }

  String _formatNewsDate(DateTime date) {
    return DateFormat('MMM d').format(date);
  }

  Color _newsAccent(int index) {
    const accents = [AppColors.yellow, AppColors.lime, AppColors.blue];
    return accents[index % accents.length];
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    const gold = AppColors.yellow;

    return RefreshIndicator(
      color: primary,
      onRefresh: _refreshCommunity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  label: settings.tx('COMMUNITY FLOOR', 'ساحة المجتمع'),
                  title: settings.tx('ACTIVITY FEED', 'آخر النشاط'),
                  accent: gold,
                ),
                const SizedBox(height: 12),
                SegmentedButton<_CommunityTab>(
                  segments: [
                    ButtonSegment(
                      value: _CommunityTab.social,
                      label: Text(settings.tx('SOCIAL FEED', 'الفيد الاجتماعي')),
                    ),
                    ButtonSegment(
                      value: _CommunityTab.leaderboard,
                      label: Text(settings.tx('LEADERBOARD', 'الترتيب')),
                    ),
                    ButtonSegment(
                      value: _CommunityTab.news,
                      label: Text(settings.tx('GYM NEWS', 'أخبار الجيم')),
                    ),
                  ],
                  selected: <_CommunityTab>{_activeTab},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _activeTab = selection.first;
                    });
                  },
                ),
                const SizedBox(height: 14),
                _buildActiveTabBody(
                  settings: settings,
                  primary: primary,
                  secondary: secondary,
                  maxWidth: constraints.maxWidth,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveTabBody({
    required AppSettings settings,
    required Color primary,
    required Color secondary,
    required double maxWidth,
  }) {
    return switch (_activeTab) {
      _CommunityTab.social => _buildFeedColumn(
          settings,
          primary,
          secondary,
          includeTopHeader: false,
        ),
      _CommunityTab.leaderboard => _buildLeaderboardTab(
          settings,
          primary,
          secondary,
        ),
      _CommunityTab.news => _buildNewsTab(
          settings,
          maxWidth,
        ),
    };
  }

  Widget _buildFeedColumn(
    AppSettings settings,
    Color primary,
    Color secondary,
    {bool includeTopHeader = true,
    }
  ) {
    const gold = AppColors.yellow;
    final challenge = _latestChallenge;
    final challengeSuggestions = _challengeSuggestions();
    final canCreateChallenges = widget.profile.role == UserRole.coach;
    final selectedComposer =
        canCreateChallenges ? _composerType : _ComposerType.post;
    final canApplyToChallenge =
        challenge != null &&
        widget.profile.role == UserRole.trainee &&
        challenge.userId != widget.currentUserId;
    final challengeApplied =
        challenge?.hasApplied(widget.currentUserId) ?? false;
    final canReviewApplicants =
        challenge != null &&
        widget.profile.role == UserRole.coach &&
        challenge.userId == widget.currentUserId;

    final feedChildren = <Widget>[
      if (includeTopHeader) ...[
        _SectionHeader(
          label: settings.tx('COMMUNITY FLOOR', 'ساحة المجتمع'),
          title: settings.tx('ACTIVITY FEED', 'آخر النشاط'),
          accent: gold,
        ),
        const SizedBox(height: 12),
      ],
      _PanelCard(
        accent: gold,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_ComposerType>(
              segments: [
                ButtonSegment(
                  value: _ComposerType.post,
                  label: Text(settings.tx('POST', 'بوست')),
                ),
                if (canCreateChallenges)
                  ButtonSegment(
                    value: _ComposerType.challenge,
                    label: Text(settings.tx('CHALLENGE', 'تحدي')),
                  ),
              ],
              selected: <_ComposerType>{selectedComposer},
              onSelectionChanged: canCreateChallenges
                  ? (selection) {
                      setState(() {
                        _composerType = selection.first;
                        _composerError = null;
                      });
                    }
                  : null,
            ),
            if (!canCreateChallenges) ...[
              const SizedBox(height: 8),
              Text(
                settings.tx(
                  'Challenge publishing is coach-only.',
                  'نشر التحديات متاح للكوتش فقط.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            if (_composerError != null) ...[
              Text(
                _composerError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            if (selectedComposer == _ComposerType.post) ...[
              TextField(
                controller: _postController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: settings.tx(
                    'Share your gym update',
                    'شارك تحديث الجيم بتاعك',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _submittingPost ? null : _publishTextPost,
                  icon: _submittingPost
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(settings.tx('POST', 'انشر')),
                ),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                initialValue: _challengeType,
                items: const [
                  DropdownMenuItem(
                    value: 'weight_goal',
                    child: Text('Weight Goal'),
                  ),
                  DropdownMenuItem(
                    value: 'rep_goal',
                    child: Text('Rep Goal'),
                  ),
                  DropdownMenuItem(
                    value: 'volume_goal',
                    child: Text('Volume Goal'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _challengeType = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: settings.tx('Challenge type', 'نوع التحدي'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _challengeExerciseController,
                decoration: InputDecoration(
                  labelText: settings.tx('Exercise', 'التمرين'),
                ),
                onChanged: (_) {
                  setState(() {
                    _selectedChallengeExercise = null;
                  });
                },
              ),
              const SizedBox(height: 6),
              if (challengeSuggestions.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: challengeSuggestions
                      .map(
                        (exercise) => ActionChip(
                          label: Text(
                            settings.isArabic
                                ? EgyptianGymLexicon.term(exercise)
                                : exercise,
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedChallengeExercise = exercise;
                              _challengeExerciseController.text =
                                  settings.isArabic
                                      ? EgyptianGymLexicon.term(exercise)
                                      : exercise;
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _challengeTargetController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: settings.tx('Target (kg)', 'الهدف (كجم)'),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _submittingChallenge ? null : _publishChallenge,
                  icon: _submittingChallenge
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.emoji_events),
                  label: Text(
                    settings.tx('PUBLISH CHALLENGE', 'انشر التحدي'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      _PanelCard(
        accent: secondary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GlowPill(
              label: settings.tx('ACTIVE CHALLENGE', 'التحدي الحالي'),
              accent: secondary,
            ),
            const SizedBox(height: 10),
            if (challenge == null)
              Text(
                settings.tx(
                  'No challenge posted yet. Start one now from the challenge composer.',
                  'لسه مفيش تحدي. ابدأ تحدي جديد من مُنشئ التحديات.',
                ),
              )
            else ...[
              Text(
                settings.tx(
                  '@${challenge.userName} posted ${_challengeTypeLabel(challenge.challengeType ?? 'weight_goal', settings)}',
                  '@${challenge.userName} نشر ${_challengeTypeLabel(challenge.challengeType ?? 'weight_goal', settings)}',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                settings.tx(
                  '${challenge.challengeExercise ?? 'Exercise'} @ ${(challenge.challengeTargetKg ?? 0).toStringAsFixed(1)}kg',
                  '${challenge.challengeExercise ?? 'تمرين'} @ ${(challenge.challengeTargetKg ?? 0).toStringAsFixed(1)} كجم',
                ),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: primary,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: canApplyToChallenge &&
                          _applyingChallengeId != challenge.id
                      ? () => _toggleChallengeApplication(challenge)
                      : null,
                  child: Text(
                    challengeApplied
                        ? settings.tx('Applied', 'تم التقديم')
                        : settings.tx(
                            'Apply to Challenge',
                            'قدّم على التحدي',
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    canReviewApplicants
                        ? settings.tx(
                            '${challenge?.challengeApplicantCount ?? 0} applicant(s) so far.',
                            'عدد المتقدمين حتى الآن: ${challenge?.challengeApplicantCount ?? 0}.',
                          )
                        : settings.tx(
                            'More gym war, less excuses.',
                            'حرب جيم أكتر، أعذار أقل.',
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                    softWrap: true,
                  ),
                ),
              ],
            ),
            if (canReviewApplicants) ...[
              const SizedBox(height: 10),
              Text(
                settings.tx('Applicants', 'المتقدمين'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              if (challenge?.challengeApplicants.isEmpty ?? true)
                Text(
                  settings.tx(
                    'No one has applied yet.',
                    'لسه محدش قدّم.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ...?challenge?.challengeApplicants.map(
                  (application) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighest.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.surfaceHigh,
                          backgroundImage: application.applicantAvatar.isNotEmpty
                              ? NetworkImage(application.applicantAvatar)
                              : null,
                          child: application.applicantAvatar.isEmpty
                              ? Text(
                                  application.applicantName.isEmpty
                                      ? '?'
                                      : application.applicantName[0]
                                          .toUpperCase(),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(application.applicantName),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Text(
            settings.tx('ACTIVITY FEED', 'آخر النشاط'),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: gold),
          ),
          const Spacer(),
          SegmentedButton<_SocialFilter>(
            segments: [
              ButtonSegment(
                value: _SocialFilter.today,
                label: Text(settings.tx('TODAY', 'النهارده')),
              ),
              ButtonSegment(
                value: _SocialFilter.week,
                label: Text(settings.tx('WEEK', 'الأسبوع')),
              ),
            ],
            selected: <_SocialFilter>{_filter},
            onSelectionChanged: (selection) {
              setState(() {
                _filter = selection.first;
              });
            },
          ),
        ],
      ),
      const SizedBox(height: 12),
    ];

    if (_loadingFeed) {
      feedChildren.add(
        _buildLoadingCard(settings.tx('Loading feed...', 'تحميل الفيد...')),
      );
    } else if (_feedError != null) {
      feedChildren.add(
        _buildErrorCard(
          title: settings.tx('Failed to load social feed', 'تعذر تحميل الفيد'),
          message: _feedError!,
          actionLabel: settings.tx('RETRY', 'حاول تاني'),
          onAction: () => _loadFeed(initialLoad: true),
        ),
      );
    } else if (_filteredPosts.isEmpty) {
      feedChildren.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              settings.tx('No feed activity yet.', 'لسه مفيش نشاط في الفيد.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    } else {
      feedChildren.addAll(
        _filteredPosts.map((post) {
          final commentController = _commentController(post.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PanelCard(
              accent: post.isChallenge ? secondary : gold,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.surfaceHighest,
                        backgroundImage: post.userAvatar.isNotEmpty
                            ? NetworkImage(post.userAvatar)
                            : null,
                        child: post.userAvatar.isNotEmpty
                            ? null
                            : Text(
                                post.userName.isEmpty
                                    ? '?'
                                    : post.userName[0].toUpperCase(),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${post.userName} ${post.userId == widget.currentUserId ? settings.tx('(YOU)', '(إنت)') : ''}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                _TagPill(
                                  label: post.userTier,
                                  color: gold,
                                ),
                                if (post.isChallenge)
                                  _TagPill(
                                    label: settings.tx('CHALLENGE', 'تحدي'),
                                    color: secondary,
                                  ),
                              ],
                            ),
                            Text(
                              '${_formatRelative(post.timestamp, settings)} • ${post.location}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (_hasPostActions(post))
                        IconButton(
                          tooltip: settings.tx('Post actions', 'إجراءات البوست'),
                          onPressed: () => _showPostActions(post),
                          icon: const Icon(Icons.more_vert),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (post.isChallenge)
                    Text(
                      settings.tx(
                        '${_challengeTypeLabel(post.challengeType ?? 'weight_goal', settings)}: ${post.challengeExercise ?? 'Exercise'} @ ${(post.challengeTargetKg ?? 0).toStringAsFixed(1)}kg',
                        '${_challengeTypeLabel(post.challengeType ?? 'weight_goal', settings)}: ${post.challengeExercise ?? 'تمرين'} @ ${(post.challengeTargetKg ?? 0).toStringAsFixed(1)} كجم',
                      ),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: secondary,
                            fontStyle: FontStyle.italic,
                          ),
                    )
                  else if (post.isText)
                    Text(
                      post.content,
                      style: Theme.of(context).textTheme.bodyLarge,
                    )
                  else ...[
                    Text(
                      post.sessionName,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricChip(
                          label: settings.tx('Volume', 'الحجم'),
                          value:
                              '${post.volume.round()} ${settings.tx('kg', 'كجم')}',
                        ),
                        _MetricChip(
                          label: settings.tx('Sets', 'جمل'),
                          value: '${post.sets}',
                        ),
                        _MetricChip(
                          label: settings.tx('Intensity', 'الشدة'),
                          value: '${post.intensity.toStringAsFixed(1)} RPE',
                        ),
                      ],
                    ),
                    if (post.lifts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...post.lifts.map(
                        (lift) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighest.withValues(
                              alpha: 0.7,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  settings.isArabic
                                      ? EgyptianGymLexicon.term(lift.name)
                                      : lift.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium,
                                ),
                              ),
                              Text(
                                '${lift.sets} ${settings.tx('sets', 'جملة')} • ${lift.weight.toStringAsFixed(1)}kg x ${lift.reps}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      _ReactionButton(
                        icon: Icons.bolt,
                        label: settings.tx('Hype', 'حماس'),
                        count: post.hypeCount,
                        selected: post.myReaction == 'hype',
                        onPressed: () => _toggleReaction(post, 'hype'),
                      ),
                      _ReactionButton(
                        icon: Icons.local_fire_department_outlined,
                        label: settings.tx('Fire', 'نار'),
                        count: post.fireCount,
                        selected: post.myReaction == 'fire',
                        onPressed: () => _toggleReaction(post, 'fire'),
                      ),
                      _ReactionButton(
                        icon: Icons.shield_outlined,
                        label: settings.tx('Respect', 'احترام'),
                        count: post.respectCount,
                        selected: post.myReaction == 'respect',
                        onPressed: () => _toggleReaction(post, 'respect'),
                      ),
                      _ReactionButton(
                        icon: Icons.sports_martial_arts_outlined,
                        label: settings.tx('Beast', 'وحش'),
                        count: post.beastCount,
                        selected: post.myReaction == 'beast',
                        onPressed: () => _toggleReaction(post, 'beast'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (post.comments.isNotEmpty) ...[
                    ...post.comments.map(
                      (comment) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${comment.userName}: ${comment.content}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commentController,
                          decoration: InputDecoration(
                            hintText: settings.tx(
                              'Add a comment',
                              'ضيف تعليق',
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _addComment(post),
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                  Text(
                    DateFormat('EEE, MMM d • HH:mm').format(post.timestamp),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: feedChildren,
    );
  }

  Widget _buildLeaderboardTab(
    AppSettings settings,
    Color primary,
    Color secondary,
  ) {
    const gold = AppColors.yellow;

    if (_loadingLeaderboard) {
      return _buildLoadingCard(
        settings.tx('Loading leaderboard...', 'تحميل الترتيب...'),
      );
    }

    if (_leaderboardError != null) {
      return _buildErrorCard(
        title: settings.tx('Failed to load leaderboard', 'تعذر تحميل الترتيب'),
        message: _leaderboardError!,
        actionLabel: settings.tx('RETRY', 'حاول تاني'),
        onAction: () => _loadLeaderboard(initialLoad: true),
      );
    }

    if (_athletes.isEmpty) {
      return _PanelCard(
        accent: gold,
        padding: const EdgeInsets.all(20),
        child: Text(
          settings.tx(
            'No athletes yet. Start logging sessions to appear here.',
            'لسه مفيش لاعيبة هنا. سجّل جلساتك عشان تظهر.',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final podium = _athletes.take(3).toList();
    final rest = _athletes.length > 3
        ? _athletes.sublist(3)
        : const <LeaderboardAthlete>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_LeaderboardGenderFilter>(
          segments: [
            ButtonSegment(
              value: _LeaderboardGenderFilter.all,
              label: Text(settings.tx('ALL', 'الكل')),
            ),
            ButtonSegment(
              value: _LeaderboardGenderFilter.male,
              label: Text(settings.tx('MALE', 'ذكور')),
            ),
            ButtonSegment(
              value: _LeaderboardGenderFilter.female,
              label: Text(settings.tx('FEMALE', 'إناث')),
            ),
          ],
          selected: <_LeaderboardGenderFilter>{_genderFilter},
          onSelectionChanged: (selection) {
            setState(() {
              _genderFilter = selection.first;
            });
            _loadLeaderboard(initialLoad: true);
          },
        ),
        const SizedBox(height: 12),
        _PanelCard(
          accent: gold,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: podium
                .asMap()
                .entries
                .map(
                  (entry) => Expanded(
                    child: _PodiumAthleteCard(
                      athlete: entry.value,
                      position: entry.key + 1,
                      primary: primary,
                      secondary: secondary,
                      highlight: entry.key == 0,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        ...rest.map(
          (athlete) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PanelCard(
              accent: primary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.surfaceHighest,
                  backgroundImage: athlete.avatarUrl.isNotEmpty
                      ? NetworkImage(athlete.avatarUrl)
                      : null,
                  child: athlete.avatarUrl.isEmpty
                      ? Text(
                          athlete.name.isEmpty
                              ? '?'
                              : athlete.name[0].toUpperCase(),
                        )
                      : null,
                ),
                title: Row(
                  children: [
                    Text(
                      athlete.rank.toString(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${athlete.id == widget.currentUserId ? widget.profile.name : athlete.name}${athlete.id == widget.currentUserId ? settings.tx(' (YOU)', ' (إنت)') : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                trailing: Text(
                  '${athlete.highestLift.toStringAsFixed(0)} kg',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: primary,
                      ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewsTab(AppSettings settings, double maxWidth) {
    const gold = AppColors.yellow;
    final columns = maxWidth >= 980 ? 3 : 2;

    if (_loadingNews) {
      return _buildLoadingCard(settings.tx('Loading news...', 'تحميل الأخبار...'));
    }

    if (_newsError != null && !_isAdminAccount) {
      return _buildErrorCard(
        title: settings.tx('Failed to load news', 'تعذر تحميل الأخبار'),
        message: _newsError!,
        actionLabel: settings.tx('RETRY', 'حاول تاني'),
        onAction: () => _loadNews(initialLoad: true),
      );
    }

    final children = <Widget>[];
    if (_isAdminAccount) {
      children.add(
        _PanelCard(
          accent: gold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.tx('ADMIN NEWS DESK', 'منصة أخبار المشرف'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newsTitleController,
                decoration: InputDecoration(
                  labelText: settings.tx('Headline', 'العنوان'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newsSummaryController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: settings.tx('Summary', 'الملخص'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newsImageController,
                decoration: InputDecoration(
                  labelText: settings.tx(
                    'Image URL or asset path',
                    'رابط الصورة أو مسار الأصل',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newsTagController,
                decoration: InputDecoration(
                  labelText: settings.tx('Tag (optional)', 'التصنيف (اختياري)'),
                ),
              ),
              if (_newsError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _newsError!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _submittingNews ? null : _publishNews,
                  icon: _submittingNews
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.campaign),
                  label: Text(settings.tx('PUBLISH NEWS', 'انشر الخبر')),
                ),
              ),
            ],
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
    }

    if (_newsItems.isEmpty) {
      children.add(
        _PanelCard(
          accent: gold,
          padding: const EdgeInsets.all(20),
          child: Text(
            settings.tx('No news yet. Check back soon.', 'لسه مفيش أخبار. ارجع قريب.'),
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }

    children.add(
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _newsItems.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.74,
        ),
        itemBuilder: (context, index) {
          final news = _newsItems[index];
          return _NewsGridTile(
            news: news,
            accent: _newsAccent(index),
            fallbackTag: settings.tx('Update', 'تحديث'),
            ctaLabel: settings.tx('READ MORE', 'اقرأ المزيد'),
          );
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildSidebarColumn(
    AppSettings settings,
    Color primary,
    Color secondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStandingsSection(settings, primary, secondary),
        const SizedBox(height: 14),
        _buildLeaderboardSection(settings, primary, secondary),
        const SizedBox(height: 16),
        _buildNewsSection(settings),
      ],
    );
  }

  Widget _buildStandingsSection(
    AppSettings settings,
    Color primary,
    Color secondary,
  ) {
    const gold = AppColors.yellow;
    final tierProgress = _tierProgress(settings);
    final currentAthlete = _currentAthlete();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: settings.tx('COMPETITIVE RANKINGS', 'الترتيب التنافسي'),
          title: settings.tx('THE IRON STANDINGS', 'ترتيب الحديد'),
          accent: gold,
        ),
        const SizedBox(height: 12),
        _PanelCard(
          accent: gold,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tierProgress.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                (currentAthlete?.movementTier ?? widget.profile.tier)
                    .toUpperCase(),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _PanelCard(
          accent: primary,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tierProgress.remaining == 0
                    ? settings.tx(
                        'You reached the highest tier.',
                        'وصلت لأعلى مستوى.',
                      )
                    : settings.tx(
                        'Need ${tierProgress.remaining.round()} kg more to level up.',
                        'محتاج ${tierProgress.remaining.round()} كجم كمان عشان تعلى.',
                      ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 9,
                  value: (tierProgress.progress / 100).clamp(0.0, 1.0),
                  backgroundColor: AppColors.surfaceHighest,
                  valueColor: AlwaysStoppedAnimation(gold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardSection(
    AppSettings settings,
    Color primary,
    Color secondary,
  ) {
    const gold = AppColors.yellow;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          settings.tx('GLOBAL LEADERBOARD', 'الترتيب العالمي'),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: gold),
        ),
        const SizedBox(height: 8),
        SegmentedButton<_LeaderboardGenderFilter>(
          segments: [
            ButtonSegment(
              value: _LeaderboardGenderFilter.all,
              label: Text(settings.tx('ALL', 'الكل')),
            ),
            ButtonSegment(
              value: _LeaderboardGenderFilter.male,
              label: Text(settings.tx('MALE', 'ذكور')),
            ),
            ButtonSegment(
              value: _LeaderboardGenderFilter.female,
              label: Text(settings.tx('FEMALE', 'إناث')),
            ),
          ],
          selected: <_LeaderboardGenderFilter>{_genderFilter},
          onSelectionChanged: (selection) {
            setState(() {
              _genderFilter = selection.first;
            });
            _loadLeaderboard(initialLoad: true);
          },
        ),
        const SizedBox(height: 8),
      ],
    );

    if (_loadingLeaderboard) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          _buildLoadingCard(
            settings.tx('Loading leaderboard...', 'تحميل الترتيب...'),
          ),
        ],
      );
    }

    if (_leaderboardError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          _buildErrorCard(
            title: settings.tx('Failed to load leaderboard', 'تعذر تحميل الترتيب'),
            message: _leaderboardError!,
            actionLabel: settings.tx('RETRY', 'حاول تاني'),
            onAction: () => _loadLeaderboard(initialLoad: true),
          ),
        ],
      );
    }

    if (_athletes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          _PanelCard(
            accent: gold,
            padding: const EdgeInsets.all(20),
            child: Text(
              settings.tx(
                'No athletes yet. Start logging sessions to appear here.',
                'لسه مفيش لاعيبة هنا. سجّل جلساتك عشان تظهر.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        ..._athletes.map(
          (athlete) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PanelCard(
              accent: athlete.rank == 1 ? gold : primary,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.surfaceHighest,
                  backgroundImage: athlete.avatarUrl.isNotEmpty
                      ? NetworkImage(athlete.avatarUrl)
                      : null,
                  child: athlete.avatarUrl.isEmpty
                      ? Text(
                          athlete.name.isEmpty
                              ? '?'
                              : athlete.name[0].toUpperCase(),
                        )
                      : null,
                ),
                title: Row(
                  children: [
                    Text(
                      '#${athlete.rank.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: athlete.rank == 1
                                ? gold
                                : AppColors.onSurface,
                          ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${athlete.id == widget.currentUserId ? widget.profile.name : athlete.name}${athlete.id == widget.currentUserId ? settings.tx(' (YOU)', ' (إنت)') : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${athlete.location.isEmpty ? settings.tx('Global', 'عالمي') : athlete.location} • ${settings.isArabic ? '${athlete.movementTier} في ${athlete.dominantMovement}' : '${athlete.movementTier} in ${athlete.dominantMovement}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Text(
                  '${athlete.highestLift.toStringAsFixed(0)}kg',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: athlete.id == widget.currentUserId
                            ? primary
                            : AppColors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewsSection(AppSettings settings) {
    const gold = AppColors.yellow;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: settings.tx('GYM NEWS', 'أخبار الجيم'),
          title: settings.tx('Latest fitness intel', 'أحدث أخبار اللياقة'),
          accent: gold,
        ),
      ],
    );

    final composer = !_isAdminAccount
        ? null
        : _PanelCard(
            accent: gold,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.tx('ADMIN NEWS DESK', 'منصة أخبار المشرف'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _newsTitleController,
                  decoration: InputDecoration(
                    labelText: settings.tx('Headline', 'العنوان'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _newsSummaryController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: settings.tx('Summary', 'الملخص'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _newsImageController,
                  decoration: InputDecoration(
                    labelText: settings.tx(
                      'Image URL or asset path',
                      'رابط الصورة أو مسار الأصل',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _newsTagController,
                  decoration: InputDecoration(
                    labelText: settings.tx('Tag (optional)', 'التصنيف (اختياري)'),
                  ),
                ),
                if (_newsError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _newsError!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _submittingNews ? null : _publishNews,
                    icon: _submittingNews
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.campaign),
                    label: Text(settings.tx('PUBLISH NEWS', 'انشر الخبر')),
                  ),
                ),
              ],
            ),
          );

    final bodyChildren = <Widget>[header];

    if (composer != null) {
      bodyChildren.addAll([
        const SizedBox(height: 10),
        composer,
      ]);
    }

    bodyChildren.add(const SizedBox(height: 12));

    if (_loadingNews) {
      bodyChildren.add(
        _buildLoadingCard(settings.tx('Loading news...', 'تحميل الأخبار...')),
      );
    } else if (_newsError != null && !_isAdminAccount) {
      bodyChildren.add(
        _buildErrorCard(
          title: settings.tx('Failed to load news', 'تعذر تحميل الأخبار'),
          message: _newsError!,
          actionLabel: settings.tx('RETRY', 'حاول تاني'),
          onAction: () => _loadNews(initialLoad: true),
        ),
      );
    } else if (_newsItems.isEmpty) {
      bodyChildren.add(
        _PanelCard(
          accent: gold,
          padding: const EdgeInsets.all(20),
          child: Text(
            _isAdminAccount
                ? settings.tx(
                    'Post the first update from the admin desk.',
                    'انشر أول خبر من منصة المشرف.',
                  )
                : settings.tx(
                    'No news yet. Check back soon.',
                    'لسه مفيش أخبار. ارجع قريب.',
                  ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    } else {
      bodyChildren.addAll(
        _newsItems.asMap().entries.map(
          (entry) {
            final index = entry.key;
            final news = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NewsCard(
                news: news,
                accent: _newsAccent(index),
                dateLabel: _formatNewsDate(news.createdAt),
                fallbackTag: settings.tx('Update', 'تحديث'),
                footerLabel: settings.tx(
                  'Community bulletin',
                  'نشرة المجتمع',
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: bodyChildren,
    );
  }

  Widget _buildLoadingCard(String label) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard({
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.title,
    required this.accent,
  });

  final String label;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: accent),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .displaySmall
              ?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    required this.accent,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceLow.withValues(alpha: 0.98),
            Color.alphaBlend(
              accent.withValues(alpha: 0.12),
              AppColors.surfaceHigh,
            ),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _GlowPill extends StatelessWidget {
  const _GlowPill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: accent, fontSize: 10),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

class _PodiumAthleteCard extends StatelessWidget {
  const _PodiumAthleteCard({
    required this.athlete,
    required this.position,
    required this.primary,
    required this.secondary,
    required this.highlight,
  });

  final LeaderboardAthlete athlete;
  final int position;
  final Color primary;
  final Color secondary;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final glow = highlight ? primary : secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: glow.withValues(alpha: 0.7), width: 2),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: highlight ? 0.35 : 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 1,
                child: athlete.avatarUrl.isNotEmpty
                    ? Image.network(
                        athlete.avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(),
                      )
                    : _avatarFallback(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            athlete.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${athlete.highestLift.toStringAsFixed(0)} kg',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: primary),
          ),
          const SizedBox(height: 4),
          _TagPill(label: '#$position', color: glow),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.surfaceHighest,
            AppColors.surfaceBright,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          athlete.name.isEmpty ? '?' : athlete.name[0].toUpperCase(),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _NewsGridTile extends StatelessWidget {
  const _NewsGridTile({
    required this.news,
    required this.accent,
    required this.fallbackTag,
    required this.ctaLabel,
  });

  final GymNewsItem news;
  final Color accent;
  final String fallbackTag;
  final String ctaLabel;

  @override
  Widget build(BuildContext context) {
    final hasImage = news.imageUrl.isNotEmpty;
    final isAssetImage = news.imageUrl.trim().startsWith('assets/');
    final tagLabel = (news.tag.isEmpty ? fallbackTag : news.tag).toUpperCase();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasImage
                  ? (isAssetImage
                      ? Image.asset(
                          news.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _NewsCardBackdrop(
                            accent: accent,
                          ),
                        )
                      : Image.network(
                          news.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _NewsCardBackdrop(
                            accent: accent,
                          ),
                        ))
                  : _NewsCardBackdrop(accent: accent),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.78),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TagPill(label: tagLabel, color: accent),
                  const Spacer(),
                  Text(
                    news.title.toUpperCase(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () {},
                    child: Text(ctaLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({
    required this.news,
    required this.accent,
    required this.dateLabel,
    required this.fallbackTag,
    required this.footerLabel,
  });

  final GymNewsItem news;
  final Color accent;
  final String dateLabel;
  final String fallbackTag;
  final String footerLabel;

  @override
  Widget build(BuildContext context) {
    final hasImage = news.imageUrl.isNotEmpty;
    final tagLabel = (news.tag.isEmpty ? fallbackTag : news.tag).toUpperCase();
    final isAssetImage = news.imageUrl.trim().startsWith('assets/');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasImage
                  ? (isAssetImage
                      ? Image.asset(
                          news.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return _NewsCardBackdrop(accent: accent);
                          },
                        )
                      : Image.network(
                          news.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return _NewsCardBackdrop(accent: accent);
                          },
                        ))
                  : _NewsCardBackdrop(accent: accent),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.8),
                          ),
                        ),
                        child: Text(
                          tagLabel,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: accent,
                                letterSpacing: 1.1,
                              ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        dateLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    news.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    news.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: accent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        footerLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsCardBackdrop extends StatelessWidget {
  const _NewsCardBackdrop({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.65),
            AppColors.surfaceHigh.withValues(alpha: 0.85),
            AppColors.surface.withValues(alpha: 0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
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

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text('$label $count'),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? primary : AppColors.onSurface,
        side: BorderSide(
          color: selected
              ? primary.withValues(alpha: 0.8)
              : AppColors.outline.withValues(alpha: 0.9),
        ),
        backgroundColor: selected ? primary.withValues(alpha: 0.12) : null,
      ),
    );
  }
}
