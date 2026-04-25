import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/gym_split.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  RealtimeChannel? _notificationsChannel;
  String? _activeUserId;
  bool _isArabic = false;
  bool _initialized = false;
  bool _exactAlarmSupported = true;

  static const _eventChannelId = 'lifttier-events';
  static const _eventChannelName = 'LiftTier Events';
  static const _eventChannelDescription =
      'Coach messages, social interactions, and challenges.';
  static const _splitChannelId = 'lifttier-split-reminders';
  static const _splitChannelName = 'Split Reminders';
  static const _splitChannelDescription =
      'Daily reminders based on the active split schedule.';

  static const _splitReminderBaseId = 8100;
  static const _splitReminderSlots = 14;
  static const _migrationChannel = MethodChannel(
    'lifttier/notifications_migration',
  );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings);
    await _requestPermissions();
    await _configureTimezone();

    _initialized = true;
  }

  Future<void> configureRealtimeNotifications({
    required String userId,
    required bool isArabic,
  }) async {
    await initialize();
    _isArabic = isArabic;

    if (_activeUserId == userId && _notificationsChannel != null) {
      return;
    }

    await stopRealtimeNotifications();

    _activeUserId = userId;
    final channel = Supabase.instance.client.channel(
      'user-notifications-$userId',
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'user_notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        final row = payload.newRecord;
        if (row.isEmpty) {
          return;
        }
        unawaited(_showRealtimeNotification(row));
      },
    );

    channel.subscribe();
    _notificationsChannel = channel;
  }

  Future<void> stopRealtimeNotifications() async {
    final channel = _notificationsChannel;
    _notificationsChannel = null;
    _activeUserId = null;

    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  Future<void> updateSplitReminders({
    required SplitSchedule? splitSchedule,
    required bool isArabic,
  }) async {
    await initialize();

    await _cancelSplitReminderSlotsWithRecovery();

    if (splitSchedule == null || splitSchedule.schedule.isEmpty) {
      return;
    }

    final usedWeekdays = <int>{};
    final scheduleEntries = splitSchedule.schedule;

    for (var i = 0; i < scheduleEntries.length; i++) {
      if (i >= _splitReminderSlots) {
        break;
      }

      final entry = scheduleEntries[i];
      final weekday = entry.date.weekday;
      if (usedWeekdays.contains(weekday)) {
        continue;
      }
      usedWeekdays.add(weekday);

      final label = isArabic
          ? (entry.labelAr.trim().isEmpty ? entry.label : entry.labelAr)
          : entry.label;
      final scheduled = _nextWeeklyInstance(weekday, hour: 8, minute: 0);

      await _scheduleSplitReminder(
        id: _splitReminderBaseId + i,
        label: label,
        scheduled: scheduled,
        isArabic: isArabic,
      );
    }
  }

  Future<void> _cancelSplitReminderSlotsWithRecovery() async {
    try {
      await _cancelSplitReminderSlots();
      return;
    } on PlatformException catch (error) {
      if (!_isLegacyAndroidTypeParameterIssue(error)) {
        rethrow;
      }
    }

    await _clearLegacyAndroidScheduledNotificationCache();

    try {
      await _cancelSplitReminderSlots();
    } on PlatformException catch (retryError) {
      if (!_isLegacyAndroidTypeParameterIssue(retryError)) {
        rethrow;
      }

      // The legacy cache may still be unreadable in this process; continue so
      // new split schedules can still be saved without crashing the UI.
    }
  }

  Future<void> _scheduleSplitReminder({
    required int id,
    required String label,
    required tz.TZDateTime scheduled,
    required bool isArabic,
  }) async {
    final mode = _exactAlarmSupported
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    try {
      await _scheduleSplitReminderWithMode(
        id: id,
        label: label,
        scheduled: scheduled,
        isArabic: isArabic,
        mode: mode,
      );
    } on PlatformException catch (error) {
      if (!_isExactAlarmDenied(error) || !_exactAlarmSupported) {
        rethrow;
      }

      _exactAlarmSupported = false;
      await _scheduleSplitReminderWithMode(
        id: id,
        label: label,
        scheduled: scheduled,
        isArabic: isArabic,
        mode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> _scheduleSplitReminderWithMode({
    required int id,
    required String label,
    required tz.TZDateTime scheduled,
    required bool isArabic,
    required AndroidScheduleMode mode,
  }) async {
    try {
      await _scheduleSplitReminderInternal(
        id: id,
        label: label,
        scheduled: scheduled,
        isArabic: isArabic,
        mode: mode,
      );
      return;
    } on PlatformException catch (error) {
      if (!_isLegacyAndroidTypeParameterIssue(error)) {
        rethrow;
      }
    }

    await _clearLegacyAndroidScheduledNotificationCache();

    try {
      await _scheduleSplitReminderInternal(
        id: id,
        label: label,
        scheduled: scheduled,
        isArabic: isArabic,
        mode: mode,
      );
    } on PlatformException catch (retryError) {
      if (!_isLegacyAndroidTypeParameterIssue(retryError)) {
        rethrow;
      }

      // Avoid blocking split setup when stale Android cache entries remain
      // unreadable in this process. Future app starts will run with cleared
      // cache and schedule reminders again.
    }
  }

  Future<void> _scheduleSplitReminderInternal({
    required int id,
    required String label,
    required tz.TZDateTime scheduled,
    required bool isArabic,
    required AndroidScheduleMode mode,
  }) {
    return _plugin.zonedSchedule(
      id,
      isArabic ? 'تذكير تمرينك اليوم' : 'Today\'s split reminder',
      isArabic
          ? 'نهارده يوم $label. يلا نتمرن.'
          : 'Today is $label day. Time to train.',
      scheduled,
      _splitNotificationDetails(),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: mode,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  bool _isExactAlarmDenied(PlatformException error) {
    if (!Platform.isAndroid) {
      return false;
    }

    final raw = '${error.code} ${error.message}'.toLowerCase();
    return raw.contains('exact_alarms_not_permitted') ||
        raw.contains('exact alarms are not permitted') ||
        raw.contains('schedule_exact_alarm');
  }

  bool _isLegacyAndroidTypeParameterIssue(PlatformException error) {
    if (!Platform.isAndroid) {
      return false;
    }

    final raw = '${error.code} ${error.message} ${error.details}'
        .toLowerCase();
    return raw.contains('missing type parameter');
  }

  Future<void> _cancelSplitReminderSlots() async {
    for (var i = 0; i < _splitReminderSlots; i++) {
      await _plugin.cancel(_splitReminderBaseId + i);
    }
  }

  Future<void> _clearLegacyAndroidScheduledNotificationCache() async {
    if (!Platform.isAndroid) {
      return;
    }

    await _migrationChannel.invokeMethod<bool>(
      'clearLegacyScheduledNotifications',
    );
  }

  Future<void> _showRealtimeNotification(Map<String, dynamic> row) async {
    final notificationId = _idFromString((row['id'] ?? '').toString());
    final type = (row['notification_type'] ?? '').toString();
    final fallbackTitle = (row['title'] ?? 'Notification').toString();
    final fallbackBody = (row['body'] ?? '').toString();

    final title = _localizedTitle(type, fallbackTitle);
    final body = _localizedBody(type, fallbackBody);

    await _plugin.show(
      notificationId,
      title,
      body,
      _eventNotificationDetails(),
    );
  }

  String _localizedTitle(String type, String fallback) {
    switch (type) {
      case 'coach_message':
        return _isArabic ? 'رسالة جديدة من الكوتش' : 'New coach message';
      case 'coach_split_suggestion':
        return _isArabic ? 'اقتراح سبليت جديد من الكوتش' : 'New split suggestion';
      case 'feed_reaction':
        return _isArabic ? 'تفاعل جديد على البوست' : 'New reaction on your post';
      case 'feed_comment':
        return _isArabic ? 'تعليق جديد على البوست' : 'New comment on your post';
      case 'challenge_application':
        return _isArabic ? 'متقدم جديد في التحدي' : 'New challenge applicant';
      case 'new_challenge':
        return _isArabic ? 'تحدي جديد من كوتش' : 'New coach challenge';
      default:
        return fallback;
    }
  }

  String _localizedBody(String type, String fallback) {
    if (fallback.trim().isNotEmpty) {
      return fallback;
    }

    switch (type) {
      case 'coach_message':
        return _isArabic
            ? 'افتح المحادثة وشوف الرسالة الجديدة.'
            : 'Open the chat to read the latest message.';
      case 'coach_split_suggestion':
        return _isArabic
            ? 'الكوتش بعتلك اقتراح سبليت جديد.'
            : 'Your coach sent you a new split suggestion.';
      case 'feed_reaction':
      case 'feed_comment':
        return _isArabic
            ? 'حد تفاعل مع آخر تحديث في الفيد.'
            : 'Someone interacted with your feed update.';
      case 'challenge_application':
        return _isArabic
            ? 'في متدرب قدم على التحدي بتاعك.'
            : 'A trainee has applied to your challenge.';
      case 'new_challenge':
        return _isArabic
            ? 'في تحدي جديد متاح دلوقتي.'
            : 'A new challenge is now available.';
      default:
        return '';
    }
  }

  NotificationDetails _eventNotificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _eventChannelId,
        _eventChannelName,
        channelDescription: _eventChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
  }

  NotificationDetails _splitNotificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _splitChannelId,
        _splitChannelName,
        channelDescription: _splitChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
  }

  tz.TZDateTime _nextWeeklyInstance(
    int weekday, {
    required int hour,
    required int minute,
  }) {
    var scheduled = tz.TZDateTime.now(tz.local);
    scheduled = tz.TZDateTime(
      tz.local,
      scheduled.year,
      scheduled.month,
      scheduled.day,
      hour,
      minute,
    );

    while (scheduled.weekday != weekday || !scheduled.isAfter(tz.TZDateTime.now(tz.local))) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  Future<void> _requestPermissions() async {
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin
    >();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

    final macImpl = _plugin.resolvePlatformSpecificImplementation<
      MacOSFlutterLocalNotificationsPlugin
    >();
    await macImpl?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _configureTimezone() async {
    tz.initializeTimeZones();

    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      final location = tz.getLocation(timezoneName);
      tz.setLocalLocation(location);
    } catch (_) {
      // Keep tz.local fallback when timezone detection fails.
    }
  }

  int _idFromString(String raw) {
    if (raw.trim().isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    }
    return raw.hashCode & 0x7fffffff;
  }
}
