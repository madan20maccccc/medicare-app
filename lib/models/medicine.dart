class Medicine {
  final String name;
  final String strength;
  final String form;
  final String category;
  final double price;
  final String source;

  Medicine({
    required this.name,
    required this.strength,
    required this.form,
    required this.category,
    required this.price,
    required this.source,
  });

  factory Medicine.fromJson(Map<String, dynamic> json) {
    return Medicine(
      name: json['name'] ?? '',
      strength: json['strength'] ?? '',
      form: json['form'] ?? '',
      category: json['category'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      source: json['source'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'strength': strength,
      'form': form,
      'category': category,
      'price': price,
      'source': source,
    };
  }
}
