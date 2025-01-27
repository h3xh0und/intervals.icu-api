import requests
import json
import base64
from datetime import datetime

# Configuration
ATHLETE_ID = "ID"  # Replace with your athlete ID
API_KEY = "API_KEY"        # Replace with your API key
BASE_URL = "https://intervals.icu/api/v1/athlete"
ZONE_TYPE = "HR" #"Pace"
# Encode "API_KEY:api_key" in Base64 for the Authorization header
def encode_auth(api_key):
    token = f"API_KEY:{api_key}".encode("utf-8")
    return base64.b64encode(token).decode("utf-8")

HEADERS = {
    "Authorization": f"Basic {encode_auth(API_KEY)}",
    "Content-Type": "application/json"
}

# Load training data from JSON file
def load_trainings(file_path):
    with open(file_path, "r") as file:
        return json.load(file)

# Convert duration values handling time (m, s) and distance (km)
def convert_duration(duration):
    if "km" in duration:
        return float(duration.replace("km", "")) * 1000  # Convert km to meters
    elif "m" in duration and not duration.endswith("km"):
        return int(duration.replace("m", "")) * 60  # Convert minutes to seconds
    elif "s" in duration:
        return int(duration.replace("s", ""))  # Keep seconds as is
    else:
        return int(duration)  # Default for unknown formats

# Expand repeated intervals into separate blocks
def expand_repeats(steps):
    expanded_steps = []
    for step in steps:
        if "description" in step and step["description"].endswith("x"):
            repeat_count = int(step["description"].replace("x", "").strip())
            for _ in range(repeat_count):
                expanded_steps.extend(steps[steps.index(step) + 1:steps.index(step) + 3])
        elif "duration" in step:
            expanded_steps.append(step)
    return expanded_steps

# Format training data for API submission
def format_training_data(trainings):
    formatted_data = []
    for training in trainings["trainings"]:
        description_lines = []
        expanded_steps = expand_repeats(training["steps"])

        for step in expanded_steps:
            description_lines.append(f"- {step['duration']} in {step['zone']}")
            if "cadence" in step:
                description_lines[-1] += f" ({step['cadence']})"

        formatted_data.append({
            "start_date_local": training["date"] + "T00:00:00",
            "category": "WORKOUT",
            "name": training["name"],
            "description": "\n".join(description_lines).strip(),
            "type": "Ride" if "Bike" in training["name"] else "Run" if "Run" in training["name"] else "Swim",
            "moving_time": sum(
                convert_duration(step["duration"]) for step in expanded_steps
            ),
            "steps": expanded_steps
        })
    return formatted_data

# Upload training data to Intervals.icu
def upload_trainings(data):
    url = f"{BASE_URL}/{ATHLETE_ID}/events/bulk"
    response = requests.post(url, headers=HEADERS, json=data)
    if response.status_code == 200:
        print("Trainings uploaded successfully.")
    else:
        print(f"Failed to upload trainings. Status code: {response.status_code}")
        print(response.text)

# Main function
def main():
    try:
        trainings = load_trainings("trainings.json")
        formatted_data = format_training_data(trainings)
        upload_trainings(formatted_data)
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
