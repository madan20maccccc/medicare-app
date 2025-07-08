// lib/patient_details_form_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:record/record.dart'; // For audio recording
import 'package:path_provider/path_provider.dart'; // For temporary file paths
import 'dart:io'; // For File operations
import 'dart:async'; // For StreamSubscription
import 'package:uuid/uuid.dart'; // For generating unique IDs
import 'package:just_audio/just_audio.dart'; // For playing audio

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');
const String __firebase_config = String.fromEnvironment('FIREBASE_CONFIG', defaultValue: '{}');
const String __initial_auth_token = String.fromEnvironment('INITIAL_AUTH_TOKEN', defaultValue: '');

class PatientDetailsFormScreen extends StatefulWidget {
  const PatientDetailsFormScreen({super.key});

  @override
  State<PatientDetailsFormScreen> createState() => _PatientDetailsFormScreenState();
}

class _PatientDetailsFormScreenState extends State<PatientDetailsFormScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid(); // For generating patient IDs

  String? _userId;
  bool _isFirebaseInitialized = false;
  String _firebaseInitError = '';

  String? _selectedLanguage = 'English';
  String? _selectedLanguageCode = 'en';
  String? _selectedVoiceGender = 'male'; // Default voice for TTS

  bool _isRecording = false;
  bool _isSpeaking = false; // Tracks if TTS is currently playing
  bool _isLoading = false;
  String _currentQuestion = ''; // Stores the question in the patient's language
  String _originalEnglishQuestion = ''; // Stores the original English question
  String _transcribedAnswer = ''; // Stores the answer in patient's language (from ASR)
  String _translatedEnglishAnswer = ''; // Stores the answer translated to English

  String _statusMessage = 'Select a language and start the interview.';
  String _errorMessage = '';
  double _currentAudioLevel = 0.0;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer(); // Audio player for TTS
  String? _audioFilePath;
  StreamSubscription<Amplitude>? _audioLevelSubscription;

  // Bhashini API Details (same as in other screens)
  final String _bhashiniApiKey = '529fda3d00-836e-498b-a266-7d1ea97a667f';
  final String _bhashiniUserId = 'ae98869a2a7542b1a24da628b955e51b';
  final String _bhashiniAuthBaseUrl = 'https://meity-auth.ulcacontrib.org';
  final String _bhashiniPipelineId = "64392f96daac500b55c543cd";

  String? _bhashiniInferenceBaseUrl;
  String? _bhashiniInferenceApiKey;
  Map<String, dynamic>? _pipelineConfigResponse;

  final Dio _dio = Dio();

  // Patient details controllers - these will now store English answers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _chiefComplaintController = TextEditingController();
  final TextEditingController _contactNumberController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController(); // NEW: Email controller

  List<Map<String, dynamic>> _questions = [];
  int _currentQuestionIndex = 0;
  String? _patientId; // To store the generated patient ID

  @override
  void initState() {
    super.initState();
    _initializeFirebaseAndBhashini();
    _initializeQuestions();
    // Listen for audio player state changes to update _isSpeaking
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
    _audioLevelSubscription?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose(); // Dispose the audio player
    _nameController.dispose();
    _ageController.dispose();
    _genderController.dispose();
    _chiefComplaintController.dispose();
    _contactNumberController.dispose();
    _addressController.dispose();
    _emailController.dispose(); // NEW: Dispose email controller
    super.dispose();
  }

  Future<void> _initializeFirebaseAndBhashini() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true; // Set loading state
      _firebaseInitError = '';
      _statusMessage = 'Initializing services...';
    });

    try {
      // Authenticate user for Firestore access
      // If a user is already signed in (e.g., from a previous session or custom token),
      // we don't need to sign in again. Otherwise, sign in anonymously.
      if (_auth.currentUser == null) {
        if (__initial_auth_token.isNotEmpty) {
          await _auth.signInWithCustomToken(__initial_auth_token);
          print('Firebase: Signed in with custom token.');
        } else {
          await _auth.signInAnonymously();
          print('Firebase: Signed in anonymously.');
        }
      } else {
        print('Firebase: User already signed in: ${_auth.currentUser!.uid}');
      }
      _userId = _auth.currentUser?.uid;
      _isFirebaseInitialized = true;
      print('Firebase initialized. User ID: $_userId');

      await _initializeBhashiniPipeline();
    } catch (e) {
      if (mounted) {
        setState(() {
          _firebaseInitError = 'Failed to initialize Firebase or Bhashini: $e';
          _statusMessage = 'Initialization failed.';
          _isLoading = false; // Reset loading on error
        });
      }
      print('Initialization error: $e');
    }
  }

  void _initializeQuestions() {
    _questions = [
      {'question': 'What is your full name?', 'controller': _nameController, 'field': 'name'},
      {'question': 'What is your age?', 'controller': _ageController, 'field': 'age'},
      {'question': 'What is your gender? (e.g., Male, Female, Other)', 'controller': _genderController, 'field': 'gender'},
      {'question': 'What is your chief complaint or main reason for visiting today?', 'controller': _chiefComplaintController, 'field': 'chiefComplaint'},
      {'question': 'What is your contact number?', 'controller': _contactNumberController, 'field': 'contactNumber'},
      {'question': 'What is your current address?', 'controller': _addressController, 'field': 'address'},
      {'question': 'What is your email address?', 'controller': _emailController, 'field': 'email'}, // NEW: Email question
    ];
  }

  // Helper function to convert English number words to digits
  String _convertWordsToDigits(String text) {
    final Map<String, String> wordToDigit = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'ten': '10', 'eleven': '11', 'twelve': '12', 'thirteen': '13',
      'fourteen': '14', 'fifteen': '15', 'sixteen': '16', 'seventeen': '17',
      'eighteen': '18', 'nineteen': '19', 'twenty': '20', 'thirty': '30',
      'forty': '40', 'fifty': '50', 'sixty': '60', 'seventy': '70',
      'eighty': '80', 'ninety': '90', 'hundred': '00', 'thousand': '000',
      'million': '000000',
      // Add more as needed, but for age/contact, simple ones are usually enough
    };

    // Replace common number words with digits
    String processedText = text.toLowerCase();
    wordToDigit.forEach((word, digit) {
      processedText = processedText.replaceAll(word, digit);
    });

    // Remove spaces and non-digit characters for fields like contact number
    if (processedText.contains(RegExp(r'\d'))) { // Only process if it contains at least one digit
      processedText = processedText.replaceAll(RegExp(r'[^0-9]'), '');
    }
    
    return processedText;
  }

  // --- Bhashini API Functions ---

  Future<void> _initializeBhashiniPipeline() async {
    if (!mounted) return;
    setState(() {
      _errorMessage = '';
      _pipelineConfigResponse = null;
      _bhashiniInferenceBaseUrl = null;
      _bhashiniInferenceApiKey = null;
      // _isLoading is already true from _initializeFirebaseAndBhashini
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
            {"taskType": "translation"}, // Ensure translation is requested
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
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_errorMessage.isEmpty) {
            _statusMessage = 'Bhashini services ready. Tap "Start Interview" to begin.';
          } else {
            _statusMessage = 'Bhashini initialization failed. $_errorMessage';
          }
        });
      }
    }
  }

  String? _findServiceId(String taskType, String sourceLanguage, {String? targetLanguage, String? voiceGender}) {
    if (_pipelineConfigResponse == null) {
      print('DEBUG: _pipelineConfigResponse is null when trying to find serviceId for $taskType.');
      return null;
    }

    final pipelineResponseConfig = _pipelineConfigResponse!['pipelineResponseConfig'];
    if (pipelineResponseConfig == null) {
      print('DEBUG: pipelineResponseConfig is null when trying to find serviceId for $taskType.');
      return null;
    }

    print('DEBUG: Searching for $taskType service for language: $sourceLanguage, target: $targetLanguage, gender: $voiceGender');
    for (var config in pipelineResponseConfig) {
      if (config['taskType'] == taskType) {
        for (var configDetail in config['config']) {
          final languageConfig = configDetail['language'];
          if (languageConfig != null && languageConfig['sourceLanguage'] == sourceLanguage) {
            if (targetLanguage == null || languageConfig['targetLanguage'] == targetLanguage) {
              // For TTS, check voiceGender explicitly, but be flexible if Bhashini doesn't specify gender
              if (taskType == 'tts') {
                final configuredGender = configDetail['gender'];
                print('DEBUG: Found TTS config for language $sourceLanguage, configured gender: $configuredGender. Requested gender: $voiceGender');
                // If Bhashini config has no gender, or if it matches the requested gender, it's a match.
                if (configuredGender == null || configuredGender == voiceGender) {
                  print('DEBUG: Found matching TTS serviceId: ${configDetail['serviceId']}');
                  return configDetail['serviceId'];
                }
              } else if (taskType == 'translation') {
                // For translation, ensure targetLanguage matches
                if (languageConfig['targetLanguage'] == targetLanguage) {
                  print('DEBUG: Found matching Translation serviceId: ${configDetail['serviceId']} for $sourceLanguage to $targetLanguage');
                  return configDetail['serviceId'];
                }
              }
              else { // For ASR, gender and target language are not relevant
                print('DEBUG: Found matching $taskType serviceId: ${configDetail['serviceId']}');
                return configDetail['serviceId'];
              }
            }
          }
        }
      }
    }
    print('DEBUG: No $taskType serviceId found for $sourceLanguage -> $targetLanguage (gender: $voiceGender)');
    return null;
  }

  // Performs Speech-to-Text (ASR) using Bhashini Inference API.
  Future<String?> _performASR(String audioBase64, String sourceLanguageCode) async {
    if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
      if (mounted) setState(() => _errorMessage = 'Bhashini Inference API not initialized.');
      return null;
    }

    final asrServiceId = _findServiceId('asr', sourceLanguageCode);
    if (asrServiceId == null) {
      if (mounted) setState(() => _errorMessage = 'ASR service not found for language ($sourceLanguageCode).');
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
      if (mounted) setState(() => _errorMessage = 'ASR failed or returned empty.');
      return null;
    } on DioException catch (e) {
      if (mounted) setState(() => _errorMessage = 'ASR Error: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'ASR Error: $e');
      return null;
    }
  }

  // NEW: Performs Text Translation using Bhashini Inference API.
  Future<String?> _performTranslation(String text, String sourceLanguageCode, String targetLanguageCode) async {
    if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
      print('DEBUG: Bhashini Inference API not initialized for translation.');
      return null;
    }

    final translationServiceId = _findServiceId('translation', sourceLanguageCode, targetLanguage: targetLanguageCode);
    if (translationServiceId == null) {
      print('DEBUG: Translation service not found for $sourceLanguageCode to $targetLanguageCode.');
      return null;
    }

    try {
      print('DEBUG: Attempting Translation for text: "$text" from $sourceLanguageCode to $targetLanguageCode');
      final response = await _dio.post(
        _bhashiniInferenceBaseUrl!,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': _bhashiniInferenceApiKey!,
        }),
        data: jsonEncode({
          "pipelineTasks": [
            {
              "taskType": "translation",
              "config": {
                "language": {
                  "sourceLanguage": sourceLanguageCode,
                  "targetLanguage": targetLanguageCode
                },
                "serviceId": translationServiceId
              }
            }
          ],
          "inputData": {
            "input": [{"source": text}]
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null && data['pipelineResponse'] != null && data['pipelineResponse'][0]['output'] != null) {
          final translatedText = data['pipelineResponse'][0]['output'][0]['target'];
          print('DEBUG: Translation API returned: "$translatedText"');
          return translatedText.toString().trim();
        }
      }
      print('DEBUG: Translation API failed or returned empty. Status: ${response.statusCode}, Data: ${response.data}');
      return null;
    } on DioException catch (e) {
      print('DEBUG: DioException during Translation API call: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      print('DEBUG: Generic Error during Translation API call: $e');
      return null;
    }
  }


  // Performs Text-to-Speech (TTS) using Bhashini Inference API.
  // Returns base64 encoded audio.
  Future<String?> _performTTS(String text, String targetLanguageCode, String voiceGender) async {
    if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
      if (mounted) setState(() => _errorMessage = 'Bhashini Inference API not initialized.');
      return null;
    }

    final ttsServiceId = _findServiceId('tts', targetLanguageCode, voiceGender: voiceGender);
    if (ttsServiceId == null) {
      if (mounted) setState(() => _errorMessage = 'TTS service not found for language ($targetLanguageCode) and gender ($voiceGender). Please select another language/gender.');
      return null;
    }

    try {
      print('DEBUG: Attempting TTS for text: "$text" in language: $targetLanguageCode, gender: $voiceGender');
      final response = await _dio.post(
        _bhashiniInferenceBaseUrl!,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': _bhashiniInferenceApiKey!,
        }),
        data: jsonEncode({
          "pipelineTasks": [
            {
              "taskType": "tts",
              "config": {
                "language": {"sourceLanguage": targetLanguageCode},
                "serviceId": ttsServiceId,
                "gender": voiceGender // Include gender for TTS
              }
            }
          ],
          "inputData": {
            "input": [{"source": text}]
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null && data['pipelineResponse'] != null && data['pipelineResponse'][0]['audio'] != null) {
          final audioContent = data['pipelineResponse'][0]['audio'][0]['audioContent'];
          print('DEBUG: TTS API returned audio content. Length: ${audioContent.length} bytes.');
          return audioContent;
        }
      }
      if (mounted) setState(() => _errorMessage = 'TTS API failed or returned empty audio.');
      print('DEBUG: TTS API response was not successful or returned empty audio. Status: ${response.statusCode}, Data: ${response.data}');
      return null;
    } on DioException catch (e) {
      if (mounted) setState(() => _errorMessage = 'TTS API Error: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'TTS API Error: $e');
      return null;
    }
  }

  // Plays base64 audio
  Future<void> _playAudio(String base64Audio) async {
    if (!mounted) return;
    try {
      // Stop any currently playing audio before starting new one
      await _audioPlayer.stop();
      
      // Set audio source from base64
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse('data:audio/wav;base64,$base64Audio')));
      
      // Play the audio
      await _audioPlayer.play();
      
      // _isSpeaking state is updated by the playerStateStream listener in initState
      print('DEBUG: Audio playback started.');

    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Error playing audio: $e. Check console for details.');
      print('DEBUG: Error playing audio (just_audio): $e');
      // Ensure _isSpeaking is false if an error occurs during playback
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  // --- Interview Flow Management ---

  Future<void> _startInterview() async {
    if (!mounted) return;
    if (!_isFirebaseInitialized || _bhashiniInferenceBaseUrl == null) {
      setState(() => _errorMessage = 'Services not ready. Please wait or check connection.');
      return;
    }
    if (_questions.isEmpty) {
      setState(() => _errorMessage = 'No questions defined.');
      return;
    }

    setState(() {
      _currentQuestionIndex = 0;
      _transcribedAnswer = '';
      _translatedEnglishAnswer = ''; // Clear translated answer
      _errorMessage = '';
      _patientId = null; // Reset patient ID for new interview
      _nameController.clear();
      _ageController.clear();
      _genderController.clear();
      _chiefComplaintController.clear();
      _contactNumberController.clear();
      _addressController.clear();
      _emailController.clear(); // NEW: Clear email controller
      _statusMessage = 'Starting interview...';
    });

    await _askQuestion();
  }

  Future<void> _askQuestion() async {
    if (!mounted) return;
    if (_currentQuestionIndex < _questions.length) {
      final questionData = _questions[_currentQuestionIndex];
      _originalEnglishQuestion = questionData['question']; // Store original English question

      String questionToSpeak = _originalEnglishQuestion;

      // Translate question to patient's preferred language if not English
      if (_selectedLanguageCode != 'en') {
        setState(() { _statusMessage = 'Translating question...'; });
        final translated = await _performTranslation(_originalEnglishQuestion, 'en', _selectedLanguageCode!);
        if (translated != null) {
          questionToSpeak = translated;
          print('DEBUG: Question translated to $_selectedLanguage: "$questionToSpeak"');
        } else {
          _errorMessage = 'Failed to translate question. Speaking in English.';
          print('DEBUG: Failed to translate question. Using English: "$_originalEnglishQuestion"');
        }
      }

      _currentQuestion = questionToSpeak; // Set for display and TTS
      setState(() {
        _statusMessage = 'Asking: $_currentQuestion';
        // _isSpeaking will be set by _playAudio's listener
      });

      final audioBase64 = await _performTTS(_currentQuestion, _selectedLanguageCode!, _selectedVoiceGender!);
      if (audioBase64 != null) {
        await _playAudio(audioBase64);
      } else {
        if (mounted) setState(() => _isSpeaking = false); // Reset if TTS fails to provide audio
        _statusMessage = 'Failed to speak question. Please read it or select another language/gender.';
      }
    } else {
      // Interview complete
      _currentQuestion = 'Interview complete!';
      setState(() {
        _statusMessage = 'Interview complete. Saving details...';
      });
      await _savePatientDetails();
    }
  }

  // Unified record button logic
  Future<void> _toggleRecording() async {
    if (!mounted) return;
    if (_isSpeaking) {
      setState(() => _errorMessage = 'Please wait for the question to finish speaking.');
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
            _transcribedAnswer = 'Processing...'; // Show processing for ASR
            _translatedEnglishAnswer = ''; // Clear previous translation
            _statusMessage = 'Processing your answer...';
          });
        }

        if (path != null && path.isNotEmpty) {
          File audioFile = File(path);
          List<int> audioBytes = await audioFile.readAsBytes();
          String audioBase64 = base64Encode(audioBytes);

          // Perform ASR in the selected language
          final transcribed = await _performASR(audioBase64, _selectedLanguageCode!);
          if (mounted) {
            setState(() {
              _transcribedAnswer = transcribed ?? 'Failed to transcribe. Please try again.';
              _errorMessage = transcribed == null ? 'Transcription failed.' : '';
            });
          }

          if (transcribed != null && transcribed.isNotEmpty) {
            setState(() { _statusMessage = 'Translating answer...'; });
            // Translate the transcribed answer to English
            final translated = await _performTranslation(transcribed, _selectedLanguageCode!, 'en');
            if (mounted) {
              setState(() {
                _translatedEnglishAnswer = translated ?? transcribed; // Fallback to original if translation fails
                _errorMessage = translated == null ? 'Translation failed. Using original transcription.' : '';
                _statusMessage = 'Answer processed.';
              });
            }
            
            // Determine the field name for current question
            final String currentField = _questions[_currentQuestionIndex]['field'];
            String finalAnswerForController = _translatedEnglishAnswer;

            // Apply number word-to-digit conversion for specific fields
            if (currentField == 'age' || currentField == 'contactNumber') {
              finalAnswerForController = _convertWordsToDigits(_translatedEnglishAnswer);
              print('DEBUG: Converted "$_translatedEnglishAnswer" to "$finalAnswerForController" for field "$currentField"');
            }

            // Update the controller with the processed (English, possibly numeric) answer
            _updateControllerWithAnswer(finalAnswerForController);
          } else {
            // If ASR failed, clear the translated answer and controller
            if (mounted) {
              setState(() {
                _translatedEnglishAnswer = '';
                _statusMessage = 'No valid answer to process.';
              });
            }
            _updateControllerWithAnswer(''); // Clear controller if no audio
          }
          
          if (mounted) {
            setState(() {
              _statusMessage = 'Answer transcribed and translated. Tap "Next Question" or edit.';
            });
          }

        } else {
          if (mounted) {
            setState(() {
              _transcribedAnswer = 'No audio recorded.';
              _translatedEnglishAnswer = '';
              _errorMessage = 'No audio recorded.';
              _statusMessage = 'No audio recorded. Tap mic to try again.';
            });
          }
          _updateControllerWithAnswer(''); // Clear controller if no audio
        }
      } catch (e) {
        if (mounted) setState(() => _errorMessage = 'Error stopping recording: $e');
        print('Error stopping recording: $e');
      }
    } else {
      // Start recording
      if (await _audioRecorder.hasPermission()) {
        try {
          Directory tempDir = await getTemporaryDirectory();
          _audioFilePath = '${tempDir.path}/patient_answer.wav';

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
              _transcribedAnswer = 'Listening...';
              _translatedEnglishAnswer = ''; // Clear previous translation
              _errorMessage = '';
              _statusMessage = 'Recording your answer...';
            });
          }
        } catch (e) {
          if (mounted) setState(() => _errorMessage = 'Error starting recording: $e');
          print('Error starting recording: $e');
        }
      } else {
        if (mounted) setState(() => _errorMessage = 'Microphone permission not granted.');
      }
    }
  }

  // This function now expects to receive the ENGLISH translated answer
  void _updateControllerWithAnswer(String englishAnswer) {
    if (_currentQuestionIndex < _questions.length) {
      final controller = _questions[_currentQuestionIndex]['controller'] as TextEditingController;
      controller.text = englishAnswer;
      controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
    }
  }

  void _nextQuestion() async {
    if (!mounted) return;
    if (_isRecording) {
      setState(() => _errorMessage = 'Please stop recording before moving to the next question.');
      return;
    }
    if (_isSpeaking) {
      setState(() => _errorMessage = 'Please wait for the current question to finish speaking.');
      return;
    }

    setState(() {
      _currentQuestionIndex++;
      _transcribedAnswer = ''; // Clear for next answer
      _translatedEnglishAnswer = ''; // Clear for next question
      _errorMessage = '';
    });
    await _askQuestion();
  }

  Future<void> _savePatientDetails() async {
    if (!mounted) return;
    if (!_isFirebaseInitialized || _userId == null) {
      setState(() => _errorMessage = 'Firebase not initialized or user not authenticated.');
      return;
    }

    setState(() {
      _statusMessage = 'Saving patient details...';
      _isLoading = true;
    });

    try {
      final String newPatientId = _uuid.v4(); // Generate a unique ID
      final patientData = {
        'id': newPatientId,
        'name': _nameController.text.trim(),
        'age': _ageController.text.trim(),
        'gender': _genderController.text.trim(),
        'chiefComplaint': _chiefComplaintController.text.trim(),
        'contactNumber': _contactNumberController.text.trim(),
        'address': _addressController.text.trim(),
        'email': _emailController.text.trim(), // NEW: Save email
        'timestamp': FieldValue.serverTimestamp(),
        'recordedByUserId': _userId, // Track which user recorded this
        'appId': __app_id, // Store the app ID
        // Optionally, save the original language of the interview
        'interviewLanguage': _selectedLanguage,
      };

      // Save to a public collection under artifacts/{appId}/public/patients
      // This path implies public readability for other authenticated users within the app.
      // Ensure your Firestore security rules allow this:
      // match /artifacts/{appId}/public/patients/{patientId} {
      //   allow read, write: if request.auth != null;
      // }
      await _firestore.collection('artifacts').doc(__app_id).collection('public').doc('patients').collection('data').doc(newPatientId).set(patientData);

      if (mounted) {
        setState(() {
          _patientId = newPatientId;
          _statusMessage = 'Patient details saved! Your Patient ID is: $_patientId';
          _isLoading = false;
        });
        // Show a success dialog with the Patient ID
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Patient Details Saved!'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Patient ID: $_patientId\n\nPlease share this ID with the doctor.',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The OPD report can be sent to this patient ID by the doctor. '
                    'Emailing the report directly would require a backend service (e.g., Firebase Cloud Functions) for security and reliability.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).pop(); // Go back to Patient Home
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error saving patient details: $e';
          _statusMessage = 'Failed to save details.';
          _isLoading = false;
        });
      }
      print('Error saving patient details: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);
    final bool bhashiniReady = _bhashiniInferenceBaseUrl != null && _bhashiniInferenceApiKey != null && _pipelineConfigResponse != null;
    final bool servicesReady = _isFirebaseInitialized && bhashiniReady;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Details Form'),
        backgroundColor: currentTheme.appBarTheme.backgroundColor,
        elevation: currentTheme.appBarTheme.elevation,
      ),
      backgroundColor: currentTheme.scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Status/Error Message Area
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: _errorMessage.isNotEmpty ? Colors.red.withOpacity(0.1) : currentTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _errorMessage.isNotEmpty ? Colors.red : currentTheme.primaryColor,
                  width: 1.5,
                ),
              ),
              child: Text(
                _errorMessage.isNotEmpty ? _errorMessage : _statusMessage,
                style: currentTheme.textTheme.titleMedium?.copyWith(
                  color: _errorMessage.isNotEmpty ? Colors.red : currentTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),
            
            if (!servicesReady && !_isLoading)
              Center(
                child: Column(
                  children: [
                    Text(
                      'Initializing services...',
                      style: currentTheme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _initializeFirebaseAndBhashini,
                      child: const Text('Retry Initialization'),
                    ),
                  ],
                ),
              ),
            
            // This Expanded widget ensures the scrollable content takes available space
            Expanded(
              child: SingleChildScrollView( // Wrap content in SingleChildScrollView
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (servicesReady && !_isLoading) ...[
                      // Language and Gender Selection
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        margin: const EdgeInsets.only(bottom: 20),
                        color: currentTheme.cardColor,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Interview Settings',
                                style: currentTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Divider(height: 20, thickness: 1),
                              Text(
                                'Preferred Language:',
                                style: currentTheme.textTheme.bodyLarge,
                              ),
                              DropdownButton<String>(
                                value: _selectedLanguage,
                                onChanged: (String? newValue) {
                                  if (newValue != null && mounted) {
                                    setState(() {
                                      _selectedLanguage = newValue;
                                      _selectedLanguageCode = {
                                        'English': 'en', 'Tamil': 'ta', 'Hindi': 'hi',
                                        'Telugu': 'te', 'Kannada': 'kn', 'Malayalam': 'ml'
                                      }[newValue];
                                      _statusMessage = 'Language set to $newValue. Tap "Start Interview".';
                                    });
                                  }
                                },
                                items: <String>['English', 'Tamil', 'Hindi', 'Telugu', 'Kannada', 'Malayalam']
                                    .map<DropdownMenuItem<String>>((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                                isExpanded: true,
                                dropdownColor: currentTheme.cardColor,
                                style: currentTheme.textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Voice Gender:',
                                style: currentTheme.textTheme.bodyLarge,
                              ),
                              DropdownButton<String>(
                                value: _selectedVoiceGender,
                                onChanged: (String? newValue) {
                                  if (newValue != null && mounted) {
                                    setState(() {
                                      _selectedVoiceGender = newValue;
                                      _statusMessage = 'Voice gender set to $newValue.';
                                    });
                                  }
                                },
                                items: <String>['male', 'female']
                                    .map<DropdownMenuItem<String>>((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value.capitalize()), // Capitalize for display
                                  );
                                }).toList(),
                                isExpanded: true,
                                dropdownColor: currentTheme.cardColor,
                                style: currentTheme.textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Interview Section (Conditional Display)
                      if (_patientId != null) // If patient details are saved, show success
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                                const SizedBox(height: 20),
                                Text(
                                  'Patient Details Saved!',
                                  style: currentTheme.textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 10),
                                SelectableText(
                                  'Your Patient ID is:',
                                  style: currentTheme.textTheme.titleLarge,
                                ),
                                SelectableText(
                                  _patientId!,
                                  style: currentTheme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: currentTheme.primaryColor),
                                ),
                                const SizedBox(height: 30),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(); // Go back to Patient Home
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: currentTheme.primaryColor,
                                    foregroundColor: currentTheme.colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  ),
                                  child: const Text('Back to Home'),
                                ),
                              ],
                            ),
                          )
                      else if (_currentQuestionIndex < _questions.length) // If interview is ongoing
                        Column( // This Column contains the question, input, and buttons
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              color: currentTheme.cardColor,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row( // Row for question text and speaker button
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Question ${_currentQuestionIndex + 1}/${_questions.length}:',
                                            style: currentTheme.textTheme.titleMedium?.copyWith(color: currentTheme.hintColor),
                                          ),
                                        ),
                                        // Speaker Button
                                        IconButton(
                                          icon: Icon(
                                            _isSpeaking ? Icons.volume_up : Icons.volume_down,
                                            color: _isSpeaking ? currentTheme.colorScheme.secondary : currentTheme.primaryColor,
                                            size: 30,
                                          ),
                                          onPressed: () async {
                                            // Replay the translated question
                                            final audioBase64 = await _performTTS(_currentQuestion, _selectedLanguageCode!, _selectedVoiceGender!);
                                            if (audioBase64 != null) {
                                              await _playAudio(audioBase64);
                                            } else {
                                              if (mounted) setState(() => _errorMessage = 'Failed to replay question. TTS unavailable.');
                                            }
                                          },
                                          tooltip: 'Repeat Question',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _currentQuestion, // This is the translated question
                                      style: currentTheme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: currentTheme.primaryColor),
                                    ),
                                    const SizedBox(height: 20),
                                    TextField(
                                      controller: _questions[_currentQuestionIndex]['controller'] as TextEditingController,
                                      decoration: InputDecoration(
                                        labelText: 'Your Answer (Editable - English)', // Indicate it's English
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        filled: true,
                                        fillColor: currentTheme.inputDecorationTheme.fillColor,
                                      ),
                                      style: currentTheme.textTheme.bodyLarge,
                                      maxLines: 3,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Original Transcription: ${_transcribedAnswer.isEmpty ? 'Waiting for voice input...' : _transcribedAnswer}',
                                      style: currentTheme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                                    ),
                                    Text(
                                      'English Translation: ${_translatedEnglishAnswer.isEmpty ? 'Processing...' : _translatedEnglishAnswer}',
                                      style: currentTheme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                                    ),
                                    if (_isRecording)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Text(
                                          'Audio Level: ${_currentAudioLevel.toStringAsFixed(2)} dB',
                                          textAlign: TextAlign.center,
                                          style: currentTheme.textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Action Buttons (Mic, Next, Save)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Mic/Stop Button (Toggle)
                                GestureDetector(
                                  onTap: _isSpeaking ? null : _toggleRecording, // Disable if speaking
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isSpeaking
                                          ? Colors.grey[400] // Grey if speaking
                                          : (_isRecording ? Colors.redAccent : currentTheme.primaryColor),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isRecording || _isSpeaking) ? Colors.red.withOpacity(0.4) : currentTheme.primaryColor.withOpacity(0.3),
                                          blurRadius: _isRecording ? 15 : 5,
                                          spreadRadius: _isRecording ? 5 : 2,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _isSpeaking ? Icons.volume_up : (_isRecording ? Icons.stop : Icons.mic),
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  ),
                                ),
                                // Next Question Button
                                ElevatedButton.icon(
                                  onPressed: _isRecording || _isSpeaking ? null : _nextQuestion,
                                  icon: const Icon(Icons.arrow_forward),
                                  label: const Text('Next Question'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: currentTheme.colorScheme.secondary,
                                    foregroundColor: currentTheme.colorScheme.onSecondary,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    elevation: 5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Save & Finish Button
                            ElevatedButton.icon(
                              onPressed: _isRecording || _isSpeaking ? null : _savePatientDetails,
                              icon: const Icon(Icons.save),
                              label: const Text('Save & Finish Interview'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: currentTheme.hintColor,
                                foregroundColor: currentTheme.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                elevation: 5,
                              ),
                            ),
                          ], // End of Column for current question/buttons
                        )else // This is the initial state where the "Start Interview" button appears
                        Center(
                          child: ElevatedButton(
                            onPressed: servicesReady && !_isLoading ? _startInterview : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentTheme.primaryColor,
                              foregroundColor: currentTheme.colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              elevation: 5,
                            ),
                            child: const Text('Start Interview', style: TextStyle(fontSize: 22)),
                          ),
                        ),
                    ], // End of if (servicesReady && !_isLoading)
                  ], // End of children for SingleChildScrollView's Column
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Extension to capitalize first letter for display
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
