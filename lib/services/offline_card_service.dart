import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/index.dart';

class OfflineCardService {
  static const _cardsKeyPrefix = 'offline_cards_cache_';
  static const _redeemKeyPrefix = 'offline_redeem_queue_';

  Future<void> cacheCards({
    required String userId,
    required List<VirtualCard> cards,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cardsKeyPrefix$userId';
    final existing = _decodeList(prefs.getString(key));
    final byBarcode = <String, Map<String, dynamic>>{};

    for (final item in existing) {
      final barcode = item['barcode']?.toString() ?? '';
      if (barcode.isNotEmpty) {
        byBarcode[barcode] = item;
      }
    }

    for (final card in cards) {
      if (!card.isPrivate) {
        continue;
      }
      final isOwner = (card.ownerId ?? '') == userId;
      final isAllowed = card.allowedUserIds.contains(userId);
      if (!isOwner && !isAllowed) {
        continue;
      }
      byBarcode[card.barcode] = card.toMap();
    }

    await prefs.setString(key, jsonEncode(byBarcode.values.toList()));
  }

  Future<VirtualCard?> findCachedCard(String userId, String barcode) async {
    final cards = await _loadCards(userId);
    final match = cards.firstWhere(
      (card) => card.barcode == barcode,
      orElse: () => VirtualCard(
        id: '',
        barcode: '',
        value: 0,
        createdAt: DateTime.now(),
      ),
    );
    return match.barcode.isEmpty ? null : match;
  }

  Future<void> markCardUsed({
    required String userId,
    required String barcode,
    String? customerName,
    String? usedBy,
    DateTime? usedAt,
  }) async {
    final cards = await _loadCards(userId);
    final updated = cards.map((card) {
      if (card.barcode != barcode) {
        return card;
      }
      return card.copyWith(
        status: CardStatus.used,
        customerName: customerName ?? card.customerName,
        usedBy: usedBy ?? card.usedBy,
        usedAt: usedAt ?? DateTime.now(),
      );
    }).toList();
    await _storeCards(userId, updated);
  }

  Future<List<Map<String, dynamic>>> getRedeemQueue(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString('$_redeemKeyPrefix$userId'));
  }

  Future<void> enqueueRedeem(
    String userId,
    Map<String, dynamic> entry,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_redeemKeyPrefix$userId';
    final queue = _decodeList(prefs.getString(key));
    queue.add(entry);
    await prefs.setString(key, jsonEncode(queue));
  }

  Future<void> clearRedeemQueue(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_redeemKeyPrefix$userId');
  }

  Future<List<VirtualCard>> _loadCards(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cardsKeyPrefix$userId';
    final raw = _decodeList(prefs.getString(key));
    return raw.map((item) => VirtualCard.fromMap(item)).toList();
  }

  Future<void> _storeCards(String userId, List<VirtualCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cardsKeyPrefix$userId';
    final payload = cards.map((card) => card.toMap()).toList();
    await prefs.setString(key, jsonEncode(payload));
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
