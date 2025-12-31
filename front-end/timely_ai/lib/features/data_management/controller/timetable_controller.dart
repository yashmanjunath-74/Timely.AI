import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:timely_ai/models/CourseModel.dart';
import 'package:timely_ai/models/InstructorModel.dart';
import 'package:timely_ai/models/RoomModel.dart';
import 'package:timely_ai/models/StudentGroupModel.dart';

// The state class that holds all our application data.
class HomeState {
  final List<Instructor> instructors;
  final List<Course> courses;
  final List<Room> rooms;
  final List<StudentGroup> studentGroups;
  final List<String> days;
  final List<String> timeslots;
  final Map<String, dynamic> settings;

  HomeState({
    required this.instructors,
    required this.courses,
    required this.rooms,
    required this.studentGroups,
    required this.days,
    required this.timeslots,
    this.settings = const {},
  });

  // A copyWith method to easily create a new state object with updated values.
  HomeState copyWith({
    List<Instructor>? instructors,
    List<Course>? courses,
    List<Room>? rooms,
    List<StudentGroup>? studentGroups,
    Map<String, dynamic>? settings,
  }) {
    return HomeState(
      instructors: instructors ?? this.instructors,
      courses: courses ?? this.courses,
      rooms: rooms ?? this.rooms,
      studentGroups: studentGroups ?? this.studentGroups,
      days: days,
      timeslots: timeslots,
      settings: settings ?? this.settings,
    );
  }
}

// The StateNotifier class that manages our HomeState.
class HomeController extends StateNotifier<HomeState> {
  HomeController() : super(_getInitialState());

  // Initializes the state with sample data.
  static HomeState _getInitialState() {
    return HomeState(
      instructors: [],
      courses: [],
      rooms: [],
      studentGroups: [],
      days: [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ],
      timeslots: [
        '08:30 AM - 09:30 AM',
        '09:30 AM - 10:30 AM',
        '11:00 AM - 12:00 PM',
        '12:00 PM - 01:00 PM',
        '02:00 PM - 03:00 PM',
        '03:00 PM - 04:00 PM',
        '04:00 PM - 05:00 PM',
      ],
    );
  }

  // --- METHODS FOR INSTRUCTOR MANIPULATION ---
  void addInstructor(Instructor instructor) {
    state = state.copyWith(instructors: [...state.instructors, instructor]);
  }

  void updateInstructor(Instructor updatedInstructor) {
    state = state.copyWith(
      instructors: [
        for (final instructor in state.instructors)
          if (instructor.id == updatedInstructor.id)
            updatedInstructor
          else
            instructor,
      ],
    );
  }

  void deleteInstructor(int index) {
    final newList = List<Instructor>.from(state.instructors)..removeAt(index);
    state = state.copyWith(instructors: newList);
  }

  // --- METHODS FOR COURSE MANIPULATION ---
  void addCourse(Course course) {
    state = state.copyWith(courses: [...state.courses, course]);
  }

  void updateCourse(Course updatedCourse) {
    state = state.copyWith(
      courses: [
        for (final course in state.courses)
          if (course.id == updatedCourse.id) updatedCourse else course,
      ],
    );
  }

  void deleteCourse(int index) {
    final newList = List<Course>.from(state.courses)..removeAt(index);
    state = state.copyWith(courses: newList);
  }

  // --- METHODS FOR ROOM MANIPULATION ---
  void addRoom(Room room) {
    state = state.copyWith(rooms: [...state.rooms, room]);
  }

  void updateRoom(Room updatedRoom) {
    state = state.copyWith(
      rooms: [
        for (final room in state.rooms)
          if (room.id == updatedRoom.id) updatedRoom else room,
      ],
    );
  }

  void deleteRoom(int index) {
    final newList = List<Room>.from(state.rooms)..removeAt(index);
    state = state.copyWith(rooms: newList);
  }

  // --- METHODS FOR STUDENT GROUP MANIPULATION ---
  void addStudentGroup(StudentGroup group) {
    state = state.copyWith(studentGroups: [...state.studentGroups, group]);
  }

  void updateStudentGroup(StudentGroup updatedGroup) {
    state = state.copyWith(
      studentGroups: [
        for (final group in state.studentGroups)
          if (group.id == updatedGroup.id) updatedGroup else group,
      ],
    );
  }

  void deleteStudentGroup(int index) {
    final newList = List<StudentGroup>.from(state.studentGroups)
      ..removeAt(index);
    state = state.copyWith(studentGroups: newList);
  }

  // --- METHODS FOR SETTINGS MANIPULATION ---
  void updateSettings(Map<String, dynamic> newSettings) {
    state = state.copyWith(settings: newSettings);
  }

  // --- EXPORT DATA ---
  Future<void> exportData() async {
    try {
      final data = {
        'instructors': state.instructors.map((e) => e.toJson()).toList(),
        'courses': state.courses.map((e) => e.toJson()).toList(),
        'rooms': state.rooms.map((e) => e.toJson()).toList(),
        'studentGroups': state.studentGroups.map((e) => e.toJson()).toList(),
        'settings': state.settings,
      };

      final jsonString = jsonEncode(data);
      final bytes = utf8.encode(jsonString);
      final uint8List = Uint8List.fromList(bytes);

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Please select an output file:',
        fileName: 'timely_ai_data.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: uint8List,
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
      }
    } catch (e) {
      print('Error exporting data: $e');
      rethrow;
    }
  }

  // --- IMPORT DATA ---
  Future<void> importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        final fileOb = result.files.single;
        String content;

        if (fileOb.bytes != null) {
          content = utf8.decode(fileOb.bytes!);
        } else if (fileOb.path != null) {
          final file = File(fileOb.path!);
          content = await file.readAsString();
        } else {
          return;
        }

        final Map<String, dynamic> data = jsonDecode(content);

        final newInstructors = (data['instructors'] as List)
            .map((e) => Instructor.fromJson(e))
            .toList();
        final newCourses = (data['courses'] as List)
            .map((e) => Course.fromJson(e))
            .toList();
        final newRooms = (data['rooms'] as List)
            .map((e) => Room.fromJson(e))
            .toList();
        final newStudentGroups = (data['studentGroups'] as List)
            .map((e) => StudentGroup.fromJson(e))
            .toList();
        final newSettings = data['settings'] as Map<String, dynamic>? ?? {};

        state = state.copyWith(
          instructors: newInstructors,
          courses: newCourses,
          rooms: newRooms,
          studentGroups: newStudentGroups,
          settings: newSettings,
        );
      }
    } catch (e) {
      print('Error importing data: $e');
      rethrow;
    }
  }
}

// The provider that makes the HomeController available throughout the app.
final homeControllerProvider = StateNotifierProvider<HomeController, HomeState>(
  (ref) {
    return HomeController();
  },
);
