// lib/widgets/editable_medicine_card.dart
import 'package:flutter/material.dart';
import 'package:medicare/models/medicine_prescription.dart';
import 'package:medicare/services/voice_input_service.dart';

class EditableMedicineCard extends StatefulWidget {
  final MedicinePrescription prescription;
  final VoidCallback onDelete;

  const EditableMedicineCard({
    Key? key,
    required this.prescription,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<EditableMedicineCard> createState() => _EditableMedicineCardState();
}

class _EditableMedicineCardState extends State<EditableMedicineCard> {
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      'name': TextEditingController(text: widget.prescription.name),
      'dosage': TextEditingController(text: widget.prescription.dosage),
      'duration': TextEditingController(text: widget.prescription.duration),
      'frequency': TextEditingController(text: widget.prescription.frequency),
      'timing': TextEditingController(text: widget.prescription.timing),
    };
  }

  @override
  void dispose() {
    _controllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  void _updateField(String field, String value) {
    setState(() {
      _controllers[field]?.text = value;
      widget.prescription.setField(field, value);
    });
  }

  Future<void> _handleVoiceInput(String field) async {
    // Simulate local audio file or implement a mic input and save to filePath
    final filePath = '/path/to/audio.wav'; // Replace with actual path
    final spokenText = await VoiceInputService.transcribeAndTranslate(filePath);
    if (spokenText.isNotEmpty) {
      _updateField(field, spokenText);
    }
  }

  Widget _buildTextField(String field, String label) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controllers[field],
            decoration: InputDecoration(labelText: label),
            onChanged: (val) => _updateField(field, val),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.mic, color: Colors.blue),
          onPressed: () => _handleVoiceInput(field),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildTextField('name', 'Medicine Name'),
            _buildTextField('dosage', 'Dosage (e.g. 650mg)'),
            _buildTextField('duration', 'Duration (e.g. 3 days)'),
            _buildTextField('frequency', 'Frequency (e.g. 2 times a day)'),
            _buildTextField('timing', 'Timing (e.g. after food)'),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: widget.onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
