import '../models/gym_split.dart';

const _bench = ExerciseEntry(
  name: 'Bench Press (Barbell)',
  nameAr: 'Bench Press (Barbell)',
  sets: 4,
  reps: '5-8',
  youtubeId: 'vcBig73ojpE',
  primaryMuscles: ['Chest', 'Triceps', 'Front Delts'],
  primaryMusclesAr: ['Chest', 'Triceps', 'Front Delts'],
  variations: [
    'Dumbbell Bench Press',
    'Close-Grip Bench Press',
    'Paused Bench',
  ],
  variationsAr: [
    'Dumbbell Bench Press',
    'Close-Grip Bench Press',
    'Paused Bench',
  ],
);

const _inclineBench = ExerciseEntry(
  name: 'Incline Bench Press',
  nameAr: 'Incline Bench Press',
  sets: 3,
  reps: '8-12',
  youtubeId: 'DbFgADa2PL8',
  primaryMuscles: ['Upper Chest', 'Front Delts', 'Triceps'],
  primaryMusclesAr: ['Upper Chest', 'Front Delts', 'Triceps'],
  variations: ['Incline DB Press', 'Low-to-High Cable Fly', 'Landmine Press'],
  variationsAr: ['Incline DB Press', 'Low-to-High Cable Fly', 'Landmine Press'],
);

const _squat = ExerciseEntry(
  name: 'Barbell Squat',
  nameAr: 'Barbell Squat',
  sets: 4,
  reps: '5-8',
  youtubeId: 'ultWZbUMPL8',
  primaryMuscles: ['Quads', 'Glutes', 'Core'],
  primaryMusclesAr: ['Quads', 'Glutes', 'Core'],
  variations: ['Goblet Squat', 'Leg Press', 'Bulgarian Split Squat'],
  variationsAr: ['Goblet Squat', 'Leg Press', 'Bulgarian Split Squat'],
);

const _deadlift = ExerciseEntry(
  name: 'Deadlift (Conventional)',
  nameAr: 'Deadlift (Conventional)',
  sets: 3,
  reps: '3-5',
  youtubeId: 'op9kVnSso6Q',
  primaryMuscles: ['Hamstrings', 'Glutes', 'Lower Back', 'Traps'],
  primaryMusclesAr: ['Hamstrings', 'Glutes', 'Lower Back', 'Traps'],
  variations: ['Romanian Deadlift', 'Trap Bar Deadlift', 'Sumo Deadlift'],
  variationsAr: ['Romanian Deadlift', 'Trap Bar Deadlift', 'Sumo Deadlift'],
);

const _rdl = ExerciseEntry(
  name: 'Romanian Deadlift',
  nameAr: 'Romanian Deadlift',
  sets: 3,
  reps: '10-12',
  youtubeId: 'JCXUYuzwNrM',
  primaryMuscles: ['Hamstrings', 'Glutes', 'Lower Back'],
  primaryMusclesAr: ['Hamstrings', 'Glutes', 'Lower Back'],
  variations: ['Stiff-Leg Deadlift', 'Single-Leg RDL', 'Leg Curl'],
  variationsAr: ['Stiff-Leg Deadlift', 'Single-Leg RDL', 'Leg Curl'],
);

const _ohp = ExerciseEntry(
  name: 'Overhead Press (Barbell)',
  nameAr: 'Overhead Press (Barbell)',
  sets: 3,
  reps: '6-10',
  youtubeId: '2yjwXTZQDDI',
  primaryMuscles: ['Shoulders', 'Triceps', 'Upper Chest'],
  primaryMusclesAr: ['Shoulders', 'Triceps', 'Upper Chest'],
  variations: ['Dumbbell Shoulder Press', 'Arnold Press', 'Landmine Press'],
  variationsAr: ['Dumbbell Shoulder Press', 'Arnold Press', 'Landmine Press'],
);

const _barbellRow = ExerciseEntry(
  name: 'Barbell Row',
  nameAr: 'Barbell Row',
  sets: 4,
  reps: '6-10',
  youtubeId: 'T3N-TO4reLQ',
  primaryMuscles: ['Lats', 'Mid Back', 'Biceps'],
  primaryMusclesAr: ['Lats', 'Mid Back', 'Biceps'],
  variations: ['Dumbbell Row', 'Seated Cable Row', 'Chest-Supported Row'],
  variationsAr: ['Dumbbell Row', 'Seated Cable Row', 'Chest-Supported Row'],
);

const _pullups = ExerciseEntry(
  name: 'Pull Ups',
  nameAr: 'Pull Ups',
  sets: 3,
  reps: '6-10',
  youtubeId: 'poFBDhX1L3Y',
  primaryMuscles: ['Lats', 'Biceps', 'Rear Delts'],
  primaryMusclesAr: ['Lats', 'Biceps', 'Rear Delts'],
  variations: ['Lat Pulldown', 'Assisted Pull-Up', 'Chin Ups'],
  variationsAr: ['Lat Pulldown', 'Assisted Pull-Up', 'Chin Ups'],
);

const _latPulldown = ExerciseEntry(
  name: 'Lat Pulldown',
  nameAr: 'Lat Pulldown',
  sets: 3,
  reps: '10-12',
  youtubeId: 'CAwf7n6Luuc',
  primaryMuscles: ['Lats', 'Biceps'],
  primaryMusclesAr: ['Lats', 'Biceps'],
  variations: ['Pull Ups', 'Single-Arm Pulldown', 'Straight-Arm Pulldown'],
  variationsAr: ['Pull Ups', 'Single-Arm Pulldown', 'Straight-Arm Pulldown'],
);

const _facePulls = ExerciseEntry(
  name: 'Face Pulls',
  nameAr: 'Face Pulls',
  sets: 3,
  reps: '15-20',
  youtubeId: 'HSoHeSjBEKs',
  primaryMuscles: ['Rear Delts', 'Rotator Cuff', 'Traps'],
  primaryMusclesAr: ['Rear Delts', 'Rotator Cuff', 'Traps'],
  variations: ['Band Pull-Apart', 'Rear Delt Fly', 'Cable Rear Delt Row'],
  variationsAr: ['Band Pull-Apart', 'Rear Delt Fly', 'Cable Rear Delt Row'],
);

const _lateralRaises = ExerciseEntry(
  name: 'Lateral Raises',
  nameAr: 'Lateral Raises',
  sets: 3,
  reps: '12-15',
  youtubeId: '3VcKaXpzqRo',
  primaryMuscles: ['Side Delts'],
  primaryMusclesAr: ['Side Delts'],
  variations: [
    'Cable Lateral Raise',
    'Leaning Lateral Raise',
    'Machine Lateral',
  ],
  variationsAr: [
    'Cable Lateral Raise',
    'Leaning Lateral Raise',
    'Machine Lateral',
  ],
);

const _tricepPushdown = ExerciseEntry(
  name: 'Triceps Pushdown',
  nameAr: 'Triceps Pushdown',
  sets: 3,
  reps: '12-15',
  youtubeId: 'nRiJVZDpdL0',
  primaryMuscles: ['Triceps'],
  primaryMusclesAr: ['Triceps'],
  variations: ['Skull Crushers', 'Overhead Extension', 'Dips'],
  variationsAr: ['Skull Crushers', 'Overhead Extension', 'Dips'],
);

const _bicepCurls = ExerciseEntry(
  name: 'Bicep Curls (Dumbbell)',
  nameAr: 'Bicep Curls (Dumbbell)',
  sets: 3,
  reps: '10-12',
  youtubeId: 'ykJmrZ5v0Oo',
  primaryMuscles: ['Biceps'],
  primaryMusclesAr: ['Biceps'],
  variations: ['Barbell Curl', 'Hammer Curl', 'Incline Dumbbell Curl'],
  variationsAr: ['Barbell Curl', 'Hammer Curl', 'Incline Dumbbell Curl'],
);

const _legPress = ExerciseEntry(
  name: 'Leg Press',
  nameAr: 'Leg Press',
  sets: 3,
  reps: '10-15',
  youtubeId: 'IZxyjW7MPJQ',
  primaryMuscles: ['Quads', 'Glutes'],
  primaryMusclesAr: ['Quads', 'Glutes'],
  variations: ['Single-Leg Press', 'Hack Squat', 'Goblet Squat'],
  variationsAr: ['Single-Leg Press', 'Hack Squat', 'Goblet Squat'],
);

const _lunges = ExerciseEntry(
  name: 'Walking Lunges',
  nameAr: 'Walking Lunges',
  sets: 3,
  reps: '10 each leg',
  youtubeId: 'wrwwXE_x-pQ',
  primaryMuscles: ['Quads', 'Glutes', 'Hamstrings'],
  primaryMusclesAr: ['Quads', 'Glutes', 'Hamstrings'],
  variations: ['Reverse Lunge', 'Bulgarian Split Squat', 'Step Ups'],
  variationsAr: ['Reverse Lunge', 'Bulgarian Split Squat', 'Step Ups'],
);

const _calfRaises = ExerciseEntry(
  name: 'Standing Calf Raises',
  nameAr: 'Standing Calf Raises',
  sets: 4,
  reps: '15-20',
  youtubeId: 'C1c7dIyiCPg',
  primaryMuscles: ['Calves'],
  primaryMusclesAr: ['Calves'],
  variations: [
    'Seated Calf Raises',
    'Single-Leg Calf Raises',
    'Leg Press Calf',
  ],
  variationsAr: [
    'Seated Calf Raises',
    'Single-Leg Calf Raises',
    'Leg Press Calf',
  ],
);

const splitsCatalog = <int, List<GymSplit>>{
  1: [
    GymSplit(
      id: 'full_body_1',
      name: 'Full Body',
      nameAr: 'Full Body',
      description: 'Train all major muscle groups in one high-value session.',
      descriptionAr: 'Train all major muscle groups in one high-value session.',
      daysPerWeek: 1,
      days: [
        GymSplitDay(
          label: 'Full Body',
          labelAr: 'Full Body',
          muscles: ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms'],
          musclesAr: ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms'],
          exercises: [_squat, _bench, _barbellRow, _ohp, _rdl],
        ),
      ],
    ),
  ],
  2: [
    GymSplit(
      id: 'full_body_2',
      name: 'Full Body 2x',
      nameAr: 'Full Body 2x',
      description: 'A/B full body split with extra recovery time.',
      descriptionAr: 'A/B full body split with extra recovery time.',
      daysPerWeek: 2,
      days: [
        GymSplitDay(
          label: 'Full Body A',
          labelAr: 'Full Body A',
          muscles: ['Squat', 'Bench', 'Row'],
          musclesAr: ['Squat', 'Bench', 'Row'],
          exercises: [_squat, _bench, _barbellRow, _bicepCurls],
        ),
        GymSplitDay(
          label: 'Full Body B',
          labelAr: 'Full Body B',
          muscles: ['Deadlift', 'Press', 'Pull'],
          musclesAr: ['Deadlift', 'Press', 'Pull'],
          exercises: [_deadlift, _ohp, _pullups, _tricepPushdown],
        ),
      ],
    ),
  ],
  3: [
    GymSplit(
      id: 'ppl_3',
      name: 'Push Pull Legs',
      nameAr: 'Push Pull Legs',
      description: 'Classic split for strength and hypertrophy balance.',
      descriptionAr: 'Classic split for strength and hypertrophy balance.',
      daysPerWeek: 3,
      days: [
        GymSplitDay(
          label: 'Push',
          labelAr: 'Push',
          muscles: ['Chest', 'Shoulders', 'Triceps'],
          musclesAr: ['Chest', 'Shoulders', 'Triceps'],
          exercises: [
            _bench,
            _inclineBench,
            _ohp,
            _lateralRaises,
            _tricepPushdown,
          ],
        ),
        GymSplitDay(
          label: 'Pull',
          labelAr: 'Pull',
          muscles: ['Back', 'Biceps', 'Rear Delts'],
          musclesAr: ['Back', 'Biceps', 'Rear Delts'],
          exercises: [
            _barbellRow,
            _pullups,
            _latPulldown,
            _facePulls,
            _bicepCurls,
          ],
        ),
        GymSplitDay(
          label: 'Legs',
          labelAr: 'Legs',
          muscles: ['Quads', 'Hamstrings', 'Glutes', 'Calves'],
          musclesAr: ['Quads', 'Hamstrings', 'Glutes', 'Calves'],
          exercises: [_squat, _rdl, _legPress, _lunges, _calfRaises],
        ),
      ],
    ),
  ],
  4: [
    GymSplit(
      id: 'upper_lower',
      name: 'Upper Lower',
      nameAr: 'Upper Lower',
      description: 'Two upper sessions and two lower sessions each week.',
      descriptionAr: 'Two upper sessions and two lower sessions each week.',
      daysPerWeek: 4,
      days: [
        GymSplitDay(
          label: 'Upper A',
          labelAr: 'Upper A',
          muscles: ['Chest', 'Back', 'Shoulders', 'Arms'],
          musclesAr: ['Chest', 'Back', 'Shoulders', 'Arms'],
          exercises: [_bench, _barbellRow, _ohp, _latPulldown],
        ),
        GymSplitDay(
          label: 'Lower A',
          labelAr: 'Lower A',
          muscles: ['Quads', 'Hamstrings', 'Glutes'],
          musclesAr: ['Quads', 'Hamstrings', 'Glutes'],
          exercises: [_squat, _rdl, _legPress, _calfRaises],
        ),
        GymSplitDay(
          label: 'Upper B',
          labelAr: 'Upper B',
          muscles: ['Chest', 'Back', 'Shoulders', 'Arms'],
          musclesAr: ['Chest', 'Back', 'Shoulders', 'Arms'],
          exercises: [_inclineBench, _pullups, _facePulls, _tricepPushdown],
        ),
        GymSplitDay(
          label: 'Lower B',
          labelAr: 'Lower B',
          muscles: ['Posterior Chain', 'Quads', 'Calves'],
          musclesAr: ['Posterior Chain', 'Quads', 'Calves'],
          exercises: [_deadlift, _squat, _lunges, _calfRaises],
        ),
      ],
    ),
  ],
  5: [
    GymSplit(
      id: 'ppl_upper_lower',
      name: 'PPL + Upper Lower',
      nameAr: 'PPL + Upper Lower',
      description:
          'Five-day plan with volume progression and recovery windows.',
      descriptionAr:
          'Five-day plan with volume progression and recovery windows.',
      daysPerWeek: 5,
      days: [
        GymSplitDay(
          label: 'Push',
          labelAr: 'Push',
          muscles: ['Chest', 'Shoulders', 'Triceps'],
          musclesAr: ['Chest', 'Shoulders', 'Triceps'],
          exercises: [
            _bench,
            _inclineBench,
            _ohp,
            _lateralRaises,
            _tricepPushdown,
          ],
        ),
        GymSplitDay(
          label: 'Pull',
          labelAr: 'Pull',
          muscles: ['Back', 'Biceps'],
          musclesAr: ['Back', 'Biceps'],
          exercises: [_barbellRow, _pullups, _latPulldown, _bicepCurls],
        ),
        GymSplitDay(
          label: 'Legs',
          labelAr: 'Legs',
          muscles: ['Quads', 'Hamstrings', 'Glutes'],
          musclesAr: ['Quads', 'Hamstrings', 'Glutes'],
          exercises: [_squat, _rdl, _legPress, _calfRaises],
        ),
        GymSplitDay(
          label: 'Upper',
          labelAr: 'Upper',
          muscles: ['Chest', 'Back', 'Arms'],
          musclesAr: ['Chest', 'Back', 'Arms'],
          exercises: [_inclineBench, _barbellRow, _facePulls, _tricepPushdown],
        ),
        GymSplitDay(
          label: 'Lower',
          labelAr: 'Lower',
          muscles: ['Quads', 'Glutes', 'Hamstrings'],
          musclesAr: ['Quads', 'Glutes', 'Hamstrings'],
          exercises: [_deadlift, _lunges, _legPress, _calfRaises],
        ),
      ],
    ),
  ],
  6: [
    GymSplit(
      id: 'ppl_6',
      name: 'Push Pull Legs x2',
      nameAr: 'Push Pull Legs x2',
      description: 'High-frequency six-day split for advanced athletes.',
      descriptionAr: 'High-frequency six-day split for advanced athletes.',
      daysPerWeek: 6,
      days: [
        GymSplitDay(
          label: 'Push A',
          labelAr: 'Push A',
          muscles: ['Chest', 'Shoulders', 'Triceps'],
          musclesAr: ['Chest', 'Shoulders', 'Triceps'],
          exercises: [_bench, _ohp, _lateralRaises, _tricepPushdown],
        ),
        GymSplitDay(
          label: 'Pull A',
          labelAr: 'Pull A',
          muscles: ['Back', 'Biceps'],
          musclesAr: ['Back', 'Biceps'],
          exercises: [_barbellRow, _pullups, _facePulls, _bicepCurls],
        ),
        GymSplitDay(
          label: 'Legs A',
          labelAr: 'Legs A',
          muscles: ['Quads', 'Hamstrings', 'Glutes'],
          musclesAr: ['Quads', 'Hamstrings', 'Glutes'],
          exercises: [_squat, _rdl, _legPress, _calfRaises],
        ),
        GymSplitDay(
          label: 'Push B',
          labelAr: 'Push B',
          muscles: ['Chest', 'Shoulders', 'Triceps'],
          musclesAr: ['Chest', 'Shoulders', 'Triceps'],
          exercises: [_inclineBench, _ohp, _lateralRaises, _tricepPushdown],
        ),
        GymSplitDay(
          label: 'Pull B',
          labelAr: 'Pull B',
          muscles: ['Back', 'Biceps'],
          musclesAr: ['Back', 'Biceps'],
          exercises: [_latPulldown, _barbellRow, _facePulls, _bicepCurls],
        ),
        GymSplitDay(
          label: 'Legs B',
          labelAr: 'Legs B',
          muscles: ['Posterior Chain', 'Quads', 'Calves'],
          musclesAr: ['Posterior Chain', 'Quads', 'Calves'],
          exercises: [_deadlift, _lunges, _legPress, _calfRaises],
        ),
      ],
    ),
  ],
};
