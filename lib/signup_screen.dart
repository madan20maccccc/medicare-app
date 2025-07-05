// lib/signup_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare/doctor_home_screen.dart';
import 'package:medicare/patient_home_screen.dart';
import 'package:medicare/role_selection_screen.dart';

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class SignupScreen extends StatefulWidget {
  final String role; // 'doctor' or 'patient'

  const SignupScreen({super.key, required this.role});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String? _selectedGender; // For dropdown
  final List<String> _genders = ['Male', 'Female', 'Other'];

  String _errorMessage = '';
  bool _isLoading = false;
  bool _receivePdfPermission = true; // Default to true for permission

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _registerUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 1. Create user with Email and Password
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 2. Send email verification
      if (userCredential.user != null) {
        await userCredential.user!.sendEmailVerification();
        print('Email verification sent to ${userCredential.user!.email}');
      }

      // 3. Save additional user details to Firestore
      if (userCredential.user != null) {
        final userId = userCredential.user!.uid;
        final userDocRef = _db
            .collection('artifacts')
            .doc(__app_id)
            .collection('users')
            .doc(userId);

        await userDocRef.set({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'role': widget.role,
          'age': int.tryParse(_ageController.text.trim()), // Convert age to int
          'gender': _selectedGender,
          'phoneNumber': _phoneController.text.trim(),
          'receivePdfPermission': widget.role == 'patient' ? _receivePdfPermission : false, // Only for patients
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 4. Navigate to a screen indicating successful signup and pending email verification
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false, // User must verify email
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Verify Your Email'),
                content: Text(
                  'A verification link has been sent to ${_emailController.text.trim()}. '
                  'Please verify your email to log in. You will be logged out now.',
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('OK'),
                    onPressed: () async {
                      await _auth.signOut(); // Log out after showing message
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                          (Route<dynamic> route) => false,
                        );
                      }
                    },
                  ),
                ],
              );
            },
          );
        }
        print('${widget.role} signed up, data saved, and email verification sent!');
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred during registration.';
      if (e.code == 'weak-password') {
        message = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        message = 'An account already exists for that email.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid.';
      }
      setState(() {
        _errorMessage = message;
      });
      print('Firebase Auth Error (Sign Up): ${e.code} - ${e.message}');
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
      });
      print('Unexpected Error (Sign Up): $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.role == 'doctor' ? 'Doctor' : 'Patient'} Sign Up'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: Theme.of(context).appBarTheme.elevation,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
              (Route<dynamic> route) => false,
            );
          },
        ),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                widget.role == 'doctor' ? Icons.person_add : Icons.person_add_alt_1,
                size: 100,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 30),
              Text(
                'Create Your ${widget.role == 'doctor' ? 'Doctor' : 'Patient'} Account',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Error Message
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Name Field
              TextField(
                controller: _nameController,
                keyboardType: TextInputType.name,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'Enter your full name',
                  prefixIcon: Icon(Icons.person, color: Theme.of(context).inputDecorationTheme.prefixIconColor),
                  border: Theme.of(context).inputDecorationTheme.border,
                  enabledBorder: Theme.of(context).inputDecorationTheme.enabledBorder,
                  focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
                  filled: Theme.of(context).inputDecorationTheme.filled,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  labelStyle: Theme.of(context).inputDecorationTheme.labelStyle,
                  hintStyle: Theme.of(context).inputDecorationTheme.hintStyle,
                ),
              ),
              const SizedBox(height: 20),

              // Email Field
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'Enter your email',
                  prefixIcon: Icon(Icons.email, color: Theme.of(context).inputDecorationTheme.prefixIconColor),
                  border: Theme.of(context).inputDecorationTheme.border,
                  enabledBorder: Theme.of(context).inputDecorationTheme.enabledBorder,
                  focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
                  filled: Theme.of(context).inputDecorationTheme.filled,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  labelStyle: Theme.of(context).inputDecorationTheme.labelStyle,
                  hintStyle: Theme.of(context).inputDecorationTheme.hintStyle,
                ),
              ),
              const SizedBox(height: 20),

              // Password Field
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Choose a strong password (min 6 characters)',
                  prefixIcon: Icon(Icons.lock, color: Theme.of(context).inputDecorationTheme.prefixIconColor),
                  border: Theme.of(context).inputDecorationTheme.border,
                  enabledBorder: Theme.of(context).inputDecorationTheme.enabledBorder,
                  focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
                  filled: Theme.of(context).inputDecorationTheme.filled,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  labelStyle: Theme.of(context).inputDecorationTheme.labelStyle,
                  hintStyle: Theme.of(context).inputDecorationTheme.hintStyle,
                ),
              ),
              const SizedBox(height: 20),

              // Age Field
              TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Age',
                  hintText: 'Enter your age',
                  prefixIcon: Icon(Icons.cake, color: Theme.of(context).inputDecorationTheme.prefixIconColor),
                  border: Theme.of(context).inputDecorationTheme.border,
                  enabledBorder: Theme.of(context).inputDecorationTheme.enabledBorder,
                  focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
                  filled: Theme.of(context).inputDecorationTheme.filled,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  labelStyle: Theme.of(context).inputDecorationTheme.labelStyle,
                  hintStyle: Theme.of(context).inputDecorationTheme.hintStyle,
                ),
              ),
              const SizedBox(height: 20),

              // Gender Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).inputDecorationTheme.fillColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedGender,
                    hint: Text('Select Gender', style: Theme.of(context).inputDecorationTheme.hintStyle),
                    icon: Icon(Icons.arrow_drop_down, color: Theme.of(context).iconTheme.color),
                    isExpanded: true,
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedGender = newValue;
                      });
                    },
                    items: _genders.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Phone Number Field
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'Enter your phone number',
                  prefixIcon: Icon(Icons.phone, color: Theme.of(context).inputDecorationTheme.prefixIconColor),
                  border: Theme.of(context).inputDecorationTheme.border,
                  enabledBorder: Theme.of(context).inputDecorationTheme.enabledBorder,
                  focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
                  filled: Theme.of(context).inputDecorationTheme.filled,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  labelStyle: Theme.of(context).inputDecorationTheme.labelStyle,
                  hintStyle: Theme.of(context).inputDecorationTheme.hintStyle,
                ),
              ),
              const SizedBox(height: 20),

              // OPD PDF Permission Checkbox (for Patient only)
              if (widget.role == 'patient')
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
                        activeColor: Theme.of(context).primaryColor,
                      ),
                      Expanded(
                        child: Text(
                          'Allow sending OPD PDFs to my registered email/phone (one-time permission)',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),

              // Register Button
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _registerUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).elevatedButtonTheme.style?.backgroundColor?.resolve(MaterialState.values.toSet()),
                        foregroundColor: Theme.of(context).elevatedButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()),
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 5,
                        minimumSize: Size(MediaQuery.of(context).size.width * 0.8, 60),
                      ),
                      child: const Text(
                        'Register',
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
