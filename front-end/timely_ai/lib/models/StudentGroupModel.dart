class StudentGroup {
  final String id;
  final int size;
  // A list of course IDs this group is enrolled in
  final List<String> enrolledCourses;
  // Map of CourseID -> InstructorID for specific faculty assignment
  final Map<String, String> instructorPreferences;
  // Availability grid: Map<Day, List<IsAvailable>>
  final Map<String, List<int>> availability;

  StudentGroup({
    required this.id,
    required this.size,
    required this.enrolledCourses,
    this.instructorPreferences = const {},
    this.availability = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'size': size,
      'enrolledCourses': enrolledCourses,
      'instructorPreferences': instructorPreferences,
      'availability': availability,
    };
  }
}
