import sys
import os
import json
import unittest

# Add server directory to path so we can import app
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app import app

class TestFacultyBreak(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        self.base_data = {
            "instructors": [{"id": "I1", "name": "Instructor 1"}],
            "rooms": [{"id": "R1", "capacity": 50, "type": "Classroom"}],
            "student_groups": [{"id": "G1", "size": 30, "enrolledCourses": []}],
            "days": ["Monday"],
            "settings": {}
        }

    def test_consecutive_lectures_fail(self):
        """
        Test that two 1-hour lectures cannot be scheduled back-to-back for the same instructor.
        Available slots: 2 (consecutive)
        Required: 2 lectures
        Expected: Failure (No solution)
        """
        data = self.base_data.copy()
        data["courses"] = [
            {"id": "C1", "name": "Course 1", "lectureHours": 1, "labHours": 0, "qualifiedInstructors": ["I1"]},
            {"id": "C2", "name": "Course 2", "lectureHours": 1, "labHours": 0, "qualifiedInstructors": ["I1"]}
        ]
        data["student_groups"][0]["enrolledCourses"] = ["C1", "C2"]
        data["timeslots"] = ["09:00 AM", "10:00 AM"] # Consecutive

        response = self.client.post('/generate-timetable', json=data)
        result = response.get_json()
        
        # Should fail because there's no way to put a gap
        self.assertEqual(result['status'], 'error')
        self.assertIn('No solution', result['message'])

    def test_consecutive_lectures_with_gap_success(self):
        """
        Test that two 1-hour lectures CAN be scheduled if there is a gap.
        Available slots: 3
        Required: 2 lectures
        Expected: Success (Scheduled at T1 and T3)
        """
        data = self.base_data.copy()
        data["courses"] = [
            {"id": "C1", "name": "Course 1", "lectureHours": 1, "labHours": 0, "qualifiedInstructors": ["I1"]},
            {"id": "C2", "name": "Course 2", "lectureHours": 1, "labHours": 0, "qualifiedInstructors": ["I1"]}
        ]
        data["student_groups"][0]["enrolledCourses"] = ["C1", "C2"]
        data["timeslots"] = ["09:00 AM", "10:00 AM", "11:00 AM"] # Gap possible at 10:00

        response = self.client.post('/generate-timetable', json=data)
        result = response.get_json()
        
        self.assertEqual(result['status'], 'success')
        schedule = result['schedule']
        self.assertEqual(len(schedule), 2)
        
        times = sorted([s['timeslot'] for s in schedule])
        self.assertEqual(times, ["09:00 AM", "11:00 AM"])

    def test_continuous_lab_success(self):
        """
        Test that a 2-hour lab CAN be scheduled back-to-back.
        Available slots: 2
        Required: 1 Lab (2 hours)
        Expected: Success
        """
        data = self.base_data.copy()
        data["courses"] = [
            {"id": "L1", "name": "Lab 1", "lectureHours": 0, "labHours": 2, "qualifiedInstructors": ["I1"], "labType": "Computer Lab"}
        ]
        data["rooms"] = [{"id": "R1", "capacity": 50, "type": "Computer Lab"}] # Ensure room is valid for lab
        data["student_groups"][0]["enrolledCourses"] = ["L1"]
        data["timeslots"] = ["09:00 AM", "10:00 AM"] # Consecutive

        response = self.client.post('/generate-timetable', json=data)
        result = response.get_json()
        
        self.assertEqual(result['status'], 'success')
        schedule = result['schedule']
        self.assertEqual(len(schedule), 2)
        
        times = sorted([s['timeslot'] for s in schedule])
        self.assertEqual(times, ["09:00 AM", "10:00 AM"])

if __name__ == '__main__':
    unittest.main()
