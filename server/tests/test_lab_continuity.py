import sys
import os
import json
import unittest
import copy

sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from app import app

class TestLabContinuity(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        self.base_data = {
            "instructors": [{"id": "I1", "name": "Instructor 1"}],
            "rooms": [
                {"id": "R1", "capacity": 50, "type": "Computer Lab"},
                {"id": "R2", "capacity": 50, "type": "Classroom"}
            ],
            "student_groups": [{"id": "G1", "size": 30, "enrolledCourses": []}],
            "courses": [],
            "days": ["Monday"],
            "timeslots": [
                "09:00 AM - 10:00 AM", # T0
                "10:00 AM - 11:00 AM", # T1 (Continuous with T0)
                "11:00 AM - 12:00 PM", # T2 (Continuous with T1)
                "01:00 PM - 02:00 PM", # T3 (1 hour gap after T2)
                "02:00 PM - 03:00 PM"  # T4 (Continuous with T3)
            ],
            "settings": {}
        }

    def test_lab_continuity_across_gap(self):
        """
        Test that a 2-hour lab CANNOT span the gap between T2 and T3.
        """
        data = copy.deepcopy(self.base_data)
        data["courses"] = [
            {"id": "L1", "name": "Lab 1", "lectureHours": 0, "labHours": 2, "qualifiedInstructors": ["I1"], "labType": "Computer Lab"}
        ]
        data["student_groups"][0]["enrolledCourses"] = ["L1"]
        
        # Force assignments to T2 and T3? 
        # We can't easily force it, but we can check if the solver produces it.
        # Actually, if we only give T2 and T3 as available slots (by blocking others), we can test it.
        # But blocking is hard.
        # Instead, let's rely on the solver finding a valid solution.
        # If we provide ONLY T2 and T3, it should FAIL.
        data["timeslots"] = ["11:00 AM - 12:00 PM", "01:00 PM - 02:00 PM"]
        
        response = self.client.post('/generate-timetable', json=data)
        result = response.get_json()
        
        # Should fail because they are not continuous
        self.assertEqual(result['status'], 'error', "Lab spanned a gap!")

    def test_faculty_break_with_gap(self):
        """
        Test that faculty CAN teach T2 and T3 back-to-back because there is a 1-hour gap (Lunch).
        Current logic might forbid this because they are adjacent in the list.
        """
        data = copy.deepcopy(self.base_data)
        data["courses"] = [
            {"id": "C1", "name": "Course 1", "lectureHours": 1, "labHours": 0, "qualifiedInstructors": ["I1"]},
            {"id": "C2", "name": "Course 2", "lectureHours": 1, "labHours": 0, "qualifiedInstructors": ["I1"]}
        ]
        data["student_groups"][0]["enrolledCourses"] = ["C1", "C2"]
        # Provide ONLY T2 and T3.
        data["timeslots"] = ["11:00 AM - 12:00 PM", "01:00 PM - 02:00 PM"]
        
        response = self.client.post('/generate-timetable', json=data)
        result = response.get_json()
        
        # Should SUCCESS because the gap is 1 hour.
        # If it fails, it means our logic is too strict.
        self.assertEqual(result['status'], 'success', "Faculty break constraint blocked valid lunch gap!")

if __name__ == '__main__':
    unittest.main()
