import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timely_ai/features/data_management/controller/timetable_controller.dart';
import 'package:timely_ai/models/StudentGroupModel.dart';
import 'package:timely_ai/shared/widgets/glass_card.dart';
import 'package:timely_ai/shared/widgets/saas_scaffold.dart';

class StudentGroupFormScreen extends ConsumerStatefulWidget {
  final StudentGroup? initialStudentGroup;

  const StudentGroupFormScreen({super.key, this.initialStudentGroup});

  @override
  ConsumerState<StudentGroupFormScreen> createState() =>
      _StudentGroupFormScreenState();
}

class _StudentGroupFormScreenState
    extends ConsumerState<StudentGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _idController;
  late TextEditingController _sizeController;
  late List<String> _selectedCourseIds;
  late Map<String, String> _instructorPreferences;
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
    _idController = TextEditingController(
      text: widget.initialStudentGroup?.id ?? '',
    );
    _sizeController = TextEditingController(
      text: (widget.initialStudentGroup?.size)?.toString() ?? '',
    );
    _selectedCourseIds = List<String>.from(
      widget.initialStudentGroup?.enrolledCourses ?? [],
    );
    _instructorPreferences = Map<String, String>.from(
      widget.initialStudentGroup?.instructorPreferences ?? {},
    );

    // Initialize availability
    if (widget.initialStudentGroup != null &&
        widget.initialStudentGroup!.availability.isNotEmpty) {
      _availability = Map<String, List<int>>.from(
        widget.initialStudentGroup!.availability.map(
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
    _sizeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      if (_selectedCourseIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one enrolled course'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final studentGroup = StudentGroup(
        id: _idController.text.trim(),
        size: int.parse(_sizeController.text),
        enrolledCourses: _selectedCourseIds,
        instructorPreferences: _instructorPreferences,
        availability: _availability,
      );
      Navigator.of(context).pop(studentGroup);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allCourses = ref.watch(homeControllerProvider).courses;
    final allInstructors = ref.watch(homeControllerProvider).instructors;

    return SaaSScaffold(
      title: widget.initialStudentGroup == null
          ? 'Add New Student Group'
          : 'Edit Student Group',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Enter group details and select enrolled courses',
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
                  _buildLabel('Group ID / Name *'),
                  TextFormField(
                    controller: _idController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('CS-Year1-A'),
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter an ID' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Group Size *'),
                  TextFormField(
                    controller: _sizeController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('30'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a size' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Courses Card
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Enrolled Courses *'),
                  const Text(
                    'Select all courses this group is enrolled in',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (allCourses.isEmpty)
                    const Text(
                      'No courses available. Please add courses first.',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ...allCourses.map((course) {
                    final isSelected = _selectedCourseIds.contains(course.id);
                    return Column(
                      children: [
                        CheckboxListTile(
                          title: Text(
                            course.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            '(${course.id})',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          value: isSelected,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: Colors.tealAccent, // Neon Teal
                          checkColor: Colors.black,
                          side: const BorderSide(color: Colors.white54),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _selectedCourseIds.add(course.id);
                              } else {
                                _selectedCourseIds.remove(course.id);
                                _instructorPreferences.remove(course.id);
                              }
                            });
                          },
                        ),
                        if (isSelected)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 40.0,
                              bottom: 16.0,
                              right: 16.0,
                            ),
                            child: DropdownButtonFormField<String>(
                              initialValue: _instructorPreferences[course.id],
                              decoration: _inputDecoration(
                                'Preferred Instructor (Optional)',
                              ),
                              dropdownColor: const Color(0xFF1E1E1E),
                              style: const TextStyle(color: Colors.white),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('No Preference (Any Qualified)'),
                                ),
                                ...allInstructors
                                    .where(
                                      (inst) => course.qualifiedInstructors
                                          .contains(inst.id),
                                    )
                                    .map((inst) {
                                      return DropdownMenuItem(
                                        value: inst.id,
                                        child: Text(inst.name),
                                      );
                                    }),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  if (value == null) {
                                    _instructorPreferences.remove(course.id);
                                  } else {
                                    _instructorPreferences[course.id] = value;
                                  }
                                });
                              },
                            ),
                          ),
                      ],
                    );
                  }),
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
                    'Group Availability',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Click on time slots to mark when the student group is unavailable',
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
                    'Save Group',
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
        borderSide: const BorderSide(color: Colors.tealAccent), // Neon Teal
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
