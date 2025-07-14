// lib/services/data_loader.dart
import 'package:flutter/foundation.dart'; // For ChangeNotifier
import 'package:flutter/services.dart' show rootBundle; // For loading assets
import 'package:csv/csv.dart'; // For CSV parsing

class DataLoader extends ChangeNotifier {
  bool _isLoaded = false;
  String? _loadError;
  final Map<String, List<Map<String, dynamic>>> _loadedData = {};

  // Public getters for state
  bool get isLoaded => _isLoaded;
  String? get loadError => _loadError;
  bool get hasAttemptedLoad => _isLoaded || _loadError != null;

  // Getter for medicine names specifically
  List<String> get medicineNames {
    if (_loadedData.containsKey('medicines')) {
      return _loadedData['medicines']!.map((e) => e['name'].toString()).toList();
    }
    return [];
  }

  DataLoader() {
    // Automatically attempt to load data when the DataLoader is created
    loadData();
  }

  // Method to get loaded data for a specific file
  List<Map<String, dynamic>>? getLoadedData(String fileName) {
    return _loadedData[fileName];
  }

  // Main method to load all necessary CSV data
  Future<void> loadData() async {
    if (_isLoaded || _loadError != null) {
      // Avoid reloading if already loaded or failed
      print('DataLoader: Data already loaded or failed. Not reloading.');
      return;
    }

    print('DataLoader: Starting data loading...');
    _isLoaded = false;
    _loadError = null;
    notifyListeners(); // Notify listeners that loading has started

    try {
      await _loadCsvFile('medicines');
      await _loadCsvFile('symptoms');
      
      _isLoaded = true;
      _loadError = null;
      print('DataLoader: All data loaded successfully.');
    } catch (e) {
      _isLoaded = false;
      _loadError = 'Failed to load essential data: $e';
      print('DataLoader: Error loading data: $e');
    } finally {
      notifyListeners(); // Notify listeners about the final state (success or failure)
    }
  }

  // Helper method to load a single CSV file
  Future<void> _loadCsvFile(String fileName) async {
    print('DataLoader: Attempting to load $fileName from assets...');
    try {
      final rawCsv = await rootBundle.loadString('assets/$fileName.csv');
      List<List<dynamic>> csvTable = const CsvToListConverter().convert(rawCsv);

      if (csvTable.isNotEmpty) {
        List<String> headers = csvTable[0].map((e) => e.toString()).toList();
        List<Map<String, dynamic>> data = [];

        for (int i = 1; i < csvTable.length; i++) {
          Map<String, dynamic> row = {};
          for (int j = 0; j < headers.length; j++) {
            if (j < csvTable[i].length) { // Ensure index is within bounds
              row[headers[j]] = csvTable[i][j];
            } else {
              row[headers[j]] = null; // Handle missing values gracefully
            }
          }
          data.add(row);
        }
        _loadedData[fileName] = data;
        print('DataLoader: Successfully loaded $fileName. Number of entries: ${data.length}');
      } else {
        throw Exception('CSV file $fileName.csv is empty or malformed.');
      }
    } catch (e) {
      print('DataLoader: WARNING: Document $fileName.csv not found in assets or failed to parse: $e');
      throw Exception('Could not load $fileName.csv from assets. Please ensure it exists and is valid.');
    }
  }

  Future loadCsvData(String s) async {}
}
