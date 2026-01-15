import requests
import json

def reproduce():
    url = "http://127.0.0.1:5000/generate-timetable"
    
    with open("repro_payload.json", "r") as f:
        data = json.load(f)
        
    try:
        response = requests.post(url, json=data)
        print(f"Status Code: {response.status_code}")
        try:
            resp_json = response.json()
            print("Message:", resp_json.get('message', 'No message'))
        except:
            print("Response Text:")
            print(response.text)
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    reproduce()
