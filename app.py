from flask import Flask, request, jsonify
from flask_cors import CORS
from transformers import (
    AutoTokenizer,
    AutoModelForTokenClassification,
    AutoModelForSeq2SeqLM,
    pipeline,
)
import numpy as np
import torch
import re
from word2number import w2n
from spellchecker import SpellChecker
from rapidfuzz import fuzz # For fuzzy matching medicine names
import json # NEW IMPORT: For loading JSON
import os # NEW IMPORT: For checking file existence

app = Flask(__name__)
CORS(app)

# Initialize spell checker (load once)
spell = SpellChecker()

# Device configuration (for GPU if available, otherwise CPU)
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")

# --- Load Biomedical NER model ---
ner_model_name = "d4data/biomedical-ner-all"
print(f"Loading NER model: {ner_model_name}...")
ner_tokenizer = AutoTokenizer.from_pretrained(ner_model_name)
ner_model = AutoModelForTokenClassification.from_pretrained(ner_model_name).to(device)
ner_pipeline = pipeline(
    "ner",
    model=ner_model,
    tokenizer=ner_tokenizer,
    aggregation_strategy="simple",
    device=0 if torch.cuda.is_available() else -1
)
print("SUCCESS: Biomedical NER model loaded.")

# --- Load Grammar Correction model ---
grammar_model_name = "vennify/t5-base-grammar-correction"
print(f"Loading Grammar Correction model: {grammar_model_name}...")
grammar_tokenizer = AutoTokenizer.from_pretrained(grammar_model_name)
grammar_model = AutoModelForSeq2SeqLM.from_pretrained(grammar_model_name).to(device)
print("SUCCESS: Grammar Correction model loaded.")

# --- Load Abstractive Summarization Model (Still loaded, but its direct output will be used differently) ---
summary_model_name = "t5-base"
print(f"Loading Summarization model: {summary_model_name}...")
summary_tokenizer = AutoTokenizer.from_pretrained(summary_model_name)
summary_model = AutoModelForSeq2SeqLM.from_pretrained(summary_model_name).to(device)
summary_pipeline = pipeline(
    "summarization",
    model=summary_model,
    tokenizer=summary_tokenizer,
    device=0 if torch.cuda.is_available() else -1
)
print("SUCCESS: Abstractive Summarization model loaded.")


# --- Utility function to make float/int JSON serializable ---
def convert_to_serializable(obj):
    """Recursively converts numpy types and torch tensors to standard Python types for JSON serialization."""
    if isinstance(obj, dict):
        return {k: convert_to_serializable(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_to_serializable(elem) for elem in obj]
    elif isinstance(obj, (np.integer, np.int64, np.int32)):
        return int(obj)
    elif isinstance(obj, (np.floating, np.float32, np.float64)):
        return float(obj)
    elif isinstance(obj, torch.Tensor):
        return obj.tolist()
    return obj

# --- Spell Correction ---
def spell_correct_text(text):
    """Corrects common spelling mistakes in the input text."""
    words = text.split()
    corrected_words = []
    for word in words:
        correction = spell.correction(word)
        corrected_words.append(correction if correction is not None else word)
    return " ".join(corrected_words)

# --- Grammar correction step ---
def grammar_correct(text):
    """
    Corrects grammar of the input text using the loaded T5-based model.
    """
    input_text = f"grammar: {text}"
    input_ids = grammar_tokenizer.encode(input_text, return_tensors="pt").to(device)
    outputs = grammar_model.generate(input_ids, max_length=128, num_beams=4, early_stopping=True)
    corrected_text = grammar_tokenizer.decode(outputs[0], skip_special_tokens=True)
    return corrected_text

# --- Normalize Number Words (e.g., "six fifty" to "six hundred fifty") ---
def normalize_number_words(text):
    """
    Normalizes common spoken number patterns (e.g., 'six fifty' to 'six hundred fifty')
    to improve word2number conversion accuracy. This is a heuristic.
    """
    text = re.sub(
        r'\b(one|two|three|four|five|six|seven|eight|nine)\s+(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)\b',
        r'\1 hundred \2',
        text,
        flags=re.IGNORECASE
    )
    return text


# --- Merge subword tokens and handle general merging ---
def merge_tokens(entities):
    """
    Merges tokens that are part of the same entity and handles subword tokens (##).
    Also tries to merge consecutive entities of the same type if they are close.
    Crucially, preserves start/end indices for merged tokens.
    """
    merged_entities = []
    current_entity = None

    # Sort entities by start index to ensure correct processing order
    entities.sort(key=lambda x: x.get('start', 0))

    for ent in entities:
        word = ent["word"]
        entity_type = ent.get("entity_group", "UNKNOWN")
        score = ent["score"]
        start = ent.get("start")
        end = ent.get("end")

        # Check if the current token can be merged with the previous one
        # Conditions: starts with ## OR same entity type and very close (e.g., 1-2 chars gap)
        if current_entity and (word.startswith("##") or \
           (entity_type == current_entity["entity"] and \
            start is not None and current_entity["end"] is not None and (start - current_entity["end"] <= 2))):
            
            # Merge word
            if word.startswith("##"):
                current_entity["word"] += word[2:]
            else:
                current_entity["word"] += " " + word
            
            # Update end and average score
            current_entity["end"] = end
            current_entity["score"] = (current_entity["score"] + score) / 2
        else:
            # If it's a new entity, add the previous one (if any) and start a new one
            if current_entity:
                merged_entities.append(current_entity)
            current_entity = {"word": word, "entity": entity_type, "score": score, "start": start, "end": end}
            
    if current_entity:
        merged_entities.append(current_entity)
        
    return merged_entities


# --- Extract General Advice/Recommendations (Enhanced for General Purpose) ---
def extract_general_advice(text):
    """
    Extracts common health advice phrases from the text using more flexible regex patterns.
    """
    advice_list = []
    text_lower = text.lower()

    # Water/Fluids
    if re.search(r'\b(drink|have|take|give)\s+(plenty\s+of\s+)?water\b|\bhydrate\b', text_lower):
        advice_list.append("Drink plenty of water.")
    if re.search(r'\b(drink|have|take|give)\s+(some\s+)?juice\b', text_lower):
        advice_list.append("Drink juice.")
    
    # Food/Diet
    if re.search(r'\b(eat|have)\s+(fresh\s+)?fruits?\b', text_lower):
        advice_list.append("Eat fruits.")
    if re.search(r'\b(eat|have)\s+(raw\s+)?vegetables?\b|\bveggies\b', text_lower):
        advice_list.append("Eat raw vegetables.")
    
    # Dietary restrictions
    if re.search(r'\b(no|avoid|reduce)\s+(extra\s+)?salt\b', text_lower):
        advice_list.append("Avoid excess salt.")
    if re.search(r'\b(no|avoid|reduce)\s+(added\s+)?sugar\b', text_lower):
        advice_list.append("Avoid excess sugar.")
    if re.search(r'\b(avoid|reduce)\s+(oily|fried)\s+food\b', text_lower):
        advice_list.append("Avoid oily/fried food.")
    
    # Rest/Activity
    if re.search(r'\b(get\s+enough|take)\s+rest\b', text_lower):
        advice_list.append("Get adequate rest.")
    if re.search(r'\b(do|perform)\s+(light\s+)?exercise\b', text_lower):
        advice_list.append("Do light exercise.")
    
    print(f"[DEBUG] Extracted Advice: {advice_list}")
    return list(set(advice_list))

# --- Mapping for common spelled-out numbers to digits ---
NUMBER_WORDS = {
    'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
    'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
    'eleven': '11', 'twelve': '12', 'thirteen': '13', 'fourteen': '14', 'fifteen': '15',
    'sixteen': '16', 'seventeen': '17', 'eighteen': '18', 'nineteen': '19', 'twenty': '20',
    'thirty': '30', 'forty': '40', 'fifty': '50', 'sixty': '60', 'seventy': '70',
    'eighty': '80', 'ninety': '90', 'hundred': '100', 'thousand': '1000',
    'half': '0.5' # For dosages like "half tablet"
}

# --- Load medicine data from JSON file ---
MEDICINE_DATA_FILE = "medicines_combined.json" # Assuming this file is in the same directory as app.py
LOADED_MEDICINE_NAMES = []
LOADED_MEDICINE_NAMES_LOWER_SET = set() # For faster lookup of lowercased names

def load_medicine_names():
    global LOADED_MEDICINE_NAMES, LOADED_MEDICINE_NAMES_LOWER_SET
    if not os.path.exists(MEDICINE_DATA_FILE):
        print(f"ERROR: {MEDICINE_DATA_FILE} not found in the app.py directory.")
        print("Please ensure you have copied 'medicines_combined.json' to the same folder as 'app.py'.")
        # Fallback to a small dummy list if file not found, for continued operation
        LOADED_MEDICINE_NAMES = ["Paracetamol", "Vitamin C", "Amoxicillin", "Ibuprofen", "Diphtheria Antitoxin"] # Added for testing
        LOADED_MEDICINE_NAMES_LOWER_SET = {name.lower() for name in LOADED_MEDICINE_NAMES}
        print("WARNING: Using a dummy medicine list due to missing JSON file.")
        return

    try:
        with open(MEDICINE_DATA_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            names_to_load = []
            for item in data:
                if 'name' in item and isinstance(item['name'], str):
                    names_to_load.append(item['name'].strip())
                
                # Extract core medicine name from 'strength' field if available
                if 'strength' in item and isinstance(item['strength'], str):
                    strength_match = re.match(r'([A-Za-z\s]+?)(?:\s*\(?\d+.*|\s+\d+.*|$)', item['strength'].strip())
                    if strength_match:
                        core_name = strength_match.group(1).strip()
                        if core_name and core_name.lower() not in LOADED_MEDICINE_NAMES_LOWER_SET:
                            names_to_load.append(core_name)
            
            unique_names = sorted(list(set(names_to_load)))
            
            LOADED_MEDICINE_NAMES = unique_names
            LOADED_MEDICINE_NAMES_LOWER_SET = {n.lower() for n in unique_names}
            
            print(f"Successfully loaded {len(LOADED_MEDICINE_NAMES)} unique medicine names from {MEDICINE_DATA_FILE}.")
            if "paracetamol" in LOADED_MEDICINE_NAMES_LOWER_SET:
                print("DEBUG: 'Paracetamol' (lowercase) IS found in loaded medicine names set.")
            else:
                print("DEBUG: 'Paracetamol' (lowercase) NOT found in loaded medicine names set. Check JSON 'strength' field extraction.")
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse {MEDICINE_DATA_FILE}. Ensure it's valid JSON. Error: {e}")
        print("WARNING: Using a dummy medicine list due to JSON parsing error.")
        LOADED_MEDICINE_NAMES = ["Paracetamol", "Vitamin C", "Amoxicillin", "Ibuprofen", "Diphtheria Antitoxin"]
        LOADED_MEDICINE_NAMES_LOWER_SET = {name.lower() for name in LOADED_MEDICINE_NAMES}
    except Exception as e:
        print(f"ERROR: An unexpected error occurred while loading {MEDICINE_DATA_FILE}: {e}")
        print("WARNING: Using a dummy medicine list due to unexpected error.")
        LOADED_MEDICINE_NAMES = ["Paracetamol", "Vitamin C", "Amoxicillin", "Ibuprofen", "Diphtheria Antitoxin"]
        LOADED_MEDICINE_NAMES_LOWER_SET = {name.lower() for name in LOADED_MEDICINE_NAMES}

# Load medicines when the app starts
load_medicine_names()

FUZZY_MATCH_THRESHOLD = 70 # Minimum similarity score to consider a fuzzy match valid

# --- Helper for extracting dosage, frequency, duration from raw text segment (now takes full_text) ---
def extract_med_details_from_segment(full_text: str, med_start_index: int, med_end_index: int, med_name_lower: str) -> (str, str, str):
    """
    Extracts dosage, frequency, and duration from the full text, focusing on the context
    around a specific medication.
    """
    dosage = "N/A"
    frequency = "N/A"
    duration = "N/A"

    # Define a broader search window around the medication entity
    # This window will be used for regex matching
    context_start = max(0, med_start_index - 70) # Increased context before
    context_end = min(len(full_text), med_end_index + 120) # Increased context after
    
    segment_for_extraction = full_text[context_start:context_end].lower()
    
    print(f"[DEBUG] Extracting details for '{med_name_lower}' from segment: '{segment_for_extraction}'")

    # To avoid matching the medication name itself as part of other details,
    # temporarily replace it in the segment. Use word boundaries.
    temp_segment_lower = re.sub(r'\b' + re.escape(med_name_lower) + r'\b', 'MED_PLACEHOLDER', segment_for_extraction, 1)


    # 1. Extract Dosage (number + unit)
    # This pattern tries to capture number words or digits, followed by optional units.
    # It's made more flexible to capture things like "six hundred fifty milligrams"
    num_word_pattern = r'(?:' + '|'.join(NUMBER_WORDS.keys()) + r'|\d+(?:\.\d+)?)(?:\s+(?:' + '|'.join(NUMBER_WORDS.keys()) + r'))*'
    units_pattern = r'(?:mg|g|ml|mcg|unit|tablet|pill|capsule|spoon(?:ful)?|units?|tabs?|caps?|bottles?|vials?|sachets?|pouches?|drops?|puffs?|sprays?|inhalations?|patches?|milligrams|grams|liters?|tablets|pills)\b'
    
    dosage_match = re.search(rf'({num_word_pattern})\s*({units_pattern})?', temp_segment_lower)
    if dosage_match:
        num_part = dosage_match.group(1).strip()
        unit_part = dosage_match.group(2) if dosage_match.group(2) else ""
        
        try:
            converted_num = str(w2n.word_to_num(num_part))
            dosage = converted_num
            if unit_part:
                dosage += f" {unit_part}"
        except ValueError:
            dosage = num_part # Fallback if w2n fails
            if unit_part:
                dosage += f" {unit_part}"
        
        temp_segment_lower = temp_segment_lower.replace(dosage_match.group(0), '', 1)
        print(f"[DEBUG] Extracted Dosage: {dosage}, Remaining segment: '{temp_segment_lower}'")


    # 2. Extract Frequency
    frequency_patterns = [
        r'\b(?:once|twice|thrice)\s+a\s+day\b',
        r'\b(?:one|two|three|four|five|six|seven|eight|nine|\d+)\s+times\s+a\s+day\b',
        r'\b(?:daily|every\s+day)\b',
        r'\b(?:every\s+\d+\s*hours?)\b',
        r'\b(?:b\.?d\.?|t\.?i\.?d\.?|o\.?d\.?|q\.?i\.?d\.?|bd|tid|od|qid|bid|tds|qds|qd|prn|stat|as needed)\b',
        r'\b(?:weekly|monthly|yearly)\b',
        r'\b(?:once)\b',
        r'\b(?:before\s+meals|after\s+meals|with\s+food|empty\s+stomach|at\s+night|in\s+the\s+morning|in\s+the\s+evening)\b' # Added common timings
    ]
    for pattern in frequency_patterns:
        freq_match = re.search(pattern, temp_segment_lower)
        if freq_match:
            frequency = freq_match.group(0).strip()
            for word, digit in NUMBER_WORDS.items(): 
                 frequency = re.sub(r'\b' + word + r'\b', digit, frequency, flags=re.IGNORECASE)
            temp_segment_lower = temp_segment_lower.replace(freq_match.group(0), '', 1)
            print(f"[DEBUG] Extracted Frequency: {frequency}, Remaining segment: '{temp_segment_lower}'")
            break


    # 3. Extract Duration
    duration_patterns = [
        r'\b(?:for\s+)?(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|\d+)\s+(?:day|week|month|year|hour)s?\b',
        r'\b(?:a\s+couple\s+of\s+days?)\b',
        r'\b(?:long\s+term|indefinitely|as\s+long\s+as\s+needed)\b' # Added more duration phrases
    ]
    for pattern in duration_patterns:
        dur_match = re.search(pattern, temp_segment_lower)
        if dur_match:
            duration = dur_match.group(0).strip()
            for word, digit in NUMBER_WORDS.items():
                 duration = re.sub(r'\b' + word + r'\b', digit, duration, flags=re.IGNORECASE)
            temp_segment_lower = temp_segment_lower.replace(dur_match.group(0), '', 1)
            print(f"[DEBUG] Extracted Duration: {duration}, Remaining segment: '{temp_segment_lower}'")
            break

    return dosage, frequency, duration


# --- API Endpoints ---

@app.route("/")
def home():
    return "AI-Powered Medical Backend is running!"

@app.route("/ner", methods=["POST"])
def extract_entities():
    """
    Processes input text to apply spell/grammar correction, extract entities,
    and generate a structured medical summary.
    """
    try:
        data = request.get_json(force=True)
        text = data.get("text", "").strip()
        if not text:
            return jsonify({"error": "Missing or empty 'text' field"}), 400

        # --- Step 1: Pre-processing (Spell Check -> Grammar Correction -> Number Word Normalization) ---
        spell_checked_text = spell_correct_text(text)
        print(f"[INFO] Spell-Corrected Text: {spell_checked_text}")
        
        grammar_corrected_text = grammar_correct(spell_checked_text)
        print(f"[INFO] Grammar-Corrected Text: {grammar_corrected_text}")

        # Normalize number words before NER and summarization
        processed_text_for_models = normalize_number_words(grammar_corrected_text)
        print(f"[INFO] Normalized Number Words Text: {processed_text_for_models}")


        # --- Step 2: Named Entity Recognition (NER) using BioBERT ---
        raw_entities = ner_pipeline(processed_text_for_models)
        # Convert to serializable format and merge subword tokens, preserving spans
        cleaned_entities = merge_tokens(convert_to_serializable(raw_entities))
        print(f"[DEBUG] Cleaned Entities (with spans): {cleaned_entities}") 

        # --- Step 3: Extract & Normalize Specific Details from NER Output ---
        
        # Symptoms (Filter out semantically incorrect ones like "signs of recovery")
        all_symptoms = [ent["word"] for ent in cleaned_entities if ent["entity"] == "Sign_symptom"]
        extracted_symptoms = list(set([s for s in all_symptoms if "recovery" not in s.lower()]))


        # Diseases/Conditions
        extracted_diseases = list(set([ent["word"] for ent in cleaned_entities if ent["entity"] == "Disease"]))
        
        # Tests/Procedures
        extracted_tests_procedures = list(set([ent["word"] for ent in cleaned_entities if ent["entity"] == "Procedure"])) 
        # Add a heuristic for "check body temperature" if BioBERT doesn't tag it as Procedure
        if "check your body temperature" in processed_text_for_models.lower() and "body temperature check" not in extracted_tests_procedures:
            extracted_tests_procedures.append("Body temperature check")

        # Medications with Dosage/Frequency/Duration (Robust extraction)
        medication_prescriptions = [] # Store final structured medication entries
        processed_med_names_lower = set() # Use a set to track lowercased, validated medicine names

        # Keep track of dosage/frequency/duration entities that have been "consumed" by a medication
        # This will be used to prevent re-associating them if they are explicitly tagged by NER
        consumed_ner_detail_indices = set() 

        # First pass: Link NER-tagged Medication to proximate NER-tagged Dosage/Frequency/Duration
        for i, ent in enumerate(cleaned_entities):
            if ent["entity"] in ["Medication", "Chemical"] and ent["word"].lower() not in processed_med_names_lower:
                potential_med_name = ent["word"].strip()
                
                best_match_name = "N/A"
                max_similarity = 0.0

                if potential_med_name.lower() in LOADED_MEDICINE_NAMES_LOWER_SET:
                    best_match_name = next((n for n in LOADED_MEDICINE_NAMES if n.lower() == potential_med_name.lower()), potential_med_name)
                    max_similarity = 100.0
                else:
                    for loaded_name in LOADED_MEDICINE_NAMES:
                        current_similarity = fuzz.ratio(potential_med_name.lower(), loaded_name.lower())
                        if current_similarity > max_similarity:
                            max_similarity = current_similarity
                            best_match_name = loaded_name
                
                print(f"[DEBUG] Potential NER Med: '{potential_med_name}', Best Fuzzy Match: '{best_match_name}' (Similarity: {max_similarity})")

                if max_similarity >= FUZZY_MATCH_THRESHOLD:
                    # Found a valid medication
                    processed_med_names_lower.add(best_match_name.lower())
                    
                    current_dosage = "N/A"
                    current_frequency = "N/A"
                    current_duration = "N/A"

                    # Search for associated NER entities in a forward window
                    search_window_indices = 5 # Look at next 5 entities
                    for j in range(i + 1, min(i + 1 + search_window_indices, len(cleaned_entities))):
                        other_ent = cleaned_entities[j]
                        # Check if entity is already consumed or too far
                        if j in consumed_ner_detail_indices or (other_ent["start"] - ent["end"] > 70): # Increased proximity window for NER details
                            continue

                        if other_ent["entity"] == "Dosage" and current_dosage == "N/A":
                            # Try to convert word numbers to digits for dosage
                            try:
                                # This regex specifically targets the numerical part and optional unit within the Dosage entity's word
                                num_unit_match = re.search(r'((?:' + '|'.join(NUMBER_WORDS.keys()) + r'|\d+(?:\.\d+)?)(?:\s+(?:' + '|'.join(NUMBER_WORDS.keys()) + r'))*)?\s*(mg|ml|g|units?|milligrams|grams|liters?|tablet|pill|capsule|spoon(?:ful)?)?', other_ent["word"].lower())
                                if num_unit_match and num_unit_match.group(1): # Ensure a number part is found
                                    num_words_only = num_unit_match.group(1).strip()
                                    unit = num_unit_match.group(2) if num_unit_match.group(2) else ""
                                    converted_num = str(w2n.word_to_num(num_words_only))
                                    current_dosage = converted_num
                                    if unit:
                                        current_dosage += f" {unit}"
                                else: # If no clear number words, just take the word as is
                                    current_dosage = other_ent["word"]
                            except ValueError:
                                current_dosage = other_ent["word"] # Fallback if w2n fails
                            consumed_ner_detail_indices.add(j)
                            print(f"[DEBUG] Found NER Dosage for '{best_match_name}': {current_dosage}")

                        elif other_ent["entity"] == "Frequency" and current_frequency == "N/A":
                            current_frequency = other_ent["word"]
                            consumed_ner_detail_indices.add(j)
                            print(f"[DEBUG] Found NER Frequency for '{best_match_name}': {current_frequency}")

                        elif other_ent["entity"] == "Duration" and current_duration == "N/A":
                            current_duration = other_ent["word"]
                            consumed_ner_detail_indices.add(j)
                            print(f"[DEBUG] Found NER Duration for '{best_match_name}': {current_duration}")
                    
                    # If any detail is still N/A, try to extract it using regex from a broader segment
                    # This is a fallback if NER didn't tag it or missed it
                    if current_dosage == "N/A" or current_frequency == "N/A" or current_duration == "N/A":
                        print(f"[DEBUG] Falling back to regex for '{best_match_name}' details.")
                        
                        # Use the entire processed_text_for_models and medication's original span for context
                        temp_dosage, temp_frequency, temp_duration = extract_med_details_from_segment(
                            processed_text_for_models, ent["start"], ent["end"], potential_med_name.lower()
                        )

                        if current_dosage == "N/A" and temp_dosage != "N/A":
                            current_dosage = temp_dosage
                        if current_frequency == "N/A" and temp_frequency != "N/A":
                            current_frequency = temp_frequency
                        if current_duration == "N/A" and temp_duration != "N/A":
                            current_duration = temp_duration


                    medication_prescriptions.append({
                        "medication": best_match_name,
                        "dosage": current_dosage,
                        "frequency": current_frequency,
                        "duration": current_duration
                    })
                else:
                    print(f"[DEBUG] Skipped '{potential_med_name}' (Similarity: {max_similarity}) - below threshold or already processed.")
            else: 
                print(f"[DEBUG] Entity '{ent['word']}' with group '{ent['entity']}' is not a primary medicine type.")

        print(f"[DEBUG] Medication Prescriptions: {medication_prescriptions}")
        
        # Extract General Advice
        general_advice = extract_general_advice(processed_text_for_models)

        # --- Step 4: Construct the Structured Summary ---
        
        structured_summary_parts = []

        # 4.1: Patient Overview / Chief Complaints
        if extracted_symptoms or extracted_diseases:
            patient_summary_line = "Patient reports "
            if extracted_symptoms:
                patient_summary_line += f"symptoms of {', '.join(extracted_symptoms)}"
            if extracted_symptoms and extracted_diseases:
                patient_summary_line += " and "
            if extracted_diseases:
                patient_summary_line += f"diagnosed with {', '.join(extracted_diseases)}"
            patient_summary_line += "."
            structured_summary_parts.append(patient_summary_line)
        else:
            # Fallback to a general summary from T5 if no specific symptoms/diseases extracted
            generated_general_summary = summary_pipeline(
                processed_text_for_models,
                max_new_tokens=100,
                min_length=20,
                do_sample=False
            )[0]['summary_text']
            if generated_general_summary:
                structured_summary_parts.append(generated_general_summary.strip())


        # 4.2: Tests/Procedures Recommended
        if extracted_tests_procedures:
            structured_summary_parts.append(f"Tests/Procedures recommended: {', '.join(extracted_tests_procedures)}.")

        # 4.3: Prescribed Medications
        if medication_prescriptions:
            med_lines = []
            for med in medication_prescriptions:
                line = f"{med['medication']}"
                if med['dosage'] != "N/A":
                    line += f" {med['dosage']}"
                if med['frequency'] != "N/A":
                    line += f" {med['frequency']}"
                if med['duration'] != "N/A":
                    line += f" for {med['duration']}" # Add 'for' for duration
                med_lines.append(line)
            structured_summary_parts.append(f"Prescribed medications: {'; '.join(med_lines)}.")

        # 4.4: Additional Advice
        if general_advice:
            structured_summary_parts.append(f"Additional advice: {'; '.join(general_advice)}.")
        
        # Combine all parts into the final structured summary
        final_structured_summary = " ".join(structured_summary_parts).strip()
        final_structured_summary = re.sub(r'\s+', ' ', final_structured_summary).strip()
        # Final punctuation cleanup for the whole summary
        if final_structured_summary and not final_structured_summary.endswith(('.', '!', '?')):
            final_structured_summary += "."
        final_structured_summary = re.sub(r'\.\s*\.', '.', final_structured_summary) # Fix double periods


        # --- Return results ---
        return jsonify({
            "entities": cleaned_entities, # Keep entities for potential future use or debugging
            "summary": final_structured_summary,
            "medication_prescriptions": medication_prescriptions # Explicitly return this structured list
        })

    except Exception as e:
        print(f"[ERROR] during /ner processing: {e}")
        return jsonify({"error": "Failed to process text", "details": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)

