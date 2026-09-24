import re

with open('c:/Users/yashy/Yash App Project/Timely.AI/front-end/timely_ai/lib/features/PDF_creation/pdf_generation_service.dart', 'r', encoding='utf-8') as f:
    text = f.read()

match = re.search(r'(  static Future<void> generateFacultyPdf\(\{.*?await Printing\.layoutPdf[^\n]+\n  \})', text, re.DOTALL)
if match:
    code = match.group(1)
    
    # We will build generateRoomPdf and generateAllRoomPdf
    
    # For generateRoomPdf
    room_code = code.replace('generateFacultyPdf', 'generateRoomPdf')
    room_code = room_code.replace('required String facultyName,', 'required String roomName,')
    room_code = room_code.replace('Faculty Name:', 'Room Name:')
    room_code = room_code.replace('facultyName', 'roomName')
    room_code = room_code.replace('Individual Time Table', 'Room Time Table')
    # Change column headers if necessary. 
    room_code = room_code.replace('''buildCell('Class Room', isHeader: true),''', '''buildCell('Instructor', isHeader: true),''')
    room_code = room_code.replace('''final rooms = items.map((s) => s['room'] as String).toSet().join(', ');''', '''final insts = items.map((s) => s['instructor'] as String).toSet().join(', ');''')
    room_code = room_code.replace('''rooms.isEmpty ? '-' : rooms,''', '''insts.isEmpty ? '-' : insts,''')
    
    room_code = room_code.replace('''if (item['room'] != null && item['room'].toString().isNotEmpty)''', '''if (item['instructor'] != null && item['instructor'].toString().isNotEmpty)''')
    room_code = room_code.replace('''item['room'],''', '''item['instructor'],''')
    
    text = text.replace(code, code + '\n\n' + room_code)
    print('Added room')
    
    # Now build generateAllRoomPdf
    
    header = '''  static Future<void> generateAllRoomPdf({
    required List<Map<String, dynamic>> schedule,
    required List<Course> courses,
    required List<String> timeSlots,
    required List<String> roomNames,
    String academicYear = '2024-25',
  }) async {
    final pdf = pw.Document();

    for (String roomName in roomNames) {
      final roomSchedule = schedule.where((s) => s['room'] == roomName).toList();
'''
    body_match = re.search(r'final pdf = pw\.Document\(\);(.*?)await Printing\.layoutPdf', room_code, re.DOTALL)
    if body_match:
        body = body_match.group(1)
        lines = body.split('\n')
        indented_lines = ['      ' + line[4:] if line.startswith('    ') else '      ' + line for line in lines]
        indented_body = '\n'.join(indented_lines)
        indented_body = re.sub(r'\bschedule\b', 'roomSchedule', indented_body)
        
        new_func = header + indented_body + '''    }

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
'''
        text = text + '\n\n' + new_func
        print('Added all room')

with open('c:/Users/yashy/Yash App Project/Timely.AI/front-end/timely_ai/lib/features/PDF_creation/pdf_generation_service.dart', 'w', encoding='utf-8') as fw:
    fw.write(text)

