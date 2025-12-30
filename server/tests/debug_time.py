from datetime import datetime

def parse_timeslot(ts_str):
    try:
        parts = ts_str.split('-')
        if len(parts) != 2:
            return 0, 0
        
        start_str = parts[0].strip()
        end_str = parts[1].strip()
        
        fmt = "%I:%M %p"
        start_dt = datetime.strptime(start_str, fmt)
        end_dt = datetime.strptime(end_str, fmt)
        
        start_min = start_dt.hour * 60 + start_dt.minute
        end_min = end_dt.hour * 60 + end_dt.minute
        
        return start_min, end_min
    except Exception as e:
        print(f"Error parsing timeslot '{ts_str}': {e}")
        return 0, 0

ts1 = "11:00 AM - 12:00 PM"
ts2 = "01:00 PM - 02:00 PM"

p1 = parse_timeslot(ts1)
p2 = parse_timeslot(ts2)

print(f"TS1: {p1}")
print(f"TS2: {p2}")
print(f"Gap: {p2[0] - p1[1]}")
