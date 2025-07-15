import 'package:flutter/material.dart';
import 'package:dio/dio.dart'; // For making HTTP requests
import 'dart:convert'; // For JSON encoding/decoding

// Firebase imports
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import the new MedicinesListScreen
import 'package:medicare/medicines_list_screen.dart';
import 'package:medicare/services/data_loader.dart';

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');
const String __firebase_config = String.fromEnvironment('FIREBASE_CONFIG', defaultValue: '{}');
const String __initial_auth_token = String.fromEnvironment('INITIAL_AUTH_TOKEN', defaultValue: '');

class SummaryScreen extends StatefulWidget {
  final String conversationText;
  const SummaryScreen({super.key, required this.conversationText});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final String _backendBaseUrl = 'http://192.168.29.68:5000';

  String _generatedSummary = 'Generating summary...';
  bool _isLoadingSummary = true;
  String _summaryErrorMessage = '';
  late TextEditingController _summaryController;

  late FirebaseFirestore _db;
  late FirebaseAuth _auth;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController(text: _generatedSummary);
    _initializeFirebaseAndGenerateSummary();
  }

  Future<void> _initializeFirebaseAndGenerateSummary() async {
    try {
      _db = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;

      if (_auth.currentUser == null) {
        if (__initial_auth_token.isNotEmpty) {
          await _auth.signInWithCustomToken(__initial_auth_token);
        } else {
          await _auth.signInAnonymously();
        }
      }
      _userId = _auth.currentUser?.uid;

      if (_userId == null) {
        _summaryErrorMessage = 'User not authenticated. Cannot save summary.';
        setState(() => _isLoadingSummary = false);
        return;
      }

      _generateSummary();
    } catch (e) {
      _summaryErrorMessage = 'Error initializing Firebase for SummaryScreen: $e';
      setState(() => _isLoadingSummary = false);
    }
  }

  // 🧠 Updated to handle NER response and format summary
  Future<void> _generateSummary() async {
  setState(() {
    _isLoadingSummary = true;
    _summaryErrorMessage = '';
  });

  final Dio dio = Dio();
  final url = '$_backendBaseUrl/ner';

  try {
    final response = await dio.post(url, data: {"text": widget.conversationText});

    if (response.statusCode == 200 && response.data['entities'] != null) {
      final String formattedSummary = response.data['summary'] ?? 'No summary returned';
      
      setState(() {
        _generatedSummary = formattedSummary;
        _summaryController.text = _generatedSummary;
      });
    } else {
      setState(() {
        _summaryErrorMessage = 'Unexpected response from backend.';
      });
    }
  } catch (e) {
    setState(() {
      _summaryErrorMessage = 'Failed to connect to backend: $e';
    });
  } finally {
    setState(() => _isLoadingSummary = false);
  }
}


  Future<void> _saveSummary() async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User not authenticated. Cannot save summary.')),
      );
      return;
    }

    setState(() => _isLoadingSummary = true);

    try {
      final CollectionReference consultationsRef = _db
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(_userId)
          .collection('consultations');

      await consultationsRef.add({
        'timestamp': FieldValue.serverTimestamp(),
        'originalText': widget.conversationText,
        'summary': _summaryController.text,
        'userId': _userId,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Summary saved successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving summary: $e')),
      );
    } finally {
      setState(() => _isLoadingSummary = false);
    }
  }

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consultation Summary'),
        backgroundColor: Colors.green,
        elevation: 0,
      ),
      backgroundColor: Colors.green[50],
      body: _isLoadingSummary && _generatedSummary == 'Generating summary...'
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
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Summary will appear here...',
                      ),
                      style: TextStyle(fontSize: 16, color: Colors.blueGrey[800]),
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: _isLoadingSummary
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MedicinesListScreen(
                                  summaryText: _summaryController.text,
                                  patientId: '',
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
                      backgroundColor: currentTheme.elevatedButtonTheme.style
                              ?.backgroundColor
                              ?.resolve(MaterialState.values.toSet()) ??
                          currentTheme.primaryColor,
                      foregroundColor: currentTheme.elevatedButtonTheme.style
                              ?.foregroundColor
                              ?.resolve(MaterialState.values.toSet()) ??
                          currentTheme.colorScheme.onPrimary,
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
                    onPressed: _isLoadingSummary ? null : _saveSummary,
                    icon: const Icon(Icons.save, size: 28),
                    label: const Text(
                      'Save Summary',
                      style: TextStyle(fontSize: 20),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
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
                    onPressed: _isLoadingSummary ? null : () => Navigator.pop(context),
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
    );
  }
}
