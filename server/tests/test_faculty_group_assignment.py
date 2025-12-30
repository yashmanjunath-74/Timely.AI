import sys
import os
import json
import unittest
import copy

# Add server directory to path so we can import app
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app import app

class TestFacultyGroupAssignment(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        self.base_data = {
            "instructors": [
                {"id": "I1", "name": "Instructor 1"},
                {"id": "I2", "name": "Instructor 2"}
            ],
            "rooms": [{"id": "R1", "capacity": 50, "type": "Classroom"}],
            "student_groups": [
                {"id": "G1", "size": 30, "enrolledCourses": ["C1"], "instructorPreferences": {}}
            ],
            "courses": [
                {"id": "C1", "name": "Course 1", "lectureHours": 1, "labHours": 0, "qualifiedInstructors": ["I1", "I2"]}
            ],
            "days": ["Monday"],
            "timeslots": ["09:00 AM"],
            "settings": {}
        }

    def test_specific_faculty_assignment(self):
        """
        Test that if a group prefers I2 for C1, I2 is assigned even if I1 is available.
        """
        data = copy.deepcopy(self.base_data)
        # Set preference for I2
        data["student_groups"][0]["instructorPreferences"] = {"C1": "I2"}

        response = self.client.post('/generate-timetable', json=data)
        result = response.get_json()
        
        self.assertEqual(result['status'], 'success')
        schedule = result['schedule']
        self.assertEqual(len(schedule), 1)
        
        # Check that the assigned instructor is I2
        self.assertEqual(schedule[0]['instructor'], "Instructor 2")

    def test_preference_conflict(self):
        """
        Test that if two groups prefer the SAME instructor for the SAME time, it handles it (either by moving one to another time, or failing if no time).
        Here we force them to clash by having only 1 timeslot.
        """
        data = copy.deepcopy(self.base_data)
        # Add another group G2
        data["student_groups"].append(
            {"id": "G2", "size": 30, "enrolledCourses": ["C1"], "instructorPreferences": {"C1": "I1"}}
        )
        # G1 also prefers I1
        data["student_groups"][0]["instructorPreferences"] = {"C1": "I1"}
        
        response = self.client.post('/generate-timetable', json=data)
        result = response.get_json()
        
        self.assertEqual(result['status'], 'error', f"Expected error but got success. Schedule: {result.get('schedule')}")
        self.assertIn('No solution', result['message'])

    def test_preference_resolution_with_slots(self):
        """
        Same as above but with 2 slots. Both should get I1 at different times.
        """
        data = copy.deepcopy(self.base_data)
        data["timeslots"] = ["09:00 AM", "10:00 AM"]
        
        data["student_groups"].append(
            {"id": "G2", "size": 30, "enrolledCourses": ["C1"], "instructorPreferences": {"C1": "I1"}}
        )
        data["student_groups"][0]["instructorPreferences"] = {"C1": "I1"}
        
        response = self.client.post('/generate-timetable', json=data)
        result = response.get_json()
        
        self.assertEqual(result['status'], 'success')
        schedule = result['schedule']
        self.assertEqual(len(schedule), 2)
        
        # Both should be taught by I1
        instructors = [s['instructor'] for s in schedule]
        self.assertEqual(instructors, ["Instructor 1", "Instructor 1"])
        
        # Times should be different
        times = [s['timeslot'] for s in schedule]
        self.assertNotEqual(times[0], times[1])

if __name__ == '__main__':
    unittest.main()
