import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart'; // Ensure intl is in your pubspec.yaml if not already
import 'package:medicare/models/medicine_prescription.dart'; // Import your MedicinePrescription model
import 'package:url_launcher/url_launcher.dart'; // For sharing via WhatsApp/Email

// PDF generation imports
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart'; // For PDF preview and printing
import 'dart:typed_data'; // For Uint8List

// For navigation back to doctor home (if needed, otherwise remove)
import 'package:medicare/doctor_home_screen.dart';


const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class OpdReportFinalScreen extends StatefulWidget {
  final String? patientId; // Made optional
  final String summaryText; // This is the summary from the conversation, used for initial diagnosis
  final List<MedicinePrescription> medicines; // Changed to MedicinePrescription list
  final String? chiefComplaint;

  const OpdReportFinalScreen({
    super.key,
    this.patientId, // Now optional
    required this.summaryText, // Kept for initial diagnosis value
    required this.medicines, // Changed parameter name and type
    this.chiefComplaint,
  });

  @override
  State<OpdReportFinalScreen> createState() => _OpdReportFinalScreenState();
}

class _OpdReportFinalScreenState extends State<OpdReportFinalScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _patientIdInputController = TextEditingController(); // New controller for manual ID input

  String _statusMessage = '';
  bool _isLoading = false;
  String? _userId;

  // State variables for fetched patient details
  String _fetchedPatientName = 'N/A';
  String _fetchedPatientAge = 'N/A';
  String _fetchedPatientGender = 'N/A';
  String _fetchedPatientContact = 'N/A';
  String _fetchedPatientAddress = 'N/A';
  String _fetchedPatientEmail = 'N/A'; // New: fetched patient email

  // Local patient ID that will be used for saving the report (either from widget or manual input)
  String? _currentPatientId;
  String? _currentChiefComplaint; // Local chief complaint

  @override
  void initState() {
    super.initState();
    _userId = _auth.currentUser?.uid;
    _diagnosisController.text = widget.summaryText; // Pre-fill diagnosis with summary

    if (widget.patientId != null && widget.patientId!.isNotEmpty) {
      _currentPatientId = widget.patientId;
      _currentChiefComplaint = widget.chiefComplaint;
      _patientIdInputController.text = widget.patientId!; // Show the ID if passed
      _fetchPatientDetails(widget.patientId!);
    } else {
      // If no patientId is passed, indicate ready for manual input
      _statusMessage = 'Enter Patient ID to load details.';
    }
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _notesController.dispose();
    _patientIdInputController.dispose();
    super.dispose();
  }

  Future<void> _fetchPatientDetails(String patientId) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Fetching patient details...';
      // Reset fetched details
      _fetchedPatientName = 'N/A';
      _fetchedPatientAge = 'N/A';
      _fetchedPatientGender = 'N/A';
      _fetchedPatientContact = 'N/A';
      _fetchedPatientAddress = 'N/A';
      _fetchedPatientEmail = 'N/A';
    });

    try {
      // Ensure the collection path matches where patient details are saved in PatientDetailsFormScreen
      // It was in 'artifacts/{appId}/public/patients/data/{patientId}'
      final patientDoc = await _firestore
          .collection('artifacts')
          .doc(__app_id)
          .collection('public')
          .doc('patients')
          .collection('data')
          .doc(patientId)
          .get();

      if (patientDoc.exists) {
        final data = patientDoc.data();
        if (mounted) {
          setState(() {
            _fetchedPatientName = data?['name'] ?? 'N/A';
            _fetchedPatientAge = data?['age'] ?? 'N/A';
            _fetchedPatientGender = data?['gender'] ?? 'N/A';
            _fetchedPatientContact = data?['contactNumber'] ?? 'N/A';
            _fetchedPatientAddress = data?['address'] ?? 'N/A';
            _fetchedPatientEmail = data?['email'] ?? 'N/A'; // Fetch email
            _currentChiefComplaint = data?['chiefComplaint'] ?? widget.chiefComplaint; // Prioritize fetched CC
            _statusMessage = 'Patient details loaded successfully. Verify and proceed.';
            _currentPatientId = patientId; // Confirm the current patient ID
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _statusMessage = 'Patient with ID "$patientId" not found.';
            _currentPatientId = null; // Clear if not found
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error fetching patient details: $e';
          _currentPatientId = null;
        });
      }
      print('Error fetching patient details: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveOpdReport() async {
    if (!mounted) return;
    if (_userId == null) {
      setState(() => _statusMessage = 'User not authenticated.');
      return;
    }
    if (_currentPatientId == null || _currentPatientId!.isEmpty) {
      setState(() => _statusMessage = 'Please load patient details before saving the report.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Saving OPD report...';
    });

    try {
      final String reportId = _uuid.v4();
      final String formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      final opdReportData = {
        'reportId': reportId,
        'patientId': _currentPatientId,
        'patientName': _fetchedPatientName,
        'patientAge': _fetchedPatientAge,
        'patientGender': _fetchedPatientGender,
        'chiefComplaint': _currentChiefComplaint, // Use the local chief complaint
        'diagnosis': _diagnosisController.text.trim(),
        'medicines': widget.medicines.map((m) => m.toJson()).toList(), // Convert list of objects to list of maps
        'additionalNotes': _notesController.text.trim(),
        'recordedByUserId': _userId,
        'timestamp': FieldValue.serverTimestamp(),
        'reportDate': formattedDate, // Store formatted date for display
      };

      await _firestore
          .collection('artifacts')
          .doc(__app_id)
          .collection('opdReports') // New collection for OPD reports
          .doc(reportId)
          .set(opdReportData);

      if (mounted) {
        setState(() {
          _statusMessage = 'OPD Report saved successfully!';
        });
        _showSuccessDialog(opdReportData);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error saving OPD report: $e';
        });
      }
      print('Error saving OPD report: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessDialog(Map<String, dynamic> opdReportData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final theme = Theme.of(context);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: theme.primaryColor, size: 30),
              const SizedBox(width: 10),
              Text('Report Saved!', style: theme.textTheme.headlineSmall),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OPD Report for ${opdReportData['patientName']} (ID: ${opdReportData['patientId']}) has been saved successfully.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Text('Share this report:', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _shareReportViaWhatsApp(opdReportData),
                    icon: const Icon(Icons.chat, color: Colors.white), // Changed from Icons.whatsapp to Icons.chat
                    label: const Text('WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _shareReportViaEmail(opdReportData),
                    icon: const Icon(Icons.email, color: Colors.white),
                    label: const Text('Email'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Generate PDF and show preview
                      final pdfBytes = await _generatePdfReport(opdReportData);
                      if (pdfBytes != null) {
                        Printing.sharePdf(bytes: pdfBytes, filename: 'OPD_Report_${opdReportData['patientId']}.pdf');
                      } else {
                        _showShareError('Failed to generate PDF for sharing.');
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                    label: const Text('PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).popUntil((route) => route.isFirst); // Go back to DoctorHomeScreen
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  // Helper function to generate the text content for sharing (WhatsApp/Email)
  String _generateReportText(Map<String, dynamic> reportData) {
    String medicinesText = (reportData['medicines'] as List<dynamic>)
        .map((m) =>
            '  - ${m['name']} (${m['dosage']}) - Duration: ${m['duration'] ?? 'N/A'}, Frequency: ${m['frequency'] ?? 'N/A'}, Timing: ${m['timing'] ?? 'N/A'}.') // Updated to use duration and timing
        .join('\n');

    return """
*OPD Report*
Date: ${reportData['reportDate']}
Report ID: ${reportData['reportId']}

*Patient Details:*
Name: ${reportData['patientName']}
ID: ${reportData['patientId']}
Age: ${reportData['patientAge']}
Gender: ${reportData['patientGender']}
Contact: ${reportData['patientContact'] ?? 'N/A'}
Address: ${reportData['patientAddress'] ?? 'N/A'}
Email: ${reportData['patientEmail'] ?? 'N/A'}

Chief Complaint: ${reportData['chiefComplaint'] ?? 'N/A'}
Diagnosis: ${reportData['diagnosis']}

*Prescribed Medicines:*
${medicinesText.isNotEmpty ? medicinesText : 'No medicines prescribed.'}

Additional Notes: ${reportData['additionalNotes'].isNotEmpty ? reportData['additionalNotes'] : 'N/A'}
""";
  }

  // New function to generate the PDF report
  Future<Uint8List> _generatePdfReport(Map<String, dynamic> reportData) async {
    final pdf = pw.Document();

    final List<MedicinePrescription> medicines = (reportData['medicines'] as List<dynamic>)
        .map((m) => MedicinePrescription.fromJson(m as Map<String, dynamic>))
        .toList();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'OPD Report',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Report ID: ${reportData['reportId']}', style: pw.TextStyle(fontSize: 12)),
              pw.Text('Date: ${reportData['reportDate']}', style: pw.TextStyle(fontSize: 12)),
              pw.Divider(height: 20, thickness: 1),

              // Patient Details Section
              pw.Text('Patient Details:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Name: ${reportData['patientName'] ?? 'N/A'}'),
                  pw.Text('Patient ID: ${reportData['patientId'] ?? 'N/A'}'),
                  pw.Text('Age: ${reportData['patientAge'] ?? 'N/A'}'),
                  pw.Text('Gender: ${reportData['patientGender'] ?? 'N/A'}'),
                  pw.Text('Contact: ${reportData['patientContact'] ?? 'N/A'}'),
                  pw.Text('Address: ${reportData['patientAddress'] ?? 'N/A'}'),
                  pw.Text('Email: ${reportData['patientEmail'] ?? 'N/A'}'),
                ],
              ),
              pw.SizedBox(height: 20),

              // Chief Complaint Section
              pw.Text('Chief Complaint:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text(reportData['chiefComplaint'] ?? 'N/A'),
              pw.SizedBox(height: 20),

              // Diagnosis Section
              pw.Text('Diagnosis:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text(reportData['diagnosis'] ?? 'N/A'),
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

              // Additional Notes Section
              pw.Text('Additional Notes:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text(reportData['additionalNotes'].isNotEmpty ? reportData['additionalNotes'] : 'N/A'),
              pw.SizedBox(height: 20),

              // Footer
              pw.Align(
                alignment: pw.Alignment.bottomRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Doctor: ${_auth.currentUser?.displayName ?? _auth.currentUser?.email ?? 'Unknown'}'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<void> _shareReportViaWhatsApp(Map<String, dynamic> reportData) async {
    final String reportText = _generateReportText(reportData);
    final String whatsappUrl = 'whatsapp://send?text=${Uri.encodeComponent(reportText)}';

    try {
      if (await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication)) {
        // Successfully launched WhatsApp
      } else {
        // Fallback for web or if WhatsApp isn't installed
        final String webWhatsappUrl = 'https://wa.me/?text=${Uri.encodeComponent(reportText)}';
        if (await launchUrl(Uri.parse(webWhatsappUrl), mode: LaunchMode.externalApplication)) {
          // Successfully launched web WhatsApp
        } else {
          _showShareError('Could not launch WhatsApp. Please ensure it is installed.');
        }
      }
    } catch (e) {
      _showShareError('Error launching WhatsApp: $e');
      print('Error launching WhatsApp: $e');
    }
  }

  Future<void> _shareReportViaEmail(Map<String, dynamic> reportData) async {
    final String reportText = _generateReportText(reportData);
    final String subject = 'OPD Report for ${reportData['patientName']} (ID: ${reportData['patientId']})';
    final String emailBody = reportText;
    
    // Use _fetchedPatientEmail for the recipient if available, otherwise leave blank
    final String recipientEmail = _fetchedPatientEmail != 'N/A' ? _fetchedPatientEmail : '';

    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: recipientEmail, // Optional recipient
      queryParameters: {
        'subject': subject,
        'body': emailBody,
      },
    );

    try {
      if (await launchUrl(emailLaunchUri)) { // launchUrl already returns bool and doesn't need canLaunchUrl
        // Successfully launched email client
      } else {
        _showShareError('Could not launch email client.');
      }
    } catch (e) {
      _showShareError('Error launching email: $e');
      print('Error launching email: $e');
    }
  }

  void _showShareError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine if we should show the manual ID input or the pre-filled ID
    final bool showManualIdInput = widget.patientId == null || widget.patientId!.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Final OPD Report'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: theme.appBarTheme.elevation,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: theme.primaryColor),
                  const SizedBox(height: 20),
                  Text(_statusMessage, style: theme.textTheme.titleMedium),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status/Error Message Area
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: _statusMessage.contains('Error') || _statusMessage.contains('not found') ? Colors.red.withOpacity(0.1) : theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _statusMessage.contains('Error') || _statusMessage.contains('not found') ? Colors.red : theme.primaryColor,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      _statusMessage,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _statusMessage.contains('Error') || _statusMessage.contains('not found') ? Colors.red : theme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Patient ID Input Field
                  if (showManualIdInput) ...[
                    TextField(
                      controller: _patientIdInputController,
                      decoration: InputDecoration(
                        labelText: 'Enter Patient ID',
                        hintText: 'e.g., abcd-1234-efgh-5678',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        suffixIcon: IconButton(
                          icon: Icon(Icons.search, color: theme.primaryColor),
                          onPressed: () {
                            final String id = _patientIdInputController.text.trim();
                            if (id.isNotEmpty) {
                              _fetchPatientDetails(id);
                            } else {
                              setState(() => _statusMessage = 'Please enter a Patient ID.');
                            }
                          },
                        ),
                      ),
                      keyboardType: TextInputType.text,
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          _fetchPatientDetails(value.trim());
                        } else {
                          setState(() => _statusMessage = 'Please enter a Patient ID.');
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Fetched Patient Details Display
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    color: theme.cardColor,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Patient Details',
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (_fetchedPatientName != 'N/A' && _currentPatientId != null) // Show tick if details loaded
                                Icon(Icons.check_circle, color: Colors.green, size: 30),
                            ],
                          ),
                          const Divider(height: 20, thickness: 1),
                          _buildDetailRow(theme, 'Patient ID:', _currentPatientId ?? 'N/A', isSelectable: true),
                          _buildDetailRow(theme, 'Name:', _fetchedPatientName),
                          _buildDetailRow(theme, 'Age:', _fetchedPatientAge),
                          _buildDetailRow(theme, 'Gender:', _fetchedPatientGender),
                          _buildDetailRow(theme, 'Contact:', _fetchedPatientContact),
                          _buildDetailRow(theme, 'Address:', _fetchedPatientAddress),
                          _buildDetailRow(theme, 'Email:', _fetchedPatientEmail), // Display email
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Chief Complaint
                  Text(
                    'Chief Complaint:',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(
                        _currentChiefComplaint ?? 'N/A',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Diagnosis Input
                  TextField(
                    controller: _diagnosisController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Diagnosis (from conversation summary)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: theme.inputDecorationTheme.fillColor,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Medicines List
                  Text(
                    'Prescribed Medicines:',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(10),
                      color: theme.cardColor,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: widget.medicines.isEmpty
                        ? Text('No medicines prescribed.', style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic))
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: widget.medicines.length,
                            itemBuilder: (context, index) {
                              final medicine = widget.medicines[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Text(
                                  '• ${medicine.name} (${medicine.dosage}) - Duration: ${medicine.duration}, Frequency: ${medicine.frequency}, Timing: ${medicine.timing}.', // Updated to use duration and timing
                                  style: theme.textTheme.bodyMedium,
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Additional Notes (Optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: theme.inputDecorationTheme.fillColor,
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: (_isLoading || _currentPatientId == null) ? null : _saveOpdReport,
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: Text(
                      "Save Final OPD Report",
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: theme.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(_statusMessage, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value, {bool isSelectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100, // Fixed width for labels
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: isSelectable
                ? SelectableText(
                    value,
                    style: theme.textTheme.bodyLarge,
                  )
                : Text(
                    value,
                    style: theme.textTheme.bodyLarge,
                  ),
          ),
        ],
      ),
    );
  }
}
