enum TransactionType { buy, sell }

class VirtualTransaction {
  const VirtualTransaction({
    required this.id,
    required this.cardId,
    required this.amount,
    required this.type,
    required this.createdAt,
    this.notes,
    this.customerName,
  });

  final String id;
  final String cardId;
  final double amount;
  final TransactionType type;
  final DateTime createdAt;
  final String? notes;
  final String? customerName;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'card_id': cardId,
      'amount': amount,
      'type': type.name,
      'created_at': createdAt.toIso8601String(),
      'notes': notes,
      'customer_name': customerName,
    };
  }

  factory VirtualTransaction.fromMap(Map<String, dynamic> map) {
    final typeName = map['type']?.toString() ?? '';

    return VirtualTransaction(
      id: map['id']?.toString() ?? '',
      cardId: map['card_id']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      type: TransactionType.values.firstWhere(
        (item) => item.name == typeName,
        orElse: () => TransactionType.buy,
      ),
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      notes: map['notes']?.toString(),
      customerName: map['customer_name']?.toString(),
    );
  }

  @override
  String toString() {
    return 'VirtualTransaction(id: $id, cardId: $cardId, amount: $amount, type: $type)';
  }
}
