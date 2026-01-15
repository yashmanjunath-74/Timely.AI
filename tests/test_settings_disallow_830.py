
import unittest
import json
import sys
import os

# Add server directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '../server'))
from app import app, generate_timetable

class TestSettingsDisallow830(unittest.TestCase):
    def test_disallow_830_labs(self):
        # Setup: A lab that COULD go at 8:30 or 11:00.
        # Use specific timeslots to make it clear.
        data = {
            'days': ['Mon'],
            'timeslots': ['08:30 AM - 09:30 AM', '09:30 AM - 10:30 AM', '11:00 AM - 12:00 PM', '12:00 PM - 01:00 PM'],
            'rooms': [{'id': 'R1', 'capacity': 50, 'type': 'Lab'}],
            'instructors': [{'id': 'I1', 'name': 'Inst1', 'availability': {'Mon': [1, 1, 1, 1]}}],
            'courses': [{'id': 'C1', 'name': 'LabCourse', 'lectureHours': 0, 'labHours': 2, 'qualifiedInstructors': ['I1']}],
            'student_groups': [{
                'id': 'G1', 
                'size': 20, 
                'enrolledCourses': ['C1'],
                'availability': {'Mon': [1, 1, 1, 1]},
                'labTimingPreferences': {} 
            }],
            'settings': {'disallow830Labs': True}  # <--- THE CONSTRAINT
        }
        
        with app.test_request_context(json=data):
             resp = generate_timetable()
             status_code = 200
             if isinstance(resp, tuple):
                 resp, status_code = resp
             
             json_data = resp.get_json()
             self.assertEqual(status_code, 200, f"Should succeed. Msg: {json_data.get('message')}")
             
             schedule = json_data.get('schedule', [])
             lab_tasks = [t for t in schedule if t['courseId'] == 'C1']
             self.assertEqual(len(lab_tasks), 2)
             
             # Verify it did NOT get scheduled at 8:30 start
             # 08:30 start would mean timeslots '08:30 AM - 09:30 AM' and '09:30 AM - 10:30 AM'
             times = [t['timeslot'] for t in lab_tasks]
             
             print(f"DEBUG: Schedule times: {times}")
             self.assertNotIn('08:30 AM - 09:30 AM', times, "Should NOT schedule at 8:30 AM when disallowed")
             self.assertIn('11:00 AM - 12:00 PM', times, "Should have scheduled at 11:00 AM instead")

    def test_disallow_830_fails_if_only_830_available(self):
        # Setup: A lab that ONLY has 8:30 available slots. Should fail.
        data = {
            'days': ['Mon'],
            'timeslots': ['08:30 AM - 09:30 AM', '09:30 AM - 10:30 AM'], # Only 8:30 block
            'rooms': [{'id': 'R1', 'capacity': 50, 'type': 'Lab'}],
            'instructors': [{'id': 'I1', 'name': 'Inst1', 'availability': {'Mon': [1, 1]}}],
            'courses': [{'id': 'C1', 'name': 'LabCourse', 'lectureHours': 0, 'labHours': 2, 'qualifiedInstructors': ['I1']}],
            'student_groups': [{
                'id': 'G1', 
                'size': 20, 
                'enrolledCourses': ['C1'],
                'availability': {'Mon': [1, 1]},
                'labTimingPreferences': {} 
            }],
            'settings': {'disallow830Labs': True}
        }
        
        with app.test_request_context(json=data):
             resp = generate_timetable()
             status_code = 200
             if isinstance(resp, tuple):
                 resp, status_code = resp
             
             # Should fail (likely 400 Bad Request due to validation or solver failure)
             self.assertNotEqual(status_code, 200, "Should FAIL because 8:30 is disallowed and no other slots exist")
             json_data = resp.get_json()
             print(f"DEBUG: Status {status_code}, Msg: {json_data.get('message')}")

if __name__ == '__main__':
    unittest.main()
