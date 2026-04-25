import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    required this.profile,
    required this.onSaveProfile,
    required this.onSignOut,
    super.key,
  });

  final AppUser profile;
  final Future<void> Function(AppUser profile) onSaveProfile;
  final Future<void> Function() onSignOut;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _locationController;
  late final TextEditingController _avatarController;
  late ProfileGender _selectedGender;

  bool _saving = false;
  String? _saveMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _ageController = TextEditingController(
      text: widget.profile.age?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: widget.profile.weight?.toString() ?? '',
    );
    _heightController = TextEditingController(
      text: widget.profile.height?.toString() ?? '',
    );
    _locationController = TextEditingController(text: widget.profile.location);
    _avatarController = TextEditingController(text: widget.profile.avatarUrl);
    _selectedGender = widget.profile.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _locationController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
      _saveMessage = null;
    });

    final updated = widget.profile.copyWith(
      name: _nameController.text.trim().isEmpty
          ? widget.profile.name
          : _nameController.text.trim(),
      gender: _selectedGender,
      age: int.tryParse(_ageController.text.trim()),
      weight: double.tryParse(_weightController.text.trim()),
      height: double.tryParse(_heightController.text.trim()),
      location: _locationController.text.trim(),
      avatarUrl: _avatarController.text.trim(),
    );

    try {
      await widget.onSaveProfile(updated);
      if (!mounted) {
        return;
      }

      final settings = context.appSettings;
      setState(() {
        _saveMessage = settings.tx('Saved!', 'اتحفظت تمام');
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final settings = context.appSettings;
      setState(() {
        _saveMessage =
            '${settings.tx('Save failed', 'الحفظ فشل')}: ${error.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;

    final accents = <(AppAccent, String, String, Color)>[
      (AppAccent.lime, 'Neon Lime', 'ليموني نيون', AppColors.lime),
      (AppAccent.red, 'Neon Red', 'أحمر نيون', AppColors.primary),
      (AppAccent.blue, 'Neon Blue', 'أزرق نيون', AppColors.blue),
      (AppAccent.yellow, 'Neon Yellow', 'أصفر نيون', AppColors.yellow),
    ];

    return FractionallySizedBox(
      heightFactor: 0.93,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceLow,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 56,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        settings.tx('Settings', 'الإعدادات'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: primary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  children: [
                    Text(
                      settings.tx('Profile', 'بياناتك'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: settings.tx('Name', 'الاسم'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(
                        settings.tx('Account Role', 'نوع الحساب'),
                      ),
                      subtitle: Text(
                        '${userRoleLabel(widget.profile.role, isArabic: settings.isArabic)} • ${settings.tx('Locked after signup', 'ثابت بعد التسجيل')}',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: settings.tx('Age', 'السن'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: settings.tx(
                                'Weight (kg)',
                                'الوزن (كجم)',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _heightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: settings.tx('Height (cm)', 'الطول (سم)'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: settings.tx('Location', 'المكان'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _avatarController,
                      decoration: InputDecoration(
                        labelText: settings.tx('Avatar URL', 'لينك الصورة'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      settings.tx('Gender', 'النوع'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(settings.tx('Male', 'ذكر')),
                          selected: _selectedGender == ProfileGender.male,
                          onSelected: (_) {
                            setState(() {
                              _selectedGender = ProfileGender.male;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(settings.tx('Female', 'أنثى')),
                          selected: _selectedGender == ProfileGender.female,
                          onSelected: (_) {
                            setState(() {
                              _selectedGender = ProfileGender.female;
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(settings.tx('Unspecified', 'غير محدد')),
                          selected:
                              _selectedGender == ProfileGender.unspecified,
                          onSelected: (_) {
                            setState(() {
                              _selectedGender = ProfileGender.unspecified;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      settings.tx('Language', 'اللغة'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () =>
                                settings.setLanguage(AppLanguage.en),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  settings.language == AppLanguage.en
                                  ? primary
                                  : AppColors.surfaceHighest,
                              foregroundColor:
                                  settings.language == AppLanguage.en
                                  ? Colors.black
                                  : AppColors.onSurface,
                            ),
                            child: const Text('English'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () =>
                                settings.setLanguage(AppLanguage.arEg),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  settings.language == AppLanguage.arEg
                                  ? primary
                                  : AppColors.surfaceHighest,
                              foregroundColor:
                                  settings.language == AppLanguage.arEg
                                  ? Colors.black
                                  : AppColors.onSurface,
                            ),
                            child: const Text('العربية (مصري)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      settings.tx('App Color', 'لون التطبيق'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    ...accents.map((accent) {
                      final selected = settings.accent == accent.$1;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighest.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? primary.withValues(alpha: 0.8)
                                : AppColors.outline,
                          ),
                        ),
                        child: ListTile(
                          onTap: () => settings.setAccent(accent.$1),
                          leading: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: accent.$4,
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(settings.tx(accent.$2, accent.$3)),
                          trailing: selected
                              ? Icon(Icons.check, color: primary)
                              : null,
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: settings.showAnimalComparison,
                      title: Text(
                        settings.tx(
                          'Animal comparison in strength notes',
                          'مقارنة الحيوان في ملاحظات القوة',
                        ),
                      ),
                      subtitle: Text(
                        settings.tx(
                          'Adds grounded real-world force comparisons after level classification.',
                          'بعد تصنيف المستوى، يضيف مقارنة واقعية بالقوة كلمسة حماس.',
                        ),
                      ),
                      onChanged: settings.setShowAnimalComparison,
                    ),
                    const SizedBox(height: 8),
                    if (_saveMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _saveMessage!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: primary),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(settings.tx('Save Profile', 'احفظ البيانات')),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout),
                      label: Text(settings.tx('Log Out', 'تسجيل الخروج')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: errorColor,
                        side: BorderSide(
                          color: errorColor.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
