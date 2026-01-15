from datetime import datetime
from flask import Flask, request, jsonify
from flask_cors import CORS
from ortools.sat.python import cp_model

app = Flask(__name__)
CORS(app)

def parse_timeslot(ts_str):
    """
    Parses a timeslot string like "08:30 AM - 09:30 AM"
    Returns (start_minutes, end_minutes) from midnight.
    """
    try:
        parts = ts_str.split('-')
        if len(parts) != 2:
            return 0, 0
        
        start_str = parts[0].strip()
        end_str = parts[1].strip()
        
        fmt = "%I:%M %p"
        start_dt = datetime.strptime(start_str, fmt)
        end_dt = datetime.strptime(end_str, fmt)
        
        start_min = start_dt.hour * 60 + start_dt.minute
        end_min = end_dt.hour * 60 + end_dt.minute
        
        return start_min, end_min
    except Exception as e:
        print(f"Error parsing timeslot '{ts_str}': {e}")
        return 0, 0

@app.route('/generate-timetable', methods=['POST'])
def generate_timetable():
    try:
        data = request.get_json()
        with open("server_debug.log", "a") as f:
            f.write(f"\n{datetime.now()} - Request received\n")
            f.write(f"Parsed JSON keys: {list(data.keys())}\n")
        instructors = data.get('instructors', [])
        courses = data.get('courses', [])
        rooms = data.get('rooms', [])
        student_groups = data.get('student_groups', [])
        days = data.get('days', [])
        timeslots = data.get('timeslots', [])
        settings = data.get('settings', {})

        # Open log file for this request
        with open("server_debug.log", "a") as f:
            f.write(f"\n\n--- NEW REQUEST {datetime.now()} ---\n")

        # DEBUG: Print received data

        # DEBUG: Print received data
        print(f"DEBUG: Received {len(student_groups)} student groups.")
        for sg in student_groups:
             print(f"DEBUG: Group {sg.get('id')} enrolled: {sg.get('enrolledCourses')}")

        model = cp_model.CpModel()

        # --- DATA PREPARATION ---
        all_instructors = {i['id']: i for i in instructors}
        all_courses = {c['id']: c for c in courses}
        all_rooms = {r['id']: r for r in rooms}
        all_student_groups = {sg['id']: sg for sg in student_groups}
        all_days = days
        all_timeslots = timeslots
        
        debug_log = []
        def log(msg):
            print(f"DEBUG: {msg}")
            debug_log.append(msg)
            try:
                with open("server_debug.log", "a") as f:
                    f.write(f"{datetime.now()}: {msg}\n")
            except: pass

        log(f"Received {len(student_groups)} student groups.")

        # ts_parsed: list of (start, end)
        ts_parsed = [parse_timeslot(ts) for ts in all_timeslots]
        
        # Calculate gaps between adjacent slots i and i+1
        # gaps[i] = start[i+1] - end[i]
        ts_gaps = []
        for i in range(len(ts_parsed) - 1):
            end_current = ts_parsed[i][1]
            start_next = ts_parsed[i+1][0]
            gap = start_next - end_current
            ts_gaps.append(gap)
            
        # --- VALIDATION: PRE-CHECK CONSTRAINT SATISFACTION ---
        # 1. Check if Student Groups have enough available slots for their requirements
        for sg_id, group in all_student_groups.items():
            enrolled_courses = group.get('enrolledCourses', [])
            total_required_hours = 0
            for c_id in enrolled_courses:
                course = all_courses.get(c_id)
                if not course: continue
                try:
                    total_required_hours += int(course.get('lectureHours', 0))
                    total_required_hours += int(course.get('labHours', 0))
                except (ValueError, TypeError):
                    pass
            
            # Calculate available slots for this group
            # Start with max possible
            total_available_slots = len(all_days) * len(all_timeslots)
            
            # Subtract unavailable slots
            availability = group.get('availability', {})
            unavailable_count = 0
            if availability:
                for day in all_days:
                    slots = availability.get(day, [])
                    # Count 0s in valid range
                    for i in range(min(len(slots), len(all_timeslots))):
                         if slots[i] == 0:
                             unavailable_count += 1
            
            total_available_slots -= unavailable_count
            
            # DEBUG: Log values for each group to trace the issue
            print(f"DEBUG: Group {sg_id} - Required: {total_required_hours}, Available: {total_available_slots}")

            if total_required_hours > total_available_slots:
                msg = f"Scheduling Failed: Student Group '{group.get('id')}' requires {total_required_hours} hours, but only has {total_available_slots} available slots. Please increase availability or reduce course load."
                log(msg)
                return jsonify({
                    'status': 'error', 
                    'message': msg
                }), 400

            # 1.1 Check for Impossible Lab Constraints (Consecutive Slots & Instructor Availability)
            # This checks for ALL labs, ensuring there are valid consecutive slots where both Group and Instructor are available.
            lab_prefs = group.get('labTimingPreferences', {})
            for c_id in enrolled_courses:
                course = all_courses.get(c_id)
                if not course: continue
                try:
                    lab_hours = int(course.get('labHours', 0))
                except: lab_hours = 0
                
                # Check for labs (assuming they need at least 2 consecutive hours)
                if lab_hours >= 2: 
                    # Check preferences
                    pref = lab_prefs.get(c_id)
                    is_afternoon = (pref == 'Afternoon')
                    
                    specific_start_min = None
                    if pref and not is_afternoon:
                        # Heuristic to find start time from strings like "11:00 - 1:00", "2 to 4", "8:30 - 10:30"
                        p_lower = pref.lower()
                        if '8:30' in p_lower: specific_start_min = 510  # 8:30 AM
                        elif '11' in p_lower: specific_start_min = 660  # 11:00 AM
                        elif '2' in p_lower and '12' not in p_lower: specific_start_min = 840   # 2:00 PM
                        elif '3' in p_lower and '13' not in p_lower: specific_start_min = 900   # 3:00 PM
                        elif '1' in p_lower and '11' not in p_lower and '12' not in p_lower: specific_start_min = 780 # 1:00 PM


                    disallow_830 = settings.get('disallow830Labs', False)

                    valid_lab_starts = []
                    for t_idx in range(len(all_timeslots) - 1): # Check for 2-hour blocks
                        t_start_min = ts_parsed[t_idx][0]
                        
                        # Filtering
                        if is_afternoon and t_start_min < 720: continue
                        if specific_start_min is not None and t_start_min != specific_start_min: continue
                        
                        # New Global Setting: Disallow 8:30 AM Labs
                        # 8:30 AM is 510 minutes from midnight
                        if disallow_830 and t_start_min == 510:
                            continue
                        
                        # Check if t_idx and t_idx+1 are continuous (gap must be 0)
                        if ts_gaps[t_idx] == 0:
                            valid_lab_starts.append(t_idx)

                    if not valid_lab_starts:
                         msg = f"Scheduling Failed: Course '{course['name']}' requires a {lab_hours}-hour lab ({pref if pref else 'Any Time'}), but no consecutive slots exist starting at the preferred time (check breaks or timeslots)."
                         log(msg)
                         return jsonify({'status': 'error', 'message': msg, 'debug_log': debug_log}), 400
                    
                    # Check Instructor Availability for these slots
                    # Needs at least ONE valid start slot where instructor is available for BOTH hours
                    
                    # Get qualified/preferred instructor
                    instructor_id = None
                    inst_prefs = group.get('instructorPreferences', {})
                    if c_id in inst_prefs:
                        instructor_id = inst_prefs[c_id]
                    
                    instructors_to_check = []
                    if instructor_id:
                         instructors_to_check = [all_instructors.get(instructor_id)]
                    else:
                         q_ids = course.get('qualifiedInstructors', [])
                         instructors_to_check = [all_instructors.get(qid) for qid in q_ids]
                    
                    instructors_to_check = [i for i in instructors_to_check if i] # Filter None

                    if not instructors_to_check:
                        log(f"Warning: No valid instructors found for {c_id}")
                        continue

                    can_schedule = False
                    
                    # Check if ANY instructor can teach in ANY valid slot on ANY day
                    for inst in instructors_to_check:
                        inst_avail = inst.get('availability', {})
                        for day in all_days:
                            # Group must also be available!
                            group_avail = availability.get(day, [])
                            inst_day_avail = inst_avail.get(day, [])
                            
                            for start_idx in valid_lab_starts:
                                # Check slot 1 and slot 2 (indices start_idx and start_idx+1)
                                
                                # Check Group Avail
                                g_ok = True
                                if start_idx < len(group_avail) and group_avail[start_idx] == 0: g_ok = False
                                if (start_idx+1) < len(group_avail) and group_avail[start_idx+1] == 0: g_ok = False
                                
                                if not g_ok: continue

                                # Check Inst Avail
                                i_ok = True
                                if start_idx < len(inst_day_avail) and inst_day_avail[start_idx] == 0: i_ok = False
                                if (start_idx+1) < len(inst_day_avail) and inst_day_avail[start_idx+1] == 0: i_ok = False

                                if i_ok:
                                    can_schedule = True
                                    # log(f"Found VALID slot for {c_id}: Day {day}, Index {start_idx}")
                                    break
                            if can_schedule: break
                        if can_schedule: break
                    
                    if not can_schedule:
                         inst_names = ", ".join([i['name'] for i in instructors_to_check])
                         msg = f"Scheduling Failed: Course '{course['name']}' ({group.get('id')}) requires a Lab{' (Afternoon)' if is_afternoon else ''}, but no assigned instructor ({inst_names}) is available for 2 consecutive slots where the group is also available."
                         log(msg)
                         log(f"Validation Detail: {c_id}, Group {group['id']}, Insts: {inst_names}")
                         log(f"Valid Lab Starts: {valid_lab_starts}")
                         return jsonify({
                            'status': 'error', 
                            'message': msg,
                            'debug_log': debug_log
                        }), 400

            # 1.2 Check Per-Course Instructor-Group Availability Overlap
            # Ensure that for each course, there are enough slots where BOTH Group and Instructor are available.
            for c_id in enrolled_courses:
                course = all_courses.get(c_id)
                if not course: continue
                
                try:
                    req_hours = int(course.get('lectureHours', 0)) + int(course.get('labHours', 0))
                except: req_hours = 0
                
                if req_hours == 0: continue

                # Get Instructors
                inst_prefs = group.get('instructorPreferences', {})
                instructor_id = inst_prefs.get(c_id)
                
                check_instructors = []
                if instructor_id:
                     check_instructors = [all_instructors.get(instructor_id)]
                else:
                     q_ids = course.get('qualifiedInstructors', [])
                     check_instructors = [all_instructors.get(qid) for qid in q_ids]
                
                check_instructors = [i for i in check_instructors if i]
                if not check_instructors: continue

                # Calculate valid overlap count
                overlap_count = 0
                # We can sum overlap across all days/slots. 
                # If ANY instructor is available at (day, slot), and Group is available, it counts.
                
                for day in all_days:
                    group_day_avail = group.get('availability', {}).get(day, [])
                    
                    # Compute union of instructor availability for this day
                    inst_union_avail = [0] * len(all_timeslots)
                    for inst in check_instructors:
                        inst_day_avail = inst.get('availability', {}).get(day, [])
                        for i in range(min(len(inst_day_avail), len(all_timeslots))):
                            if inst_day_avail[i] == 1:
                                inst_union_avail[i] = 1
                    
                    # Intersect with Group
                    for i in range(min(len(group_day_avail), len(all_timeslots))):
                        if group_day_avail[i] == 1 and inst_union_avail[i] == 1:
                            overlap_count += 1
                
                print(f"DEBUG: Course {c_id} ({course['name']}) Overlap: {overlap_count}, Required: {req_hours}")
                
                if overlap_count < req_hours:
                     msg = f"Scheduling Failed: Course '{course['name']}' requires {req_hours} hours. Based on Student Group '{group.get('id')}' availability and Instructor availability, only {overlap_count} valid slots exist. Please increase availability."
                     print(f"DEBUG: {msg}")
                     return jsonify({
                        'status': 'error', 
                        'message': msg
                    }), 400


        # 2. Check Global Room Capacity vs Total Requirements
        total_global_required_hours = 0
        for sg_id, group in all_student_groups.items():
            enrolled_courses = group.get('enrolledCourses', [])
            for c_id in enrolled_courses:
                course = all_courses.get(c_id)
                if not course: continue
                try:
                    total_global_required_hours += int(course.get('lectureHours', 0))
                    total_global_required_hours += int(course.get('labHours', 0))
                except: pass
        
        total_global_room_slots = 0
        for r_id, room in all_rooms.items():
            room_slots = len(all_days) * len(all_timeslots)
            availability = room.get('availability', {})
            unavailable_count = 0
            if availability:
                for day in all_days:
                    slots = availability.get(day, [])
                    for i in range(min(len(slots), len(all_timeslots))):
                        if slots[i] == 0:
                            unavailable_count += 1
            
            total_global_room_slots += (room_slots - unavailable_count)
            
        print(f"DEBUG: Global Check - Required: {total_global_required_hours}, Room Capacity: {total_global_room_slots}")

        if total_global_required_hours > total_global_room_slots:
             msg = f"Scheduling Failed: Total class hours required ({total_global_required_hours}) exceed the total capacity of all rooms ({total_global_room_slots}). Please add more rooms or extend working hours."
             print(f"DEBUG: {msg}")
             return jsonify({
                'status': 'error', 
                'message': msg
            }), 400


        # Create unique tasks for each required session (lecture or lab)
        # REFACTOR: Tasks are now specific to a Student Group.
        # Task ID format: {sg_id}_{c_id}_{type}_{index}
        tasks = {}
        
        for sg_id, group in all_student_groups.items():
            enrolled_courses = group.get('enrolledCourses', [])
            for c_id in enrolled_courses:
                course = all_courses.get(c_id)
                if not course:
                    continue
                
                try:
                    lec_hours = int(course.get('lectureHours', 0))
                except (ValueError, TypeError):
                    lec_hours = 0
                
                try:
                    lab_hours = int(course.get('labHours', 0))
                except (ValueError, TypeError):
                    lab_hours = 0

                for i in range(lec_hours):
                    task_id = f'{sg_id}_{c_id}_lec_{i}'
                    tasks[task_id] = {
                        'course_id': c_id, 
                        'type': 'lecture',
                        'group_id': sg_id
                    }
                for i in range(lab_hours):
                    task_id = f'{sg_id}_{c_id}_lab_{i}'
                    tasks[task_id] = {
                        'course_id': c_id, 
                        'type': 'lab',
                        'group_id': sg_id
                    }
        msg_tasks = f"Created {len(tasks)} tasks."
        print(f"DEBUG: {msg_tasks}")
        with open("server_debug.log", "a") as f:
            f.write(f"{datetime.now()}: {msg_tasks}\n")

        # --- CREATE VARIABLES ---
        assign = {}
        lab_vars = []
        for task_id, task_info in tasks.items():
            course_id = task_info['course_id']
            course = all_courses[course_id]
            
            # Check for group preference
            sg_id = task_info['group_id']
            group = all_student_groups.get(sg_id)
            preferred_inst_id = None
            if group:
                preferences = group.get('instructorPreferences', {})
                preferred_inst_id = preferences.get(course_id)

            qualified_instructors = course.get('qualifiedInstructors', [])
            
            # If preference exists, restrict to that instructor (if qualified, or just trust preference?)
            # Let's assume preference must be in qualified list, or just use it.
            # The previous logic added a constraint, but here we can just optimize variable creation.
            target_instructors = qualified_instructors
            if preferred_inst_id:
                # If preferred instructor is valid, only create vars for them
                # If not in qualified list, maybe we should still allow? Let's assume valid.
                target_instructors = [preferred_inst_id]

            for inst_id in target_instructors:
                for room_id in all_rooms:
                    for day in all_days:
                        for timeslot in all_timeslots:
                            v = model.NewBoolVar(f'assign_{task_id}_{inst_id}_{room_id}_{day}_{timeslot}')
                            assign[(task_id, inst_id, room_id, day, timeslot)] = v
                            
                            if task_info['type'] == 'lab':
                                lab_vars.append(v)
        
        # --- PRIORITIZE LAB ALLOCATION ---
        # Force the solver to branch on lab variables first.
        if lab_vars:
             model.AddDecisionStrategy(lab_vars, cp_model.CHOOSE_FIRST, cp_model.SELECT_MIN_VALUE)

        # --- INSTRUCTOR AVAILABILITY CONSTRAINT ---
        # Enforce that instructors are not assigned to slots where they are unavailable.
        # availability is a map: { "Monday": [1, 1, 0, ...], ... }
        # The index in the list corresponds to the index in all_timeslots.
        
        # Map timeslots to indices for easier lookup
        ts_to_index = {ts: i for i, ts in enumerate(all_timeslots)}
        
        for inst_id, instructor in all_instructors.items():
            availability = instructor.get('availability', {})
            if not availability:
                continue
                
            for day, slots in availability.items():
                if day not in all_days:
                    continue
                
                # Iterate through the availability slots
                # Note: The length of slots should match all_timeslots. 
                # If mismatch, we use the minimum length to avoid errors, or assume 1 (available) if missing.
                for t_idx, is_available in enumerate(slots):
                    if t_idx >= len(all_timeslots):
                        break
                        
                    if is_available == 0: # Unavailable
                        timeslot = all_timeslots[t_idx]
                        
                        # Forbid this instructor from being assigned to ANY task at this time
                        for task_id in tasks:
                            for room_id in all_rooms:
                                if (task_id, inst_id, room_id, day, timeslot) in assign:
                                    model.Add(assign[(task_id, inst_id, room_id, day, timeslot)] == 0)

        # --- STUDENT GROUP AVAILABILITY CONSTRAINT ---
        # Enforce that student groups are not assigned to classes when they are unavailable.
        for sg_id, group in all_student_groups.items():
            availability = group.get('availability', {})
            if not availability:
                continue

            # Identify all tasks belonging to this group
            group_tasks = [tid for tid, t in tasks.items() if t['group_id'] == sg_id]

            for day, slots in availability.items():
                if day not in all_days:
                    continue

                for t_idx, is_available in enumerate(slots):
                    if t_idx >= len(all_timeslots):
                        break
                    
                    if is_available == 0: # Unavailable
                        timeslot = all_timeslots[t_idx]

                        # Forbid ANY task for this group to be scheduled at this time
                        for task_id in group_tasks:
                            for inst_id in all_instructors:
                                for room_id in all_rooms:
                                    if (task_id, inst_id, room_id, day, timeslot) in assign:
                                        model.Add(assign[(task_id, inst_id, room_id, day, timeslot)] == 0)

        # --- ROOM AVAILABILITY CONSTRAINT ---
        # Enforce that rooms are not assigned to classes when they are unavailable.
        for r_id, room in all_rooms.items():
            availability = room.get('availability', {})
            if not availability:
                continue

            for day, slots in availability.items():
                if day not in all_days:
                    continue

                for t_idx, is_available in enumerate(slots):
                    if t_idx >= len(all_timeslots):
                        break
                    
                    if is_available == 0: # Unavailable
                        timeslot = all_timeslots[t_idx]

                        # Forbid ANY task in this room at this time
                        for task_id in tasks:
                            for inst_id in all_instructors:
                                if (task_id, inst_id, r_id, day, timeslot) in assign:
                                    model.Add(assign[(task_id, inst_id, r_id, day, timeslot)] == 0)

        # --- HARD CONSTRAINTS ---

        # 1. Each task must be scheduled exactly once
        for task_id in tasks:
            # Check if any assignment variable exists for this task (it might not if no qualified instructor)
            possible_vars = [assign[(task_id, inst_id, room_id, day, timeslot)]
                                for inst_id in all_instructors for room_id in all_rooms
                                for day in all_days for timeslot in all_timeslots
                                if (task_id, inst_id, room_id, day, timeslot) in assign]
            if possible_vars:
                model.AddExactlyOne(possible_vars)

        # 2. No double booking
        for day in all_days:
            for timeslot in all_timeslots:
                # Instructor conflict
                for inst_id in all_instructors:
                    model.AddAtMostOne(assign.get((task_id, inst_id, room_id, day, timeslot))
                                       for task_id in tasks for room_id in all_rooms
                                       if assign.get((task_id, inst_id, room_id, day, timeslot)) is not None)
                
                # Room conflict
                for room_id in all_rooms:
                    model.AddAtMostOne(assign.get((task_id, inst_id, room_id, day, timeslot))
                                       for task_id in tasks for inst_id in all_instructors
                                       if assign.get((task_id, inst_id, room_id, day, timeslot)) is not None)
                
                # Student Group conflict
                # Since tasks are now group-specific, we just need to ensure that for a given group,
                # only one task is scheduled at a time.
                for sg_id in all_student_groups:
                    # Filter tasks belonging to this group
                    group_tasks = [tid for tid, t in tasks.items() if t['group_id'] == sg_id]
                    
                    model.AddAtMostOne(assign.get((task_id, inst_id, room_id, day, timeslot))
                                       for task_id in group_tasks for inst_id in all_instructors for room_id in all_rooms
                                       if assign.get((task_id, inst_id, room_id, day, timeslot)) is not None)

        # 3. Room capacity constraint
        for task_id, task_info in tasks.items():
            sg_id = task_info['group_id']
            group = all_student_groups[sg_id]
            
            try:
                group_size = int(group.get('size', 0))
            except (ValueError, TypeError):
                group_size = 0
            
            for room_id, room in all_rooms.items():
                try:
                    capacity = int(room.get('capacity', 0))
                except (ValueError, TypeError):
                    capacity = 0
                    
                if group_size > capacity:
                    for inst_id in all_instructors:
                        for day in all_days:
                            for timeslot in all_timeslots:
                                if (task_id, inst_id, room_id, day, timeslot) in assign:
                                    model.Add(assign[(task_id, inst_id, room_id, day, timeslot)] == 0)

        # 4. Equipment constraint
        for task_id, task_info in tasks.items():
            course = all_courses[task_info['course_id']]
            required_equipment = set(course.get('equipment', []))
            
            if required_equipment:
                for room_id, room in all_rooms.items():
                    room_equipment = set(room.get('equipment', []))
                    if not required_equipment.issubset(room_equipment):
                        for inst_id in all_instructors:
                             for day in all_days:
                                for timeslot in all_timeslots:
                                    if (task_id, inst_id, room_id, day, timeslot) in assign:
                                        model.Add(assign[(task_id, inst_id, room_id, day, timeslot)] == 0)

        # 5. Guaranteed Lunch Break (Hard Constraint)
        # Implicitly handled.

        # 6. Lab Room Constraint
        # Labs must be scheduled in rooms of type 'Lab' or 'Computer Lab'
        for task_id, task_info in tasks.items():
            if task_info['type'] == 'lab':
                course = all_courses[task_info['course_id']]
                lab_type = course.get('labType', 'Computer Lab') # Default to Computer Lab

                # Check for specific room preference (Hard Constraint)
                sg_id = task_info['group_id']
                group = all_student_groups.get(sg_id)
                preferred_room_id = None
                if group:
                     preferred_room_id = group.get('labRoomPreferences', {}).get(task_info['course_id'])

                for room_id, room in all_rooms.items():
                    # 1. Check Preference Constraint
                    if preferred_room_id and room_id != preferred_room_id:
                         # Block ALL slots for this room
                         for inst_id in all_instructors:
                             for day in all_days:
                                 for timeslot in all_timeslots:
                                     if (task_id, inst_id, room_id, day, timeslot) in assign:
                                         model.Add(assign[(task_id, inst_id, room_id, day, timeslot)] == 0)
                         continue

                    room_type = room.get('type', '').lower()
                    
                    is_valid_room = False
                    if lab_type == 'Hardware Lab':
                        if 'hardware' in room_type:
                            is_valid_room = True
                    else: # Computer Lab
                        if 'computer' in room_type:
                            is_valid_room = True
                        if 'lab' in room_type and 'hardware' not in room_type:
                             is_valid_room = True

                    
                    if not is_valid_room:
                        for inst_id in all_instructors:
                            for day in all_days:
                                for timeslot in all_timeslots:
                                    if (task_id, inst_id, room_id, day, timeslot) in assign:
                                        model.Add(assign[(task_id, inst_id, room_id, day, timeslot)] == 0)
            
            elif task_info['type'] == 'lecture':
                for room_id, room in all_rooms.items():
                    # Check if room type indicates it's a lab
                    room_type = room.get('type', '').lower()
                    is_lab_room = 'lab' in room_type or 'computer' in room_type
                    
                    if is_lab_room:
                        for inst_id in all_instructors:
                            for day in all_days:
                                for timeslot in all_timeslots:
                                    if (task_id, inst_id, room_id, day, timeslot) in assign:
                                        model.Add(assign[(task_id, inst_id, room_id, day, timeslot)] == 0)

        # --- NEW CONSTRAINTS ---

        # 6. No Repeating Classes per Day for a Student Group (Lectures)
        for sg_id, group in all_student_groups.items():
            enrolled_courses = group.get('enrolledCourses', [])
            for course_id in enrolled_courses:
                # Get all lecture tasks for this course AND this group
                course_lec_tasks = [tid for tid, t in tasks.items() 
                                  if t['course_id'] == course_id and t['type'] == 'lecture' and t['group_id'] == sg_id]
                
                if len(course_lec_tasks) > 1:
                    for day in all_days:
                        # Sum of assignments for this course for this group on this day must be <= 1
                        daily_assignments = []
                        for task_id in course_lec_tasks:
                            for inst_id in all_instructors:
                                for room_id in all_rooms:
                                    for timeslot in all_timeslots:
                                        if (task_id, inst_id, room_id, day, timeslot) in assign:
                                            daily_assignments.append(assign[(task_id, inst_id, room_id, day, timeslot)])
                        
                        if daily_assignments:
                            model.Add(sum(daily_assignments) <= 1)

        # 7. Consecutive Labs
        # Labs must be 2 hours long and cannot span across breaks.
        
        for sg_id, group in all_student_groups.items():
            enrolled_courses = group.get('enrolledCourses', [])
            for course_id in enrolled_courses:
                course = all_courses.get(course_id)
                if not course: continue

                try:
                    lab_hours = int(course.get('labHours', 0))
                except (ValueError, TypeError):
                    lab_hours = 0
                    
                if lab_hours > 0:
                    # Tasks are now: {sg_id}_{c_id}_lab_{i}
                    for i in range(0, lab_hours, 2):
                        if i + 1 < lab_hours:
                            lab_task_1 = f'{sg_id}_{course_id}_lab_{i}'
                            lab_task_2 = f'{sg_id}_{course_id}_lab_{i+1}'
                            
                            if lab_task_1 in tasks and lab_task_2 in tasks:
                                for day in all_days:
                                    for inst_id in all_instructors: # Assuming same instructor for both hours
                                        for room_id in all_rooms:   # Assuming same room for both hours
                                            
                                            # For each starting slot t, if we assign lab_1 at t, we MUST assign lab_2 at t+1
                                            for t_idx in range(len(all_timeslots) - 1):
                                                t1 = all_timeslots[t_idx]
                                                t2 = all_timeslots[t_idx + 1]
                                                
                                                # Check if this pair is valid (continuous)
                                                # Use calculated gaps
                                                gap = ts_gaps[t_idx]
                                                is_valid_pair = (gap == 0)
                                                
                                                if (lab_task_1, inst_id, room_id, day, t1) in assign and \
                                                   (lab_task_2, inst_id, room_id, day, t2) in assign:
                                                    
                                                    if is_valid_pair:
                                                        # If lab_1 is at t1, lab_2 MUST be at t2
                                                        model.Add(assign[(lab_task_2, inst_id, room_id, day, t2)] == 
                                                                  assign[(lab_task_1, inst_id, room_id, day, t1)])
                                                    else:
                                                        # Invalid pair (spans break), forbid starting at t1
                                                        model.Add(assign[(lab_task_1, inst_id, room_id, day, t1)] == 0)
                                            
                                            # Boundary condition: lab_1 cannot start at the LAST slot
                                            last_ts = all_timeslots[-1]
                                            if (lab_task_1, inst_id, room_id, day, last_ts) in assign:
                                                model.Add(assign[(lab_task_1, inst_id, room_id, day, last_ts)] == 0)
                                                
                                            # Boundary condition: lab_2 cannot start at the FIRST slot
                                            first_ts = all_timeslots[0]
                                            if (lab_task_2, inst_id, room_id, day, first_ts) in assign:
                                                model.Add(assign[(lab_task_2, inst_id, room_id, day, first_ts)] == 0)

        # 8. Faculty Break Constraint (Minimum 1 hour break between classes)
        # Exception: Continuous Lab sessions (which are effectively one long class)
        
        # First, identify all "paired" lab tasks that MUST be consecutive.
        # We can store them as a set of tuples: (task_id_1, task_id_2)
        paired_lab_tasks = set()
        for sg_id, group in all_student_groups.items():
            enrolled_courses = group.get('enrolledCourses', [])
            for course_id in enrolled_courses:
                course = all_courses.get(course_id)
                if not course: continue
                try:
                    lab_hours = int(course.get('labHours', 0))
                except:
                    lab_hours = 0
                
                if lab_hours > 0:
                    for i in range(0, lab_hours, 2):
                        if i + 1 < lab_hours:
                            t1_id = f'{sg_id}_{course_id}_lab_{i}'
                            t2_id = f'{sg_id}_{course_id}_lab_{i+1}'
                            if t1_id in tasks and t2_id in tasks:
                                paired_lab_tasks.add((t1_id, t2_id))

        # Now apply the constraint for each instructor
        for inst_id in all_instructors:
            for day in all_days:
                for t_idx in range(len(all_timeslots) - 1):
                    t1 = all_timeslots[t_idx]
                    t2 = all_timeslots[t_idx + 1]
                    
                    # Check gap. If gap >= 60 minutes, then they ALREADY have a break.
                    # So we only enforce the constraint if gap < 60.
                    gap = ts_gaps[t_idx]
                    if gap >= 60:
                        continue

                    # Gather all assignments for this instructor at t1 and t2
                    assigns_t1 = []
                    assigns_t2 = []
                    
                    # Also track if a paired lab is starting at t1
                    paired_lab_start_vars = []

                    for task_id in tasks:
                        for room_id in all_rooms:
                            # Check t1 assignment
                            if (task_id, inst_id, room_id, day, t1) in assign:
                                var_t1 = assign[(task_id, inst_id, room_id, day, t1)]
                                assigns_t1.append(var_t1)
                                
                                # Check if this task is the first part of a paired lab
                                is_start_of_pair = False
                                for (pt1, pt2) in paired_lab_tasks:
                                    if pt1 == task_id:
                                        is_start_of_pair = True
                                        break
                                
                                if is_start_of_pair:
                                    paired_lab_start_vars.append(var_t1)

                            # Check t2 assignment
                            if (task_id, inst_id, room_id, day, t2) in assign:
                                assigns_t2.append(assign[(task_id, inst_id, room_id, day, t2)])
                    
                    if assigns_t1 and assigns_t2:
                        # Constraint: Sum(assigns_t1) + Sum(assigns_t2) <= 1 + Sum(paired_lab_start_vars)
                        model.Add(sum(assigns_t1) + sum(assigns_t2) <= 1 + sum(paired_lab_start_vars))

        # 9. Max One Lab Per Day per Student Group
        for sg_id, group in all_student_groups.items():
            enrolled_courses = group.get('enrolledCourses', [])
            lab_courses = []
            
            # Identify which enrolled courses are labs
            for c_id in enrolled_courses:
                course = all_courses.get(c_id)
                if not course: continue
                try:
                    lab_hours = int(course.get('labHours', 0))
                except:
                    lab_hours = 0
                
                if lab_hours > 0:
                    lab_courses.append(c_id)
            
            if len(lab_courses) > 1:
                # If group has multiple lab courses, ensure only 1 is scheduled per day
                for day in all_days:
                    course_active_vars = []
                    
                    for c_id in lab_courses:
                        # Find all tasks for this lab course
                        lab_tasks = [tid for tid, t in tasks.items() 
                                     if t['group_id'] == sg_id and t['course_id'] == c_id and t['type'] == 'lab']
                        
                        if not lab_tasks:
                            continue
                            
                        # Gather actual assignment vars for this course on this day
                        course_day_assigns = []
                        for task_id in lab_tasks:
                            for inst_id in all_instructors:
                                for room_id in all_rooms:
                                    for timeslot in all_timeslots:
                                        if (task_id, inst_id, room_id, day, timeslot) in assign:
                                            course_day_assigns.append(assign[(task_id, inst_id, room_id, day, timeslot)])
                        
                        # Create a bool: is this lab course scheduled today?
                        if course_day_assigns:
                            is_active = model.NewBoolVar(f'lab_active_{sg_id}_{c_id}_{day}')
                            model.AddMaxEquality(is_active, course_day_assigns)
                            course_active_vars.append(is_active)
                    
                    if course_active_vars:
                        # At most 1 lab course can be active on this day
                        model.Add(sum(course_active_vars) <= 1)



        # 10. Lab Afternoon Preference (Hard Constraint)
        # If a student group prefers labs in the afternoon for a specific course, enforce it.
        # Afternoon starts at 12:00 PM (720 minutes)
        
        # Identify morning slots
        morning_slots = []
        for i, ts in enumerate(all_timeslots):
            start_min, _ = ts_parsed[i]
            if start_min < 720: # Before 12:00 PM
                morning_slots.append(ts)
        
        for task_id, task_info in tasks.items():
            if task_info['type'] == 'lab':
                sg_id = task_info['group_id']
                course_id = task_info['course_id']
                group = all_student_groups.get(sg_id)
                
                if group:
                    lab_prefs = group.get('labTimingPreferences', {})
                    pref = lab_prefs.get(course_id)
                    
                    if pref == 'Afternoon':
                        # Forbid morning slots
                        for timeslot in morning_slots:
                             for day in all_days:
                                for inst_id in all_instructors:
                                    for room_id in all_rooms:
                                        if (task_id, inst_id, room_id, day, timeslot) in assign:
                                            model.Add(assign[(task_id, inst_id, room_id, day, timeslot)] == 0)

        # --- SOFT CONSTRAINTS (OBJECTIVES) ---
        objectives = []

        # 11. Disallow 8:30 AM Labs (Soft Constraint / Penalty)
        # We moved this from Hard to Soft because strict enforcement can cause failures 
        # (e.g., on Saturdays or with limited rooms/availabilities).
        # We apply a MASSIVE penalty (e.g. 1000) to ensure it's avoided unless absolutely necessary.
        if settings.get('disallow830Labs', False):
            # Identify slots in 8:30 AM - 10:30 AM range (510 to 630 minutes)
            forbidden_slots = []
            for i, ts in enumerate(all_timeslots):
                start_min, end_min = ts_parsed[i]
                if start_min >= 510 and end_min <= 630:
                     forbidden_slots.append(ts)
            
            if forbidden_slots:
                penalty_weight = 1000 # Very high penalty
                for task_id, task_info in tasks.items():
                    if task_info['type'] == 'lab':
                         for (tid, inst_id, room_id, day, timeslot), var in assign.items():
                             if tid == task_id and timeslot in forbidden_slots:
                                 objectives.append(var * penalty_weight)

        # 6. Minimize Gaps for Students
        gap_priority = settings.get('gapPriority', 0.0)
        if gap_priority > 0:
            weight = int(gap_priority * 10) # 10 or 20
            
            # Map timeslots to indices
            ts_map = {ts: i for i, ts in enumerate(all_timeslots)}
            num_slots = len(all_timeslots)
            
            for sg_id, group in all_student_groups.items():
                # Filter tasks for this group
                group_tasks = [tid for tid, t in tasks.items() if t['group_id'] == sg_id]
                
                for day in all_days:
                    # Create boolean vars for "is slot t occupied for this group"
                    slot_active = [model.NewBoolVar(f'active_{sg_id}_{day}_{t}') for t in range(num_slots)]
                    
                    for t_idx, ts in enumerate(all_timeslots):
                        # Gather all possible assignments for this group in this slot
                        possible_assigns = []
                        for task_id in group_tasks:
                            for inst_id in all_instructors:
                                for room_id in all_rooms:
                                    if (task_id, inst_id, room_id, day, ts) in assign:
                                        possible_assigns.append(assign[(task_id, inst_id, room_id, day, ts)])
                        
                        # Link slot_active to assignments
                        if possible_assigns:
                            model.AddMaxEquality(slot_active[t_idx], possible_assigns)
                        else:
                            model.Add(slot_active[t_idx] == 0)
                    
                    # Calculate span: max_index - min_index
                    has_classes = model.NewBoolVar(f'has_classes_{sg_id}_{day}')
                    model.AddMaxEquality(has_classes, slot_active)
                    
                    min_slot = model.NewIntVar(0, num_slots, f'min_slot_{sg_id}_{day}')
                    max_slot = model.NewIntVar(0, num_slots, f'max_slot_{sg_id}_{day}')

                    for t in range(num_slots):
                        model.Add(min_slot <= t).OnlyEnforceIf(slot_active[t])
                        model.Add(max_slot >= t).OnlyEnforceIf(slot_active[t])
                    
                    total_active = sum(slot_active)
                    span = model.NewIntVar(0, num_slots, f'span_{sg_id}_{day}')
                    model.Add(span == max_slot - min_slot + 1).OnlyEnforceIf(has_classes)
                    model.Add(span == 0).OnlyEnforceIf(has_classes.Not())
                    
                    gaps = model.NewIntVar(0, num_slots, f'gaps_{sg_id}_{day}')
                    model.Add(gaps == span - total_active)
                    
                    objectives.append(gaps * weight)

        # 7. Fair Instructor Workload
        if settings.get('fairWorkload', False):
            weight = 5
            instructor_hours = []
            for inst_id in all_instructors:
                # Sum all assignments for this instructor
                inst_assigns = []
                for key, var in assign.items():
                    if key[1] == inst_id: # key is (task_id, inst_id, room_id, day, timeslot)
                        inst_assigns.append(var)
                
                hours = model.NewIntVar(0, len(all_timeslots) * len(all_days), f'hours_{inst_id}')
                model.Add(hours == sum(inst_assigns))
                instructor_hours.append(hours)
            
            if instructor_hours:
                min_h = model.NewIntVar(0, 100, 'min_hours')
                max_h = model.NewIntVar(0, 100, 'max_hours')
                
                model.AddMinEquality(min_h, instructor_hours)
                model.AddMaxEquality(max_h, instructor_hours)
                
                diff = model.NewIntVar(0, 100, 'diff_hours')
                model.Add(diff == max_h - min_h)
                
                objectives.append(diff * weight)

        # 8. Preferred Morning Classes
        preferred_courses = set(settings.get('preferredMorningCourses', []))
        if preferred_courses:
            weight = 2
            # Morning slots: Ends with AM
            
            for (task_id, inst_id, room_id, day, timeslot), var in assign.items():
                task_info = tasks[task_id]
                if task_info['course_id'] in preferred_courses:
                    if 'PM' in timeslot and not timeslot.startswith('12'): # 12 PM is noon, arguably morning/lunch, but let's say strictly AM
                         # Penalize if NOT in morning (so if it is PM, penalize)
                         # Actually, let's be stricter: Must be AM.
                         if 'AM' not in timeslot:
                            objectives.append(var * weight)

        # 9. Preferred Common Room (Soft Constraint)
        # If a student group has a preferred room, prioritize it for their lectures.
        room_pref_weight = 5 # Adjust weight as needed (higher than others to prioritize)
        
        for (task_id, inst_id, room_id, day, timeslot), var in assign.items():
            task_info = tasks[task_id]
            sg_id = task_info['group_id']
            group = all_student_groups.get(sg_id)
            
            if group:
                preferred_room_id = group.get('preferredRoomId')
                
                if preferred_room_id and preferred_room_id in all_rooms:
                     # If this group has a preference, and the assigned room is NOT the preferred one
                     if room_id != preferred_room_id:
                         # Penalize
                         objectives.append(var * room_pref_weight)


        # Minimize total penalty
        if objectives:
            model.Minimize(sum(objectives))
        
        # --- SOLVE ---
        solver = cp_model.CpSolver()
        solver.parameters.max_time_in_seconds = 120.0
        status = solver.Solve(model)
        status_msg = f"Solver Status: {status} (Optimal={cp_model.OPTIMAL}, Feasible={cp_model.FEASIBLE})"
        print(f"DEBUG: {status_msg}")
        with open("server_debug.log", "a") as f:
            f.write(f"{datetime.now()}: {status_msg}\n")

        # --- PROCESS RESULTS ---
        if status == cp_model.OPTIMAL or status == cp_model.FEASIBLE:
            schedule = []
            for (task_id, inst_id, room_id, day, timeslot), var in assign.items():
                if solver.Value(var) == 1:
                    task_info = tasks[task_id]
                    course_id = task_info['course_id']
                    sg_id = task_info['group_id']
                    
                    # Get group name
                    group_name = all_student_groups[sg_id]['id'] # Or name if available

                    schedule.append({
                        'day': day,
                        'timeslot': timeslot,
                        'courseId': course_id,
                        'course': all_courses[course_id]['name'],
                        'instructor': all_instructors[inst_id]['name'],
                        'room': room_id,
                        'group': group_name,
                        'type': task_info['type'] # 'lecture' or 'lab'
                    })
            return jsonify({'status': 'success', 'schedule': schedule})
        else:
            # --- HEURISTIC ANALYSIS FOR USER FRIENDLY ERROR ---
            hints = []
            
            # 1. Check for "Tight Fit" Groups
            for sg_id, group in all_student_groups.items():
                # Re-calculate required
                enrolled_courses = group.get('enrolledCourses', [])
                req_hours = 0
                for c_id in enrolled_courses:
                    course = all_courses.get(c_id)
                    if course:
                        try:
                            req_hours += int(course.get('lectureHours', 0)) + int(course.get('labHours', 0))
                        except: pass
                
                # Re-calculate available
                avail_slots = 0
                availability = group.get('availability', {})
                if availability:
                    for day in all_days:
                        slots = availability.get(day, [])
                        for i in range(min(len(slots), len(all_timeslots))):
                            if slots[i] == 1:
                                avail_slots += 1
                else:
                    avail_slots = len(all_days) * len(all_timeslots)
                
                if avail_slots > 0 and (req_hours / avail_slots) >= 0.8: # Lowered to 80%
                     hints.append(f"Student Group '{group.get('id')}' is very busy (Needs {req_hours} slots, Has {avail_slots} available). Any mismatch in lab hours or instructor availability will cause failure. Try freeing up more slots for this group.")

            # 2. Check for Overworked Instructors
            # This is an estimation, as we don't know exactly which instructor is picked for every course (if multiple qualified).
            # But we can check if a single instructor is the ONLY option for many courses.
            inst_load = {}
            for sg_id, group in all_student_groups.items():
                for c_id in group.get('enrolledCourses', []):
                    course = all_courses.get(c_id)
                    if not course: continue
                    
                    # Determine probable instructor
                    prob_inst_id = None
                    inst_prefs = group.get('instructorPreferences', {})
                    if c_id in inst_prefs:
                        prob_inst_id = inst_prefs[c_id]
                    else:
                        q_ids = course.get('qualifiedInstructors', [])
                        if len(q_ids) == 1:
                            prob_inst_id = q_ids[0]
                    
                    if prob_inst_id:
                        try:
                            hrs = int(course.get('lectureHours', 0)) + int(course.get('labHours', 0))
                        except: hrs = 0
                        inst_load[prob_inst_id] = inst_load.get(prob_inst_id, 0) + hrs

            for inst_id, required_hours in inst_load.items():
                instructor = all_instructors.get(inst_id)
                if not instructor: continue
                
                # key 'availability'
                avail_slots = 0
                availability = instructor.get('availability', {})
                if availability:
                    for day in all_days:
                        slots = availability.get(day, [])
                        for i in range(min(len(slots), len(all_timeslots))):
                            if slots[i] == 1:
                                avail_slots += 1
                else:
                     avail_slots = len(all_days) * len(all_timeslots)
                
                if avail_slots > 0 and required_hours > avail_slots:
                    hints.append(f"Instructor '{instructor['name']}' is overloaded (Assigned {required_hours} hours, Available for {avail_slots} slots).")
                elif avail_slots > 0 and (required_hours / avail_slots) > 0.8:
                     hints.append(f"Instructor '{instructor['name']}' has very high load (Assigned {required_hours} hours, Available for {avail_slots} slots).")


            message = 'No solution found for the given constraints.'
            if hints:
                message += " Likely causes: " + " ".join(hints)
            
            return jsonify({'status': 'error', 'message': message, 'debug_log': debug_log}), 400

    except Exception as e:
        import traceback
        traceback.print_exc()
        # This will now give a more descriptive error message in the app
        return jsonify({'status': 'error', 'message': f"Server crashed: {str(e)}", 'debug_log': debug_log if 'debug_log' in locals() else []}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000, use_reloader=True, reloader_interval=1, reloader_type='stat', extra_files=None, exclude_patterns=['*/Timely_venv/*', '*\\Timely_venv\\*'])

