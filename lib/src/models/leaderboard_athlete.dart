class LeaderboardAthlete {
  const LeaderboardAthlete({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.location,
    required this.gender,
    required this.profileTier,
    required this.movementTier,
    required this.highestLift,
    required this.dominantMovement,
    required this.rank,
  });

  final String id;
  final String name;
  final String avatarUrl;
  final String location;
  final String gender;
  final String profileTier;
  final String movementTier;
  final double highestLift;
  final String dominantMovement;
  final int rank;

  LeaderboardAthlete copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? location,
    String? gender,
    String? profileTier,
    String? movementTier,
    double? highestLift,
    String? dominantMovement,
    int? rank,
  }) {
    return LeaderboardAthlete(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      location: location ?? this.location,
      gender: gender ?? this.gender,
      profileTier: profileTier ?? this.profileTier,
      movementTier: movementTier ?? this.movementTier,
      highestLift: highestLift ?? this.highestLift,
      dominantMovement: dominantMovement ?? this.dominantMovement,
      rank: rank ?? this.rank,
    );
  }

  factory LeaderboardAthlete.fromMap(Map<String, dynamic> map, int rank) {
    return LeaderboardAthlete(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? 'Athlete').toString(),
      avatarUrl: (map['avatar_url'] ?? '').toString(),
      location: (map['location'] ?? 'Global').toString(),
      gender: (map['gender'] ?? 'unspecified').toString(),
        profileTier: (map['profile_tier'] ?? map['tier'] ?? 'IRON').toString(),
        movementTier:
          (map['movement_tier'] ?? map['tier'] ?? 'IRON').toString(),
        highestLift:
          _asDouble(map['highest_lift'] ?? map['total_lifted']) ?? 0,
        dominantMovement:
          (map['dominant_movement'] ?? 'General').toString(),
      rank: rank,
    );
  }

  static double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
