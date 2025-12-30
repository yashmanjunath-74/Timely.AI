import requests
import json

BASE_URL = 'http://127.0.0.1:5000'

def test_lab_limit():
    print("Testing One Lab Per Day Constraint...")
    
    # 1. Setup Data:
    # 1 Student Group
    # 2 Lab Courses (Physics, Chemistry)
    # 2 Days (Mon, Tue)
    # Each lab is 2 hours.
    
    payload = {
        "instructors": [
            {"id": "inst1", "name": "Physics Prof", "availability": {"Monday": [1]*10, "Tuesday": [1]*10}}, 
            {"id": "inst2", "name": "Chem Prof", "availability": {"Monday": [1]*10, "Tuesday": [1]*10}}
        ],
        "courses": [
            {"id": "c1", "name": "Physics Lab", "lectureHours": 0, "labHours": 2, "qualifiedInstructors": ["inst1"]},
            {"id": "c2", "name": "Chem Lab", "lectureHours": 0, "labHours": 2, "qualifiedInstructors": ["inst2"]}
        ],
        "rooms": [
            {"id": "r1", "name": "Lab Room", "capacity": 30, "type": "Lab"}
        ],
        "student_groups": [
            {"id": "sg1", "size": 20, "enrolledCourses": ["c1", "c2"]}
        ],
        "days": ["Monday", "Tuesday"],
        "timeslots": ["09:00 AM - 10:00 AM", "10:00 AM - 11:00 AM", "11:00 AM - 12:00 PM", "12:00 PM - 01:00 PM"],
        "settings": {}
    }

    try:
        response = requests.post(f'{BASE_URL}/generate-timetable', json=payload)
        if response.status_code == 200:
            result = response.json()
            schedule = result.get('schedule', [])
            print(f"Generated schedule with {len(schedule)} items.")
            
            # Check correctness
            # Group assignments by day
            assignments_by_day = {}
            for item in schedule:
                day = item['day']
                c_id = item['courseId']
                if day not in assignments_by_day:
                    assignments_by_day[day] = set()
                assignments_by_day[day].add(c_id)
            
            failed = False
            for day, courses in assignments_by_day.items():
                if len(courses) > 1:
                    print(f"FAILURE: Group has {len(courses)} labs on {day}: {courses}")
                    failed = True
                else:
                    print(f"Success: {day} has {len(courses)} lab: {courses}")
            
            if not failed:
                print("TEST PASSED: No student group has >1 lab per day.")
            else:
                print("TEST FAILED.")

        else:
            print(f"Request failed: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Exception: {e}")

if __name__ == "__main__":
    test_lab_limit()
