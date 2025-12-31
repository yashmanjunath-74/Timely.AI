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
        instructors = data.get('instructors', [])
        courses = data.get('courses', [])
        rooms = data.get('rooms', [])
        student_groups = data.get('student_groups', [])
        days = data.get('days', [])
        timeslots = data.get('timeslots', [])
        settings = data.get('settings', {})

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
        
        # Parse timeslots and calculate gaps
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

        # --- CREATE VARIABLES ---
        assign = {}
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
                            assign[(task_id, inst_id, room_id, day, timeslot)] = model.NewBoolVar(f'assign_{task_id}_{inst_id}_{room_id}_{day}_{timeslot}')

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

                for room_id, room in all_rooms.items():
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


        # --- SOFT CONSTRAINTS (OBJECTIVES) ---
        objectives = []

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
        solver.parameters.max_time_in_seconds = 30.0
        status = solver.Solve(model)

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
            return jsonify({'status': 'error', 'message': 'No solution found for the given constraints.'}), 400

    except Exception as e:
        import traceback
        traceback.print_exc()
        # This will now give a more descriptive error message in the app
        return jsonify({'status': 'error', 'message': f"Server crashed: {str(e)}"}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000, use_reloader=True, reloader_interval=1, reloader_type='stat', extra_files=None, exclude_patterns=['*/Timely_venv/*', '*\\Timely_venv\\*'])

