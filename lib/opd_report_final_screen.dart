// lib/opd_report_final_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart'; // For PDF preview and printing
import 'package:medicare/models/medicine_prescription.dart'; // Import the medicine model
import 'package:medicare/doctor_home_screen.dart'; // For navigation back to doctor home
import 'dart:typed_data'; // For Uint8List

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class OpdReportFinalScreen extends StatefulWidget {
  final String patientId;
  final String summaryText;
  final List<Map<String, dynamic>> prescribedMedicines; // List of medicine JSONs
  final String? chiefComplaint;

  const OpdReportFinalScreen({
    super.key,
    required this.patientId,
    required this.summaryText,
    required this.prescribedMedicines,
    this.chiefComplaint,
  });

  @override
  State<OpdReportFinalScreen> createState() => _OpdReportFinalScreenState();
}

class _OpdReportFinalScreenState extends State<OpdReportFinalScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _patientName = 'Loading...';
  String _patientAge = 'N/A';
  String _patientGender = 'N/A';
  String _patientContact = 'N/A';
  String _patientEmail = 'N/A';
  String _patientAddress = 'N/A';
  bool _receivePdfPermission = false;

  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchPatientDetails();
  }

  Future<void> _fetchPatientDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Fetch patient details from the public/patients/data collection
      final patientDoc = await _firestore
          .collection('artifacts')
          .doc(__app_id)
          .collection('public')
          .doc('patients')
          .collection('data')
          .doc(widget.patientId)
          .get();

      if (patientDoc.exists && patientDoc.data() != null) {
        final patientData = patientDoc.data()!;
        setState(() {
          _patientName = patientData['name'] as String? ?? 'N/A';
          _patientAge = patientData['age']?.toString() ?? 'N/A';
          _patientGender = patientData['gender'] as String? ?? 'N/A';
          _patientContact = patientData['contactNumber'] as String? ?? 'N/A';
          _patientEmail = patientData['email'] as String? ?? 'N/A';
          _patientAddress = patientData['address'] as String? ?? 'N/A';
          // Check if the patient has granted permission to receive PDFs
          _receivePdfPermission = patientData['receivePdfPermission'] as bool? ?? false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Patient details not found for ID: ${widget.patientId}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching patient details: $e';
        _isLoading = false;
      });
      print('Error fetching patient details: $e');
    }
  }

  // Function to save the consultation to Firestore
  Future<void> _saveConsultation() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _errorMessage = 'No doctor logged in to save consultation.';
        _isLoading = false;
      });
      return;
    }

    try {
      final String doctorId = currentUser.uid;
      final String doctorName = currentUser.displayName ?? currentUser.email ?? 'Unknown Doctor';

      final consultationData = {
        'patientId': widget.patientId,
        'patientName': _patientName,
        'chiefComplaint': widget.chiefComplaint,
        'summaryText': widget.summaryText,
        'prescribedMedicines': widget.prescribedMedicines,
        'consultationDate': FieldValue.serverTimestamp(), // This is the FieldValue
        'doctorId': doctorId,
        'doctorName': doctorName,
        'appId': __app_id,
      };

      // Save to doctor's private consultations subcollection
      await _firestore
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(doctorId)
          .collection('consultations')
          .add(consultationData); // Use add() for auto-generated document ID

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consultation saved successfully!')),
        );
        _showOpdSuccessDialog(); // Show success dialog after saving
      }
      print('Consultation saved successfully for doctor: $doctorId');
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save consultation: $e';
        });
      }
      print('Error saving consultation: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // NEW: Success dialog for OPD report
  void _showOpdSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must tap button to dismiss
      builder: (BuildContext dialogContext) {
        final ThemeData currentTheme = Theme.of(dialogContext);
        return AlertDialog(
          backgroundColor: currentTheme.cardTheme.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            'Consultation Saved!',
            style: currentTheme.textTheme.titleLarge?.copyWith(color: Colors.green),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OPD report for $_patientName has been successfully saved.',
                style: currentTheme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 10),
              Text(
                'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', // Use DateTime.now()
                style: currentTheme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'You can now generate a PDF or view past reports.',
                style: currentTheme.textTheme.bodyMedium,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close the dialog
                // Optionally navigate back to DoctorHomeScreen immediately
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => DoctorHomeScreen(doctorName: _auth.currentUser?.displayName ?? _auth.currentUser?.email ?? 'Doctor')),
                  (Route<dynamic> route) => false,
                );
              },
              child: Text(
                'OK',
                style: TextStyle(color: currentTheme.primaryColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  // Function to generate the PDF report
  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final doc = pw.Document();

    // Convert prescribed medicines list of maps to MedicinePrescription objects
    final List<MedicinePrescription> medicines = widget.prescribedMedicines
        .map((json) => MedicinePrescription.fromJson(json))
        .toList();

    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'OPD Consultation Report',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 10),

              // Patient Details Section
              pw.Text('Patient Details:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Name: $_patientName')),
                  pw.Expanded(child: pw.Text('ID: ${widget.patientId}')),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Age: $_patientAge')),
                  pw.Expanded(child: pw.Text('Gender: $_patientGender')),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Contact: $_patientContact')),
                  pw.Expanded(child: pw.Text('Email: $_patientEmail')),
                ],
              ),
              pw.Text('Address: $_patientAddress'),
              pw.SizedBox(height: 20),

              // Consultation Details Section
              pw.Text('Consultation Details:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              if (widget.chiefComplaint != null && widget.chiefComplaint!.isNotEmpty)
                pw.Text('Chief Complaint: ${widget.chiefComplaint}'),
              pw.Text('Summary: ${widget.summaryText}'),
              pw.SizedBox(height: 20),

              // Prescribed Medicines Section
              pw.Text('Prescribed Medicines:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              if (medicines.isEmpty)
                pw.Text('No medicines prescribed.', style: pw.TextStyle(fontStyle: pw.FontStyle.italic))
              else
                pw.Table.fromTextArray(
                  headers: ['Medicine', 'Dosage', 'Duration', 'Frequency', 'Timing'],
                  data: medicines.map((med) => [
                    med.name,
                    med.dosage,
                    med.duration,
                    med.frequency,
                    med.timing,
                  ]).toList(),
                  border: pw.TableBorder.all(color: PdfColors.grey500),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellPadding: const pw.EdgeInsets.all(5),
                ),
              pw.SizedBox(height: 20),

              // Footer
              pw.Align(
                alignment: pw.Alignment.bottomRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                    pw.Text('Doctor: ${_auth.currentUser?.displayName ?? _auth.currentUser?.email ?? 'Unknown'}'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  // Function to print/share the PDF
  Future<void> _printPdf() async {
    if (_isLoading) return; // Prevent multiple clicks
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      await Printing.layoutPdf(onLayout: _generatePdf);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF generated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error generating PDF: $e';
        });
      }
      print('Error generating PDF: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OPD Report Final'),
        backgroundColor: currentTheme.appBarTheme.backgroundColor,
        elevation: currentTheme.appBarTheme.elevation,
      ),
      backgroundColor: currentTheme.scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 60),
                        const SizedBox(height: 20),
                        Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: currentTheme.textTheme.bodyLarge?.copyWith(color: Colors.red),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _fetchPatientDetails,
                          child: const Text('Retry Fetching Details'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Final OPD Report',
                        style: currentTheme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      // Patient Details Card
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Patient Information',
                                style: currentTheme.textTheme.titleLarge?.copyWith(color: currentTheme.primaryColor),
                              ),
                              const Divider(height: 20),
                              _buildDetailRow('Name:', _patientName),
                              _buildDetailRow('Patient ID:', widget.patientId),
                              _buildDetailRow('Age:', _patientAge),
                              _buildDetailRow('Gender:', _patientGender),
                              _buildDetailRow('Contact:', _patientContact),
                              _buildDetailRow('Email:', _patientEmail),
                              _buildDetailRow('Address:', _patientAddress),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Consultation Summary Card
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Consultation Summary',
                                style: currentTheme.textTheme.titleLarge?.copyWith(color: currentTheme.primaryColor),
                              ),
                              const Divider(height: 20),
                              if (widget.chiefComplaint != null && widget.chiefComplaint!.isNotEmpty)
                                _buildDetailRow('Chief Complaint:', widget.chiefComplaint!),
                              _buildDetailRow('Summary:', widget.summaryText),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Prescribed Medicines Card
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Prescribed Medicines',
                                style: currentTheme.textTheme.titleLarge?.copyWith(color: currentTheme.primaryColor),
                              ),
                              const Divider(height: 20),
                              if (widget.prescribedMedicines.isEmpty)
                                Text(
                                  'No medicines prescribed.',
                                  style: currentTheme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: widget.prescribedMedicines.length,
                                  itemBuilder: (context, index) {
                                    final medicine = MedicinePrescription.fromJson(widget.prescribedMedicines[index]);
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${index + 1}. ${medicine.name}',
                                            style: currentTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(left: 16.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Dosage: ${medicine.dosage}', style: currentTheme.textTheme.bodyMedium),
                                                Text('Duration: ${medicine.duration}', style: currentTheme.textTheme.bodyMedium),
                                                Text('Frequency: ${medicine.frequency}', style: currentTheme.textTheme.bodyMedium),
                                                Text('Timing: ${medicine.timing}', style: currentTheme.textTheme.bodyMedium),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Action Buttons
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveConsultation,
                        icon: const Icon(Icons.save, size: 28),
                        label: const Text(
                          'Save Consultation',
                          style: TextStyle(fontSize: 20),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
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
                        onPressed: _isLoading ? null : _printPdf,
                        icon: const Icon(Icons.picture_as_pdf, size: 28),
                        label: const Text(
                          'Generate & Print PDF',
                          style: TextStyle(fontSize: 20),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
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
                        onPressed: () {
                          // Navigate back to DoctorHomeScreen and remove all other routes
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => DoctorHomeScreen(doctorName: _auth.currentUser?.displayName ?? _auth.currentUser?.email ?? 'Doctor')),
                            (Route<dynamic> route) => false,
                          );
                        },
                        icon: const Icon(Icons.home, size: 28),
                        label: const Text(
                          'Back to Doctor Home',
                          style: TextStyle(fontSize: 20),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentTheme.colorScheme.secondary,
                          foregroundColor: currentTheme.colorScheme.onSecondary,
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

  Widget _buildDetailRow(String label, String value) {
    final ThemeData currentTheme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: currentTheme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: currentTheme.textTheme.bodyMedium,
              softWrap: true,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }
}
