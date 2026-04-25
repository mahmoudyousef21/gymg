import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/coach_hub.dart';
import '../../models/lift_entry.dart';
import '../../models/training_session.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/topological_background.dart';
import '../auth/profile_onboarding_screen.dart';
import 'ai_rehab_screen.dart';
import 'add_lift_sheet.dart';
import 'coaches_hub_screen.dart';
import 'dashboard_screen.dart';
import 'gym_splits_screen.dart';
import 'community_screen.dart';
import 'settings_sheet.dart';

enum HomeTab { dashboard, community, coaches, splits, rehab }

class HomeShell extends StatefulWidget {
  const HomeShell({required this.userId, required this.onSignOut, super.key});

  final String userId;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _service = SupabaseService.instance;
  final _notificationService = NotificationService.instance;

  bool _loading = true;
  bool _genderPromptShown = false;
  String? _error;
  AppUser? _profile;
  List<TrainingSession> _sessions = <TrainingSession>[];
  List<CoachProfileListing> _coachSpotlight = <CoachProfileListing>[];
  HomeTab _activeTab = HomeTab.dashboard;
  AppSettings? _listenedSettings;
  AppLanguage? _lastLanguage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _loadData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.appSettings;
    if (identical(settings, _listenedSettings)) {
      return;
    }

    _listenedSettings?.removeListener(_onSettingsChanged);
    _listenedSettings = settings;
    _lastLanguage = settings.language;
    _listenedSettings?.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    final settings = _listenedSettings;
    if (settings == null || !mounted) {
      return;
    }

    if (_lastLanguage == settings.language) {
      return;
    }

    _lastLanguage = settings.language;
    unawaited(_refreshLocalizedNotifications(settings.isArabic));
  }

  Future<void> _refreshLocalizedNotifications(bool isArabic) async {
    try {
      await _notificationService
          .configureRealtimeNotifications(
            userId: widget.userId,
            isArabic: isArabic,
          )
          .timeout(const Duration(seconds: 6));
      final splitSchedule = await _service
          .fetchSplitSchedule(widget.userId)
          .timeout(const Duration(seconds: 10));
      await _notificationService
          .updateSplitReminders(
            splitSchedule: splitSchedule,
            isArabic: isArabic,
          )
          .timeout(const Duration(seconds: 6));
    } catch (error, stackTrace) {
      dev.log(
        'Failed to refresh localized notifications after settings change.',
        name: 'HomeShell',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void dispose() {
    _listenedSettings?.removeListener(_onSettingsChanged);
    unawaited(_notificationService.stopRealtimeNotifications());
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final settings = context.appSettings;
      final isArabic = settings.isArabic;

      try {
        await _service.bumpLoginStreak().timeout(const Duration(seconds: 8));
      } catch (error, stackTrace) {
        dev.log(
          'bump_login_streak RPC is unavailable, continuing without streak update.',
          name: 'HomeShell',
          error: error,
          stackTrace: stackTrace,
        );
      }

      final profile = await _service
          .fetchProfile(widget.userId)
          .timeout(const Duration(seconds: 12));
      final sessions = await _service
          .fetchTrainingSessions(widget.userId)
          .timeout(const Duration(seconds: 12));
      final splitSchedule = await _service
          .fetchSplitSchedule(widget.userId)
          .timeout(const Duration(seconds: 12));

      var coachSpotlight = <CoachProfileListing>[];
      try {
        coachSpotlight = await _service
            .fetchCoachMarketplace(currentUserId: widget.userId)
            .timeout(const Duration(seconds: 10));
      } catch (error, stackTrace) {
        dev.log(
          'Coach marketplace unavailable while loading dashboard spotlight.',
          name: 'HomeShell',
          error: error,
          stackTrace: stackTrace,
        );
      }

      if (profile == null) {
        setState(() {
          _profile = null;
          _sessions = sessions;
          _coachSpotlight = coachSpotlight.take(3).toList();
          _loading = false;
        });
        return;
      }

      final derived = _deriveProfile(profile, sessions);

      if (derived.tier != profile.tier ||
          derived.totalLifted != profile.totalLifted ||
          derived.percentile != profile.percentile) {
        await _service
            .upsertProfile(derived)
            .timeout(const Duration(seconds: 10));
      }

      setState(() {
        _profile = derived;
        _sessions = sessions;
        _coachSpotlight = coachSpotlight.take(3).toList();
        _loading = false;
      });

      try {
        await _notificationService
            .configureRealtimeNotifications(
              userId: widget.userId,
              isArabic: isArabic,
            )
            .timeout(const Duration(seconds: 6));
        await _notificationService
            .updateSplitReminders(
              splitSchedule: splitSchedule,
              isArabic: isArabic,
            )
            .timeout(const Duration(seconds: 6));
      } catch (error, stackTrace) {
        dev.log(
          'Failed to configure local notifications.',
          name: 'HomeShell',
          error: error,
          stackTrace: stackTrace,
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptGenderIfMissing(derived);
      });
    } on TimeoutException catch (error) {
      if (!mounted) {
        return;
      }

      final timeoutMessage = context.appSettings.tx(
        'Server is taking too long to respond. Please retry.',
        'السيرفر اتأخر في الرد. حاول تاني.',
      );

      setState(() {
        _error = timeoutMessage;
        _loading = false;
      });
      dev.log(
        'HomeShell data load timed out.',
        name: 'HomeShell',
        error: error,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final networkError = _networkErrorMessage(error);
      setState(() {
        _error = networkError ?? error.toString();
        _loading = false;
      });

      if (networkError != null) {
        dev.log(
          'HomeShell network/DNS failure while loading data.',
          name: 'HomeShell',
          error: error,
        );
      }
    }
  }

  String? _networkErrorMessage(Object error) {
    final raw = error.toString().toLowerCase();
    final hasHostLookup =
        raw.contains('failed host lookup') ||
        raw.contains('no address associated with hostname');
    final hasSocketIssue =
        error is SocketException ||
        raw.contains('socketexception') ||
        raw.contains('network is unreachable');

    if (!hasHostLookup && !hasSocketIssue) {
      return null;
    }

    return context.appSettings.tx(
      'Cannot reach Supabase right now (network/DNS issue). Check internet, disable VPN/private DNS if enabled, then tap TRY AGAIN.',
      'مش قادرين نوصل لـ Supabase دلوقتي (مشكلة نت أو DNS). اتأكد من النت، واقفل VPN أو Private DNS لو شغال، وبعدها دوس حاول تاني.',
    );
  }

  AppUser _deriveProfile(AppUser profile, List<TrainingSession> sessions) {
    final prs = <String, double>{};
    for (final session in sessions) {
      for (final lift in session.lifts) {
        final effectiveWeight = lift.weight + (lift.addedWeight ?? 0);
        final current = prs[lift.name];
        if (current == null || effectiveWeight > current) {
          prs[lift.name] = effectiveWeight;
        }
      }
    }

    final highestWeight = prs.values.fold<double>(
      0,
      (maxWeight, weight) => weight > maxWeight ? weight : maxWeight,
    );

    const tiers = [
      'IRON',
      'BRONZE',
      'SILVER',
      'GOLD',
      'PLATINUM',
      'DIAMOND',
      'ELITE',
      'LEGENDARY',
    ];
    const thresholds = [45.0, 60.0, 75.0, 90.0, 110.0, 140.0, 180.0];

    var index = 0;
    for (var i = 0; i < thresholds.length; i++) {
      if (highestWeight >= thresholds[i]) {
        index = i + 1;
      }
    }

    final tier = tiers[index.clamp(0, tiers.length - 1)];
    final totalLifted = prs.values.fold<double>(
      0,
      (sum, weight) => sum + weight,
    );

    const percentileMap = {
      'IRON': 99,
      'BRONZE': 80,
      'SILVER': 60,
      'GOLD': 40,
      'PLATINUM': 20,
      'DIAMOND': 8,
      'ELITE': 2,
      'LEGENDARY': 0.2,
    };

    return profile.copyWith(
      tier: tier,
      totalLifted: double.parse(totalLifted.toStringAsFixed(2)),
      percentile: (percentileMap[tier] ?? 99).toDouble(),
    );
  }

  Future<void> _promptGenderIfMissing(AppUser profile) async {
    if (_genderPromptShown ||
        !mounted ||
        profile.gender != ProfileGender.unspecified) {
      return;
    }

    _genderPromptShown = true;
    final settings = context.appSettings;
    var selected = ProfileGender.male;

    final picked = await showDialog<ProfileGender>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(settings.tx('Profile update', 'تحديث البروفايل')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.tx(
                      'Choose your gender to calibrate AI rehab anatomy and gender ranking.',
                      'اختار النوع عشان نضبط تشريح التأهيل الذكي وترتيب النوع.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(settings.tx('Male', 'ذكر')),
                        selected: selected == ProfileGender.male,
                        onSelected: (_) {
                          setDialogState(() {
                            selected = ProfileGender.male;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text(settings.tx('Female', 'أنثى')),
                        selected: selected == ProfileGender.female,
                        onSelected: (_) {
                          setDialogState(() {
                            selected = ProfileGender.female;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  child: Text(settings.tx('Save', 'حفظ')),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    final updated = profile.copyWith(gender: picked);
    await _service.upsertProfile(updated);
    if (!mounted) {
      return;
    }

    setState(() {
      _profile = updated;
    });
  }

  Future<bool> _createSession(String name, List<LiftEntry> lifts) async {
    final settings = context.appSettings;
    try {
      await _service.createSessionWithLifts(
        userId: widget.userId,
        name: name,
        sessionDate: DateTime.now(),
        lifts: lifts,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              settings.tx(
                'Session saved to database.',
                'الجلسة اتحفظت في قاعدة البيانات.',
              ),
            ),
          ),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${settings.tx('Save failed', 'الحفظ فشل')}: $error'),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> _appendSession(String sessionId, List<LiftEntry> lifts) async {
    final settings = context.appSettings;
    try {
      await _service.appendLiftsToSession(
        userId: widget.userId,
        sessionId: sessionId,
        lifts: lifts,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              settings.tx(
                'Lifts appended successfully.',
                'الرفعات اتضافت بنجاح.',
              ),
            ),
          ),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${settings.tx('Update failed', 'التحديث فشل')}: $error',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final settings = context.appSettings;
    try {
      await _service.deleteSession(userId: widget.userId, sessionId: sessionId);
      await _loadData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${settings.tx('Delete failed', 'المسح فشل')}: $error'),
        ),
      );
    }
  }

  Future<void> _deleteLift(String sessionId, String liftId) async {
    final settings = context.appSettings;
    try {
      await _service.deleteLift(
        userId: widget.userId,
        sessionId: sessionId,
        liftId: liftId,
      );
      await _loadData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${settings.tx('Lift delete failed', 'مسح الرفعة فشل')}: $error',
          ),
        ),
      );
    }
  }

  void _openAddLiftSheet() {
    if (_profile == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddLiftSheet(
        userId: widget.userId,
        profile: _profile!,
        sessions: _sessions,
        onCreateSession: _createSession,
        onAppendSession: _appendSession,
      ),
    );
  }

  Future<void> _saveProfile(AppUser profile) async {
    await _service.upsertProfile(profile);
    if (!mounted) {
      return;
    }

    setState(() {
      _profile = profile;
    });

    await _loadData();
  }

  void _openSettingsSheet() {
    if (_profile == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SettingsSheet(
        profile: _profile!,
        onSaveProfile: _saveProfile,
        onSignOut: widget.onSignOut,
      ),
    );
  }

  void _onTabSelected(HomeTab tab) {
    setState(() {
      _activeTab = tab;
    });
  }

  String _tabLabel(HomeTab tab, AppSettings settings) {
    switch (tab) {
      case HomeTab.dashboard:
        return settings.tx('Dashboard', 'الرئيسية');
      case HomeTab.community:
        return settings.tx('Community', 'المجتمع');
      case HomeTab.coaches:
        return settings.tx('Coaches', 'الكوتشات');
      case HomeTab.splits:
        return settings.tx('Splits', 'السبليت');
      case HomeTab.rehab:
        return settings.tx('AI Rehab', 'تأهيل ذكي');
    }
  }

  Widget _buildBody() {
    final profile = _profile;
    if (profile == null) {
      return const SizedBox.shrink();
    }

    switch (_activeTab) {
      case HomeTab.dashboard:
        return DashboardScreen(
          profile: profile,
          sessions: _sessions,
          coachSpotlight: _coachSpotlight,
          onOpenCoaches: () => _onTabSelected(HomeTab.coaches),
          onDeleteSession: _deleteSession,
          onDeleteLift: _deleteLift,
        );
      case HomeTab.community:
        return CommunityScreen(
          profile: profile,
          currentUserId: widget.userId,
        );
      case HomeTab.coaches:
        return CoachesHubScreen(userId: widget.userId, profile: profile);
      case HomeTab.splits:
        return GymSplitsScreen(userId: widget.userId);
      case HomeTab.rehab:
        return AIRehabScreen(profile: profile, sessions: _sessions);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return Scaffold(
        body: TopologicalBackground(
          child: Center(child: CircularProgressIndicator(color: primary)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: TopologicalBackground(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.tx(
                          'Failed to load data',
                          'تحميل البيانات فشل',
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: Text(settings.tx('TRY AGAIN', 'حاول تاني')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_profile == null) {
      return ProfileOnboardingScreen(
        userId: widget.userId,
        onCompleted: (profile) {
          setState(() {
            _profile = profile;
          });
          _loadData();
        },
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;
    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop
          ? null
          : _MobileSidebarDrawer(
              settings: settings,
              activeTab: _activeTab,
              profile: _profile!,
              onTabChanged: _onTabSelected,
              onAddLift: _openAddLiftSheet,
              onOpenSettings: _openSettingsSheet,
              onSignOut: widget.onSignOut,
            ),
      drawerScrimColor: Colors.black.withValues(alpha: 0.45),
      body: TopologicalBackground(
        child: SafeArea(
          child: Row(
            children: [
              if (isDesktop)
                _DesktopSidebar(
                  settings: settings,
                  activeTab: _activeTab,
                  profile: _profile!,
                  onTabChanged: _onTabSelected,
                  onAddLift: _openAddLiftSheet,
                  onOpenSettings: _openSettingsSheet,
                  onSignOut: widget.onSignOut,
                ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      settings: settings,
                      title: _tabLabel(_activeTab, settings),
                      profile: _profile!,
                      onOpenSettings: _openSettingsSheet,
                      onSignOut: widget.onSignOut,
                      onOpenMenu: isDesktop
                          ? null
                          : () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: KeyedSubtree(
                          key: ValueKey<HomeTab>(_activeTab),
                          child: _buildBody(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isDesktop
          ? null
          : _NeonAddFab(onPressed: _openAddLiftSheet),
      bottomNavigationBar: isDesktop ? null : SizedBox.shrink() /* Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLow.withValues(alpha: 0.62),
                      border: Border.all(
                        color: AppColors.outline.withValues(alpha: 0.16),
                      ),
                    ),
                    child: NavigationBar(
                      height: 74,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      selectedIndex: _activeTab.index,
                      onDestinationSelected: (index) {
                        _onTabSelected(HomeTab.values[index]);
                      },
                      destinations: [
                        NavigationDestination(
                          icon: const Icon(Icons.dashboard_outlined),
                          selectedIcon: const Icon(Icons.dashboard),
                          label: settings.tx('Home', 'الرئيسية'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.groups_outlined),
                          selectedIcon: const Icon(Icons.groups),
                          label: settings.tx('Social', 'الفيد'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.school_outlined),
                          selectedIcon: const Icon(Icons.school),
                          label: settings.tx('Coaches', 'الكوتشات'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.calendar_month_outlined),
                          selectedIcon: const Icon(Icons.calendar_month),
                          label: settings.tx('Splits', 'السبليت'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.emoji_events_outlined),
                          selectedIcon: const Icon(Icons.emoji_events),
                          label: settings.tx('Rank', 'الترتيب'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.favorite_outline),
                          selectedIcon: const Icon(Icons.favorite),
                          label: settings.tx('AI', 'تأهيل'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    */,
    );
  }
}

class _MobileSidebarDrawer extends StatelessWidget {
  const _MobileSidebarDrawer({
    required this.settings,
    required this.activeTab,
    required this.profile,
    required this.onTabChanged,
    required this.onAddLift,
    required this.onOpenSettings,
    required this.onSignOut,
  });

  final AppSettings settings;
  final HomeTab activeTab;
  final AppUser profile;
  final ValueChanged<HomeTab> onTabChanged;
  final VoidCallback onAddLift;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onSignOut;

  void _closeAndRun(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    Future.microtask(action);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final tabs = <(HomeTab, IconData, String)>[
      (
        HomeTab.dashboard,
        Icons.dashboard,
        settings.tx('Dashboard', 'الرئيسية'),
      ),
      (HomeTab.community, Icons.groups, settings.tx('Community', 'المجتمع')),
      (HomeTab.coaches, Icons.school, settings.tx('Coaches', 'الكوتشات')),
      (HomeTab.splits, Icons.calendar_month, settings.tx('Splits', 'السبليت')),
      (HomeTab.rehab, Icons.favorite, settings.tx('AI Rehab', 'تأهيل ذكي')),
    ];

    return SizedBox(
      width: 320,
      child: Drawer(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(28),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceLow.withValues(alpha: 0.94),
                border: Border(
                  right: BorderSide(
                    color: AppColors.outline.withValues(alpha: 0.18),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 28,
                    offset: const Offset(8, 0),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LIFTTIER',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: primary,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: 0.7,
                                ),
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.surfaceHighest,
                              backgroundImage: profile.avatarUrl.isNotEmpty
                                  ? NetworkImage(profile.avatarUrl)
                                  : null,
                              child: profile.avatarUrl.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                      color: AppColors.onSurfaceVariant,
                                    )
                                  : null,
                            ),
                            title: Text(
                              profile.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            subtitle: Text(
                              '${profile.tier} • ${profile.totalLifted.toStringAsFixed(1)}kg',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: AppColors.outline.withValues(alpha: 0.18)),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                        children: [
                          ...tabs.map((entry) {
                            final tab = entry.$1;
                            final selected = activeTab == tab;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                selected: selected,
                                selectedTileColor: primary.withValues(
                                  alpha: 0.14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                leading: Icon(
                                  entry.$2,
                                  color: selected
                                      ? primary
                                      : AppColors.onSurfaceVariant,
                                ),
                                title: Text(
                                  settings.isArabic
                                      ? entry.$3
                                      : entry.$3.toUpperCase(),
                                ),
                                onTap: () {
                                  _closeAndRun(context, () {
                                    onTabChanged(tab);
                                  });
                                },
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              _closeAndRun(context, onAddLift);
                            },
                            icon: const Icon(Icons.add),
                            label: Text(settings.tx('ADD LIFT', 'سجل رفعة')),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              _closeAndRun(context, onOpenSettings);
                            },
                            icon: const Icon(Icons.settings),
                            label: Text(settings.tx('SETTINGS', 'الإعدادات')),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              _closeAndRun(context, () {
                                unawaited(onSignOut());
                              });
                            },
                            icon: const Icon(Icons.logout),
                            label: Text(settings.tx('LOG OUT', 'تسجيل الخروج')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.error.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.settings,
    required this.activeTab,
    required this.profile,
    required this.onTabChanged,
    required this.onAddLift,
    required this.onOpenSettings,
    required this.onSignOut,
  });

  final AppSettings settings;
  final HomeTab activeTab;
  final AppUser profile;
  final ValueChanged<HomeTab> onTabChanged;
  final VoidCallback onAddLift;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final tabs = <(HomeTab, IconData, String)>[
      (
        HomeTab.dashboard,
        Icons.dashboard,
        settings.tx('Dashboard', 'الرئيسية'),
      ),
      (HomeTab.community, Icons.groups, settings.tx('Community', 'المجتمع')),
      (HomeTab.coaches, Icons.school, settings.tx('Coaches', 'الكوتشات')),
      (HomeTab.splits, Icons.calendar_month, settings.tx('Splits', 'السبليت')),
      (HomeTab.rehab, Icons.favorite, settings.tx('AI Rehab', 'تأهيل ذكي')),
    ];

    return Container(
      width: 270,
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'LIFTTIER',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: primary,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surfaceHighest,
                backgroundImage: profile.avatarUrl.isNotEmpty
                    ? NetworkImage(profile.avatarUrl)
                    : null,
                child: profile.avatarUrl.isEmpty
                    ? const Icon(
                        Icons.person,
                        color: AppColors.onSurfaceVariant,
                      )
                    : null,
              ),
              title: Text(profile.name),
              subtitle: Text(
                '${profile.tier} • ${profile.totalLifted.toStringAsFixed(1)}kg',
              ),
            ),
            const SizedBox(height: 12),
            ...tabs.map((entry) {
              final tab = entry.$1;
              final selected = activeTab == tab;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => onTabChanged(tab),
                  icon: Icon(entry.$2),
                  label: Text(
                    settings.isArabic ? entry.$3 : entry.$3.toUpperCase(),
                  ),
                  style: FilledButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    backgroundColor: selected
                        ? primary.withValues(alpha: 0.15)
                        : AppColors.surfaceLow.withValues(alpha: 0.7),
                    foregroundColor: selected
                        ? primary
                        : AppColors.onSurfaceVariant,
                    elevation: 0,
                    side: BorderSide(
                      color: selected
                          ? primary.withValues(alpha: 0.42)
                          : AppColors.outline.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onAddLift,
              icon: const Icon(Icons.add),
              label: Text(settings.tx('ADD LIFT', 'سجل رفعة')),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings),
              label: Text(settings.tx('SETTINGS', 'الإعدادات')),
              style: FilledButton.styleFrom(alignment: Alignment.centerLeft),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
              label: Text(settings.tx('LOG OUT', 'تسجيل الخروج')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.settings,
    required this.title,
    required this.profile,
    required this.onOpenSettings,
    required this.onSignOut,
    required this.onOpenMenu,
  });

  final AppSettings settings;
  final String title;
  final AppUser profile;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onSignOut;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 430;
    final media = MediaQuery.of(context);
    final clampedMedia = media.copyWith(
      textScaler: media.textScaler.clamp(
        minScaleFactor: 0.88,
        maxScaleFactor: 1.06,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(
                    AppColors.surfaceLow,
                    primary,
                    0.08,
                  )!.withValues(alpha: 0.84),
                  AppColors.surfaceHigh.withValues(alpha: 0.76),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.outline.withValues(alpha: 0.15),
              ),
            ),
            child: MediaQuery(
              data: clampedMedia,
              child: Row(
                children: [
                  if (onOpenMenu != null) ...[
                    IconButton(
                      tooltip: settings.tx('Menu', 'القائمة'),
                      onPressed: onOpenMenu,
                      icon: const Icon(Icons.menu_rounded),
                    ),
                    const SizedBox(width: 2),
                  ],
                  Expanded(
                    child: Text(
                      settings.isArabic ? title : title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  if (!isCompact)
                    IconButton(
                      tooltip: settings.tx('Reload', 'تحديث'),
                      onPressed: () {
                        final state = context
                            .findAncestorStateOfType<_HomeShellState>();
                        state?._loadData();
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  IconButton(
                    tooltip: settings.tx('Settings', 'الإعدادات'),
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighest.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.outline.withValues(alpha: 0.25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.26),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department,
                          size: 16,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${profile.loginStreak}d',
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurface,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.surfaceHighest,
                      backgroundImage: profile.avatarUrl.isNotEmpty
                          ? NetworkImage(profile.avatarUrl)
                          : null,
                      child: profile.avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 18,
                              color: AppColors.onSurfaceVariant,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: settings.tx('Sign out', 'تسجيل الخروج'),
                      onPressed: onSignOut,
                      icon: const Icon(Icons.logout),
                    ),
                  ] else ...[
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded),
                      color: AppColors.surfaceHigh,
                      onSelected: (value) {
                        if (value == 'reload') {
                          final state = context
                              .findAncestorStateOfType<_HomeShellState>();
                          state?._loadData();
                          return;
                        }
                        if (value == 'logout') {
                          onSignOut();
                        }
                      },
                      itemBuilder: (menuContext) {
                        return [
                          PopupMenuItem<String>(
                            value: 'reload',
                            child: Text(settings.tx('Reload', 'تحديث')),
                          ),
                          PopupMenuItem<String>(
                            value: 'logout',
                            child: Text(
                              settings.tx('Sign out', 'تسجيل الخروج'),
                            ),
                          ),
                        ];
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeonAddFab extends StatelessWidget {
  const _NeonAddFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.primaryContainer],
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        child: const Icon(Icons.add),
      ),
    );
  }
}
