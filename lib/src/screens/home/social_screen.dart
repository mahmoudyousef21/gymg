import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/exercises.dart';
import '../../localization/egyptian_gym_lexicon.dart';
import '../../models/app_user.dart';
import '../../models/social_post.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';

enum _SocialFilter { today, week }
enum _ComposerType { post, challenge }

class SocialScreen extends StatefulWidget {
  const SocialScreen({
    required this.currentUserId,
    required this.currentUserRole,
    super.key,
  });

  final String currentUserId;
  final UserRole currentUserRole;

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  static const String _adminEmail = 'devilg5701@gmail.com';

  final _service = SupabaseService.instance;
  final _postController = TextEditingController();
  final _challengeExerciseController = TextEditingController();
  final _challengeTargetController = TextEditingController();
  final Map<String, TextEditingController> _commentControllers =
      <String, TextEditingController>{};

  bool _loading = true;
  bool _submittingPost = false;
  bool _submittingChallenge = false;
  bool _refreshingFeed = false;
  String? _applyingChallengeId;
  String? _error;
  _SocialFilter _filter = _SocialFilter.week;
  _ComposerType _composerType = _ComposerType.post;
  List<SocialPost> _posts = <SocialPost>[];
  String _challengeType = 'weight_goal';
  String? _selectedChallengeExercise;
  RealtimeChannel? _socialRealtimeChannel;
  Timer? _feedRefreshDebounce;
  bool _isAdminAccount = false;

  @override
  void initState() {
    super.initState();
    final currentEmail =
        Supabase.instance.client.auth.currentUser?.email?.toLowerCase().trim();
    _isAdminAccount = currentEmail == _adminEmail;
    unawaited(_loadFeed(initialLoad: true));
    _subscribeToSocialRealtime();
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

  @override
  void dispose() {
    _feedRefreshDebounce?.cancel();
    unawaited(_socialRealtimeChannel?.unsubscribe());
    _socialRealtimeChannel = null;
    _postController.dispose();
    _challengeExerciseController.dispose();
    _challengeTargetController.dispose();
    for (final controller in _commentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _commentController(String postId) {
    return _commentControllers.putIfAbsent(postId, TextEditingController.new);
  }

  Future<void> _loadFeed({bool initialLoad = false}) async {
    if (initialLoad) {
      setState(() {
        _loading = true;
        _error = null;
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
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
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
        _loading = false;
        _error = null;
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
      _error = null;
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
    if (widget.currentUserRole != UserRole.coach) {
      setState(() {
        _error = settings.tx(
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
        _error = settings.tx(
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
      _error = null;
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

    if (widget.currentUserRole != UserRole.trainee) {
      setState(() {
        _error = settings.tx(
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
      _error = null;
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

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: primary));
    }

    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.tx('Failed to load social feed', 'تعذر تحميل الفيد'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(_error!),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadFeed,
                    child: Text(settings.tx('RETRY', 'حاول تاني')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final challenge = _latestChallenge;
    final challengeSuggestions = _challengeSuggestions();
    final canCreateChallenges = widget.currentUserRole == UserRole.coach;
    final selectedComposer = canCreateChallenges
      ? _composerType
      : _ComposerType.post;
    final canApplyToChallenge =
      challenge != null &&
      widget.currentUserRole == UserRole.trainee &&
      challenge.userId != widget.currentUserId;
    final challengeApplied =
      challenge?.hasApplied(widget.currentUserId) ?? false;
    final canReviewApplicants =
      challenge != null &&
      widget.currentUserRole == UserRole.coach &&
      challenge.userId == widget.currentUserId;

    return RefreshIndicator(
      color: primary,
      onRefresh: _refreshFeedSilently,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Card(
            color: AppColors.surfaceLow.withValues(alpha: 0.92),
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                    onSelectionChanged: canCreateChallenges ? (selection) {
                      setState(() {
                        _composerType = selection.first;
                        _error = null;
                      });
                    } : null,
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
                        onPressed: _submittingChallenge
                            ? null
                            : _publishChallenge,
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
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.surfaceLow.withValues(alpha: 0.92),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: secondary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      settings.tx('ACTIVE CHALLENGE', 'التحدي الحالي'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontSize: 10,
                      ),
                    ),
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
                              : settings.tx('Apply to Challenge', 'قدّم على التحدي'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          canReviewApplicants
                              ? settings.tx(
                                  '${challenge.challengeApplicantCount} applicant(s) so far.',
                                  'عدد المتقدمين حتى الآن: ${challenge.challengeApplicantCount}.',
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
                    if (challenge.challengeApplicants.isEmpty)
                      Text(
                        settings.tx(
                          'No one has applied yet.',
                          'لسه محدش قدّم.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      ...challenge.challengeApplicants.map(
                        (application) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighest.withValues(
                              alpha: 0.68,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppColors.surfaceHigh,
                                backgroundImage:
                                    application.applicantAvatar.isNotEmpty
                                    ? NetworkImage(application.applicantAvatar)
                                    : null,
                                child: application.applicantAvatar.isEmpty
                                    ? Text(
                                        application.applicantName.isEmpty
                                            ? '?'
                                            : application
                                                  .applicantName[0]
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
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                settings.tx('ACTIVITY FEED', 'آخر النشاط'),
                style: Theme.of(context).textTheme.labelMedium,
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
          if (_filteredPosts.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  settings.tx('No feed activity yet.', 'لسه مفيش نشاط في الفيد.'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ..._filteredPosts.map((post) {
              final commentController = _commentController(post.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  color: AppColors.surfaceLow.withValues(alpha: 0.86),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
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
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '${post.userName} ${post.userId == widget.currentUserId ? settings.tx('(YOU)', '(إنت)') : ''}',
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: primary.withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Text(
                                          post.userTier,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: primary,
                                                fontSize: 10,
                                              ),
                                        ),
                                      ),
                                      if (post.isChallenge)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: secondary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            settings.tx('CHALLENGE', 'تحدي'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: secondary,
                                                  fontSize: 10,
                                                ),
                                          ),
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
                                value: '${post.volume.round()} ${settings.tx('kg', 'كجم')}',
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
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ),
                                    Text(
                                      '${lift.sets} ${settings.tx('sets', 'جملة')} • ${lift.weight.toStringAsFixed(1)}kg x ${lift.reps}',
                                      style: Theme.of(context).textTheme.bodySmall
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
                ),
              );
            }),
        ],
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
