import unittest
import json
import sys
import os

# Add parent directory to path to import app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app

class TestCommonRoom(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        self.base_data = {
            "instructors": [
                {"id": "I1", "name": "Instructor 1"},
                {"id": "I2", "name": "Instructor 2"}
            ],
            "rooms": [
                {"id": "R1", "capacity": 50, "type": "Classroom"}, # Preferred
                {"id": "R2", "capacity": 50, "type": "Classroom"}  # Backup
            ],
            "days": ["Monday"],
            "timeslots": [
                "08:30 AM - 09:30 AM",
                "09:30 AM - 10:30 AM"
            ],
            # Setup Group 1 with preferred room R1
            "student_groups": [
                {
                    "id": "G1", 
                    "size": 30, 
                    "enrolledCourses": ["C1", "C2"],
                    "preferredRoomId": "R1"
                }
            ],
            "courses": [
                {"id": "C1", "name": "Course 1", "lectureHours": 1, "qualifiedInstructors": ["I1"]},
                {"id": "C2", "name": "Course 2", "lectureHours": 1, "qualifiedInstructors": ["I2"]}
            ],
            "settings": {}
        }

    def test_preferred_room_assignment(self):
        """Test that the preferred room is assigned when available."""
        response = self.client.post('/generate-timetable', 
                                  data=json.dumps(self.base_data),
                                  content_type='application/json')
        
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'success')
        
        schedule = data['schedule']
        self.assertEqual(len(schedule), 2)
        
        # Both slots should be in R1
        for item in schedule:
            print(f"Task: {item['course']} - Room: {item['room']}")
            self.assertEqual(item['room'], "R1")

    def test_fallback_room_assignment(self):
        """Test that it falls back to another room if preferred room is unavailable."""
        # Make R1 unavailable on Monday by using room availability
        data = self.base_data.copy()
        data['rooms'][0]['availability'] = {
            "Monday": [0, 0] # Unavailable for both slots
        }
        
        response = self.client.post('/generate-timetable', 
                                  data=json.dumps(data),
                                  content_type='application/json')
        
        res_data = json.loads(response.data)
        self.assertEqual(res_data['status'], 'success')

        
        schedule = res_data['schedule']
        self.assertEqual(len(schedule), 2)
        
        # Should be in R2 because R1 is unavailable
        for item in schedule:
            print(f"Fallback Task: {item['course']} - Room: {item['room']}")
            self.assertEqual(item['room'], "R2")

if __name__ == '__main__':
    unittest.main()
