class Instructor {
  final String id;
  final String name;
  // Represents a grid of availability: Map<Day, List<IsAvailable>>
  // e.g., {'Monday': [1, 1, 0, 1], 'Tuesday': [0, 1, 1, 1]} where 1 is available.
  final Map<String, List<int>> availability;

  Instructor({
    required this.id,
    required this.name,
    required this.availability,
  });

  // Convert the object to a JSON format for the API request
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'availability': availability};
  }

  factory Instructor.fromJson(Map<String, dynamic> json) {
    return Instructor(
      id: json['id'] as String,
      name: json['name'] as String,
      availability: (json['availability'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, List<int>.from(value)),
      ),
    );
  }
}
