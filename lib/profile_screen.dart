// lib/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart'; // Keep if Google Sign-In is used
import 'package:medicare/role_selection_screen.dart';
import 'package:medicare/complete_profile_screen.dart';

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _userName = 'Loading...';
  String _userEmail = 'Loading...';
  String _userRole = 'Loading...';
  String _userAge = 'N/A';
  String _userGender = 'N/A';
  String _userPhone = 'N/A';
  String _userAddress = 'N/A'; // Added address
  String _userChiefComplaint = 'N/A'; // Added chief complaint
  String? _patientFirebaseId; // Store the patient's ID if fetched from public/patients
  bool _receivePdfPermission = false;

  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final User? user = _auth.currentUser;

    if (user == null) {
      setState(() {
        _errorMessage = 'No user logged in.';
        _isLoading = false;
      });
      return;
    }

    try {
      // First, try to fetch from the 'users' collection (where doctors and email/password patients are)
      final userDoc = await _db
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        setState(() {
          _userName = userData['name'] as String? ?? 'N/A';
          _userEmail = userData['email'] as String? ?? user.email ?? 'N/A';
          _userRole = userData['role'] as String? ?? 'N/A';
          _userAge = userData['age']?.toString() ?? 'N/A';
          _userGender = userData['gender'] as String? ?? 'N/A';
          _userPhone = userData['phoneNumber'] as String? ?? 'N/A';
          _userAddress = userData['address'] as String? ?? 'N/A'; // Fetch address
          _userChiefComplaint = userData['chiefComplaint'] as String? ?? 'N/A'; // Fetch chief complaint
          _receivePdfPermission = userData['receivePdfPermission'] as bool? ?? false;
          _isLoading = false;
        });
      } else {
        // If not found in 'users' collection, check the 'public/patients/data' collection
        // This handles patients who filled out the form without a direct user login
        final patientDoc = await _db
            .collection('artifacts')
            .doc(__app_id)
            .collection('public')
            .doc('patients')
            .collection('data')
            .doc(user.uid) // Assuming patientId is their Firebase UID if they signed in anonymously
            .get();

        if (patientDoc.exists && patientDoc.data() != null) {
          final patientData = patientDoc.data()!;
          setState(() {
            _userName = patientData['name'] as String? ?? 'N/A';
            _userEmail = patientData['email'] as String? ?? user.email ?? 'N/A';
            _userRole = 'patient'; // Explicitly set role for patients from this collection
            _userAge = patientData['age']?.toString() ?? 'N/A';
            _userGender = patientData['gender'] as String? ?? 'N/A';
            _userPhone = patientData['contactNumber'] as String? ?? 'N/A'; // Note: 'contactNumber' for patients
            _userAddress = patientData['address'] as String? ?? 'N/A'; // Fetch address
            _userChiefComplaint = patientData['chiefComplaint'] as String? ?? 'N/A'; // Fetch chief complaint
            _receivePdfPermission = patientData['receivePdfPermission'] as bool? ?? false; // Assuming this field exists for patients too
            _patientFirebaseId = patientData['id'] as String?; // Store the patient's UUID
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'User profile not found. Please complete your profile.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching profile: $e';
        _isLoading = false;
      });
      print('Error fetching user profile: $e');
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _auth.signOut();
      // Only attempt Google sign out if they were signed in with Google
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error logging out: $e';
        _isLoading = false;
      });
      print('Error during logout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: Theme.of(context).appBarTheme.elevation,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _isLoading ? null : _logout,
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
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
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.red),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _fetchUserProfile,
                            child: const Text('Retry'),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: _logout,
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Center(
                          child: Icon(
                            _userRole == 'doctor' ? Icons.medical_services : Icons.person_outline,
                            size: 100,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 30),
                        _buildProfileCard(
                          context,
                          title: 'Personal Information',
                          children: [
                            _buildProfileDetail('Name', _userName, Icons.person),
                            _buildProfileDetail('Email', _userEmail, Icons.email),
                            _buildProfileDetail('Role', _userRole.toUpperCase(), Icons.assignment_ind),
                            if (_userRole == 'patient' && _patientFirebaseId != null) // Show patient's UUID
                              _buildProfileDetail('Patient ID', _patientFirebaseId!, Icons.badge),
                            _buildProfileDetail('Age', _userAge, Icons.cake),
                            _buildProfileDetail('Gender', _userGender, Icons.wc),
                            _buildProfileDetail('Phone Number', _userPhone, Icons.phone),
                            _buildProfileDetail('Address', _userAddress, Icons.location_on), // Display address
                            if (_userRole == 'patient') // Only show chief complaint for patients
                              _buildProfileDetail('Chief Complaint', _userChiefComplaint, Icons.sick), // Display chief complaint
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (_userRole == 'patient')
                          _buildProfileCard(
                            context,
                            title: 'Permissions',
                            children: [
                              _buildProfileDetail(
                                'Receive OPD PDFs',
                                _receivePdfPermission ? 'Allowed' : 'Denied',
                                _receivePdfPermission ? Icons.check_circle_outline : Icons.cancel_outlined,
                                valueColor: _receivePdfPermission ? Colors.green : Colors.red,
                              ),
                            ],
                          ),
                        const SizedBox(height: 30),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CompleteProfileScreen(
                                    userId: _auth.currentUser!.uid,
                                    email: _userEmail,
                                    role: _userRole,
                                  ),
                                ),
                              ).then((_) {
                                // Refresh profile data when returning from CompleteProfileScreen
                                _fetchUserProfile();
                              });
                            },
                            icon: const Icon(Icons.edit, size: 24),
                            label: const Text(
                              'Edit Profile',
                              style: TextStyle(fontSize: 18),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).elevatedButtonTheme.style?.backgroundColor?.resolve(MaterialState.values.toSet()),
                              foregroundColor: Theme.of(context).elevatedButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()),
                              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
    );
  }

  Widget _buildProfileCard(BuildContext context, {required String title, required List<Widget> children}) {
    return Card(
      elevation: Theme.of(context).cardTheme.elevation,
      shape: Theme.of(context).cardTheme.shape,
      color: Theme.of(context).cardTheme.color,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(height: 25, thickness: 1),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDetail(String label, String value, IconData icon, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Align items to the start of the cross axis
        children: [
          Icon(icon, color: Theme.of(context).iconTheme.color, size: 20),
          const SizedBox(width: 15),
          Expanded( // Ensure the column takes remaining space
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall, // Use bodySmall for label
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: valueColor ?? Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                  softWrap: true, // Allow text to wrap
                  overflow: TextOverflow.visible, // Or .ellipsis if you prefer truncation
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
