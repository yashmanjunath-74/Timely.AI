
import json
import requests
import sys
import os

# Add server directory to path
sys.path.append(os.path.join(os.path.dirname(__file__), '../server'))
from app import app, generate_timetable

def run_repro():
    with open('tests/repro_data.json', 'r') as f:
        data = json.load(f)
    
    # Add days and timeslots if missing (inferred from arrays)
    if 'days' not in data:
        data['days'] = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    if 'timeslots' not in data:
        # User arrays have 7 slots (Mon-Fri) and 7 slots (Sat? No Sat has 0,0,0 at end).
        # Mon: [1, 1, 1, 1, 1, 1, 0] -> 7 slots.
        # Implied Timeslots: 
        # 0: 08:30 - 09:30
        # 1: 09:30 - 10:30
        # 2: 11:00 - 12:00
        # 3: 12:00 - 01:00
        # 4: 02:00 - 03:00
        # 5: 03:00 - 04:00
        # 6: 04:00 - 05:00
        data['timeslots'] = [
            "08:30 AM - 09:30 AM",
            "09:30 AM - 10:30 AM",
            "11:00 AM - 12:00 PM",
            "12:00 PM - 01:00 PM",
            "02:00 PM - 03:00 PM",
            "03:00 PM - 04:00 PM",
            "04:00 PM - 05:00 PM"
        ]

    print(f"Running repro with Disallow 8:30 Labs = {data['settings'].get('disallow830Labs')}")
    
    with app.test_request_context(json=data):
             resp = generate_timetable()
             status_code = 200
             if isinstance(resp, tuple):
                 resp, status_code = resp
             
             json_data = resp.get_json()
             print(f"Status Code: {status_code}")
             if status_code != 200:
                 print(f"Error Message: {json_data.get('message')}")
                 # Check logic
                 msg = json_data.get('message')
                 if "No solution found" in msg:
                    print("SUCCESS: Reproduced 'No solution found' error.")
                 else:
                    print("Unexpected error message.")
             else:
                 print("SUCCESS: Scheduling SUCCEEDED (Issue NOT reproduced?)")

if __name__ == '__main__':
    run_repro()
