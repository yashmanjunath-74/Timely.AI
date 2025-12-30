import unittest
import json
import sys
import os

# Add parent directory to path to import app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app

class TestFacultyAvailability(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        self.base_data = {
            "instructors": [
                {
                    "id": "I1", 
                    "name": "Instructor 1",
                    "availability": {
                        "Monday": [0, 1, 1, 1, 1, 1, 1] # Unavailable at 08:30 AM (index 0)
                    }
                }
            ],
            "rooms": [{"id": "R1", "capacity": 50, "type": "Classroom"}],
            "student_groups": [{"id": "G1", "size": 30, "enrolledCourses": ["C1"]}],
            "courses": [
                {"id": "C1", "name": "Course 1", "lectureHours": 1, "qualifiedInstructors": ["I1"]}
            ],
            "days": ["Monday"],
            "timeslots": [
                "08:30 AM - 09:30 AM", # Index 0
                "09:30 AM - 10:30 AM", # Index 1
                "11:00 AM - 12:00 PM",
                "12:00 PM - 01:00 PM",
                "02:00 PM - 03:00 PM",
                "03:00 PM - 04:00 PM",
                "04:00 PM - 05:00 PM"
            ],
            "settings": {}
        }

    def test_unavailable_slot(self):
        """Test that instructor is NOT assigned to an unavailable slot."""
        # Instructor I1 is unavailable at 08:30 AM (index 0)
        # We request 1 lecture hour. It should be assigned to 09:30 AM (index 1) or later.
        
        response = self.client.post('/generate-timetable', 
                                  data=json.dumps(self.base_data),
                                  content_type='application/json')
        
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'success')
        
        schedule = data['schedule']
        self.assertEqual(len(schedule), 1)
        
        assigned_slot = schedule[0]['timeslot']
        print(f"Assigned slot: {assigned_slot}")
        
        # Should NOT be 08:30 AM
        self.assertNotEqual(assigned_slot, "08:30 AM - 09:30 AM")

    def test_saturday_afternoon_unavailable(self):
        """Test that Saturday afternoon is unavailable if marked so."""
        data = self.base_data.copy()
        data['days'] = ["Saturday"]
        data['instructors'][0]['availability'] = {
            "Saturday": [1, 1, 1, 1, 0, 0, 0] # Unavailable from 02:00 PM onwards (indices 4, 5, 6)
        }
        
        # Add a second course to allow 2 hours on the same day (avoiding "No repeating classes" constraint)
        data['courses'].append(
            {"id": "C2", "name": "Course 2", "lectureHours": 1, "qualifiedInstructors": ["I1"]}
        )
        data['student_groups'][0]['enrolledCourses'] = ["C1", "C2"]
        
        # Request 1 hour for C1 (default) and 1 hour for C2. Total 2 hours.
        # Available slots: 08:30, 09:30, 11:00, 12:00 (4 slots)
        # With break constraint (gap < 60 forbidden), we can pick e.g. 08:30 and 11:00.
        
        response = self.client.post('/generate-timetable', 
                                  data=json.dumps(data),
                                  content_type='application/json')
        
        res_data = json.loads(response.data)
        if res_data['status'] != 'success':
            print(f"DEBUG: Server returned error: {res_data}")
            
        self.assertEqual(res_data['status'], 'success')
        
        schedule = res_data['schedule']
        self.assertEqual(len(schedule), 2)
        
        for item in schedule:
            ts = item['timeslot']
            print(f"Saturday slot: {ts}")
            self.assertNotIn("02:00 PM", ts)
            self.assertNotIn("03:00 PM", ts)
            self.assertNotIn("04:00 PM", ts)

if __name__ == '__main__':
    unittest.main()
