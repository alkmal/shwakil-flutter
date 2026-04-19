import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/index.dart';

class OfflineCardService {
  static const _cardsKeyPrefix = 'offline_cards_cache_';
  static const _redeemKeyPrefix = 'offline_redeem_queue_';
  static const _offlineKeyName = 'offline_cards_aes_key_v1';
  static final AesGcm _cipher = AesGcm.with256bits();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<void> cacheCards({
    required String userId,
    required List<VirtualCard> cards,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cardsKeyPrefix$userId';
    final existing = await _decodeStoredList(prefs.getString(key));
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

    await prefs.setString(
      key,
      await _encodeStoredList(byBarcode.values.toList()),
    );
  }

  Future<VirtualCard?> findCachedCard(String userId, String barcode) async {
    final cards = await _loadCards(userId);
    final match = cards.firstWhere(
      (card) => card.barcode == barcode,
      orElse: () =>
          VirtualCard(id: '', barcode: '', value: 0, createdAt: DateTime.now()),
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

  Future<void> removeCardsByBarcode({
    required String userId,
    required Set<String> barcodes,
  }) async {
    if (barcodes.isEmpty) {
      return;
    }
    final cards = await _loadCards(userId);
    await _storeCards(
      userId,
      cards.where((card) => !barcodes.contains(card.barcode)).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> getRedeemQueue(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeStoredList(prefs.getString('$_redeemKeyPrefix$userId'));
  }

  Future<void> enqueueRedeem(String userId, Map<String, dynamic> entry) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_redeemKeyPrefix$userId';
    final queue = await _decodeStoredList(prefs.getString(key));
    queue.add(entry);
    await prefs.setString(key, await _encodeStoredList(queue));
  }

  Future<void> clearRedeemQueue(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_redeemKeyPrefix$userId');
  }

  Future<void> replaceRedeemQueue(
    String userId,
    List<Map<String, dynamic>> entries,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_redeemKeyPrefix$userId';
    if (entries.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, await _encodeStoredList(entries));
  }

  Future<List<VirtualCard>> _loadCards(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cardsKeyPrefix$userId';
    final raw = await _decodeStoredList(prefs.getString(key));
    return raw.map((item) => VirtualCard.fromMap(item)).toList();
  }

  Future<void> _storeCards(String userId, List<VirtualCard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_cardsKeyPrefix$userId';
    final payload = cards.map((card) => card.toMap()).toList();
    await prefs.setString(key, await _encodeStoredList(payload));
  }

  Future<String> _encodeStoredList(List<Map<String, dynamic>> payload) async {
    final secretKey = await _getOrCreateSecretKey();
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: secretKey,
    );
    return jsonEncode({
      'v': 1,
      'alg': 'AES-256-GCM',
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  Future<List<Map<String, dynamic>>> _decodeStoredList(String? raw) async {
    if (raw == null || raw.trim().isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['v'] == 1) {
        final secretKey = await _getOrCreateSecretKey();
        final clearBytes = await _cipher.decrypt(
          SecretBox(
            base64Decode(decoded['cipherText']?.toString() ?? ''),
            nonce: base64Decode(decoded['nonce']?.toString() ?? ''),
            mac: Mac(base64Decode(decoded['mac']?.toString() ?? '')),
          ),
          secretKey: secretKey,
        );
        return _coerceList(jsonDecode(utf8.decode(clearBytes)));
      }
      return _coerceList(decoded);
    } catch (_) {
      return [];
    }
  }

  Future<SecretKey> _getOrCreateSecretKey() async {
    final existing = await _secureStorage.read(key: _offlineKeyName);
    if (existing != null && existing.isNotEmpty) {
      return SecretKey(base64Decode(existing));
    }
    final key = await _cipher.newSecretKey();
    await _secureStorage.write(
      key: _offlineKeyName,
      value: base64Encode(await key.extractBytes()),
    );
    return key;
  }

  List<Map<String, dynamic>> _coerceList(dynamic decoded) {
    if (decoded is! List) {
      return [];
    }
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
