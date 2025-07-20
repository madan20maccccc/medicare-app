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
import 'package:string_similarity/string_similarity.dart'; // For fuzzy matching medicine names

// Import the next screen in the workflow
import 'package:medicare/opd_report_final_screen.dart';

// Global variables provided by the Canvas environment (not directly used for API key here)
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class MedicinesListScreen extends StatefulWidget {
  final String summaryText; // This is the summary generated from the conversation
  final String patientId; // Patient ID passed from SummaryScreen
  final String? chiefComplaint; // Chief Complaint passed from SummaryScreen

  const MedicinesListScreen({
    super.key,
    required this.summaryText,
    required this.patientId,
    this.chiefComplaint,
  });

  @override
  State<MedicinesListScreen> createState() => _MedicinesListScreenState();
}

class _MedicinesListScreenState extends State<MedicinesListScreen> {
  List<MedicinePrescription> _medicines = [];
  bool _isLoading = false; // General loading for API calls, data loading
  String _errorMessage = '';
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30), // Increased connect timeout
    receiveTimeout: const Duration(seconds: 60), // Increased receive timeout
  )); // Initialize Dio for API calls

  // Backend API Details for Custom ML Model
  // IMPORTANT: For Android Emulator, use 10.0.2.2. For iOS Simulator/Desktop, use localhost.
  final String _backendApiBaseUrl = 'http://192.168.29.68:8000'; // For Physical Device // For Android Emulator

  // Bhashini API Details (remains for ASR)
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

  List<String> _availableMedicineNames = []; // List of medicine names from DataLoader for suggestions

  @override
  void initState() {
    super.initState();
    _initializeBhashiniPipeline(); // Initialize Bhashini first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataLoader = Provider.of<DataLoader>(context, listen: false);
      if (!dataLoader.isLoaded) {
        dataLoader.addListener(_handleDataLoaderChange);
        dataLoader.loadData();
      } else {
        _handleInitialMedicineExtraction();
      }
    });
  }

  @override
  void dispose() {
    final dataLoader = Provider.of<DataLoader>(context, listen: false);
    dataLoader.removeListener(_handleDataLoaderChange);

    _audioLevelSubscription?.cancel();
    _audioRecorder.dispose();

    _fieldControllers.forEach((medicineId, fieldMap) {
      fieldMap.forEach((field, controller) {
        controller.dispose();
      });
    });
    _fieldControllers.clear();

    super.dispose();
  }

  TextEditingController _getOrCreateController(String medicineId, String field, String initialText) {
    _fieldControllers.putIfAbsent(medicineId, () => {});
    if (!_fieldControllers[medicineId]!.containsKey(field)) {
      final controller = TextEditingController(text: initialText);
      _fieldControllers[medicineId]![field] = controller;
      controller.addListener(() {
        if (!mounted) return;
        final index = _medicines.indexWhere((m) => m.id == medicineId);
        if (index != -1) {
          if (controller.text != _medicines[index].getField(field)) {
              setState(() {
                _medicines[index].setField(field, controller.text);
              });
          }
        }
      });
    } else {
      final controller = _fieldControllers[medicineId]![field]!;
      if (controller.text != initialText) {
        try {
          controller.text = initialText;
          controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
        } catch (e) {
          print('Error updating controller for $medicineId, field $field: $e');
        }
      }
    }
    return _fieldControllers[medicineId]![field]!;
  }

  void _handleDataLoaderChange() {
    final dataLoader = Provider.of<DataLoader>(context, listen: false);
    if (dataLoader.isLoaded) {
      _handleInitialMedicineExtraction();
      dataLoader.removeListener(_handleDataLoaderChange);
    } else if (dataLoader.loadError != null) {
      if (mounted) {
        setState(() {
          _errorMessage = dataLoader.loadError!;
          _isLoading = false;
        });
      }
      dataLoader.removeListener(_handleDataLoaderChange);
    }
  }

  void _handleInitialMedicineExtraction() {
    final dataLoader = Provider.of<DataLoader>(context, listen: false);
    final medicinesFromLoader = dataLoader.medicineNames;
    if (medicinesFromLoader.isNotEmpty) {
      setState(() {
        _availableMedicineNames = medicinesFromLoader;
        _errorMessage = '';
      });
    } else {
      setState(() {
        _errorMessage = 'No medicine names found in local assets. Please ensure medicine_combined.json is correctly bundled and contains "name" fields.';
      });
    }

    if (widget.summaryText.isNotEmpty && widget.summaryText != 'Generating summary...') {
      _extractMedicinesFromBackend(widget.summaryText);
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
        // Corrected Bhashini API endpoint
        '$_bhashiniAuthBaseUrl/ulca/apis/v0/model/getModelsPipeline',
        options: Options(headers: {
          'Content-Type': 'application/json',
          'ulcaApiKey': _bhashiniApiKey, // Corrected header for Bhashini v0
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
    } on DioException catch (e) {
      _errorMessage = 'Error initializing Bhashini pipeline: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      print('DioError initializing Bhashini: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
    } catch (e) {
      _errorMessage = 'Error initializing Bhashini pipeline: $e';
      print('Unexpected error initializing Bhashini: $e');
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
          "inputData": { // Corrected input key for Bhashini v0
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
        options: Options(headers: {'Content-Type': 'application/json', 'Authorization': _bhashiniInferenceApiKey!,}), // Authorization header for inference
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


  // --- Backend API Call for Extraction ---
  Future<void> _extractMedicinesFromBackend(String text, {int retryCount = 0}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await _dio.post(
        '$_backendApiBaseUrl/extract_medicines',
        data: jsonEncode({'text': text}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = response.data;
        if (mounted) {
          setState(() {
            _medicines.addAll(jsonList.map((item) {
              final newMedicine = MedicinePrescription.fromJson({
                ...item,
                'id': DateTime.now().microsecondsSinceEpoch.toString(),
              });
              _getOrCreateController(newMedicine.id, 'name', newMedicine.name);
              _getOrCreateController(newMedicine.id, 'dosage', newMedicine.dosage);
              _getOrCreateController(newMedicine.id, 'duration', newMedicine.duration);
              _getOrCreateController(newMedicine.id, 'frequency', newMedicine.frequency);
              _getOrCreateController(newMedicine.id, 'timing', newMedicine.timing);
              return newMedicine;
            }).toList());
          });
        }
        if (_medicines.isEmpty && mounted) {
          _errorMessage = 'No medicines extracted from summary. You can add them manually or use voice input.';
        }
      } else if (response.statusCode == 503 && retryCount < 3) {
        print('Backend returned 503. Retrying in 2 seconds (Retry ${retryCount + 1})...');
        await Future.delayed(const Duration(seconds: 2));
        return _extractMedicinesFromBackend(text, retryCount: retryCount + 1);
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to extract medicines from backend. Status: ${response.statusCode} - ${response.statusMessage}';
          });
        }
        print('Backend Error: Status ${response.statusCode} - ${response.statusMessage}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 503 && retryCount < 3) {
        print('DioException (503) during backend call. Retrying in 2 seconds (Retry ${retryCount + 1})...');
        await Future.delayed(const Duration(seconds: 2));
        return _extractMedicinesFromBackend(text, retryCount: retryCount + 1);
      }
      if (mounted) {
        _errorMessage = 'Error communicating with backend: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      }
      print('DioException during backend call: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
    } catch (e) {
      if (mounted) {
        _errorMessage = 'An unexpected error occurred: $e';
      }
      print('Unexpected Error extracting medicines: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- Backend API Call for Comprehensive Voice Input Extraction ---
  Future<List<MedicinePrescription>?> _extractMedicinesFromVoiceInputBackend(String voiceInputText, {int retryCount = 0}) async {
    if (voiceInputText.trim().isEmpty) return [];

    try {
      final response = await _dio.post(
        '$_backendApiBaseUrl/extract_medicines',
        data: jsonEncode({'text': voiceInputText}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = response.data;
        return jsonList.map((item) => MedicinePrescription.fromJson(item)).toList();
      } else if (response.statusCode == 503 && retryCount < 3) {
        print('Backend returned 503. Retrying in 2 seconds (Retry ${retryCount + 1})...');
        await Future.delayed(const Duration(seconds: 2));
        return _extractMedicinesFromVoiceInputBackend(voiceInputText, retryCount: retryCount + 1);
      } else {
        if (mounted) {
          _errorMessage = 'Failed to extract medicines from voice input via backend. Status: ${response.statusCode} - ${response.statusMessage}';
        }
        print('Backend Error: Status ${response.statusCode} - ${response.statusMessage}');
        return [];
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 503 && retryCount < 3) {
        print('DioException (503) during voice extraction backend call. Retrying in 2 seconds (Retry ${retryCount + 1})...');
        await Future.delayed(const Duration(seconds: 2));
        return _extractMedicinesFromVoiceInputBackend(voiceInputText, retryCount: retryCount + 1);
      }
      if (mounted) {
        _errorMessage = 'Error communicating with backend for voice input: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      }
      print('DioException during voice extraction backend call: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return [];
    } catch (e) {
      if (mounted) {
        _errorMessage = 'An unexpected error occurred during voice input extraction: $e';
      }
      print('Unexpected Error during voice input extraction: $e');
      return [];
    }
  }

  // --- Backend API Call for Medicine Name Suggestion ---
  Future<String> _getMedicineSuggestionFromBackend(String input, String patientSummary, {int retryCount = 0}) async {
    if (input.trim().isEmpty) return 'N/A';

    try {
      final response = await _dio.post(
        '$_backendApiBaseUrl/suggest_medicine',
        data: jsonEncode({
          'input_text': input,
          'patient_summary': patientSummary,
        }),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );

      if (response.statusCode == 200) {
        final result = response.data;
        return result['suggestion']?.toString() ?? 'N/A';
      } else if (response.statusCode == 503 && retryCount < 3) {
        print('Backend returned 503. Retrying suggestion in 2 seconds (Retry ${retryCount + 1})...');
        await Future.delayed(const Duration(seconds: 2));
        return _getMedicineSuggestionFromBackend(input, patientSummary, retryCount: retryCount + 1);
      } else {
        print('Backend Error for suggestion: Status ${response.statusCode} - ${response.statusMessage}');
        return 'N/A';
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 503 && retryCount < 3) {
        print('DioException (503) during suggestion backend call. Retrying in 2 seconds (Retry ${retryCount + 1})...');
        await Future.delayed(const Duration(seconds: 2));
        return _getMedicineSuggestionFromBackend(input, patientSummary, retryCount: retryCount + 1);
      }
      print('Error getting medicine suggestion from backend: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return 'N/A';
    } catch (e) {
      print('Unexpected Error getting medicine suggestion: $e');
      return 'N/A';
    }
  }

  // --- Send Feedback to Backend ---
  Future<void> _sendFeedbackToBackend(String originalText, List<MedicinePrescription> correctedMedicines) async {
    try {
      final payload = {
        'original_text': originalText,
        'corrected_medicines': correctedMedicines.map((m) => m.toJson()).toList(),
      };
      await _dio.post(
        '$_backendApiBaseUrl/feedback_extraction',
        data: jsonEncode(payload),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      print('DEBUG: Feedback sent to backend successfully.');
    } on DioException catch (e) {
      print('ERROR: Failed to send feedback to backend: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
    } catch (e) {
      print('ERROR: Unexpected error sending feedback: $e');
    }
  }


  // Function to add a new empty medicine prescription to the list
  void _addNewMedicine() {
    if (!mounted) return;
    setState(() {
      final newMedicine = MedicinePrescription.empty();
      _medicines.add(newMedicine);
      _getOrCreateController(newMedicine.id, 'name', newMedicine.name);
      _getOrCreateController(newMedicine.id, 'dosage', newMedicine.dosage);
      _getOrCreateController(newMedicine.id, 'duration', newMedicine.duration);
      _getOrCreateController(newMedicine.id, 'frequency', newMedicine.frequency);
      _getOrCreateController(newMedicine.id, 'timing', newMedicine.timing);
    });
  }

  // Function to remove a medicine prescription from the list
  void _removeMedicine(String id) {
    if (!mounted) return;
    _fieldControllers[id]?.forEach((field, controller) {
      controller.dispose();
    });
    _fieldControllers.remove(id);
    setState(() {
      _medicines.removeWhere((medicine) => medicine.id == id);
    });
  }

  // Function to save/confirm the medicines list
  void _saveMedicines() async {
    print('Saving medicines:');
    for (var medicine in _medicines) {
      print('  - ${medicine.toJson()}');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicines list saved! (Check console for details)')),
      );
    }

    // Send the current summary and the final (corrected) medicines list as feedback
    await _sendFeedbackToBackend(widget.summaryText, _medicines);

    // Navigate to the next screen (OPDReportFinalScreen)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OpdReportFinalScreen(
          patientId: widget.patientId,
          chiefComplaint: widget.chiefComplaint,
          summaryText: widget.summaryText,
          medicines: _medicines,
        ),
      ),
    );
  }

  // --- Voice Input Dialog (for individual fields) ---
  Future<String?> _showVoiceInputDialog({
    required String initialText,
    required bool isMedicineNameField,
  }) async {
    String currentTranscribedText = initialText;
    String suggestedMedicine = '';
    bool isDialogRecording = false;
    bool isSuggesting = false;
    String dialogError = '';
    double dialogAudioLevel = 0.0;
    TextEditingController dialogInputController = TextEditingController(text: initialText);

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final ThemeData currentTheme = Theme.of(context);
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
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
                          await _audioLevelSubscription?.cancel();
                          _audioLevelSubscription = null;
                          String? path = await _audioRecorder.stop();
                          setDialogState(() {
                            isDialogRecording = false;
                            dialogAudioLevel = 0.0;
                            currentTranscribedText = 'Processing...';
                          });
                          if (path != null) {
                            File audioFile = File(path);
                            List<int> audioBytes = await audioFile.readAsBytes();
                            String audioBase64 = base64Encode(audioBytes);
                            final transcribed = await _performASR(audioBase64, 'en');
                            setDialogState(() {
                              currentTranscribedText = transcribed ?? 'Failed to transcribe.';
                              dialogError = transcribed == null ? 'Failed to transcribe audio.' : '';
                              dialogInputController.text = currentTranscribedText;
                              dialogInputController.selection = TextSelection.fromPosition(TextPosition(offset: dialogInputController.text.length));
                            });
                          } else {
                            setDialogState(() {
                              currentTranscribedText = 'No audio recorded.';
                              dialogError = 'No audio recorded.';
                            });
                          }
                        } else {
                          setDialogState(() {
                            isDialogRecording = true;
                            currentTranscribedText = 'Listening...';
                            dialogError = '';
                            dialogInputController.text = '';
                          });
                          Directory tempDir = await getTemporaryDirectory();
                          _audioFilePath = '${tempDir.path}/temp_audio_field.wav';
                          _audioLevelSubscription = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
                            setDialogState(() {
                              dialogAudioLevel = amp.current;
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
                    if (isDialogRecording)
                      Text(
                        'Audio Level: ${dialogAudioLevel.toStringAsFixed(2)} dB',
                        textAlign: TextAlign.center,
                        style: currentTheme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dialogInputController,
                      onChanged: (value) {
                        setDialogState(() {
                          currentTranscribedText = value;
                          suggestedMedicine = '';
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
                                      final suggestion = await _getMedicineSuggestionFromBackend(dialogInputController.text, widget.summaryText);
                                      setDialogState(() {
                                        suggestedMedicine = suggestion;
                                        isSuggesting = false;
                                      });
                                    },
                            icon: isSuggesting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lightbulb_outline),
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
                                        color: suggestedMedicine == 'N/A' ? Colors.red : currentTheme.primaryColor,
                                      ),
                                    ),
                                  ),
                                  if (suggestedMedicine != 'N/A')
                                    IconButton(
                                      icon: const Icon(Icons.check_circle, color: Colors.green),
                                      onPressed: () {
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
                    Navigator.of(context).pop(null);
                  },
                ),
                TextButton(
                  child: Text('Apply (Current Text)', style: TextStyle(color: currentTheme.primaryColor)),
                  onPressed: () {
                    Navigator.of(context).pop(dialogInputController.text);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      dialogInputController.dispose();
    });
    return result;
  }

  // --- NEW: Dialog for comprehensive voice input for multiple medicines ---
  Future<List<MedicinePrescription>?> _showComprehensiveVoiceInputDialog() async {
    TextEditingController comprehensiveInputController = TextEditingController();
    String currentTranscribedText = '';
    bool isDialogRecording = false;
    bool isExtracting = false;
    String dialogError = '';
    double dialogAudioLevel = 0.0;
    String? selectedLanguage = 'English';
    String? selectedLanguageCode = 'en';

    final result = await showDialog<List<MedicinePrescription>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final ThemeData currentTheme = Theme.of(context);
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
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
                          await _audioLevelSubscription?.cancel();
                          _audioLevelSubscription = null;
                          String? path = await _audioRecorder.stop();
                          setDialogState(() {
                            isDialogRecording = false;
                            dialogAudioLevel = 0.0;
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
                              comprehensiveInputController.text = currentTranscribedText;
                              comprehensiveInputController.selection = TextSelection.fromPosition(TextPosition(offset: comprehensiveInputController.text.length));
                            });
                          } else {
                            setDialogState(() {
                              currentTranscribedText = 'No audio recorded.';
                              dialogError = 'No audio recorded.';
                            });
                          }
                        } else {
                          setDialogState(() {
                            isDialogRecording = true;
                            currentTranscribedText = 'Listening...';
                            dialogError = '';
                            comprehensiveInputController.text = '';
                          });
                          Directory tempDir = await getTemporaryDirectory();
                          _audioFilePath = '${tempDir.path}/temp_audio_comprehensive.wav';
                          _audioLevelSubscription = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
                            setDialogState(() {
                              dialogAudioLevel = amp.current;
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
                    if (isDialogRecording)
                      Text(
                        'Audio Level: ${dialogAudioLevel.toStringAsFixed(2)} dB',
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
                                final extractedMedicines = await _extractMedicinesFromVoiceInputBackend(comprehensiveInputController.text);
                                setDialogState(() {
                                  isExtracting = false;
                                  if (extractedMedicines != null && extractedMedicines.isNotEmpty) {
                                    Navigator.of(context).pop(extractedMedicines);
                                  } else {
                                    dialogError = 'No medicines extracted. Please refine input or try again.';
                                  }
                                });
                              },
                      icon: isExtracting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.playlist_add),
                      label: Text(isExtracting ? 'Extracting...' : 'Extract & Add Medicines'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: currentTheme.primaryColor,
                        foregroundColor: currentTheme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 3,
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel', style: TextStyle(color: currentTheme.hintColor)),
                  onPressed: () {
                    Navigator.of(context).pop(null);
                  },
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      comprehensiveInputController.dispose();
    });
    return result;
  }

  // Widget to build a single medicine card with editable fields
  Widget _buildEditableField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Future<void> Function(TextEditingController) onVoiceInput,
    required Key fieldKey,
  }) {
    final ThemeData currentTheme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: currentTheme.primaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: currentTheme.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: currentTheme.colorScheme.secondary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: currentTheme.textTheme.bodyLarge,
              cursorColor: currentTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: Icon(Icons.mic, color: currentTheme.colorScheme.secondary),
            onPressed: () => onVoiceInput(controller),
            tooltip: 'Voice input for $label',
          ),
        ],
      ),
    );
  }

  // Widget to build a single medicine card with editable fields
  Widget _buildMedicineCard(MedicinePrescription medicine, int index, ThemeData currentTheme) {
    TextEditingController nameController = _getOrCreateController(medicine.id, 'name', medicine.name);
    TextEditingController dosageController = _getOrCreateController(medicine.id, 'dosage', medicine.dosage);
    TextEditingController durationController = _getOrCreateController(medicine.id, 'duration', medicine.duration);
    TextEditingController frequencyController = _getOrCreateController(medicine.id, 'frequency', medicine.frequency);
    TextEditingController timingController = _getOrCreateController(medicine.id, 'timing', medicine.timing);

    return Card(
      key: ValueKey(medicine.id),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: currentTheme.cardColor,
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
                  style: currentTheme.textTheme.titleLarge?.copyWith(
                    color: currentTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red[600], size: 24),
                  onPressed: () => _removeMedicine(medicine.id),
                  tooltip: 'Remove Medicine',
                ),
              ],
            ),
            const Divider(height: 20, thickness: 1.5, color: Colors.grey),
            _buildEditableField(
              context,
              label: 'Name',
              controller: nameController,
              icon: Icons.medication,
              onVoiceInput: (currentController) async {
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: true,
                );
                if (resultText != null && mounted) {
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_name'),
            ),
            _buildEditableField(
              context,
              label: 'Dosage',
              controller: dosageController,
              icon: Icons.medical_information,
              onVoiceInput: (currentController) async {
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: false,
                );
                if (resultText != null && mounted) {
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_dosage'),
            ),
            _buildEditableField(
              context,
              label: 'Duration',
              controller: durationController,
              icon: Icons.calendar_today,
              onVoiceInput: (currentController) async {
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: false,
                );
                if (resultText != null && mounted) {
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_duration'),
            ),
            _buildEditableField(
              context,
              label: 'Frequency',
              controller: frequencyController,
              icon: Icons.access_time,
              onVoiceInput: (currentController) async {
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: false,
                );
                if (resultText != null && mounted) {
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_frequency'),
            ),
            _buildEditableField(
              context,
              label: 'Timing',
              controller: timingController,
              icon: Icons.schedule,
              onVoiceInput: (currentController) async {
                final resultText = await _showVoiceInputDialog(
                  initialText: currentController.text,
                  isMedicineNameField: false,
                );
                if (resultText != null && mounted) {
                  currentController.text = resultText;
                  currentController.selection = TextSelection.fromPosition(TextPosition(offset: currentController.text.length));
                }
              },
              fieldKey: ValueKey('${medicine.id}_timing'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Prescribe Medicines',
          style: currentTheme.appBarTheme.titleTextStyle?.copyWith(
            fontWeight: FontWeight.bold,
            color: currentTheme.colorScheme.onPrimary,
          ),
        ),
        backgroundColor: currentTheme.primaryColor,
        iconTheme: IconThemeData(color: currentTheme.colorScheme.onPrimary),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: currentTheme.textTheme.headlineSmall?.copyWith(color: Colors.red),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _medicines.length,
                        itemBuilder: (context, index) {
                          return _buildMedicineCard(_medicines[index], index, currentTheme);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _addNewMedicine,
                                  icon: const Icon(Icons.add, size: 24),
                                  label: const Text('Add New Medicine'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: currentTheme.colorScheme.secondary,
                                    foregroundColor: currentTheme.colorScheme.onSecondary,
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final extracted = await _showComprehensiveVoiceInputDialog();
                                    if (extracted != null && extracted.isNotEmpty && mounted) {
                                      setState(() {
                                        _medicines.addAll(extracted.map((item) {
                                          final newMedicine = MedicinePrescription.fromJson({
                                            ...item.toJson(),
                                            'id': item.id.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : item.id,
                                          });
                                          _getOrCreateController(newMedicine.id, 'name', newMedicine.name);
                                          _getOrCreateController(newMedicine.id, 'dosage', newMedicine.dosage);
                                          _getOrCreateController(newMedicine.id, 'duration', newMedicine.duration);
                                          _getOrCreateController(newMedicine.id, 'frequency', newMedicine.frequency);
                                          _getOrCreateController(newMedicine.id, 'timing', newMedicine.timing);
                                          return newMedicine;
                                        }).toList());
                                      });
                                    } else if (extracted != null && extracted.isEmpty && mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('No medicines extracted from voice input.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.mic_none, size: 24),
                                  label: const Text('Voice Input (Full)'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: currentTheme.colorScheme.tertiary,
                                    foregroundColor: currentTheme.colorScheme.onTertiary,
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _medicines.isEmpty ? null : _saveMedicines,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: currentTheme.primaryColor,
                                foregroundColor: currentTheme.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 5,
                                textStyle: currentTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              child: const Text('Confirm Medicines & Generate OPD Report'),
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
