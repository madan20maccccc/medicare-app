// lib/services/fhir_serializer.dart
import 'package:medicare/models/medicine_prescription.dart'; // Assuming this model exists
import 'package:intl/intl.dart'; // For date formatting
// If you want to use data from DataLoader for mapping, you might need to
// pass it to the FhirSerializer or make FhirSerializer a ChangeNotifier
// and consume DataLoader within it, or a static mapping accessible globally.
// For simplicity in this example, we'll use a mock map.
// import 'package:medicare/services/data_loader.dart';

class FhirSerializer {
  /// Converts a MedicinePrescription object into a simplified FHIR MedicationRequest JSON.
  /// This is a basic representation and would need to be expanded for full FHIR compliance.
  static Map<String, dynamic> createMedicationRequestFhir(
    MedicinePrescription medicine,
    String patientId,
    String practitionerId, // Assuming you have a way to get the doctor's FHIR ID
    DateTime encounterDateTime, // The date/time of the consultation
  ) {
    // Attempt to get SNOMED-CT code for the medication name
    final snomedMedicationConcept = _getSnomedConcept(medicine.name, 'medication');

    // A simplified representation of a FHIR MedicationRequest resource
    return {
      "resourceType": "MedicationRequest",
      "id": medicine.id, // Use the medicine's ID as the resource ID
      "status": "active", // Or 'completed', 'stopped', etc. based on context
      "intent": "order",
      "medicationCodeableConcept": {
        "coding": [
          {
            // Use the SNOMED-CT code if found, otherwise provide the display text
            "system": snomedMedicationConcept['system'],
            "code": snomedMedicationConcept['code'],
            "display": snomedMedicationConcept['display'],
          }
        ],
        "text": medicine.name,
      },
      "subject": {
        "reference": "Patient/$patientId", // Reference to the patient resource
        "display": "Patient ID: $patientId", // A human-readable identifier
      },
      "requester": {
        "reference": "Practitioner/$practitionerId", // Reference to the practitioner resource
      },
      "encounter": {
        // In a real scenario, this would link to a specific Encounter resource ID
        "reference": "Encounter/consultation-${DateFormat('yyyyMMdd-HHmmss').format(encounterDateTime)}",
      },
      "authoredOn": DateFormat('yyyy-MM-ddTHH:mm:ssZ').format(encounterDateTime.toUtc()),
      "extension": [ // Using an extension for duration as a simplified example
        {
          "url": "http://example.org/fhir/StructureDefinition/medicationrequest-duration",
          "valueDuration": {
            "value": double.tryParse(medicine.duration) ?? 0.0,
            "unit": medicine.durationUnit ?? "days",
            "system": "http://unitsofmeasure.org",
            "code": "d" // 'd' for days from UCUM
          }
        }
      ],
      "dosageInstruction": [
        {
          "text": "${medicine.dosage}, ${medicine.frequency}, ${medicine.timing}, for ${medicine.duration} ${medicine.durationUnit ?? 'days'}",
          "timing": {
            "repeat": {
              "frequency": _mapFrequencyToFhir(medicine.frequency),
              "period": 1, // Example period
              "periodUnit": "d", // Example unit (days)
            },
          },
          "route": {
            "coding": [
              // Example: SNOMED-CT code for 'Oral route'
              {"system": "http://snomed.info/sct", "code": "26643006", "display": "Oral route"}
            ]
          },
          "doseAndRate": [
            {
              "type": {
                "coding": [
                  {"system": "http://terminology.hl7.org/CodeSystem/dose-rate-type", "code": "ordered"}
                ]
              },
              "doseQuantity": {
                "value": double.tryParse(medicine.dosage.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0,
                "unit": medicine.dosage.replaceAll(RegExp(r'[0-9.]'), '').trim(),
              }
            }
          ]
        }
      ],
    };
  }

  /// Converts chief complaint or summary text into a simplified FHIR Observation JSON.
  /// This can be used for observations like "Chief Complaint" or "Clinical Summary".
  static Map<String, dynamic> createObservationFhir(
    String patientId,
    String practitionerId,
    String codeDisplay, // e.g., "Chief Complaint", "Clinical Summary"
    String value, // The actual complaint/summary text
    DateTime effectiveDateTime,
  ) {
    // Attempt to get SNOMED-CT code for the observation type
    final snomedObservationTypeConcept = _getSnomedConcept(codeDisplay, 'observation_type');

    return {
      "resourceType": "Observation",
      "id": "obs-${DateTime.now().millisecondsSinceEpoch}", // Unique ID for this observation
      "status": "final",
      "code": {
        "coding": [
          {
            "system": snomedObservationTypeConcept['system'],
            "code": snomedObservationTypeConcept['code'],
            "display": snomedObservationTypeConcept['display'],
          }
        ],
        "text": codeDisplay,
      },
      "subject": {
        "reference": "Patient/$patientId",
        "display": "Patient ID: $patientId",
      },
      "performer": [
        {
          "reference": "Practitioner/$practitionerId",
        }
      ],
      "effectiveDateTime": DateFormat('yyyy-MM-ddTHH:mm:ssZ').format(effectiveDateTime.toUtc()),
      "valueString": value, // The observation value as a string
    };
  }

  /// Helper to map common frequency strings to FHIR timing frequency.
  static int? _mapFrequencyToFhir(String frequency) {
    switch (frequency.toLowerCase()) {
      case 'once a day':
      case 'od':
        return 1;
      case 'twice a day':
      case 'bd':
        return 2;
      case 'thrice a day':
      case 'tds':
        return 3;
      case 'four times a day':
      case 'qid':
        return 4;
      case 'hourly':
        return 24;
      case 'every 4 hours':
        return 6;
      case 'every 6 hours':
        return 4;
      case 'every 8 hours':
        return 3;
      default:
        return null;
    }
  }

  static Map<String, dynamic> createPatientFhir(String patientId, String name, String gender, int age, String contact) {
    return {
      "resourceType": "Patient",
      "id": patientId,
      "name": [{"use": "official", "text": name}],
      "gender": gender.toLowerCase(),
      "birthDate": DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(Duration(days: age * 365))),
      "telecom": [
        {"system": "phone", "value": contact, "use": "mobile"}
      ],
    };
  }

  /// CONCEPTUAL: This function simulates connecting to a SNOMED-CT terminology service
  /// or a local mapping database to get the official SNOMED-CT code for a given term.
  ///
  /// For demonstration, it returns a placeholder based on simple string matching.
  /// In a real application, you would:
  /// 1. Query a SNOMED-CT API (e.g., SNOMED International's SNOMED CT Browser API, or a FHIR terminology service).
  /// 2. Use a pre-built local mapping table (e.g., from your DataLoader if it contained SNOMED mappings
  ///    alongside medicine/symptom names).
  static Map<String, String> _getSnomedConcept(String term, String type) {
    // This is a highly simplified mock-up for demonstration purposes.
    // In a production environment, this would involve a robust lookup mechanism.
    final String lowerCaseTerm = term.toLowerCase();
    final String snomedSystem = "http://snomed.info/sct"; // Official SNOMED CT URI

    // --- Mock Mapping for Medications ---
    if (type == 'medication') {
      if (lowerCaseTerm.contains('paracetamol')) {
        return {'system': snomedSystem, 'code': '387226002', 'display': 'Paracetamol (substance)'};
      } else if (lowerCaseTerm.contains('amoxicillin')) {
        return {'system': snomedSystem, 'code': '372583008', 'display': 'Amoxicillin (substance)'};
      } else if (lowerCaseTerm.contains('ibuprofen')) {
        return {'system': snomedSystem, 'code': '387114008', 'display': 'Ibuprofen (substance)'};
      }
      // Add more specific medication mappings
    }
    // --- Mock Mapping for Observation Types / Clinical Findings ---
    else if (type == 'observation_type') {
      if (lowerCaseTerm.contains('chief complaint')) {
        return {'system': "http://loinc.org", 'code': '8661-1', 'display': 'Chief complaint'}; // LOINC for Chief Complaint
      } else if (lowerCaseTerm.contains('clinical summary')) {
        return {'system': snomedSystem, 'code': '408108003', 'display': 'Clinical finding (finding)'};
      } else if (lowerCaseTerm.contains('fever')) {
        return {'system': snomedSystem, 'code': '386661006', 'display': 'Fever (finding)'};
      } else if (lowerCaseTerm.contains('cough')) {
        return {'system': snomedSystem, 'code': '49727002', 'display': 'Cough (finding)'};
      }
      // Add more specific symptom/observation mappings.
      // You could potentially use the 'symptoms' data loaded by DataLoader here.
    }
    // --- Default / Fallback ---
    return {
      'system': snomedSystem,
      'code': 'NOT_CODED', // Indicate that no specific SNOMED code was found
      'display': term, // Fallback to the original term
    };
  }
}