import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../localization/egyptian_gym_lexicon.dart';
import '../../models/app_user.dart';
import '../../models/coach_hub.dart';
import '../../models/training_session.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../utils/strength_evaluator.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.profile,
    required this.sessions,
    required this.coachSpotlight,
    required this.onOpenCoaches,
    required this.onDeleteSession,
    required this.onDeleteLift,
    super.key,
  });

  final AppUser profile;
  final List<TrainingSession> sessions;
  final List<CoachProfileListing> coachSpotlight;
  final VoidCallback onOpenCoaches;
  final Future<void> Function(String sessionId) onDeleteSession;
  final Future<void> Function(String sessionId, String liftId) onDeleteLift;

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final sortedSessions = sessions.toList()
      ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
    final records = _buildPersonalRecords(sortedSessions);
    final peak = _peakLift(records);
    final weeklyVolume = _weeklyVolume(sortedSessions);
    final todaySession = _todaySession(sortedSessions);
    final tomorrowSession = _tomorrowSession(sortedSessions, todaySession);
    final activityDaysThisMonth = _calendarActivityDays(
      sortedSessions,
      DateTime.now(),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StreakSplashCard(
            profile: profile,
            settings: settings,
            peakLabel: peak?.key,
            peakWeight: peak?.value,
            weeklyVolume: weeklyVolume,
            totalSessions: sortedSessions.length,
          ),
          const SizedBox(height: 16),
          _CoachHeroBanner(
            settings: settings,
            coaches: coachSpotlight,
            onOpenCoaches: onOpenCoaches,
          ),
          const SizedBox(height: 16),
          _StreakCalendarCard(
            settings: settings,
            currentStreak: profile.loginStreak,
            activeDays: activityDaysThisMonth,
          ),
          const SizedBox(height: 16),
          _ExercisePlanSection(
            settings: settings,
            todaySession: todaySession,
            tomorrowSession: tomorrowSession,
          ),
          const SizedBox(height: 16),
          _ImprovementsPanel(sessions: sortedSessions),
          const SizedBox(height: 16),
          Text(
            settings.tx('SESSION HISTORY', 'سجل الجلسات'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          if (sortedSessions.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Text(
                  settings.tx(
                    'No sessions yet. Use Add Lift to create your first training session.',
                    'لسه مفيش جلسات. استخدم إضافة رفعة عشان تبدأ أول جلسة.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ...sortedSessions.map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  color: AppColors.surfaceLow.withValues(alpha: 0.7),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    title: Text(
                      session.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      DateFormat(
                        'EEE, MMM d • HH:mm',
                      ).format(session.sessionDate),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          settings.tx(
                            '${session.lifts.length} lifts',
                            '${session.lifts.length} رفعة',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        IconButton(
                          tooltip: settings.tx('Delete session', 'امسح الجلسة'),
                          onPressed: () async {
                            final shouldDelete =
                                await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(
                                      settings.tx(
                                        'Delete Session?',
                                        'تمسح الجلسة؟',
                                      ),
                                    ),
                                    content: Text(
                                      settings.tx(
                                        'This will permanently remove the full session.',
                                        'كده هتمسح الجلسة كلها نهائي.',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(
                                          settings.tx('Cancel', 'إلغاء'),
                                        ),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(
                                          settings.tx('Delete', 'امسح'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;
                            if (!shouldDelete) {
                              return;
                            }
                            await onDeleteSession(session.id);
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    children: [
                      ...session.lifts.map((lift) {
                        final strengthLine = StrengthEvaluator.strengthLine(
                          tierCode: lift.strengthTier,
                          ratio: lift.strengthRatio,
                          isArabic: settings.isArabic,
                        );
                        final animalLine = settings.showAnimalComparison
                            ? StrengthEvaluator.animalLine(
                                animalCode: lift.animalCode,
                                forceNewtons: lift.estimatedForceN,
                                isArabic: settings.isArabic,
                              )
                            : null;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      settings.isArabic
                                          ? EgyptianGymLexicon.term(lift.name)
                                          : lift.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                  Text(
                                    '${lift.sets} ${settings.tx('sets', 'جملة')} • ${lift.weight.toStringAsFixed(1)}kg x ${lift.reps}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: primary),
                                  ),
                                  IconButton(
                                    tooltip: settings.tx(
                                      'Delete lift',
                                      'امسح الرفعة',
                                    ),
                                    onPressed: () =>
                                        onDeleteLift(session.id, lift.id),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                strengthLine,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (animalLine != null)
                                Text(
                                  animalLine,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(fontSize: 11),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Map<String, double> _buildPersonalRecords(List<TrainingSession> history) {
    final prs = <String, double>{};
    for (final session in history) {
      for (final lift in session.lifts) {
        final current = prs[lift.name];
        if (current == null || lift.weight > current) {
          prs[lift.name] = lift.weight;
        }
      }
    }
    return prs;
  }

  MapEntry<String, double>? _peakLift(Map<String, double> records) {
    if (records.isEmpty) {
      return null;
    }
    final sorted = records.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first;
  }

  TrainingSession? _todaySession(List<TrainingSession> history) {
    for (final session in history) {
      if (session.isToday) {
        return session;
      }
    }
    return null;
  }

  TrainingSession? _tomorrowSession(
    List<TrainingSession> history,
    TrainingSession? today,
  ) {
    for (final session in history) {
      if (today != null && session.id == today.id) {
        continue;
      }
      return session;
    }
    return null;
  }

  Set<int> _calendarActivityDays(
    List<TrainingSession> history,
    DateTime month,
  ) {
    final days = <int>{};
    for (final session in history) {
      final date = session.sessionDate;
      if (date.year == month.year && date.month == month.month) {
        days.add(date.day);
      }
    }
    return days;
  }

  double _weeklyVolume(List<TrainingSession> history) {
    final since = DateTime.now().subtract(const Duration(days: 7));
    var volume = 0.0;
    for (final session in history) {
      if (session.sessionDate.isBefore(since)) {
        continue;
      }
      for (final lift in session.lifts) {
        volume += lift.weight * lift.reps * lift.sets;
      }
    }
    return volume;
  }
}

class _StreakSplashCard extends StatelessWidget {
  const _StreakSplashCard({
    required this.profile,
    required this.settings,
    required this.peakLabel,
    required this.peakWeight,
    required this.weeklyVolume,
    required this.totalSessions,
  });

  final AppUser profile;
  final AppSettings settings;
  final String? peakLabel;
  final double? peakWeight;
  final double weeklyVolume;
  final int totalSessions;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    final peakValue = peakLabel == null
        ? '--'
        : '${peakWeight?.toStringAsFixed(1)}kg ${settings.isArabic ? EgyptianGymLexicon.term(peakLabel!) : peakLabel!}';

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.surfaceLow.withValues(alpha: 0.94),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF11151D),
              Color.alphaBlend(
                secondary.withValues(alpha: 0.14),
                const Color(0xFF151A20),
              ),
              const Color(0xFF0F1319),
            ],
          ),
          border: Border.all(color: secondary.withValues(alpha: 0.22)),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -20,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: secondary.withValues(alpha: 0.14),
                ),
              ),
            ),
            Positioned(
              bottom: -36,
              left: -24,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withValues(alpha: 0.12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        settings.tx('BADPOWER', 'بادباور'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighest.withValues(
                            alpha: 0.78,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.outline.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          profile.tier,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Icon(
                      Icons.local_fire_department,
                      color: secondary,
                      size: 50,
                    ),
                  ),
                  Center(
                    child: Text(
                      '${profile.loginStreak}',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: secondary.withValues(alpha: 0.45),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      settings.tx('DAY STREAK', 'يوم ستريك'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      settings.tx(
                        'Keep the momentum going!',
                        'حافظ على الزخم!',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PulseStatPill(
                        label: settings.tx('Peak Lift', 'أفضل رفعة'),
                        value: peakValue,
                      ),
                      _PulseStatPill(
                        label: settings.tx('7d Volume', 'حجم ٧ أيام'),
                        value: '${weeklyVolume.toStringAsFixed(0)}kg',
                      ),
                      _PulseStatPill(
                        label: settings.tx('Sessions', 'الجلسات'),
                        value: '$totalSessions',
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

class _PulseStatPill extends StatelessWidget {
  const _PulseStatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.25)),
        color: AppColors.surfaceHighest.withValues(alpha: 0.72),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 10),
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

class _CoachHeroBanner extends StatelessWidget {
  const _CoachHeroBanner({
    required this.settings,
    required this.coaches,
    required this.onOpenCoaches,
  });

  final AppSettings settings;
  final List<CoachProfileListing> coaches;
  final VoidCallback onOpenCoaches;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    final showcase = coaches.isNotEmpty
        ? coaches
              .take(3)
              .map(
                (coach) => _CoachCardData(
                  name: coach.name.isEmpty
                      ? settings.tx('Coach', 'كوتش')
                      : coach.name,
                  specialty: coach.coachingSystem.isEmpty
                      ? settings.tx(
                          'Strength & Conditioning',
                          'قوة وتجهيز بدني',
                        )
                      : coach.coachingSystem,
                  detail: coach.subscriptionPrice > 0
                      ? settings.tx(
                          '${coach.subscriptionPrice.toStringAsFixed(0)} EGP / month',
                          '${coach.subscriptionPrice.toStringAsFixed(0)} جنيه / شهر',
                        )
                      : settings.tx('Book a Session', 'احجز جلسة'),
                  avatarUrl: coach.avatarUrl,
                ),
              )
              .toList(growable: false)
        : <_CoachCardData>[
            _CoachCardData(
              name: 'Alex Rivera',
              specialty: settings.tx(
                'Strength & Conditioning',
                'قوة وتجهيز بدني',
              ),
              detail: settings.tx('Book a Session', 'احجز جلسة'),
            ),
            _CoachCardData(
              name: 'Sarah Lee',
              specialty: settings.tx('HIIT & Mobility', 'هاي إنتنسيف ومرونة'),
              detail: settings.tx('Book a Session', 'احجز جلسة'),
            ),
            _CoachCardData(
              name: 'Mike Chen',
              specialty: settings.tx('Performance Nutrition', 'تغذية الأداء'),
              detail: settings.tx('Book a Session', 'احجز جلسة'),
            ),
          ];

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.surfaceLow.withValues(alpha: 0.94),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                secondary.withValues(alpha: 0.15),
                AppColors.surfaceLow,
              ),
              AppColors.surfaceHigh.withValues(alpha: 0.94),
              Color.alphaBlend(
                primary.withValues(alpha: 0.13),
                AppColors.surfaceLow,
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.tx(
                  'Unlock Your Potential with Expert Coaching',
                  'افتح أقصى إمكانياتك مع كوتشينج محترف',
                ),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 152,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: showcase.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    return _CoachSpotlightTile(
                      coach: showcase[index],
                      onTap: onOpenCoaches,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton(
                  onPressed: onOpenCoaches,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: secondary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(settings.tx('BOOK A SESSION', 'احجز جلسة')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachSpotlightTile extends StatelessWidget {
  const _CoachSpotlightTile({required this.coach, required this.onTap});

  final _CoachCardData coach;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return Container(
      width: 230,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surfaceHighest.withValues(alpha: 0.72),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: coach.avatarUrl != null && coach.avatarUrl!.isNotEmpty
                      ? Image.network(
                          coach.avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _coachAvatarFallback(),
                        )
                      : _coachAvatarFallback(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coach.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      coach.specialty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.surfaceLow.withValues(alpha: 0.82),
              border: Border.all(color: secondary.withValues(alpha: 0.32)),
            ),
            child: Text(
              coach.detail,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onTap,
              child: Text(context.appSettings.tx('Open', 'افتح')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coachAvatarFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2E34), Color(0xFF1A1C20)],
        ),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.24)),
      ),
      child: const Icon(Icons.person, color: AppColors.onSurfaceVariant),
    );
  }
}

class _CoachCardData {
  const _CoachCardData({
    required this.name,
    required this.specialty,
    required this.detail,
    this.avatarUrl,
  });

  final String name;
  final String specialty;
  final String detail;
  final String? avatarUrl;
}

class _StreakCalendarCard extends StatelessWidget {
  const _StreakCalendarCard({
    required this.settings,
    required this.currentStreak,
    required this.activeDays,
  });

  final AppSettings settings;
  final int currentStreak;
  final Set<int> activeDays;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    final firstWeekOffset = DateTime(now.year, now.month, 1).weekday % 7;
    final cellsCount = ((firstWeekOffset + daysInMonth + 6) ~/ 7) * 7;
    final goalDays = daysInMonth >= 25 ? 25 : daysInMonth;
    final progress = goalDays == 0
        ? 0.0
        : (activeDays.length / goalDays).clamp(0.0, 1.0);
    final weekLabels = settings.isArabic
        ? const ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س']
        : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final secondary = Theme.of(context).colorScheme.secondary;

    return Card(
      color: AppColors.surfaceLow.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        secondary,
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.tx('STREAK & DAY LOG', 'ستريك وسجل الأيام'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        settings.tx(
                          'Current streak with activity calendar',
                          'ستريكك الحالي مع تقويم النشاط',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      settings.tx('Current Streak', 'الستريك الحالي'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      settings.tx('$currentStreak Days', '$currentStreak يوم'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: weekLabels
                  .map(
                    (label) => Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellsCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                mainAxisExtent: 44,
              ),
              itemBuilder: (context, index) {
                final day = index - firstWeekOffset + 1;
                if (day <= 0 || day > daysInMonth) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: AppColors.surfaceHighest.withValues(alpha: 0.18),
                    ),
                  );
                }

                return _CalendarDayCell(
                  day: day,
                  isActive: activeDays.contains(day),
                  isToday: day == now.day,
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              settings.tx('Monthly Goal: Progress', 'هدف الشهر: التقدم'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: progress,
                valueColor: AlwaysStoppedAnimation<Color>(secondary),
                backgroundColor: AppColors.surfaceHighest,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                settings.tx(
                  '${activeDays.length}/$goalDays Days Active',
                  '${activeDays.length}/$goalDays يوم نشط',
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.isActive,
    required this.isToday,
  });

  final int day;
  final bool isActive;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isToday
              ? secondary.withValues(alpha: 0.85)
              : AppColors.outline.withValues(alpha: 0.22),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isActive
              ? [
                  secondary.withValues(alpha: 0.24),
                  AppColors.surfaceHighest.withValues(alpha: 0.95),
                ]
              : [
                  AppColors.surfaceHigh.withValues(alpha: 0.75),
                  AppColors.surfaceLow.withValues(alpha: 0.92),
                ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 4,
            right: 6,
            child: Text(
              '$day',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isActive
                    ? AppColors.onSurface
                    : AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          if (isActive)
            Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: secondary, width: 1.8),
                  color: Colors.transparent,
                ),
                child: Icon(Icons.check, size: 14, color: secondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExercisePlanSection extends StatelessWidget {
  const _ExercisePlanSection({
    required this.settings,
    required this.todaySession,
    required this.tomorrowSession,
  });

  final AppSettings settings;
  final TrainingSession? todaySession;
  final TrainingSession? tomorrowSession;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;
    final primary = Theme.of(context).colorScheme.primary;
    final todayExercises = _exerciseNames(
      todaySession,
      fallback: const [
        'Romanian Deadlift',
        'Bench Press (Barbell)',
        'Squat (High Bar)',
      ],
    );
    final tomorrowExercises = _exerciseNames(
      tomorrowSession,
      fallback: const ['Overhead Press (Barbell)', 'Pull Ups', 'Lunges'],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 760;
        if (useRow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ExerciseContainerCard(
                  heading: settings.tx('TODAY\'S EXERCISES', 'تمارين النهارده'),
                  subheading:
                      todaySession?.name ??
                      settings.tx(
                        'No session logged yet, suggested starter list.',
                        'لسه مفيش جلسة متسجلة، دي قائمة بداية مقترحة.',
                      ),
                  exerciseNames: todayExercises,
                  isArabic: settings.isArabic,
                  accent: secondary,
                  imageAssetPath: 'assets/images/anatomy/muscles_front.png',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ExerciseContainerCard(
                  heading: settings.tx('TOMORROW\'S EXERCISES', 'تمارين بكرة'),
                  subheading:
                      tomorrowSession?.name ??
                      settings.tx(
                        'Suggested from your recent training pattern.',
                        'اقتراح مبني على نمط تمرينك الأخير.',
                      ),
                  exerciseNames: tomorrowExercises,
                  isArabic: settings.isArabic,
                  accent: primary,
                  imageAssetPath: 'assets/images/anatomy/muscles_back.png',
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _ExerciseContainerCard(
              heading: settings.tx('TODAY\'S EXERCISES', 'تمارين النهارده'),
              subheading:
                  todaySession?.name ??
                  settings.tx(
                    'No session logged yet, suggested starter list.',
                    'لسه مفيش جلسة متسجلة، دي قائمة بداية مقترحة.',
                  ),
              exerciseNames: todayExercises,
              isArabic: settings.isArabic,
              accent: secondary,
              imageAssetPath: 'assets/images/anatomy/muscles_front.png',
            ),
            const SizedBox(height: 12),
            _ExerciseContainerCard(
              heading: settings.tx('TOMORROW\'S EXERCISES', 'تمارين بكرة'),
              subheading:
                  tomorrowSession?.name ??
                  settings.tx(
                    'Suggested from your recent training pattern.',
                    'اقتراح مبني على نمط تمرينك الأخير.',
                  ),
              exerciseNames: tomorrowExercises,
              isArabic: settings.isArabic,
              accent: primary,
              imageAssetPath: 'assets/images/anatomy/muscles_back.png',
            ),
          ],
        );
      },
    );
  }

  List<String> _exerciseNames(
    TrainingSession? session, {
    required List<String> fallback,
  }) {
    if (session == null || session.lifts.isEmpty) {
      return fallback;
    }

    final names = <String>[];
    for (final lift in session.lifts) {
      if (!names.contains(lift.name)) {
        names.add(lift.name);
      }
    }

    if (names.isEmpty) {
      return fallback;
    }

    return names.take(4).toList();
  }
}

class _ExerciseContainerCard extends StatelessWidget {
  const _ExerciseContainerCard({
    required this.heading,
    required this.subheading,
    required this.exerciseNames,
    required this.isArabic,
    required this.accent,
    required this.imageAssetPath,
  });

  final String heading;
  final String subheading;
  final List<String> exerciseNames;
  final bool isArabic;
  final Color accent;
  final String imageAssetPath;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.surfaceLow.withValues(alpha: 0.92),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.surfaceHigh.withValues(alpha: 0.92),
              Color.alphaBlend(
                accent.withValues(alpha: 0.12),
                AppColors.surfaceLow,
              ),
            ],
          ),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.25)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -12,
              bottom: -26,
              child: Opacity(
                opacity: 0.13,
                child: Image.asset(
                  imageAssetPath,
                  height: 170,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [accent, accent.withValues(alpha: 0.7)],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          heading,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subheading,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  ...exerciseNames
                      .take(4)
                      .map(
                        (exercise) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ExerciseRowTile(
                            exerciseName: exercise,
                            isArabic: isArabic,
                            accent: accent,
                          ),
                        ),
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

class _ExerciseRowTile extends StatelessWidget {
  const _ExerciseRowTile({
    required this.exerciseName,
    required this.isArabic,
    required this.accent,
  });

  final String exerciseName;
  final bool isArabic;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final localizedName = isArabic
        ? EgyptianGymLexicon.term(exerciseName)
        : exerciseName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: AppColors.surfaceLow.withValues(alpha: 0.68),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: accent.withValues(alpha: 0.16),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Icon(
              _exerciseIconForName(exerciseName),
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              localizedName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _exerciseIconForName(String exerciseName) {
  final normalized = exerciseName.toLowerCase();
  if (normalized.contains('deadlift') || normalized.contains('row')) {
    return Icons.fitness_center_rounded;
  }
  if (normalized.contains('bench') ||
      normalized.contains('press') ||
      normalized.contains('push')) {
    return Icons.sports_gymnastics_rounded;
  }
  if (normalized.contains('pull') || normalized.contains('chin')) {
    return Icons.vertical_align_top_rounded;
  }
  if (normalized.contains('squat') ||
      normalized.contains('lunge') ||
      normalized.contains('leg')) {
    return Icons.directions_run_rounded;
  }
  return Icons.local_fire_department_rounded;
}

class _ImprovementsPanel extends StatelessWidget {
  const _ImprovementsPanel({required this.sessions});

  final List<TrainingSession> sessions;

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    final ordered = sessions.toList()
      ..sort((a, b) => a.sessionDate.compareTo(b.sessionDate));

    if (ordered.length < 2) {
      return Card(
        color: AppColors.surfaceLow.withValues(alpha: 0.78),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            settings.tx(
              'Log at least 2 sessions to unlock your Improvements graphs.',
              'سجل جلستين على الأقل عشان تفتح رسوم التطور.',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final recent = ordered.length > 7
        ? ordered.sublist(ordered.length - 7)
        : ordered;

    final volumePoints = recent
        .map(
          (session) => _GraphPoint(
            label: DateFormat('MM/dd').format(session.sessionDate),
            value: _sessionVolume(session),
          ),
        )
        .toList();

    final strengthPoints = recent
        .map(
          (session) => _GraphPoint(
            label: DateFormat('MM/dd').format(session.sessionDate),
            value: _sessionBestEstimated1Rm(session),
          ),
        )
        .toList();

    final firstStrength = strengthPoints.first.value;
    final lastStrength = strengthPoints.last.value;
    final strengthDelta = lastStrength - firstStrength;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.surfaceLow.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [primary, secondary],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.tx('IMPROVEMENTS', 'التطورات'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: primary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        settings.tx(
                          'Track your momentum with session-based progress graphs.',
                          'تابع تقدمك برسوم مبنية على جلساتك الفعلية.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppColors.surfaceHighest.withValues(alpha: 0.46),
                border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _DeltaMetric(
                      label: settings.tx('Strength Delta', 'فارق القوة'),
                      value:
                          '${strengthDelta >= 0 ? '+' : ''}${strengthDelta.toStringAsFixed(1)}kg',
                      positive: strengthDelta >= 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DeltaMetric(
                      label: settings.tx('Sessions Tracked', 'جلسات متتبعة'),
                      value: '${recent.length}',
                      positive: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _GraphCard(
              title: settings.tx('Volume Momentum', 'زخم حجم التمرين'),
              subtitle: settings.tx(
                'Last sessions total volume',
                'حجم آخر الجلسات',
              ),
              child: _VolumeBars(points: volumePoints),
            ),
            const SizedBox(height: 10),
            _GraphCard(
              title: settings.tx(
                'Strength Trajectory (Estimated 1RM)',
                'مسار القوة (1RM تقديري)',
              ),
              subtitle: settings.tx(
                'Best lift per session over time',
                'أفضل رفعة بكل جلسة عبر الوقت',
              ),
              child: _StrengthLine(points: strengthPoints),
            ),
          ],
        ),
      ),
    );
  }

  double _sessionVolume(TrainingSession session) {
    var total = 0.0;
    for (final lift in session.lifts) {
      total += lift.weight * lift.reps * lift.sets;
    }
    return total;
  }

  double _sessionBestEstimated1Rm(TrainingSession session) {
    var best = 0.0;
    for (final lift in session.lifts) {
      final oneRm = lift.weight * (1 + (lift.reps / 30));
      if (oneRm > best) {
        best = oneRm;
      }
    }
    return best;
  }
}

class _GraphPoint {
  const _GraphPoint({required this.label, required this.value});

  final String label;
  final double value;
}

class _DeltaMetric extends StatelessWidget {
  const _DeltaMetric({
    required this.label,
    required this.value,
    required this.positive,
  });

  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final ok = Theme.of(context).colorScheme.secondary;
    final warn = Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: positive ? ok : warn,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _GraphCard extends StatelessWidget {
  const _GraphCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceHighest.withValues(alpha: 0.42),
            AppColors.surfaceHigh.withValues(alpha: 0.48),
          ],
        ),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _VolumeBars extends StatelessWidget {
  const _VolumeBars({required this.points});

  final List<_GraphPoint> points;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    final maxValue = points
        .map((point) => point.value)
        .fold<double>(0, (prev, value) => value > prev ? value : prev);

    return SizedBox(
      height: 166,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((point) {
          final ratio = maxValue <= 0
              ? 0.12
              : (point.value / maxValue).clamp(0.12, 1.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    point.value.toStringAsFixed(0),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: ratio,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [primary, secondary],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    point.label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StrengthLine extends StatelessWidget {
  const _StrengthLine({required this.points});

  final List<_GraphPoint> points;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final min = points
        .map((point) => point.value)
        .fold<double>(
          points.first.value,
          (prev, value) => value < prev ? value : prev,
        );
    final max = points
        .map((point) => point.value)
        .fold<double>(
          points.first.value,
          (prev, value) => value > prev ? value : prev,
        );

    return SizedBox(
      height: 160,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _LineGraphPainter(
                points: points,
                minY: min,
                maxY: max,
                color: primary,
              ),
              child: Container(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: points
                .map(
                  (point) => Expanded(
                    child: Text(
                      point.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontSize: 10),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LineGraphPainter extends CustomPainter {
  const _LineGraphPainter({
    required this.points,
    required this.minY,
    required this.maxY,
    required this.color,
  });

  final List<_GraphPoint> points;
  final double minY;
  final double maxY;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.36), color.withValues(alpha: 0.04)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final normalized = points.map((point) {
      final span = (maxY - minY).abs() < 0.001 ? 1.0 : (maxY - minY);
      return (point.value - minY) / span;
    }).toList();

    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < normalized.length; i++) {
      final x = (size.width / (normalized.length - 1)) * i;
      final y = size.height - (normalized[i] * (size.height - 6)) - 3;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    final endX = size.width;
    fillPath.lineTo(endX, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < normalized.length; i++) {
      final x = (size.width / (normalized.length - 1)) * i;
      final y = size.height - (normalized[i] * (size.height - 6)) - 3;
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineGraphPainter oldDelegate) {
    if (oldDelegate.points.length != points.length) {
      return true;
    }
    if (oldDelegate.minY != minY || oldDelegate.maxY != maxY) {
      return true;
    }
    for (var i = 0; i < points.length; i++) {
      if (oldDelegate.points[i].value != points[i].value ||
          oldDelegate.points[i].label != points[i].label) {
        return true;
      }
    }
    return oldDelegate.color != color;
  }
}
