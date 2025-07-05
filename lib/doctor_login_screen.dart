// lib/doctor_login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare/doctor_home_screen.dart';
import 'package:medicare/role_selection_screen.dart';
import 'package:medicare/signup_screen.dart';
import 'package:medicare/complete_profile_screen.dart';

// Global variables provided by the Canvas environment
const String __app_id = String.fromEnvironment('APP_ID', defaultValue: 'default-app-id');

class DoctorLoginScreen extends StatefulWidget {
  const DoctorLoginScreen({super.key});

  @override
  State<DoctorLoginScreen> createState() => _DoctorLoginScreenState();
}

class _DoctorLoginScreenState extends State<DoctorLoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = '';
  bool _isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  void _handleSuccessfulAuth(User user) async {
    if (user.email != null && !user.emailVerified) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Email Not Verified'),
            content: Text(
              'Your email (${user.email}) is not verified. Please check your inbox for a verification link.',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Resend Verification'),
                onPressed: () async {
                  await user.sendEmailVerification();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Verification email sent!')),
                    );
                    Navigator.of(context).pop();
                  }
                },
              ),
              TextButton(
                child: const Text('OK'),
                onPressed: () async {
                  await _auth.signOut();
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
      return;
    }

    try {
      final userDoc = await _db
          .collection('artifacts')
          .doc(__app_id)
          .collection('users')
          .doc(user.uid)
          .get();

      if (mounted) {
        if (userDoc.exists && userDoc.data() != null && userDoc.data()!['name'] != null) {
          final String doctorName = userDoc.data()!['name'] as String;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => DoctorHomeScreen(doctorName: doctorName)),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => CompleteProfileScreen(userId: user.uid, email: user.email, role: 'doctor')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error checking user profile: $e';
      });
      print('Error checking user profile after login: $e');
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CompleteProfileScreen(userId: user.uid, email: user.email, role: 'doctor')),
        );
      }
    }
  }

  Future<void> _loginDoctor() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      _handleSuccessfulAuth(userCredential.user!);
      print('Doctor logged in successfully with email!');
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed. Please check your credentials.';
      if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password provided.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid.';
      } else if (e.code == 'user-disabled') {
        message = 'This account has been disabled.';
      }
      setState(() {
        _errorMessage = message;
      });
      print('Firebase Auth Error (Login): ${e.code} - ${e.message}');
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
      });
      print('Unexpected Error (Login): $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        final userId = userCredential.user!.uid;
        final userDocRef = _db
            .collection('artifacts')
            .doc(__app_id)
            .collection('users')
            .doc(userId);

        final userDoc = await userDocRef.get();

        if (!userDoc.exists) {
          await userDocRef.set({
            'name': googleUser.displayName ?? userCredential.user!.email ?? 'Doctor',
            'email': googleUser.email,
            'role': 'doctor',
            'receivePdfPermission': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('New doctor profile created via Google Sign-In.');
        }

        _handleSuccessfulAuth(userCredential.user!);
        print('Doctor logged in successfully with Google!');
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = 'Google Sign-In failed: ${e.message}';
      });
      print('Firebase Auth Error (Google Sign-In): ${e.code} - ${e.message}');
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred during Google Sign-In: $e';
      });
      print('Unexpected Error (Google Sign-In): $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Login'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor, // Use theme's app bar color
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Use theme's background color
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.local_hospital,
                size: 100,
                color: Theme.of(context).primaryColor, // Use theme's primary color
              ),
              const SizedBox(height: 30),
              Text(
                'Doctor Access',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Sign in to manage consultations.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

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

              // Email Field
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'Enter your email',
                  prefixIcon: Icon(Icons.email, color: Theme.of(context).inputDecorationTheme.prefixIconColor), // Use theme's prefixIconColor
                  border: Theme.of(context).inputDecorationTheme.border, // Use theme's input decoration
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
                  hintText: 'Enter your password',
                  prefixIcon: Icon(Icons.lock, color: Theme.of(context).inputDecorationTheme.prefixIconColor), // Use theme's prefixIconColor
                  border: Theme.of(context).inputDecorationTheme.border, // Use theme's input decoration
                  enabledBorder: Theme.of(context).inputDecorationTheme.enabledBorder,
                  focusedBorder: Theme.of(context).inputDecorationTheme.focusedBorder,
                  filled: Theme.of(context).inputDecorationTheme.filled,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  labelStyle: Theme.of(context).inputDecorationTheme.labelStyle,
                  hintStyle: Theme.of(context).inputDecorationTheme.hintStyle,
                ),
              ),
              const SizedBox(height: 40),

              // Login Button
              _isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        ElevatedButton(
                          onPressed: _loginDoctor,
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
                            'Login',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Google Sign-In Button (Neutral Color)
                        ElevatedButton.icon(
                          onPressed: _signInWithGoogle,
                          icon: Image.network(
                            'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/2048px-Google_%22G%22_logo.svg.png',
                            height: 24.0,
                            width: 24.0,
                            errorBuilder: (context, error, stackTrace) => Icon(Icons.login, color: Theme.of(context).iconTheme.color), // Fallback, use theme icon color
                          ),
                          label: Text(
                            'Sign in with Google',
                            style: Theme.of(context).textTheme.bodyLarge, // Use theme's bodyLarge text style
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).cardColor, // Use card color for neutral background
                            foregroundColor: Theme.of(context).textTheme.bodyLarge?.color, // Text color from theme
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                              side: BorderSide(color: Theme.of(context).dividerColor), // Subtle border
                            ),
                            elevation: 2, // Less elevation than primary buttons
                            minimumSize: Size(MediaQuery.of(context).size.width * 0.8, 60),
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Link to Sign Up
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SignupScreen(role: 'doctor')),
                            );
                          },
                          child: Text(
                            'Don\'t have an account? Create one',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).textButtonTheme.style?.foregroundColor?.resolve(MaterialState.values.toSet()),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
