// lib/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:medicare/doctor_login_screen.dart';
import 'package:medicare/patient_login_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Role'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: Theme.of(context).appBarTheme.elevation,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.supervised_user_circle,
                size: 120,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 40),
              Text(
                'Who are you?',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DoctorLoginScreen()),
                  );
                },
                icon: const Icon(Icons.medical_services, size: 28),
                label: const Text(
                  'I am a Doctor',
                  style: TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent, // Specific color
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PatientLoginScreen()),
                  );
                },
                icon: const Icon(Icons.person, size: 28),
                label: const Text(
                  'I am a Patient',
                  style: TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Specific color
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
