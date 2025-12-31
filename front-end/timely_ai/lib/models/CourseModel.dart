class Course {
  final String id;
  final String name;
  final int lectureHours;
  final int labHours;
  final List<String> qualifiedInstructors;
  final List<String> equipment;
  final int credits;
  final String ltp;
  final String labType; // NEW

  Course({
    required this.id,
    required this.name,
    required this.lectureHours,
    required this.labHours,
    required this.qualifiedInstructors,
    this.equipment = const [],
    this.credits = 4, // Default value
    this.ltp = '3-0-2', // Default value
    this.labType = 'Computer Lab', // Default value
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lectureHours': lectureHours,
      'labHours': labHours,
      'qualifiedInstructors': qualifiedInstructors,
      'equipment': equipment,
      'credits': credits,
      'ltp': ltp,
      'labType': labType,
    };
  }

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      name: json['name'] as String,
      lectureHours: json['lectureHours'] as int,
      labHours: json['labHours'] as int,
      qualifiedInstructors: List<String>.from(json['qualifiedInstructors']),
      equipment: List<String>.from(json['equipment'] ?? []),
      credits: json['credits'] as int? ?? 4,
      ltp: json['ltp'] as String? ?? '3-0-2',
      labType: json['labType'] as String? ?? 'Computer Lab',
    );
  }
}
