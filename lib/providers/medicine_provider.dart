class MedicinePrescription {
  final String name;
  final String strength;
  final String form;
  String frequency;
  String duration;

  MedicinePrescription({
    required this.name,
    required this.strength,
    required this.form,
    this.frequency = '',
    this.duration = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'strength': strength,
      'form': form,
      'frequency': frequency,
      'duration': duration,
    };
  }

  factory MedicinePrescription.fromJson(Map<String, dynamic> json) {
    return MedicinePrescription(
      name: json['name'],
      strength: json['strength'],
      form: json['form'],
      frequency: json['frequency'] ?? '',
      duration: json['duration'] ?? '',
    );
  }
}
