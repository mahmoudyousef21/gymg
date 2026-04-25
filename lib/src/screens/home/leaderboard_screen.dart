import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/leaderboard_athlete.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';

enum _LeaderboardGenderFilter { all, male, female }

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({
    required this.profile,
    required this.currentUserId,
    super.key,
  });

  final AppUser profile;
  final String currentUserId;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _service = SupabaseService.instance;

  bool _loading = true;
  String? _error;
  List<LeaderboardAthlete> _athletes = <LeaderboardAthlete>[];
  late _LeaderboardGenderFilter _genderFilter;

  @override
  void initState() {
    super.initState();
    _genderFilter = switch (widget.profile.gender) {
      ProfileGender.male => _LeaderboardGenderFilter.male,
      ProfileGender.female => _LeaderboardGenderFilter.female,
      ProfileGender.unspecified => _LeaderboardGenderFilter.all,
    };
    _loadLeaderboard();
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

  Future<void> _loadLeaderboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

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
                    settings.tx(
                      'Failed to load leaderboard',
                      'تعذر تحميل الترتيب',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(_error!),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadLeaderboard,
                    child: Text(settings.tx('RETRY', 'حاول تاني')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final tierProgress = _tierProgress(settings);
  final currentAthlete = _currentAthlete();

    return RefreshIndicator(
      color: primary,
      onRefresh: _loadLeaderboard,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Text(
            settings.tx('COMPETITIVE RANKINGS', 'الترتيب التنافسي'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(
            settings.tx('THE IRON STANDINGS', 'ترتيب الحديد'),
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.surfaceLow.withValues(alpha: 0.92),
            child: Padding(
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
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: secondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: AppColors.surfaceLow.withValues(alpha: 0.86),
            child: Padding(
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
                      valueColor: AlwaysStoppedAnimation(primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            settings.tx('GLOBAL LEADERBOARD', 'الترتيب العالمي'),
            style: Theme.of(context).textTheme.labelMedium,
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
              _loadLeaderboard();
            },
          ),
          const SizedBox(height: 8),
          if (_athletes.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  settings.tx(
                    'No athletes yet. Start logging sessions to appear here.',
                    'لسه مفيش لاعيبة هنا. سجّل جلساتك عشان تظهر.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ..._athletes.map(
              (athlete) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  color: athlete.id == widget.currentUserId
                      ? primary.withValues(alpha: 0.14)
                      : AppColors.surfaceLow.withValues(alpha: 0.86),
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: athlete.rank == 1
                                    ? secondary
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
      ),
    );
  }
}
