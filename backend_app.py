# backend_app.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict
import uvicorn
import re
import json
import os # For checking file existence
from transformers import AutoTokenizer, AutoModelForTokenClassification, pipeline
import torch # Required by transformers[torch]
from rapidfuzz import fuzz # Using rapidfuzz for string similarity

# --- Model Loading and Data Loading ---
# Path to your fine-tuned BioBERT model (if you've trained it)
FINE_TUNED_MODEL_PATH = "./fine_tuned_biobert_model"
tokenizer = None
model = None
nlp_pipeline = None # Hugging Face pipeline for easier NER

# Using d4data/biomedical-ner-all, which is a general biomedical NER model
GENERIC_BIOBERT_MODEL = "d4data/biomedical-ner-all" 

try:
    if os.path.exists(FINE_TUNED_MODEL_PATH):
        print(f"Attempting to load fine-tuned BioBERT tokenizer and model from local path: {FINE_TUNED_MODEL_PATH}...")
        tokenizer = AutoTokenizer.from_pretrained(FINE_TUNED_MODEL_PATH)
        model = AutoModelForTokenClassification.from_pretrained(FINE_TUNED_MODEL_PATH)
        nlp_pipeline = pipeline("ner", model=model, tokenizer=tokenizer, aggregation_strategy="simple")
        print("SUCCESS: Fine-tuned BioBERT model and tokenizer loaded.")
    else:
        print(f"INFO: Fine-tuned model not found at {FINE_TUNED_MODEL_PATH}.")
        print(f"Attempting to download/load pre-trained NER model from Hugging Face Hub: {GENERIC_BIOBERT_MODEL}...")
        tokenizer = AutoTokenizer.from_pretrained(GENERIC_BIOBERT_MODEL)
        model = AutoModelForTokenClassification.from_pretrained(GENERIC_BIOBERT_MODEL)
        nlp_pipeline = pipeline("ner", model=model, tokenizer=tokenizer, aggregation_strategy="simple")
        print(f"SUCCESS: NER model '{GENERIC_BIOBERT_MODEL}' loaded.")

except Exception as e:
    print(f"CRITICAL ERROR: Failed to load any BioBERT model.")
    print(f"This often indicates a network issue, firewall blocking Hugging Face, or insufficient memory/GPU resources.")
    print(f"Please ensure you have a stable internet connection and no firewalls/proxies are blocking access to 'huggingface.co'.")
    print(f"Also, consider if other large models are running simultaneously.")
    print(f"Detailed error: {e}")
    print("Medicine extraction will fall back to basic keyword matching and regex.")
    tokenizer = None
    model = None
    nlp_pipeline = None

# --- Load medicine data from JSON file ---
MEDICINE_DATA_FILE = "medicines_combined.json" # Corrected filename
LOADED_MEDICINE_NAMES: List[str] = []
LOADED_MEDICINE_NAMES_LOWER_SET: set = set() # For faster lookup of lowercased names

def load_medicine_names():
    global LOADED_MEDICINE_NAMES, LOADED_MEDICINE_NAMES_LOWER_SET
    if not os.path.exists(MEDICINE_DATA_FILE):
        print(f"ERROR: {MEDICINE_DATA_FILE} not found in the backend directory.")
        print("Please ensure you have copied 'medicines_combined.json' from your Flutter assets to the 'medicare_backend' folder.")
        return []

    try:
        with open(MEDICINE_DATA_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            names_to_load = []
            for item in data:
                if 'name' in item and isinstance(item['name'], str):
                    names_to_load.append(item['name'].strip())
                
                # Extract core medicine name from 'strength' field
                if 'strength' in item and isinstance(item['strength'], str):
                    # Regex to find the main medicine name before dosage/form in strength
                    # e.g., "Paracetamol (500mg)" -> "Paracetamol"
                    # e.g., "Cetirizine 10mg" -> "Cetirizine"
                    strength_match = re.match(r'([A-Za-z\s]+?)(?:\s*\(?\d+.*|\s+\d+.*|$)', item['strength'].strip())
                    if strength_match:
                        core_name = strength_match.group(1).strip()
                        if core_name and core_name.lower() not in LOADED_MEDICINE_NAMES_LOWER_SET: # Avoid duplicates
                            names_to_load.append(core_name)
            
            # Remove duplicates and sort for consistency (optional, but good for debugging)
            unique_names = sorted(list(set(names_to_load)))
            
            LOADED_MEDICINE_NAMES = unique_names
            LOADED_MEDICINE_NAMES_LOWER_SET = {n.lower() for n in unique_names} # Populate the set for quick lowercase lookups
            
            print(f"Successfully loaded {len(LOADED_MEDICINE_NAMES)} unique medicine names from {MEDICINE_DATA_FILE}.")
            if "paracetamol" in LOADED_MEDICINE_NAMES_LOWER_SET:
                print("DEBUG: 'Paracetamol' (lowercase) IS found in loaded medicine names set.")
            else:
                print("DEBUG: 'Paracetamol' (lowercase) NOT found in loaded medicine names set. Check JSON 'strength' field extraction.")
            return LOADED_MEDICINE_NAMES
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse {MEDICINE_DATA_FILE}. Ensure it's valid JSON. Error: {e}")
        return []
    except Exception as e:
        print(f"ERROR: An unexpected error occurred while loading {MEDICINE_DATA_FILE}: {e}")
        return []

# Load medicines when the app starts
LOADED_MEDICINE_NAMES = load_medicine_names()

# --- Adaptive Learning: In-memory storage for feedback ---
LEARNED_FEEDBACK: List[Dict] = []

app = FastAPI(
    title="Medicare Medicine Extraction Backend",
    description="API for extracting medicine prescriptions and providing suggestions using a custom ML model.",
    version="1.0.0"
)

# --- Pydantic Models ---
class MedicineDetail(BaseModel): # Matches MedicinePrescription in Flutter
    name: str
    dosage: str
    duration: str
    frequency: str
    timing: str

class MedicineRequest(BaseModel):
    text: str

class MedicineResponse(BaseModel):
    name: str
    dosage: str
    duration: str
    frequency: str
    timing: str

class SuggestionRequest(BaseModel):
    input_text: str
    patient_summary: str

class SuggestionResponse(BaseModel):
    suggestion: str

class FeedbackRequest(BaseModel):
    original_text: str
    corrected_medicines: List[MedicineDetail]

# --- Helper Functions for Regex Extraction (used after name identification) ---

# Mapping for common spelled-out numbers to digits
NUMBER_WORDS = {
    'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
    'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
    'eleven': '11', 'twelve': '12', 'thirteen': '13', 'fourteen': '14', 'fifteen': '15',
    'sixteen': '16', 'seventeen': '17', 'eighteen': '18', 'nineteen': '19', 'twenty': '20',
    'thirty': '30', 'forty': '40', 'fifty': '50', 'sixty': '60', 'seventy': '70',
    'eighty': '80', 'ninety': '90', 'hundred': '100', 'thousand': '1000',
    'half': '0.5' # For dosages like "half tablet"
}

def word_to_num(text_segment):
    """Converts a string segment containing spelled-out numbers to digits.
    Handles simple single words and common two-word numbers like "six fifty".
    """
    text_segment_lower = text_segment.lower().strip()
    
    # Direct mapping for single words
    if text_segment_lower in NUMBER_WORDS:
        return NUMBER_WORDS[text_segment_lower]

    # Handle compound numbers like "six fifty" -> "650"
    parts = text_segment_lower.split()
    if len(parts) == 2:
        if parts[0] in NUMBER_WORDS and parts[1] in NUMBER_WORDS:
            try:
                val1 = float(NUMBER_WORDS[parts[0]])
                val2 = float(NUMBER_WORDS[parts[1]])
                # Heuristic: if first number is <100 and second is >=10, it's likely a combination like "six fifty"
                if val1 < 100 and val2 >= 10:
                    return str(int(val1 * 100 + val2)) # e.g., 6 * 100 + 50 = 650
            except ValueError:
                pass # Not convertible to number
    
    # Fallback: Try to parse as a float if it contains digits
    try:
        if re.match(r'^\d+(\.\d+)?$', text_segment_lower):
            return text_segment_lower
    except ValueError:
        pass

    return text_segment # Return original if no conversion happened

def _extract_dosage(text: str) -> str:
    # Pattern for numbers (digits or spelled out)
    num_pattern = r'(?:(?:\d+(?:\.\d+)?)|' + r'|'.join(NUMBER_WORDS.keys()) + r')'
    
    # Units pattern
    units_pattern = r'(?:mg|g|ml|mcg|unit|tablet|pill|capsule|spoon(?:ful)?|units?|tabs?|caps?|bottles?|vials?|sachets?|pouches?|drops?|puffs?|sprays?|inhalations?|patches?|ml|drops|units|tabs|caps|bottles|vials|sachets|pouches|puffs|sprays|inhalations|patches)\b'
    
    # Try to find a number followed by a unit (e.g., "50 mg", "two tablets", "six fifty mg")
    # This pattern tries to capture multi-word numbers like "six fifty"
    regex = re.search(rf'({num_pattern}(?:\s*{num_pattern})*\s*{units_pattern})', text, re.IGNORECASE)
    if regex:
        matched_str = regex.group(0).strip() # Get the full matched string
        
        # Extract the numerical part to convert it
        num_part_match = re.search(rf'({num_pattern}(?:\s*{num_pattern})*)', matched_str, re.IGNORECASE)
        unit_part_match = re.search(units_pattern, matched_str, re.IGNORECASE)
        
        if num_part_match and unit_part_match:
            converted_value = word_to_num(num_part_match.group(0))
            return f"{converted_value} {unit_part_match.group(0).strip()}"
        return matched_str # Fallback if parts not found
    
    # Fallback: Just a number that might be a dosage (e.g., "paracetamol 650")
    # Look for a number pattern that is not necessarily followed by a unit, but is a standalone number
    regex_just_num = re.search(rf'(\b{num_pattern}(?:\s*{num_pattern})*\b)', text, re.IGNORECASE)
    if regex_just_num:
        converted_value = word_to_num(regex_just_num.group(0))
        # Only append "mg" as a common default if no unit was explicitly found nearby
        # This is a heuristic, adjust if it causes false positives
        if not re.search(units_pattern, text, re.IGNORECASE): # Check entire text for units
            return f"{converted_value} mg" 
        return converted_value # Return just the number if a unit was present but not captured by main regex
    
    return 'N/A'

def _extract_duration(text: str) -> str:
    # Captures number + time unit (days, weeks, months, years, hours)
    num_pattern = r'(?:(?:\d+(?:\.\d+)?)|' + r'|'.join(NUMBER_WORDS.keys()) + r')'
    duration_units = r'(?:day|week|month|year|hr|hour)s?'
    regex = re.search(rf'(?:for\s+)?({num_pattern}(?:\s*{num_pattern})*\s*{duration_units})\b', text, re.IGNORECASE)
    if regex:
        matched_str = regex.group(0).strip()
        num_part_match = re.search(rf'({num_pattern}(?:\s*{num_pattern})*)', matched_str, re.IGNORECASE)
        unit_part_match = re.search(duration_units, matched_str, re.IGNORECASE)
        if num_part_match and unit_part_match:
            converted_value = word_to_num(num_part_match.group(0))
            return f"{converted_value} {unit_part_match.group(0).strip()}"
        return matched_str
    
    return 'N/A'

def _extract_frequency(text: str) -> str:
    # Captures common frequency terms and abbreviations
    num_pattern = r'(?:(?:\d+(?:\.\d+)?)|' + r'|'.join(NUMBER_WORDS.keys()) + r')'
    frequency_terms = r'(twice daily|once a day|thrice daily|three times a day|four times a day|daily|every\s+' + num_pattern + r'\s*hours|b\.?d\.?|t\.?i\.?d\.?|o\.?d\.?|q\.?i\.?d\.?|bd|tid|od|qid|bid|tds|qds|qd|prn|stat|as needed|every other day|alternate day|weekly|monthly|once)\b'
    regex = re.search(frequency_terms, text, re.IGNORECASE)
    if regex:
        matched_str = regex.group(0).strip()
        # If it contains a number word, try to convert it
        num_match = re.search(num_pattern, matched_str, re.IGNORECASE)
        if num_match:
            converted_num = word_to_num(num_match.group(0))
            # Replace the word number with digit
            return re.sub(re.escape(num_match.group(0)), converted_num, matched_str, flags=re.IGNORECASE) # Use re.escape for safety
        return matched_str
    return 'N/A'

def _extract_timing(text: str) -> str:
    # Captures common timing phrases
    timing_terms = r'(before food|after food|at night|morning|evening|bedtime|before meal|after meal|empty stomach|with food|after breakfast|after lunch|after dinner|before breakfast|before lunch|before dinner)\b'
    regex = re.search(timing_terms, text, re.IGNORECASE)
    if regex:
        return regex.group(0).strip()
    return 'N/A'

# Helper to merge subword tokens from NER results
def merge_ner_tokens(ner_results):
    merged_entities = []
    current_entity = None

    for entity in ner_results:
        # If it's a subword token (starts with ##) and we have a current entity to merge with
        if entity['word'].startswith('##') and current_entity:
            current_entity['word'] += entity['word'][2:] # Append without ##
            current_entity['end'] = entity['end'] # Extend end index
            current_entity['score'] = (current_entity['score'] + entity['score']) / 2 # Average score
        else:
            # If it's a new entity, add the previous one (if any) and start a new one
            if current_entity:
                merged_entities.append(current_entity)
            current_entity = entity.copy() # Start new entity

    if current_entity: # Add the last entity
        merged_entities.append(current_entity)
    return merged_entities

# --- Core Extraction Logic (Prioritizes Learned Feedback) ---
def _extract_medicines(text: str) -> List[Dict]:
    print(f"DEBUG: nlp_pipeline status at _extract_medicines start: {nlp_pipeline is not None}")
    text_lower = text.lower()

    # 1. Check LEARNED_FEEDBACK first for highly similar inputs
    for feedback_entry in LEARNED_FEEDBACK:
        original_feedback_text_lower = feedback_entry['original_text'].lower()
        similarity_score = fuzz.ratio(text_lower, original_feedback_text_lower) # Returns a score out of 100
        if similarity_score > 90: # High threshold (e.g., 90 out of 100) for direct reuse
            print(f"DEBUG: Found highly similar input in learned feedback (score: {similarity_score}). Returning corrected data.")
            return [med.dict() for med in feedback_entry['corrected_medicines']]

    # 2. If no direct feedback match, proceed with NER model (or fallback)
    if nlp_pipeline:
        print(f"DEBUG: Processing input text with NER model: '{text}'")
        return _extract_medicines_with_biobert(text) # Function name remains, but uses new model
    else:
        print(f"DEBUG: Processing input text with basic keyword matching: '{text}'")
        return _extract_medicines_basic(text)

# --- NER Model-based Extraction (if loaded) ---
def _extract_medicines_with_biobert(text: str) -> List[Dict]:
    extracted_data = []
    raw_ner_results = nlp_pipeline(text)
    print(f"DEBUG: Raw NER results from NER model (before merging): {raw_ner_results}")
    
    # Merge subword tokens first
    ner_results = merge_ner_tokens(raw_ner_results)
    print(f"DEBUG: Merged NER results: {ner_results}")

    identified_medicine_names = set()

    for entity in ner_results:
        # d4data/biomedical-ner-all uses 'Chemical' and 'Medication' for drugs.
        # We'll target 'Chemical' and 'Medication' for medicine names.
        if entity['entity_group'] in ['Chemical', 'CHEMICAL', 'DRUG', 'MEDICINE', 'COMPOUND', 'Medication']: 
            potential_med_name = entity['word'].strip()
            print(f"DEBUG: Potential medicine recognized by NER model: '{potential_med_name}' (Entity Group: {entity['entity_group']})")
            
            best_match_from_list = "N/A"
            max_similarity = 0.0
            
            # Prioritize exact match first using the lowercased set for efficiency
            if potential_med_name.lower() in LOADED_MEDICINE_NAMES_LOWER_SET:
                # Find the original casing from the full list
                best_match_from_list = next((n for n in LOADED_MEDICINE_NAMES if n.lower() == potential_med_name.lower()), potential_med_name)
                max_similarity = 100.0 # Assign 100% for exact match
                print(f"DEBUG: Exact match found for '{potential_med_name}': '{best_match_from_list}'")
            else: # Then proceed with fuzzy matching
                for loaded_name in LOADED_MEDICINE_NAMES:
                    current_similarity = fuzz.ratio(potential_med_name.lower(), loaded_name.lower()) # Score out of 100
                    if current_similarity > max_similarity:
                        max_similarity = current_similarity
                        best_match_from_list = loaded_name
                print(f"DEBUG: Best fuzzy match for '{potential_med_name}' from loaded list: '{best_match_from_list}' (Similarity: {max_similarity})")

            # Only add if similarity is above threshold and not already identified
            if max_similarity > 65 and best_match_from_list != "N/A": 
                if best_match_from_list.lower() not in identified_medicine_names:
                    identified_medicine_names.add(best_match_from_list.lower())
                    extracted_data.append({
                        "name": best_match_from_list,
                        "dosage": _extract_dosage(text),
                        "duration": _extract_duration(text), 
                        "frequency": _extract_frequency(text),
                        "timing": _extract_timing(text),
                    })
                    print(f"DEBUG: Added extracted medicine (high similarity): {best_match_from_list}")
            else:
                print(f"DEBUG: Skipped '{potential_med_name}' (Similarity: {max_similarity}) as it's below threshold or not a valid match.")
        else: 
            print(f"DEBUG: Entity '{entity['word']}' with group '{entity['entity_group']}' is not a recognized medicine type.")

    print(f"DEBUG: Final extracted data from NER model: {extracted_data}")
    return extracted_data

# Fallback basic extraction (if NER model not loaded or fails)
def _extract_medicines_basic(text: str) -> List[Dict]:
    extracted_data = []
    text_lower = text.lower()
    # Sort by length descending to match longer names first (e.g., "Vitamin C" before "Vitamin")
    sorted_available_medicines = sorted(LOADED_MEDICINE_NAMES, key=len, reverse=True)
    matched_names = set()
    print(f"DEBUG: Basic extraction for text: '{text}'")

    for med_name in sorted_available_medicines:
        med_name_lower = med_name.lower()
        # Check for direct containment or high fuzzy ratio
        if med_name_lower in text_lower and med_name_lower not in matched_names:
            print(f"DEBUG: Basic direct containment match found: '{med_name}'")
            extracted_data.append({
                "name": med_name,
                "dosage": _extract_dosage(text),
                "duration": _extract_duration(text),
                "frequency": _extract_frequency(text),
                "timing": _extract_timing(text),
            })
            matched_names.add(med_name_lower)
        else:
            similarity_score = fuzz.ratio(med_name_lower, text_lower) # Get similarity score
            if similarity_score > 60 and med_name_lower not in matched_names: # Use 60 as the fuzzy threshold
                print(f"DEBUG: Basic fuzzy match found: '{med_name}' (Similarity: {similarity_score})")
                extracted_data.append({
                    "name": med_name,
                    "dosage": _extract_dosage(text),
                    "duration": _extract_duration(text),
                    "frequency": _extract_frequency(text),
                    "timing": _extract_timing(text),
                })
                matched_names.add(med_name_lower)
    print(f"DEBUG: Final extracted data from basic: {extracted_data}")
    return extracted_data


# --- Medicine Suggestion Logic (Using NER model's understanding for names) ---
def _get_medicine_suggestion(input_text: str, patient_summary: str) -> str:
    input_lower = input_text.lower()
    
    # Prioritize learned feedback for suggestions too
    for feedback_entry in LEARNED_FEEDBACK:
        original_feedback_text_lower = feedback_entry['original_text'].lower()
        similarity_score = fuzz.ratio(input_lower, original_feedback_text_lower) # Returns a score out of 100
        if similarity_score > 90: # High threshold (e.g., 90 out of 100) for direct reuse
            for corrected_med in feedback_entry['corrected_medicines']:
                if fuzz.ratio(input_lower, corrected_med.name.lower()) > 75:
                    print(f"DEBUG: Suggestion from learned feedback: {corrected_med.name}")
                    return corrected_med.name
            return "N/A" # If feedback matches but no medicine in feedback matches input
    
    if nlp_pipeline:
        print("DEBUG: No direct feedback match for suggestion. Using NER model.")
        return _get_medicine_suggestion_with_biobert(input_text, patient_summary) # Function name remains
    else:
        print("DEBUG: No direct feedback match for suggestion and NER model not loaded. Falling back to basic matching.")
        best_match = "N/A"
        highest_similarity = 0.0
        for med_name in LOADED_MEDICINE_NAMES:
            current_similarity = fuzz.ratio(input_lower, med_name.lower())
            if current_similarity > 60:
                highest_similarity = current_similarity
                best_match = med_name
        return best_match if highest_similarity > 60 else "N/A"

def _get_medicine_suggestion_with_biobert(input_text: str, patient_summary: str) -> str:
    input_lower = input_text.lower()
    
    raw_ner_results = nlp_pipeline(input_text)
    ner_results = merge_ner_tokens(raw_ner_results) # Merge subwords for suggestion too
    
    potential_drug_entity = None
    for entity in ner_results:
        if entity['entity_group'] in ['Chemical', 'CHEMICAL', 'DRUG', 'MEDICINE', 'COMPOUND', 'Medication']:
            potential_drug_entity = entity['word'].strip()
            break

    if potential_drug_entity:
        best_match_name = "N/A"
        max_similarity = 0.0
        
        # Prioritize exact match first for suggestion
        if potential_drug_entity.lower() in LOADED_MEDICINE_NAMES_LOWER_SET:
            best_match_name = next((n for n in LOADED_MEDICINE_NAMES if n.lower() == potential_drug_entity.lower()), potential_drug_entity)
            max_similarity = 100.0
            print(f"DEBUG: Exact match found for suggestion '{potential_drug_entity}': '{best_match_name}'")
        else: # Then proceed with fuzzy matching
            for loaded_name in LOADED_MEDICINE_NAMES:
                current_similarity = fuzz.ratio(potential_drug_entity.lower(), loaded_name.lower())
                if current_similarity > max_similarity:
                    max_similarity = current_similarity
                    best_match_name = loaded_name
            print(f"DEBUG: Best fuzzy match for suggestion '{potential_drug_entity}': '{best_match_name}' (Similarity: {max_similarity})")
        
        if max_similarity > 65: # Use the same fuzzy threshold as extraction
            return best_match_name
    
    return "N/A" # Return N/A if no suitable drug entity is found and matched.


# --- API Endpoints ---
@app.post("/extract_medicines", response_model=List[MedicineResponse])
async def extract_medicines_api(request: MedicineRequest):
    """
    Extracts medicine prescriptions from a given text (summary or voice input)
    by prioritizing learned feedback, then using BioBERT, then basic matching.
    """
    if not LOADED_MEDICINE_NAMES:
        raise HTTPException(status_code=500, detail="Medicine data not loaded on backend. Check server logs.")

    extracted = _extract_medicines(request.text)
    
    if not extracted:
        return []
    
    return extracted

@app.post("/suggest_medicine", response_model=SuggestionResponse)
async def suggest_medicine_api(request: SuggestionRequest):
    """
    Suggests a medicine name based on input, patient summary, and available medicines,
    prioritizing learned feedback, then leveraging BioBERT.
    """
    if not LOADED_MEDICINE_NAMES:
        raise HTTPException(status_code=500, detail="Medicine data not loaded on backend. Check server logs.")

    suggestion = _get_medicine_suggestion(
        request.input_text,
        request.patient_summary
    )
    return {"suggestion": suggestion}

@app.post("/feedback_extraction")
async def feedback_extraction(feedback: FeedbackRequest):
    """
    Receives feedback on extracted medicines to 'learn' from user corrections.
    This data is stored in-memory for demonstration.
    """
    LEARNED_FEEDBACK.append(feedback.dict())
    print(f"DEBUG: Received feedback. Current learned feedback count: {len(LEARNED_FEEDBACK)}")
    print(f"DEBUG: Stored feedback for original text (first 50 chars): {feedback.original_text[:50]}...")
    return {"message": "Feedback received and stored conceptually."}

# To run this file: uvicorn backend_app:app --reload --host 0.0.0.0 --port 8000
