import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:timely_ai/models/CourseModel.dart';
import 'package:timely_ai/models/InstructorModel.dart';

class PdfGenerator {
  static Future<void> generateAndPreview({
    required List<Map<String, dynamic>> schedule,
    required List<Course> courses,
    required List<Instructor> instructors,
    String title = 'Timetable',
    String subtitle = '',
    String semester =
        '5th Semester B.E.', // This acts as "Class" now as per request
    String section = 'A', // Requested Section A
    String room = '', // Requested Blank
    String academicYear = '2025-26',
  }) async {
    final pdf = pw.Document();

    // --- Helper Functions ---

    // 1. Get Initials from Name
    String getInitials(String name) {
      if (name.isEmpty) return '';
      // Remove titles like Mr., Mrs., Dr.
      var cleanName = name.replaceAll(
        RegExp(r'^(Mr\.|Mrs\.|Dr\.|Ms\.|Prof\.)\s+'),
        '',
      );
      return cleanName
          .split(' ')
          .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
          .join('');
    }

    // 2. Format Time Range
    // Converts "08:30 AM - 09:30 AM" to "08.30-\n09.30"
    String formatTimeRange(String ts) {
      try {
        final parts = ts.split(' - ');
        if (parts.length != 2) return ts;

        String formatSingle(String t) {
          final p = t.split(' ');
          return p[0].replaceAll(':', '.');
        }

        return '${formatSingle(parts[0])}-\n${formatSingle(parts[1])}';
      } catch (e) {
        return ts;
      }
    }

    // --- Data Preparation ---
    final List<String> allDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    // Sort timeslots
    final encodedTimeslots = schedule
        .map((e) => e['timeslot'] as String)
        .toSet()
        .toList();

    int parseTime(String t) {
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

    (int, int) getRange(String ts) {
      final parts = ts.split(' - ');
      if (parts.length != 2) return (0, 0);
      return (parseTime(parts[0]), parseTime(parts[1]));
    }

    encodedTimeslots.sort((a, b) => getRange(a).$1.compareTo(getRange(b).$1));

    final morningSlots = <String>[];
    final afternoonSlots = <String>[];

    const lunchStartMin = 13 * 60; // 13:00
    const lunchEndMin = 14 * 60; // 14:00

    for (var ts in encodedTimeslots) {
      final (start, end) = getRange(ts);
      // Heuristic: If it ends by 1:30 PM (13:30) or starts before lunch, it's morning.
      // Actually user requested specifically based on the image structure.
      // Typically 1-2 PM is lunch.
      if (end <= lunchStartMin) {
        morningSlots.add(ts);
      } else if (start >= lunchEndMin) {
        afternoonSlots.add(ts);
      } else {
        // If it overlaps lunch? For now put in morning if starts before lunch
        if (start < lunchStartMin) {
          morningSlots.add(ts);
        } else {
          afternoonSlots.add(ts);
        }
      }
    }

    // Grid Helper
    final Map<String, Map<String, dynamic>> gridMap = {};
    for (var s in schedule) {
      final d = s['day'];
      final t = s['timeslot'];
      if (gridMap[d] == null) gridMap[d] = {};
      gridMap[d]![t] = s;
    }

    // --- WIDGET BUILDER HELPERS ---

    pw.Widget buildCell(
      String text, {
      bool isHeader = false,
      int colspan = 1,
      pw.TextAlign align = pw.TextAlign.center,
      double? width,
    }) {
      return pw.Container(
        width: width,
        padding: const pw.EdgeInsets.all(4),
        alignment: isHeader ? pw.Alignment.center : pw.Alignment.center,
        height: 35, // Consistent Row Height
        child: isHeader
            ? pw.Text(
                text,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
                textAlign: align,
              )
            : pw.Text(
                text,
                style: const pw.TextStyle(fontSize: 8),
                textAlign: align,
              ),
      );
    }

    // Helper to generate a cell content widget (not the container wrapper, for merging logic)
    pw.Widget buildContent(Map<String, dynamic>? item) {
      if (item == null) return pw.SizedBox();

      return pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            item['course'] ?? '',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
          ),
          if (item['type'] == 'lab')
            pw.Text(
              '(${item['instructor']})',
              style: const pw.TextStyle(fontSize: 7),
              textAlign: pw.TextAlign.center,
            )
          else
            pw.Text(
              getInitials(item['instructor'] ?? ''),
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
          if (item['room'] != null &&
              item['room'].toString().isNotEmpty &&
              item['room'] != room)
            pw.Text(
              item['room'],
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
        ],
      );
    }

    // Wrapper for data cells to handle borders same as buildCell
    pw.Widget buildDataCell({required pw.Widget? content, int flex = 1}) {
      return pw.Expanded(
        flex: flex,
        child: pw.Container(
          height: 35,
          padding: const pw.EdgeInsets.all(2),
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(
            border: pw.Border(right: pw.BorderSide(), bottom: pw.BorderSide()),
          ),
          child: content ?? pw.SizedBox(),
        ),
      );
    }

    // --- BUILDING THE GRIDS ---

    // Morning Header Row
    // (removed unused definition)

    final morningHeaderWidgets = <pw.Widget>[
      buildCell('Class: $semester', isHeader: true, width: 60),
    ];
    for (var ts in morningSlots) {
      morningHeaderWidgets.add(
        pw.Expanded(
          flex: 1,
          child: pw.Container(
            height: 35,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(),
                bottom: pw.BorderSide(),
              ),
            ),
            child: pw.Text(
              formatTimeRange(ts),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
      );
    }

    // Afternoon Header Row
    final afternoonHeaderWidgets = <pw.Widget>[
      buildCell('Section: $section', isHeader: true, width: 60),
    ];
    for (var ts in afternoonSlots) {
      afternoonHeaderWidgets.add(
        pw.Expanded(
          flex: 1,
          child: pw.Container(
            height: 35,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(),
                bottom: pw.BorderSide(),
              ),
            ),
            child: pw.Text(
              formatTimeRange(ts),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
      );
    }

    // Morning Rows
    List<pw.Widget> morningRows = [];
    morningRows.add(pw.Row(children: morningHeaderWidgets));

    for (var day in allDays) {
      List<pw.Widget> children = [];
      // Day Cell
      children.add(buildCell(day, isHeader: true, width: 60));

      // Slots
      int i = 0;
      while (i < morningSlots.length) {
        final ts = morningSlots[i];
        final item = gridMap[day]?[ts];
        int span = 1;

        // Merge logic
        if (item != null && item['type'] == 'lab') {
          for (int j = i + 1; j < morningSlots.length; j++) {
            final nextItem = gridMap[day]?[morningSlots[j]];
            if (nextItem != null &&
                nextItem['courseId'] == item['courseId'] &&
                nextItem['group'] == item['group'] &&
                nextItem['type'] == 'lab') {
              span++;
            } else {
              break;
            }
          }
        }

        children.add(buildDataCell(content: buildContent(item), flex: span));
        i += span;
      }

      // Fill missing slots if any
      // If logic above skips properly, we are good.

      morningRows.add(pw.Row(children: children));
    }

    // Afternoon Rows
    List<pw.Widget> afternoonRows = [];
    afternoonRows.add(pw.Row(children: afternoonHeaderWidgets));

    for (int d = 0; d < allDays.length; d++) {
      var day = allDays[d];
      List<pw.Widget> children = [];

      // Col 0
      if (d == 0) {
        children.add(buildCell('Room: $room', isHeader: true, width: 60));
      } else {
        children.add(buildCell('', width: 60));
      }

      // Slots
      int i = 0;
      while (i < afternoonSlots.length) {
        final ts = afternoonSlots[i];
        final item = gridMap[day]?[ts];
        int span = 1;

        // Merge Logic
        if (item != null && item['type'] == 'lab') {
          for (int j = i + 1; j < afternoonSlots.length; j++) {
            final nextItem = gridMap[day]?[afternoonSlots[j]];
            if (nextItem != null &&
                nextItem['courseId'] == item['courseId'] &&
                nextItem['group'] == item['group'] &&
                nextItem['type'] == 'lab') {
              span++;
            } else {
              break;
            }
          }
        }

        children.add(buildDataCell(content: buildContent(item), flex: span));
        i += span;
      }

      afternoonRows.add(pw.Row(children: children));
    }

    // ---Footer Data Prep---
    final uniqueCourseIds = schedule
        .map((e) => e['courseId'] as String)
        .toSet();
    final footerData = <List<String>>[];

    for (var cid in uniqueCourseIds) {
      final course = courses.firstWhere(
        (c) => c.id == cid,
        orElse: () => Course(
          id: cid,
          name: 'Unknown',
          lectureHours: 0,
          labHours: 0,
          qualifiedInstructors: [],
        ),
      );

      final courseItems = schedule.where((s) => s['courseId'] == cid).toList();
      String facultyStr = '';

      if (course.labHours > 0 ||
          (courseItems.isNotEmpty && courseItems.first['type'] == 'lab')) {
        final batchMap = <String, String>{};
        for (var item in courseItems) {
          final grp = item['group'] as String;
          final inst = item['instructor'] as String;

          if (!batchMap.containsKey(grp)) {
            batchMap[grp] = inst;
          } else {
            if (!batchMap[grp]!.contains(inst)) {
              batchMap[grp] = '${batchMap[grp]} + $inst';
            }
          }
        }

        final uniqueInsts = batchMap.values.toSet();
        if (uniqueInsts.length == 1 && uniqueInsts.isNotEmpty) {
          facultyStr = uniqueInsts.first;
        } else {
          facultyStr = batchMap.entries
              .map((e) => '${e.key}: ${e.value}')
              .join('\n');
        }
      } else {
        final instNames = courseItems
            .map((s) => s['instructor'] as String)
            .toSet()
            .toList();
        facultyStr = instNames.join(', ');
      }

      footerData.add([
        course.id,
        course.name,
        course.ltp,
        course.credits.toString(),
        facultyStr,
      ]);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              // 1. INSTITUTION HEADER
              pw.Text(
                'MALNAD COLLEGE OF ENGINEERING, HASSAN',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'DEPARTMENT OF INFORMATION SCIENCE & ENGINEERING',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Time-Table for Academic Year Odd Semester $academicYear',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),

              // 2. TIMETABLE GRID
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // --- LEFT SECTION (Morning) ---
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(),
                          left: pw.BorderSide(),
                        ),
                      ),
                      child: pw.Column(children: morningRows),
                    ),
                  ),

                  // --- MIDDLE SECTION (Lunch Break) ---
                  pw.Container(
                    width: 30,
                    height: (morningRows.length * 35)
                        .toDouble(), // Approx height sync
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(),
                        bottom: pw.BorderSide(),
                        right: pw.BorderSide(),
                      ),
                    ),
                    child: pw.Center(
                      child: pw.Transform.rotate(
                        angle: -math.pi / 2,
                        child: pw.Text(
                          'LUNCH BREAK',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // --- RIGHT SECTION (Afternoon) ---
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide()),
                      ),
                      child: pw.Column(children: afternoonRows),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 15),

              // 3. SUBJECT LEGEND TABLE
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FixedColumnWidth(60), // Code
                  1: const pw.FlexColumnWidth(3), // Title
                  2: const pw.FixedColumnWidth(40), // L-T-P
                  3: const pw.FixedColumnWidth(40), // Credits
                  4: const pw.FlexColumnWidth(2), // Faculty
                },
                children: [
                  // Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.amber),
                    children: [
                      buildCell('Subject\nCode', isHeader: true),
                      buildCell('Subject Title', isHeader: true),
                      buildCell('L-T-P', isHeader: true),
                      buildCell('Credits', isHeader: true),
                      buildCell('Name of the Faculty Member', isHeader: true),
                    ],
                  ),
                  // Data
                  ...footerData.map((row) {
                    return pw.TableRow(
                      children: [
                        buildCell(row[0]),
                        buildCell(row[1], align: pw.TextAlign.left),
                        buildCell(row[2]),
                        buildCell(row[3]),
                        buildCell(row[4], align: pw.TextAlign.left),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 10),

              // 4. FOOTER NOTES
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    "Note: ",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      "Remedial Classes will be engaged by the concerned Faculty with prior notification.",
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static Future<void> generateFacultyPdf({
    required List<Map<String, dynamic>> schedule,
    required List<Course> courses,
    required List<String> timeSlots,
    required String facultyName,
    String academicYear = '2024-25',
  }) async {
    final pdf = pw.Document();

    String formatTimeRange(String ts) {
      try {
        final parts = ts.split(' - ');
        if (parts.length != 2) return ts;
        String formatSingle(String t) {
          final p = t.split(' ');
          return p[0].replaceAll(':', '.');
        }

        return '${formatSingle(parts[0])}-\n${formatSingle(parts[1])}';
      } catch (e) {
        return ts;
      }
    }

    final List<String> allDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    final encodedTimeslots = List<String>.from(timeSlots);

    int parseTime(String t) {
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

    (int, int) getRange(String ts) {
      final parts = ts.split(' - ');
      if (parts.length != 2) return (0, 0);
      return (parseTime(parts[0]), parseTime(parts[1]));
    }

    encodedTimeslots.sort((a, b) => getRange(a).$1.compareTo(getRange(b).$1));

    final morningSlots = <String>[];
    final afternoonSlots = <String>[];
    const lunchStartMin = 13 * 60;
    const lunchEndMin = 14 * 60;

    for (var ts in encodedTimeslots) {
      final (start, end) = getRange(ts);
      if (end <= lunchStartMin) {
        morningSlots.add(ts);
      } else if (start >= lunchEndMin) {
        afternoonSlots.add(ts);
      } else {
        if (start < lunchStartMin)
          morningSlots.add(ts);
        else
          afternoonSlots.add(ts);
      }
    }

    final Map<String, Map<String, dynamic>> gridMap = {};
    for (var s in schedule) {
      final d = s['day'];
      final t = s['timeslot'];
      if (gridMap[d] == null) gridMap[d] = {};
      gridMap[d]![t] = s;
    }

    pw.Widget buildCell(
      String text, {
      bool isHeader = false,
      pw.TextAlign align = pw.TextAlign.center,
      double? width,
      bool hasBorder = false,
    }) {
      return pw.Container(
        width: width,
        padding: const pw.EdgeInsets.all(4),
        alignment: pw.Alignment.center,
        height: 35,
        decoration: hasBorder
            ? const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              )
            : null,
        child: pw.Text(
          text,
          style: isHeader
              ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)
              : const pw.TextStyle(fontSize: 8),
          textAlign: align,
        ),
      );
    }

    pw.Widget buildContent(Map<String, dynamic>? item) {
      if (item == null) return pw.SizedBox();
      return pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            item['course'] ?? '',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
          ),
          pw.Text(
            item['group'] != null
                ? item['group'].toString().replaceAll(',', '\n')
                : '',
            style: const pw.TextStyle(fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
          if (item['room'] != null && item['room'].toString().isNotEmpty)
            pw.Text(
              item['room'],
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          if (item['type'] == 'lab')
            pw.Text(
              'LAB',
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
            ),
        ],
      );
    }

    pw.Widget buildDataCell({required pw.Widget? content, int flex = 1}) {
      return pw.Expanded(
        flex: flex,
        child: pw.Container(
          height: 35,
          padding: const pw.EdgeInsets.all(2),
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(
            border: pw.Border(right: pw.BorderSide(), bottom: pw.BorderSide()),
          ),
          child: content ?? pw.SizedBox(),
        ),
      );
    }

    final morningHeaderWidgets = <pw.Widget>[
      buildCell('Days', isHeader: true, width: 60, hasBorder: true),
    ];
    for (var ts in morningSlots) {
      morningHeaderWidgets.add(
        pw.Expanded(
          child: pw.Container(
            height: 35,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(),
                bottom: pw.BorderSide(),
              ),
            ),
            child: pw.Text(
              formatTimeRange(ts),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
      );
    }

    final afternoonHeaderWidgets = <pw.Widget>[
      buildCell('', isHeader: true, width: 60, hasBorder: true),
    ];
    for (var ts in afternoonSlots) {
      afternoonHeaderWidgets.add(
        pw.Expanded(
          child: pw.Container(
            height: 35,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(),
                bottom: pw.BorderSide(),
              ),
            ),
            child: pw.Text(
              formatTimeRange(ts),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
      );
    }

    List<pw.Widget> morningRows = [pw.Row(children: morningHeaderWidgets)];
    for (var day in allDays) {
      List<pw.Widget> children = [];
      children.add(
        buildCell(
          day.substring(0, 3).toUpperCase(),
          isHeader: true,
          width: 60,
          hasBorder: true,
        ),
      );
      int i = 0;
      while (i < morningSlots.length) {
        final ts = morningSlots[i];
        final item = gridMap[day]?[ts];
        int span = 1;
        if (item != null && item['type'] == 'lab') {
          for (int j = i + 1; j < morningSlots.length; j++) {
            final next = gridMap[day]?[morningSlots[j]];
            if (next != null &&
                next['courseId'] == item['courseId'] &&
                next['group'] == item['group'] &&
                next['type'] == 'lab')
              span++;
            else
              break;
          }
        }
        children.add(buildDataCell(content: buildContent(item), flex: span));
        i += span;
      }
      morningRows.add(pw.Row(children: children));
    }

    List<pw.Widget> afternoonRows = [pw.Row(children: afternoonHeaderWidgets)];
    for (var day in allDays) {
      List<pw.Widget> children = [];
      children.add(buildCell('', width: 60, hasBorder: true));
      int i = 0;
      while (i < afternoonSlots.length) {
        final ts = afternoonSlots[i];
        final item = gridMap[day]?[ts];
        int span = 1;
        if (item != null && item['type'] == 'lab') {
          for (int j = i + 1; j < afternoonSlots.length; j++) {
            final next = gridMap[day]?[afternoonSlots[j]];
            if (next != null &&
                next['courseId'] == item['courseId'] &&
                next['group'] == item['group'] &&
                next['type'] == 'lab')
              span++;
            else
              break;
          }
        }
        children.add(buildDataCell(content: buildContent(item), flex: span));
        i += span;
      }
      afternoonRows.add(pw.Row(children: children));
    }

    final uniqueCourseIds = schedule
        .map((e) => e['courseId'] as String)
        .toSet();
    final loadData = <List<String>>[];
    int grandTotal = 0;

    for (var cid in uniqueCourseIds) {
      final course = courses.firstWhere(
        (c) => c.id == cid,
        orElse: () => Course(
          id: cid,
          name: 'Unknown',
          lectureHours: 0,
          labHours: 0,
          qualifiedInstructors: [],
        ),
      );
      final items = schedule.where((s) => s['courseId'] == cid).toList();
      final hours = items.length;
      grandTotal += hours;
      final rooms = items.map((s) => s['room'] as String).toSet().join(', ');
      loadData.add([
        course.id,
        course.name,
        hours.toString(),
        rooms.isEmpty ? '-' : rooms,
      ]);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Text(
                'MALNAD COLLEGE OF ENGINEERING, HASSAN',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'DEPARTMENT OF INFORMATION SCIENCE & ENGINEERING',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Individual Time Table - Even Semester $academicYear',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Faculty Name: $facultyName',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(),
                          left: pw.BorderSide(),
                        ),
                      ),
                      child: pw.Column(children: morningRows),
                    ),
                  ),
                  pw.Container(
                    width: 30,
                    height: (morningRows.length * 35).toDouble(),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(),
                        bottom: pw.BorderSide(),
                        right: pw.BorderSide(),
                      ),
                    ),
                    child: pw.Center(
                      child: pw.Transform.rotate(
                        angle: -math.pi / 2,
                        child: pw.Text(
                          'BREAK',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide()),
                      ),
                      child: pw.Column(children: afternoonRows),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Direct/Teaching Load',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FixedColumnWidth(80),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FixedColumnWidth(60),
                  3: const pw.FixedColumnWidth(80),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.amber),
                    children: [
                      buildCell('Course Code', isHeader: true),
                      buildCell('Course Title', isHeader: true),
                      buildCell('No. of Hours', isHeader: true),
                      buildCell('Class Room', isHeader: true),
                    ],
                  ),
                  ...loadData.map(
                    (row) => pw.TableRow(
                      children: [
                        buildCell(row[0]),
                        buildCell(row[1], align: pw.TextAlign.left),
                        buildCell(row[2]),
                        buildCell(row[3]),
                      ],
                    ),
                  ),
                  pw.TableRow(
                    children: [
                      buildCell(''),
                      buildCell(
                        'Total',
                        align: pw.TextAlign.right,
                        isHeader: true,
                      ),
                      buildCell(grandTotal.toString(), isHeader: true),
                      buildCell('', isHeader: true),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static Future<void> generateRoomPdf({
    required List<Map<String, dynamic>> schedule,
    required List<Course> courses,
    required List<String> timeSlots,
    required String roomName,
    String academicYear = '2024-25',
  }) async {
    final pdf = pw.Document();

    String formatTimeRange(String ts) {
      try {
        final parts = ts.split(' - ');
        if (parts.length != 2) return ts;
        String formatSingle(String t) {
          final p = t.split(' ');
          return p[0].replaceAll(':', '.');
        }

        return '${formatSingle(parts[0])}-\n${formatSingle(parts[1])}';
      } catch (e) {
        return ts;
      }
    }

    final List<String> allDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    final encodedTimeslots = List<String>.from(timeSlots);

    int parseTime(String t) {
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

    (int, int) getRange(String ts) {
      final parts = ts.split(' - ');
      if (parts.length != 2) return (0, 0);
      return (parseTime(parts[0]), parseTime(parts[1]));
    }

    encodedTimeslots.sort((a, b) => getRange(a).$1.compareTo(getRange(b).$1));

    final morningSlots = <String>[];
    final afternoonSlots = <String>[];
    const lunchStartMin = 13 * 60;
    const lunchEndMin = 14 * 60;

    for (var ts in encodedTimeslots) {
      final (start, end) = getRange(ts);
      if (end <= lunchStartMin) {
        morningSlots.add(ts);
      } else if (start >= lunchEndMin) {
        afternoonSlots.add(ts);
      } else {
        if (start < lunchStartMin)
          morningSlots.add(ts);
        else
          afternoonSlots.add(ts);
      }
    }

    final Map<String, Map<String, dynamic>> gridMap = {};
    for (var s in schedule) {
      final d = s['day'];
      final t = s['timeslot'];
      if (gridMap[d] == null) gridMap[d] = {};
      gridMap[d]![t] = s;
    }

    pw.Widget buildCell(
      String text, {
      bool isHeader = false,
      pw.TextAlign align = pw.TextAlign.center,
      double? width,
      bool hasBorder = false,
    }) {
      return pw.Container(
        width: width,
        padding: const pw.EdgeInsets.all(4),
        alignment: pw.Alignment.center,
        height: 35,
        decoration: hasBorder
            ? const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              )
            : null,
        child: pw.Text(
          text,
          style: isHeader
              ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)
              : const pw.TextStyle(fontSize: 8),
          textAlign: align,
        ),
      );
    }

    pw.Widget buildContent(Map<String, dynamic>? item) {
      if (item == null) return pw.SizedBox();
      return pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            item['course'] ?? '',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
          ),
          pw.Text(
            item['group'] != null
                ? item['group'].toString().replaceAll(',', '\n')
                : '',
            style: const pw.TextStyle(fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
          if (item['instructor'] != null && item['instructor'].toString().isNotEmpty)
            pw.Text(
              item['instructor'],
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          if (item['type'] == 'lab')
            pw.Text(
              'LAB',
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
            ),
        ],
      );
    }

    pw.Widget buildDataCell({required pw.Widget? content, int flex = 1}) {
      return pw.Expanded(
        flex: flex,
        child: pw.Container(
          height: 35,
          padding: const pw.EdgeInsets.all(2),
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(
            border: pw.Border(right: pw.BorderSide(), bottom: pw.BorderSide()),
          ),
          child: content ?? pw.SizedBox(),
        ),
      );
    }

    final morningHeaderWidgets = <pw.Widget>[
      buildCell('Days', isHeader: true, width: 60, hasBorder: true),
    ];
    for (var ts in morningSlots) {
      morningHeaderWidgets.add(
        pw.Expanded(
          child: pw.Container(
            height: 35,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(),
                bottom: pw.BorderSide(),
              ),
            ),
            child: pw.Text(
              formatTimeRange(ts),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
      );
    }

    final afternoonHeaderWidgets = <pw.Widget>[
      buildCell('', isHeader: true, width: 60, hasBorder: true),
    ];
    for (var ts in afternoonSlots) {
      afternoonHeaderWidgets.add(
        pw.Expanded(
          child: pw.Container(
            height: 35,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(),
                bottom: pw.BorderSide(),
              ),
            ),
            child: pw.Text(
              formatTimeRange(ts),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
      );
    }

    List<pw.Widget> morningRows = [pw.Row(children: morningHeaderWidgets)];
    for (var day in allDays) {
      List<pw.Widget> children = [];
      children.add(
        buildCell(
          day.substring(0, 3).toUpperCase(),
          isHeader: true,
          width: 60,
          hasBorder: true,
        ),
      );
      int i = 0;
      while (i < morningSlots.length) {
        final ts = morningSlots[i];
        final item = gridMap[day]?[ts];
        int span = 1;
        if (item != null && item['type'] == 'lab') {
          for (int j = i + 1; j < morningSlots.length; j++) {
            final next = gridMap[day]?[morningSlots[j]];
            if (next != null &&
                next['courseId'] == item['courseId'] &&
                next['group'] == item['group'] &&
                next['type'] == 'lab')
              span++;
            else
              break;
          }
        }
        children.add(buildDataCell(content: buildContent(item), flex: span));
        i += span;
      }
      morningRows.add(pw.Row(children: children));
    }

    List<pw.Widget> afternoonRows = [pw.Row(children: afternoonHeaderWidgets)];
    for (var day in allDays) {
      List<pw.Widget> children = [];
      children.add(buildCell('', width: 60, hasBorder: true));
      int i = 0;
      while (i < afternoonSlots.length) {
        final ts = afternoonSlots[i];
        final item = gridMap[day]?[ts];
        int span = 1;
        if (item != null && item['type'] == 'lab') {
          for (int j = i + 1; j < afternoonSlots.length; j++) {
            final next = gridMap[day]?[afternoonSlots[j]];
            if (next != null &&
                next['courseId'] == item['courseId'] &&
                next['group'] == item['group'] &&
                next['type'] == 'lab')
              span++;
            else
              break;
          }
        }
        children.add(buildDataCell(content: buildContent(item), flex: span));
        i += span;
      }
      afternoonRows.add(pw.Row(children: children));
    }

    final uniqueCourseIds = schedule
        .map((e) => e['courseId'] as String)
        .toSet();
    final loadData = <List<String>>[];
    int grandTotal = 0;

    for (var cid in uniqueCourseIds) {
      final course = courses.firstWhere(
        (c) => c.id == cid,
        orElse: () => Course(
          id: cid,
          name: 'Unknown',
          lectureHours: 0,
          labHours: 0,
          qualifiedInstructors: [],
        ),
      );
      final items = schedule.where((s) => s['courseId'] == cid).toList();
      final hours = items.length;
      grandTotal += hours;
      final insts = items.map((s) => s['instructor'] as String).toSet().join(', ');
      loadData.add([
        course.id,
        course.name,
        hours.toString(),
        insts.isEmpty ? '-' : insts,
      ]);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Text(
                'MALNAD COLLEGE OF ENGINEERING, HASSAN',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'DEPARTMENT OF INFORMATION SCIENCE & ENGINEERING',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Room Time Table - Even Semester $academicYear',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Room Name: $roomName',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(),
                          left: pw.BorderSide(),
                        ),
                      ),
                      child: pw.Column(children: morningRows),
                    ),
                  ),
                  pw.Container(
                    width: 30,
                    height: (morningRows.length * 35).toDouble(),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(),
                        bottom: pw.BorderSide(),
                        right: pw.BorderSide(),
                      ),
                    ),
                    child: pw.Center(
                      child: pw.Transform.rotate(
                        angle: -math.pi / 2,
                        child: pw.Text(
                          'BREAK',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide()),
                      ),
                      child: pw.Column(children: afternoonRows),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  'Direct/Teaching Load',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FixedColumnWidth(80),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FixedColumnWidth(60),
                  3: const pw.FixedColumnWidth(80),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.amber),
                    children: [
                      buildCell('Course Code', isHeader: true),
                      buildCell('Course Title', isHeader: true),
                      buildCell('No. of Hours', isHeader: true),
                      buildCell('Instructor', isHeader: true),
                    ],
                  ),
                  ...loadData.map(
                    (row) => pw.TableRow(
                      children: [
                        buildCell(row[0]),
                        buildCell(row[1], align: pw.TextAlign.left),
                        buildCell(row[2]),
                        buildCell(row[3]),
                      ],
                    ),
                  ),
                  pw.TableRow(
                    children: [
                      buildCell(''),
                      buildCell(
                        'Total',
                        align: pw.TextAlign.right,
                        isHeader: true,
                      ),
                      buildCell(grandTotal.toString(), isHeader: true),
                      buildCell('', isHeader: true),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
  static Future<void> generateAllFacultyPdf({
    required List<Map<String, dynamic>> schedule,
    required List<Course> courses,
    required List<String> timeSlots,
    required List<String> facultyNames,
    String academicYear = '2024-25',
  }) async {
    final pdf = pw.Document();

    for (String facultyName in facultyNames) {
      final facultySchedule = schedule.where((s) => s['instructor'] == facultyName).toList();
      
      
      String formatTimeRange(String ts) {
        try {
          final parts = ts.split(' - ');
          if (parts.length != 2) return ts;
          String formatSingle(String t) {
            final p = t.split(' ');
            return p[0].replaceAll(':', '.');
          }
      
          return '${formatSingle(parts[0])}-\n${formatSingle(parts[1])}';
        } catch (e) {
          return ts;
        }
      }
      
      final List<String> allDays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ];
      
      final encodedTimeslots = List<String>.from(timeSlots);
      
      int parseTime(String t) {
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
      
      (int, int) getRange(String ts) {
        final parts = ts.split(' - ');
        if (parts.length != 2) return (0, 0);
        return (parseTime(parts[0]), parseTime(parts[1]));
      }
      
      encodedTimeslots.sort((a, b) => getRange(a).$1.compareTo(getRange(b).$1));
      
      final morningSlots = <String>[];
      final afternoonSlots = <String>[];
      const lunchStartMin = 13 * 60;
      const lunchEndMin = 14 * 60;
      
      for (var ts in encodedTimeslots) {
        final (start, end) = getRange(ts);
        if (end <= lunchStartMin) {
          morningSlots.add(ts);
        } else if (start >= lunchEndMin) {
          afternoonSlots.add(ts);
        } else {
          if (start < lunchStartMin)
            morningSlots.add(ts);
          else
            afternoonSlots.add(ts);
        }
      }
      
      final Map<String, Map<String, dynamic>> gridMap = {};
      for (var s in facultySchedule) {
        final d = s['day'];
        final t = s['timeslot'];
        if (gridMap[d] == null) gridMap[d] = {};
        gridMap[d]![t] = s;
      }
      
      pw.Widget buildCell(
        String text, {
        bool isHeader = false,
        pw.TextAlign align = pw.TextAlign.center,
        double? width,
        bool hasBorder = false,
      }) {
        return pw.Container(
          width: width,
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.center,
          height: 35,
          decoration: hasBorder
              ? const pw.BoxDecoration(
                  border: pw.Border(
                    right: pw.BorderSide(),
                    bottom: pw.BorderSide(),
                  ),
                )
              : null,
          child: pw.Text(
            text,
            style: isHeader
                ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)
                : const pw.TextStyle(fontSize: 8),
            textAlign: align,
          ),
        );
      }
      
      pw.Widget buildContent(Map<String, dynamic>? item) {
        if (item == null) return pw.SizedBox();
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              item['course'] ?? '',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
              maxLines: 2,
            ),
            pw.Text(
              item['group'] != null
                  ? item['group'].toString().replaceAll(',', '\n')
                  : '',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
            if (item['room'] != null && item['room'].toString().isNotEmpty)
              pw.Text(
                item['room'],
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            if (item['type'] == 'lab')
              pw.Text(
                'LAB',
                style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
              ),
          ],
        );
      }
      
      pw.Widget buildDataCell({required pw.Widget? content, int flex = 1}) {
        return pw.Expanded(
          flex: flex,
          child: pw.Container(
            height: 35,
            padding: const pw.EdgeInsets.all(2),
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(right: pw.BorderSide(), bottom: pw.BorderSide()),
            ),
            child: content ?? pw.SizedBox(),
          ),
        );
      }
      
      final morningHeaderWidgets = <pw.Widget>[
        buildCell('Days', isHeader: true, width: 60, hasBorder: true),
      ];
      for (var ts in morningSlots) {
        morningHeaderWidgets.add(
          pw.Expanded(
            child: pw.Container(
              height: 35,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              ),
              child: pw.Text(
                formatTimeRange(ts),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
        );
      }
      
      final afternoonHeaderWidgets = <pw.Widget>[
        buildCell('', isHeader: true, width: 60, hasBorder: true),
      ];
      for (var ts in afternoonSlots) {
        afternoonHeaderWidgets.add(
          pw.Expanded(
            child: pw.Container(
              height: 35,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              ),
              child: pw.Text(
                formatTimeRange(ts),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
        );
      }
      
      List<pw.Widget> morningRows = [pw.Row(children: morningHeaderWidgets)];
      for (var day in allDays) {
        List<pw.Widget> children = [];
        children.add(
          buildCell(
            day.substring(0, 3).toUpperCase(),
            isHeader: true,
            width: 60,
            hasBorder: true,
          ),
        );
        int i = 0;
        while (i < morningSlots.length) {
          final ts = morningSlots[i];
          final item = gridMap[day]?[ts];
          int span = 1;
          if (item != null && item['type'] == 'lab') {
            for (int j = i + 1; j < morningSlots.length; j++) {
              final next = gridMap[day]?[morningSlots[j]];
              if (next != null &&
                  next['courseId'] == item['courseId'] &&
                  next['group'] == item['group'] &&
                  next['type'] == 'lab')
                span++;
              else
                break;
            }
          }
          children.add(buildDataCell(content: buildContent(item), flex: span));
          i += span;
        }
        morningRows.add(pw.Row(children: children));
      }
      
      List<pw.Widget> afternoonRows = [pw.Row(children: afternoonHeaderWidgets)];
      for (var day in allDays) {
        List<pw.Widget> children = [];
        children.add(buildCell('', width: 60, hasBorder: true));
        int i = 0;
        while (i < afternoonSlots.length) {
          final ts = afternoonSlots[i];
          final item = gridMap[day]?[ts];
          int span = 1;
          if (item != null && item['type'] == 'lab') {
            for (int j = i + 1; j < afternoonSlots.length; j++) {
              final next = gridMap[day]?[afternoonSlots[j]];
              if (next != null &&
                  next['courseId'] == item['courseId'] &&
                  next['group'] == item['group'] &&
                  next['type'] == 'lab')
                span++;
              else
                break;
            }
          }
          children.add(buildDataCell(content: buildContent(item), flex: span));
          i += span;
        }
        afternoonRows.add(pw.Row(children: children));
      }
      
      final uniqueCourseIds = facultySchedule
          .map((e) => e['courseId'] as String)
          .toSet();
      final loadData = <List<String>>[];
      int grandTotal = 0;
      
      for (var cid in uniqueCourseIds) {
        final course = courses.firstWhere(
          (c) => c.id == cid,
          orElse: () => Course(
            id: cid,
            name: 'Unknown',
            lectureHours: 0,
            labHours: 0,
            qualifiedInstructors: [],
          ),
        );
        final items = facultySchedule.where((s) => s['courseId'] == cid).toList();
        final hours = items.length;
        grandTotal += hours;
        final rooms = items.map((s) => s['room'] as String).toSet().join(', ');
        loadData.add([
          course.id,
          course.name,
          hours.toString(),
          rooms.isEmpty ? '-' : rooms,
        ]);
      }
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Text(
                  'MALNAD COLLEGE OF ENGINEERING, HASSAN',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'DEPARTMENT OF INFORMATION SCIENCE & ENGINEERING',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Individual Time Table - Even Semester $academicYear',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 10),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Faculty Name: $facultyName',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            top: pw.BorderSide(),
                            left: pw.BorderSide(),
                          ),
                        ),
                        child: pw.Column(children: morningRows),
                      ),
                    ),
                    pw.Container(
                      width: 30,
                      height: (morningRows.length * 35).toDouble(),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(),
                          bottom: pw.BorderSide(),
                          right: pw.BorderSide(),
                        ),
                      ),
                      child: pw.Center(
                        child: pw.Transform.rotate(
                          angle: -math.pi / 2,
                          child: pw.Text(
                            'BREAK',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(top: pw.BorderSide()),
                        ),
                        child: pw.Column(children: afternoonRows),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 15),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Direct/Teaching Load',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(80),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FixedColumnWidth(60),
                    3: const pw.FixedColumnWidth(80),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.amber),
                      children: [
                        buildCell('Course Code', isHeader: true),
                        buildCell('Course Title', isHeader: true),
                        buildCell('No. of Hours', isHeader: true),
                        buildCell('Class Room', isHeader: true),
                      ],
                    ),
                    ...loadData.map(
                      (row) => pw.TableRow(
                        children: [
                          buildCell(row[0]),
                          buildCell(row[1], align: pw.TextAlign.left),
                          buildCell(row[2]),
                          buildCell(row[3]),
                        ],
                      ),
                    ),
                    pw.TableRow(
                      children: [
                        buildCell(''),
                        buildCell(
                          'Total',
                          align: pw.TextAlign.right,
                          isHeader: true,
                        ),
                        buildCell(grandTotal.toString(), isHeader: true),
                        buildCell('', isHeader: true),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
          }

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }


  static Future<void> generateStudentPdf({
    required List<Map<String, dynamic>> schedule,
    required List<Course> courses,
    required List<String> timeSlots,
    required String studentGroupName,
    required String section,
    required String preferredRoom,
    String academicYear = '2024-25',
  }) async {
    final pdf = pw.Document();

    String formatTimeRange(String ts) {
      try {
        final parts = ts.split(' - ');
        if (parts.length != 2) return ts;
        String formatSingle(String t) {
          final p = t.split(' ');
          return p[0].replaceAll(':', '.');
        }

        return '${formatSingle(parts[0])}-\n${formatSingle(parts[1])}';
      } catch (e) {
        return ts;
      }
    }

    final List<String> allDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    final encodedTimeslots = List<String>.from(timeSlots);

    int parseTime(String t) {
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

    (int, int) getRange(String ts) {
      final parts = ts.split(' - ');
      if (parts.length != 2) return (0, 0);
      return (parseTime(parts[0]), parseTime(parts[1]));
    }

    encodedTimeslots.sort((a, b) => getRange(a).$1.compareTo(getRange(b).$1));

    final morningSlots = <String>[];
    final afternoonSlots = <String>[];
    const lunchStartMin = 13 * 60;
    const lunchEndMin = 14 * 60;

    for (var ts in encodedTimeslots) {
      final (start, end) = getRange(ts);
      if (end <= lunchStartMin) {
        morningSlots.add(ts);
      } else if (start >= lunchEndMin) {
        afternoonSlots.add(ts);
      } else {
        if (start < lunchStartMin)
          morningSlots.add(ts);
        else
          afternoonSlots.add(ts);
      }
    }

    final Map<String, Map<String, dynamic>> gridMap = {};
    for (var s in schedule) {
      final d = s['day'];
      final t = s['timeslot'];
      if (gridMap[d] == null) gridMap[d] = {};
      gridMap[d]![t] = s;
    }

    pw.Widget buildCell(
      String text, {
      bool isHeader = false,
      pw.TextAlign align = pw.TextAlign.center,
      double? width,
      bool hasBorder = false,
    }) {
      return pw.Container(
        width: width,
        padding: const pw.EdgeInsets.all(4),
        alignment: pw.Alignment.center,
        height: 35,
        decoration: hasBorder
            ? const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              )
            : null,
        child: pw.Text(
          text,
          style: isHeader
              ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)
              : const pw.TextStyle(fontSize: 8),
          textAlign: align,
        ),
      );
    }

    pw.Widget buildContent(Map<String, dynamic>? item) {
      if (item == null) return pw.SizedBox();

      String instructorText = item['instructor'] ?? '';

      return pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            item['course'] ?? '',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
          ),
          pw.Text(
            instructorText,
            style: const pw.TextStyle(fontSize: 7),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
          ),
          // Conditionally show room if different from preferred
          if (item['room'] != null &&
              item['room'].toString().isNotEmpty &&
              item['room'].toString() != preferredRoom)
            pw.Text(
              item['room'],
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          if (item['type'] == 'lab')
            pw.Text(
              'LAB',
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
            ),
        ],
      );
    }

    pw.Widget buildDataCell({required pw.Widget? content, int flex = 1}) {
      return pw.Expanded(
        flex: flex,
        child: pw.Container(
          height: 35,
          padding: const pw.EdgeInsets.all(2),
          alignment: pw.Alignment.center,
          decoration: const pw.BoxDecoration(
            border: pw.Border(right: pw.BorderSide(), bottom: pw.BorderSide()),
          ),
          child: content ?? pw.SizedBox(),
        ),
      );
    }

    // --- Grid Headers ---
    final morningHeaderWidgets = <pw.Widget>[
      buildCell('Time\nDay', isHeader: true, width: 60, hasBorder: true),
    ];
    for (var ts in morningSlots) {
      morningHeaderWidgets.add(
        pw.Expanded(
          child: pw.Container(
            height: 35,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(),
                bottom: pw.BorderSide(),
              ),
            ),
            child: pw.Text(
              formatTimeRange(ts),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
      );
    }

    final afternoonHeaderWidgets = <pw.Widget>[
      // No extra cell here for Student PDF as per image
    ];
    for (var ts in afternoonSlots) {
      afternoonHeaderWidgets.add(
        pw.Expanded(
          child: pw.Container(
            height: 35,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                right: pw.BorderSide(),
                bottom: pw.BorderSide(),
              ),
            ),
            child: pw.Text(
              formatTimeRange(ts),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ),
      );
    }

    // --- Morning Rows ---
    final morningRows = <pw.Widget>[pw.Row(children: morningHeaderWidgets)];
    for (var day in allDays) {
      List<pw.Widget> children = [];
      children.add(
        buildCell(
          day.substring(0, 3).toUpperCase(),
          isHeader: true,
          width: 60,
          hasBorder: true,
        ),
      );
      int i = 0;
      while (i < morningSlots.length) {
        final ts = morningSlots[i];
        final item = gridMap[day]?[ts];
        int span = 1;
        if (item != null && item['type'] == 'lab') {
          for (int j = i + 1; j < morningSlots.length; j++) {
            final next = gridMap[day]?[morningSlots[j]];
            if (next != null &&
                next['courseId'] == item['courseId'] &&
                next['group'] == item['group'] &&
                next['type'] == 'lab')
              span++;
            else
              break;
          }
        }
        children.add(buildDataCell(content: buildContent(item), flex: span));
        i += span;
      }
      morningRows.add(pw.Row(children: children));
    }

    // --- Afternoon Rows ---
    final afternoonRows = <pw.Widget>[pw.Row(children: afternoonHeaderWidgets)];
    for (var day in allDays) {
      List<pw.Widget> children = [];
      // No prefix cell
      int i = 0;
      while (i < afternoonSlots.length) {
        final ts = afternoonSlots[i];
        final item = gridMap[day]?[ts];
        int span = 1;
        if (item != null && item['type'] == 'lab') {
          for (int j = i + 1; j < afternoonSlots.length; j++) {
            final next = gridMap[day]?[afternoonSlots[j]];
            if (next != null &&
                next['courseId'] == item['courseId'] &&
                next['group'] == item['group'] &&
                next['type'] == 'lab')
              span++;
            else
              break;
          }
        }
        children.add(buildDataCell(content: buildContent(item), flex: span));
        i += span;
      }
      afternoonRows.add(pw.Row(children: children));
    }

    // --- Footer Data ---
    final uniqueCourseIds = schedule
        .map((e) => e['courseId'] as String)
        .toSet();
    final footerData = <List<String>>[];
    for (var cid in uniqueCourseIds) {
      final course = courses.firstWhere(
        (c) => c.id == cid,
        orElse: () => Course(
          id: cid,
          name: 'Unknown',
          lectureHours: 0,
          labHours: 0,
          qualifiedInstructors: [],
        ),
      );
      final items = schedule.where((s) => s['courseId'] == cid).toList();
      String facultyStr = '';
      if (items.isNotEmpty) {
        final insts = items
            .map((e) => e['instructor'].toString())
            .toSet()
            .join(', ');
        facultyStr = insts;
      }
      footerData.add([
        course.id,
        course.name,
        course.ltp,
        course.credits.toString(),
        facultyStr,
      ]);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => pw.Column(
          children: [
            pw.Text(
              'MALNAD COLLEGE OF ENGINEERING, HASSAN',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.Text(
              'DEPARTMENT OF INFORMATION SCIENCE & ENGINEERING',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
            pw.Text(
              'Time-Table for Academic Year Even Semester $academicYear',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 10),

            // SUPER HEADERS
            pw.Row(
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(2),
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(border: pw.Border.all()),
                    child: pw.Text(
                      'Classes: $studentGroupName',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                pw.Container(
                  width: 30,
                  height: 18, // Matches approx font height + padding
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(),
                      bottom: pw.BorderSide(),
                      right: pw.BorderSide(),
                    ),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    "Sec:$section",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8,
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 4,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(2),
                    alignment: pw.Alignment.center,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(),
                        bottom: pw.BorderSide(),
                        right: pw.BorderSide(),
                      ),
                    ),
                    child: pw.Text(
                      'Room: $preferredRoom',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // GRID
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Container(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        left: pw.BorderSide(),
                        right: pw.BorderSide(),
                        bottom: pw.BorderSide(),
                      ),
                    ),
                    child: pw.Column(children: morningRows),
                  ),
                ),
                pw.Container(
                  width: 30,
                  height: (morningRows.length * 35).toDouble(),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      right: pw.BorderSide(),
                      bottom: pw.BorderSide(),
                    ),
                  ),
                  child: pw.Center(
                    child: pw.Transform.rotate(
                      angle: -math.pi / 2,
                      child: pw.Text(
                        'LUNCH BREAK',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 4,
                  child: pw.Container(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        right: pw.BorderSide(),
                        bottom: pw.BorderSide(),
                      ),
                    ),
                    child: pw.Column(children: afternoonRows),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 15),
            // LEGEND
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: const pw.FixedColumnWidth(60),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(40),
                3: const pw.FixedColumnWidth(40),
                4: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.amber),
                  children: [
                    buildCell('Subject\nCode', isHeader: true),
                    buildCell('Subject Title', isHeader: true),
                    buildCell('L-T-P', isHeader: true),
                    buildCell('Credits', isHeader: true),
                    buildCell('Name of the Faculty Member', isHeader: true),
                  ],
                ),
                ...footerData.map(
                  (row) => pw.TableRow(
                    children: [
                      buildCell(row[0]),
                      buildCell(row[1], align: pw.TextAlign.left),
                      buildCell(row[2]),
                      buildCell(row[3]),
                      buildCell(row[4], align: pw.TextAlign.left),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Text(
                  "Note: ",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
                pw.Text(
                  "Remedial Classes will be engaged by the concerned Faculty with prior notification.",
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static Future<void> generateAllStudentPdf({
    required List<Map<String, dynamic>> schedule,
    required List<Course> courses,
    required List<String> timeSlots,
    required List<String> studentGroupNames,
    String academicYear = '2024-25',
  }) async {
    final pdf = pw.Document();

    for (String studentGroupName in studentGroupNames) {
      final groupSchedule = schedule.where((s) => s['group'].toString().contains(studentGroupName)).toList();
      String section = 'A';
      final parts = studentGroupName.split(' ');
      if (parts.isNotEmpty) {
        final last = parts.last;
        if (last.length == 1 && RegExp(r'[A-Za-z]').hasMatch(last)) {
          section = last;
        }
      }
      String preferredRoom = ''; // Can't easily infer room here unless passed or fetched, but we will leave it as '' 
      
      
      String formatTimeRange(String ts) {
        try {
          final parts = ts.split(' - ');
          if (parts.length != 2) return ts;
          String formatSingle(String t) {
            final p = t.split(' ');
            return p[0].replaceAll(':', '.');
          }
      
          return '${formatSingle(parts[0])}-\n${formatSingle(parts[1])}';
        } catch (e) {
          return ts;
        }
      }
      
      final List<String> allDays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ];
      
      final encodedTimeslots = List<String>.from(timeSlots);
      
      int parseTime(String t) {
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
      
      (int, int) getRange(String ts) {
        final parts = ts.split(' - ');
        if (parts.length != 2) return (0, 0);
        return (parseTime(parts[0]), parseTime(parts[1]));
      }
      
      encodedTimeslots.sort((a, b) => getRange(a).$1.compareTo(getRange(b).$1));
      
      final morningSlots = <String>[];
      final afternoonSlots = <String>[];
      const lunchStartMin = 13 * 60;
      const lunchEndMin = 14 * 60;
      
      for (var ts in encodedTimeslots) {
        final (start, end) = getRange(ts);
        if (end <= lunchStartMin) {
          morningSlots.add(ts);
        } else if (start >= lunchEndMin) {
          afternoonSlots.add(ts);
        } else {
          if (start < lunchStartMin)
            morningSlots.add(ts);
          else
            afternoonSlots.add(ts);
        }
      }
      
      final Map<String, Map<String, dynamic>> gridMap = {};
      for (var s in groupSchedule) {
        final d = s['day'];
        final t = s['timeslot'];
        if (gridMap[d] == null) gridMap[d] = {};
        gridMap[d]![t] = s;
      }
      
      pw.Widget buildCell(
        String text, {
        bool isHeader = false,
        pw.TextAlign align = pw.TextAlign.center,
        double? width,
        bool hasBorder = false,
      }) {
        return pw.Container(
          width: width,
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.center,
          height: 35,
          decoration: hasBorder
              ? const pw.BoxDecoration(
                  border: pw.Border(
                    right: pw.BorderSide(),
                    bottom: pw.BorderSide(),
                  ),
                )
              : null,
          child: pw.Text(
            text,
            style: isHeader
                ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)
                : const pw.TextStyle(fontSize: 8),
            textAlign: align,
          ),
        );
      }
      
      pw.Widget buildContent(Map<String, dynamic>? item) {
        if (item == null) return pw.SizedBox();
      
        String instructorText = item['instructor'] ?? '';
      
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              item['course'] ?? '',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
              maxLines: 2,
            ),
            pw.Text(
              instructorText,
              style: const pw.TextStyle(fontSize: 7),
              textAlign: pw.TextAlign.center,
              maxLines: 2,
            ),
            // Conditionally show room if different from preferred
            if (item['room'] != null &&
                item['room'].toString().isNotEmpty &&
                item['room'].toString() != preferredRoom)
              pw.Text(
                item['room'],
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            if (item['type'] == 'lab')
              pw.Text(
                'LAB',
                style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
              ),
          ],
        );
      }
      
      pw.Widget buildDataCell({required pw.Widget? content, int flex = 1}) {
        return pw.Expanded(
          flex: flex,
          child: pw.Container(
            height: 35,
            padding: const pw.EdgeInsets.all(2),
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(right: pw.BorderSide(), bottom: pw.BorderSide()),
            ),
            child: content ?? pw.SizedBox(),
          ),
        );
      }
      
      // --- Grid Headers ---
      final morningHeaderWidgets = <pw.Widget>[
        buildCell('Time\nDay', isHeader: true, width: 60, hasBorder: true),
      ];
      for (var ts in morningSlots) {
        morningHeaderWidgets.add(
          pw.Expanded(
            child: pw.Container(
              height: 35,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              ),
              child: pw.Text(
                formatTimeRange(ts),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
        );
      }
      
      final afternoonHeaderWidgets = <pw.Widget>[
        // No extra cell here for Student PDF as per image
      ];
      for (var ts in afternoonSlots) {
        afternoonHeaderWidgets.add(
          pw.Expanded(
            child: pw.Container(
              height: 35,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              ),
              child: pw.Text(
                formatTimeRange(ts),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
        );
      }
      
      // --- Morning Rows ---
      final morningRows = <pw.Widget>[pw.Row(children: morningHeaderWidgets)];
      for (var day in allDays) {
        List<pw.Widget> children = [];
        children.add(
          buildCell(
            day.substring(0, 3).toUpperCase(),
            isHeader: true,
            width: 60,
            hasBorder: true,
          ),
        );
        int i = 0;
        while (i < morningSlots.length) {
          final ts = morningSlots[i];
          final item = gridMap[day]?[ts];
          int span = 1;
          if (item != null && item['type'] == 'lab') {
            for (int j = i + 1; j < morningSlots.length; j++) {
              final next = gridMap[day]?[morningSlots[j]];
              if (next != null &&
                  next['courseId'] == item['courseId'] &&
                  next['group'] == item['group'] &&
                  next['type'] == 'lab')
                span++;
              else
                break;
            }
          }
          children.add(buildDataCell(content: buildContent(item), flex: span));
          i += span;
        }
        morningRows.add(pw.Row(children: children));
      }
      
      // --- Afternoon Rows ---
      final afternoonRows = <pw.Widget>[pw.Row(children: afternoonHeaderWidgets)];
      for (var day in allDays) {
        List<pw.Widget> children = [];
        // No prefix cell
        int i = 0;
        while (i < afternoonSlots.length) {
          final ts = afternoonSlots[i];
          final item = gridMap[day]?[ts];
          int span = 1;
          if (item != null && item['type'] == 'lab') {
            for (int j = i + 1; j < afternoonSlots.length; j++) {
              final next = gridMap[day]?[afternoonSlots[j]];
              if (next != null &&
                  next['courseId'] == item['courseId'] &&
                  next['group'] == item['group'] &&
                  next['type'] == 'lab')
                span++;
              else
                break;
            }
          }
          children.add(buildDataCell(content: buildContent(item), flex: span));
          i += span;
        }
        afternoonRows.add(pw.Row(children: children));
      }
      
      // --- Footer Data ---
      final uniqueCourseIds = groupSchedule
          .map((e) => e['courseId'] as String)
          .toSet();
      final footerData = <List<String>>[];
      for (var cid in uniqueCourseIds) {
        final course = courses.firstWhere(
          (c) => c.id == cid,
          orElse: () => Course(
            id: cid,
            name: 'Unknown',
            lectureHours: 0,
            labHours: 0,
            qualifiedInstructors: [],
          ),
        );
        final items = groupSchedule.where((s) => s['courseId'] == cid).toList();
        String facultyStr = '';
        if (items.isNotEmpty) {
          final insts = items
              .map((e) => e['instructor'].toString())
              .toSet()
              .join(', ');
          facultyStr = insts;
        }
        footerData.add([
          course.id,
          course.name,
          course.ltp,
          course.credits.toString(),
          facultyStr,
        ]);
      }
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => pw.Column(
            children: [
              pw.Text(
                'MALNAD COLLEGE OF ENGINEERING, HASSAN',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
              ),
              pw.Text(
                'DEPARTMENT OF INFORMATION SCIENCE & ENGINEERING',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
              ),
              pw.Text(
                'Time-Table for Academic Year Even Semester $academicYear',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),
      
              // SUPER HEADERS
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(2),
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(border: pw.Border.all()),
                      child: pw.Text(
                        'Classes: $studentGroupName',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  pw.Container(
                    width: 30,
                    height: 18, // Matches approx font height + padding
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(),
                        bottom: pw.BorderSide(),
                        right: pw.BorderSide(),
                      ),
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      "Sec:$section",
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(2),
                      alignment: pw.Alignment.center,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(),
                          bottom: pw.BorderSide(),
                          right: pw.BorderSide(),
                        ),
                      ),
                      child: pw.Text(
                        'Room: $preferredRoom',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      
              // GRID
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          left: pw.BorderSide(),
                          right: pw.BorderSide(),
                          bottom: pw.BorderSide(),
                        ),
                      ),
                      child: pw.Column(children: morningRows),
                    ),
                  ),
                  pw.Container(
                    width: 30,
                    height: (morningRows.length * 35).toDouble(),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        right: pw.BorderSide(),
                        bottom: pw.BorderSide(),
                      ),
                    ),
                    child: pw.Center(
                      child: pw.Transform.rotate(
                        angle: -math.pi / 2,
                        child: pw.Text(
                          'LUNCH BREAK',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 4,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          right: pw.BorderSide(),
                          bottom: pw.BorderSide(),
                        ),
                      ),
                      child: pw.Column(children: afternoonRows),
                    ),
                  ),
                ],
              ),
      
              pw.SizedBox(height: 15),
              // LEGEND
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FixedColumnWidth(60),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FixedColumnWidth(40),
                  3: const pw.FixedColumnWidth(40),
                  4: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.amber),
                    children: [
                      buildCell('Subject\nCode', isHeader: true),
                      buildCell('Subject Title', isHeader: true),
                      buildCell('L-T-P', isHeader: true),
                      buildCell('Credits', isHeader: true),
                      buildCell('Name of the Faculty Member', isHeader: true),
                    ],
                  ),
                  ...footerData.map(
                    (row) => pw.TableRow(
                      children: [
                        buildCell(row[0]),
                        buildCell(row[1], align: pw.TextAlign.left),
                        buildCell(row[2]),
                        buildCell(row[3]),
                        buildCell(row[4], align: pw.TextAlign.left),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  pw.Text(
                    "Note: ",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                  pw.Text(
                    "Remedial Classes will be engaged by the concerned Faculty with prior notification.",
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
          }

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }



  static Future<void> generateAllRoomPdf({
    required List<Map<String, dynamic>> schedule,
    required List<Course> courses,
    required List<String> timeSlots,
    required List<String> roomNames,
    String academicYear = '2024-25',
  }) async {
    final pdf = pw.Document();

    for (String roomName in roomNames) {
      final roomSchedule = schedule.where((s) => s['room'] == roomName).toList();
      
      
      String formatTimeRange(String ts) {
        try {
          final parts = ts.split(' - ');
          if (parts.length != 2) return ts;
          String formatSingle(String t) {
            final p = t.split(' ');
            return p[0].replaceAll(':', '.');
          }
      
          return '${formatSingle(parts[0])}-\n${formatSingle(parts[1])}';
        } catch (e) {
          return ts;
        }
      }
      
      final List<String> allDays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ];
      
      final encodedTimeslots = List<String>.from(timeSlots);
      
      int parseTime(String t) {
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
      
      (int, int) getRange(String ts) {
        final parts = ts.split(' - ');
        if (parts.length != 2) return (0, 0);
        return (parseTime(parts[0]), parseTime(parts[1]));
      }
      
      encodedTimeslots.sort((a, b) => getRange(a).$1.compareTo(getRange(b).$1));
      
      final morningSlots = <String>[];
      final afternoonSlots = <String>[];
      const lunchStartMin = 13 * 60;
      const lunchEndMin = 14 * 60;
      
      for (var ts in encodedTimeslots) {
        final (start, end) = getRange(ts);
        if (end <= lunchStartMin) {
          morningSlots.add(ts);
        } else if (start >= lunchEndMin) {
          afternoonSlots.add(ts);
        } else {
          if (start < lunchStartMin)
            morningSlots.add(ts);
          else
            afternoonSlots.add(ts);
        }
      }
      
      final Map<String, Map<String, dynamic>> gridMap = {};
      for (var s in roomSchedule) {
        final d = s['day'];
        final t = s['timeslot'];
        if (gridMap[d] == null) gridMap[d] = {};
        gridMap[d]![t] = s;
      }
      
      pw.Widget buildCell(
        String text, {
        bool isHeader = false,
        pw.TextAlign align = pw.TextAlign.center,
        double? width,
        bool hasBorder = false,
      }) {
        return pw.Container(
          width: width,
          padding: const pw.EdgeInsets.all(4),
          alignment: pw.Alignment.center,
          height: 35,
          decoration: hasBorder
              ? const pw.BoxDecoration(
                  border: pw.Border(
                    right: pw.BorderSide(),
                    bottom: pw.BorderSide(),
                  ),
                )
              : null,
          child: pw.Text(
            text,
            style: isHeader
                ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)
                : const pw.TextStyle(fontSize: 8),
            textAlign: align,
          ),
        );
      }
      
      pw.Widget buildContent(Map<String, dynamic>? item) {
        if (item == null) return pw.SizedBox();
        return pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              item['course'] ?? '',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
              maxLines: 2,
            ),
            pw.Text(
              item['group'] != null
                  ? item['group'].toString().replaceAll(',', '\n')
                  : '',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.center,
            ),
            if (item['instructor'] != null && item['instructor'].toString().isNotEmpty)
              pw.Text(
                item['instructor'],
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            if (item['type'] == 'lab')
              pw.Text(
                'LAB',
                style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
              ),
          ],
        );
      }
      
      pw.Widget buildDataCell({required pw.Widget? content, int flex = 1}) {
        return pw.Expanded(
          flex: flex,
          child: pw.Container(
            height: 35,
            padding: const pw.EdgeInsets.all(2),
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(
              border: pw.Border(right: pw.BorderSide(), bottom: pw.BorderSide()),
            ),
            child: content ?? pw.SizedBox(),
          ),
        );
      }
      
      final morningHeaderWidgets = <pw.Widget>[
        buildCell('Days', isHeader: true, width: 60, hasBorder: true),
      ];
      for (var ts in morningSlots) {
        morningHeaderWidgets.add(
          pw.Expanded(
            child: pw.Container(
              height: 35,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              ),
              child: pw.Text(
                formatTimeRange(ts),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
        );
      }
      
      final afternoonHeaderWidgets = <pw.Widget>[
        buildCell('', isHeader: true, width: 60, hasBorder: true),
      ];
      for (var ts in afternoonSlots) {
        afternoonHeaderWidgets.add(
          pw.Expanded(
            child: pw.Container(
              height: 35,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  right: pw.BorderSide(),
                  bottom: pw.BorderSide(),
                ),
              ),
              child: pw.Text(
                formatTimeRange(ts),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
        );
      }
      
      List<pw.Widget> morningRows = [pw.Row(children: morningHeaderWidgets)];
      for (var day in allDays) {
        List<pw.Widget> children = [];
        children.add(
          buildCell(
            day.substring(0, 3).toUpperCase(),
            isHeader: true,
            width: 60,
            hasBorder: true,
          ),
        );
        int i = 0;
        while (i < morningSlots.length) {
          final ts = morningSlots[i];
          final item = gridMap[day]?[ts];
          int span = 1;
          if (item != null && item['type'] == 'lab') {
            for (int j = i + 1; j < morningSlots.length; j++) {
              final next = gridMap[day]?[morningSlots[j]];
              if (next != null &&
                  next['courseId'] == item['courseId'] &&
                  next['group'] == item['group'] &&
                  next['type'] == 'lab')
                span++;
              else
                break;
            }
          }
          children.add(buildDataCell(content: buildContent(item), flex: span));
          i += span;
        }
        morningRows.add(pw.Row(children: children));
      }
      
      List<pw.Widget> afternoonRows = [pw.Row(children: afternoonHeaderWidgets)];
      for (var day in allDays) {
        List<pw.Widget> children = [];
        children.add(buildCell('', width: 60, hasBorder: true));
        int i = 0;
        while (i < afternoonSlots.length) {
          final ts = afternoonSlots[i];
          final item = gridMap[day]?[ts];
          int span = 1;
          if (item != null && item['type'] == 'lab') {
            for (int j = i + 1; j < afternoonSlots.length; j++) {
              final next = gridMap[day]?[afternoonSlots[j]];
              if (next != null &&
                  next['courseId'] == item['courseId'] &&
                  next['group'] == item['group'] &&
                  next['type'] == 'lab')
                span++;
              else
                break;
            }
          }
          children.add(buildDataCell(content: buildContent(item), flex: span));
          i += span;
        }
        afternoonRows.add(pw.Row(children: children));
      }
      
      final uniqueCourseIds = roomSchedule
          .map((e) => e['courseId'] as String)
          .toSet();
      final loadData = <List<String>>[];
      int grandTotal = 0;
      
      for (var cid in uniqueCourseIds) {
        final course = courses.firstWhere(
          (c) => c.id == cid,
          orElse: () => Course(
            id: cid,
            name: 'Unknown',
            lectureHours: 0,
            labHours: 0,
            qualifiedInstructors: [],
          ),
        );
        final items = roomSchedule.where((s) => s['courseId'] == cid).toList();
        final hours = items.length;
        grandTotal += hours;
        final insts = items.map((s) => s['instructor'] as String).toSet().join(', ');
        loadData.add([
          course.id,
          course.name,
          hours.toString(),
          insts.isEmpty ? '-' : insts,
        ]);
      }
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Text(
                  'MALNAD COLLEGE OF ENGINEERING, HASSAN',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'DEPARTMENT OF INFORMATION SCIENCE & ENGINEERING',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Room Time Table - Even Semester $academicYear',
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.SizedBox(height: 10),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Room Name: $roomName',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 5,
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            top: pw.BorderSide(),
                            left: pw.BorderSide(),
                          ),
                        ),
                        child: pw.Column(children: morningRows),
                      ),
                    ),
                    pw.Container(
                      width: 30,
                      height: (morningRows.length * 35).toDouble(),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(),
                          bottom: pw.BorderSide(),
                          right: pw.BorderSide(),
                        ),
                      ),
                      child: pw.Center(
                        child: pw.Transform.rotate(
                          angle: -math.pi / 2,
                          child: pw.Text(
                            'BREAK',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Container(
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(top: pw.BorderSide()),
                        ),
                        child: pw.Column(children: afternoonRows),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 15),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'Direct/Teaching Load',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(80),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FixedColumnWidth(60),
                    3: const pw.FixedColumnWidth(80),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.amber),
                      children: [
                        buildCell('Course Code', isHeader: true),
                        buildCell('Course Title', isHeader: true),
                        buildCell('No. of Hours', isHeader: true),
                        buildCell('Instructor', isHeader: true),
                      ],
                    ),
                    ...loadData.map(
                      (row) => pw.TableRow(
                        children: [
                          buildCell(row[0]),
                          buildCell(row[1], align: pw.TextAlign.left),
                          buildCell(row[2]),
                          buildCell(row[3]),
                        ],
                      ),
                    ),
                    pw.TableRow(
                      children: [
                        buildCell(''),
                        buildCell(
                          'Total',
                          align: pw.TextAlign.right,
                          isHeader: true,
                        ),
                        buildCell(grandTotal.toString(), isHeader: true),
                        buildCell('', isHeader: true),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
          }

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }



}
