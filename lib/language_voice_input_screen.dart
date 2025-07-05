// lib/language_voice_input_screen.dart
import 'package:flutter/material.dart';
import 'package:record/record.dart'; // Import the main record package file
import 'package:path_provider/path_provider.dart'; // For temporary file paths
import 'package:dio/dio.dart'; // For making HTTP requests
import 'dart:io'; // For File operations
import 'dart:convert'; // For JSON encoding/decoding
import 'dart:math'; // Added for min function in debug prints
import 'dart:async'; // Added for StreamSubscription
import 'package:medicare/summary_screen.dart'; // Import the SummaryScreen

// This screen will handle language selection and voice input for the doctor.
class LanguageVoiceInputScreen extends StatefulWidget {
  const LanguageVoiceInputScreen({super.key});

  @override
  State<LanguageVoiceInputScreen> createState() => _LanguageVoiceInputScreenState();
}

class _LanguageVoiceInputScreenState extends State<LanguageVoiceInputScreen> {
  // Bhashini API Details (REPLACE WITH YOUR ACTUAL CREDENTIALS)
  final String _bhashiniApiKey = '529fda3d00-836e-498b-a266-7d1ea97a667f'; // <-- Replace with your Bhashini API Key
  final String _bhashiniUserId = 'ae98869a2a7542b1a24da628b955e51b'; // <-- Replace with your Bhashini User ID

  // Base URL for Bhashini Authentication API (for getting pipeline config)
  final String _bhashiniAuthBaseUrl = 'https://meity-auth.ulcacontrib.org';

  // Specific pipeline ID from your Colab for getModelsPipeline
  final String _bhashiniPipelineId = "64392f96daac500b55c543cd";

  // New variables to store dynamic inference endpoint and API key
  String? _bhashiniInferenceBaseUrl;
  String? _bhashiniInferenceApiKey;

  // Supported languages and their Bhashini codes (ISO 639-1)
  final Map<String, String> _languages = {
    'English': 'en',
    'Tamil': 'ta',
    'Hindi': 'hi',
    'Telugu': 'te',
    'Kannada': 'kn',
    'Malayalam': 'ml',
    // Add more languages as supported by Bhashini
  };
  String? _selectedLanguage; // Stores the currently selected language (e.g., 'English')
  String? _selectedLanguageCode; // Stores the Bhashini language code (e.g., 'en')

  final AudioRecorder _audioRecorder = AudioRecorder(); // Instance of the audio recorder
  String? _audioFilePath; // Path where the recorded audio file is stored temporarily

  bool _isRecording = false; // State to track if recording is active
  bool _isLoading = false; // State to track if an API call is in progress
  String _transcribedText = 'Your transcribed text will appear here...'; // Placeholder for transcribed text
  String _translatedText = 'Your English translation will appear here...'; // Placeholder for translated text
  String _errorMessage = ''; // To display any errors

  // Full pipeline config response to parse ASR/Translation service IDs later
  Map<String, dynamic>? _pipelineConfigResponse;

  // Audio level monitoring variables
  StreamSubscription<Amplitude>? _audioLevelSubscription;
  double _currentAudioLevel = 0.0; // dB value

  @override
  void initState() {
    super.initState();
    _selectedLanguage = _languages.keys.first; // Set English as the default selected language.
    _selectedLanguageCode = _languages[_selectedLanguage]; // Set corresponding code.
    _initializeBhashiniPipeline(); // Fetch Bhashini pipeline config on start.
  }

  // --- Bhashini API Functions ---

  // Fetches ASR and Translation pipeline IDs from Bhashini Auth API.
  Future<void> _initializeBhashiniPipeline() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _pipelineConfigResponse = null; // Clear previous config
      _bhashiniInferenceBaseUrl = null; // Clear previous inference URL
      _bhashiniInferenceApiKey = null; // Clear previous inference API key
    });

    try {
      final Dio dio = Dio();
      final response = await dio.post(
        '$_bhashiniAuthBaseUrl/ulca/apis/v0/model/getModelsPipeline', // Corrected URL path
        options: Options(headers: {
          'Content-Type': 'application/json',
          'ulcaApiKey': _bhashiniApiKey,
          'userID': _bhashiniUserId,
        }),
        data: jsonEncode({
          "pipelineTasks": [
            {"taskType": "asr"},
            {"taskType": "translation"},
            {"taskType": "tts"} // Including TTS as per your Colab's initial request
          ],
          "pipelineRequestConfig": {
            "pipelineId": _bhashiniPipelineId
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data != null) {
          _pipelineConfigResponse = data; // Store the full response for later parsing
          
          // Extract dynamic inference API endpoint and key
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Helper to find serviceId from pipeline config
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
  Future<String?> _performASR(String audioBase64) async {
    if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
      _errorMessage = 'Bhashini Inference API not initialized. Please select language and try again.';
      return null;
    }

    final asrServiceId = _findServiceId('asr', _selectedLanguageCode!);
    if (asrServiceId == null) {
      _errorMessage = 'ASR service not found for selected language (${_selectedLanguageCode}).';
      print('DEBUG: ASR serviceId not found for source: $_selectedLanguageCode');
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
                  "sourceLanguage": _selectedLanguageCode
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
      print('DEBUG: ASR Request Body (first 200 chars): ${requestBody.substring(0, min(requestBody.length, 200))}...');
      print('DEBUG: ASR Audio Base64 Length: ${audioBase64.length}');


      final response = await dio.post(
        _bhashiniInferenceBaseUrl!, // Use dynamic inference URL
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': _bhashiniInferenceApiKey!, // Use dynamic inference API key in Authorization header
        }),
        data: requestBody,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        print('DEBUG: ASR Response Data: $data');
        if (data != null && data['pipelineResponse'] != null && data['pipelineResponse'][0]['output'] != null) {
          final transcribed = data['pipelineResponse'][0]['output'][0]['source'];
          if (transcribed != null && transcribed.toString().trim().isNotEmpty) {
            return transcribed.toString();
          } else {
            _errorMessage = 'ASR returned empty or null text. Please try speaking more clearly.';
            print('DEBUG: ASR returned empty or null text: $transcribed');
            return null;
          }
        } else {
          _errorMessage = 'Invalid ASR response structure.';
          print('DEBUG: Invalid ASR response structure: $data');
          return null;
        }
      } else {
        _errorMessage = 'Failed to perform ASR: ${response.statusCode} - ${response.data}';
        print('DEBUG: ASR API Error Response: ${response.statusCode} - ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      _errorMessage = 'Error performing ASR: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      print('DEBUG: DioException during ASR: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      _errorMessage = 'Error performing ASR: $e';
      print('DEBUG: Generic Error performing ASR: $e');
      return null;
    }
  }

  // Performs Translation using Bhashini Inference API.
  Future<String?> _performTranslation(String textToTranslate) async {
    if (_bhashiniInferenceBaseUrl == null || _bhashiniInferenceApiKey == null) {
      _errorMessage = 'Bhashini Inference API not initialized. Please select language and try again.';
      return null;
    }

    if (textToTranslate.trim().isEmpty) {
      print('DEBUG: Skipping translation - input text is empty.');
      _errorMessage = 'No text to translate from ASR.';
      return null;
    }

    // Skip translation if source is already English
    if (_selectedLanguageCode == 'en') {
      print('DEBUG: Skipping translation - source already in English.');
      return textToTranslate;
    }

    final translationServiceId = _findServiceId('translation', _selectedLanguageCode!, targetLanguage: 'en');
    if (translationServiceId == null) {
      _errorMessage = 'Translation service not found for ${_selectedLanguageCode} to English. Please try another language.';
      print('DEBUG: Translation serviceId not found for source: $_selectedLanguageCode, target: en');
      return null;
    }

    try {
      final Dio dio = Dio();
      final requestBody = jsonEncode({
          "pipelineTasks": [
            {
              "taskType": "translation",
              "config": {
                "language": {
                  "sourceLanguage": _selectedLanguageCode,
                  "targetLanguage": "en"
                },
                "serviceId": translationServiceId
              }
            }
          ],
          "inputData": {
            "input": [
              {
                "source": textToTranslate
              }
            ]
          }
        });

      print('DEBUG: Translation Request URL: $_bhashiniInferenceBaseUrl');
      print('DEBUG: Translation Request Headers: {"Content-Type": "application/json", "Authorization": "${_bhashiniInferenceApiKey?.substring(0,5)}..."}');
      print('DEBUG: Translation Request Body: $requestBody');


      final response = await dio.post(
        _bhashiniInferenceBaseUrl!, // Use dynamic inference URL
        options: Options(headers: {
          'Content-Type': 'application/json',
          'Authorization': _bhashiniInferenceApiKey!, // Use dynamic inference API key in Authorization header
        }),
        data: requestBody,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        print('DEBUG: Translation Response Data: $data');
        if (data != null && data['pipelineResponse'] != null && data['pipelineResponse'][0]['output'] != null) {
          return data['pipelineResponse'][0]['output'][0]['target'];
        } else {
          _errorMessage = 'Invalid Translation response structure.';
          return null;
        }
      } else {
        _errorMessage = 'Failed to perform Translation: ${response.statusCode} - ${response.data}';
        print('DEBUG: Translation API Error Response: ${response.statusCode} - ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      _errorMessage = 'Error performing Translation: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      print('DEBUG: DioException during Translation: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
      return null;
    } catch (e) {
      _errorMessage = 'Error performing Translation: $e';
      print('DEBUG: Generic Error performing Translation: $e');
      return null;
    }
  }

  // --- Audio Recording Functions ---

  // Checks and requests microphone permissions.
  Future<bool> _checkPermissions() async {
    if (await _audioRecorder.hasPermission()) {
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Microphone permission required to record audio.')),
      );
      return false;
    }
  }

  // Starts audio recording.
  Future<void> _startRecording() async {
    try {
      if (await _checkPermissions()) {
        Directory tempDir = await getTemporaryDirectory();
        _audioFilePath = '${tempDir.path}/temp_audio.wav'; // Save as WAV for Bhashini
        
        // Start listening to audio levels
        _audioLevelSubscription = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
          setState(() {
            _currentAudioLevel = amp.current; // Get current amplitude in dB
          });
        });

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav, // Bhashini prefers WAV format
            numChannels: 1, // Mono audio
            sampleRate: 16000, // Corrected parameter name
            bitRate: 16, // Explicitly set bit rate to 16-bit PCM
          ),
          path: _audioFilePath!,
        );
        setState(() {
          _isRecording = true;
          _transcribedText = 'Listening...';
          _translatedText = 'Waiting for transcription...';
          _errorMessage = '';
        });
        print('Recording started to $_audioFilePath');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error starting recording: $e';
        _isRecording = false;
      });
      print('Error starting recording: $e');
    }
  }

  // Stops audio recording and triggers ASR/Translation.
  Future<void> _stopRecording() async {
    try {
      // Cancel audio level subscription
      await _audioLevelSubscription?.cancel();
      _audioLevelSubscription = null;
      setState(() {
        _currentAudioLevel = 0.0; // Reset audio level display
      });

      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isLoading = true;
        _transcribedText = 'Processing audio...';
        _translatedText = 'Processing translation...';
      });

      if (path != null) {
        _audioFilePath = path;
        print('Recording stopped. File saved at: $_audioFilePath');
        File audioFile = File(_audioFilePath!);
        print('DEBUG: Recorded WAV file size: ${audioFile.lengthSync()} bytes');
        List<int> audioBytes = await audioFile.readAsBytes();
        String audioBase64 = base64Encode(audioBytes);

        // Perform ASR
        final transcribed = await _performASR(audioBase64);
        if (transcribed != null) {
          setState(() {
            _transcribedText = transcribed;
          });
          // Perform Translation
          final translated = await _performTranslation(transcribed);
          if (translated != null) {
            setState(() {
              _translatedText = translated;
            });
            // NO automatic navigation here anymore. User clicks button.
            print('Transcribed: $_transcribedText');
            print('Translated: $_translatedText');
          }
        } else {
          setState(() {
            _transcribedText = 'Failed to transcribe audio.';
            _translatedText = 'Translation not available.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'No audio recorded.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error stopping recording or processing audio: $e';
      });
      print('Error stopping recording: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Toggles recording state (start/stop).
  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  @override
  void dispose() {
    _audioLevelSubscription?.cancel(); // Cancel subscription on dispose
    _audioRecorder.dispose(); // Release recorder resources
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine if the "Generate Summary" button should be enabled
    bool canGenerateSummary = !_isLoading && _translatedText != 'Your English translation will appear here...' && _translatedText.isNotEmpty && _translatedText != 'Translation not available.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Input & Language'),
        backgroundColor: Colors.blueAccent,
        elevation: 0,
      ),
      backgroundColor: Colors.blueGrey[50],
      body: _isLoading && _bhashiniInferenceBaseUrl == null // Show loading while initializing Bhashini
          ? const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Initializing Bhashini services...', style: TextStyle(fontSize: 16)),
            ],
          ))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
          children: <Widget>[
            // --- Error Message Display ---
            if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 20),
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

            // --- Language Selection Dropdown ---
            Text(
              'Select Patient\'s Language:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[700],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: DropdownButtonHideUnderline( // Hides the default underline
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
                  iconSize: 30,
                  elevation: 16,
                  style: TextStyle(color: Colors.blueGrey[800], fontSize: 16),
                  onChanged: _isLoading ? null : (String? newValue) { // Disable dropdown if loading
                    setState(() {
                      _selectedLanguage = newValue;
                      _selectedLanguageCode = newValue != null ? _languages[newValue] : null;
                    });
                  },
                  items: _languages.keys.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 40),

            // --- Voice Input Section ---
            Text(
              _isRecording ? 'Recording in progress...' : 'Tap the mic to start recording',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: _isRecording ? Colors.redAccent : Colors.blueGrey[700],
              ),
            ),
            const SizedBox(height: 10),
            // Audio Level Display
            if (_isRecording)
              Text(
                'Audio Level: ${_currentAudioLevel.toStringAsFixed(2)} dB',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blueGrey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(height: 20),

            // Microphone Button
            GestureDetector(
              onTap: _isLoading ? null : _toggleRecording, // Disable button if loading
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: 150,
                width: 150,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.redAccent.withOpacity(0.9) : Colors.blueAccent,
                  shape: BoxShape.circle, // Circular button
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic, // Change icon based on recording state
                  color: Colors.white,
                  size: 80,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // --- Transcribed Text Display ---
            Text(
              'Transcribed Text (Original Language):',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[700],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.blueGrey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                _transcribedText,
                style: TextStyle(fontSize: 16, color: Colors.blueGrey[800]),
                textAlign: TextAlign.left,
              ),
            ),
            const SizedBox(height: 20),

            // --- Translated Text Display ---
            Text(
              'Translated Text (English):',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[700],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.blueGrey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                _translatedText,
                style: TextStyle(fontSize: 16, color: Colors.blueGrey[800]),
                textAlign: TextAlign.left,
              ),
            ),
            const SizedBox(height: 30),

            // "Click here for generating summary" Button
            ElevatedButton.icon(
              onPressed: canGenerateSummary
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SummaryScreen(translatedText: _translatedText),
                        ),
                      );
                    }
                  : null, // Disable button if not ready
              icon: const Icon(Icons.summarize, size: 28),
              label: const Text(
                'Click here for generating summary',
                style: TextStyle(fontSize: 20),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple, // New color for summary generation
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
    );
  }
}
