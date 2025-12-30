import 'package:flutter/material.dart';
import 'package:timely_ai/models/InstructorModel.dart';
import 'package:timely_ai/shared/widgets/glass_card.dart';
import 'package:timely_ai/shared/widgets/saas_scaffold.dart';

class InstructorFormScreen extends StatefulWidget {
  final Instructor? initialInstructor;

  const InstructorFormScreen({super.key, this.initialInstructor});

  @override
  State<InstructorFormScreen> createState() => _InstructorFormScreenState();
}

class _InstructorFormScreenState extends State<InstructorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _id;
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

  @override
  void initState() {
    super.initState();
    _name = widget.initialInstructor?.name ?? '';
    _id = widget.initialInstructor?.id ?? '';

    // Initialize availability
    if (widget.initialInstructor != null) {
      // Deep copy existing availability
      _availability = Map<String, List<int>>.from(
        widget.initialInstructor!.availability.map(
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

      // Set Saturday afternoon to unavailable (0)
      // Indices 4, 5, 6 correspond to 02:00 PM, 03:00 PM, 04:00 PM
      if (_availability.containsKey('Saturday')) {
        for (int i = 4; i < _timeslots.length; i++) {
          _availability['Saturday']![i] = 0;
        }
      }
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      // If ID is empty (e.g. user didn't fill it), generate one
      if (_id.isEmpty) {
        _id =
            'INS${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      }

      final newInstructor = Instructor(
        id: _id,
        name: _name,
        availability: _availability,
      );
      Navigator.of(context).pop(newInstructor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SaaSScaffold(
      title: widget.initialInstructor == null
          ? 'Add New Instructor'
          : 'Edit Instructor',
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Enter instructor details and mark unavailable time slots',
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
                    _buildLabel('Instructor Name *'),
                    TextFormField(
                      initialValue: _name,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Dr. Jane Smith'),
                      validator: (value) =>
                          (value == null || value.isEmpty) ? 'Required' : null,
                      onSaved: (value) => _name = value!,
                    ),
                    const SizedBox(height: 16),
                    _buildLabel('Instructor ID'),
                    TextFormField(
                      initialValue: _id,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('INS001'),
                      onSaved: (value) => _id = value ?? '',
                    ),
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
                      'Availability',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Click on time slots to mark when the instructor is unavailable',
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
                              const SizedBox(
                                width: 80,
                              ), // Space for time labels
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
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
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
                    onPressed: _submitForm,
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
                      'Save Instructor',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        borderSide: const BorderSide(color: Color(0xFF00C6FF)), // Neon Cyan
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
