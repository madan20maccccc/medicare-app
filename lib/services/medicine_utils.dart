import '../models/medicine.dart';
import '../models/medicine_prescription.dart';

class MedicineUtils {
  // Convert a found medicine into a pre-filled prescription item
  static MedicinePrescription toPrescription(Medicine med) {
    return MedicinePrescription(
      name: med.name,
      dosage: med.strength.isNotEmpty ? med.strength : 'N/A',
      duration: '5 days', // default
      frequency: 'Twice a day', // default
      timing: med.form.toLowerCase().contains('tablet') ? 'After food' : 'Before food',
    );
  }
}
