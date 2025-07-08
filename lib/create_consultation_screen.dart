// lib/consultation_workflow_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

// Bhashini and Audio Imports
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:just_audio/just_audio.dart';

import 'package:medicare/services/data_loader.dart';

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class ConsultationWorkflowScreen extends StatefulWidget {
  const ConsultationWorkflowScreen({super.key});

  @override
  State<ConsultationWorkflowScreen> createState() => _ConsultationWorkflowScreenState();
}

class _ConsultationWorkflowScreenState extends State<ConsultationWorkflowScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  // --- Patient & Consultation Details ---
  final TextEditingController _patientIdController = TextEditingController();
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _followUpController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  Map<String, dynamic>? _currentPatientData; // Patient details fetched based on ID

  List<String> _selectedMedicines = [];
  List<String> _availableMedicines = [];
  bool _isLoadingMedicines = true;
  String _saveConsultationMessage = '';
  bool _isSavingConsultation = false;

  // --- Bhashini & AI Integration ---
  String? _bhashiniInferenceBaseUrl;
  String? _bhashiniInferenceApiKey;
  Map<String, dynamic>? _pipelineConfigResponse;
  final Dio _dio = Dio();

  bool _isRecording = false;
  bool _isSpeaking = false; // Tracks if TTS is currently playing
  double _currentAudioLevel = 0.0;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _audioFilePath;
  StreamSubscription<Amplitude>? _audioLevelSubscription;

  String _currentVoiceInputTarget = ''; // 'patient_id', 'diagnosis', 'notes', 'summary' etc.
  String _transcribedDoctorInput = '';
  String _aiStatusMessage = 'AI services initializing...';

  // Bhashini API Details (ensure consistency with your setup)
  final String _bhashiniApiKey = '529fda3d00-836e-498b-a266-7d1ea97a667f';
  final String _bhashiniUserId = 'ae98869a2a7542b1a24da628b955e51b';
  final String _bhashiniAuthBaseUrl = 'https://meity-auth.ulcacontrib.org';
  final String _bhashiniPipelineId = "64392f96daac500b55c543cd"; // Ensure this ID supports ASR, Translation, TTS

  @override
  void initState() {
    super.initState();
    _loadMedicines();
    _initializeBhashiniPipeline();
    _audioPlayer.playerStateStream.listen((playerState) {
      if (mounted) {
        setState(() {
          _isSpeaking = playerState.playing && playerState.processingState != ProcessingState.completed;
        });
      }
    });
  }

  @override
  void dispose() {
    _patientIdController.dispose();
    _diagnosisController.dispose();
    _followUpController.dispose();
    _notesController.dispose();
    _audioLevelSubscription?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- Bhashini API Functions (Adapted for this screen) ---
  Future<void> _initializeBhashiniPipeline() async {
    if (!mounted) return;
    setState(() {
      _aiStatusMessage = 'Initializing Bhashini services...';
    });

    try {
      final response = await _dio.post(
        '$_bhashiniAuthBaseUrl/ulca/apis/v0/model/getModelsPipeline',
        options: Options(headers: {
          'Content-Type': 'application/json',
          'ulcaApiKey': _bhashiniApiKey,
          'userID': _bhashiniUserId,
        }),
        data: jsonEncode({
          "pipelineTasks": [
            {"taskType": "asr"},
            {"taskType": "translation"}, // Include if you need patient-side translation/cross-language convo
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
          } else {
            _aiStatusMessage = 'Missing pipelineInferenceAPIEndPoint in Bhashini config response.';
          }

          if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
             _aiStatusMessage = 'Failed to get Bhashini inference API details. Check Bhashini configuration.';
          }
        } else {
          _aiStatusMessage = 'Invalid pipeline configuration response (empty data).';
        }
      } else {
        _aiStatusMessage = 'Failed to fetch Bhashini pipeline config: ${response.statusCode} - ${response.data}';
      }
    } catch (e) {
      _aiStatusMessage = 'Error initializing Bhashini pipeline: $e';
      print('Error initializing Bhashini pipeline: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (_aiStatusMessage.contains('Error') || _aiStatusMessage.contains('Failed')) {
            // Keep error message
          } else {
            _aiStatusMessage = 'AI services ready.';
          }
        });
      }
    }
  }

  String? _findServiceId(String taskType, String sourceLanguage, {String? targetLanguage, String? voiceGender}) {
    if (_pipelineConfigResponse == null) return null;

    final pipelineResponseConfig = _pipelineConfigResponse!['pipelineResponseConfig'];
    if (pipelineResponseConfig == null) return null;

    for (var config in pipelineResponseConfig) {
      if (config['taskType'] == taskType) {
        for (var configDetail in config['config']) {
          final languageConfig = configDetail['language'];
          if (languageConfig != null && languageConfig['sourceLanguage'] == sourceLanguage) {
            if (targetLanguage == null || languageConfig['targetLanguage'] == targetLanguage) {
              if (taskType == 'tts') {
                final configuredGender = configDetail['gender'];
                if (configuredGender == null || configuredGender == voiceGender) {
                  return configDetail['serviceId'];
                }
              } else if (taskType == 'translation') {
                if (languageConfig['targetLanguage'] == targetLanguage) {
                  return configDetail['serviceId'];
                }
              } else {
                return configDetail['serviceId'];
              }
            }
          }
        }
      }
    }
    return null;
  }

  Future<String?> _performASR(String audioBase64, String sourceLanguageCode) async {
    if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
      if (mounted) setState(() => _aiStatusMessage = 'Bhashini Inference API not initialized.');
      return null;
    }

    final asrServiceId = _findServiceId('asr', sourceLanguageCode);
    if (asrServiceId == null) {
      if (mounted) setState(() => _aiStatusMessage = 'ASR service not found for language ($sourceLanguageCode).');
      return null;
    }

    try {
      final response = await _dio.post(
        _bhashiniInferenceBaseUrl!,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': _bhashiniInferenceApiKey!,
        }),
        data: jsonEncode({
          "pipelineTasks": [
            {
              "taskType": "asr",
              "config": {
                "language": {"sourceLanguage": sourceLanguageCode},
                "serviceId": asrServiceId
              }
            }
          ],
          "inputData": {
            "audio": [{"audioContent": audioBase64}]
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null && data['pipelineResponse'] != null && data['pipelineResponse'][0]['output'] != null) {
          final transcribed = data['pipelineResponse'][0]['output'][0]['source'];
          return transcribed.toString().trim();
        }
      }
      if (mounted) setState(() => _aiStatusMessage = 'ASR failed or returned empty.');
      return null;
    } on DioException catch (e) {
      if (mounted) setState(() => _aiStatusMessage = 'ASR Error: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      if (mounted) setState(() => _aiStatusMessage = 'ASR Error: $e');
      return null;
    }
  }

  // Simplified toggle recording for doctor's input (always English)
  Future<void> _toggleRecording(TextEditingController controller, String targetField) async {
    if (!mounted) return;
    if (_isSpeaking) {
      setState(() => _aiStatusMessage = 'Please wait for audio to finish speaking.');
      return;
    }

    if (_isRecording) {
      // Stop recording
      try {
        _audioLevelSubscription?.cancel();
        _audioLevelSubscription = null;
        String? path = await _audioRecorder.stop();

        if (mounted) {
          setState(() {
            _isRecording = false;
            _currentAudioLevel = 0.0;
            _currentVoiceInputTarget = '';
            _transcribedDoctorInput = 'Processing...';
            _aiStatusMessage = 'Processing your voice input...';
          });
        }

        if (path != null && path.isNotEmpty) {
          File audioFile = File(path);
          List<int> audioBytes = await audioFile.readAsBytes();
          String audioBase64 = base64Encode(audioBytes);

          final transcribed = await _performASR(audioBase64, 'en'); // Doctor speaks English

          if (mounted) {
            setState(() {
              _transcribedDoctorInput = transcribed ?? 'Failed to transcribe. Please try again.';
              _aiStatusMessage = transcribed == null ? 'Transcription failed.' : 'Voice input processed.';
            });
          }

          if (transcribed != null && transcribed.isNotEmpty) {
            controller.text = transcribed;
            controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
          } else {
            controller.clear();
          }
        } else {
          if (mounted) {
            setState(() {
              _transcribedDoctorInput = 'No audio recorded.';
              _aiStatusMessage = 'No audio recorded. Tap mic to try again.';
            });
          }
          controller.clear();
        }
      } catch (e) {
        if (mounted) setState(() => _aiStatusMessage = 'Error stopping recording: $e');
        print('Error stopping recording: $e');
      }
    } else {
      // Start recording
      if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
        setState(() => _aiStatusMessage = 'AI services not ready for voice input. Please wait.');
        return;
      }
      if (await _audioRecorder.hasPermission()) {
        try {
          Directory tempDir = await getTemporaryDirectory();
          _audioFilePath = '${tempDir.path}/doctor_input.wav';

          await _audioRecorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              numChannels: 1,
              sampleRate: 16000,
              bitRate: 16,
            ),
            path: _audioFilePath!,
          );

          _audioLevelSubscription = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
            if (mounted) {
              setState(() {
                _currentAudioLevel = amp.current;
              });
            }
          });

          if (mounted) {
            setState(() {
              _isRecording = true;
              _currentVoiceInputTarget = targetField;
              _transcribedDoctorInput = 'Listening...';
              _aiStatusMessage = 'Recording voice input for $targetField...';
            });
          }
        } catch (e) {
          if (mounted) setState(() => _aiStatusMessage = 'Error starting recording: $e');
          print('Error starting recording: $e');
        }
      } else {
        if (mounted) setState(() => _aiStatusMessage = 'Microphone permission not granted.');
      }
    }
  }

  // --- LLM Integration Placeholders (Enhanced for this screen) ---
  Future<void> _generateSummary() async {
    if (_isSavingConsultation || _isRecording || _isSpeaking) {
      setState(() => _aiStatusMessage = 'Please wait for current operations to finish.');
      return;
    }
    if (_patientIdController.text.isEmpty && _diagnosisController.text.isEmpty && _notesController.text.isEmpty) {
      setState(() => _aiStatusMessage = 'Please enter patient ID, diagnosis, or notes to generate a summary.');
      return;
    }
    setState(() {
      _aiStatusMessage = 'Generating summary... (Simulated LLM call)';
    });
    // Simulate LLM call based on available text inputs
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      String summaryText = 'Consultation Summary:\n';
      if (_currentPatientData != null) {
        summaryText += 'Patient: ${_currentPatientData!['name']} (ID: ${_currentPatientData!['id']}), Chief Complaint: ${_currentPatientData!['chiefComplaint']}.\n';
      } else if (_patientIdController.text.isNotEmpty) {
        summaryText += 'Patient ID: ${_patientIdController.text}.\n';
      }
      if (_diagnosisController.text.isNotEmpty) {
        summaryText += 'Diagnosis: ${_diagnosisController.text}.\n';
      }
      if (_notesController.text.isNotEmpty) {
        summaryText += 'Notes: ${_notesController.text}.\n';
      }
      summaryText += 'This is a simulated summary generated by AI.';

      setState(() {
        _notesController.text = summaryText; // Populate notes with summary
        _aiStatusMessage = 'Summary generated.';
      });
    }
  }

  Future<void> _suggestMedicines() async {
    if (_isSavingConsultation || _isRecording || _isSpeaking) {
      setState(() => _aiStatusMessage = 'Please wait for current operations to finish.');
      return;
    }
    if (_diagnosisController.text.isEmpty) {
      setState(() => _aiStatusMessage = 'Please enter a diagnosis to get medicine suggestions.');
      return;
    }
    setState(() {
      _aiStatusMessage = 'Suggesting medicines... (Simulated LLM call)';
    });
    // Simulate LLM call for medicine suggestion based on diagnosis
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      // Add some dummy suggestions based on "keywords" for demonstration
      List<String> suggested = [];
      String diagnosisLower = _diagnosisController.text.toLowerCase();
      if (diagnosisLower.contains('fever')) {
        suggested.add('Paracetamol');
        suggested.add('Ibuprofen');
      }
      if (diagnosisLower.contains('headache')) {
        suggested.add('Aspirin');
      }
      if (diagnosisLower.contains('cough')) {
        suggested.add('Cough Syrup');
      }
      if (diagnosisLower.contains('cold')) {
        suggested.add('Antihistamine');
      }
      
      // Add unique suggestions to _selectedMedicines
      for (String med in suggested) {
        if (!_selectedMedicines.contains(med)) {
          _selectedMedicines.add(med);
        }
      }

      setState(() {
        _aiStatusMessage = 'Medicines suggested.';
      });
    }
  }

  // --- Load Medicines for Autocomplete ---
  Future<void> _loadMedicines() async {
    setState(() {
      _isLoadingMedicines = true;
    });
    try {
      final dataLoader = Provider.of<DataLoader>(context, listen: false);
      final medicines = await dataLoader.loadCsvData('medicines');
      if (medicines != null && medicines.isNotEmpty) {
        setState(() {
          _availableMedicines = medicines.map((e) => e['name'].toString()).toList();
        });
      }
    } catch (e) {
      print('Error loading medicines: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load medicines: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMedicines = false;
        });
      }
    }
  }

  // --- Fetch Patient Details for Consultation ---
  Future<void> _fetchPatientDetails() async {
    final patientId = _patientIdController.text.trim();
    if (patientId.isEmpty) {
      setState(() {
        _aiStatusMessage = 'Please enter a Patient ID.';
        _currentPatientData = null;
      });
      return;
    }

    setState(() {
      _aiStatusMessage = 'Fetching patient details...';
      _currentPatientData = null;
    });

    try {
      final patientDocRef = _firestore
          .collection('artifacts')
          .doc(__app_id)
          .collection('public')
          .doc('patients')
          .collection('data')
          .doc(patientId);
      final patientSnapshot = await patientDocRef.get();

      if (patientSnapshot.exists && patientSnapshot.data() != null) {
        setState(() {
          _currentPatientData = patientSnapshot.data();
          _aiStatusMessage = 'Patient details loaded.';
        });
      } else {
        setState(() {
          _aiStatusMessage = 'Patient with ID "$patientId" not found. You can still save the consultation, but patient details will be limited.';
          _currentPatientData = {
            'id': patientId,
            'name': 'Unknown Patient',
            'age': 'N/A',
            'gender': 'N/A',
            'chiefComplaint': 'N/A',
            'contactNumber': 'N/A',
            'address': 'N/A',
            'email': 'N/A',
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiStatusMessage = 'Error fetching patient details: $e';
          _currentPatientData = null;
        });
      }
      print('Error fetching patient details: $e');
    }
  }

  // --- Save Consultation (OPD Report) ---
  Future<void> _saveConsultation() async {
    if (_patientIdController.text.trim().isEmpty) {
      setState(() {
        _saveConsultationMessage = 'Please enter Patient ID to save consultation.';
      });
      return;
    }
    if (_diagnosisController.text.trim().isEmpty) {
      setState(() {
        _saveConsultationMessage = 'Diagnosis cannot be empty.';
      });
      return;
    }

    setState(() {
      _isSavingConsultation = true;
      _saveConsultationMessage = 'Saving consultation...';
    });

    try {
      final String consultationId = _uuid.v4();
      final String doctorId = _auth.currentUser?.uid ?? 'unknown_doctor';
      final doctorDoc = await _firestore.collection('artifacts').doc(__app_id).collection('users').doc(doctorId).get();
      final doctorName = doctorDoc.exists ? (doctorDoc.data()?['name'] ?? 'Unknown Doctor') : 'Unknown Doctor';

      // Use _currentPatientData if fetched, otherwise use fallback from _patientIdController
      Map<String, dynamic> patientDetailsToSave = _currentPatientData ?? {
        'id': _patientIdController.text.trim(),
        'name': 'Unknown Patient',
        'age': 'N/A',
        'gender': 'N/A',
        'chiefComplaint': 'N/A',
        'contactNumber': 'N/A',
        'address': 'N/A',
        'email': 'N/A',
      };

      final consultationData = {
        'consultationId': consultationId,
        'patientId': patientDetailsToSave['id'],
        'patientName': patientDetailsToSave['name'],
        'patientAge': patientDetailsToSave['age'],
        'patientGender': patientDetailsToSave['gender'],
        'patientChiefComplaint': patientDetailsToSave['chiefComplaint'],
        'patientContactNumber': patientDetailsToSave['contactNumber'],
        'patientAddress': patientDetailsToSave['address'],
        'patientEmail': patientDetailsToSave['email'],
        'doctorId': doctorId,
        'doctorName': doctorName,
        'diagnosis': _diagnosisController.text.trim(),
        'prescribedMedicines': _selectedMedicines,
        'followUpInstructions': _followUpController.text.trim(),
        'notes': _notesController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'appId': __app_id,
      };

      await _firestore
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(doctorId)
          .collection('consultations')
          .doc(consultationId)
          .set(consultationData);

      if (mounted) {
        setState(() {
          _saveConsultationMessage = 'Consultation saved successfully!';
          _isSavingConsultation = false;
          // Clear form after saving
          _patientIdController.clear();
          _diagnosisController.clear();
          _followUpController.clear();
          _notesController.clear();
          _selectedMedicines.clear();
          _currentPatientData = null; // Clear patient data
        });
        _showConsultationSuccessDialog(consultationData);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveConsultationMessage = 'Error saving consultation: $e';
          _isSavingConsultation = false;
        });
      }
      print('Error saving consultation: $e');
    }
  }

  void _showConsultationSuccessDialog(Map<String, dynamic> consultationData) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Consultation Saved!'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Consultation ID: ${consultationData['consultationId']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                Text('Patient Name: ${consultationData['patientName']}'),
                Text('Patient ID: ${consultationData['patientId']}'),
                Text('Age: ${consultationData['patientAge']}'),
                Text('Gender: ${consultationData['patientGender']}'),
                // Only show if available, chief complaint might not be in _currentPatientData initially
                if (consultationData['patientChiefComplaint'] != null && consultationData['patientChiefComplaint'] != 'N/A')
                  Text('Chief Complaint: ${consultationData['patientChiefComplaint']}'),
                Text('Contact: ${consultationData['patientContactNumber']}'),
                Text('Email: ${consultationData['patientEmail']}'),
                const Divider(),
                Text('Doctor Name: ${consultationData['doctorName']}'),
                Text('Diagnosis: ${consultationData['diagnosis']}'),
                Text('Prescribed Medicines: ${consultationData['prescribedMedicines'].join(', ')}'),
                Text('Follow-up: ${consultationData['followUpInstructions']}'),
                if (consultationData['notes'] != null && consultationData['notes'].isNotEmpty)
                  Text('Notes: ${consultationData['notes']}'),
                Text('Date: ${DateFormat('yyyy-MM-dd HH:mm').format((consultationData['timestamp'] as Timestamp).toDate())}'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);
    final bool aiServicesReady = _bhashiniInferenceBaseUrl != null && _bhashiniInferenceApiKey != null && _pipelineConfigResponse != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Consultation'),
        backgroundColor: currentTheme.appBarTheme.backgroundColor,
        elevation: currentTheme.appBarTheme.elevation,
      ),
      backgroundColor: currentTheme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'AI Services Status: $_aiStatusMessage',
              style: currentTheme.textTheme.bodyMedium?.copyWith(
                color: aiServicesReady ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // --- Patient ID & Details Section ---
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              color: currentTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patient Information',
                      style: currentTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _patientIdController,
                            decoration: InputDecoration(
                              labelText: 'Patient ID',
                              hintText: 'Enter existing patient ID',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            style: currentTheme.textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () => _fetchPatientDetails(),
                          icon: const Icon(Icons.search),
                          label: const Text('Fetch'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: currentTheme.primaryColor,
                            foregroundColor: currentTheme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_currentPatientData != null) ...[
                      Text('Name: ${_currentPatientData!['name'] ?? 'N/A'}', style: currentTheme.textTheme.bodyLarge),
                      Text('Age: ${_currentPatientData!['age'] ?? 'N/A'}', style: currentTheme.textTheme.bodyLarge),
                      Text('Gender: ${_currentPatientData!['gender'] ?? 'N/A'}', style: currentTheme.textTheme.bodyLarge),
                      Text('Chief Complaint: ${_currentPatientData!['chiefComplaint'] ?? 'N/A'}', style: currentTheme.textTheme.bodyLarge),
                      Text('Contact: ${_currentPatientData!['contactNumber'] ?? 'N/A'}', style: currentTheme.textTheme.bodyLarge),
                      Text('Email: ${_currentPatientData!['email'] ?? 'N/A'}', style: currentTheme.textTheme.bodyLarge),
                    ] else ...[
                      Text('Enter Patient ID and click "Fetch" to load details.', style: currentTheme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                    ]
                  ],
                ),
              ),
            ),

            // --- Doctor's Assessment & AI Tools ---
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              color: currentTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doctor\'s Assessment & AI Tools',
                      style: currentTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    // Diagnosis Input with Voice
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _diagnosisController,
                            decoration: InputDecoration(
                              labelText: 'Diagnosis',
                              hintText: 'Enter your diagnosis here',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: currentTheme.inputDecorationTheme.fillColor,
                            ),
                            style: currentTheme.textTheme.bodyLarge,
                            maxLines: 3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: aiServicesReady && !_isSpeaking ? () => _toggleRecording(_diagnosisController, 'diagnosis') : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isSpeaking
                                  ? Colors.grey[400]
                                  : (_isRecording && _currentVoiceInputTarget == 'diagnosis' ? Colors.redAccent : currentTheme.primaryColor),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isRecording && _currentVoiceInputTarget == 'diagnosis') ? Colors.red.withOpacity(0.4) : currentTheme.primaryColor.withOpacity(0.3),
                                  blurRadius: (_isRecording && _currentVoiceInputTarget == 'diagnosis') ? 10 : 3,
                                  spreadRadius: (_isRecording && _currentVoiceInputTarget == 'diagnosis') ? 3 : 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isSpeaking ? Icons.volume_up : (_isRecording && _currentVoiceInputTarget == 'diagnosis' ? Icons.stop : Icons.mic),
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_currentVoiceInputTarget == 'diagnosis' && _transcribedDoctorInput.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Transcribed: $_transcribedDoctorInput',
                          style: currentTheme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (_isRecording && _currentVoiceInputTarget == 'diagnosis')
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          'Audio Level: ${_currentAudioLevel.toStringAsFixed(2)} dB',
                          textAlign: TextAlign.center,
                          style: currentTheme.textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Medicine Suggestion
                    Text(
                      'Prescribed Medicines:',
                      style: currentTheme.textTheme.titleMedium,
                    ),
                    _isLoadingMedicines
                        ? const Center(child: CircularProgressIndicator())
                        : Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text == '') {
                                return const Iterable<String>.empty();
                              }
                              return _availableMedicines.where((String option) {
                                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            onSelected: (String selection) {
                              if (!_selectedMedicines.contains(selection)) {
                                setState(() {
                                  _selectedMedicines.add(selection);
                                });
                              }
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: InputDecoration(
                                  labelText: 'Search & Add Medicine',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () {
                                      if (textEditingController.text.isNotEmpty && !_selectedMedicines.contains(textEditingController.text)) {
                                        setState(() {
                                          _selectedMedicines.add(textEditingController.text);
                                          textEditingController.clear();
                                        });
                                      }
                                    },
                                  ),
                                ),
                                style: currentTheme.textTheme.bodyLarge,
                                onSubmitted: (_) => onFieldSubmitted(),
                              );
                            },
                          ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: aiServicesReady && !_isSavingConsultation && !_isRecording && !_isSpeaking ? _suggestMedicines : null,
                      icon: const Icon(Icons.medication),
                      label: const Text('Suggest Medicines (LLM)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: currentTheme.colorScheme.secondary,
                        foregroundColor: currentTheme.colorScheme.onSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _selectedMedicines.map((medicine) {
                        return Chip(
                          label: Text(medicine),
                          onDeleted: () {
                            setState(() {
                              _selectedMedicines.remove(medicine);
                            });
                          },
                          backgroundColor: currentTheme.chipTheme.backgroundColor,
                          labelStyle: currentTheme.chipTheme.labelStyle,
                          deleteIconColor: currentTheme.chipTheme.deleteIconColor,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Follow-up
                    TextField(
                      controller: _followUpController,
                      decoration: InputDecoration(
                        labelText: 'Follow-up Instructions',
                        hintText: 'e.g., Review in 1 week, take medicines as prescribed',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: currentTheme.inputDecorationTheme.fillColor,
                      ),
                      style: currentTheme.textTheme.bodyLarge,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    // Notes Input with Voice & Summary Generation
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _notesController,
                            decoration: InputDecoration(
                              labelText: 'Additional Notes (Optional)',
                              hintText: 'Any other relevant observations',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: currentTheme.inputDecorationTheme.fillColor,
                            ),
                            style: currentTheme.textTheme.bodyLarge,
                            maxLines: 3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: aiServicesReady && !_isSpeaking ? () => _toggleRecording(_notesController, 'notes') : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isSpeaking
                                  ? Colors.grey[400]
                                  : (_isRecording && _currentVoiceInputTarget == 'notes' ? Colors.redAccent : currentTheme.primaryColor),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isRecording && _currentVoiceInputTarget == 'notes') ? Colors.red.withOpacity(0.4) : currentTheme.primaryColor.withOpacity(0.3),
                                  blurRadius: (_isRecording && _currentVoiceInputTarget == 'notes') ? 10 : 3,
                                  spreadRadius: (_isRecording && _currentVoiceInputTarget == 'notes') ? 3 : 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isSpeaking ? Icons.volume_up : (_isRecording && _currentVoiceInputTarget == 'notes' ? Icons.stop : Icons.mic),
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_currentVoiceInputTarget == 'notes' && _transcribedDoctorInput.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Transcribed: $_transcribedDoctorInput',
                          style: currentTheme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (_isRecording && _currentVoiceInputTarget == 'notes')
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          'Audio Level: ${_currentAudioLevel.toStringAsFixed(2)} dB',
                          textAlign: TextAlign.center,
                          style: currentTheme.textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: aiServicesReady && !_isSavingConsultation && !_isRecording && !_isSpeaking ? _generateSummary : null,
                      icon: const Icon(Icons.summarize),
                      label: const Text('Generate Summary (LLM)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: currentTheme.colorScheme.secondary,
                        foregroundColor: currentTheme.colorScheme.onSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // --- Save OPD Report Button ---
            ElevatedButton.icon(
              onPressed: _isSavingConsultation || _isRecording || _isSpeaking ? null : _saveConsultation,
              icon: _isSavingConsultation ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save, size: 28),
              label: Text(
                _isSavingConsultation ? 'Saving...' : 'Save OPD Report',
                style: const TextStyle(fontSize: 20),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: currentTheme.primaryColor,
                foregroundColor: currentTheme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 5,
                minimumSize: Size(double.infinity, 60),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              _saveConsultationMessage,
              style: currentTheme.textTheme.bodyMedium?.copyWith(
                color: _saveConsultationMessage.contains('Error') || _saveConsultationMessage.contains('Failed') ? Colors.red : Colors.green,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
