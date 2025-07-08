// lib/doctor_home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Required for fetching doctor data
import 'package:provider/provider.dart'; // Required for DataLoader
import 'package:medicare/language_voice_input_screen.dart'; // For new consultation
import 'package:medicare/view_opd_report_screen.dart'; // For viewing past reports
import 'package:medicare/services/data_loader.dart'; // For loading CSV data
import 'package:medicare/profile_screen.dart'; // For profile management
import 'package:medicare/settings_screen.dart'; // For settings
import 'package:medicare/role_selection_screen.dart'; // For logout navigation
import 'package:medicare/complete_profile_screen.dart'; // Import CompleteProfileScreen

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');
const String __initial_auth_token = String.fromEnvironment('INITIAL_AUTH_TOKEN', defaultValue: '');

class DoctorHomeScreen extends StatefulWidget {
  // doctorName is now optional as it will be fetched from Firestore
  final String? doctorName;

  const DoctorHomeScreen({super.key, this.doctorName});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  String? _doctorName;
  String? _userId;
  String _authStatus = 'Authenticating...';
  bool _isLoadingData = true; // Tracks loading for CSVs
  String _dataLoadError = '';
  bool _isProfileComplete = false; // Tracks profile completion status

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initializeFirebaseAndFetchDoctorData(); // Initialize Firebase and fetch doctor's name
    
    // Listen to DataLoader changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataLoader = Provider.of<DataLoader>(context, listen: false);
      dataLoader.addListener(_handleDataLoaderChange);
      // Manually trigger initial check of DataLoader state to immediately set _isLoadingData
      _handleDataLoaderChange(); 
    });
  }

  @override
  void dispose() {
    // Ensure the listener is removed to prevent memory leaks
    Provider.of<DataLoader>(context, listen: false).removeListener(_handleDataLoaderChange);
    super.dispose();
  }

  // Listener to update UI based on DataLoader's state
  void _handleDataLoaderChange() {
    final dataLoader = Provider.of<DataLoader>(context, listen: false);
    if (mounted) {
      setState(() {
        _isLoadingData = !dataLoader.isLoaded;
        _dataLoadError = dataLoader.loadError ?? '';
        print('DEBUG: DataLoader state updated - isLoaded: ${dataLoader.isLoaded}, loadError: ${dataLoader.loadError}');
      });
    }
  }

  // Initializes Firebase Auth and fetches doctor's name from Firestore
  Future<void> _initializeFirebaseAndFetchDoctorData() async {
    try {
      if (_auth.currentUser == null) {
        if (__initial_auth_token.isNotEmpty) {
          await _auth.signInWithCustomToken(__initial_auth_token);
          print('Firebase: Signed in with custom token.');
        } else {
          await _auth.signInAnonymously();
          print('Firebase: Signed in anonymously.');
        }
      }

      final User? user = _auth.currentUser;
      if (user != null) {
        setState(() {
          _userId = user.uid;
          _authStatus = 'Authenticated as: ${user.uid}';
        });

        // Fetch doctor's name and profile completion from Firestore
        final doctorDoc = await _firestore
            .collection('artifacts')
            .doc(__app_id)
            .collection('users')
            .doc(_userId)
            .get();

        if (doctorDoc.exists && doctorDoc.data() != null) {
          final userData = doctorDoc.data()!;
          setState(() {
            _doctorName = userData['name'] ?? 'Doctor';
            _isProfileComplete = userData['isProfileComplete'] as bool? ?? false;
            print('DEBUG: Profile fetched - Name: $_doctorName, isProfileComplete: $_isProfileComplete');
          });
        } else {
          // If doctor document doesn't exist, create a placeholder and mark profile incomplete
          final initialName = widget.doctorName ?? user.email ?? 'Doctor $_userId';
          await _firestore
              .collection('artifacts')
              .doc(__app_id)
              .collection('users')
              .doc(_userId)
              .set({'name': initialName, 'role': 'doctor', 'isProfileComplete': false}, SetOptions(merge: true));
          setState(() {
            _doctorName = initialName;
            _isProfileComplete = false;
            print('DEBUG: Profile created - Name: $_doctorName, isProfileComplete: $_isProfileComplete');
          });
        }
      } else {
        setState(() {
          _authStatus = 'Authentication failed.';
        });
      }
    } catch (e) {
      setState(() {
        _authStatus = 'Authentication error: $e';
      });
      print('Authentication error: $e');
    }
  }

  // Handles user logout
  Future<void> _logout() async {
    try {
      await _auth.signOut();
      // No GoogleSignIn.signOut() here unless explicitly using Google Sign-In in this app
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
    final dataLoader = Provider.of<DataLoader>(context); // Access DataLoader state

    // Buttons are disabled ONLY if data is loading or there's a data load error
    final bool areButtonsDisabledByData = _isLoadingData || _dataLoadError.isNotEmpty;
    print('DEBUG: Build - areButtonsDisabledByData: $areButtonsDisabledByData (isLoadingData: $_isLoadingData, dataLoadError: $_dataLoadError)');


    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Dashboard'),
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              ).then((_) => _initializeFirebaseAndFetchDoctorData()); // Refresh profile status on return
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
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${_doctorName ?? 'Doctor'}!',
                      style: currentTheme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your User ID: ${_userId ?? 'N/A'}', // Display user ID
                      style: currentTheme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _authStatus,
                      style: currentTheme.textTheme.bodySmall?.copyWith(
                        color: _authStatus.contains('Error') || _authStatus.contains('failed') ? Colors.red : Colors.green,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_isLoadingData)
                      // FIX: Wrapped Text with Expanded to prevent overflow
                      const Row(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 10),
                          Expanded( // Added Expanded here
                            child: Text('Loading essential medical data (medicines, symptoms)...'),
                          ),
                        ],
                      ),
                    if (_dataLoadError.isNotEmpty)
                      Text(
                        'Data Load Error: $_dataLoadError',
                        style: const TextStyle(color: Colors.red),
                      ),
                    // Message and button if profile is incomplete (optional)
                    if (!_isProfileComplete && !_isLoadingData) // Show only if not loading data and profile is genuinely incomplete
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          children: [
                            Text(
                              'Consider completing your profile for a more personalized experience.',
                              style: currentTheme.textTheme.bodyMedium?.copyWith(color: Colors.blueGrey),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () {
                                // Navigate to CompleteProfileScreen
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CompleteProfileScreen(
                                      userId: _userId!, // Pass current user ID
                                      email: _auth.currentUser?.email ?? '', // Pass current email
                                      role: 'doctor', // Role is doctor
                                    ),
                                  ),
                                ).then((_) => _initializeFirebaseAndFetchDoctorData()); // Refresh on return
                              },
                              icon: const Icon(Icons.assignment_ind),
                              label: const Text('Complete My Profile'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.lightBlue, // Different color for optional action
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Buttons are now only disabled by data loading status
            ElevatedButton.icon(
              onPressed: areButtonsDisabledByData ? null : () { 
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LanguageVoiceInputScreen()),
                );
              },
              icon: const Icon(Icons.mic, size: 30),
              label: const Text(
                'Start New Consultation',
                style: TextStyle(fontSize: 20),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, // Specific color for this action
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
              onPressed: areButtonsDisabledByData ? null : () { 
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ViewOpdReportScreen()), // Correct navigation
                );
              },
              icon: const Icon(Icons.history, size: 30),
              label: const Text(
                'View Past OPD Reports',
                style: TextStyle(fontSize: 20),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, // Specific color for this action
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
