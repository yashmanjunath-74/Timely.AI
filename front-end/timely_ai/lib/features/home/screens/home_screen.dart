import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timely_ai/features/data_management/controller/timetable_controller.dart';
import 'package:timely_ai/features/data_management/repository/timetable_repository.dart';
import 'package:timely_ai/features/data_management/screens/ManageCoursesScreen.dart';
import 'package:timely_ai/features/data_management/screens/ManageInstructorsScreen.dart';
import 'package:timely_ai/features/data_management/screens/ManageRoomsScreen.dart';
import 'package:timely_ai/features/data_management/screens/ManageStudentGroupsScreen.dart';
import 'package:timely_ai/features/settings/screens/SettingsScreen.dart';
import 'package:timely_ai/features/timetable/screens/timetable_view_screen.dart';

import 'package:timely_ai/shared/widgets/saas_scaffold.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // ... (keep existing methods: _generateTimetable, _performGeneration, _navigateTo) ...
  // Handles calling the backend to generate the timetable.
  void _generateTimetable(BuildContext context, WidgetRef ref) {
    final homeState = ref.read(homeControllerProvider);
    final allCourses = homeState.courses;
    final allGroups = homeState.studentGroups;

    if (allCourses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one course.')),
      );
      return;
    }

    // Collect all enrolled course IDs
    final enrolledCourseIds = <String>{};
    for (final group in allGroups) {
      enrolledCourseIds.addAll(group.enrolledCourses);
    }

    // Find unassigned courses
    final unassignedCourses = <String>[];
    for (final course in allCourses) {
      if (!enrolledCourseIds.contains(course.id)) {
        unassignedCourses.add(course.name);
      }
    }

    if (unassignedCourses.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unassigned Courses Warning'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The following courses are not assigned to any Student Group. They will appear as "No Group Assigned" in the timetable.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                ...unassignedCourses.map(
                  (c) => Text(
                    '• $c',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Do you want to proceed?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _performGeneration(context, ref);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              child: const Text(
                'Generate Anyway',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } else {
      _performGeneration(context, ref);
    }
  }

  void _performGeneration(BuildContext context, WidgetRef ref) async {
    // Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await ref
          .read(timetableRepositoryProvider)
          .generateTimetable();

      // --- FIX: Safely cast the schedule list ---
      // The JSON decoder gives us a List<dynamic>, but our UI needs a List<Map<String, dynamic>>.
      // We create a new, correctly typed list to prevent the TypeError.
      final List<dynamic> dynamicSchedule = result['schedule'];
      final List<Map<String, dynamic>> typedSchedule =
          List<Map<String, dynamic>>.from(dynamicSchedule);

      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TimetableViewScreen(schedule: typedSchedule),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  // --- Navigation helpers ---
  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeState = ref.watch(homeControllerProvider);

    // Calculate stats
    final int totalEntities =
        homeState.instructors.length +
        homeState.courses.length +
        homeState.rooms.length +
        homeState.studentGroups.length;

    return SaaSScaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width:
                        50, // Slightly increased size since padding/box is gone
                    height: 50,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MCE Timely.AI',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white, // White text
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'AI-Powered MCE Class Timetable Generator',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[400], // Light grey text
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Stats Row
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.check_circle_outline,
                    label: 'Status',
                    value: 'Ready',
                    iconColor: Colors.greenAccent, // Neon Green
                    bgColor: Colors.green.withOpacity(0.2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    icon: Icons.data_usage,
                    label: 'Entities',
                    value: totalEntities.toString(),
                    iconColor: Colors.purpleAccent, // Neon Purple
                    bgColor: Colors.purple.withOpacity(0.2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    icon: Icons.book_outlined,
                    label: 'Courses',
                    value: homeState.courses.length.toString(),
                    iconColor: Colors.blueAccent, // Neon Blue
                    bgColor: Colors.blue.withOpacity(0.2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    icon: Icons.groups_outlined,
                    label: 'Groups',
                    value: homeState.studentGroups.length.toString(),
                    iconColor: Colors.orangeAccent, // Neon Orange
                    bgColor: Colors.orange.withOpacity(0.2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Section Title
            const Text(
              'Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white, // White text
              ),
            ),
            const SizedBox(height: 16),

            // Management Grid
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 3.5,
                  children: [
                    _ManagementCard(
                      title: 'Instructors',
                      subtitle: '${homeState.instructors.length} Registered',
                      icon: Icons.person_outline,
                      gradientColors: [Colors.blue[700]!, Colors.blue[900]!],
                      onTap: () =>
                          _navigateTo(context, const ManageInstructorsScreen()),
                    ),
                    _ManagementCard(
                      title: 'Courses',
                      subtitle: '${homeState.courses.length} Available',
                      icon: Icons.library_books_outlined,
                      gradientColors: [
                        Colors.purple[700]!,
                        Colors.purple[900]!,
                      ],
                      onTap: () =>
                          _navigateTo(context, const ManageCoursesScreen()),
                    ),
                    _ManagementCard(
                      title: 'Rooms',
                      subtitle: '${homeState.rooms.length} Configured',
                      icon: Icons.meeting_room_outlined,
                      gradientColors: [
                        Colors.orange[700]!,
                        Colors.orange[900]!,
                      ],
                      onTap: () =>
                          _navigateTo(context, const ManageRoomsScreen()),
                    ),
                    _ManagementCard(
                      title: 'Student Groups',
                      subtitle: '${homeState.studentGroups.length} Active',
                      icon: Icons.groups_outlined,
                      gradientColors: [Colors.teal[700]!, Colors.teal[900]!],
                      onTap: () => _navigateTo(
                        context,
                        const ManageStudentGroupsScreen(),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // Settings Card
            _ManagementCard(
              title: 'Settings & Preferences',
              subtitle: 'Configure generation rules',
              icon: Icons.settings_outlined,
              gradientColors: [Colors.grey[800]!, Colors.black],
              onTap: () => _navigateTo(context, const SettingsScreen()),
            ),

            const SizedBox(height: 48),

            // Generate Button
            Center(
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF334155)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _generateTimetable(context, ref),
                  icon: const Icon(Icons.auto_awesome, color: Colors.white),
                  label: const Text(
                    'Generate Timetable',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color bgColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.6), // Dark Glass
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Decorative Vector (Background)
            Positioned(
              right: -10,
              bottom: -10,
              child: Transform.rotate(
                angle: -0.2,
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      colors: [
                        iconColor.withOpacity(0.2),
                        iconColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.srcIn,
                  child: Icon(
                    icon,
                    size: 80,
                    color: Colors.white, // Color is handled by ShaderMask
                  ),
                ),
              ),
            ),
            // Main Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[400], // Light Grey
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white, // White
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _ManagementCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.6), // Dark Glass
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Decorative Vector (Background)
              Positioned(
                right: -20,
                bottom: -20,
                child: Transform.rotate(
                  angle: -0.2,
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        colors: [
                          gradientColors.first.withOpacity(0.2),
                          gradientColors.last.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.srcIn,
                    child: Icon(
                      icon,
                      size: 140,
                      color: Colors.white, // Color is handled by ShaderMask
                    ),
                  ),
                ),
              ),
              // Main Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: gradientColors.first.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white, // White
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                            ), // Light Grey
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
