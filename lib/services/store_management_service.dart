import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api_service.dart';

class StoreManagementService {
  static const _snapshotKeyPrefix = 'store_management_snapshot_';
  static const _queueKeyPrefix = 'store_management_queue_';
  static const _offlineKeyName = 'store_management_aes_key_v1';
  static final AesGcm _cipher = AesGcm.with256bits();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const Uuid _uuid = Uuid();

  Future<Map<String, dynamic>> getSnapshot(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = await _decodeObject(
      prefs.getString('$_snapshotKeyPrefix$userId'),
    );
    return decoded;
  }

  Future<List<Map<String, dynamic>>> getPendingOperations(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString('$_queueKeyPrefix$userId'));
  }

  Future<Map<String, dynamic>> refresh({
    required String userId,
    required ApiService api,
  }) async {
    final snapshot = await api.getStoreManagementSnapshot();
    await _storeSnapshot(userId, snapshot);
    return snapshot;
  }

  Future<Map<String, dynamic>> syncPending({
    required String userId,
    required ApiService api,
  }) async {
    final operations = await getPendingOperations(userId);
    if (operations.isEmpty) {
      return refresh(userId: userId, api: api);
    }
    final snapshot = await api.syncStoreManagement(operations);
    await _storeSnapshot(userId, snapshot);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_queueKeyPrefix$userId');
    return snapshot;
  }

  Future<void> queueProduct({
    required String userId,
    String? serverId,
    String? clientRef,
    required String name,
    required String baseUnit,
    required double minimumStock,
    required double salePrice,
    required List<Map<String, dynamic>> units,
  }) {
    return _enqueue(userId, {
      'opId': _uuid.v4(),
      'entity': 'product',
      'type': 'upsert',
      'serverId': ?serverId,
      'clientRef': clientRef ?? _uuid.v4(),
      'name': name.trim(),
      'baseUnit': baseUnit,
      'minimumStock': minimumStock,
      'defaultSalePrice': salePrice,
      'units': units,
    });
  }

  Future<void> queueParty({
    required String userId,
    required String type,
    required String name,
    String phone = '',
    String notes = '',
  }) {
    return _enqueue(userId, {
      'opId': _uuid.v4(),
      'entity': 'party',
      'type': 'upsert',
      'clientRef': _uuid.v4(),
      'partyType': type,
      'name': name.trim(),
      'phone': phone.trim(),
      'notes': notes.trim(),
    });
  }

  Future<void> queueInvoice({
    required String userId,
    required String invoiceType,
    String? partyId,
    String? partyName,
    required double paidAmount,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
    double discount = 0,
    String notes = '',
  }) {
    return _enqueue(userId, {
      'opId': _uuid.v4(),
      'entity': 'invoice',
      'type': 'create',
      'clientRef': _uuid.v4(),
      'invoiceType': invoiceType,
      'partyId': ?partyId,
      'partyName': ?partyName,
      'paidAmount': paidAmount,
      'paymentMethod': paymentMethod,
      'discount': discount,
      'notes': notes.trim(),
      'occurredAt': DateTime.now().toIso8601String(),
      'items': items,
    });
  }

  Future<void> queuePayment({
    required String userId,
    String? invoiceId,
    String? partyId,
    required String direction,
    required double amount,
    String method = 'cash',
    String notes = '',
  }) {
    return _enqueue(userId, {
      'opId': _uuid.v4(),
      'entity': 'payment',
      'type': 'create',
      'clientRef': _uuid.v4(),
      'invoiceId': ?invoiceId,
      'partyId': ?partyId,
      'direction': direction,
      'amount': amount,
      'method': method,
      'notes': notes.trim(),
      'occurredAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _storeSnapshot(
    String userId,
    Map<String, dynamic> snapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_snapshotKeyPrefix$userId',
      await _encode(snapshot),
    );
  }

  Future<void> _enqueue(String userId, Map<String, dynamic> operation) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_queueKeyPrefix$userId';
    final queue = await _decodeList(prefs.getString(key));
    queue.add(operation);
    await prefs.setString(key, await _encode(queue));
  }

  Future<String> _encode(Object payload) async {
    final secretKey = await _getOrCreateSecretKey();
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: secretKey,
    );
    return jsonEncode({
      'v': 1,
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  Future<Map<String, dynamic>> _decodeObject(String? raw) async {
    final decoded = await _decode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<List<Map<String, dynamic>>> _decodeList(String? raw) async {
    final decoded = await _decode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<dynamic> _decode(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['v'] == 1) {
        final clear = await _cipher.decrypt(
          SecretBox(
            base64Decode(decoded['cipherText']?.toString() ?? ''),
            nonce: base64Decode(decoded['nonce']?.toString() ?? ''),
            mac: Mac(base64Decode(decoded['mac']?.toString() ?? '')),
          ),
          secretKey: await _getOrCreateSecretKey(),
        );
        return jsonDecode(utf8.decode(clear));
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _getOrCreateSecretKey() async {
    final existing = await _readSecureValue(_offlineKeyName);
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

  Future<String?> _readSecureValue(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } on PlatformException catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('badpaddingexception') ||
          message.contains('bad_decrypt') ||
          message.contains('failed to unwrap key') ||
          message.contains('invalidkeyexception')) {
        await _secureStorage.delete(key: key);
        return null;
      }
      rethrow;
    }
  }
}
