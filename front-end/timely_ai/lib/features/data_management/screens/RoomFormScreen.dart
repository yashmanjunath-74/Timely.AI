import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timely_ai/models/RoomModel.dart';
import 'package:timely_ai/shared/widgets/glass_card.dart';
import 'package:timely_ai/shared/widgets/saas_scaffold.dart';

class RoomFormScreen extends StatefulWidget {
  final Room? initialRoom;

  const RoomFormScreen({super.key, this.initialRoom});

  @override
  State<RoomFormScreen> createState() => _RoomFormScreenState();
}

class _RoomFormScreenState extends State<RoomFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _idController;
  late TextEditingController _capacityController;
  late TextEditingController _equipmentController;
  late String _selectedType;
  late List<String> _equipment;
  late Map<String, List<int>> _availability;

  final List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  final List<String> _timeslots = [
    '08:30 AM',
    '09:30 AM',
    '11:00 AM',
    '12:00 PM',
    '02:00 PM',
    '03:00 PM',
    '04:00 PM',
  ];

  final List<String> _roomTypes = [
    'Lecture Hall',
    'Computer Lab',
    'Hardware Lab',
    'Seminar Room',
    'Lab',
  ];

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController(text: widget.initialRoom?.id ?? '');
    _capacityController = TextEditingController(
      text: widget.initialRoom?.capacity.toString() ?? '',
    );
    _equipmentController = TextEditingController();
    _selectedType = widget.initialRoom?.type ?? _roomTypes[0];
    _equipment = List<String>.from(widget.initialRoom?.equipment ?? []);

    // Initialize availability
    if (widget.initialRoom != null &&
        widget.initialRoom!.availability.isNotEmpty) {
      _availability = Map<String, List<int>>.from(
        widget.initialRoom!.availability.map(
          (key, value) => MapEntry(key, List<int>.from(value)),
        ),
      );
      // Ensure it matches the new timeslot length
      for (var day in _days) {
        if (!_availability.containsKey(day)) {
          _availability[day] = List.filled(_timeslots.length, 1);
        } else if (_availability[day]!.length != _timeslots.length) {
          final oldList = _availability[day]!;
          if (oldList.length < _timeslots.length) {
            _availability[day] = [
              ...oldList,
              ...List.filled(_timeslots.length - oldList.length, 1),
            ];
          } else {
            _availability[day] = oldList.sublist(0, _timeslots.length);
          }
        }
      }
    } else {
      // Default: All available (1)
      _availability = {
        for (var day in _days) day: List.filled(_timeslots.length, 1),
      };

      // Optional: Set Saturday afternoon to unavailable by default
      if (_availability.containsKey('Saturday')) {
        for (int i = 4; i < _timeslots.length; i++) {
          _availability['Saturday']![i] = 0;
        }
      }
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _capacityController.dispose();
    _equipmentController.dispose();
    super.dispose();
  }

  void _addEquipment() {
    final text = _equipmentController.text.trim();
    if (text.isNotEmpty && !_equipment.contains(text)) {
      setState(() {
        _equipment.add(text);
        _equipmentController.clear();
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final room = Room(
        id: _idController.text,
        capacity: int.parse(_capacityController.text),
        type: _selectedType,
        equipment: _equipment,
        availability: _availability,
      );
      Navigator.of(context).pop(room);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SaaSScaffold(
      title: widget.initialRoom == null ? 'Add New Room' : 'Edit Room',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Enter room details and available equipment',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 24),

            // Details Card
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Room ID / Name *'),
                  TextFormField(
                    controller: _idController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('Room A101'),
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter an ID' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Capacity *'),
                  TextFormField(
                    controller: _capacityController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('30'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a capacity' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Room Type *'),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedType,
                    dropdownColor: const Color(0xFF1A1A1A),
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('Select Type'),
                    items: _roomTypes.map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedType = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Equipment Card
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Available Equipment'),
                  const Text(
                    'Type equipment name and press Enter or click Add',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _equipmentController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('e.g., Projector'),
                          onFieldSubmitted: (_) => _addEquipment(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _addEquipment,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_equipment.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _equipment.map((e) {
                        return Chip(
                          label: Text(
                            e,
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.white.withOpacity(0.1),
                          deleteIcon: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white54,
                          ),
                          onDeleted: () {
                            setState(() {
                              _equipment.remove(e);
                            });
                          },
                          side: BorderSide.none,
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Availability Card
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Room Availability',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Click on time slots to mark when the room is unavailable',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // Grid
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      children: [
                        // Header Row
                        Row(
                          children: [
                            const SizedBox(width: 80), // Space for time labels
                            ..._days.map(
                              (day) => Container(
                                width: 80,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  day.substring(0, 3),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Time Slots
                        ...List.generate(_timeslots.length, (timeIndex) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    _timeslots[timeIndex],
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                ..._days.map((day) {
                                  final isAvailable =
                                      _availability[day]![timeIndex] == 1;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _availability[day]![timeIndex] =
                                            isAvailable ? 0 : 1;
                                      });
                                    },
                                    child: Container(
                                      width: 80,
                                      height: 36,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isAvailable
                                            ? const Color(
                                                0xFF00C6FF,
                                              ).withOpacity(0.2) // Neon Cyan
                                            : Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isAvailable
                                              ? const Color(0xFF00C6FF)
                                              : Colors.white10,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Legend
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        _buildLegendItem(true, 'Available'),
                        const SizedBox(width: 24),
                        _buildLegendItem(false, 'Unavailable'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Save Room',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Colors.white,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFFF4E50)), // Neon Red
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildLegendItem(bool isAvailable, String label) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isAvailable
                ? const Color(0xFF00C6FF).withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isAvailable ? const Color(0xFF00C6FF) : Colors.white10,
            ),
          ),
          child: isAvailable
              ? const Icon(Icons.check, size: 14, color: Color(0xFF00C6FF))
              : const Icon(Icons.close, size: 14, color: Colors.redAccent),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}
