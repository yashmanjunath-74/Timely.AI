import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../server')))

from flask import Flask
from app import app, generate_timetable
import unittest

class TestLabSpecificTimes(unittest.TestCase):
    def test_specific_time_enforcement_11_to_1(self):
        # Setup: "11:00 AM - 1:00 PM"
        # Timeslots: 10:00-11:00 (600), 11:00-12:00 (660), 12:00-1:00 (720), 1:00-2:00 (780)
        # 11:00 start is 660.
        
        data = {
            'days': ['Mon'],
            'timeslots': [
                '10:00 AM - 11:00 AM', 
                '11:00 AM - 12:00 PM', 
                '12:00 PM - 01:00 PM', 
                '01:00 PM - 02:00 PM'
            ],
            'rooms': [{'id': 'R1', 'capacity': 50, 'type': 'Lab'}],
            'instructors': [{'id': 'I1', 'name': 'Inst1', 'availability': {'Mon': [1, 1, 1, 1]}}],
            'courses': [{'id': 'C1', 'name': 'LabCourse', 'lectureHours': 0, 'labHours': 2, 'qualifiedInstructors': ['I1']}],
            'student_groups': [{
                'id': 'G1', 
                'size': 20, 
                'enrolledCourses': ['C1'],
                'availability': {'Mon': [1, 1, 1, 1]},
                'labTimingPreferences': {'C1': '11:00 AM - 1:00 PM'} # Prefers 11:00 start (660)
            }],
            'settings': {}
        }
        
        # Case 1: Instructor Unavailable at 11:00 (Index 1)
        data['instructors'][0]['availability']['Mon'] = [1, 0, 1, 1]
        
        with app.test_request_context(json=data):
            resp = generate_timetable()
            status_code = 200
            if isinstance(resp, tuple):
                resp, status_code = resp
            
            with open("debug_run.log", "a") as f:
                f.write(f"DEBUG TEST 1: Status {status_code}\n")
                f.write(f"DEBUG TEST 1: Body {resp.get_json()}\n")
            
            self.assertEqual(status_code, 400)
            self.assertIn("no assigned instructor", resp.get_json()['message'])

    def test_specific_time_heuristic_2_to_4(self):
        # Test "2 to 4" (2:00 PM = 840)
        # Timeslots starting: 1 (780), 2 (840), 3 (900)
        data = {
            'days': ['Mon'],
            'timeslots': [
                '01:00 PM - 02:00 PM', 
                '02:00 PM - 03:00 PM', 
                '03:00 PM - 04:00 PM',
            ],
            'rooms': [{'id': 'R1', 'capacity': 50, 'type': 'Lab'}],
            'instructors': [{'id': 'I1', 'name': 'Inst1', 'availability': {'Mon': [1, 1, 1]}}],
            'courses': [{'id': 'C1', 'name': 'LabCourse', 'lectureHours': 0, 'labHours': 2, 'qualifiedInstructors': ['I1']}],
            'student_groups': [{
                'id': 'G1', 
                'size': 20,
                'enrolledCourses': ['C1'],
                'availability': {'Mon': [1, 1, 1]},
                'labTimingPreferences': {'C1': '2 to 4'} # Should map to 840 (Index 1)
            }],
            'settings': {}
        }
        
        # Make 2:00 unavailable (index 1)
        data['instructors'][0]['availability']['Mon'] = [1, 0, 1]
             
        with app.test_request_context(json=data):
             resp = generate_timetable()
             status_code = 200
             if isinstance(resp, tuple):
                 resp, status_code = resp
             
             with open("debug_run.log", "a") as f:
                 f.write(f"DEBUG TEST 2: Status {status_code}\n")
                 f.write(f"DEBUG TEST 2: Body {resp.get_json()}\n")
                 
             self.assertEqual(status_code, 400, "Should fail if preferred slot 2:00 is unavailable")
             self.assertIn("no assigned instructor", resp.get_json()['message'])

    def test_specific_time_allocation_success(self):
        # Verify it actually allocates the slot if valid
        data = {
            'days': ['Mon'],
            'timeslots': ['10:00 AM - 11:00 AM', '11:00 AM - 12:00 PM', '12:00 PM - 01:00 PM'],
            'rooms': [{'id': 'R1', 'capacity': 50, 'type': 'Lab'}],
            'instructors': [{'id': 'I1', 'name': 'Inst1', 'availability': {'Mon': [1, 1, 1]}}],
            'courses': [{'id': 'C1', 'name': 'LabCourse', 'lectureHours': 0, 'labHours': 2, 'qualifiedInstructors': ['I1']}],
            'student_groups': [{
                'id': 'G1', 
                'size': 20, 
                'enrolledCourses': ['C1'],
                'availability': {'Mon': [1, 1, 1]},
                'labTimingPreferences': {'C1': '11:00 AM - 1:00 PM'} # Prefers 11:00 start (Index 1)
            }],
            'settings': {}
        }
        
        with app.test_request_context(json=data):
             resp = generate_timetable()
             status_code = 200
             if isinstance(resp, tuple):
                 resp, status_code = resp
             
             json_data = resp.get_json()
             self.assertEqual(status_code, 200, f"Should succeed. Msg: {json_data.get('message')}")
             
             schedule = json_data.get('schedule', [])
             # Find the lab tasks
             lab_tasks = [t for t in schedule if t['courseId'] == 'C1']
             self.assertEqual(len(lab_tasks), 2)
             
             # Verify timeslots
             times = [t['timeslot'] for t in lab_tasks]
             self.assertIn('11:00 AM - 12:00 PM', times)
             self.assertIn('12:00 PM - 01:00 PM', times)

if __name__ == '__main__':
    # Clear log
    with open("debug_run.log", "w") as f: f.write("")
    unittest.main()
