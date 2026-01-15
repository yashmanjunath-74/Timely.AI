import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:timely_ai/features/data_management/controller/timetable_controller.dart';

// Provider for the repository, making it easy to access from other parts of the app.
final timetableRepositoryProvider = Provider((ref) {
  return TimetableRepository(ref: ref);
});

class TimetableRepository {
  final Ref _ref;
  TimetableRepository({required Ref ref}) : _ref = ref;

  // This method sends the entire app state to the backend for solving.
  Future<Map<String, dynamic>> generateTimetable() async {
    // The server URL for your local Python backend.
    // 10.0.2.2 is a special IP for the Android emulator to access the host machine (localhost).
    const String serverUrl = 'http://10.60.168.121:5000/generate-timetable';

    // Get the current state (all our lists of data) from the HomeController.
    final homeState = _ref.read(homeControllerProvider);

    // Convert all the Dart data model objects into a JSON format that the Python server understands.
    final requestBody = jsonEncode({
      'instructors': homeState.instructors.map((e) => e.toJson()).toList(),
      'courses': homeState.courses.map((e) => e.toJson()).toList(),
      'rooms': homeState.rooms.map((e) => e.toJson()).toList(),
      'student_groups': homeState.studentGroups.map((e) => e.toJson()).toList(),

      'days': homeState.days,
      'timeslots': homeState.timeslots,
      'settings': homeState.settings,
    });

    http.Response response;
    try {
      response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );
    } catch (e) {
      // Handle network errors (e.g., the server is not running).
      throw Exception(
        'Failed to connect to the server. Please ensure it is running.',
      );
    }

    if (response.statusCode == 200) {
      // If the server returns a success response, parse and return the data.
      return jsonDecode(response.body);
    } else {
      // If the server returns an error, parse the message and throw an exception.
      final errorData = jsonDecode(response.body);
      throw Exception(
        errorData['message'] ?? 'An unknown server error occurred.',
      );
    }
  }

  // --- PERSISTENCE METHODS ---

  // Save a timetable locally
  Future<void> saveTimetable(
    List<Map<String, dynamic>> schedule,
    String name,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Create a unique ID
    final String id = DateTime.now().millisecondsSinceEpoch.toString();
    final String dateStr = DateTime.now().toString().split('.')[0];

    // Save the schedule data
    await prefs.setString('timetable_\$id', jsonEncode(schedule));

    // Update metadata list
    final List<String> metaList = prefs.getStringList('timetable_meta') ?? [];
    final metaData = {'id': id, 'name': name, 'date': dateStr};
    metaList.add(jsonEncode(metaData));
    await prefs.setStringList('timetable_meta', metaList);
  }

  // Get list of saved timetables (metadata only)
  Future<List<Map<String, dynamic>>> getSavedTimetables() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> metaList = prefs.getStringList('timetable_meta') ?? [];

    return metaList.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  // Load a specific timetable by ID
  Future<List<Map<String, dynamic>>> loadTimetable(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('timetable_\$id');

    if (data != null) {
      final List<dynamic> list = jsonDecode(data);
      return List<Map<String, dynamic>>.from(list);
    }
    return [];
  }

  // Delete a timetable
  Future<void> deleteTimetable(String id) async {
    final prefs = await SharedPreferences.getInstance();

    // Remove data
    await prefs.remove('timetable_\$id');

    // Remove from metadata
    final List<String> metaList = prefs.getStringList('timetable_meta') ?? [];
    final newList = metaList.where((e) {
      final Map<String, dynamic> meta = jsonDecode(e);
      return meta['id'] != id;
    }).toList();

    await prefs.setStringList('timetable_meta', newList);
  }
}
