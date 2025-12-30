import 'dart:convert';
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
    const String serverUrl = 'http://10.101.73.121:5000/generate-timetable';

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

    try {
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

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
    } catch (e) {
      // Handle network errors (e.g., the server is not running).
      throw Exception(
        'Failed to connect to the server. Please ensure it is running.',
      );
    }
  }
}
