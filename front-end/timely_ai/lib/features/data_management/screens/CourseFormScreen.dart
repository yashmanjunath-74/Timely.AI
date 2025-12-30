import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timely_ai/features/data_management/controller/timetable_controller.dart';
import 'package:timely_ai/models/CourseModel.dart';
import 'package:timely_ai/shared/widgets/glass_card.dart';
import 'package:timely_ai/shared/widgets/saas_scaffold.dart';

class CourseFormScreen extends ConsumerStatefulWidget {
  final Course? initialCourse;

  const CourseFormScreen({super.key, this.initialCourse});

  @override
  ConsumerState<CourseFormScreen> createState() => _CourseFormScreenState();
}

class _CourseFormScreenState extends ConsumerState<CourseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _idController;
  late TextEditingController _lectureHoursController;
  late TextEditingController _labHoursController;
  late TextEditingController _equipmentController;
  late TextEditingController _creditsController;
  late TextEditingController _ltpController;
  late List<String> _selectedInstructorIds;
  late List<String> _equipment;
  late String _selectedLabType;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialCourse?.name ?? '',
    );
    _idController = TextEditingController(text: widget.initialCourse?.id ?? '');
    _lectureHoursController = TextEditingController(
      text: widget.initialCourse?.lectureHours.toString() ?? '3',
    );
    _labHoursController = TextEditingController(
      text: widget.initialCourse?.labHours.toString() ?? '0',
    );
    _labHoursController.addListener(() {
      setState(() {});
    });
    _creditsController = TextEditingController(
      text: widget.initialCourse?.credits.toString() ?? '4',
    );
    _ltpController = TextEditingController(
      text: widget.initialCourse?.ltp ?? '3-0-2',
    );
    _selectedLabType = widget.initialCourse?.labType ?? 'Computer Lab';
    _equipmentController = TextEditingController();
    _selectedInstructorIds = List<String>.from(
      widget.initialCourse?.qualifiedInstructors ?? [],
    );
    _equipment = List<String>.from(widget.initialCourse?.equipment ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _lectureHoursController.dispose();
    _labHoursController.dispose();
    _creditsController.dispose();
    _ltpController.dispose();
    _equipmentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      if (_selectedInstructorIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one instructor'),
          ),
        );
        return;
      }

      final course = Course(
        id: _idController.text.trim(),
        name: _nameController.text,
        lectureHours: int.parse(_lectureHoursController.text),
        labHours: int.parse(_labHoursController.text),
        qualifiedInstructors: _selectedInstructorIds,
        equipment: _equipment,
        credits: int.parse(_creditsController.text),
        ltp: _ltpController.text,
        labType: _selectedLabType,
      );
      Navigator.of(context).pop(course);
    }
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

  @override
  Widget build(BuildContext context) {
    final allInstructors = ref.watch(homeControllerProvider).instructors;

    return SaaSScaffold(
      title: widget.initialCourse == null ? 'Add New Course' : 'Edit Course',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Enter course details and assign qualified instructors',
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
                  _buildLabel('Course Name *'),
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      'Introduction to Computer Science',
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter a name' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildLabel('Course ID *'),
                  TextFormField(
                    controller: _idController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('CS101'),
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter an ID' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Lecture Hours *'),
                            TextFormField(
                              controller: _lectureHoursController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('3'),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) =>
                                  value!.isEmpty ? 'Required' : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Lab Hours *'),
                            TextFormField(
                              controller: _labHoursController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('0'),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) =>
                                  value!.isEmpty ? 'Required' : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (int.tryParse(_labHoursController.text) != null &&
                      int.parse(_labHoursController.text) > 0) ...[
                    _buildLabel('Lab Type *'),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedLabType,
                      dropdownColor: const Color(0xFF1A1A1A),
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('Select Lab Type'),
                      items: ['Computer Lab', 'Hardware Lab'].map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedLabType = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Credits'),
                            TextFormField(
                              controller: _creditsController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('4'),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) =>
                                  value!.isEmpty ? 'Required' : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('L-T-P'),
                            TextFormField(
                              controller: _ltpController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration('3-0-2'),
                              validator: (value) =>
                                  value!.isEmpty ? 'Required' : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Instructors Card
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Qualified Instructors *'),
                  const Text(
                    'Select instructors who can teach this course',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (allInstructors.isEmpty)
                    const Text(
                      'No instructors available. Please add instructors first.',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ...allInstructors.map((instructor) {
                    return CheckboxListTile(
                      title: Text(
                        instructor.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      value: _selectedInstructorIds.contains(instructor.id),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFF7F00FF), // Neon Violet
                      checkColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedInstructorIds.add(instructor.id);
                          } else {
                            _selectedInstructorIds.remove(instructor.id);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Equipment Card
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Required Equipment'),
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
                    'Save Course',
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
        borderSide: const BorderSide(color: Color(0xFF7F00FF)), // Neon Violet
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
