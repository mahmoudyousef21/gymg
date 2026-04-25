import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/app_user.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../widgets/topological_background.dart';

class ProfileOnboardingScreen extends StatefulWidget {
  const ProfileOnboardingScreen({
    required this.userId,
    required this.onCompleted,
    super.key,
  });

  final String userId;
  final ValueChanged<AppUser> onCompleted;

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _locationController = TextEditingController();
  final _avatarController = TextEditingController();
  final _coachWhatsappController = TextEditingController();
  final _coachExperienceController = TextEditingController();
  final _coachClientsController = TextEditingController();
  final _coachPriceController = TextEditingController();
  final _coachPaymentMethodsController = TextEditingController();
  final _coachBioController = TextEditingController();
  ProfileGender _selectedGender = ProfileGender.unspecified;
  UserRole _selectedRole = UserRole.trainee;
  String _selectedCoachingSystem = 'Hybrid Strength Coaching';
  Uint8List? _avatarPreviewBytes;

  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _error;

  static const List<String> _coachingSystems = <String>[
    'Hybrid Strength Coaching',
    '5/3/1 Coaching',
    'PHUL Progression',
    'Upper-Lower Strength',
    'Push Pull Legs Periodized',
  ];

  int? _parseLocalizedInt(String input) {
    final normalized = input
        .trim()
        .replaceAllMapped(RegExp(r'[\u0660-\u0669]'), (match) {
          const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
          return arabicDigits.indexOf(match.group(0)!).toString();
        })
        .replaceAllMapped(RegExp(r'[\u06F0-\u06F9]'), (match) {
          const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
          return persianDigits.indexOf(match.group(0)!).toString();
        });
    if (normalized.isEmpty) {
      return null;
    }
    return int.tryParse(normalized);
  }

  double? _parseLocalizedDouble(String input) {
    final normalized = input
        .trim()
        .replaceAllMapped(RegExp(r'[\u0660-\u0669]'), (match) {
          const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
          return arabicDigits.indexOf(match.group(0)!).toString();
        })
        .replaceAllMapped(RegExp(r'[\u06F0-\u06F9]'), (match) {
          const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
          return persianDigits.indexOf(match.group(0)!).toString();
        })
        .replaceAll('٫', '.')
        .replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  List<String> _parsePaymentMethods(String input) {
    return input
        .split(RegExp(r'[,،;\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _resolveImageExtension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == filename.length - 1) {
      return 'jpg';
    }

    final ext = filename.substring(dotIndex + 1).toLowerCase();
    if (ext == 'png' || ext == 'webp' || ext == 'gif' || ext == 'jpg' || ext == 'jpeg') {
      return ext == 'jpeg' ? 'jpg' : ext;
    }
    return 'jpg';
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar || _saving) {
      return;
    }

    final settings = context.appSettings;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      imageQuality: 86,
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _uploadingAvatar = true;
      _error = null;
    });

    try {
      final bytes = await picked.readAsBytes();
      final url = await SupabaseService.instance.uploadProfileAvatar(
        userId: widget.userId,
        bytes: bytes,
        extension: _resolveImageExtension(picked.name),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _avatarPreviewBytes = bytes;
        _avatarController.text = url;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = settings.tx(
          'Avatar upload failed. Please try again.',
          'رفع الصورة فشل. حاول تاني.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _locationController.dispose();
    _avatarController.dispose();
    _coachWhatsappController.dispose();
    _coachExperienceController.dispose();
    _coachClientsController.dispose();
    _coachPriceController.dispose();
    _coachPaymentMethodsController.dispose();
    _coachBioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = context.appSettings;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = settings.tx('Name is required.', 'الاسم مطلوب.');
      });
      return;
    }

    if (_selectedGender == ProfileGender.unspecified) {
      setState(() {
        _error = settings.tx(
          'Choose your gender to calibrate ranking and rehab analysis.',
          'اختار النوع عشان نضبط الترتيب وتحليل التأهيل.',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    if (_selectedRole == UserRole.coach) {
      final yearsExp = _parseLocalizedInt(_coachExperienceController.text);
      final clients = _parseLocalizedInt(_coachClientsController.text);
      final monthlyPrice = _parseLocalizedDouble(_coachPriceController.text);
      final paymentMethods = _parsePaymentMethods(
        _coachPaymentMethodsController.text,
      );

      if (_coachWhatsappController.text.trim().isEmpty ||
          yearsExp == null ||
          yearsExp < 0 ||
          clients == null ||
          clients < 0 ||
          monthlyPrice == null ||
          monthlyPrice <= 0 ||
          paymentMethods.isEmpty) {
        setState(() {
          _saving = false;
          _error = settings.tx(
            'Coach profile needs WhatsApp, years, clients, price, and payment methods.',
            'بيانات الكوتش لازم تشمل واتساب، سنوات خبرة، عدد العملاء، سعر الاشتراك، وطرق الدفع.',
          );
        });
        return;
      }
    }

    final profile = AppUser(
      id: widget.userId,
      name: name,
      avatarUrl: _avatarController.text.trim(),
      location: _locationController.text.trim(),
      role: _selectedRole,
      gender: _selectedGender,
      age: int.tryParse(_ageController.text.trim()),
      weight: double.tryParse(_weightController.text.trim()),
      height: double.tryParse(_heightController.text.trim()),
      tier: 'IRON',
      totalLifted: 0,
      percentile: 99,
    );

    try {
      await SupabaseService.instance.upsertProfile(profile);
      if (_selectedRole == UserRole.coach) {
        final paymentMethods = _parsePaymentMethods(
          _coachPaymentMethodsController.text,
        );

        await SupabaseService.instance.upsertCoachProfile(
          coachId: widget.userId,
          whatsappNumber: _coachWhatsappController.text.trim(),
          yearsExperience: _parseLocalizedInt(_coachExperienceController.text) ?? 0,
          clientsCoached: _parseLocalizedInt(_coachClientsController.text) ?? 0,
          subscriptionPrice:
              _parseLocalizedDouble(_coachPriceController.text) ?? 0,
          paymentMethods: paymentMethods,
          coachingSystem: _selectedCoachingSystem,
          bio: _coachBioController.text.trim(),
        );
      }

      if (!mounted) {
        return;
      }
      widget.onCompleted(profile);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
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

    return Scaffold(
      body: TopologicalBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          settings.tx('Complete Your Profile', 'كمّل بروفايلك'),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: primary,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          settings.tx(
                            'This profile is required before you can add sessions and lifts.',
                            'لازم تكمل بياناتك الأول قبل ما تضيف جلسات ورفعات.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: errorColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: errorColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: errorColor),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: settings.tx('Name *', 'الاسم *'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          settings.tx('Account Role *', 'نوع الحساب *'),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(settings.tx('Trainee', 'متدرب')),
                              selected: _selectedRole == UserRole.trainee,
                              onSelected: (_) {
                                setState(() {
                                  _selectedRole = UserRole.trainee;
                                  _error = null;
                                });
                              },
                            ),
                            ChoiceChip(
                              label: Text(settings.tx('Coach', 'كوتش')),
                              selected: _selectedRole == UserRole.coach,
                              onSelected: (_) {
                                setState(() {
                                  _selectedRole = UserRole.coach;
                                  _error = null;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          settings.tx(
                            'Role is locked after signup.',
                            'اختيار الدور ثابت بعد إنشاء الحساب.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          settings.tx('Gender *', 'النوع *'),
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
                                  _error = null;
                                });
                              },
                            ),
                            ChoiceChip(
                              label: Text(settings.tx('Female', 'أنثى')),
                              selected:
                                  _selectedGender == ProfileGender.female,
                              onSelected: (_) {
                                setState(() {
                                  _selectedGender = ProfileGender.female;
                                  _error = null;
                                });
                              },
                            ),
                          ],
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
                                keyboardType:
                                    const TextInputType.numberWithOptions(
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
                          onChanged: (_) {
                            if (_avatarPreviewBytes != null) {
                              setState(() {
                                _avatarPreviewBytes = null;
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: settings.tx('Avatar URL', 'لينك الصورة'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              backgroundImage: _avatarPreviewBytes != null
                                  ? MemoryImage(_avatarPreviewBytes!)
                                  : _avatarController.text.trim().isNotEmpty
                                  ? NetworkImage(_avatarController.text.trim())
                                  : null,
                              child: _avatarPreviewBytes == null &&
                                      _avatarController.text.trim().isEmpty
                                  ? const Icon(Icons.person_outline)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _uploadingAvatar
                                    ? null
                                    : _pickAndUploadAvatar,
                                icon: _uploadingAvatar
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.file_upload_outlined),
                                label: Text(
                                  settings.tx(
                                    'Upload from device',
                                    'ارفع من الجهاز',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_selectedRole == UserRole.coach) ...[
                          const SizedBox(height: 12),
                          Text(
                            settings.tx('Coach Public Profile', 'بيانات الكوتش العامة'),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _coachWhatsappController,
                            decoration: InputDecoration(
                              labelText: settings.tx(
                                'WhatsApp Number *',
                                'رقم واتساب *',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _coachExperienceController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: settings.tx(
                                      'Years Experience *',
                                      'سنين الخبرة *',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _coachClientsController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: settings.tx(
                                      'Clients Coached *',
                                      'عدد العملاء *',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _coachPriceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: settings.tx(
                                'Monthly Subscription Price *',
                                'سعر الاشتراك الشهري *',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCoachingSystem,
                            decoration: InputDecoration(
                              labelText: settings.tx(
                                'Coaching System',
                                'نظام الكوتشينج',
                              ),
                            ),
                            items: _coachingSystems
                                .map(
                                  (system) => DropdownMenuItem<String>(
                                    value: system,
                                    child: Text(system),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _selectedCoachingSystem = value;
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _coachPaymentMethodsController,
                            decoration: InputDecoration(
                              labelText: settings.tx(
                                'Payment Methods * (comma separated)',
                                'طرق الدفع * (افصل بينهم بفاصلة)',
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _coachBioController,
                            minLines: 2,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: settings.tx('Bio', 'نبذة عنك'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : Text(settings.tx('LET\'S LIFT', 'يلا نتمرن')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
