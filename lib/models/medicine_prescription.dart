// lib/models/medicine_prescription.dart
import 'package:uuid/uuid.dart'; // For generating unique IDs

class MedicinePrescription {
  String id; // Unique ID for this prescription item (e.g., UUID)
  String name;
  String dosage;
  String duration;
  String frequency;
  String timing; // e.g., 'before food', 'after food', 'at night'

  MedicinePrescription({
    String? id, // Make ID optional for constructor, generate if null
    required this.name,
    required this.dosage,
    required this.duration,
    required this.frequency,
    required this.timing,
  }) : this.id = id ?? const Uuid().v4(); // Generate UUID if not provided

  // Factory constructor to create a MedicinePrescription from a JSON map
  factory MedicinePrescription.fromJson(Map<String, dynamic> json) {
    return MedicinePrescription(
      id: json['id'] as String?, // ID might be present if loaded from DB
      name: json['name'] as String? ?? 'N/A',
      dosage: json['dosage'] as String? ?? 'N/A',
      duration: json['duration'] as String? ?? 'N/A',
      frequency: json['frequency'] as String? ?? 'N/A',
      timing: json['timing'] as String? ?? 'N/A',
    );
  }

  // Method to convert a MedicinePrescription object to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'dosage': dosage,
      'duration': duration,
      'frequency': frequency,
      'timing': timing,
    };
  }

  // Factory constructor for an empty/default prescription
  factory MedicinePrescription.empty() {
    return MedicinePrescription(
      name: '',
      dosage: '',
      duration: '',
      frequency: '',
      timing: '',
    );
  }

  // Helper to get field by name for TextEditingController syncing
  String getField(String fieldName) {
    switch (fieldName) {
      case 'name':
        return name;
      case 'dosage':
        return dosage;
      case 'duration':
        return duration;
      case 'frequency':
        return frequency;
      case 'timing':
        return timing;
      default:
        return '';
    }
  }

  // Helper to set field by name for TextEditingController syncing
  void setField(String fieldName, String value) {
    switch (fieldName) {
      case 'name':
        name = value;
        break;
      case 'dosage':
        dosage = value;
        break;
      case 'duration':
        duration = value;
        break;
      case 'frequency':
        frequency = value;
        break;
      case 'timing':
        timing = value;
        break;
    }
  }
}
