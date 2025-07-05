import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:medicare/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // FIXED: Changed from .s to .dart

import 'package:medicare/role_selection_screen.dart';
import 'package:medicare/doctor_home_screen.dart';
import 'package:medicare/patient_home_screen.dart';
import 'package:medicare/complete_profile_screen.dart';
import 'package:medicare/theme_provider.dart';
import 'package:medicare/app_themes.dart';

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');
const String __initial_auth_token = String.fromEnvironment('INITIAL_AUTH_TOKEN', defaultValue: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print('DEBUG: --- Firebase Initialization Start (Using firebase_options.dart) ---');
    print('DEBUG: Raw __app_id from environment: $__app_id');
    print('DEBUG: Raw __initial_auth_token from environment: ${__initial_auth_token.isNotEmpty ? "TOKEN_PRESENT" : "TOKEN_MISSING"}');

    final FirebaseApp app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final FirebaseAuth auth = FirebaseAuth.instanceFor(app: app);

    if (__initial_auth_token.isNotEmpty) {
      await auth.signInWithCustomToken(__initial_auth_token);
      print('Firebase: Signed in with custom token.');
    }

    FirebaseFirestore.instance;

    print('Firebase: App ID: ${__app_id}');
    print('Firebase: User ID: ${auth.currentUser?.uid ?? "N/A"}');
    print('Firebase: Initialization successful.');
    print('DEBUG: --- Firebase Initialization End ---');

  } catch (e) {
    print('Firebase: CRITICAL ERROR during initialization: $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final ThemeData currentTheme = Theme.of(context);

    return MaterialApp(
      title: 'Medicare App',
      themeMode: themeProvider.themeMode,
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            final User user = snapshot.data!;
            
            if (user.email != null && !user.emailVerified) {
              print('User ${user.email} is not email verified.');
              return Scaffold(
                backgroundColor: currentTheme.scaffoldBackgroundColor,
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.email, size: 80, color: currentTheme.primaryColor),
                        const SizedBox(height: 20),
                        Text(
                          'Please verify your email address to continue. Check your inbox.',
                          textAlign: TextAlign.center,
                          style: currentTheme.textTheme.titleMedium?.copyWith(color: Colors.orange),
                        ),
                        const SizedBox(height: 30),
                        const CircularProgressIndicator(),
                      ],
                    ),
                  ),
                ),
              );
            }

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('artifacts')
                  .doc(__app_id)
                  .collection('users')
                  .doc(user.uid)
                  .get(),
              builder: (context, userDocSnapshot) {
                if (userDocSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (userDocSnapshot.hasData && userDocSnapshot.data!.exists) {
                  final userData = userDocSnapshot.data!.data() as Map<String, dynamic>;
                  final userRole = userData['role'] as String?;
                  final userName = userData['name'] as String?;

                  print('DEBUG: User ${user.uid} profile found. Role: $userRole, Name: $userName');

                  if (userRole == 'doctor') {
                    return DoctorHomeScreen(doctorName: userName ?? user.email ?? 'Doctor');
                  } else if (userRole == 'patient') {
                    return PatientHomeScreen(patientName: userName ?? user.email ?? 'Patient');
                  }
                }
                print('DEBUG: User ${user.uid} profile not found or role missing. Redirecting to CompleteProfileScreen.');
                return CompleteProfileScreen(userId: user.uid, email: user.email);
              },
            );
          } else {
            print('DEBUG: No user logged in. Redirecting to RoleSelectionScreen.');
            return const RoleSelectionScreen();
          }
        },
      ),
    );
  }
}
