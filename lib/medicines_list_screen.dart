// lib/medicines_list_screen.dart
import 'package:flutter/material.dart';
import 'package:medicare/models/medicine_prescription.dart'; // Ensure this model is created
import 'dart:convert'; // For JSON encoding/decoding
import 'package:provider/provider.dart';
import 'package:medicare/services/data_loader.dart'; // Ensure this DataLoader is the latest version
import 'package:dio/dio.dart'; // For making HTTP requests
import 'package:record/record.dart'; // For audio recording
import 'package:path_provider/path_provider.dart'; // For temporary file paths
import 'dart:io'; // For File operations
import 'dart:math'; // For min function in debug prints
import 'dart:async'; // For StreamSubscription

// Import the next screen in the workflow
import 'package:medicare/opd_report_final_screen.dart';

// Global variables provided by the Canvas environment (not directly used for API key here)
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class MedicinesListScreen extends StatefulWidget {
  final String summaryText; // This is the summary generated from the conversation
  final String patientId; // NEW: Patient ID passed from SummaryScreen
  final String? chiefComplaint; // NEW: Chief Complaint passed from SummaryScreen

  const MedicinesListScreen({
    super.key,
    required this.summaryText,
    required this.patientId, // Added patientId
    this.chiefComplaint, // Added chiefComplaint
  });

  @override
  State<MedicinesListScreen> createState() => _MedicinesListScreenState();
}

class _MedicinesListScreenState extends State<MedicinesListScreen> {
  List<MedicinePrescription> _medicines = [];
  bool _isLoading = false; // General loading for API calls, data loading
  String _errorMessage = '';
  final Dio _dio = Dio(); // Initialize Dio for API calls

  // Hardcoded Gemini API Details
  final String _geminiApiKey = 'AIzaSyCXmcg_aOEwg38airIbs14C0SqZK6b_UTo';
  final String _geminiModel = 'gemini-1.5-flash'; // Consistent with SummaryScreen
  final String _geminiApiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/';

  // Bhashini API Details
  final String _bhashiniApiKey = '529fda3d00-836e-498b-a266-7d1ea97a667f'; // Bhashini API Key
  final String _bhashiniUserId = 'ae98869a2a7542b1a24da628b955e51b'; // Bhashini User ID
  final String _bhashiniAuthBaseUrl = 'https://meity-auth.ulcacontrib.org';
  final String _bhashiniPipelineId = "64392f96daac500b55c543cd"; // Pipeline ID from your Colab

  String? _bhashiniInferenceBaseUrl;
  String? _bhashiniInferenceApiKey;
  Map<String, dynamic>? _pipelineConfigResponse;

  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _audioFilePath;
  StreamSubscription<Amplitude>? _audioLevelSubscription;

  // Maps to hold TextEditingControllers for each medicine's fields
  final Map<String, Map<String, TextEditingController>> _fieldControllers = {};

  List<String> _availableMedicineNames = []; // List of medicine names from CSV for suggestions

  @override
  void initState() {
    super.initState();
    _initializeBhashiniPipeline(); // Initialize Bhashini first
    // Use addPostFrameCallback to ensure context is fully built before accessing DataLoader
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataLoader = Provider.of<DataLoader>(context, listen: false);
      // Listen to DataLoader changes only if not already loaded
      if (!dataLoader.isLoaded) {
        dataLoader.addListener(_handleDataLoaderChange);
      } else {
        // If already loaded, proceed with initial medicine extraction
        _handleInitialMedicineExtraction();
      }
    });
  }

  @override
  void dispose() {
    final dataLoader = Provider.of<DataLoader>(context, listen: false);
    dataLoader.removeListener(_handleDataLoaderChange); // Remove listener on dispose

    _audioLevelSubscription?.cancel();
    _audioRecorder.dispose();

    // Dispose all managed controllers
    _fieldControllers.forEach((medicineId, fieldMap) {
      fieldMap.forEach((field, controller) {
        controller.dispose();
      });
    });
    _fieldControllers.clear(); // Clear the map after disposing all controllers

    super.dispose();
  }

  // Helper to get or create a TextEditingController for a specific field
  TextEditingController _getOrCreateController(String medicineId, String field, String initialText) {
    // Ensure the map for this medicineId exists
    _fieldControllers.putIfAbsent(medicineId, () => {});

    if (!_fieldControllers[medicineId]!.containsKey(field)) {
      final controller = TextEditingController(text: initialText);
      _fieldControllers[medicineId]![field] = controller;

      // Add listener to update the model when text changes
      controller.addListener(() {
        if (!mounted) return; // Guard against disposed widget
        final index = _medicines.indexWhere((m) => m.id == medicineId);
        if (index != -1) {
          // Only update if the text actually changed to prevent unnecessary rebuilds
          if (controller.text != _medicines[index].getField(field)) {
             setState(() { // setState is needed here to reflect changes in UI
               _medicines[index].setField(field, controller.text);
             });
          }
        }
      });
    } else {
      // If controller already exists, ensure its text is synced with the model
      final controller = _fieldControllers[medicineId]![field]!;
      // Only update if different, to avoid cursor jumping, and ensure it's not disposed
      if (controller.text != initialText) {
        try {
          controller.text = initialText;
          // Move cursor to end if text was programmatically updated
          controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
        } catch (e) {
          print('Error updating controller for $medicineId, field $field: $e');
        }
      }
    }
    return _fieldControllers[medicineId]![field]!;
  }

  // Listener for DataLoader changes
  void _handleDataLoaderChange() {
    final dataLoader = Provider.of<DataLoader>(context, listen: false);
    if (dataLoader.isLoaded) {
      _handleInitialMedicineExtraction();
      dataLoader.removeListener(_handleDataLoaderChange); // Remove listener once loaded
    } else if (dataLoader.loadError != null) {
      if (mounted) {
        setState(() {
          _errorMessage = dataLoader.loadError!;
          _isLoading = false;
        });
      }
      dataLoader.removeListener(_handleDataLoaderChange); // Remove listener on error
    }
  }

  // Handles initial medicine extraction from summary, only if conditions met
  void _handleInitialMedicineExtraction() {
    // Load medicine names from CSV via DataLoader
    // This is now called after DataLoader confirms data is loaded
    final dataLoader = Provider.of<DataLoader>(context, listen: false);
    final medicinesFromLoader = dataLoader.getLoadedData('medicines');
    if (medicinesFromLoader != null && medicinesFromLoader.isNotEmpty) {
      setState(() {
        _availableMedicineNames = medicinesFromLoader.map((e) => e['name'].toString()).toList();
        _errorMessage = ''; // Clear error if successful
      });
    } else {
      setState(() {
        _errorMessage = 'No medicines found in local assets. Please ensure medicines.csv is correctly bundled.';
      });
    }

    if (widget.summaryText.isNotEmpty && widget.summaryText != 'Generating summary...') {
      _extractMedicinesFromSummary();
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No summary provided. Please add medicines manually or use voice input.';
        });
      }
    }
  }

  // --- Bhashini API Functions ---

  Future<void> _initializeBhashiniPipeline() async {
    if (!mounted) return; // Guard
    setState(() {
      _isLoading = true; // Use _isLoading for Bhashini init
      _errorMessage = '';
      _pipelineConfigResponse = null;
      _bhashiniInferenceBaseUrl = null;
      _bhashiniInferenceApiKey = null;
    });

    try {
      final Dio dio = Dio();
      final response = await dio.post(
        '$_bhashiniAuthBaseUrl/ulca/apis/v0/model/getModelsPipeline',
        options: Options(headers: {
          'Content-Type': 'application/json',
          'ulcaApiKey': _bhashiniApiKey,
          'userID': _bhashiniUserId,
        }),
        data: jsonEncode({
          "pipelineTasks": [
            {"taskType": "asr"},
            {"taskType": "translation"},
            {"taskType": "tts"}
          ],
          "pipelineRequestConfig": {
            "pipelineId": _bhashiniPipelineId
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null) {
          _pipelineConfigResponse = data;
          if (data['pipelineInferenceAPIEndPoint'] != null) {
            _bhashiniInferenceBaseUrl = data['pipelineInferenceAPIEndPoint']['callbackUrl'];
            _bhashiniInferenceApiKey = data['pipelineInferenceAPIEndPoint']['inferenceApiKey']['value'];
            print('Bhashini Inference Base URL: $_bhashiniInferenceBaseUrl');
            print('Bhashini Inference API Key (first 5 chars): ${_bhashiniInferenceApiKey?.substring(0,5)}...');
            _errorMessage = ''; // Clear error if successful
          } else {
            _errorMessage = 'Missing pipelineInferenceAPIEndPoint in Bhashini config response.';
          }

          if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
             _errorMessage = 'Failed to get Bhashini inference API details. Check Bhashini configuration.';
          }
        } else {
          _errorMessage = 'Invalid pipeline configuration response (empty data).';
        }
      } else {
        _errorMessage = 'Failed to fetch Bhashini pipeline config: ${response.statusCode} - ${response.data}';
      }
    } catch (e) {
      _errorMessage = 'Error initializing Bhashini pipeline: $e';
      print('Error initializing Bhashini pipeline: $e');
    } finally {
      if (mounted) { // Ensure widget is still mounted before calling setState
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _findServiceId(String taskType, String sourceLanguage, {String? targetLanguage}) {
    if (_pipelineConfigResponse == null) {
      print('DEBUG: _pipelineConfigResponse is null when trying to find serviceId for $taskType.');
      return null;
    }

    final pipelineResponseConfig = _pipelineConfigResponse!['pipelineResponseConfig'];
    if (pipelineResponseConfig == null) {
      print('DEBUG: pipelineResponseConfig is null when trying to find serviceId for $taskType.');
      return null;
    }

    for (var config in pipelineResponseConfig) {
      if (config['taskType'] == taskType) {
        for (var configDetail in config['config']) {
          final languageConfig = configDetail['language'];
          if (languageConfig != null && languageConfig['sourceLanguage'] == sourceLanguage) {
            if (targetLanguage == null || languageConfig['targetLanguage'] == targetLanguage) {
              print('DEBUG: Found $taskType serviceId: ${configDetail['serviceId']} for $sourceLanguage -> $targetLanguage');
              return configDetail['serviceId'];
            }
          }
        }
      }
    }
    print('DEBUG: No $taskType serviceId found for $sourceLanguage -> $targetLanguage');
    return null;
  }

  // Performs Speech-to-Text (ASR) using Bhashini Inference API.
  // Returns transcribed text.
  Future<String?> _performASR(String audioBase64, String sourceLanguageCode) async {
    if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
      if (mounted) { // Guard setState
        _errorMessage = 'Bhashini Inference API not initialized.';
      }
      return null;
    }

    final asrServiceId = _findServiceId('asr', sourceLanguageCode);
    if (asrServiceId == null) {
      if (mounted) { // Guard setState
        _errorMessage = 'ASR service not found for language ($sourceLanguageCode).';
      }
      print('DEBUG: ASR serviceId not found for source: $sourceLanguageCode');
      return null;
    }

    try {
      final Dio dio = Dio();
      final requestBody = jsonEncode({
          "pipelineTasks": [
            {
              "taskType": "asr",
              "config": {
                "language": {
                  "sourceLanguage": sourceLanguageCode
                },
                "serviceId": asrServiceId
              }
            }
          ],
          "inputData": {
            "audio": [
              {
                "audioContent": audioBase64
              }
            ]
          }
        });

      print('DEBUG: ASR Request URL: $_bhashiniInferenceBaseUrl');
      print('DEBUG: ASR Request Headers: {"Content-Type": "application/json", "Authorization": "${_bhashiniInferenceApiKey?.substring(0,5)}..."}');
      print('DEBUG: ASR Audio Base64 Length: ${audioBase64.length}');

      final response = await dio.post(
        _bhashiniInferenceBaseUrl!,
        options: Options(headers: {'Content-Type': 'application/json', 'Authorization': _bhashiniInferenceApiKey!,}),
        data: requestBody,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null && data['pipelineResponse'] != null && data['pipelineResponse'][0]['output'] != null) {
          final transcribed = data['pipelineResponse'][0]['output'][0]['source'];
          if (transcribed != null && transcribed.toString().trim().isNotEmpty) {
            return transcribed.toString();
          } else {
            if (mounted) { // Guard setState
              _errorMessage = 'ASR returned empty or null text. Please try speaking more clearly.';
            }
            print('DEBUG: ASR returned empty or null text: $transcribed');
            return null;
          }
        } else {
          if (mounted) { // Guard setState
            _errorMessage = 'Invalid ASR response structure.';
          }
          print('DEBUG: Invalid ASR response structure: $data');
          return null;
        }
      } else {
        if (mounted) { // Guard setState
          _errorMessage = 'Failed to perform ASR: ${response.statusCode} - ${response.data}';
        }
        print('DEBUG: ASR API Error Response: ${response.statusCode} - ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      if (mounted) { // Guard setState
        _errorMessage = 'Error performing ASR: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      }
      print('DEBUG: DioException during ASR: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      if (mounted) { // Guard setState
        _errorMessage = 'Error performing ASR: $e';
      }
      print('DEBUG: Generic Error performing ASR: $e');
      return null;
    }
  }

  // Function to call Gemini API for medicine extraction from the GENERATED SUMMARY
  Future<void> _extractMedicinesFromSummary() async {
    if (!mounted) return; // Guard
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final String prompt = """
      Extract medicine prescriptions from the following patient summary. For each medicine, identify its name, dosage, duration, frequency, and timing (e.g., 'before food', 'after food', 'at night', 'morning', 'evening', 'bedtime'). If a detail is not explicitly mentioned or is unclear, use 'N/A' for that specific field.
      If no medicines are mentioned, return an empty JSON array `[]`.

      Provide the output as a JSON array of objects. Each object should have the following properties: 'name', 'dosage', 'duration', 'frequency', 'timing'.

      Example JSON structure:
      [
        {
          "name": "Paracetamol",
          "dosage": "500mg",
          "duration": "5 days",
          "frequency": "twice daily",
          "timing": "after food"
        },
        {
          "name": "Amoxicillin",
          "dosage": "250mg",
          "duration": "7 days",
          "frequency": "three times a day",
          "timing": "before food"
        }
      ]

      Summary:
      ${widget.summaryText}
      """;

      List<Map<String, dynamic>> chatHistory = [];
      chatHistory.add({ "role": "user", "parts": [{ "text": prompt }] });
      
      final Map<String, dynamic> payload = {
          "contents": chatHistory,
          "generationConfig": {
              "responseMimeType": "application/json",
              "responseSchema": {
                  "type": "ARRAY",
                  "items": {
                      "type": "OBJECT",
                      "properties": {
                          "name": { "type": "STRING" },
                          "dosage": { "type": "STRING" },
                          "duration": { "type": "STRING" },
                          "frequency": { "type": "STRING" },
                          "timing": { "type": "STRING" }
                      },
                      "propertyOrdering": ["name", "dosage", "duration", "frequency", "timing"]
                  }
              }
          }
      };

      final fullGeminiApiUrl = '$_geminiApiBaseUrl$_geminiModel:generateContent?key=$_geminiApiKey';

      print('DEBUG: Gemini Medicines Request URL: $fullGeminiApiUrl');
      print('DEBUG: Gemini Medicines Request Body: ${jsonEncode(payload)}');

      final response = await _dio.post(
        fullGeminiApiUrl,
        data: json.encode(payload),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      
      if (response.statusCode == 200) {
        final result = response.data;
        print('DEBUG: Gemini Medicines Response Data: $result');
        if (result['candidates'] != null && result['candidates'].length > 0 &&
            result['candidates'][0]['content'] != null && result['candidates'][0]['content']['parts'] != null &&
            result['candidates'][0]['content']['parts'].length > 0) {
          final jsonString = result['candidates'][0]['content']['parts'][0]['text'];
          print('Gemini API Raw Response: $jsonString');

          final List<dynamic> jsonList = json.decode(jsonString);
          
          if (mounted) { // Check mounted before setState
            setState(() {
              _medicines.addAll(jsonList.map((item) {
                final newMedicine = MedicinePrescription.fromJson({
                  ...item,
                  'id': DateTime.now().microsecondsSinceEpoch.toString(), // Using microseconds for higher uniqueness
                });
                // Initialize controllers for the new medicine
                _getOrCreateController(newMedicine.id, 'name', newMedicine.name);
                _getOrCreateController(newMedicine.id, 'dosage', newMedicine.dosage);
                _getOrCreateController(newMedicine.id, 'duration', newMedicine.duration);
                _getOrCreateController(newMedicine.id, 'frequency', newMedicine.frequency);
                _getOrCreateController(newMedicine.id, 'timing', newMedicine.timing);
                return newMedicine;
              }).toList());
            });
          }
          
          if (_medicines.isEmpty && mounted) { // Check mounted before setting error message
            _errorMessage = 'No medicines extracted from summary. You can add them manually or use voice input.';
          }

        } else {
          if (mounted) { // Check mounted before setting error message
            setState(() {
              _errorMessage = 'Failed to extract medicines. Unexpected API response structure.';
            });
          }
          print('Gemini API Error: Unexpected response structure or no candidates.');
        }
      } else {
        if (mounted) { // Check mounted before setting error message
          setState(() {
            _errorMessage = 'Failed to extract medicines. Status: ${response.statusCode} - ${response.statusMessage}';
        });
        }
        print('Gemini API Error: Status ${response.statusCode} - ${response.statusMessage}');
      }

    } on DioException catch (e) {
      if (mounted) { // Check mounted before setting error message
        _errorMessage = 'Error communicating with AI: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      }
      print('DioException during Gemini API call: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
    } catch (e) {
      if (mounted) { // Check mounted before setting error message
        _errorMessage = 'An unexpected error occurred: $e';
      }
      print('Unexpected Error extracting medicines: $e');
    } finally {
      if (mounted) { // Ensure widget is still mounted before calling setState
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // NEW: Function to call Gemini API for comprehensive medicine extraction from voice input
  Future<List<MedicinePrescription>?> _extractMedicinesFromVoiceInput(String voiceInputText) async {
    if (voiceInputText.trim().isEmpty) return [];

    try {
      final String prompt = """
      You are a highly accurate medical transcription and prescription parsing assistant.
      Your task is to extract all medicine prescriptions from the given natural language input.
      For each medicine, identify its name, dosage, duration, frequency, and timing (e.g., 'before food', 'after food', 'at night', 'morning', 'evening', 'bedtime').

      If a detail is not explicitly mentioned or is unclear for a specific medicine, use 'N/A' for that specific field.
      If no medicines are mentioned, return an empty JSON array `[]`.

      Provide the output as a JSON array of objects. Each object must strictly adhere to the following structure:
      {
        "name": "STRING",
        "dosage": "STRING",
        "duration": "STRING",
        "frequency": "STRING",
        "timing": "STRING"
      }

      Example Input:
      "The patient needs Paracetamol 650 mg, twice daily for 5 days after food. Also, prescribe Ibuprofen 200mg once a day for 3 days before food."

      Example Output:
      [
        {
          "name": "Paracetamol",
          "dosage": "650 mg",
          "duration": "5 days",
          "frequency": "twice daily",
          "timing": "after food"
        },
        {
          "name": "Ibuprofen",
          "dosage": "200mg",
          "duration": "3 days",
          "frequency": "once a day",
          "timing": "before food"
        }
      ]

      Now, extract medicines from the following input:
      $voiceInputText
      """;

      List<Map<String, dynamic>> chatHistory = [];
      chatHistory.add({ "role": "user", "parts": [{ "text": prompt }] });
      
      final Map<String, dynamic> payload = {
          "contents": chatHistory,
          "generationConfig": {
              "responseMimeType": "application/json",
              "responseSchema": {
                  "type": "ARRAY",
                  "items": {
                      "type": "OBJECT",
                      "properties": {
                          "name": { "type": "STRING" },
                          "dosage": { "type": "STRING" },
                          "duration": { "type": "STRING" },
                          "frequency": { "type": "STRING" },
                          "timing": { "type": "STRING" }
                      },
                      "propertyOrdering": ["name", "dosage", "duration", "frequency", "timing"]
                  }
              }
          }
      };

      final fullGeminiApiUrl = '$_geminiApiBaseUrl$_geminiModel:generateContent?key=$_geminiApiKey';

      print('DEBUG: Gemini Comprehensive Extraction Request URL: $fullGeminiApiUrl');
      print('DEBUG: Gemini Comprehensive Extraction Request Body: ${jsonEncode(payload)}');

      final response = await _dio.post(
        fullGeminiApiUrl,
        data: json.encode(payload),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      
      if (response.statusCode == 200) {
        final result = response.data;
        print('DEBUG: Gemini Comprehensive Extraction Response Data: $result');
        if (result['candidates'] != null && result['candidates'].length > 0 &&
            result['candidates'][0]['content'] != null && result['candidates'][0]['content']['parts'] != null &&
            result['candidates'][0]['content']['parts'].length > 0) {
          final jsonString = result['candidates'][0]['content']['parts'][0]['text'];
          print('Gemini API Raw Response: $jsonString');

          final List<dynamic> jsonList = json.decode(jsonString);
          return jsonList.map((item) => MedicinePrescription.fromJson(item)).toList();
        }
      }
      return []; // Return empty list on error or invalid response
    } on DioException catch (e) {
      if (mounted) { // Guard setState
        _errorMessage = 'Error extracting medicines from voice input: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      }
      print('DioException during comprehensive extraction: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return [];
    } catch (e) {
      if (mounted) { // Guard setState
        _errorMessage = 'An unexpected error occurred during comprehensive extraction: $e';
      }
      print('Unexpected Error during comprehensive extraction: $e');
      return [];
    }
  }

  // Function to call Gemini API for medicine name suggestion/correction
  // Now takes the current patient summary for context
  Future<String> _getMedicineSuggestion(String input, String patientSummary) async {
    if (input.trim().isEmpty) return 'N/A'; // Return N/A for empty input

    final dataLoader = Provider.of<DataLoader>(context, listen: false);
    final List<String> availableMedicines = dataLoader.medicineNames;

    // Combined prompt for Gemini to handle local CSV, global knowledge,
    // phonetic similarity, and symptom relevance.
    final String combinedPrompt = """
    The user is trying to input a medicine name. The input provided is: "$input".
    This input might be a misspelled word, a phonetic transcription from speech-to-text, or a partial name.

    Here is a list of known medicine names (CSV data):
    ${availableMedicines.isEmpty ? 'No local medicine data available.' : availableMedicines.join(', ')}

    Here is a summary of the patient's symptoms/condition:
    ${patientSummary.isEmpty || patientSummary == 'Generating summary...' ? 'No patient summary available.' : patientSummary}

    Based on the input, the known medicine names, and the patient's symptoms, perform the following steps:
    1.  **Prioritize:** Find the closest matching medicine name from the 'known medicine names' list, considering phonetic similarity and common misspellings.
    2.  **Contextualize:** If multiple close matches exist, or if the best match is ambiguous, consider which medicine would be most relevant or commonly prescribed for the patient's symptoms/condition.
    3.  **Global Check:** If no very strong and relevant match is found in the 'known medicine names' list, then use your general medical knowledge to determine if "$input" (or a very close phonetic variant) is a recognized medicine name in the global market.

    Your response should be *only* the best suggested medicine name. If, after all considerations (local list, symptoms, global knowledge, phonetic similarity), you cannot confidently identify a valid medicine name, return "N/A".

    Examples:
    Input: "porocetomol", Symptoms: "fever, headache" -> Output: "Paracetamol"
    Input: "azithromicin", Symptoms: "bacterial infection" -> Output: "Azithromycin"
    Input: "lipitor", Symptoms: "high cholesterol" -> Output: "Atorvastatin" (if Lipitor is brand name for Atorvastatin and Atorvastatin is in CSV or globally known)
    Input: "xyz-drug", Symptoms: "cough" -> Output: "N/A"
    Input: "i see through my sin", Symptoms: "sore throat, cough" -> Output: "Azithromycin" (inferring from phonetic similarity and symptoms)
    """;

    List<Map<String, dynamic>> chatHistory = [];
    chatHistory.add({ "role": "user", "parts": [{ "text": combinedPrompt }] });
    
    final Map<String, dynamic> payload = { "contents": chatHistory };
    final fullGeminiApiUrl = '$_geminiApiBaseUrl$_geminiModel:generateContent?key=$_geminiApiKey';

    print('DEBUG: Gemini Suggestion Request URL: $fullGeminiApiUrl');
    print('DEBUG: Gemini Suggestion Request Body (truncated to 500 chars): ${jsonEncode(payload).substring(0, min(jsonEncode(payload).length, 500))}...');

    try {
      final response = await _dio.post(
        fullGeminiApiUrl,
        data: json.encode(payload),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      
      if (response.statusCode == 200) {
        final result = response.data;
        print('DEBUG: Gemini Suggestion Response Data: $result');
        if (result['candidates'] != null && result['candidates'].length > 0 &&
            result['candidates'][0]['content'] != null && result['candidates'][0]['content']['parts'] != null &&
            result['candidates'][0]['content']['parts'].length > 0) {
          return result['candidates'][0]['content']['parts'][0]['text'].trim();
        }
      }
      return 'N/A'; // Fallback if no valid response or error
    } on DioException catch (e) {
      print('Error getting medicine suggestion: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return 'N/A'; // Fallback on error
    } catch (e) {
      print('Unexpected Error getting medicine suggestion: $e');
      return 'N/A'; // Fallback on error
    }
  }

  // Function to add a new empty medicine prescription to the list
  void _addNewMedicine() {
    if (!mounted) return; // Guard
    setState(() {
      final newMedicine = MedicinePrescription.empty();
      _medicines.add(newMedicine);
      // Initialize controllers for the newly added medicine
      _getOrCreateController(newMedicine.id, 'name', newMedicine.name);
      _getOrCreateController(newMedicine.id, 'dosage', newMedicine.dosage);
      _getOrCreateController(newMedicine.id, 'duration', newMedicine.duration);
      _getOrCreateController(newMedicine.id, 'frequency', newMedicine.frequency);
      _getOrCreateController(newMedicine.id, 'timing', newMedicine.timing);
    });
  }

  // Function to remove a medicine prescription from the list
  void _removeMedicine(String id) {
    if (!mounted) return; // Guard
    
    // Dispose controllers associated with the removed medicine BEFORE removing from list
    _fieldControllers[id]?.forEach((field, controller) {
      controller.dispose();
    });
    _fieldControllers.remove(id); // Remove the entry from the map

    setState(() {
      _medicines.removeWhere((medicine) => medicine.id == id);
    });
  }

  // Function to save/confirm the medicines list (for demonstration)
  void _saveMedicines() {
    // In a real application, you would send this _medicines list to a backend
    // or save it to a database (e.g., Firestore).
    print('Saving medicines:');
    for (var medicine in _medicines) {
      print('  - ${medicine.toJson()}');
    }
    if (mounted) { // Check mounted before showing SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicines list saved! (Check console for details)')),
      );
    }
  }

  // --- Voice Input Dialog (for individual fields) ---
  // This dialog now returns a String? result
  Future<String?> _showVoiceInputDialog({
    required String initialText,
    required bool isMedicineNameField,
  }) async {
    String currentTranscribedText = initialText; // Initialize with the field's current text
    String suggestedMedicine = '';
    bool isDialogRecording = false;
    bool isSuggesting = false;
    String dialogError = '';
    double dialogAudioLevel = 0.0; // LOCAL variable for audio level in dialog

    TextEditingController dialogInputController = TextEditingController(text: initialText);

    final result = await showDialog<String>( // Dialog now returns String?
      context: context,
      barrierDismissible: false, // User must interact with buttons
      builder: (BuildContext context) {
        final ThemeData currentTheme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: currentTheme.cardTheme.color,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Text(
                isMedicineNameField ? 'Voice Input & Medicine Suggestion' : 'Voice Input',
                style: currentTheme.textTheme.titleMedium,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isDialogRecording ? 'Recording...' : 'Tap mic to speak ${isMedicineNameField ? 'medicine name' : 'details'}',
                      style: currentTheme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        if (_bhashiniInferenceBaseUrl == null) {
                          setDialogState(() {
                            dialogError = 'Bhashini services not initialized. Please try again later.';
                          });
                          return;
                        }
                        if (await _audioRecorder.isRecording()) {
                          // Stop recording
                          await _audioLevelSubscription?.cancel();
                          _audioLevelSubscription = null;
                          String? path = await _audioRecorder.stop();
                          setDialogState(() {
                            isDialogRecording = false;
                            dialogAudioLevel = 0.0; // Reset local audio level
                            currentTranscribedText = 'Processing...';
                          });
                          if (path != null) {
                            File audioFile = File(path);
                            List<int> audioBytes = await audioFile.readAsBytes();
                            String audioBase64 = base64Encode(audioBytes); // Correct variable name
                            final transcribed = await _performASR(audioBase64, 'en'); // Corrected variable usage
                            setDialogState(() {
                              currentTranscribedText = transcribed ?? 'Failed to transcribe.';
                              dialogError = transcribed == null ? 'Failed to transcribe audio.' : '';
                              dialogInputController.text = currentTranscribedText; // Update dialog's text field
                              dialogInputController.selection = TextSelection.fromPosition(TextPosition(offset: dialogInputController.text.length)); // Move cursor to end
                            });
                          } else {
                            setDialogState(() {
                              currentTranscribedText = 'No audio recorded.';
                              dialogError = 'No audio recorded.';
                            });
                          }
                        } else {
                          // Start recording
                          setDialogState(() {
                            isDialogRecording = true;
                            currentTranscribedText = 'Listening...';
                            dialogError = '';
                            dialogInputController.text = ''; // Clear previous text
                          });
                          Directory tempDir = await getTemporaryDirectory();
                          _audioFilePath = '${tempDir.path}/temp_audio_field.wav';
                          _audioLevelSubscription = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
                            setDialogState(() {
                              dialogAudioLevel = amp.current; // Update local audio level
                            });
                          });
                          await _audioRecorder.start(
                            const RecordConfig(
                              encoder: AudioEncoder.wav, numChannels: 1, sampleRate: 16000, bitRate: 16,
                            ),
                            path: _audioFilePath!,
                          );
                        }
                      },
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: isDialogRecording ? Colors.redAccent : currentTheme.primaryColor,
                        child: Icon(isDialogRecording ? Icons.stop : Icons.mic, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Display audio level if recording
                    if (isDialogRecording)
                      Text(
                        'Audio Level: ${dialogAudioLevel.toStringAsFixed(2)} dB', // Use local dialogAudioLevel
                        textAlign: TextAlign.center,
                        style: currentTheme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dialogInputController, // This is the controller for the dialog's input
                      onChanged: (value) {
                        setDialogState(() {
                          currentTranscribedText = value; // Keep transcribed text synced with manual edits
                          suggestedMedicine = ''; // Clear suggestion if user starts typing
                          isSuggesting = false;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Transcribed Text (Editable)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        fillColor: currentTheme.inputDecorationTheme.fillColor,
                        filled: true,
                      ),
                      style: currentTheme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    if (dialogError.isNotEmpty)
                      Text(
                        dialogError,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    // Show "Get Suggestion" button ONLY for medicine name field
                    if (isMedicineNameField)
                      Column(
                        children: [
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: isSuggesting || dialogInputController.text.isEmpty || dialogInputController.text == 'Listening...' || dialogInputController.text == 'Processing...' || dialogInputController.text == 'Failed to transcribe.'
                                ? null
                                : () async {
                                    setDialogState(() {
                                      isSuggesting = true;
                                      suggestedMedicine = 'Suggesting...';
                                    });
                                    // Pass the patient summary for context
                                    final suggestion = await _getMedicineSuggestion(dialogInputController.text, widget.summaryText);
                                    setDialogState(() {
                                      suggestedMedicine = suggestion;
                                      isSuggesting = false;
                                    });
                                  },
                            icon: isSuggesting ? const CircularProgressIndicator(strokeWidth: 2) : const Icon(Icons.lightbulb_outline),
                            label: Text(isSuggesting ? 'Suggesting...' : 'Get Suggestion'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentTheme.primaryColor,
                              foregroundColor: currentTheme.colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                          if (suggestedMedicine.isNotEmpty && suggestedMedicine != 'Suggesting...')
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Suggested: $suggestedMedicine',
                                      style: currentTheme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: suggestedMedicine == 'N/A' || suggestedMedicine == 'N/A (No data)' ? Colors.red : currentTheme.primaryColor,
                                      ),
                                    ),
                                  ),
                                  if (suggestedMedicine != 'N/A' && suggestedMedicine != 'N/A (No data)')
                                    IconButton(
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                      onPressed: () {
                                        // When accepted, pop with the suggested value
                                        Navigator.of(context).pop(suggestedMedicine);
                                      },
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel', style: TextStyle(color: currentTheme.hintColor)),
                  onPressed: () {
                    Navigator.of(context).pop(null); // Pop with null on cancel
                  },
                ),
                TextButton(
                  child: Text('Apply (Current Text)', style: TextStyle(color: currentTheme.primaryColor)),
                  onPressed: () {
                    Navigator.of(context).pop(dialogInputController.text); // Pop with current text
                  },
                ),
              ],
            );
          },
        );
      },
    );

    // Dispose the local controller after the dialog closes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dialogInputController.dispose();
    });
    return result; // Return the result from the dialog
  }

  // NEW: Dialog for comprehensive voice input for multiple medicines
  // This dialog now returns a List<MedicinePrescription>? result
  Future<List<MedicinePrescription>?> _showComprehensiveVoiceInputDialog() async {
    TextEditingController comprehensiveInputController = TextEditingController();
    String currentTranscribedText = '';
    bool isDialogRecording = false;
    bool isExtracting = false;
    String dialogError = '';
    double dialogAudioLevel = 0.0; // LOCAL variable for audio level in dialog
    String? selectedLanguage = 'English'; // Default to English for comprehensive input
    String? selectedLanguageCode = 'en';

    final result = await showDialog<List<MedicinePrescription>>( // Dialog now returns List<MedicinePrescription>?
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final ThemeData currentTheme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: currentTheme.cardTheme.color,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Text('Full Prescription Voice Input', style: currentTheme.textTheme.titleMedium),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Speak (or type) the full prescription details, e.g., "Give Paracetamol 650mg twice daily for 5 days after food, and Amoxicillin 250mg once a day for 7 days before food."',
                      style: currentTheme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 15),
                    // Language selection for comprehensive voice input
                    DropdownButton<String>(
                      value: selectedLanguage,
                      onChanged: (String? newValue) {
                        setDialogState(() {
                          selectedLanguage = newValue;
                          selectedLanguageCode = newValue != null ? {'English': 'en', 'Tamil': 'ta', 'Hindi': 'hi', 'Telugu': 'te', 'Kannada': 'kn', 'Malayalam': 'ml'}[newValue] : null;
                        });
                      },
                      items: <String>['English', 'Tamil', 'Hindi', 'Telugu', 'Kannada', 'Malayalam']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        if (_bhashiniInferenceBaseUrl == null) {
                          setDialogState(() {
                            dialogError = 'Bhashini services not initialized. Please try again later.';
                          });
                          return;
                        }
                        if (await _audioRecorder.isRecording()) {
                          // Stop recording
                          await _audioLevelSubscription?.cancel();
                          _audioLevelSubscription = null;
                          String? path = await _audioRecorder.stop();
                          setDialogState(() {
                            isDialogRecording = false;
                            dialogAudioLevel = 0.0; // Reset local audio level
                            currentTranscribedText = 'Processing...';
                          });
                          if (path != null) {
                            File audioFile = File(path);
                            List<int> audioBytes = await audioFile.readAsBytes();
                            String audioBase64 = base64Encode(audioBytes);
                            final transcribed = await _performASR(audioBase64, selectedLanguageCode!); 
                            setDialogState(() {
                              currentTranscribedText = transcribed ?? 'Failed to transcribe.';
                              dialogError = transcribed == null ? 'Failed to transcribe audio.' : '';
                              // Update the text controller with transcribed text
                              comprehensiveInputController.text = currentTranscribedText;
                              comprehensiveInputController.selection = TextSelection.fromPosition(TextPosition(offset: comprehensiveInputController.text.length)); // Move cursor to end
                            });
                          } else {
                            setDialogState(() {
                              currentTranscribedText = 'No audio recorded.';
                              dialogError = 'No audio recorded.';
                            });
                          }
                        } else {
                          // Start recording
                          setDialogState(() {
                            isDialogRecording = true;
                            currentTranscribedText = 'Listening...';
                            dialogError = '';
                            comprehensiveInputController.text = ''; // Clear previous text
                          });
                          Directory tempDir = await getTemporaryDirectory();
                          _audioFilePath = '${tempDir.path}/temp_audio_comprehensive.wav';
                          _audioLevelSubscription = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
                            setDialogState(() {
                              dialogAudioLevel = amp.current; // Update local audio level
                            });
                          });
                          await _audioRecorder.start(
                            const RecordConfig(
                              encoder: AudioEncoder.wav, numChannels: 1, sampleRate: 16000, bitRate: 16,
                            ),
                            path: _audioFilePath!,
                          );
                        }
                      },
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: isDialogRecording ? Colors.redAccent : currentTheme.primaryColor,
                        child: Icon(isDialogRecording ? Icons.stop : Icons.mic, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Display audio level if recording
                    if (isDialogRecording)
                      Text(
                        'Audio Level: ${dialogAudioLevel.toStringAsFixed(2)} dB', // Use local dialogAudioLevel
                        textAlign: TextAlign.center,
                        style: currentTheme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: comprehensiveInputController,
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        labelText: 'Manual Input (or edit transcribed text)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        fillColor: currentTheme.inputDecorationTheme.fillColor,
                        filled: true,
                      ),
                      style: currentTheme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    if (dialogError.isNotEmpty)
                      Text(
                        dialogError,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: isExtracting || comprehensiveInputController.text.isEmpty
                          ? null
                          : () async {
                                setDialogState(() {
                                  isExtracting = true;
                                  dialogError = '';
                                });
                                final extractedMedicines = await _extractMedicinesFromVoiceInput(comprehensiveInputController.text);
                                setDialogState(() {
                                  isExtracting = false;
                                  if (extractedMedicines!.isNotEmpty) {
                                    Navigator.of(context).pop(extractedMedicines); // Pop with the list of medicines
                                  } else {
                                    dialogError = 'No medicines extracted. Please refine input or try again.';
                                  }
                                });
                              },
                      icon: isExtracting ? const CircularProgressIndicator(strokeWidth: 2) : const Icon(Icons.playlist_add),
                      label: Text(isExtracting ? 'Extracting...' : 'Extract & Add Medicines'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: currentTheme.primaryColor,
                        foregroundColor: currentTheme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel', style: TextStyle(color: currentTheme.hintColor)),
                  onPressed: () {
                    Navigator.of(context).pop(null); // Pop with null on cancel
                  },
                ),
              ],
            );
          },
        );
      },
    );

    // Dispose the local controller after the dialog closes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      comprehensiveInputController.dispose();
    });
    return result;

  }

  // Widget to build a single medicine card with editable fields
  Widget _buildMedicineCard(MedicinePrescription medicine, int index, ThemeData currentTheme) {
    // Get or create controllers for each field using the medicine's ID
    TextEditingController nameController = _getOrCreateController(medicine.id, 'name', medicine.name);
    TextEditingController dosageController = _getOrCreateController(medicine.id, 'dosage', medicine.dosage);
    TextEditingController durationController = _getOrCreateController(medicine.id, 'duration', medicine.duration);
    TextEditingController frequencyController = _getOrCreateController(medicine.id, 'frequency', medicine.frequency);
    TextEditingController timingController = _getOrCreateController(medicine.id, 'timing', medicine.timing);

    return Card(
      // ValueKey is crucial for stable widget identity in ListView.builder
      key: ValueKey(medicine.id), 
      margin: const EdgeInsets.symmetric(vertical: 10),
      elevation: currentTheme.cardTheme.elevation,
      shape: currentTheme.cardTheme.shape,
      color: currentTheme.cardTheme.color,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Medicine ${index + 1}',
                  style: currentTheme.textTheme.titleMedium?.copyWith(color: currentTheme.primaryColor),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red[400]),
                  onPressed: () => _removeMedicine(medicine.id),
                ),
              ],
            ),
            const Divider(height: 10, thickness: 1), // Reduced divider height
            _buildEditableField(
              context,
              label: 'Name',
              controller: nameController,
              icon: Icons.medication,
              onVoiceInput: (currentController) async { // Make this async
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: true,
                );
                if (resultText != null && mounted) { // Check mounted before updating controller
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_name'), // Add unique key to TextField
            ),
            _buildEditableField(
              context,
              label: 'Dosage',
              controller: dosageController,
              icon: Icons.medical_information,
              onVoiceInput: (currentController) async { // Make this async
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: false,
                );
                if (resultText != null && mounted) { // Check mounted before updating controller
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_dosage'), // Add unique key to TextField
            ),
            _buildEditableField(
              context,
              label: 'Duration',
              controller: durationController,
              icon: Icons.calendar_today,
              onVoiceInput: (currentController) async { // Make this async
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: false,
                );
                if (resultText != null && mounted) { // Check mounted before updating controller
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_duration'), // Add unique key to TextField
            ),
            _buildEditableField(
              context,
              label: 'Frequency',
              controller: frequencyController,
              icon: Icons.access_time,
              onVoiceInput: (currentController) async { // Make this async
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: false,
                );
                if (resultText != null && mounted) { // Check mounted before updating controller
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_frequency'), // Add unique key to TextField
            ),
            _buildEditableField(
              context,
              label: 'Timing',
              controller: timingController,
              icon: Icons.fastfood,
              onVoiceInput: (currentController) async { // Make this async
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: false,
                );
                if (resultText != null && mounted) { // Check mounted before updating controller
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_timing'), // Add unique key to TextField
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget for editable text fields with voice input icon
  // onVoiceInput now takes the controller as an argument
  Widget _buildEditableField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Function(TextEditingController) onVoiceInput, // Changed signature
    required Key fieldKey, // Added Key parameter for TextField
  }) {
    final ThemeData currentTheme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0), // Reduced vertical padding
      child: TextField(
        key: fieldKey, // Assign the key here
        controller: controller,
        style: currentTheme.textTheme.bodyMedium,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: currentTheme.inputDecorationTheme.prefixIconColor),
          suffixIcon: IconButton(
            icon: Icon(Icons.mic, color: currentTheme.primaryColor),
            onPressed: () => onVoiceInput(controller), // Pass the controller to the callback
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: currentTheme.dividerColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: currentTheme.dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: currentTheme.primaryColor, width: 2),
          ),
          filled: true,
          fillColor: currentTheme.inputDecorationTheme.fillColor,
          labelStyle: currentTheme.inputDecorationTheme.labelStyle,
          contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0), // Smaller content padding
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);
    final dataLoader = Provider.of<DataLoader>(context); // Listen to DataLoader

    // Determine if the app is loading data or Bhashini services
    final bool isAppLoading = _isLoading || !dataLoader.hasAttemptedLoad || dataLoader.loadError != null || _pipelineConfigResponse == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescribe Medicines'),
        backgroundColor: Colors.teal, // Distinct color for this screen
        elevation: 0,
      ),
      backgroundColor: Colors.teal[50],
      body: isAppLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    _errorMessage.isNotEmpty
                        ? _errorMessage
                        : (dataLoader.loadError != null
                            ? 'Error loading data: ${dataLoader.loadError}'
                            : 'Loading essential data and AI services...'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )
          : Column( // Changed from SingleChildScrollView to Column
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // --- Patient Information (Read-only) ---
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Reduced vertical margin further
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0), // Reduced padding inside card
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Patient ID: ${widget.patientId}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (widget.chiefComplaint != null && widget.chiefComplaint!.isNotEmpty)
                          Text(
                            'Chief Complaint: ${widget.chiefComplaint}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        const Divider(height: 5), // Reduced divider height further
                        Text(
                          'Summary from Consultation:',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 3), // Reduced space
                        Text(
                          widget.summaryText,
                          style: currentTheme.textTheme.bodySmall,
                          maxLines: 2, // Further reduced maxLines for summary
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // --- Error Message Display ---
                if (_errorMessage.isNotEmpty && !isAppLoading) // Only show if not initial loading
                  Container(
                    padding: const EdgeInsets.all(10), // Reduced padding
                    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Reduced vertical margin
                    decoration: BoxDecoration(
                      color: Colors.red[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),

                // --- Medicines List Title ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 5.0, 16.0, 5.0), // Adjusted top/bottom padding
                  child: Text(
                    'Prescribed Medicines:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal[700],
                    ),
                  ),
                ),

                // --- Medicines List (Expanded to take remaining space) ---
                Expanded(
                  child: _medicines.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Text(
                              'No medicines extracted. Click "Add New Medicine Manually" or "Add Medicines via Voice Input" to start.',
                              style: currentTheme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0), // Padding for cards inside list
                          itemCount: _medicines.length,
                          itemBuilder: (context, index) {
                            final medicine = _medicines[index];
                            return _buildMedicineCard(medicine, index, currentTheme);
                          },
                        ),
                ),

                // --- Action Buttons at the bottom ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0), // Reduced vertical padding
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isLoading || _medicines.isEmpty ? null : () {
                          // Convert List<MedicinePrescription> to List<Map<String, dynamic>>
                          final List<Map<String, dynamic>> medicinesAsJson = _medicines.map((m) => m.toJson()).toList();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OpdReportFinalScreen(
                                patientId: widget.patientId,
                                summaryText: widget.summaryText,
                                prescribedMedicines: medicinesAsJson,
                                chiefComplaint: widget.chiefComplaint,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.arrow_forward, size: 28),
                        label: const Text(
                          'Proceed to Final Report',
                          style: TextStyle(fontSize: 20),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 5,
                          minimumSize: Size(MediaQuery.of(context).size.width * 0.7, 60),
                        ),
                      ),
                      const SizedBox(height: 10), // Reduced spacing between buttons
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _addNewMedicine,
                        icon: const Icon(Icons.add_circle_outline, size: 28),
                        label: const Text(
                          'Add New Medicine Manually',
                          style: TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 3,
                        ),
                      ),
                      const SizedBox(height: 10), // Reduced spacing between buttons
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : () async {
                          final extractedMedicines = await _showComprehensiveVoiceInputDialog();
                          if (extractedMedicines != null && extractedMedicines.isNotEmpty && mounted) {
                            setState(() {
                              _medicines.addAll(extractedMedicines.map((newMedicine) {
                                // Initialize controllers for the newly added medicine
                                _getOrCreateController(newMedicine.id, 'name', newMedicine.name);
                                _getOrCreateController(newMedicine.id, 'dosage', newMedicine.dosage);
                                _getOrCreateController(newMedicine.id, 'duration', newMedicine.duration);
                                _getOrCreateController(newMedicine.id, 'frequency', newMedicine.frequency);
                                _getOrCreateController(newMedicine.id, 'timing', newMedicine.timing);
                                return newMedicine;
                              }));
                            });
                          }
                        },
                        icon: const Icon(Icons.mic_none, size: 28),
                        label: const Text(
                          'Add Medicines via Voice Input',
                          style: TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple, // Distinct color for voice input
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 3,
                        ),
                      ),
                      const SizedBox(height: 10), // Reduced spacing between buttons
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Go back to Summary Screen
                        },
                        icon: const Icon(Icons.arrow_back, size: 28),
                        label: const Text(
                          'Go Back',
                          style: TextStyle(fontSize: 20),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 5,
                          minimumSize: Size(MediaQuery.of(context).size.width * 0.7, 60),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// Extend MedicinePrescription to add helpers for field access
extension MedicinePrescriptionFieldHelpers on MedicinePrescription {
  String getField(String fieldName) {
    switch (fieldName) {
      case 'name': return name;
      case 'dosage': return dosage;
      case 'duration': return duration;
      case 'frequency': return frequency;
      case 'timing': return timing;
      default: return '';
    }
  }

  void setField(String fieldName, String value) {
    switch (fieldName) {
      case 'name': this.name = value; break;
      case 'dosage': this.dosage = value; break;
      case 'duration': this.duration = value; break;
      case 'frequency': this.frequency = value; break;
      case 'timing': this.timing = value; break;
    }
  }
}
