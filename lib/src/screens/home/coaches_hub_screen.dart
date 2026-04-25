import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/splits_catalog.dart';
import '../../models/app_user.dart';
import '../../models/coach_hub.dart';
import '../../models/gym_split.dart';
import '../../services/supabase_service.dart';
import '../../state/app_settings.dart';
import '../../theme/app_theme.dart';

enum _CoachTier { diamond, elite, iron }

enum _CoachFilter { all, diamond, elite, iron }

class CoachesHubScreen extends StatefulWidget {
  const CoachesHubScreen({
    required this.userId,
    required this.profile,
    super.key,
  });

  final String userId;
  final AppUser profile;

  @override
  State<CoachesHubScreen> createState() => _CoachesHubScreenState();
}

class _CoachesHubScreenState extends State<CoachesHubScreen> {
  final _service = SupabaseService.instance;
  final _coachSearchController = TextEditingController();
  final _coachWhatsAppController = TextEditingController();
  final _coachExperienceController = TextEditingController();
  final _coachClientsController = TextEditingController();
  final _coachPriceController = TextEditingController();
  final _coachPaymentMethodsController = TextEditingController();
  final _coachBioController = TextEditingController();
  final _coachAvatarController = TextEditingController();
  late final List<ExerciseEntry> _exerciseLibrary = _buildExerciseLibrary();
  Uint8List? _coachAvatarPreviewBytes;

  bool _loading = true;
  bool _savingCoachProfile = false;
  bool _uploadingCoachAvatar = false;
  String? _error;

  List<CoachTraineeSnapshot> _coachTrainees = <CoachTraineeSnapshot>[];

  CoachProfileListing? _assignedCoach;
  List<CoachProfileListing> _coachMarketplace = <CoachProfileListing>[];
  List<CoachSplitSuggestion> _splitSuggestions = <CoachSplitSuggestion>[];
  String _coachSearchQuery = '';
  _CoachFilter _coachFilter = _CoachFilter.all;

  static const List<String> _popularSystems = <String>[
    '5/3/1 Strength',
    'Push Pull Legs Periodized',
    'Upper / Lower Progressive Overload',
    'PHUL',
    'Hybrid Hypertrophy + Strength',
  ];

  String _selectedCoachSystem = _popularSystems.first;

  @override
  void initState() {
    super.initState();
    _coachAvatarController.text = widget.profile.avatarUrl;
    _loadHub();
  }

  @override
  void dispose() {
    _coachSearchController.dispose();
    _coachWhatsAppController.dispose();
    _coachExperienceController.dispose();
    _coachClientsController.dispose();
    _coachPriceController.dispose();
    _coachPaymentMethodsController.dispose();
    _coachBioController.dispose();
    _coachAvatarController.dispose();
    super.dispose();
  }

  bool get _isCoach => widget.profile.role == UserRole.coach;

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

  List<ExerciseEntry> _buildExerciseLibrary() {
    final byName = <String, ExerciseEntry>{};
    for (final splits in splitsCatalog.values) {
      for (final split in splits) {
        for (final day in split.days) {
          for (final exercise in day.exercises) {
            byName.putIfAbsent(exercise.name, () => exercise);
          }
        }
      }
    }
    final list = byName.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
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

  Future<void> _loadHub() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isCoach) {
        final coachProfile = await _service.fetchCoachProfile(widget.userId);
        final trainees = await _service.fetchCoachTrainees(widget.userId);

        if (!mounted) {
          return;
        }

        setState(() {
          _seedCoachProfileFields(coachProfile);
          _coachTrainees = trainees;
          _loading = false;
        });
        return;
      }

      final assignedCoach = await _service.fetchAssignedCoachForTrainee(
        widget.userId,
      );
      final marketplace = await _service.fetchCoachMarketplace(
        currentUserId: widget.userId,
      );
      final suggestions = await _service.fetchTraineeSplitSuggestions(
        widget.userId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _assignedCoach = assignedCoach;
        _coachMarketplace = marketplace;
        _splitSuggestions = suggestions;
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

  void _seedCoachProfileFields(CoachProfileListing? profile) {
    if (profile == null) {
      _coachAvatarController.text = _coachAvatarController.text.trim().isEmpty
          ? widget.profile.avatarUrl
          : _coachAvatarController.text;
      _coachWhatsAppController.text = '';
      _coachExperienceController.text = '';
      _coachClientsController.text = '';
      _coachPriceController.text = '';
      _coachPaymentMethodsController.text = '';
      _coachBioController.text = '';
      _selectedCoachSystem = _popularSystems.first;
      return;
    }

    _coachAvatarController.text = profile.avatarUrl;
    _coachWhatsAppController.text = profile.whatsappNumber;
    _coachExperienceController.text = profile.yearsExperience.toString();
    _coachClientsController.text = profile.clientsCoached.toString();
    _coachPriceController.text = profile.subscriptionPrice.toStringAsFixed(0);
    _coachPaymentMethodsController.text = profile.paymentMethods.join(', ');
    _coachBioController.text = profile.bio;

    if (_popularSystems.contains(profile.coachingSystem)) {
      _selectedCoachSystem = profile.coachingSystem;
    }
  }

  Future<void> _saveCoachProfile() async {
    final settings = context.appSettings;
    if (_savingCoachProfile) {
      return;
    }

    final years = _parseLocalizedInt(_coachExperienceController.text);
    final clients = _parseLocalizedInt(_coachClientsController.text);
    final price = _parseLocalizedDouble(_coachPriceController.text);
    final paymentMethods = _parsePaymentMethods(
      _coachPaymentMethodsController.text,
    );

    if (_coachWhatsAppController.text.trim().isEmpty ||
        years == null ||
        years < 0 ||
        clients == null ||
        clients < 0 ||
        price == null ||
        price <= 0 ||
        paymentMethods.isEmpty) {
      setState(() {
        _error = settings.tx(
          'Complete WhatsApp, years, clients, monthly price, and payment methods.',
          'كمّل رقم الواتساب، سنين الخبرة، عدد العملاء، سعر الاشتراك، وطرق الدفع.',
        );
      });
      return;
    }

    setState(() {
      _savingCoachProfile = true;
      _error = null;
    });

    try {
      await _service.updateProfileAvatar(
        userId: widget.userId,
        avatarUrl: _coachAvatarController.text.trim(),
      );

      await _service.upsertCoachProfile(
        coachId: widget.userId,
        whatsappNumber: _coachWhatsAppController.text.trim(),
        yearsExperience: years,
        clientsCoached: clients,
        subscriptionPrice: price,
        paymentMethods: paymentMethods,
        coachingSystem: _selectedCoachSystem,
        bio: _coachBioController.text.trim(),
      );

      await _loadHub();
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
          _savingCoachProfile = false;
        });
      }
    }
  }

  Future<void> _subscribeToCoach(CoachProfileListing coach) async {
    final settings = context.appSettings;

    try {
      await _service.assignCoachToTrainee(
        traineeId: widget.userId,
        coachId: coach.coachId,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            settings.tx(
              'Coach subscription updated.',
              'تم تحديث اشتراك الكوتش.',
            ),
          ),
        ),
      );

      await _loadHub();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final cleaned = phone.trim();
    if (cleaned.isEmpty) {
      return;
    }

    final uri = Uri.parse('https://wa.me/${cleaned.replaceAll(RegExp(r'[^0-9+]'), '')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _pickAndUploadCoachAvatar() async {
    if (_uploadingCoachAvatar || _savingCoachProfile) {
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
      _uploadingCoachAvatar = true;
      _error = null;
    });

    try {
      final bytes = await picked.readAsBytes();
      final url = await _service.uploadProfileAvatar(
        userId: widget.userId,
        bytes: bytes,
        extension: _resolveImageExtension(picked.name),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _coachAvatarPreviewBytes = bytes;
        _coachAvatarController.text = url;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = settings.tx(
          'Coach photo upload failed. Please try again.',
          'رفع صورة الكوتش فشل. حاول تاني.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploadingCoachAvatar = false;
        });
      }
    }
  }

  SplitSchedule? _splitFromSuggestion(CoachSplitSuggestion suggestion) {
    try {
      return SplitSchedule.fromMap(suggestion.splitData);
    } catch (_) {
      return null;
    }
  }

  Future<void> _applySuggestedSplit(CoachSplitSuggestion suggestion) async {
    final settings = context.appSettings;
    final split = _splitFromSuggestion(suggestion);
    if (split == null) {
      return;
    }

    try {
      await _service.upsertSplitSchedule(userId: widget.userId, schedule: split);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            settings.tx(
              'Split applied. Check your Splits tab.',
              'تم تطبيق السبليت. افتح تبويب السبليتات.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    }
  }

  Future<void> _createCustomSplitForTrainee(CoachTraineeSnapshot trainee) async {
    final settings = context.appSettings;
    final splitNameController = TextEditingController(
      text: '${trainee.profile.name} Custom Plan',
    );
    final noteController = TextEditingController();

    var daysPerWeek = 4;
    var submitting = false;
    String? dialogError;
    final dayExercises = List<List<ExerciseEntry>>.generate(
      daysPerWeek,
      (_) => <ExerciseEntry>[],
    );
    final selectedExerciseName = List<String?>.filled(
      daysPerWeek,
      null,
      growable: true,
    );

    void syncDays(int nextDays) {
      if (nextDays > dayExercises.length) {
        for (var i = dayExercises.length; i < nextDays; i++) {
          dayExercises.add(<ExerciseEntry>[]);
          selectedExerciseName.add(null);
        }
      } else if (nextDays < dayExercises.length) {
        dayExercises.removeRange(nextDays, dayExercises.length);
        selectedExerciseName.removeRange(nextDays, selectedExerciseName.length);
      }
    }

    SplitSchedule buildSchedule() {
      final now = DateTime.now();
      final base = DateTime(now.year, now.month, now.day);
      final splitName = splitNameController.text.trim().isEmpty
          ? 'Coach Custom Plan'
          : splitNameController.text.trim();

      final schedule = dayExercises.asMap().entries.map((entry) {
        final index = entry.key;
        final exercises = entry.value;
        final muscles = <String>{};
        final musclesAr = <String>{};
        for (final exercise in exercises) {
          muscles.addAll(exercise.primaryMuscles);
          musclesAr.addAll(exercise.primaryMusclesAr);
        }
        return SplitScheduleEntry(
          label: 'Day ${index + 1}',
          labelAr: 'اليوم ${index + 1}',
          muscles: muscles.toList(),
          musclesAr: musclesAr.toList(),
          exercises: exercises,
          date: base.add(Duration(days: index)),
          completed: false,
        );
      }).toList();

      return SplitSchedule(
        splitId:
            'coach_custom_${widget.userId}_${trainee.profile.id}_${DateTime.now().millisecondsSinceEpoch}',
        splitName: splitName,
        splitNameAr: 'خطة مخصصة من الكوتش',
        daysPerWeek: daysPerWeek,
        currentDayIndex: 0,
        schedule: schedule,
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                settings.tx(
                  'Create custom split for ${trainee.profile.name}',
                  'اعمل سبليت مخصص لـ ${trainee.profile.name}',
                ),
              ),
              content: SizedBox(
                width: 680,
                height: 540,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dialogError != null) ...[
                        Text(
                          dialogError!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: splitNameController,
                        decoration: InputDecoration(
                          labelText: settings.tx('Split name', 'اسم السبليت'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: daysPerWeek,
                        decoration: InputDecoration(
                          labelText: settings.tx(
                            'Training days per week',
                            'عدد أيام التمرين في الأسبوع',
                          ),
                        ),
                        items: const [1, 2, 3, 4, 5, 6]
                            .map(
                              (day) => DropdownMenuItem<int>(
                                value: day,
                                child: Text('$day'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            daysPerWeek = value;
                            syncDays(daysPerWeek);
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      ...List.generate(daysPerWeek, (dayIndex) {
                        final selected = dayExercises[dayIndex];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  settings.tx(
                                    'Day ${dayIndex + 1}',
                                    'اليوم ${dayIndex + 1}',
                                  ),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: selectedExerciseName[dayIndex],
                                  decoration: InputDecoration(
                                    labelText: settings.tx(
                                      'Pick exercise',
                                      'اختار تمرين',
                                    ),
                                  ),
                                  items: _exerciseLibrary
                                      .map(
                                        (exercise) => DropdownMenuItem<String>(
                                          value: exercise.name,
                                          child: Text(exercise.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedExerciseName[dayIndex] = value;
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        final chosen = selectedExerciseName[dayIndex];
                                        if (chosen == null || chosen.isEmpty) {
                                          return;
                                        }
                                        final exercise = _exerciseLibrary.firstWhere(
                                          (item) => item.name == chosen,
                                        );
                                        if (selected.any(
                                          (existing) => existing.name == exercise.name,
                                        )) {
                                          return;
                                        }
                                        setDialogState(() {
                                          selected.add(exercise);
                                        });
                                      },
                                      icon: const Icon(Icons.add_circle_outline),
                                      label: Text(
                                        settings.tx('Add Exercise', 'أضف تمرين'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      settings.tx(
                                        '${selected.length} selected',
                                        '${selected.length} متضاف',
                                      ),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                if (selected.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: selected
                                        .map(
                                          (exercise) => InputChip(
                                            label: Text(
                                              '${exercise.name} • ${exercise.sets}x${exercise.reps}',
                                            ),
                                            onDeleted: () {
                                              setDialogState(() {
                                                selected.removeWhere(
                                                  (item) => item.name == exercise.name,
                                                );
                                              });
                                            },
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                      TextField(
                        controller: noteController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: settings.tx(
                            'Coach note (optional)',
                            'ملاحظة الكوتش (اختياري)',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(settings.tx('Cancel', 'إلغاء')),
                ),
                ElevatedButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          for (var i = 0; i < dayExercises.length; i++) {
                            if (dayExercises[i].isEmpty) {
                              setDialogState(() {
                                dialogError = settings.tx(
                                  'Each day needs at least one exercise.',
                                  'كل يوم لازم يبقى فيه تمرين واحد على الأقل.',
                                );
                              });
                              return;
                            }
                          }

                          final schedule = buildSchedule();
                          final messenger = ScaffoldMessenger.of(context);
                          final assignedMessage = settings.tx(
                            'Custom split assigned to trainee.',
                            'تم تعيين السبليت المخصص للمتدرب.',
                          );
                          setDialogState(() {
                            submitting = true;
                            dialogError = null;
                          });

                          try {
                            await _service.assignCoachCustomSplitToTrainee(
                              coachId: widget.userId,
                              traineeId: trainee.profile.id,
                              schedule: schedule,
                              note: noteController.text.trim(),
                            );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }

                            if (!mounted) {
                              return;
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(assignedMessage),
                              ),
                            );

                            await _loadHub();
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                dialogError = error.toString();
                              });
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                submitting = false;
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.check_circle_outline),
                  label: submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          settings.tx(
                            'Assign Custom Split',
                            'تعيين السبليت المخصص',
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    splitNameController.dispose();
    noteController.dispose();
  }

  Future<void> _openConversation({
    required String coachId,
    required String traineeId,
    required String peerName,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CoachConversationDialog(
        service: _service,
        settings: context.appSettings,
        coachId: coachId,
        traineeId: traineeId,
        senderId: widget.userId,
        peerName: peerName,
      ),
    );
  }

  Future<void> _suggestSplitToTrainee(CoachTraineeSnapshot trainee) async {
    final settings = context.appSettings;
    String selectedSystem = _popularSystems.first;
    final noteController = TextEditingController();
    var submitting = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                settings.tx(
                  'Suggest split to ${trainee.profile.name}',
                  'اقترح سبليت لـ ${trainee.profile.name}',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dialogError != null) ...[
                    Text(
                      dialogError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: selectedSystem,
                    decoration: InputDecoration(
                      labelText: settings.tx('System', 'النظام'),
                    ),
                    items: _popularSystems
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
                      setDialogState(() {
                        selectedSystem = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: settings.tx('Coach note', 'ملاحظة الكوتش'),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(settings.tx('Cancel', 'إلغاء')),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() {
                            submitting = true;
                            dialogError = null;
                          });

                          try {
                            await _service.createCoachSplitSuggestion(
                              coachId: widget.userId,
                              traineeId: trainee.profile.id,
                              systemName: selectedSystem,
                              note: noteController.text.trim(),
                              splitData: {
                                'system': selectedSystem,
                                'recommendedDays': 4,
                                'focus': trainee.profile.weight != null &&
                                        trainee.profile.weight! > 90
                                    ? 'strength + mobility'
                                    : 'hypertrophy + technique',
                              },
                            );

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                dialogError = error.toString();
                                submitting = false;
                              });
                            }
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(settings.tx('Send Suggestion', 'إرسال الاقتراح')),
                ),
              ],
            );
          },
        );
      },
    );

    noteController.dispose();
  }

  String _rehabSummary(
    Map<String, dynamic> rehabMetrics,
    AppSettings settings,
  ) {
    double metricWeight(String key) {
      final raw = rehabMetrics[key];
      final item = raw is Map<String, dynamic>
          ? raw
          : raw is Map
          ? Map<String, dynamic>.from(raw)
          : const <String, dynamic>{};

      final value = item['weight'];
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final bench = metricWeight('bench');
    final pull = metricWeight('pull');
    final legs = metricWeight('leg_press');
    final overhead = metricWeight('overhead');

    if (bench <= 0 || pull <= 0 || legs <= 0 || overhead <= 0) {
      return settings.tx(
        'Partial rehab data available.',
        'بيانات التأهيل لسه ناقصة.',
      );
    }

    final pushPull = bench / pull;
    final overheadBench = overhead / bench;

    if (pushPull > 1.15) {
      return settings.tx('Back chain needs focus.', 'سلسلة السحب محتاجة تركيز.');
    }
    if (overheadBench < 0.55) {
      return settings.tx('Shoulder endurance lagging.', 'تحمل الكتف محتاج شغل.');
    }

    return settings.tx('Balance is acceptable.', 'التوازن مقبول.');
  }

  CoachProfileListing _draftCoachProfile() {
    return CoachProfileListing(
      coachId: widget.userId,
      name: widget.profile.name,
      avatarUrl: _coachAvatarController.text.trim(),
      location: widget.profile.location,
      whatsappNumber: _coachWhatsAppController.text.trim(),
      yearsExperience: _parseLocalizedInt(_coachExperienceController.text) ?? 0,
      clientsCoached: _parseLocalizedInt(_coachClientsController.text) ?? 0,
      subscriptionPrice: _parseLocalizedDouble(_coachPriceController.text) ?? 0,
      paymentMethods: _parsePaymentMethods(_coachPaymentMethodsController.text),
      coachingSystem: _selectedCoachSystem,
      bio: _coachBioController.text.trim(),
    );
  }

  _CoachTier _coachTierFor(CoachProfileListing coach) {
    final score =
        (coach.yearsExperience * 2) +
        (coach.clientsCoached / 18) +
        (coach.subscriptionPrice / 70);

    if (score >= 18) {
      return _CoachTier.diamond;
    }
    if (score >= 10) {
      return _CoachTier.elite;
    }
    return _CoachTier.iron;
  }

  _CoachFilter _filterForTier(_CoachTier tier) {
    return switch (tier) {
      _CoachTier.diamond => _CoachFilter.diamond,
      _CoachTier.elite => _CoachFilter.elite,
      _CoachTier.iron => _CoachFilter.iron,
    };
  }

  String _filterLabel(_CoachFilter filter, AppSettings settings) {
    return switch (filter) {
      _CoachFilter.all => settings.tx('All specialists', 'كل المتخصصين'),
      _CoachFilter.diamond => settings.tx('Diamond', 'دايموند'),
      _CoachFilter.elite => settings.tx('Elite', 'إيليت'),
      _CoachFilter.iron => settings.tx('Iron', 'آيرون'),
    };
  }

  String _tierLabel(_CoachTier tier, AppSettings settings) {
    return switch (tier) {
      _CoachTier.diamond => settings.tx('Diamond', 'دايموند'),
      _CoachTier.elite => settings.tx('Elite', 'إيليت'),
      _CoachTier.iron => settings.tx('Iron', 'آيرون'),
    };
  }

  IconData _tierIcon(_CoachTier tier) {
    return switch (tier) {
      _CoachTier.diamond => Icons.diamond_rounded,
      _CoachTier.elite => Icons.bolt_rounded,
      _CoachTier.iron => Icons.shield_rounded,
    };
  }

  Color _tierColor(_CoachTier tier, BuildContext context) {
    return switch (tier) {
      _CoachTier.diamond => Theme.of(context).colorScheme.secondary,
      _CoachTier.elite => Theme.of(context).colorScheme.primary,
      _CoachTier.iron => AppColors.onSurfaceVariant,
    };
  }

  int _tierRank(_CoachTier tier) {
    return switch (tier) {
      _CoachTier.diamond => 0,
      _CoachTier.elite => 1,
      _CoachTier.iron => 2,
    };
  }

  List<CoachProfileListing> _filteredMarketplace() {
    final query = _coachSearchQuery.trim().toLowerCase();

    final filtered = _coachMarketplace.where((coach) {
      final tier = _coachTierFor(coach);
      if (_coachFilter != _CoachFilter.all && _filterForTier(tier) != _coachFilter) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final haystack = <String>[
        coach.name,
        coach.coachingSystem,
        coach.location,
        coach.bio,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final aAssigned = _assignedCoach?.coachId == a.coachId;
      final bAssigned = _assignedCoach?.coachId == b.coachId;
      if (aAssigned != bAssigned) {
        return aAssigned ? -1 : 1;
      }

      final tierCompare = _tierRank(_coachTierFor(a)).compareTo(
        _tierRank(_coachTierFor(b)),
      );
      if (tierCompare != 0) {
        return tierCompare;
      }

      return b.clientsCoached.compareTo(a.clientsCoached);
    });

    return filtered;
  }

  Future<void> _openCoachFilterSheet() async {
    final settings = context.appSettings;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceHigh,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.tx('Filter coaches', 'فلترة الكوتشات'),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _CoachFilter.values.map((filter) {
                    final selected = filter == _coachFilter;
                    return ChoiceChip(
                      label: Text(_filterLabel(filter, settings)),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _coachFilter = filter;
                        });
                        Navigator.of(sheetContext).pop();
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCoachProfileSheet(CoachProfileListing coach) async {
    final settings = context.appSettings;
    final isAssigned = _assignedCoach?.coachId == coach.coachId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            coach.name,
                            style: Theme.of(sheetContext).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      children: [
                        if (coach.avatarUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: AspectRatio(
                              aspectRatio: 4 / 3,
                              child: Image.network(
                                coach.avatarUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 220,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHighest,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              coach.name.isEmpty
                                  ? '?'
                                  : coach.name[0].toUpperCase(),
                              style: Theme.of(sheetContext).textTheme.displaySmall,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          coach.coachingSystem,
                          style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                            color: Theme.of(sheetContext).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          coach.bio.trim().isEmpty
                              ? settings.tx(
                                  'No profile summary yet.',
                                  'لسه مفيش نبذة على البروفايل.',
                                )
                              : coach.bio,
                          style: Theme.of(sheetContext).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _CoachStatChip(
                              icon: Icons.payments_outlined,
                              label: settings.tx(
                                'Monthly plan',
                                'اشتراك شهري',
                              ),
                              value: '${coach.subscriptionPrice.toStringAsFixed(0)}${settings.tx('/month', '/شهر')}',
                            ),
                            _CoachStatChip(
                              icon: Icons.timelapse_rounded,
                              label: settings.tx('Experience', 'الخبرة'),
                              value: '${coach.yearsExperience}+ ${settings.tx('yrs', 'سنة')}',
                            ),
                            _CoachStatChip(
                              icon: Icons.groups_2_outlined,
                              label: settings.tx('Clients', 'العملاء'),
                              value: '${coach.clientsCoached}+',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              if (isAssigned) {
                                _openConversation(
                                  coachId: coach.coachId,
                                  traineeId: widget.userId,
                                  peerName: coach.name,
                                );
                                return;
                              }
                              _subscribeToCoach(coach);
                            },
                            icon: Icon(
                              isAssigned
                                  ? Icons.chat_bubble_outline
                                  : Icons.workspace_premium_outlined,
                            ),
                            label: Text(
                              isAssigned
                                  ? settings.tx('Message Coach', 'ابعت للكوتش')
                                  : settings.tx(
                                      'Subscribe Monthly',
                                      'اشترك شهري',
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _openWhatsApp(coach.whatsappNumber);
                            },
                            icon: const Icon(Icons.call_outlined),
                            label: Text(settings.tx('Open WhatsApp', 'افتح واتساب')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: primary));
    }

    if (_error != null) {
      return Center(
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
                    settings.tx('Coach hub issue', 'مشكلة في صفحة الكوتش'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(_error!),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _loadHub,
                    child: Text(settings.tx('TRY AGAIN', 'حاول تاني')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      child: _isCoach ? _buildCoachDesk(context) : _buildTraineeMarket(context),
    );
  }

  Widget _buildTraineeMarket(BuildContext context) {
    final settings = context.appSettings;
    final primary = Theme.of(context).colorScheme.primary;
    final visibleCoaches = _filteredMarketplace();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.tx('HUMAN PERFORMANCE', 'الأداء البشري'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: primary,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: settings.tx('Select Your\n', 'اختار\n'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: settings.tx('Elite Coach', 'الكوتش المميز'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                settings.tx(
                  'Upgrade your kinetic potential with world-class specialists in strength engineering.',
                  'طوّر مستواك مع متخصصين عالميين في هندسة القوة.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighest.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _coachSearchController,
                  onChanged: (value) {
                    setState(() {
                      _coachSearchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: settings.tx(
                      'Find specialist...',
                      'دوّر على متخصص...',
                    ),
                    hintStyle: Theme.of(context).textTheme.bodySmall,
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              height: 52,
              child: FilledButton.tonal(
                onPressed: _openCoachFilterSheet,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.surfaceHighest.withValues(alpha: 0.86),
                  foregroundColor: primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.tune_rounded),
              ),
            ),
          ],
        ),
        if (_coachFilter != _CoachFilter.all) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(_filterLabel(_coachFilter, settings)),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                onDeleted: () {
                  setState(() {
                    _coachFilter = _CoachFilter.all;
                  });
                },
              ),
            ],
          ),
        ],
        if (_assignedCoach != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primary.withValues(alpha: 0.34)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_rounded, size: 18, color: primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    settings.tx(
                      'Active coach: ${_assignedCoach!.name}',
                      'الكوتش الحالي: ${_assignedCoach!.name}',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (visibleCoaches.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                settings.tx(
                  'No matching coaches found.',
                  'مفيش كوتشات مطابقة للبحث.',
                ),
              ),
            ),
          )
        else
          ...visibleCoaches.map((coach) {
            final assigned = _assignedCoach?.coachId == coach.coachId;
            final tier = _coachTierFor(coach);
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _CoachCard(
                coach: coach,
                tier: tier,
                isAssigned: assigned,
                onSubscribe: () => _subscribeToCoach(coach),
                onWhatsApp: () => _openWhatsApp(coach.whatsappNumber),
                onMessage: assigned
                    ? () => _openConversation(
                        coachId: coach.coachId,
                        traineeId: widget.userId,
                        peerName: coach.name,
                      )
                    : null,
                onViewProfile: () => _openCoachProfileSheet(coach),
                tierLabel: _tierLabel(tier, settings),
                tierIcon: _tierIcon(tier),
                tierColor: _tierColor(tier, context),
              ),
            );
          }),
        if (_splitSuggestions.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            settings.tx('COACH SPLIT SUGGESTIONS', 'اقتراحات سبليت من الكوتش'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          ..._splitSuggestions.map((suggestion) {
            final assignableSplit = _splitFromSuggestion(suggestion);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                color: AppColors.surfaceLow.withValues(alpha: 0.9),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              suggestion.systemName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(DateFormat('MMM d').format(suggestion.createdAt)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        suggestion.note.isEmpty
                            ? settings.tx(
                                'Coach shared this split framework.',
                                'الكوتش شارك إطار السبليت ده.',
                              )
                            : suggestion.note,
                      ),
                      if (assignableSplit != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _applySuggestedSplit(suggestion),
                          icon: const Icon(Icons.fitness_center_outlined),
                          label: Text(
                            settings.tx(
                              'Use in Splits',
                              'استخدمه في السبليتات',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildCoachDesk(BuildContext context) {
    final settings = context.appSettings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: AppColors.surfaceLow.withValues(alpha: 0.92),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.tx('COACH PROFILE', 'بروفايل الكوتش'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.surfaceHighest,
                      backgroundImage: _coachAvatarPreviewBytes != null
                          ? MemoryImage(_coachAvatarPreviewBytes!)
                          : _coachAvatarController.text.trim().isNotEmpty
                          ? NetworkImage(_coachAvatarController.text.trim())
                          : null,
                      child: _coachAvatarPreviewBytes == null &&
                              _coachAvatarController.text.trim().isEmpty
                          ? Text(
                              widget.profile.name.isEmpty
                                  ? '?'
                                  : widget.profile.name[0].toUpperCase(),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _uploadingCoachAvatar
                                ? null
                                : _pickAndUploadCoachAvatar,
                            icon: _uploadingCoachAvatar
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
                                'Upload coach photo',
                                'ارفع صورة الكوتش',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _coachAvatarController,
                  onChanged: (_) {
                    if (_coachAvatarPreviewBytes != null) {
                      setState(() {
                        _coachAvatarPreviewBytes = null;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    labelText: settings.tx('Coach photo URL', 'لينك صورة الكوتش'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _coachWhatsAppController,
                  decoration: InputDecoration(
                    labelText: settings.tx('WhatsApp Number', 'رقم واتساب'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _coachExperienceController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: settings.tx(
                            'Years Experience',
                            'سنين الخبرة',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _coachClientsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: settings.tx('Clients', 'العملاء'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _coachPriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: settings.tx(
                      'Monthly Price',
                      'سعر الاشتراك الشهري',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCoachSystem,
                  decoration: InputDecoration(
                    labelText: settings.tx('Coaching System', 'نظام الكوتشينج'),
                  ),
                  items: _popularSystems
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
                      _selectedCoachSystem = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _coachPaymentMethodsController,
                  decoration: InputDecoration(
                    labelText: settings.tx(
                      'Payment Methods (comma separated)',
                      'طرق الدفع (افصل بفاصلة)',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _coachBioController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: settings.tx('Bio', 'نبذة'),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _savingCoachProfile ? null : _saveCoachProfile,
                  icon: _savingCoachProfile
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    settings.tx('Save Coach Profile', 'احفظ بروفايل الكوتش'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  settings.tx('Coach Profile Preview', 'معاينة بروفايل الكوتش'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final previewCoach = _draftCoachProfile();
                    final previewTier = _coachTierFor(previewCoach);
                    return _CoachCard(
                      coach: previewCoach,
                      tier: previewTier,
                      tierLabel: _tierLabel(previewTier, settings),
                      tierIcon: _tierIcon(previewTier),
                      tierColor: _tierColor(previewTier, context),
                      isAssigned: false,
                      onViewProfile: () {},
                      onSubscribe: () {},
                      onWhatsApp: () {},
                      showActions: false,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          settings.tx('YOUR TRAINEES', 'المتدربين عندك'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        if (_coachTrainees.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                settings.tx(
                  'No active trainees yet.',
                  'لسه مفيش متدربين مشتركين.',
                ),
              ),
            ),
          )
        else
          ..._coachTrainees.map((trainee) {
            final splitLabel = trainee.currentSplitName.isEmpty
                ? settings.tx('No split selected', 'لسه مفيش سبليت')
                : trainee.currentSplitName;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                color: AppColors.surfaceLow.withValues(alpha: 0.88),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 21,
                            backgroundColor: AppColors.surfaceHighest,
                            backgroundImage: trainee.profile.avatarUrl.isNotEmpty
                                ? NetworkImage(trainee.profile.avatarUrl)
                                : null,
                            child: trainee.profile.avatarUrl.isNotEmpty
                                ? null
                                : Text(
                                    trainee.profile.name.isEmpty
                                        ? '?'
                                        : trainee.profile.name[0].toUpperCase(),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  trainee.profile.name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  '${trainee.profile.tier} • ${trainee.profile.weight?.toStringAsFixed(1) ?? '--'}kg',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${trainee.sessionCount} ${settings.tx('sessions', 'جلسة')}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${settings.tx('Current split', 'السبليت الحالي')}: $splitLabel',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${settings.tx('Rehab status', 'حالة التأهيل')}: ${_rehabSummary(trainee.rehabMetrics, settings)}',
                      ),
                      if (trainee.lastSessionAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${settings.tx('Last session', 'آخر جلسة')}: ${DateFormat('MMM d • HH:mm').format(trainee.lastSessionAt!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openConversation(
                              coachId: widget.userId,
                              traineeId: trainee.profile.id,
                              peerName: trainee.profile.name,
                            ),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: Text(
                              settings.tx('Message', 'مراسلة'),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _suggestSplitToTrainee(trainee),
                            icon: const Icon(Icons.auto_graph),
                            label: Text(
                              settings.tx('Suggest Split', 'اقترح سبليت'),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _createCustomSplitForTrainee(trainee),
                            icon: const Icon(Icons.playlist_add_check_circle_outlined),
                            label: Text(
                              settings.tx(
                                'Create Custom Split',
                                'اعمل سبليت مخصص',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _CoachConversationDialog extends StatefulWidget {
  const _CoachConversationDialog({
    required this.service,
    required this.settings,
    required this.coachId,
    required this.traineeId,
    required this.senderId,
    required this.peerName,
  });

  final SupabaseService service;
  final AppSettings settings;
  final String coachId;
  final String traineeId;
  final String senderId;
  final String peerName;

  @override
  State<_CoachConversationDialog> createState() =>
      _CoachConversationDialogState();
}

class _CoachConversationDialogState extends State<_CoachConversationDialog> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  bool _stickToBottom = true;
  String? _error;
  List<CoachMessage> _messages = <CoachMessage>[];
  RealtimeChannel? _messagesChannel;
  Timer? _messageRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_loadMessages(initialLoad: true));
    _subscribeToMessageRealtime();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _messageRefreshDebounce?.cancel();
    unawaited(_messagesChannel?.unsubscribe());
    _messagesChannel = null;
    _controller.dispose();
    super.dispose();
  }

  void _scheduleRealtimeMessagesRefresh() {
    _messageRefreshDebounce?.cancel();
    _messageRefreshDebounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_loadMessages());
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) <= 36;
  }

  void _handleScroll() {
    _stickToBottom = _isNearBottom();
  }

  void _scrollToBottomIfNeeded({bool force = false}) {
    if (!mounted || (!_stickToBottom && !force)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _loadMessages({bool initialLoad = false}) async {
    if (!mounted) {
      return;
    }

    if (initialLoad) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final fetched = await widget.service.fetchCoachMessages(
        coachId: widget.coachId,
        traineeId: widget.traineeId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = fetched;
        _loading = false;
        _error = null;
      });
      _scrollToBottomIfNeeded(force: initialLoad);
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

  void _subscribeToMessageRealtime() {
    final channel = Supabase.instance.client.channel(
      'coach-messages-${widget.coachId}-${widget.traineeId}',
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'coach_messages',
      callback: (payload) {
        if (!mounted) {
          return;
        }

        final row = payload.newRecord.isNotEmpty
            ? payload.newRecord
            : payload.oldRecord;
        final coachId = (row['coach_id'] ?? '').toString();
        final traineeId = (row['trainee_id'] ?? '').toString();
        if (coachId != widget.coachId || traineeId != widget.traineeId) {
          return;
        }

        _scheduleRealtimeMessagesRefresh();
      },
    );

    channel.subscribe();
    _messagesChannel = channel;
  }

  Future<void> _sendMessage() async {
    if (_sending) {
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await widget.service.sendCoachMessage(
        coachId: widget.coachId,
        traineeId: widget.traineeId,
        senderId: widget.senderId,
        content: text,
      );

      if (!mounted) {
        return;
      }

      _controller.clear();
      _scrollToBottomIfNeeded(force: true);
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
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;

    return AlertDialog(
      title: Text(
        settings.tx('Chat with ${widget.peerName}', 'محادثة مع ${widget.peerName}'),
      ),
      content: SizedBox(
        width: 520,
        height: 430,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _messages.isEmpty
                  ? Center(
                      child: Text(
                        settings.tx(
                          'No messages yet. Start the chat.',
                          'لسه مفيش رسايل. ابدأ المحادثة.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final mine = message.isFrom(widget.senderId);
                        return Align(
                          alignment:
                              mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            constraints: const BoxConstraints(
                              maxWidth: 360,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.16)
                                  : AppColors.surfaceHighest.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.outline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(message.content),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('MMM d • HH:mm').format(
                                    message.createdAt,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: settings.tx(
                        'Write a message',
                        'اكتب رسالة',
                      ),
                    ),
                    onSubmitted: (_) {
                      unawaited(_sendMessage());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _sendMessage,
                  child: _sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(settings.tx('Send', 'إرسال')),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading
              ? null
              : () {
                  unawaited(_loadMessages());
                },
          child: Text(settings.tx('Refresh', 'تحديث')),
        ),
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(settings.tx('Close', 'إغلاق')),
        ),
      ],
    );
  }
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.coach,
    required this.tier,
    required this.tierLabel,
    required this.tierIcon,
    required this.tierColor,
    required this.isAssigned,
    required this.onViewProfile,
    required this.onSubscribe,
    required this.onWhatsApp,
    this.onMessage,
    this.showActions = true,
  });

  final CoachProfileListing coach;
  final _CoachTier tier;
  final String tierLabel;
  final IconData tierIcon;
  final Color tierColor;
  final bool isAssigned;
  final VoidCallback onViewProfile;
  final VoidCallback onSubscribe;
  final VoidCallback onWhatsApp;
  final VoidCallback? onMessage;
  final bool showActions;

  String _headlineSystem(AppSettings settings) {
    final system = coach.coachingSystem.trim().isEmpty
        ? settings.tx('Strength Specialist', 'متخصص قوة')
        : coach.coachingSystem.trim();
    return settings.isArabic ? system : system.toUpperCase();
  }

  String _secondaryMetricLabel(AppSettings settings) {
    return switch (tier) {
      _CoachTier.diamond => settings.tx('Experience', 'الخبرة'),
      _CoachTier.elite => settings.tx('Clients', 'العملاء'),
      _CoachTier.iron => settings.tx('Method', 'الطريقة'),
    };
  }

  String _secondaryMetricValue(AppSettings settings) {
    return switch (tier) {
      _CoachTier.diamond => '${coach.yearsExperience}+ ${settings.tx('Yrs', 'سنة')}',
      _CoachTier.elite => '${coach.clientsCoached}+',
      _CoachTier.iron => coach.coachingSystem.trim().isEmpty
          ? settings.tx('Hybrid', 'هايبرد')
          : coach.coachingSystem.split(RegExp(r'[+/,&-]')).first.trim(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.appSettings;
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        onTap: onViewProfile,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PositionedDirectional(
              top: -10,
              end: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: tierColor.withValues(alpha: 0.42),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tierColor.withValues(alpha: 0.24),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tierIcon, size: 14, color: tierColor),
                    const SizedBox(width: 4),
                    Text(
                      tierLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tierColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.outline.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 256,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                          child: coach.avatarUrl.isNotEmpty
                              ? Image.network(
                                  coach.avatarUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) {
                                    return Container(
                                      color: AppColors.surfaceHighest,
                                      alignment: Alignment.center,
                                      child: Text(
                                        coach.name.isEmpty
                                            ? '?'
                                            : coach.name[0].toUpperCase(),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.displaySmall,
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  color: AppColors.surfaceHighest,
                                  alignment: Alignment.center,
                                  child: Text(
                                    coach.name.isEmpty
                                        ? '?'
                                        : coach.name[0].toUpperCase(),
                                    style: Theme.of(context).textTheme.displaySmall,
                                  ),
                                ),
                        ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.2),
                                  AppColors.surfaceLow.withValues(alpha: 0.92),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (isAssigned)
                          PositionedDirectional(
                            top: 14,
                            start: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: primary.withValues(alpha: 0.42),
                                ),
                              ),
                              child: Text(
                                settings.tx('ACTIVE', 'نشط'),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        PositionedDirectional(
                          bottom: 14,
                          start: 16,
                          end: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                coach.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _headlineSystem(settings),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: primary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    settings.tx(
                                      'Monthly plan',
                                      'اشتراك شهري',
                                    ),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${coach.subscriptionPrice.toStringAsFixed(0)}${settings.tx('/month', '/شهر')}',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _secondaryMetricLabel(settings),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _secondaryMetricValue(settings),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (showActions) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonal(
                                  onPressed: onViewProfile,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.surfaceHighest.withValues(
                                      alpha: 0.92,
                                    ),
                                    foregroundColor: AppColors.onSurface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  child: Text(
                                    settings.tx('VIEW PROFILE', 'عرض البروفايل'),
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: AppColors.onSurface,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        colorScheme.primary,
                                        colorScheme.primaryContainer,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primary.withValues(alpha: 0.35),
                                        blurRadius: 14,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: onSubscribe,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      foregroundColor: colorScheme.onPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: Text(
                                      isAssigned
                                          ? settings.tx('CHANGE COACH', 'غيّر الكوتش')
                                          : settings.tx(
                                              'SUBSCRIBE MONTHLY',
                                              'اشترك شهري',
                                            ),
                                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: colorScheme.onPrimary,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: onWhatsApp,
                                icon: const Icon(Icons.call_outlined, size: 18),
                                label: Text(settings.tx('WhatsApp', 'واتساب')),
                              ),
                              if (onMessage != null)
                                TextButton.icon(
                                  onPressed: onMessage,
                                  icon: const Icon(Icons.chat_outlined, size: 18),
                                  label: Text(settings.tx('Message', 'مراسلة')),
                                ),
                            ],
                          ),
                        ],
                      ],
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

class _CoachStatChip extends StatelessWidget {
  const _CoachStatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
