// lib/services/medicine_extraction_service.dart
import 'package:medicare/models/medicine_prescription.dart';

class MedicineExtractionService {
  static List<MedicinePrescription> extractFromSummary(String summary) {
    final List<MedicinePrescription> extracted = [];

    // Lowercase for easier parsing
    final text = summary.toLowerCase();

    // Split by sentence or phrases (basic)
    final phrases = text.split(RegExp(r'[.;\n]'));

    for (final phrase in phrases) {
      final trimmed = phrase.trim();
      if (trimmed.isEmpty) continue;

      final name = _extractName(trimmed);
      final dosage = _extractDosage(trimmed);
      final frequency = _extractFrequency(trimmed);
      final duration = _extractDuration(trimmed);
      final timing = _extractTiming(trimmed);

      // If we detect at least a name or dosage, consider it valid
      if (name.isNotEmpty || dosage.isNotEmpty) {
        extracted.add(MedicinePrescription(
          name: name,
          dosage: dosage,
          duration: duration,
          frequency: frequency,
          timing: timing,
        ));
      }
    }

    return extracted;
  }

  static String _extractName(String phrase) {
    final pattern = RegExp(r'\b[A-Za-z][a-z]+\s?\d*(mg|ml)?\b');
    final match = pattern.firstMatch(phrase);
    return match?.group(0)?.toUpperCase() ?? '';
  }

  static String _extractDosage(String phrase) {
    final pattern = RegExp(r'\b\d+\s?(mg|ml|mcg|g|drops|tablet[s]?|capsule[s]?)\b');
    final match = pattern.firstMatch(phrase);
    return match?.group(0) ?? '';
  }

  static String _extractFrequency(String phrase) {
    final freqKeywords = ['once', 'twice', 'thrice', 'daily', 'every morning', 'every night', 'bid', 'tid', 'qhs'];
    return freqKeywords.firstWhere((k) => phrase.contains(k), orElse: () => '');
  }

  static String _extractDuration(String phrase) {
    final pattern = RegExp(r'\b\d+\s?(day|days|week|weeks|month|months)\b');
    final match = pattern.firstMatch(phrase);
    return match?.group(0) ?? '';
  }

  static String _extractTiming(String phrase) {
    final timingKeywords = ['before food', 'after food', 'with food', 'at night', 'in morning', 'empty stomach'];
    return timingKeywords.firstWhere((k) => phrase.contains(k), orElse: () => '');
  }
}
