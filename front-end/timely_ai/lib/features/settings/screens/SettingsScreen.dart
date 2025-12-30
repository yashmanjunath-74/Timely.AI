import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timely_ai/features/data_management/controller/timetable_controller.dart';
import 'package:timely_ai/shared/widgets/glass_card.dart';
import 'package:timely_ai/shared/widgets/saas_scaffold.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // State variables
  double _gapPriority = 2.0; // 0: Low, 1: Medium, 2: High
  bool _fairWorkload = false;
  bool _guaranteedLunch = false;
  final List<String> _preferredMorningCourses = [];

  @override
  void initState() {
    super.initState();
    // Initialize state from controller (mocked for now, will connect later)
    final settings = ref.read(homeControllerProvider).settings;
    _gapPriority = settings['gapPriority'] ?? 2.0;
    _fairWorkload = settings['fairWorkload'] ?? false;
    _guaranteedLunch = settings['guaranteedLunch'] ?? false;
    _preferredMorningCourses.addAll(
      List<String>.from(settings['preferredMorningCourses'] ?? []),
    );
  }

  void _saveSettings() {
    ref.read(homeControllerProvider.notifier).updateSettings({
      'gapPriority': _gapPriority,
      'fairWorkload': _fairWorkload,
      'guaranteedLunch': _guaranteedLunch,
      'preferredMorningCourses': _preferredMorningCourses,
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final allCourses = ref.watch(homeControllerProvider).courses;

    return SaaSScaffold(
      title: 'Settings & Preferences',
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Configure how the timetable generation algorithm should prioritize constraints',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
          ),
          const SizedBox(height: 24),

          // Minimize Gaps
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Minimize Gaps for Students',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Reduce idle time between classes',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        _getPriorityLabel(_gapPriority),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF00C6FF), // Neon Cyan
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: const Color(0xFF00C6FF).withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _gapPriority,
                    min: 0,
                    max: 2,
                    divisions: 2,
                    onChanged: (value) {
                      setState(() {
                        _gapPriority = value;
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'Low',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      Text(
                        'Medium',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      Text(
                        'High',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Fair Instructor Workload
          GlassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fair Instructor Workload',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Distribute teaching hours evenly',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
                Switch(
                  value: _fairWorkload,
                  activeThumbColor: const Color(0xFF7F00FF), // Neon Violet
                  activeTrackColor: const Color(0xFF7F00FF).withOpacity(0.5),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  onChanged: (value) {
                    setState(() {
                      _fairWorkload = value;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Preferred Morning Classes
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Preferred Morning Classes',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select courses for morning slots',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (allCourses.isEmpty)
                  const Text(
                    'No courses available',
                    style: TextStyle(color: Colors.white54),
                  ),
                ...allCourses.map((course) {
                  return CheckboxListTile(
                    title: Text(
                      course.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      '(${course.id})',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _preferredMorningCourses.contains(course.id),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFF00C6FF), // Neon Cyan
                    checkColor: Colors.black,
                    side: const BorderSide(color: Colors.white54),
                    dense: true,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _preferredMorningCourses.add(course.id);
                        } else {
                          _preferredMorningCourses.remove(course.id);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Guaranteed Lunch Break
          GlassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guaranteed Lunch Break',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ensure 1 hour free between 12:00-14:00',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _guaranteedLunch,
                  activeThumbColor: const Color(0xFFFF4E50), // Neon Red
                  activeTrackColor: const Color(0xFFFF4E50).withOpacity(0.5),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  onChanged: (value) {
                    setState(() {
                      _guaranteedLunch = value;
                    });
                  },
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
                onPressed: _saveSettings,
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
                  'Save Settings',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getPriorityLabel(double value) {
    if (value == 0.0) return 'Low Priority';
    if (value == 1.0) return 'Medium Priority';
    return 'High Priority';
  }
}
