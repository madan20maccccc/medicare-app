// lib/patient_home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:google_sign_in/google_sign_in.dart'; // Removed: Assuming patients don't use Google Sign-In for direct login anymore
import 'package:medicare/role_selection_screen.dart';
import 'package:medicare/profile_screen.dart'; // For viewing/editing profile
import 'package:medicare/settings_screen.dart';
// No need to import patient_details_form_screen.dart here, as navigation is from RoleSelectionScreen

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class PatientHomeScreen extends StatefulWidget {
  final String patientName;
  final String? patientId; // Patient ID (UUID) passed from PatientDetailsFormScreen

  const PatientHomeScreen({super.key, required this.patientName, this.patientId});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  String _currentPatientName = 'Patient';
  String? _currentPatientId; // State variable for patient ID
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // final GoogleSignIn _googleSignIn = GoogleSignIn(); // Removed: No longer needed if patients don't use Google Sign-In

  @override
  void initState() {
    super.initState();
    _currentPatientName = widget.patientName;
    _currentPatientId = widget.patientId; // Initialize patient ID from widget
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
      // No GoogleSignIn.signOut() call needed if patients don't use it.
      // If a doctor uses GoogleSignIn, their logout will handle it.
      if (mounted) {
        // Navigate back to the role selection screen and remove all previous routes
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Home'),
        backgroundColor: currentTheme.appBarTheme.backgroundColor,
        elevation: currentTheme.appBarTheme.elevation,
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: currentTheme.appBarTheme.iconTheme?.color),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.person, color: currentTheme.appBarTheme.iconTheme?.color),
            tooltip: 'My Profile',
            onPressed: () {
              // Navigate to ProfileScreen. ProfileScreen will fetch details based on current user's UID.
              // For patients coming from PatientDetailsFormScreen, their UID is the anonymous UID,
              // and ProfileScreen will then look up their details in the public/patients/data collection.
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: currentTheme.appBarTheme.iconTheme?.color),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      backgroundColor: currentTheme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.person_outline, // Patient-like icon
                size: 100,
                color: currentTheme.primaryColor,
              ),
              const SizedBox(height: 30),
              Text(
                'Welcome, $_currentPatientName!',
                style: currentTheme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (_currentPatientId != null) // Display patient ID if available
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Your Patient ID: $_currentPatientId',
                    style: currentTheme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'How can we assist you today?',
                style: currentTheme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),
              ElevatedButton.icon(
                onPressed: () {
                  // Navigate to ProfileScreen for viewing/editing their own details
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen()),
                  );
                },
                icon: const Icon(Icons.account_circle, size: 28), // Changed icon
                label: const Text(
                  'View My Profile', // Changed label
                  style: TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: currentTheme.elevatedButtonTheme.style?.backgroundColor?.resolve(MaterialState.values.toSet()) ?? currentTheme.primaryColor,
                  foregroundColor: currentTheme.elevatedButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()) ?? currentTheme.colorScheme.onPrimary,
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Viewing appointments (Feature coming soon!)')),
                  );
                },
                icon: const Icon(Icons.calendar_today, size: 28),
                label: const Text(
                  'View My Appointments',
                  style: TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, // Specific color for this button
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
      ),
    );
  }
}
