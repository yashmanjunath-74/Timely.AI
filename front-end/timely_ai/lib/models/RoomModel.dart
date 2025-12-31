class Room {
  final String id;
  final int capacity;
  final String type;
  final List<String> equipment; // NEW: Added equipment list
  final Map<String, List<int>> availability;

  Room({
    required this.id,
    required this.capacity,
    required this.type,
    this.equipment = const [], // NEW: Initialize as empty list
    this.availability = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'capacity': capacity,
      'type': type,
      'equipment': equipment, // NEW: Include in JSON
      'availability': availability,
    };
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String,
      capacity: json['capacity'] as int,
      type: json['type'] as String,
      equipment: List<String>.from(json['equipment'] ?? []),
      availability:
          (json['availability'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, List<int>.from(value)),
          ) ??
          const {},
    );
  }
}
