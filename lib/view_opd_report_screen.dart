// lib/view_opd_report_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // For date formatting

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');
const String __initial_auth_token = String.fromEnvironment('INITIAL_AUTH_TOKEN', defaultValue: '');

class ViewOpdReportScreen extends StatefulWidget {
  const ViewOpdReportScreen({super.key});

  @override
  State<ViewOpdReportScreen> createState() => _ViewOpdReportScreenState();
}

class _ViewOpdReportScreenState extends State<ViewOpdReportScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _patientIdController = TextEditingController();

  List<Map<String, dynamic>> _opdReports = [];
  bool _isLoading = false;
  String _errorMessage = '';
  String? _userId;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    try {
      if (_auth.currentUser == null) {
        if (__initial_auth_token.isNotEmpty) {
          await _auth.signInWithCustomToken(__initial_auth_token);
        } else {
          await _auth.signInAnonymously();
        }
      }
      setState(() {
        _userId = _auth.currentUser?.uid;
      });
      print('Firebase: Current User ID in ViewOpdReportScreen: $_userId');
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing Firebase Auth: $e';
      });
      print('Error initializing Firebase Auth: $e');
    }
  }

  Future<void> _fetchOpdReports() async {
    final patientId = _patientIdController.text.trim();
    if (patientId.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a Patient ID to view reports.';
        _opdReports = [];
      });
      return;
    }
    if (_userId == null) {
      setState(() {
        _errorMessage = 'User not authenticated. Cannot fetch reports.';
        _opdReports = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _opdReports = [];
    });

    try {
      // Fetch reports from the doctor's private consultations collection
      final QuerySnapshot querySnapshot = await _firestore
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(_userId)
          .collection('consultations')
          .where('patientId', isEqualTo: patientId)
          .orderBy('timestamp', descending: true) // Order by timestamp to get latest first
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        setState(() {
          _opdReports = querySnapshot.docs
              .map((doc) => doc.data() as Map<String, dynamic>)
              .toList();
        });
      } else {
        setState(() {
          _errorMessage = 'No OPD reports found for Patient ID: "$patientId".';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching OPD reports: $e';
      });
      print('Error fetching OPD reports: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _patientIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('View Past OPD Reports'),
        backgroundColor: Colors.blueGrey, // Distinct color for this screen
        elevation: 0,
      ),
      backgroundColor: Colors.blueGrey[50],
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Enter Patient ID:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey[700],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _patientIdController,
                    decoration: InputDecoration(
                      labelText: 'Patient ID',
                      hintText: 'e.g., 123e4567-e89b-12d3-a456-426614174000',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.badge),
                    ),
                    style: currentTheme.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _fetchOpdReports,
                  icon: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.search),
                  label: const Text('Search'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentTheme.primaryColor,
                    foregroundColor: currentTheme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _opdReports.isEmpty && _errorMessage.isEmpty
                      ? const Center(
                          child: Text(
                            'Enter Patient ID and click search to view reports.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _opdReports.length,
                          itemBuilder: (context, index) {
                            final report = _opdReports[index];
                            final timestamp = report['timestamp'] as Timestamp?;
                            final formattedDate = timestamp != null
                                ? DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toDate())
                                : 'N/A';
                            final prescribedMedicines = (report['prescribedMedicines'] as List<dynamic>?)
                                    ?.map((e) => (e as Map<String, dynamic>)['name'] ?? 'N/A')
                                    .join(', ') ?? 'No medicines prescribed.';

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Consultation Date: $formattedDate',
                                      style: currentTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    const Divider(),
                                    _buildReportDetail('Patient Name:', report['patientName'] ?? 'N/A'),
                                    _buildReportDetail('Patient ID:', report['patientId'] ?? 'N/A'),
                                    _buildReportDetail('Chief Complaint:', report['patientChiefComplaint'] ?? 'N/A'),
                                    _buildReportDetail('Diagnosis:', report['diagnosis'] ?? 'N/A'),
                                    _buildReportDetail('Prescribed Medicines:', prescribedMedicines),
                                    _buildReportDetail('Follow-up Instructions:', report['followUpInstructions'] ?? 'N/A'),
                                    _buildReportDetail('Additional Notes:', report['notes'] ?? 'N/A'),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: ' $value'),
          ],
        ),
      ),
    );
  }
}
