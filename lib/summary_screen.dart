// lib/summary_screen.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart'; // For making HTTP requests
import 'dart:convert'; // For JSON encoding/decoding

// Firebase imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import the new MedicinesListScreen
import 'package:medicare/medicines_list_screen.dart';

// Global variables provided by the Canvas environment
// These are used for Firebase initialization and authentication.
// DO NOT modify these.
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');
const String __firebase_config = String.fromEnvironment('FIREBASE_CONFIG', defaultValue: '{}');
const String __initial_auth_token = String.fromEnvironment('INITIAL_AUTH_TOKEN', defaultValue: '');


class SummaryScreen extends StatefulWidget {
  // Renamed for clarity: this is the raw conversation text for summary generation
  final String conversationText;

  const SummaryScreen({super.key, required this.conversationText});

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

  final Dio dio = Dio();

  // REVISED PROMPT
  final prompt = """
You are a highly skilled medical transcription assistant.
Your task is to analyze the following doctor-patient conversation and generate a comprehensive, structured Outpatient Department (OPD) summary.

**Extract all relevant medical information and present it clearly under the specified headings.**
**If a section's information is not explicitly mentioned or is unclear, use "N/A" for that specific field.**

**Output Format (Strictly adhere to this structure):**

--- OPD SUMMARY ---
**Date of Consultation:** ${DateTime.now().toLocal().toString().split(' ')[0]}
**Patient ID:** N/A (or extract if available in conversation)
**Doctor ID:** N/A (or extract if available in conversation)

**Chief Complaint (CC):** [Patient's primary reason for visit]

**History of Present Illness (HPI):**
- **Onset:** 
- **Duration:** 
- **Character:** 
- **Location:** 
- **Severity:** 
- **Associated Symptoms:** 
- **Aggravating Factors:** 
- **Relieving Factors:** 
- **Past Medical History:** 

**Review of Systems (ROS):** 

**Provisional Diagnosis:** 

**Medications Prescribed:**
- **[Medicine Name 1]:**
  - **Dosage:** 
  - **Frequency:** 
  - **Duration:** 
  - **Timing:** 
(Add more if needed or say "No new medications prescribed.")

**Investigations/Tests Recommended:** 

**Advice/Instructions:**
- 
- 

--- END OF OPD SUMMARY ---

Here is the doctor-patient conversation to summarize:
${widget.conversationText}
""";

  final chatHistory = [
    {"role": "user", "parts": [{"text": prompt}]}
  ];

  final payload = {
    "contents": chatHistory,
  };

  final fullGeminiApiUrl =
      '$_geminiApiBaseUrl$_geminiModel:generateContent?key=$_geminiApiKey';

  print('DEBUG: Gemini Request URL: $fullGeminiApiUrl');
  print('DEBUG: Gemini Request Body: ${jsonEncode(payload)}');

  try {
    Response response;
    int retryCount = 0;
    bool requestSuccessful = false;

    while (retryCount < 3 && !requestSuccessful) {
      try {
        response = await dio.post(
          fullGeminiApiUrl,
          options: Options(headers: {
            'Content-Type': 'application/json',
          }),
          data: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          requestSuccessful = true;
          final data = response.data;
          print('DEBUG: Gemini Response Data: $data');

          if (data != null &&
              data['candidates'] != null &&
              data['candidates'].isNotEmpty &&
              data['candidates'][0]['content'] != null &&
              data['candidates'][0]['content']['parts'] != null &&
              data['candidates'][0]['content']['parts'].isNotEmpty) {
            final summary =
                data['candidates'][0]['content']['parts'][0]['text'];
            setState(() {
              _generatedSummary = summary;
              _summaryController.text = summary;
            });
          } else {
            _summaryErrorMessage = 'Invalid Gemini API response structure.';
            print('DEBUG: Invalid Gemini API response structure: $data');
          }
        } else {
          throw DioException(
            requestOptions: RequestOptions(path: fullGeminiApiUrl),
            response: response,
            error: 'Unexpected status: ${response.statusCode}',
          );
        }
      } on DioException catch (e) {
        retryCount++;
        print(
            'Retry $retryCount due to DioException: ${e.response?.statusCode} - ${e.response?.statusMessage}');
        await Future.delayed(Duration(seconds: 2 * retryCount));
        if (retryCount == 3) rethrow;
      }
    }
  } on DioException catch (e) {
    _summaryErrorMessage =
        'Gemini service is temporarily overloaded. Please try again later.';
    print(
        'DEBUG: DioException during Gemini API call: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
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
        'originalText': widget.conversationText, // Store the original conversation text
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
    // Using currentTheme for consistent styling
    // Note: Some colors are hardcoded as per your provided file for exact match.
    final ThemeData currentTheme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consultation Summary'),
        backgroundColor: Colors.green, // Hardcoded as per your provided file
        elevation: 0, // Hardcoded as per your provided file
      ),
      backgroundColor: Colors.green[50], // Hardcoded as per your provided file
      body: _isLoadingSummary && _generatedSummary == 'Generating summary...' // Only show full loading for initial summary generation
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Generating medical summary...', style: TextStyle(fontSize: 16)), // Text style kept as per your provided file
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
                    style: TextStyle( // Text style kept as per your provided file
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white, // Hardcoded as per your provided file
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.green[200]!), // Hardcoded as per your provided file
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05), // Hardcoded as per your provided file
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
                      decoration: const InputDecoration( // Hardcoded as per your provided file
                        border: InputBorder.none, // Remove default border
                        hintText: 'Summary will appear here...',
                      ),
                      style: TextStyle(fontSize: 16, color: Colors.blueGrey[800]), // Hardcoded as per your provided file
                    ),
                  ),
                  const SizedBox(height: 30),

                  // NEW BUTTON: Manage Medicines List
                  ElevatedButton.icon(
                    onPressed: _isLoadingSummary ? null : () {
                      // Navigate to the new MedicinesListScreen, passing the generated summary
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MedicinesListScreen(
                            summaryText: _summaryController.text, patientId: '', // Pass the generated/edited summary
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.medication, size: 28),
                    label: const Text(
                      'Manage Medicines List',
                      style: TextStyle(fontSize: 20),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: currentTheme.elevatedButtonTheme.style?.backgroundColor?.resolve(MaterialState.values.toSet()) ?? currentTheme.primaryColor, // Using theme for this button
                      foregroundColor: currentTheme.elevatedButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()) ?? currentTheme.colorScheme.onPrimary, // Using theme for this button
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
                    onPressed: _isLoadingSummary ? null : _saveSummary, // Call _saveSummary function
                    icon: const Icon(Icons.save, size: 28),
                    label: const Text(
                      'Save Summary',
                      style: TextStyle(fontSize: 20),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent, // Hardcoded as per your provided file
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
                      backgroundColor: Colors.grey, // Hardcoded as per your provided file
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
