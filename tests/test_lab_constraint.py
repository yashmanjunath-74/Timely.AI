import sys
import os
# Adjust path to import from server directory
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../server')))

from flask import Flask
from app import app, generate_timetable
import unittest
from unittest.mock import patch, MagicMock

class TestLabConstraint(unittest.TestCase):
    def test_fragmented_lab_fail(self):
        # Data: 1 Group, 1 Course (Lab 2h), 1 Instructor.
        # Availability: [1, 0, 1, 0] (Fragmented)
        # Should fail with my new error message.
        
        data = {
            'days': ['Mon'],
            'timeslots': ['09:00 AM - 10:00 AM', '10:00 AM - 11:00 AM', '11:00 AM - 12:00 PM', '12:00 PM - 01:00 PM'], # 4 slots
            'rooms': [{'id': 'R1', 'capacity': 50, 'type': 'Lab'}],
            'instructors': [{'id': 'I1', 'name': 'Inst1', 'availability': {'Mon': [1, 1, 1, 1]}}],
            'courses': [{'id': 'C1', 'name': 'LabCourse', 'lectureHours': 0, 'labHours': 2, 'qualifiedInstructors': ['I1']}],
            'student_groups': [{
                'id': 'G1', 
                'size': 20, 
                'enrolledCourses': ['C1'],
                'availability': {'Mon': [1, 0, 1, 0]} # Fragmented! No consecutive slots.
            }],
            'settings': {}
        }
        
        with app.test_request_context(json=data):
            try:
                response = generate_timetable()
                # generate_timetable returns (response, status) or response
                if isinstance(response, tuple):
                    resp_obj, status_code = response
                    json_data = resp_obj.get_json()
                else:
                    json_data = response.get_json()
                    status_code = response.status_code

                print(f"Response: {json_data}")
                self.assertEqual(status_code, 400)
                self.assertIn("consecutive slots", json_data['message'])
            except Exception as e:
                self.fail(f"Generate Timetable raised exception: {e}")

if __name__ == '__main__':
    unittest.main()
