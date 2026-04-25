import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

enum AppLanguage { en, arEg }

enum AppAccent { lime, red, blue, yellow }

class AppSettings extends ChangeNotifier {
  static const _languageKey = 'app.language';
  static const _accentKey = 'app.accent';
  static const _animalComparisonKey = 'app.showAnimalComparison';

  AppLanguage _language = AppLanguage.en;
  AppAccent _accent = AppAccent.blue;
  bool _showAnimalComparison = true;
  bool _hydrated = false;
  bool _disposed = false;

  AppLanguage get language => _language;
  AppAccent get accent => _accent;
  bool get showAnimalComparison => _showAnimalComparison;
  bool get hydrated => _hydrated;

  bool get isArabic => _language == AppLanguage.arEg;

  Color get primaryColor {
    return switch (_accent) {
      AppAccent.lime => AppColors.lime,
      AppAccent.red => AppColors.secondary,
      AppAccent.blue => AppColors.blue,
      AppAccent.yellow => AppColors.yellow,
    };
  }

  Color get secondaryColor {
    return switch (_accent) {
      AppAccent.lime => const Color(0xFFE7FF8A),
      AppAccent.red => const Color(0xFFFFA28C),
      AppAccent.blue => AppColors.secondary,
      AppAccent.yellow => const Color(0xFFFFE78A),
    };
  }

  TextDirection get textDirection =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;

  String tx(String english, String egyptianArabic) {
    if (!isArabic) {
      return english;
    }
    return _egyptianize(egyptianArabic);
  }

  static const List<({String from, String to})> _egyptianReplacements = [
    (from: 'إعادة تعيين كلمة السر', to: 'تغيير كلمة السر'),
    (from: 'إرسال الرابط', to: 'ابعت اللينك'),
    (from: 'جلسة تمرين', to: 'تمرينه'),
    (from: 'تحديث البروفايل', to: 'تعديل البروفايل'),
    (from: 'التعليق فشل', to: 'الكومنت فشل'),
    (from: 'التفاعل فشل', to: 'الريأكشن فشل'),
    (from: 'نشر التحدي فشل', to: 'نزول التحدي فشل'),
    (from: 'نوع التحدي', to: 'نوع الشالنج'),
    (from: 'الترتيب العالمي', to: 'ترتيب العالم'),
    (from: 'الترتيب التنافسي', to: 'الرانكينج التنافسي'),
    (from: 'ترتيب الحديد', to: 'رانكينج الوحوش'),
    (from: 'تعذر تحميل', to: 'ماعرفناش نحمّل'),
    (from: 'حاول تاني', to: 'جرّب تاني'),
    (from: 'إظهار كلمة السر', to: 'بيّن كلمة السر'),
    (from: 'إخفاء كلمة السر', to: 'خبّي كلمة السر'),
    (from: 'نسيت كلمة السر؟', to: 'ناسي كلمة السر؟'),
    (from: 'النهارده', to: 'النهاردة'),
    (from: 'مبتدئ', to: 'لسه بادئ'),
    (from: 'متوسط', to: 'متوسط مستوى'),
    (from: 'متقدم', to: 'جامد'),
    (from: 'أنثى', to: 'ست'),
    (from: 'ذكر', to: 'راجل'),
    (from: 'الذكاء الاصطناعي', to: 'الـAI'),
  ];

  String _egyptianize(String input) {
    var output = input;
    for (final replacement in _egyptianReplacements) {
      output = output.replaceAll(replacement.from, replacement.to);
    }
    return output;
  }

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) {
      return;
    }

    final nextLanguage = _decodeLanguage(prefs.getString(_languageKey));
    final nextAccent = _decodeAccent(prefs.getString(_accentKey));
    final nextAnimalToggle = prefs.getBool(_animalComparisonKey) ?? true;

    final changed =
        nextLanguage != _language ||
        nextAccent != _accent ||
        nextAnimalToggle != _showAnimalComparison ||
        !_hydrated;

    _language = nextLanguage;
    _accent = nextAccent;
    _showAnimalComparison = nextAnimalToggle;
    _hydrated = true;

    if (changed && !_disposed) {
      notifyListeners();
    }
  }

  void setLanguage(AppLanguage nextLanguage) {
    if (_disposed) {
      return;
    }
    if (nextLanguage == _language) {
      return;
    }
    _language = nextLanguage;
    notifyListeners();
    unawaited(_persist());
  }

  void setAccent(AppAccent nextAccent) {
    if (_disposed) {
      return;
    }
    if (nextAccent == _accent) {
      return;
    }
    _accent = nextAccent;
    notifyListeners();
    unawaited(_persist());
  }

  void setShowAnimalComparison(bool enabled) {
    if (_disposed) {
      return;
    }
    if (enabled == _showAnimalComparison) {
      return;
    }
    _showAnimalComparison = enabled;
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() async {
    if (_disposed) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) {
      return;
    }
    await prefs.setString(_languageKey, _encodeLanguage(_language));
    await prefs.setString(_accentKey, _encodeAccent(_accent));
    await prefs.setBool(_animalComparisonKey, _showAnimalComparison);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String _encodeLanguage(AppLanguage language) {
    return switch (language) {
      AppLanguage.en => 'en',
      AppLanguage.arEg => 'ar-eg',
    };
  }

  AppLanguage _decodeLanguage(String? raw) {
    return raw == 'ar-eg' ? AppLanguage.arEg : AppLanguage.en;
  }

  String _encodeAccent(AppAccent accent) {
    return switch (accent) {
      AppAccent.lime => 'lime',
      AppAccent.red => 'red',
      AppAccent.blue => 'blue',
      AppAccent.yellow => 'yellow',
    };
  }

  AppAccent _decodeAccent(String? raw) {
    return switch (raw) {
      'lime' => AppAccent.lime,
      'blue' => AppAccent.blue,
      'yellow' => AppAccent.yellow,
      _ => AppAccent.blue,
    };
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    required super.notifier,
    required super.child,
    super.key,
  });

  static AppSettings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    if (scope == null || scope.notifier == null) {
      throw FlutterError(
        'AppSettingsScope is missing above this widget in the tree.',
      );
    }
    return scope.notifier!;
  }
}

extension AppSettingsBuildContextX on BuildContext {
  AppSettings get appSettings => AppSettingsScope.of(this);
}
