import 'package:flutter/material.dart';
import 'package:timely_ai/shared/widgets/glass_card.dart';
import 'package:timely_ai/shared/widgets/saas_scaffold.dart';
import 'package:timely_ai/models/CourseModel.dart';
import 'package:timely_ai/models/RoomModel.dart';

class ManualEditTimetableScreen extends StatefulWidget {
  final List<Map<String, dynamic>> schedule;
  final List<Room> rooms;
  final List<Course> courses;

  const ManualEditTimetableScreen({
    super.key,
    required this.schedule,
    required this.rooms,
    required this.courses,
  });

  @override
  State<ManualEditTimetableScreen> createState() =>
      _ManualEditTimetableScreenState();
}

class _ManualEditTimetableScreenState extends State<ManualEditTimetableScreen> {
  late List<Map<String, dynamic>> _mutableSchedule;

  final List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  final List<String> _timeSlots = [
    '08:30 AM - 09:30 AM',
    '09:30 AM - 10:30 AM',
    '11:00 AM - 12:00 PM',
    '12:00 PM - 01:00 PM',
    '02:00 PM - 03:00 PM',
    '03:00 PM - 04:00 PM',
    '04:00 PM - 05:00 PM',
  ];

  List<String> _allGroups = [];
  Map<String, dynamic>? _selectedClassForSuggestion;

  @override
  void initState() {
    super.initState();
    // Deep copy to allow editing without mutating the original unless saved
    _mutableSchedule = List<Map<String, dynamic>>.from(
      widget.schedule.map((m) => Map<String, dynamic>.from(m)),
    );
    _extractGroups();
  }

  void _extractGroups() {
    final Set<String> uniqueGroups = {};
    for (var item in _mutableSchedule) {
      final groupStr = item['group'] as String;
      if (groupStr.contains(',')) {
        final parts = groupStr.split(',').map((e) => e.trim()).toList();
        uniqueGroups.addAll(parts);
      } else {
        uniqueGroups.add(groupStr);
      }
    }
    _allGroups = uniqueGroups.toList()..sort();
  }

  int _parseTime(String t) {
    try {
      final parts = t.split(' ');
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final isPM = parts.length > 1 && parts[1] == 'PM';
      if (isPM && hour != 12) hour += 12;
      if (!isPM && hour == 12) hour = 0;
      return hour * 60 + minute;
    } catch (e) {
      return 0;
    }
  }

  (int, int) _getRange(String ts) {
    final parts = ts.split(' - ');
    if (parts.length != 2) return (0, 0);
    return (_parseTime(parts[0]), _parseTime(parts[1]));
  }

  bool _areConsecutive(String ts1, String ts2) {
    final range1 = _getRange(ts1);
    final range2 = _getRange(ts2);
    if (range1.$1 == 0 && range1.$2 == 0) return false;
    if (range2.$1 == 0 && range2.$2 == 0) return false;
    if (range1.$1 < range2.$1) {
      final gap = range2.$1 - range1.$2;
      return gap < 60;
    } else {
      final gap = range1.$1 - range2.$2;
      return gap < 60;
    }
  }

  bool _areConsecutiveLabSlots(String ts1, String ts2) {
    final range1 = _getRange(ts1);
    final range2 = _getRange(ts2);
    if (range1.$1 == 0 && range1.$2 == 0) return false;
    if (range2.$1 == 0 && range2.$2 == 0) return false;
    if (range1.$1 < range2.$1) {
      return range2.$1 == range1.$2;
    } else {
      return range1.$1 == range2.$2;
    }
  }

  Map<String, dynamic>? _getPartnerLab(Map<String, dynamic> classInfo) {
    if (classInfo['type'] != 'lab') return null;
    
    final day = classInfo['day'];
    final instructor = classInfo['instructor'];
    final courseId = classInfo['courseId'];
    final group = classInfo['group'];
    final timeslot = classInfo['timeslot'];

    for (var other in _mutableSchedule) {
      if (other != classInfo &&
          other['type'] == 'lab' &&
          other['day'] == day &&
          other['instructor'] == instructor &&
          other['courseId'] == courseId &&
          other['group'] == group) {
        if (_areConsecutiveLabSlots(timeslot, other['timeslot'])) {
          return other;
        }
      }
    }
    return null;
  }

  bool _isAnyValidRoomAvailable(
    Map<String, dynamic> classInfo,
    String targetDay,
    String targetTime, {
    Map<String, dynamic>? ignoreClass,
  }) {
    final String courseId = classInfo['courseId'] ?? '';
    final String classType = classInfo['type'] ?? '';

    // Find course
    Course? course;
    for (final c in widget.courses) {
      if (c.id == courseId) {
        course = c;
        break;
      }
    }

    final requiredEquipment = course?.equipment ?? [];
    final String labType = course?.labType ?? 'Computer Lab';

    // Loop through all rooms to find if at least one is valid and unoccupied
    for (final room in widget.rooms) {
      // 1. Check Equipment: required equipment must be subset of room equipment
      bool hasAllEquipment = true;
      for (final req in requiredEquipment) {
        if (!room.equipment.contains(req)) {
          hasAllEquipment = false;
          break;
        }
      }
      if (!hasAllEquipment) continue;

      // 2. Check Room Type
      final rType = room.type.toLowerCase();
      bool isValidType = false;
      if (classType == 'lab') {
        if (labType == 'Hardware Lab') {
          if (rType.contains('hardware')) {
            isValidType = true;
          }
        } else { // Computer Lab
          if (rType.contains('computer')) {
            isValidType = true;
          } else if (rType.contains('lab') && !rType.contains('hardware')) {
            isValidType = true;
          }
        }
      } else { // Lecture
        final isLabRoom = rType.contains('lab') || rType.contains('computer');
        if (!isLabRoom) {
          isValidType = true;
        }
      }

      if (!isValidType) continue;

      // 3. Check Room Occupation: is this room occupied at the target slot?
      final roomOccupied = _mutableSchedule.any(
        (element) =>
            element['day'] == targetDay &&
            element['timeslot'] == targetTime &&
            element['room'] == room.id &&
            element != classInfo &&
            (ignoreClass == null || element != ignoreClass),
      );

      if (!roomOccupied) {
        return true; // Found at least one valid and free room!
      }
    }

    return false; // No valid rooms available
  }

  bool _checkSingleSlotValid(
    Map<String, dynamic> classInfo,
    String targetDay,
    String targetTime,
    String targetGroup, {
    Map<String, dynamic>? ignoreClass,
  }) {
    // 1. Group Clash: is there another class in this target slot for this group?
    final targetItems = _mutableSchedule.where(
      (e) =>
          e['day'] == targetDay &&
          e['timeslot'] == targetTime &&
          e['group'].toString().contains(targetGroup) &&
          e != classInfo &&
          (ignoreClass == null || e != ignoreClass),
    );
    if (targetItems.isNotEmpty) {
      return false; // Slot occupied for this group
    }

    // 2. Instructor Clash: is the instructor teaching elsewhere at this time?
    final String instructor = classInfo['instructor'];
    final instructorClashes = _mutableSchedule.where(
      (element) =>
          element['day'] == targetDay &&
          element['timeslot'] == targetTime &&
          element['instructor'] == instructor &&
          element != classInfo &&
          (ignoreClass == null || element != ignoreClass),
    );
    if (instructorClashes.isNotEmpty) {
      return false; // Instructor busy
    }

    // 3. Room Clash: is there any valid, unoccupied room of the required type available?
    if (!_isAnyValidRoomAvailable(classInfo, targetDay, targetTime, ignoreClass: ignoreClass)) {
      return false; // No valid room of the required type is available!
    }

    // 4. Instructor Consecutive Class Clash (Faculty Break Constraint)
    for (var otherClass in _mutableSchedule) {
      if (otherClass != classInfo &&
          (ignoreClass == null || otherClass != ignoreClass) &&
          otherClass['day'] == targetDay &&
          otherClass['instructor'] == instructor) {
        
        final otherTime = otherClass['timeslot'] as String;
        if (_areConsecutive(targetTime, otherTime)) {
          final isPairedLab = classInfo['type'] == 'lab' &&
              otherClass['type'] == 'lab' &&
              classInfo['courseId'] == otherClass['courseId'] &&
              classInfo['group'] == otherClass['group'];
          
          if (!isPairedLab) {
            return false; // Instructor consecutive clash!
          }
        }
      }
    }

    return true; // Valid slot!
  }

  bool _isValidMoveSuggestion(
    Map<String, dynamic> classInfo,
    String targetDay,
    String targetTime,
    String targetGroup,
  ) {
    final partner = _getPartnerLab(classInfo);
    if (partner != null) {
      final indexCurrent = _timeSlots.indexOf(classInfo['timeslot']);
      final indexPartner = _timeSlots.indexOf(partner['timeslot']);
      final indexTarget = _timeSlots.indexOf(targetTime);
      
      if (indexCurrent == -1 || indexPartner == -1 || indexTarget == -1) {
        return false;
      }
      
      final int targetPartnerIndex = indexTarget + (indexPartner - indexCurrent);
      if (targetPartnerIndex < 0 || targetPartnerIndex >= _timeSlots.length) {
        return false;
      }
      
      final partnerTargetTime = _timeSlots[targetPartnerIndex];
      
      // Ensure the target slots are consecutive lab slots
      if (!_areConsecutiveLabSlots(targetTime, partnerTargetTime)) {
        return false;
      }

      // Check validation for both parts of the lab
      return _checkSingleSlotValid(classInfo, targetDay, targetTime, targetGroup, ignoreClass: partner) &&
             _checkSingleSlotValid(partner, targetDay, partnerTargetTime, targetGroup, ignoreClass: classInfo);
    } else {
      return _checkSingleSlotValid(classInfo, targetDay, targetTime, targetGroup);
    }
  }

  bool _hasSingleSlotClash(
    Map<String, dynamic> droppedItem,
    String targetDay,
    String targetTime,
    String targetGroup, {
    Map<String, dynamic>? ignoreClass,
  }) {
    // 1. Group Clash
    final targetItems = _mutableSchedule.where(
      (e) =>
          e['day'] == targetDay &&
          e['timeslot'] == targetTime &&
          e['group'].toString().contains(targetGroup) &&
          e != droppedItem &&
          (ignoreClass == null || e != ignoreClass),
    );
    if (targetItems.isNotEmpty) {
      _showWarning('Slot $targetTime is already occupied by another class for this group!');
      return true;
    }

    // 2. Instructor Clash
    final String instructor = droppedItem['instructor'];
    final instructorClashes = _mutableSchedule.where(
      (element) =>
          element['day'] == targetDay &&
          element['timeslot'] == targetTime &&
          element['instructor'] == instructor &&
          element != droppedItem &&
          (ignoreClass == null || element != ignoreClass),
    );
    if (instructorClashes.isNotEmpty) {
      _showWarning('Instructor $instructor is already teaching at $targetTime!');
      return true;
    }

    // 3. Room Clash: check if the selected room is occupied at target slot
    final String room = droppedItem['room'];
    final roomClashes = _mutableSchedule.where(
      (element) =>
          element['day'] == targetDay &&
          element['timeslot'] == targetTime &&
          element['room'] == room &&
          element != droppedItem &&
          (ignoreClass == null || element != ignoreClass),
    );
    if (roomClashes.isNotEmpty) {
      _showWarning('Room $room is already occupied at $targetTime!');
      return true;
    }

    // 3.1 Room Type check (final validation)
    final String courseId = droppedItem['courseId'] ?? '';
    Course? course;
    for (final c in widget.courses) {
      if (c.id == courseId) {
        course = c;
        break;
      }
    }
    final String classType = droppedItem['type'] ?? '';
    final String labType = course?.labType ?? 'Computer Lab';

    Room? targetRoomObj;
    for (final r in widget.rooms) {
      if (r.id == room) {
        targetRoomObj = r;
        break;
      }
    }

    if (targetRoomObj != null) {
      // Check equipment
      final requiredEquipment = course?.equipment ?? [];
      bool hasAllEquipment = true;
      for (final req in requiredEquipment) {
        if (!targetRoomObj.equipment.contains(req)) {
          hasAllEquipment = false;
          break;
        }
      }
      if (!hasAllEquipment) {
        _showWarning('Room $room does not have all required equipment for this class!');
        return true;
      }

      // Check type
      final rType = targetRoomObj.type.toLowerCase();
      bool isValidType = false;
      if (classType == 'lab') {
        if (labType == 'Hardware Lab') {
          if (rType.contains('hardware')) {
            isValidType = true;
          }
        } else {
          if (rType.contains('computer')) {
            isValidType = true;
          } else if (rType.contains('lab') && !rType.contains('hardware')) {
            isValidType = true;
          }
        }
      } else {
        final isLabRoom = rType.contains('lab') || rType.contains('computer');
        if (!isLabRoom) {
          isValidType = true;
        }
      }
      if (!isValidType) {
        _showWarning('Room $room is not of the correct type for this class!');
        return true;
      }
    }

    // 4. Instructor Consecutive Class Clash (Faculty Break Constraint)
    for (var otherClass in _mutableSchedule) {
      if (otherClass != droppedItem &&
          (ignoreClass == null || otherClass != ignoreClass) &&
          otherClass['day'] == targetDay &&
          otherClass['instructor'] == instructor) {
        
        final otherTime = otherClass['timeslot'] as String;
        if (_areConsecutive(targetTime, otherTime)) {
          final isPairedLab = droppedItem['type'] == 'lab' &&
              otherClass['type'] == 'lab' &&
              droppedItem['courseId'] == otherClass['courseId'] &&
              droppedItem['group'] == otherClass['group'];
          
          if (!isPairedLab) {
            _showWarning('Instructor $instructor would have consecutive classes without a break between $targetTime and $otherTime!');
            return true;
          }
        }
      }
    }

    return false;
  }

  bool _checkForClash(
    Map<String, dynamic> droppedItem,
    String targetDay,
    String targetTime,
    String targetGroup,
    Map<String, dynamic>? currentItemInTarget,
  ) {
    final partner = _getPartnerLab(droppedItem);
    if (partner != null) {
      final indexCurrent = _timeSlots.indexOf(droppedItem['timeslot']);
      final indexPartner = _timeSlots.indexOf(partner['timeslot']);
      final indexTarget = _timeSlots.indexOf(targetTime);
      
      if (indexCurrent == -1 || indexPartner == -1 || indexTarget == -1) {
        _showWarning('Invalid timeslots involved!');
        return true;
      }
      
      final int targetPartnerIndex = indexTarget + (indexPartner - indexCurrent);
      if (targetPartnerIndex < 0 || targetPartnerIndex >= _timeSlots.length) {
        _showWarning('Partner lab slot would fall outside schedule hours!');
        return true;
      }
      
      final partnerTargetTime = _timeSlots[targetPartnerIndex];
      
      if (!_areConsecutiveLabSlots(targetTime, partnerTargetTime)) {
        _showWarning('Partner lab slots must be consecutive!');
        return true;
      }

      if (_hasSingleSlotClash(droppedItem, targetDay, targetTime, targetGroup, ignoreClass: partner)) {
        return true;
      }
      
      if (_hasSingleSlotClash(partner, targetDay, partnerTargetTime, targetGroup, ignoreClass: droppedItem)) {
        return true;
      }
      
      return false;
    } else {
      return _hasSingleSlotClash(droppedItem, targetDay, targetTime, targetGroup);
    }
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onAcceptDrop(
    Map<String, dynamic> droppedItem,
    String targetDay,
    String targetTime,
    String targetGroup,
  ) async {
    final currentRoom = droppedItem['room'] as String;
    
    // Find partner lab if exists
    final partner = _getPartnerLab(droppedItem);
    String? partnerOriginalRoom;
    String? partnerTargetTime;

    if (partner != null) {
      partnerOriginalRoom = partner['room'];
      final indexCurrent = _timeSlots.indexOf(droppedItem['timeslot']);
      final indexPartner = _timeSlots.indexOf(partner['timeslot']);
      final indexTarget = _timeSlots.indexOf(targetTime);
      final int targetPartnerIndex = indexTarget + (indexPartner - indexCurrent);
      partnerTargetTime = _timeSlots[targetPartnerIndex];
    }

    // Filter available rooms of matching type/equipment at the target timeslot(s)
    final String courseId = droppedItem['courseId'] ?? '';
    final String classType = droppedItem['type'] ?? '';

    // Find course
    Course? course;
    for (final c in widget.courses) {
      if (c.id == courseId) {
        course = c;
        break;
      }
    }

    final requiredEquipment = course?.equipment ?? [];
    final String labType = course?.labType ?? 'Computer Lab';

    final List<String> displayRooms = [];

    for (final room in widget.rooms) {
      // 1. Check Equipment
      bool hasAllEquipment = true;
      for (final req in requiredEquipment) {
        if (!room.equipment.contains(req)) {
          hasAllEquipment = false;
          break;
        }
      }
      if (!hasAllEquipment) continue;

      // 2. Check Room Type
      final rType = room.type.toLowerCase();
      bool isValidType = false;
      if (classType == 'lab') {
        if (labType == 'Hardware Lab') {
          if (rType.contains('hardware')) {
            isValidType = true;
          }
        } else {
          if (rType.contains('computer')) {
            isValidType = true;
          } else if (rType.contains('lab') && !rType.contains('hardware')) {
            isValidType = true;
          }
        }
      } else { // Lecture
        final isLabRoom = rType.contains('lab') || rType.contains('computer');
        if (!isLabRoom) {
          isValidType = true;
        }
      }

      if (!isValidType) continue;

      // 3. Check Room Occupation at targetTime
      final roomOccupied = _mutableSchedule.any(
        (element) =>
            element['day'] == targetDay &&
            element['timeslot'] == targetTime &&
            element['room'] == room.id &&
            element != droppedItem &&
            (partner == null || element != partner),
      );

      // 4. Check Room Occupation at partnerTargetTime (if partner exists)
      bool partnerRoomOccupied = false;
      if (partner != null && partnerTargetTime != null) {
        partnerRoomOccupied = _mutableSchedule.any(
          (element) =>
              element['day'] == targetDay &&
              element['timeslot'] == partnerTargetTime &&
              element['room'] == room.id &&
              element != droppedItem &&
              element != partner,
        );
      }

      if (!roomOccupied && !partnerRoomOccupied) {
        displayRooms.add(room.id);
      }
    }

    // Fallback: make sure the current room is included if displayRooms is empty
    if (currentRoom.isNotEmpty && !displayRooms.contains(currentRoom)) {
      displayRooms.add(currentRoom);
    }
    displayRooms.sort();

    final String? selectedRoom = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        String tempSelectedRoom = displayRooms.contains(currentRoom) ? currentRoom : (displayRooms.isNotEmpty ? displayRooms.first : '');
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24),
          ),
          title: const Text(
            'Select Classroom',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Course: ${droppedItem['course']}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Instructor: ${droppedItem['instructor']}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text(
                'Classroom:',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: const Color(0xFF2C2C2C),
                ),
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    return DropdownButtonFormField<String>(
                      value: tempSelectedRoom.isEmpty ? null : tempSelectedRoom,
                      dropdownColor: const Color(0xFF2C2C2C),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF2C2C2C),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: displayRooms.map((room) {
                        return DropdownMenuItem<String>(
                          value: room,
                          child: Text(room),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            tempSelectedRoom = val;
                          });
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, tempSelectedRoom),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C6FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Move & Assign',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (selectedRoom == null || selectedRoom.isEmpty) {
      return; // Canceled
    }

    final originalRoom = droppedItem['room'];
    
    // Set rooms temporarily for clash checking
    droppedItem['room'] = selectedRoom;
    if (partner != null) {
      partner['room'] = selectedRoom;
    }

    if (_checkForClash(
      droppedItem,
      targetDay,
      targetTime,
      targetGroup,
      null,
    )) {
      // Revert room on clash
      droppedItem['room'] = originalRoom;
      if (partner != null) {
        partner['room'] = partnerOriginalRoom;
      }
      return; // Clash detected, do nothing.
    }

    setState(() {
      droppedItem['day'] = targetDay;
      droppedItem['timeslot'] = targetTime;
      droppedItem['group'] = targetGroup;

      if (partner != null && partnerTargetTime != null) {
        partner['day'] = targetDay;
        partner['timeslot'] = partnerTargetTime;
        partner['group'] = targetGroup;
      }
      _selectedClassForSuggestion = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SaaSScaffold(
      title: 'Edit Timetables',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: ElevatedButton.icon(
            onPressed: () {
              // Passing back the updated schedule
              Navigator.pop(context, _mutableSchedule);
            },
            icon: const Icon(Icons.check, size: 18, color: Colors.black),
            label: const Text(
              'Done',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate how many grids we can fit per row
          int crossAxisCount = constraints.maxWidth > 1200 ? 2 : 1;

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 1.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _allGroups.length,
            itemBuilder: (context, index) {
              return _buildGroupTimetable(_allGroups[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildGroupTimetable(String group) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group: $group',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time Column
                    Column(
                      children: [
                        const SizedBox(height: 40), // Header offset
                        ..._timeSlots.map(
                          (time) => Container(
                            height: 100,
                            width: 120,
                            padding: const EdgeInsets.only(right: 8, top: 8),
                            child: Text(
                              time,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Days Columns
                    ..._days.map((day) {
                      return Container(
                        width: 150,
                        margin: const EdgeInsets.only(right: 8),
                        child: Column(
                          children: [
                            // Day Header
                            Container(
                              height: 30,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Text(
                                day,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Slots
                            ..._timeSlots.map((time) {
                              final items = _mutableSchedule
                                  .where(
                                    (e) =>
                                        e['day'] == day &&
                                        e['timeslot'] == time &&
                                        e['group'].toString().contains(group),
                                  )
                                  .toList();

                              final classInfo = items.isNotEmpty
                                  ? items.first
                                  : null;

                              final isSuggested = _selectedClassForSuggestion != null &&
                                  _selectedClassForSuggestion!['group']
                                      .toString()
                                      .contains(group) &&
                                  _isValidMoveSuggestion(
                                    _selectedClassForSuggestion!,
                                    day,
                                    time,
                                    group,
                                  );

                              return DragTarget<Map<String, dynamic>>(
                                onWillAcceptWithDetails: (details) => true,
                                onAcceptWithDetails: (details) {
                                  _onAcceptDrop(details.data, day, time, group);
                                },
                                builder:
                                    (context, candidateData, rejectedData) {
                                      final isHovering =
                                          candidateData.isNotEmpty;

                                      if (classInfo == null) {
                                        return GestureDetector(
                                          onTap: isSuggested
                                              ? () {
                                                  _onAcceptDrop(
                                                    _selectedClassForSuggestion!,
                                                    day,
                                                    time,
                                                    group,
                                                  );
                                                }
                                              : null,
                                          child: Container(
                                            height: 100,
                                            margin: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isHovering
                                                  ? Colors.white.withValues(alpha: 0.2)
                                                  : isSuggested
                                                      ? Colors.green.withValues(alpha: 0.15)
                                                      : Colors.white.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isHovering
                                                    ? Colors.green
                                                    : isSuggested
                                                        ? Colors.greenAccent
                                                        : Colors.white10,
                                                width: (isHovering || isSuggested) ? 2 : 1,
                                              ),
                                              boxShadow: isSuggested
                                                  ? [
                                                      BoxShadow(
                                                        color: Colors.greenAccent.withValues(alpha: 0.3),
                                                        blurRadius: 8,
                                                        spreadRadius: 1,
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: isSuggested
                                                ? const Center(
                                                    child: Icon(
                                                      Icons.add_circle_outline,
                                                      color: Colors.greenAccent,
                                                      size: 24,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        );
                                      }

                                      final isSelected =
                                          _selectedClassForSuggestion == classInfo;

                                      return GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (_selectedClassForSuggestion == classInfo) {
                                              _selectedClassForSuggestion = null;
                                            } else {
                                              _selectedClassForSuggestion = classInfo;
                                            }
                                          });
                                        },
                                        child: Draggable<Map<String, dynamic>>(
                                          data: classInfo,
                                          feedback: Opacity(
                                            opacity: 0.8,
                                            child: _buildClassCard(
                                              classInfo,
                                              day,
                                              time,
                                              group,
                                              true,
                                              isSelected: isSelected,
                                            ),
                                          ),
                                          childWhenDragging: _buildClassCard(
                                            classInfo,
                                            day,
                                            time,
                                            group,
                                            false,
                                            isDragging: true,
                                            isSelected: isSelected,
                                          ),
                                          child: _buildClassCard(
                                            classInfo,
                                            day,
                                            time,
                                            group,
                                            false,
                                            isHovering: isHovering,
                                            isSelected: isSelected,
                                          ),
                                        ),
                                      );
                                    },
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassCard(
    Map<String, dynamic> classInfo,
    String day,
    String time,
    String group,
    bool isFeedback, {
    bool isDragging = false,
    bool isHovering = false,
    bool isSelected = false,
  }) {
    final isLab = classInfo['type'] == 'lab';
    return Container(
      height: 100,
      width: 150,
      margin: EdgeInsets.only(bottom: isFeedback ? 0 : 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDragging
            ? Colors.white.withValues(alpha: 0.05)
            : isSelected
            ? const Color(0xFF00C6FF).withValues(alpha: 0.3)
            : isHovering
            ? Colors.white.withValues(alpha: 0.2)
            : isLab
            ? const Color(0xFF7F00FF).withValues(alpha: 0.2)
            : const Color(0xFF00C6FF).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF00C6FF)
              : isHovering
              ? Colors.green
              : isDragging
              ? Colors.white10
              : isLab
              ? const Color(0xFF7F00FF).withValues(alpha: 0.5)
              : const Color(0xFF00C6FF).withValues(alpha: 0.5),
          width: (isSelected || isHovering) ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: const Color(0xFF00C6FF).withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: isDragging
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classInfo['course'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  classInfo['instructor'] ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 10,
                      color: isLab
                          ? const Color(0xFF7F00FF)
                          : const Color(0xFF00C6FF),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        classInfo['room'] ?? '',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
