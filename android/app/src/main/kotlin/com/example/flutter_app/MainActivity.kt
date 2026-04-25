package com.example.flutter_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL = "lifttier/notifications_migration"
		private const val SCHEDULED_NOTIFICATIONS_KEY = "scheduled_notifications"
		private const val FLUTTER_SCHEDULED_NOTIFICATIONS_KEY = "flutter.scheduled_notifications"
		private val SCHEDULED_NOTIFICATION_PREF_FILES = listOf(
			"scheduled_notifications",
			"flutter_local_notifications_plugin",
			"FlutterLocalNotificationsPlugin",
			"FlutterSharedPreferences"
		)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"clearLegacyScheduledNotifications" -> {
						try {
							for (prefName in SCHEDULED_NOTIFICATION_PREF_FILES) {
								val prefs = applicationContext.getSharedPreferences(prefName, MODE_PRIVATE)
								prefs
									.edit()
									.remove(SCHEDULED_NOTIFICATIONS_KEY)
									.remove(FLUTTER_SCHEDULED_NOTIFICATIONS_KEY)
									.apply()
							}
							result.success(true)
						} catch (e: Exception) {
							result.error("CACHE_CLEAR_FAILED", e.message, null)
						}
					}

					else -> result.notImplemented()
				}
			}
	}
}
