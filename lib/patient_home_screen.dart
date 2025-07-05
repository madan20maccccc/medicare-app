// lib/patient_home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
// No need for cloud_firestore import if not directly used in this screen
// import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare/role_selection_screen.dart';
import 'package:medicare/profile_screen.dart';
import 'package:medicare/settings_screen.dart';

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class PatientHomeScreen extends StatefulWidget {
  final String patientName;

  const PatientHomeScreen({super.key, required this.patientName});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  String _currentPatientName = 'Patient';
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  @override
  void initState() {
    super.initState();
    _currentPatientName = widget.patientName;
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the current theme to access its properties safely
    final ThemeData currentTheme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Home'),
        backgroundColor: currentTheme.appBarTheme.backgroundColor, // Use currentTheme
        elevation: currentTheme.appBarTheme.elevation,
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: currentTheme.appBarTheme.iconTheme?.color), // Use currentTheme
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.person, color: currentTheme.appBarTheme.iconTheme?.color), // Use currentTheme
            tooltip: 'My Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: currentTheme.appBarTheme.iconTheme?.color), // Use currentTheme
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      backgroundColor: currentTheme.scaffoldBackgroundColor, // Use currentTheme
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.health_and_safety,
                size: 100,
                color: currentTheme.primaryColor, // Use currentTheme
              ),
              const SizedBox(height: 30),
              Text(
                'Welcome, $_currentPatientName!',
                style: currentTheme.textTheme.titleLarge, // Use currentTheme
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Your health information at a glance.',
                style: currentTheme.textTheme.bodyMedium, // Use currentTheme
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Starting voice recording for form... (Next Step!)')),
                  );
                },
                icon: const Icon(Icons.mic, size: 28),
                label: const Text(
                  'Start Recording Symptoms',
                  style: TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  // Safely resolve MaterialStateProperty<Color?> to Color?
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
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Viewing your records... (Coming Soon!)')),
                  );
                },
                icon: const Icon(Icons.folder_open, size: 28),
                label: const Text(
                  'View My Records',
                  style: TextStyle(fontSize: 20),
                ),
                style: OutlinedButton.styleFrom(
                  // Safely resolve MaterialStateProperty<Color?> to Color?
                  foregroundColor: currentTheme.textButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()) ?? currentTheme.primaryColor,
                  side: BorderSide(color: currentTheme.primaryColor, width: 2), // Use currentTheme.primaryColor for border
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
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
