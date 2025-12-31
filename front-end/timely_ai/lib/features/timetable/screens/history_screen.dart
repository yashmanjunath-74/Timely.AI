import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timely_ai/features/data_management/repository/timetable_repository.dart';
import 'package:timely_ai/features/timetable/screens/timetable_view_screen.dart';
import 'package:timely_ai/shared/widgets/saas_scaffold.dart';
import 'package:timely_ai/shared/widgets/glass_card.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<Map<String, dynamic>> _savedTimetables = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final timetables = await ref
        .read(timetableRepositoryProvider)
        .getSavedTimetables();
    if (mounted) {
      setState(() {
        _savedTimetables = timetables.reversed.toList(); // Show newest first
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTimetable(String id) async {
    await ref.read(timetableRepositoryProvider).deleteTimetable(id);
    _loadHistory();
  }

  void _openTimetable(String id) async {
    setState(() => _isLoading = true);
    try {
      final schedule = await ref
          .read(timetableRepositoryProvider)
          .loadTimetable(id);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TimetableViewScreen(schedule: schedule),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SaaSScaffold(
      title: 'Timetable History',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedTimetables.isEmpty
          ? const Center(
              child: Text(
                'No saved timetables found.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _savedTimetables.length,
              itemBuilder: (context, index) {
                final item = _savedTimetables[index];
                return Dismissible(
                  key: Key(item['id']),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _deleteTimetable(item['id']),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red.withOpacity(0.8),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: GestureDetector(
                    onTap: () => _openTimetable(item['id']),
                    child: GlassCard(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.calendar_today,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'] ?? 'Unnamed',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Created: ${item['date']}',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.white54,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
