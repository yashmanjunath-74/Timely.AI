import sys
import os
import json
import copy

# Add server directory to path so we can import app
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from app import app

def get_base_data():
    return {
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

def test_specific_faculty_assignment():
    print("Running test_specific_faculty_assignment...")
    client = app.test_client()
    data = copy.deepcopy(get_base_data())
    # Set preference for I2
    data["student_groups"][0]["instructorPreferences"] = {"C1": "I2"}

    response = client.post('/generate-timetable', json=data)
    result = response.get_json()
    
    assert result['status'] == 'success'
    schedule = result['schedule']
    assert len(schedule) == 1
    assert schedule[0]['instructor'] == "Instructor 2"
    print("PASS")

def test_preference_conflict():
    print("Running test_preference_conflict...")
    client = app.test_client()
    data = copy.deepcopy(get_base_data())
    # Add another group G2
    data["student_groups"].append(
        {"id": "G2", "size": 30, "enrolledCourses": ["C1"], "instructorPreferences": {"C1": "I1"}}
    )
    # G1 also prefers I1
    data["student_groups"][0]["instructorPreferences"] = {"C1": "I1"}
    
    response = client.post('/generate-timetable', json=data)
    result = response.get_json()
    
    if result['status'] == 'success':
        print("FAIL: Expected error but got success.")
        print("Schedule:", result.get('schedule'))
        sys.exit(1)
    
    assert result['status'] == 'error'
    assert 'No solution' in result['message']
    print("PASS")

def test_preference_resolution_with_slots():
    print("Running test_preference_resolution_with_slots...")
    client = app.test_client()
    data = copy.deepcopy(get_base_data())
    # Use 3 slots to allow a gap (09:00, 10:00, 11:00)
    # The code treats adjacent indices as consecutive, so we need an intermediate slot.
    data["timeslots"] = ["09:00 AM", "10:00 AM", "11:00 AM"]
    
    data["student_groups"].append(
        {"id": "G2", "size": 30, "enrolledCourses": ["C1"], "instructorPreferences": {"C1": "I1"}}
    )
    data["student_groups"][0]["instructorPreferences"] = {"C1": "I1"}
    
    response = client.post('/generate-timetable', json=data)
    result = response.get_json()
    
    assert result['status'] == 'success'
    schedule = result['schedule']
    assert len(schedule) == 2
    
    instructors = [s['instructor'] for s in schedule]
    assert instructors == ["Instructor 1", "Instructor 1"]
    
    times = [s['timeslot'] for s in schedule]
    assert times[0] != times[1]
    print("PASS")

if __name__ == '__main__':
    try:
        test_specific_faculty_assignment()
        test_preference_conflict()
        test_preference_resolution_with_slots()
        print("\nALL TESTS PASSED")
    except Exception as e:
        import traceback
        traceback.print_exc()
        sys.exit(1)
