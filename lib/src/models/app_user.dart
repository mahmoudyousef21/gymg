enum ProfileGender { male, female, unspecified }

enum UserRole { trainee, coach }

UserRole parseUserRole(String? raw) {
  return switch (raw?.trim().toLowerCase()) {
    'coach' => UserRole.coach,
    _ => UserRole.trainee,
  };
}

String userRoleLabel(UserRole role, {required bool isArabic}) {
  if (isArabic) {
    return switch (role) {
      UserRole.trainee => 'متدرب',
      UserRole.coach => 'كوتش',
    };
  }

  return switch (role) {
    UserRole.trainee => 'Trainee',
    UserRole.coach => 'Coach',
  };
}

ProfileGender parseProfileGender(String? raw) {
  return switch (raw?.trim().toLowerCase()) {
    'male' => ProfileGender.male,
    'female' => ProfileGender.female,
    _ => ProfileGender.unspecified,
  };
}

String profileGenderLabel(ProfileGender gender, {required bool isArabic}) {
  if (isArabic) {
    return switch (gender) {
      ProfileGender.male => 'راجل',
      ProfileGender.female => 'ست',
      ProfileGender.unspecified => 'غير محدد',
    };
  }

  return switch (gender) {
    ProfileGender.male => 'Male',
    ProfileGender.female => 'Female',
    ProfileGender.unspecified => 'Unspecified',
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.location,
    required this.tier,
    required this.totalLifted,
    required this.percentile,
    this.role = UserRole.trainee,
    this.gender = ProfileGender.unspecified,
    this.age,
    this.weight,
    this.height,
    this.loginStreak = 0,
  });

  final String id;
  final String name;
  final String avatarUrl;
  final String location;
  final UserRole role;
  final ProfileGender gender;
  final int? age;
  final double? weight;
  final double? height;
  final int loginStreak;
  final String tier;
  final double totalLifted;
  final double percentile;

  AppUser copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? location,
    UserRole? role,
    ProfileGender? gender,
    int? age,
    double? weight,
    double? height,
    int? loginStreak,
    String? tier,
    double? totalLifted,
    double? percentile,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      location: location ?? this.location,
      role: role ?? this.role,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      weight: weight ?? this.weight,
      height: height ?? this.height,
      loginStreak: loginStreak ?? this.loginStreak,
      tier: tier ?? this.tier,
      totalLifted: totalLifted ?? this.totalLifted,
      percentile: percentile ?? this.percentile,
    );
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      avatarUrl: (map['avatar_url'] ?? '').toString(),
      location: (map['location'] ?? '').toString(),
      role: parseUserRole(map['role']?.toString()),
      gender: parseProfileGender(map['gender']?.toString()),
      age: _asInt(map['age']),
      weight: _asDouble(map['weight']),
      height: _asDouble(map['height']),
      loginStreak: _asInt(map['login_streak']) ?? 0,
      tier: (map['tier'] ?? 'IRON').toString(),
      totalLifted: _asDouble(map['total_lifted']) ?? 0,
      percentile: _asDouble(map['percentile']) ?? 99,
    );
  }

  Map<String, dynamic> toUpsertMap() {
    return {
      'id': id,
      'name': name,
      'avatar_url': avatarUrl.isEmpty ? null : avatarUrl,
      'location': location,
      'role': role.name,
      'gender': gender.name,
      'age': age,
      'weight': weight,
      'height': height,
      'tier': tier,
      'total_lifted': totalLifted,
      'percentile': percentile,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
