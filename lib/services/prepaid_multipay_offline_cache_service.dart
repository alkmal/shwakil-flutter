import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrepaidMultipayOfflineCacheService {
  const PrepaidMultipayOfflineCacheService();

  static const String cacheKey = 'prepaid_multipay_cards_offline_cache_v1';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<void> save({
    required List<Map<String, dynamic>> cards,
    required List<Map<String, dynamic>> payments,
    required bool nfcEnabled,
    required bool canUsePrepaidCards,
    required bool canAcceptPrepaidPayments,
    required bool canUsePrepaidNfc,
  }) async {
    if (cards.isEmpty || !canUsePrepaidCards) {
      return;
    }

    await _secureStorage.write(
      key: cacheKey,
      value: jsonEncode({
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'cards': cards,
        'payments': payments.take(20).toList(),
        'nfcEnabled': nfcEnabled,
        'canUsePrepaidCards': canUsePrepaidCards,
        'canAcceptPrepaidPayments': canAcceptPrepaidPayments,
        'canUsePrepaidNfc': canUsePrepaidNfc,
      }),
    );
  }

  Future<Map<String, dynamic>?> load() async {
    final raw =
        await _secureStorage.read(key: cacheKey) ?? await _migrateLegacyCache();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final cards = List<Map<String, dynamic>>.from(
        (decoded['cards'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      if (cards.isEmpty) {
        return null;
      }
      final payments = List<Map<String, dynamic>>.from(
        (decoded['payments'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );

      return {
        'cards': cards,
        'payments': payments,
        'nfcEnabled': decoded['nfcEnabled'] == true,
        'canUsePrepaidCards': decoded['canUsePrepaidCards'] == true,
        'canAcceptPrepaidPayments': decoded['canAcceptPrepaidPayments'] == true,
        'canUsePrepaidNfc': decoded['canUsePrepaidNfc'] == true,
        'cachedAt': decoded['cachedAt']?.toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasCards() async {
    final cached = await load();
    final cards = cached?['cards'];
    return cards is List && cards.isNotEmpty;
  }

  Future<String?> _migrateLegacyCache() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(cacheKey);
    if (legacy == null || legacy.isEmpty) {
      return null;
    }
    await _secureStorage.write(key: cacheKey, value: legacy);
    await prefs.remove(cacheKey);
    return legacy;
  }
}
