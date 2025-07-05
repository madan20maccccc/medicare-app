// lib/summary_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart'; // For making HTTP requests
import 'dart:convert'; // For JSON encoding/decoding
import 'dart:math'; // For min function in debug prints

// Firebase imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Global variables provided by the Canvas environment
// These are used for Firebase initialization and authentication.
// DO NOT modify these.
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');
const String __firebase_config = String.fromEnvironment('FIREBASE_CONFIG', defaultValue: '{}');
const String __initial_auth_token = String.fromEnvironment('INITIAL_AUTH_TOKEN', defaultValue: '');


class SummaryScreen extends StatefulWidget {
  final String translatedText;

  const SummaryScreen({super.key, required this.translatedText});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  // Gemini API Details
  // IMPORTANT: Using the API key provided by the user directly.
  final String _geminiApiKey = 'AIzaSyCXmcg_aOEwg38airIbs14C0SqZK6b_UTo'; // <-- Your actual API key
  // Use the specific model from your Colab: gemini-1.5-flash
  final String _geminiModel = 'gemini-1.5-flash';
  // Base URL for the Gemini API endpoint
  final String _geminiApiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/';

  String _generatedSummary = 'Generating summary...';
  bool _isLoadingSummary = true;
  String _summaryErrorMessage = '';
  late TextEditingController _summaryController;

  // Firestore instance and user ID
  late FirebaseFirestore _db;
  late FirebaseAuth _auth;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController(text: _generatedSummary);
    _initializeFirebaseAndGenerateSummary(); // Combined initialization and summary generation
  }

  Future<void> _initializeFirebaseAndGenerateSummary() async {
    try {
      // Initialize Firebase instances
      _db = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;

      // Ensure user is authenticated and get UID
      // This part is crucial for Firestore security rules
      if (_auth.currentUser == null) {
        if (__initial_auth_token.isNotEmpty) {
          await _auth.signInWithCustomToken(__initial_auth_token);
        } else {
          await _auth.signInAnonymously();
        }
      }
      _userId = _auth.currentUser?.uid;
      print('Firebase: Current User ID in SummaryScreen: $_userId');

      if (_userId == null) {
        _summaryErrorMessage = 'User not authenticated. Cannot save summary.';
        setState(() {
          _isLoadingSummary = false;
        });
        return;
      }

      // Now proceed with generating the summary
      _generateSummary();

    } catch (e) {
      _summaryErrorMessage = 'Error initializing Firebase for SummaryScreen: $e';
      print('Error initializing Firebase for SummaryScreen: $e');
      setState(() {
        _isLoadingSummary = false;
      });
    }
  }

  // Function to call Gemini API for summarization
  Future<void> _generateSummary() async {
    setState(() {
      _isLoadingSummary = true;
      _summaryErrorMessage = '';
      _generatedSummary = 'Generating summary...';
      _summaryController.text = _generatedSummary;
    });

    try {
      final Dio dio = Dio();

      // Use the exact prompt structure from your Colab notebook
      final prompt = """
You are a medical transcription assistant.

Your task is to analyze the following doctor-patient conversation and generate a structured OPD summary.

Pay **special attention to medicine mentions**, even if they are not clearly translated — try to guess based on patterns like:
- '650 mg twice a day'
- 'one tablet at night'
- or brand/generic drug names

Include:
1. Patient's symptoms
2. Diagnosis
3. Medicine name, strength, frequency, duration
4. Any advice or follow-up

Here is the conversation:
${widget.translatedText}

--- OUTPUT FORMAT ---
Summary:
Diagnosis:
Symptoms:
Medicines:
- Name:
- Strength:
- Frequency:
- Duration:
- Name:
- Strength:
- Frequency:
- Duration:
Advice:
-----------------------
"""; // Adjusted prompt for two medicine entries as per typical output from your Colab

      final chatHistory = [
        {"role": "user", "parts": [{"text": prompt}]}
      ];

      final payload = {
        "contents": chatHistory,
      };

      // Construct the full API URL by explicitly appending the key.
      final fullGeminiApiUrl = '$_geminiApiBaseUrl$_geminiModel:generateContent?key=$_geminiApiKey';

      print('DEBUG: Gemini Request URL: $fullGeminiApiUrl');
      print('DEBUG: Gemini Request Body: ${jsonEncode(payload)}');

      final response = await dio.post(
        fullGeminiApiUrl,
        options: Options(headers: {
          'Content-Type': 'application/json',
        }),
        data: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        print('DEBUG: Gemini Response Data: $data');
        if (data != null && data['candidates'] != null && data['candidates'].isNotEmpty &&
            data['candidates'][0]['content'] != null && data['candidates'][0]['content']['parts'] != null &&
            data['candidates'][0]['content']['parts'].isNotEmpty) {
          final summary = data['candidates'][0]['content']['parts'][0]['text'];
          setState(() {
            _generatedSummary = summary;
            _summaryController.text = summary;
          });
        } else {
          _summaryErrorMessage = 'Invalid Gemini API response structure.';
          print('DEBUG: Invalid Gemini API response structure: $data');
        }
      } else {
        _summaryErrorMessage = 'Failed to generate summary: ${response.statusCode} - ${response.data}';
        print('DEBUG: Gemini API Error Response: ${response.statusCode} - ${response.data}');
      }
    } on DioException catch (e) {
      _summaryErrorMessage = 'Error calling Gemini API: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      print('DEBUG: DioException during Gemini API call: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
    } catch (e) {
      _summaryErrorMessage = 'Error calling Gemini API: $e';
      print('DEBUG: Generic Error calling Gemini API: $e');
    } finally {
      setState(() {
        _isLoadingSummary = false;
      });
    }
  }

  // Function to save summary to Firestore
  Future<void> _saveSummary() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User not authenticated. Cannot save summary.')),
      );
      return;
    }

    setState(() {
      _isLoadingSummary = true; // Show loading while saving
    });

    try {
      // Define the Firestore collection path for private user data
      // /artifacts/{appId}/users/{userId}/consultations
      final CollectionReference consultationsRef = _db
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(_userId)
          .collection('consultations');

      await consultationsRef.add({
        'timestamp': FieldValue.serverTimestamp(), // Automatically get server timestamp
        'originalText': widget.translatedText, // Store the original translated text
        'summary': _summaryController.text, // Store the generated/edited summary
        'userId': _userId, // Store the user ID for reference
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Summary saved successfully!')),
      );
      print('DEBUG: Summary saved to Firestore for user: $_userId');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving summary: $e')),
      );
      print('DEBUG: Error saving summary to Firestore: $e');
    } finally {
      setState(() {
        _isLoadingSummary = false; // Hide loading
      });
    }
  }

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consultation Summary'),
        backgroundColor: Colors.green,
        elevation: 0,
      ),
      backgroundColor: Colors.green[50],
      body: _isLoadingSummary && _generatedSummary == 'Generating summary...' // Only show full loading for initial summary generation
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Generating medical summary...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_summaryErrorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Text(
                        _summaryErrorMessage,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ),
                  
                  Text(
                    'Generated Summary:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.green[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextFormField(
                      controller: _summaryController,
                      maxLines: null, // Allows multiple lines
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: InputBorder.none, // Remove default border
                        hintText: 'Summary will appear here...',
                      ),
                      style: TextStyle(fontSize: 16, color: Colors.blueGrey[800]),
                    ),
                  ),
                  const SizedBox(height: 30),

                  ElevatedButton.icon(
                    onPressed: _isLoadingSummary ? null : _saveSummary, // Call _saveSummary function
                    icon: const Icon(Icons.save, size: 28),
                    label: const Text(
                      'Save Summary',
                      style: TextStyle(fontSize: 20),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent, // Blue for save action
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                      minimumSize: Size(MediaQuery.of(context).size.width * 0.7, 60),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isLoadingSummary ? null : () {
                      Navigator.pop(context); // Go back to the previous screen
                    },
                    icon: const Icon(Icons.arrow_back, size: 28),
                    label: const Text(
                      'Go Back',
                      style: TextStyle(fontSize: 20),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey, // Grey for back action
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
