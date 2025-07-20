// lib/screens/add_medicine_from_search_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medicare/models/medicine_prescription.dart';

class AddMedicineFromSearchScreen extends StatefulWidget {
  const AddMedicineFromSearchScreen({super.key});

  @override
  State<AddMedicineFromSearchScreen> createState() => _AddMedicineFromSearchScreenState();
}

class _AddMedicineFromSearchScreenState extends State<AddMedicineFromSearchScreen> {
  List<dynamic> allMedicines = [];
  List<dynamic> filteredMedicines = [];
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadMedicines();
  }

  Future<void> loadMedicines() async {
    final String jsonString = await rootBundle.loadString('assets/medicine.json');
    final List<dynamic> jsonList = json.decode(jsonString);
    setState(() {
      allMedicines = jsonList;
      filteredMedicines = jsonList;
    });
  }

  void filterMedicines(String query) {
    query = query.toLowerCase();
    setState(() {
      filteredMedicines = allMedicines.where((med) {
        return (med['name'] ?? '').toString().toLowerCase().contains(query);
      }).toList();
    });
  }

  void selectMedicine(Map<String, dynamic> medicine) {
    final prescription = MedicinePrescription(
      name: medicine['name'] ?? '',
      dosage: medicine['strength'] ?? '1 Tablet',
      duration: '5 days',
      frequency: 'Twice a day',
      timing: 'After food',
    );
    Navigator.pop(context, prescription);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search Medicine')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchController,
              onChanged: filterMedicines,
              decoration: InputDecoration(
                hintText: 'Search by medicine name',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredMedicines.length,
              itemBuilder: (context, index) {
                final medicine = filteredMedicines[index];
                return ListTile(
                  title: Text(medicine['name'] ?? ''),
                  subtitle: Text(medicine['strength'] ?? ''),
                  onTap: () => selectMedicine(medicine),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
