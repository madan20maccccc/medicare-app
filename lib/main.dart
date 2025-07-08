import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:medicare/firebase_options.dart'; // Ensure this file exists and is correct
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import 'package:medicare/role_selection_screen.dart';
// Removed direct imports for home screens as navigation will start from RoleSelectionScreen
// import 'package:medicare/doctor_home_screen.dart';
// import 'package:medicare/patient_home_screen.dart';
// import 'package:medicare/complete_profile_screen.dart';
import 'package:medicare/theme_provider.dart';
import 'package:medicare/app_themes.dart';
import 'package:medicare/services/data_loader.dart';

// Global variables provided by the Canvas environment
// These are essential for Firebase authentication within the Canvas platform.
// DO NOT modify these.
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');
const String __initial_auth_token = String.fromEnvironment('INITIAL_AUTH_TOKEN', defaultValue: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print('DEBUG: --- Firebase Initialization Start (Using firebase_options.dart) ---');
    print('DEBUG: Raw __app_id from environment: $__app_id');
    print('DEBUG: Raw __initial_auth_token from environment: ${__initial_auth_token.isNotEmpty ? "TOKEN_PRESENT" : "TOKEN_MISSING"}');

    // Initialize Firebase App
    final FirebaseApp app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Get Firebase Auth instance for the initialized app
    final FirebaseAuth auth = FirebaseAuth.instanceFor(app: app);

    // Sign in with custom token if provided by the environment.
    // This allows the app to function with Firestore rules that require authentication,
    // even if the user hasn't explicitly logged in yet via email/password or Google.
    if (__initial_auth_token.isNotEmpty) {
      await auth.signInWithCustomToken(__initial_auth_token);
      print('Firebase: Signed in with custom token.');
    } else {
      // If no custom token, sign in anonymously.
      await auth.signInAnonymously();
      print('Firebase: Signed in anonymously.');
    }

    // Ensure Firestore instance is accessible (implicitly initialized by Firebase.initializeApp)
    FirebaseFirestore.instance;

    print('Firebase: App ID: ${__app_id}');
    print('Firebase: User ID: ${auth.currentUser?.uid ?? "N/A"}');
    print('Firebase: Initialization successful.');
    print('DEBUG: --- Firebase Initialization End ---');

  } catch (e) {
    print('Firebase: CRITICAL ERROR during initialization: $e');
    // In a production app, you might want to show a user-friendly error screen here.
  }

  runApp(
    MultiProvider( // Use MultiProvider to manage multiple providers
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()), // Provides theme management
        ChangeNotifierProvider(create: (context) => DataLoader()), // Provides CSV data loading
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Medicare App',
      themeMode: themeProvider.themeMode, // Use themeMode from ThemeProvider
      theme: AppThemes.lightTheme, // Define light theme
      darkTheme: AppThemes.darkTheme, // Define dark theme
      
      debugShowCheckedModeBanner: false, // Remove debug banner
      // Set RoleSelectionScreen as the initial home screen
      home: const RoleSelectionScreen(),
    );
  }
}
