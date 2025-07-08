// lib/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:medicare/doctor_login_screen.dart'; // Import doctor login screen
import 'package:medicare/patient_details_form_screen.dart'; // Import the patient details form

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context); // Get current theme for consistent styling

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Role'),
        backgroundColor: currentTheme.appBarTheme.backgroundColor,
        elevation: currentTheme.appBarTheme.elevation,
      ),
      backgroundColor: currentTheme.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.medical_services,
                size: 120,
                color: currentTheme.primaryColor,
              ),
              const SizedBox(height: 40),
              Text(
                'Welcome to Medicare!',
                style: currentTheme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Please select your role to continue.',
                style: currentTheme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),
              SizedBox(
                width: double.infinity, // Make buttons full width
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DoctorLoginScreen()),
                    );
                  },
                  icon: const Icon(Icons.person_outline, size: 28),
                  label: const Text(
                    'I am a Doctor',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentTheme.elevatedButtonTheme.style?.backgroundColor?.resolve(MaterialState.values.toSet()),
                    foregroundColor: currentTheme.elevatedButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                    minimumSize: const Size.fromHeight(60), // Ensure consistent height
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, // Make buttons full width
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navigate directly to PatientDetailsFormScreen
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PatientDetailsFormScreen()),
                    );
                  },
                  icon: const Icon(Icons.sick_outlined, size: 28),
                  label: const Text(
                    'I am a Patient',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentTheme.elevatedButtonTheme.style?.backgroundColor?.resolve(MaterialState.values.toSet()),
                    foregroundColor: currentTheme.elevatedButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                    minimumSize: const Size.fromHeight(60), // Ensure consistent height
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
