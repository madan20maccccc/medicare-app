import json
import os

MEDICINE_DATA_FILE = "medicines_combined.json"
file_path = os.path.join(os.path.dirname(__file__), MEDICINE_DATA_FILE)

print(f"Attempting to load: {file_path}")

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(f"Successfully loaded {len(data)} items from {MEDICINE_DATA_FILE}.")
    # Optional: Print a small part to confirm structure
    # print(data[0])
except FileNotFoundError:
    print(f"ERROR: File not found at {file_path}. Please ensure it's in the same directory.")
except json.JSONDecodeError as e:
    print(f"JSON DECODE ERROR in {MEDICINE_DATA_FILE}: {e}")
    print(f"Error at line {e.lineno}, column {e.colno}")
    # You can try to read around the error for more context
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        start_line = max(0, e.lineno - 5)
        end_line = min(len(lines), e.lineno + 5)
        print("\n--- Context around error ---")
        for i in range(start_line, end_line):
            print(f"{i+1}: {lines[i].strip()}")
        print("----------------------------")
except Exception as e:
    print(f"An unexpected error occurred: {e}")