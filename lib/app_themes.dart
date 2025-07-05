import 'package:flutter/material.dart';

class AppThemes {
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: Colors.blueAccent,
    hintColor: Colors.cyan,
    scaffoldBackgroundColor: Colors.blueGrey[50],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blueAccent,
      foregroundColor: Colors.white,
      elevation: 4,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        elevation: 5,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.blueAccent[700],
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.blueGrey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.blueGrey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      labelStyle: TextStyle(color: Colors.blueGrey[700]),
      hintStyle: TextStyle(color: Colors.blueGrey[400]),
      prefixIconColor: Colors.blueAccent,
    ),
    iconTheme: IconThemeData(color: Colors.blueGrey[700]),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: Colors.blueGrey[800], fontSize: 16),
      bodyMedium: TextStyle(color: Colors.blueGrey[700], fontSize: 14),
      bodySmall: TextStyle(color: Colors.blueGrey[600], fontSize: 12),
      titleLarge: TextStyle(
        color: Colors.blueGrey[900],
        fontWeight: FontWeight.bold,
        fontSize: 28,
      ),
      titleMedium: TextStyle(
        color: Colors.blueGrey[800],
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
    ),
    fontFamily: 'Inter',
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: Colors.indigoAccent,
    hintColor: Colors.tealAccent,
    scaffoldBackgroundColor: Colors.grey[900],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey[850],
      foregroundColor: Colors.white,
      elevation: 4,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.grey[800],
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.indigoAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        elevation: 5,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.indigoAccent[100],
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.indigoAccent, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey[850],
      labelStyle: TextStyle(color: Colors.grey[300]),
      hintStyle: TextStyle(color: Colors.grey[500]),
      prefixIconColor: Colors.indigoAccent,
    ),
    iconTheme: IconThemeData(color: Colors.grey[300]),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: Colors.grey[100], fontSize: 16),
      bodyMedium: TextStyle(color: Colors.grey[200], fontSize: 14),
      bodySmall: TextStyle(color: Colors.grey[400], fontSize: 12),
      titleLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 28,
      ),
      titleMedium: TextStyle(
        color: Colors.grey[100],
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
    ),
    fontFamily: 'Inter',
  );
}
