enum CardStatus { unused, used, archived }

class VirtualCard {
  final String id;
  final String barcode;
  final double value;
  final String cardType;
  final String visibilityScope;
  final double issueCost;
  final DateTime createdAt;
  final String? ownerId;
  final String? ownerUsername;
  final String? issuedById;
  final String? issuedByUsername;
  final String? redeemedById;
  final List<String> allowedUserIds;
  final List<String> allowedUsernames;
  final String? customerName;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final Map<String, dynamic> details;
  final DateTime? lastResoldAt;
  final int useCount;
  final int resaleCount;
  final double totalRedeemedValue;
  CardStatus status;
  DateTime? usedAt;
  String? usedBy;
  double? soldPrice;

  VirtualCard({
    required this.id,
    required this.barcode,
    required this.value,
    this.cardType = 'standard',
    this.visibilityScope = 'general',
    this.issueCost = 0,
    required this.createdAt,
    this.ownerId,
    this.ownerUsername,
    this.issuedById,
    this.issuedByUsername,
    this.redeemedById,
    this.allowedUserIds = const [],
    this.allowedUsernames = const [],
    this.customerName,
    this.validFrom,
    this.validUntil,
    this.details = const {},
    this.lastResoldAt,
    this.useCount = 0,
    this.resaleCount = 0,
    this.totalRedeemedValue = 0,
    this.status = CardStatus.unused,
    this.usedAt,
    this.usedBy,
    this.soldPrice,
  });

  bool get isSingleUse => cardType == 'single_use';
  bool get isDelivery => cardType == 'delivery';
  bool get isAppointment => cardType == 'appointment';
  bool get isQueueTicket => cardType == 'queue';
  bool get isPrivate => visibilityScope == 'restricted';
  String? get title => details['title']?.toString();
  String? get description => details['description']?.toString();
  String? get location => details['location']?.toString();
  DateTime? get appointmentStartsAt =>
      DateTime.tryParse(details['startsAt']?.toString() ?? '');
  DateTime? get appointmentEndsAt =>
      DateTime.tryParse(details['endsAt']?.toString() ?? '');

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'barcode': barcode,
      'value': value,
      'card_type': cardType,
      'visibility_scope': visibilityScope,
      'issue_cost': issueCost,
      'created_at': createdAt.toIso8601String(),
      'owner_id': ownerId,
      'owner_username': ownerUsername,
      'issued_by_id': issuedById,
      'issued_by_username': issuedByUsername,
      'redeemed_by_id': redeemedById,
      'allowed_user_ids': allowedUserIds,
      'allowed_usernames': allowedUsernames,
      'customer_name': customerName,
      'valid_from': validFrom?.toIso8601String(),
      'valid_until': validUntil?.toIso8601String(),
      'details': details,
      'last_resold_at': lastResoldAt?.toIso8601String(),
      'use_count': useCount,
      'resale_count': resaleCount,
      'total_redeemed_value': totalRedeemedValue,
      'status': status.toString().split('.').last,
      'used_at': usedAt?.toIso8601String(),
      'used_by': usedBy,
      'sold_price': soldPrice,
    };
  }

  factory VirtualCard.fromMap(Map<String, dynamic> map) {
    final createdAtValue =
        map['createdAt'] ?? map['issuedAt'] ?? map['created_at'];
    final usedAtValue = map['usedAt'] ?? map['redeemedAt'] ?? map['used_at'];
    return VirtualCard(
      id: map['id']?.toString() ?? '',
      barcode: map['barcode']?.toString() ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0,
      cardType:
          map['cardType']?.toString() ??
          map['card_type']?.toString() ??
          'standard',
      visibilityScope:
          map['visibilityScope']?.toString() ??
          map['visibility_scope']?.toString() ??
          'general',
      issueCost:
          (map['issueCost'] as num?)?.toDouble() ??
          (map['issue_cost'] as num?)?.toDouble() ??
          0,
      ownerId: (map['ownerId'] ?? map['owner_id'])?.toString(),
      ownerUsername: (map['ownerUsername'] ?? map['owner_username'])
          ?.toString(),
      issuedById: (map['issuedById'] ?? map['issued_by_id'])?.toString(),
      issuedByUsername: (map['issuedByUsername'] ?? map['issued_by_username'])
          ?.toString(),
      redeemedById: (map['redeemedById'] ?? map['redeemed_by_id'])?.toString(),
      allowedUserIds: List<String>.from(
        ((map['allowedUserIds'] ?? map['allowed_user_ids']) as List? ??
                const [])
            .map((item) => item.toString()),
      ),
      allowedUsernames: List<String>.from(
        ((map['allowedUsernames'] ?? map['allowed_usernames']) as List? ??
                const [])
            .map((item) => item.toString()),
      ),
      customerName: (map['customerName'] ?? map['customer_name'])?.toString(),
      validFrom: (map['validFrom'] ?? map['valid_from']) == null
          ? null
          : DateTime.tryParse(
              (map['validFrom'] ?? map['valid_from']).toString(),
            ),
      validUntil: (map['validUntil'] ?? map['valid_until']) == null
          ? null
          : DateTime.tryParse(
              (map['validUntil'] ?? map['valid_until']).toString(),
            ),
      details: Map<String, dynamic>.from(
        (map['details'] as Map?) ?? const <String, dynamic>{},
      ),
      createdAt:
          DateTime.tryParse(createdAtValue?.toString() ?? '') ?? DateTime.now(),
      lastResoldAt: (map['lastResoldAt'] ?? map['last_resold_at']) == null
          ? null
          : DateTime.tryParse(
              (map['lastResoldAt'] ?? map['last_resold_at']).toString(),
            ),
      useCount: ((map['useCount'] ?? map['use_count']) as num?)?.toInt() ?? 0,
      resaleCount:
          ((map['resaleCount'] ?? map['resale_count']) as num?)?.toInt() ?? 0,
      totalRedeemedValue:
          ((map['totalRedeemedValue'] ?? map['total_redeemed_value']) as num?)
              ?.toDouble() ??
          0,
      status: CardStatus.values.firstWhere(
        (e) => e.toString().split('.').last == map['status']?.toString(),
        orElse: () => CardStatus.unused,
      ),
      usedAt: usedAtValue == null
          ? null
          : DateTime.tryParse(usedAtValue.toString()),
      usedBy: (map['usedBy'] ?? map['redeemedByUsername'] ?? map['used_by'])
          ?.toString(),
      soldPrice: ((map['soldPrice'] ?? map['sold_price']) as num?)?.toDouble(),
    );
  }

  VirtualCard copyWith({
    String? id,
    String? barcode,
    double? value,
    String? cardType,
    String? visibilityScope,
    double? issueCost,
    DateTime? createdAt,
    String? ownerId,
    String? ownerUsername,
    String? issuedById,
    String? issuedByUsername,
    String? redeemedById,
    List<String>? allowedUserIds,
    List<String>? allowedUsernames,
    String? customerName,
    DateTime? validFrom,
    DateTime? validUntil,
    Map<String, dynamic>? details,
    DateTime? lastResoldAt,
    int? useCount,
    int? resaleCount,
    double? totalRedeemedValue,
    CardStatus? status,
    DateTime? usedAt,
    String? usedBy,
    double? soldPrice,
  }) {
    return VirtualCard(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      value: value ?? this.value,
      cardType: cardType ?? this.cardType,
      visibilityScope: visibilityScope ?? this.visibilityScope,
      issueCost: issueCost ?? this.issueCost,
      createdAt: createdAt ?? this.createdAt,
      ownerId: ownerId ?? this.ownerId,
      ownerUsername: ownerUsername ?? this.ownerUsername,
      issuedById: issuedById ?? this.issuedById,
      issuedByUsername: issuedByUsername ?? this.issuedByUsername,
      redeemedById: redeemedById ?? this.redeemedById,
      allowedUserIds: allowedUserIds ?? this.allowedUserIds,
      allowedUsernames: allowedUsernames ?? this.allowedUsernames,
      customerName: customerName ?? this.customerName,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      details: details ?? this.details,
      lastResoldAt: lastResoldAt ?? this.lastResoldAt,
      useCount: useCount ?? this.useCount,
      resaleCount: resaleCount ?? this.resaleCount,
      totalRedeemedValue: totalRedeemedValue ?? this.totalRedeemedValue,
      status: status ?? this.status,
      usedAt: usedAt ?? this.usedAt,
      usedBy: usedBy ?? this.usedBy,
      soldPrice: soldPrice ?? this.soldPrice,
    );
  }

  @override
  String toString() {
    return 'VirtualCard(id: $id, barcode: $barcode, value: $value, '
        'cardType: $cardType, visibilityScope: $visibilityScope, status: $status)';
  }
}
