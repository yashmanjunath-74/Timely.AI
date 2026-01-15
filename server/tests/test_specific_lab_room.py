import unittest
import json
import sys
import os

# Add parent directory to path to import app
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app

class TestSpecificLabRoom(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()
        self.base_data = {
            "instructors": [
                {"id": "I1", "name": "Instructor 1", "availability": {"Monday": [1, 1, 1, 1, 1, 1, 1]}}
            ],
            "rooms": [
                {"id": "L1", "capacity": 50, "type": "Computer Lab"},
                {"id": "L2", "capacity": 50, "type": "Computer Lab"}
            ],
            "days": ["Monday"],
            "timeslots": [
                "02:00 PM - 03:00 PM",
                "03:00 PM - 04:00 PM"
            ],
            "student_groups": [
                {
                    "id": "G1", 
                    "size": 30, 
                    "enrolledCourses": ["C1"],
                    "labRoomPreferences": {"C1": "L1"},
                    "availability": {"Monday": [1, 1]}
                }
            ],
            "courses": [
                {"id": "C1", "name": "Lab Course", "labHours": 2, "qualifiedInstructors": ["I1"], "labType": "Computer Lab"}
            ],
            "settings": {}
        }

    def test_specific_room_assignment(self):
        """Test that the specific room is assigned when available."""
        response = self.client.post('/generate-timetable', 
                                  data=json.dumps(self.base_data),
                                  content_type='application/json')
        
        data = json.loads(response.data)
        if data['status'] != 'success':
            print(f"DEBUG LOG: {data.get('debug_log')}")
            print(f"MESSAGE: {data.get('message')}")

        self.assertEqual(data['status'], 'success')
        
        schedule = data['schedule']
        self.assertEqual(len(schedule), 2)
        
        # Both slots should be in L1
        for item in schedule:
            print(f"Task: {item['course']} - Room: {item['room']}")
            self.assertEqual(item['room'], "L1")

    def test_scheduling_fails_if_specific_room_unavailable(self):
        """Test that scheduling fails if the specific room is unavailable, even if another lab is open."""
        # Make L1 unavailable
        data = self.base_data.copy()
        data['rooms'][0]['availability'] = {
            "Monday": [0, 0] # L1 Unavailable
        }
        # L2 is still available!
        
        response = self.client.post('/generate-timetable', 
                                  data=json.dumps(data),
                                  content_type='application/json')
        
        res_data = json.loads(response.data)
        
        # Should fail because L1 is the ONLY allowed room for C1
        self.assertEqual(res_data['status'], 'error')
        # We don't check the specific message, but it should fail.

if __name__ == '__main__':
    unittest.main()
