// lib/services/medical_nlp_service.dart
import 'package:collection/collection.dart'; // For more advanced list operations if needed later

/// A conceptual service for performing medical Natural Language Processing (NLP).
/// In a real application, this would integrate with specialized medical NLP APIs
/// (e.g., Google Cloud Healthcare API's NLP features, AWS Comprehend Medical,
/// or custom models hosted on platforms like Hugging Face).
class MedicalNlpService {
  // A simple, mock dictionary of medical terms and their conceptual categories.
  // In reality, these would come from vast, professionally curated medical ontologies
  // or be learned by advanced NLP models.
  static final Map<String, List<String>> _medicalKeywords = {
    'symptom': ['fever', 'cough', 'headache', 'nausea', 'vomiting', 'pain', 'rash', 'fatigue', 'dizziness'],
    'disease': ['hypertension', 'diabetes', 'asthma', 'malaria', 'dengue', 'tuberculosis', 'covid-19', 'flu'],
    'body_part': ['head', 'chest', 'abdomen', 'throat', 'joint', 'lung', 'heart', 'stomach'],
    'medication_class': ['antibiotic', 'analgesic', 'antipyretic', 'antihistamine', 'insulin'],
    // Add more categories and terms as needed
  };

  /// Conceptually analyzes medical text to identify entities and provide context.
  ///
  /// [text] The raw transcribed medical conversation or prescription text.
  ///
  /// Returns a Map containing identified entities and any relevant contextual flags.
  ///
  /// This is a simplified mock. A real implementation would:
  /// - Use advanced NLP techniques (NER, relation extraction, disambiguation).
  /// - Leverage large medical ontologies (SNOMED-CT, RxNorm, ICD-10).
  /// - Integrate with AI models specifically trained on clinical data.
  Map<String, dynamic> analyzeMedicalText(String text) {
    final Map<String, List<String>> identifiedEntities = {
      'symptoms': [],
      'diseases': [],
      'body_parts': [],
      'medication_classes': [],
      'other_medical_terms': [],
    };

    final List<String> words = text.toLowerCase().split(RegExp(r'\W+')).where((s) => s.isNotEmpty).toList();

    for (final word in words) {
      bool found = false;
      _medicalKeywords.forEach((category, keywords) {
        if (keywords.contains(word)) {
          // Add only if not already present to avoid duplicates
          if (category == 'symptom' && !identifiedEntities['symptoms']!.contains(word)) {
            identifiedEntities['symptoms']!.add(word);
          } else if (category == 'disease' && !identifiedEntities['diseases']!.contains(word)) {
            identifiedEntities['diseases']!.add(word);
          } else if (category == 'body_part' && !identifiedEntities['body_parts']!.contains(word)) {
            identifiedEntities['body_parts']!.add(word);
          } else if (category == 'medication_class' && !identifiedEntities['medication_classes']!.contains(word)) {
            identifiedEntities['medication_classes']!.add(word);
          }
          found = true;
        }
      });

      // If a word isn't in our mock categories, but looks like a medical term (e.g., from a medicine list CSV)
      // This part would be more sophisticated in a real system, potentially using a global list of known terms
      // or a more advanced classification model.
      if (!found &&
          word.length > 3 && // Avoid very short words
          !['the', 'and', 'for', 'with', 'patient', 'doctor', 'said', 'has', 'is'].contains(word) && // Common words
          !identifiedEntities['other_medical_terms']!.contains(word)
          ) {
        // This is a very simplistic heuristic for 'other medical terms'
        // A better approach would be to check against a comprehensive medical dictionary or a trained model.
        // For example, if DataLoader exposed a list of all known medicine names (not just names for autocomplete),
        // we could check against that.
        // identifiedEntities['other_medical_terms']!.add(word);
      }
    }

    // Add conceptual context awareness.
    // For example, if "pain" is mentioned near "abdomen", classify as "abdominal pain".
    // This requires more advanced NLP (e.g., dependency parsing, semantic role labeling),
    // which is beyond simple keyword matching. This is a placeholder for the concept.
    String contextualNote = "Basic entity extraction performed.";
    if (identifiedEntities['symptoms']!.contains('pain') && identifiedEntities['body_parts']!.contains('head')) {
      contextualNote = "Identified headache (pain in head).";
    }

    return {
      'entities': identifiedEntities,
      'contextual_note': contextualNote,
      // In a real system, you might have:
      // 'disambiguated_terms': { 'term': 'disambiguated_meaning' },
      // 'relations': [ { 'subject': 'entity1', 'verb': 'rel', 'object': 'entity2' } ],
    };
  }

  /// Conceptually disambiguates similar-sounding medical terms based on context.
  /// This is a highly complex NLP task. This function merely serves as a placeholder
  /// to illustrate where such logic would reside.
  ///
  /// For example, differentiating between "dysphagia" (difficulty swallowing) and "dysphasia" (speech disorder).
  /// Real disambiguation requires advanced machine learning models trained on large medical corpora.
  String disambiguateTerm(String term, String sentenceContext) {
    String lowerCaseTerm = term.toLowerCase();
    String lowerCaseContext = sentenceContext.toLowerCase();

    if (lowerCaseTerm == 'dysphasia' && lowerCaseContext.contains('speech') || lowerCaseContext.contains('language')) {
      return '$term (speech disorder)';
    }
    if (lowerCaseTerm == 'dysphagia' && lowerCaseContext.contains('swallowing') || lowerCaseContext.contains('eating')) {
      return '$term (difficulty swallowing)';
    }
    // Add more complex disambiguation rules here.
    return term; // Return original if no disambiguation applied
  }
}