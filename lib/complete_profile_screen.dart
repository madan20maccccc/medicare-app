// lib/complete_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare/doctor_home_screen.dart';
import 'package:medicare/patient_home_screen.dart';

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class CompleteProfileScreen extends StatefulWidget {
  final String userId;
  final String? email;
  final String? role; // This role is passed if known from signup/login

  const CompleteProfileScreen({
    super.key,
    required this.userId,
    this.email,
    this.role,
  });

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String? _selectedGender;
  final List<String> _genders = ['Male', 'Female', 'Other'];

  String? _selectedRole; // New state for role selection if not already set
  final List<String> _roles = ['doctor', 'patient'];

  bool _receivePdfPermission = false;
  String _errorMessage = '';
  bool _isLoading = false;
  bool _isFetchingData = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.role; // Initialize with role passed from previous screen
    _fetchExistingProfile();
  }

  Future<void> _fetchExistingProfile() async {
    setState(() {
      _isFetchingData = true;
      _errorMessage = '';
    });

    try {
      final userDoc = await _db
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(widget.userId)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        _nameController.text = userData['name'] as String? ?? '';
        _ageController.text = userData['age']?.toString() ?? '';
        _phoneController.text = userData['phoneNumber'] as String? ?? '';
        _selectedGender = userData['gender'] as String?;
        
        // If role is already in Firestore, use it. Otherwise, keep what was passed or null.
        _selectedRole = userData['role'] as String? ?? _selectedRole; 

        if (_selectedRole == 'patient') {
          _receivePdfPermission = userData['receivePdfPermission'] as bool? ?? false;
        }
      } else {
        // If user doc doesn't exist, try to pre-fill name from email
        if (widget.email != null) {
          _nameController.text = widget.email!.split('@')[0];
        }
      }
    } catch (e) {
      _errorMessage = 'Error loading existing profile data: $e';
      print('Error loading existing profile: $e');
    } finally {
      setState(() {
        _isFetchingData = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_selectedRole == null || _selectedRole!.isEmpty) {
      setState(() {
        _errorMessage = 'Please select your role (Doctor or Patient).';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userDocRef = _db
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(widget.userId);

      await userDocRef.set({
        'name': _nameController.text.trim(),
        'email': widget.email ?? _auth.currentUser?.email,
        'role': _selectedRole, // Save the selected role
        'age': int.tryParse(_ageController.text.trim()),
        'gender': _selectedGender,
        'phoneNumber': _phoneController.text.trim(),
        'receivePdfPermission': _selectedRole == 'patient' ? _receivePdfPermission : false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!')),
        );
        if (_selectedRole == 'doctor') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => DoctorHomeScreen(doctorName: _nameController.text.trim())),
          );
        } else if (_selectedRole == 'patient') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => PatientHomeScreen(patientName: _nameController.text.trim())),
          );
        }
      }
      print('User profile saved/updated successfully!');
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving profile: $e';
      });
      print('Error saving profile: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        backgroundColor: currentTheme.appBarTheme.backgroundColor,
        elevation: currentTheme.appBarTheme.elevation,
      ),
      backgroundColor: currentTheme.scaffoldBackgroundColor,
      body: _isFetchingData
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.account_circle,
                      size: 100,
                      color: currentTheme.primaryColor,
                    ),
                    const SizedBox(height: 30),
                    Text(
                      'Please Complete Your Profile',
                      style: currentTheme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'We need a few more details to set up your account.',
                      style: currentTheme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    if (_errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    TextField(
                      controller: _nameController,
                      keyboardType: TextInputType.name,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'Enter your full name',
                        prefixIcon: Icon(Icons.person, color: currentTheme.inputDecorationTheme.prefixIconColor),
                        border: currentTheme.inputDecorationTheme.border,
                        enabledBorder: currentTheme.inputDecorationTheme.enabledBorder,
                        focusedBorder: currentTheme.inputDecorationTheme.focusedBorder,
                        filled: currentTheme.inputDecorationTheme.filled,
                        fillColor: currentTheme.inputDecorationTheme.fillColor,
                        labelStyle: currentTheme.inputDecorationTheme.labelStyle,
                        hintStyle: currentTheme.inputDecorationTheme.hintStyle,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Role Selection Dropdown - ONLY IF role is not already set
                    if (_selectedRole == null || _selectedRole!.isEmpty)
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: currentTheme.inputDecorationTheme.fillColor,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: currentTheme.dividerColor),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedRole,
                                hint: Text('Select Your Role', style: currentTheme.inputDecorationTheme.hintStyle),
                                icon: Icon(Icons.arrow_drop_down, color: currentTheme.iconTheme.color),
                                isExpanded: true,
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _selectedRole = newValue;
                                  });
                                },
                                items: _roles.map<DropdownMenuItem<String>>((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value == 'doctor' ? 'Doctor' : 'Patient', style: currentTheme.textTheme.bodyMedium),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),

                    TextField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Age',
                        hintText: 'Enter your age',
                        prefixIcon: Icon(Icons.cake, color: currentTheme.inputDecorationTheme.prefixIconColor),
                        border: currentTheme.inputDecorationTheme.border,
                        enabledBorder: currentTheme.inputDecorationTheme.enabledBorder,
                        focusedBorder: currentTheme.inputDecorationTheme.focusedBorder,
                        filled: currentTheme.inputDecorationTheme.filled,
                        fillColor: currentTheme.inputDecorationTheme.fillColor,
                        labelStyle: currentTheme.inputDecorationTheme.labelStyle,
                        hintStyle: currentTheme.inputDecorationTheme.hintStyle,
                      ),
                    ),
                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: currentTheme.inputDecorationTheme.fillColor,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: currentTheme.dividerColor),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedGender,
                          hint: Text('Select Gender', style: currentTheme.inputDecorationTheme.hintStyle),
                          icon: Icon(Icons.arrow_drop_down, color: currentTheme.iconTheme.color),
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedGender = newValue;
                            });
                          },
                          items: _genders.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value, style: currentTheme.textTheme.bodyMedium),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        hintText: 'Enter your phone number',
                        prefixIcon: Icon(Icons.phone, color: currentTheme.inputDecorationTheme.prefixIconColor),
                        border: currentTheme.inputDecorationTheme.border,
                        enabledBorder: currentTheme.inputDecorationTheme.enabledBorder,
                        focusedBorder: currentTheme.inputDecorationTheme.focusedBorder,
                        filled: currentTheme.inputDecorationTheme.filled,
                        fillColor: currentTheme.inputDecorationTheme.fillColor,
                        labelStyle: currentTheme.inputDecorationTheme.labelStyle,
                        hintStyle: currentTheme.inputDecorationTheme.hintStyle,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // OPD PDF Permission Checkbox (only if patient role is selected or already set)
                    if (_selectedRole == 'patient')
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 20),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _receivePdfPermission,
                              onChanged: (bool? value) {
                                setState(() {
                                  _receivePdfPermission = value ?? false;
                                });
                              },
                              activeColor: currentTheme.primaryColor,
                            ),
                            Expanded(
                              child: Text(
                                'Allow sending OPD PDFs to my registered email/phone (one-time permission)',
                                style: currentTheme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    _isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentTheme.elevatedButtonTheme.style?.backgroundColor?.resolve(MaterialState.values.toSet()) ?? currentTheme.primaryColor,
                              foregroundColor: currentTheme.elevatedButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()) ?? currentTheme.colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 5,
                              minimumSize: Size(MediaQuery.of(context).size.width * 0.8, 60),
                            ),
                            child: const Text(
                              'Save Profile',
                              style: TextStyle(fontSize: 20),
                            ),
                          ),
                  ],
                ),
              ),
            ),
    );
  }
}
