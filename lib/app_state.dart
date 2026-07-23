import 'dart:async';

import 'package:flutter/material.dart';

import 'data/app_repository.dart';
import 'models.dart';

export 'models.dart';

class AppState extends ChangeNotifier {
  AppState({AppRepository? repository})
    : _repository = repository ?? MemoryAppRepository() {
    _seedSessions();
  }

  final AppRepository _repository;
  Timer? _persistTimer;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  Object? persistenceError;

  UserRole role = UserRole.guest;
  bool isDarkMode = false;
  String weightUnit = 'kg';
  int restDefaultSeconds = 90;
  int restRemaining = 0;
  Timer? _restTimer;

  final List<ExerciseTemplate> exercises = const [
    ExerciseTemplate(
      id: 'bench',
      name: '바벨 벤치 프레스',
      muscle: '가슴',
      icon: Icons.fitness_center,
    ),
    ExerciseTemplate(
      id: 'incline',
      name: '인클라인 덤벨 프레스',
      muscle: '가슴',
      icon: Icons.sports_gymnastics,
    ),
    ExerciseTemplate(
      id: 'squat',
      name: '스쿼트',
      muscle: '하체',
      icon: Icons.accessibility_new,
    ),
    ExerciseTemplate(
      id: 'legpress',
      name: '레그 프레스',
      muscle: '하체',
      icon: Icons.airline_seat_recline_extra,
    ),
    ExerciseTemplate(
      id: 'latpull',
      name: '렛 풀 다운',
      muscle: '등',
      icon: Icons.vertical_align_bottom,
    ),
    ExerciseTemplate(id: 'row', name: '바벨 로우', muscle: '등', icon: Icons.rowing),
    ExerciseTemplate(
      id: 'ohp',
      name: '오버헤드 프레스',
      muscle: '어깨',
      icon: Icons.upload,
    ),
    ExerciseTemplate(
      id: 'lateral',
      name: '사이드 레터럴 레이즈',
      muscle: '어깨',
      icon: Icons.open_with,
    ),
    ExerciseTemplate(
      id: 'curl',
      name: '덤벨 컬',
      muscle: '팔',
      icon: Icons.fitness_center,
    ),
    ExerciseTemplate(
      id: 'plank',
      name: '플랭크',
      muscle: '복근',
      icon: Icons.timer_outlined,
    ),
    ExerciseTemplate(
      id: 'run',
      name: '트레드밀 러닝',
      muscle: '유산소',
      icon: Icons.directions_run,
    ),
  ];

  final Map<DateTime, WorkoutSession> sessions = {};
  final List<RoutineData> routines = [];

  Future<void> initialize() async {
    try {
      final snapshot = await _repository.load(exercises);
      if (snapshot != null) {
        role = snapshot.role;
        isDarkMode = snapshot.isDarkMode;
        weightUnit = snapshot.weightUnit;
        restDefaultSeconds = snapshot.restDefaultSeconds;
        sessions
          ..clear()
          ..addAll(snapshot.sessions);
        routines
          ..clear()
          ..addAll(snapshot.routines);
      }
      _initialized = true;
      persistenceError = null;
      if (snapshot == null) _schedulePersist();
    } catch (error) {
      _initialized = true;
      persistenceError = error;
    }
    notifyListeners();
  }

  List<RoutineData> get marketRoutines => [
    RoutineData(
      id: 'market_1',
      name: '초보자 4주 근력 스타트',
      description: '무리 없이 기초 근력을 만드는 주 3회 프로그램',
      color: const Color(0xFF10CEBD),
      exercises: [exercises[0], exercises[2], exercises[4]],
      author: '김코치 · 인증 트레이너',
      level: '초급',
    ),
    RoutineData(
      id: 'market_2',
      name: '등 라인 집중 루틴',
      description: '당기는 힘과 선명한 등 라인을 함께 만드는 루틴',
      color: const Color(0xFF8B5CF6),
      exercises: [exercises[4], exercises[5], exercises[8]],
      author: '모션짐 · 사업자 인증',
      level: '중급',
    ),
    RoutineData(
      id: 'market_3',
      name: '퇴근 후 35분 전신',
      description: '짧은 시간 안에 전신 볼륨을 채우는 고효율 구성',
      color: const Color(0xFFFFB20C),
      exercises: [exercises[2], exercises[0], exercises[6]],
      author: '박트레이너 · 인증 트레이너',
      level: '중급',
    ),
  ];

  void chooseRole(UserRole value) {
    role = value;
    _schedulePersist();
    notifyListeners();
  }

  void logout() {
    role = UserRole.guest;
    cancelRestTimer();
    _schedulePersist();
    notifyListeners();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    _schedulePersist();
    notifyListeners();
  }

  void setWeightUnit(String value) {
    weightUnit = value;
    _schedulePersist();
    notifyListeners();
  }

  void setRestDefaultSeconds(int seconds) {
    restDefaultSeconds = seconds.clamp(30, 600);
    _schedulePersist();
    notifyListeners();
  }

  DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  WorkoutSession sessionFor(DateTime date) {
    final key = dateOnly(date);
    return sessions.putIfAbsent(
      key,
      () => WorkoutSession(date: key, exercises: []),
    );
  }

  void addExercise(DateTime date, ExerciseTemplate template) {
    final session = sessionFor(date);
    if (session.exercises.any((item) => item.template.id == template.id)) {
      return;
    }
    session.exercises.add(
      WorkoutExercise(
        id: '${template.id}_${DateTime.now().microsecondsSinceEpoch}',
        template: template,
        sets: [
          WorkoutSetEntry(number: 1, weight: 40, reps: 10),
          WorkoutSetEntry(number: 2, weight: 40, reps: 10),
          WorkoutSetEntry(number: 3, weight: 40, reps: 8),
        ],
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  void addSet(WorkoutExercise exercise) {
    final previous = exercise.sets.lastOrNull;
    exercise.sets.add(
      WorkoutSetEntry(
        number: exercise.sets.length + 1,
        weight: previous?.weight ?? 20,
        reps: previous?.reps ?? 10,
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  void reorderExercise(WorkoutSession session, int oldIndex, int newIndex) {
    final item = session.exercises.removeAt(oldIndex);
    session.exercises.insert(newIndex, item);
    _schedulePersist();
    notifyListeners();
  }

  void removeExercise(WorkoutSession session, WorkoutExercise exercise) {
    session.exercises.remove(exercise);
    _schedulePersist();
    notifyListeners();
  }

  void removeSet(WorkoutExercise exercise, WorkoutSetEntry set) {
    exercise.sets.remove(set);
    for (var index = 0; index < exercise.sets.length; index++) {
      exercise.sets[index].number = index + 1;
    }
    _schedulePersist();
    notifyListeners();
  }

  void updateSet(
    WorkoutSetEntry set, {
    double? weight,
    int? reps,
    String? type,
  }) {
    if (weight != null) set.weight = weight.clamp(0, 999);
    if (reps != null) set.reps = reps.clamp(0, 999);
    if (type != null) set.type = type;
    _schedulePersist();
    notifyListeners();
  }

  void toggleSet(WorkoutSetEntry set) {
    set.completed = !set.completed;
    if (set.completed) startRestTimer(restDefaultSeconds);
    _schedulePersist();
    notifyListeners();
  }

  void copySession(DateTime from, DateTime to) {
    final source = sessions[dateOnly(from)];
    if (source == null) return;
    final target = dateOnly(to);
    sessions[target] = WorkoutSession(
      date: target,
      exercises: source.exercises.map((exercise) => exercise.copy()).toList(),
    );
    _schedulePersist();
    notifyListeners();
  }

  void deleteSession(DateTime date) {
    sessions.remove(dateOnly(date));
    _schedulePersist();
    notifyListeners();
  }

  void applyRoutine(RoutineData routine, DateTime date) {
    for (final exercise in routine.exercises) {
      addExercise(date, exercise);
    }
  }

  void importRoutine(RoutineData routine) {
    if (routines.any((item) => item.id == routine.id)) return;
    routines.add(routine);
    _schedulePersist();
    notifyListeners();
  }

  void createRoutine(String name, String description) {
    routines.add(
      RoutineData(
        id: 'routine_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        description: description,
        color: const Color(0xFF3B82F6),
        exercises: [exercises[0], exercises[2], exercises[4]],
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  Future<void> clearPersistedData() async {
    _persistTimer?.cancel();
    await _repository.clear();
  }

  void retryPersistence() => _schedulePersist();

  void _schedulePersist() {
    if (!_initialized) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        await _repository.save(
          AppSnapshot(
            role: role,
            isDarkMode: isDarkMode,
            weightUnit: weightUnit,
            restDefaultSeconds: restDefaultSeconds,
            sessions: sessions,
            routines: routines,
          ),
        );
        persistenceError = null;
      } catch (error) {
        persistenceError = error;
        notifyListeners();
      }
    });
  }

  void startRestTimer(int seconds) {
    _restTimer?.cancel();
    restRemaining = seconds;
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (restRemaining <= 1) {
        restRemaining = 0;
        timer.cancel();
      } else {
        restRemaining--;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelRestTimer() {
    _restTimer?.cancel();
    restRemaining = 0;
    notifyListeners();
  }

  void _seedSessions() {
    final now = DateTime.now();
    final templates = exercises;
    for (var day = 1; day <= 21; day++) {
      if (day == 1 ||
          day == 2 ||
          day == 3 ||
          day == 4 ||
          day == 5 ||
          day == 6) {
        continue;
      }
      if (day % 4 == 2) continue;
      final date = DateTime(now.year, now.month, day);
      final lower = day % 4 == 0;
      final exercise = WorkoutExercise(
        id: 'seed_$day',
        template: lower ? templates[2] : templates[0],
        sets: List.generate(
          lower ? 4 : 5,
          (index) => WorkoutSetEntry(
            number: index + 1,
            weight: lower ? 80 : 40,
            reps: lower ? 8 : 10,
            completed: day % 5 != 0 || index < 2,
          ),
        ),
      );
      sessions[date] = WorkoutSession(date: date, exercises: [exercise]);
    }
    routines.addAll([
      RoutineData(
        id: 'mine_1',
        name: '월요일 상체',
        description: '가슴과 등을 균형 있게 채우는 45분 루틴',
        color: const Color(0xFF10CEBD),
        exercises: [templates[0], templates[4], templates[6]],
      ),
      RoutineData(
        id: 'mine_2',
        name: '하체 집중',
        description: '스쿼트 중심의 하체 근력 루틴',
        color: const Color(0xFFFFB20C),
        exercises: [templates[2], templates[3]],
      ),
    ]);
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _persistTimer?.cancel();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required super.notifier, required super.child, super.key});

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this context.');
    return scope!.notifier!;
  }
}
