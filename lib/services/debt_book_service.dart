import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api_service.dart';

class DebtBookService {
  static const _snapshotKeyPrefix = 'debt_book_snapshot_';
  static const _queueKeyPrefix = 'debt_book_queue_';
  static const _offlineKeyName = 'debt_book_aes_key_v1';
  static final AesGcm _cipher = AesGcm.with256bits();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const Uuid _uuid = Uuid();

  Future<Map<String, dynamic>> getSnapshot(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = await _decodeStoredObject(
      prefs.getString('$_snapshotKeyPrefix$userId'),
    );
    return {
      'customers': _coerceList(decoded['customers']),
      'entries': _coerceList(decoded['entries']),
      'summary': decoded['summary'] is Map
          ? Map<String, dynamic>.from(decoded['summary'] as Map)
          : const <String, dynamic>{},
      'syncedAt': decoded['syncedAt'],
    };
  }

  Future<void> replaceSnapshot(
    String userId,
    Map<String, dynamic> snapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_snapshotKeyPrefix$userId',
      await _encodeStoredObject({
        'customers': _coerceList(snapshot['customers']),
        'entries': _coerceList(snapshot['entries']),
        'summary': snapshot['summary'] is Map
            ? Map<String, dynamic>.from(snapshot['summary'] as Map)
            : const <String, dynamic>{},
        'syncedAt': snapshot['syncedAt'] ?? DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<List<Map<String, dynamic>>> getPendingOperations(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeStoredList(prefs.getString('$_queueKeyPrefix$userId'));
  }

  Future<bool> hasPendingOperations(String userId) async {
    final queue = await getPendingOperations(userId);
    return queue.isNotEmpty;
  }

  Future<void> clearPendingOperations(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_queueKeyPrefix$userId');
  }

  Future<Map<String, dynamic>> refreshFromServer({
    required String userId,
    required ApiService api,
  }) async {
    final snapshot = await api.getDebtBookSnapshot();
    await replaceSnapshot(userId, snapshot);
    return getSnapshot(userId);
  }

  Future<Map<String, dynamic>> syncPending({
    required String userId,
    required ApiService api,
  }) async {
    final queue = await getPendingOperations(userId);
    if (queue.isEmpty) {
      return refreshFromServer(userId: userId, api: api);
    }
    final response = await api.syncDebtBook(queue);
    await replaceSnapshot(userId, response);
    await clearPendingOperations(userId);
    return getSnapshot(userId);
  }

  Future<Map<String, dynamic>> upsertCustomerLocally({
    required String userId,
    String? customerRef,
    required String fullName,
    required String phone,
    String notes = '',
  }) async {
    final snapshot = await getSnapshot(userId);
    final customers = _coerceList(snapshot['customers']);
    final entries = _coerceList(snapshot['entries']);
    final now = DateTime.now().toIso8601String();

    final existingIndex = customers.indexWhere(
      (item) => _matchesCustomerRef(item, customerRef),
    );
    final existing = existingIndex >= 0 ? customers[existingIndex] : null;
    final clientRef =
        existing?['clientRef']?.toString() ??
        _normalizeCustomerClientRef(customerRef) ??
        _uuid.v4();
    final serverId = existing?['id']?.toString();

    final customer = {
      'id': serverId ?? 'local:$clientRef',
      'clientRef': clientRef,
      'fullName': fullName.trim(),
      'phone': phone.trim(),
      'notes': notes.trim(),
      'totalDebt': (existing?['totalDebt'] as num?)?.toDouble() ?? 0,
      'totalPaid': (existing?['totalPaid'] as num?)?.toDouble() ?? 0,
      'balance': (existing?['balance'] as num?)?.toDouble() ?? 0,
      'lastEntryAt': existing?['lastEntryAt']?.toString(),
      'createdAt': existing?['createdAt']?.toString() ?? now,
      'updatedAt': now,
    };

    if (existingIndex >= 0) {
      customers[existingIndex] = customer;
    } else {
      customers.add(customer);
    }

    await _enqueueOperation(userId, {
      'opId': _uuid.v4(),
      'entity': 'customer',
      'type': 'upsert',
      'clientRef': clientRef,
      if (serverId != null && !serverId.startsWith('local:')) 'serverId': serverId,
      'fullName': fullName.trim(),
      'phone': phone.trim(),
      'notes': notes.trim(),
      'updatedAt': now,
    });

    await replaceSnapshot(
      userId,
      _rebuildSnapshot(customers: customers, entries: entries),
    );

    return customer;
  }

  Future<Map<String, dynamic>> addEntryLocally({
    required String userId,
    required String customerRef,
    required String entryType,
    required double amount,
    String note = '',
    DateTime? occurredAt,
  }) async {
    final snapshot = await getSnapshot(userId);
    final customers = _coerceList(snapshot['customers']);
    final entries = _coerceList(snapshot['entries']);
    final customerIndex = customers.indexWhere(
      (item) => _matchesCustomerRef(item, customerRef),
    );
    if (customerIndex < 0) {
      throw Exception('تعذر العثور على العميل المطلوب.');
    }

    final customer = customers[customerIndex];
    final clientRef = _uuid.v4();
    final occurred = (occurredAt ?? DateTime.now()).toIso8601String();
    final serverId = customer['id']?.toString();
    final customerClientRef = customer['clientRef']?.toString();

    final entry = {
      'id': 'local:$clientRef',
      'clientRef': clientRef,
      'customerId': serverId != null && !serverId.startsWith('local:')
          ? serverId
          : 'local:${customerClientRef ?? ''}',
      'type': entryType,
      'amount': amount,
      'note': note.trim(),
      'occurredAt': occurred,
      'createdAt': occurred,
      'updatedAt': occurred,
      'metadata': const <String, dynamic>{'source': 'offline_local'},
    };

    entries.insert(0, entry);

    await _enqueueOperation(userId, {
      'opId': _uuid.v4(),
      'entity': 'entry',
      'type': 'create',
      'clientRef': clientRef,
      if (serverId != null && !serverId.startsWith('local:')) 'customerId': serverId,
      if (customerClientRef != null && customerClientRef.isNotEmpty)
        'customerClientRef': customerClientRef,
      'entryType': entryType,
      'amount': amount,
      'note': note.trim(),
      'occurredAt': occurred,
    });

    await replaceSnapshot(
      userId,
      _rebuildSnapshot(customers: customers, entries: entries),
    );

    return entry;
  }

  Future<Map<String, dynamic>> updateEntryLocally({
    required String userId,
    required String entryRef,
    required String entryType,
    required double amount,
    String note = '',
    DateTime? occurredAt,
  }) async {
    final snapshot = await getSnapshot(userId);
    final customers = _coerceList(snapshot['customers']);
    final entries = _coerceList(snapshot['entries']);
    final entryIndex = entries.indexWhere((item) {
      final id = item['id']?.toString() ?? '';
      final clientRef = item['clientRef']?.toString() ?? '';
      return id == entryRef ||
          clientRef == entryRef ||
          'local:$clientRef' == entryRef;
    });
    if (entryIndex < 0) {
      throw Exception('تعذر العثور على القيد المطلوب.');
    }

    final existing = entries[entryIndex];
    final occurred = (occurredAt ?? DateTime.now()).toIso8601String();
    final serverId = existing['id']?.toString();
    final clientRef = existing['clientRef']?.toString() ?? _uuid.v4();
    final updated = {
      ...existing,
      'type': entryType,
      'amount': amount,
      'note': note.trim(),
      'occurredAt': occurred,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    entries[entryIndex] = updated;

    await _enqueueOperation(userId, {
      'opId': _uuid.v4(),
      'entity': 'entry',
      'type': 'update',
      'clientRef': clientRef,
      if (serverId != null && !serverId.startsWith('local:')) 'serverId': serverId,
      'entryType': entryType,
      'amount': amount,
      'note': note.trim(),
      'occurredAt': occurred,
    });

    await replaceSnapshot(
      userId,
      _rebuildSnapshot(customers: customers, entries: entries),
    );

    return updated;
  }

  Future<void> deleteCustomerLocally({
    required String userId,
    required String customerRef,
  }) async {
    final snapshot = await getSnapshot(userId);
    final customers = _coerceList(snapshot['customers']);
    final entries = _coerceList(snapshot['entries']);
    final customerIndex = customers.indexWhere(
      (item) => _matchesCustomerRef(item, customerRef),
    );
    if (customerIndex < 0) {
      throw Exception('تعذر العثور على العميل المطلوب.');
    }

    final customer = customers.removeAt(customerIndex);
    final customerId = customer['id']?.toString() ?? '';
    final customerClientRef = customer['clientRef']?.toString() ?? '';
    entries.removeWhere((entry) {
      final entryCustomerId = entry['customerId']?.toString() ?? '';
      return entryCustomerId == customerId ||
          entryCustomerId == 'local:$customerClientRef';
    });

    await _enqueueOperation(userId, {
      'opId': _uuid.v4(),
      'entity': 'customer',
      'type': 'delete',
      if (customerClientRef.isNotEmpty) 'clientRef': customerClientRef,
      if (customerId.isNotEmpty && !customerId.startsWith('local:'))
        'serverId': customerId,
    });

    await replaceSnapshot(
      userId,
      _rebuildSnapshot(customers: customers, entries: entries),
    );
  }

  Future<void> deleteEntryLocally({
    required String userId,
    required String entryRef,
  }) async {
    final snapshot = await getSnapshot(userId);
    final customers = _coerceList(snapshot['customers']);
    final entries = _coerceList(snapshot['entries']);
    final entryIndex = entries.indexWhere((item) {
      final id = item['id']?.toString() ?? '';
      final clientRef = item['clientRef']?.toString() ?? '';
      return id == entryRef ||
          clientRef == entryRef ||
          'local:$clientRef' == entryRef;
    });
    if (entryIndex < 0) {
      throw Exception('تعذر العثور على القيد المطلوب.');
    }

    final entry = entries.removeAt(entryIndex);
    final entryId = entry['id']?.toString() ?? '';
    final clientRef = entry['clientRef']?.toString() ?? '';
    final customerId = entry['customerId']?.toString() ?? '';

    await _enqueueOperation(userId, {
      'opId': _uuid.v4(),
      'entity': 'entry',
      'type': 'delete',
      if (clientRef.isNotEmpty) 'clientRef': clientRef,
      if (entryId.isNotEmpty && !entryId.startsWith('local:')) 'serverId': entryId,
      if (customerId.isNotEmpty && !customerId.startsWith('local:'))
        'customerId': customerId,
    });

    await replaceSnapshot(
      userId,
      _rebuildSnapshot(customers: customers, entries: entries),
    );
  }

  Map<String, dynamic> _rebuildSnapshot({
    required List<Map<String, dynamic>> customers,
    required List<Map<String, dynamic>> entries,
  }) {
    final updatedCustomers = customers.map((customer) {
      final customerEntries = entries
          .where((entry) => _entryBelongsToCustomer(entry, customer))
          .toList();
      final totalDebt = customerEntries
          .where((entry) => entry['type'] == 'debt')
          .fold<double>(
            0,
            (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
          );
      final totalPaid = customerEntries
          .where((entry) => entry['type'] == 'payment')
          .fold<double>(
            0,
            (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
          );
      final sortedEntries = [...customerEntries]
        ..sort((a, b) => (b['occurredAt']?.toString() ?? '').compareTo(
              a['occurredAt']?.toString() ?? '',
            ));
      return {
        ...customer,
        'totalDebt': totalDebt,
        'totalPaid': totalPaid,
        'balance': totalDebt - totalPaid,
        'lastEntryAt': sortedEntries.isNotEmpty
            ? sortedEntries.first['occurredAt']
            : customer['lastEntryAt'],
        'updatedAt': DateTime.now().toIso8601String(),
      };
    }).toList()
      ..sort((a, b) {
        final aBalance = (a['balance'] as num?)?.toDouble() ?? 0;
        final bBalance = (b['balance'] as num?)?.toDouble() ?? 0;
        if (aBalance > 0 && bBalance <= 0) return -1;
        if (aBalance <= 0 && bBalance > 0) return 1;
        return (b['lastEntryAt']?.toString() ?? '').compareTo(
          a['lastEntryAt']?.toString() ?? '',
        );
      });

    final totalDebt = updatedCustomers.fold<double>(
      0,
      (sum, item) => sum + ((item['totalDebt'] as num?)?.toDouble() ?? 0),
    );
    final totalPaid = updatedCustomers.fold<double>(
      0,
      (sum, item) => sum + ((item['totalPaid'] as num?)?.toDouble() ?? 0),
    );

    return {
      'customers': updatedCustomers,
      'entries': entries,
      'summary': {
        'customersCount': updatedCustomers.length,
        'openCustomersCount': updatedCustomers
            .where((item) => ((item['balance'] as num?)?.toDouble() ?? 0) > 0)
            .length,
        'totalDebt': totalDebt,
        'totalPaid': totalPaid,
        'totalBalance': totalDebt - totalPaid,
      },
      'syncedAt': DateTime.now().toIso8601String(),
    };
  }

  bool _matchesCustomerRef(Map<String, dynamic> customer, String? customerRef) {
    if (customerRef == null || customerRef.isEmpty) {
      return false;
    }
    final id = customer['id']?.toString() ?? '';
    final clientRef = customer['clientRef']?.toString() ?? '';
    return id == customerRef ||
        clientRef == customerRef ||
        'local:$clientRef' == customerRef;
  }

  bool _entryBelongsToCustomer(
    Map<String, dynamic> entry,
    Map<String, dynamic> customer,
  ) {
    final entryCustomerId = entry['customerId']?.toString() ?? '';
    final customerId = customer['id']?.toString() ?? '';
    final customerClientRef = customer['clientRef']?.toString() ?? '';
    return entryCustomerId == customerId ||
        entryCustomerId == 'local:$customerClientRef';
  }

  String? _normalizeCustomerClientRef(String? customerRef) {
    if (customerRef == null || customerRef.isEmpty) {
      return null;
    }
    if (customerRef.startsWith('local:')) {
      return customerRef.substring(6);
    }
    return null;
  }

  Future<void> _enqueueOperation(
    String userId,
    Map<String, dynamic> operation,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_queueKeyPrefix$userId';
    final queue = await _decodeStoredList(prefs.getString(key));
    queue.add(operation);
    await prefs.setString(key, await _encodeStoredList(queue));
  }

  Future<String> _encodeStoredList(List<Map<String, dynamic>> payload) async {
    return _encodeJsonPayload(payload);
  }

  Future<String> _encodeStoredObject(Map<String, dynamic> payload) async {
    return _encodeJsonPayload(payload);
  }

  Future<String> _encodeJsonPayload(Object payload) async {
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
    final decoded = await _decodeJsonPayload(raw);
    return _coerceList(decoded);
  }

  Future<Map<String, dynamic>> _decodeStoredObject(String? raw) async {
    final decoded = await _decodeJsonPayload(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<dynamic> _decodeJsonPayload(String? raw) async {
    if (raw == null || raw.trim().isEmpty) {
      return null;
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
        return jsonDecode(utf8.decode(clearBytes));
      }
      return decoded;
    } catch (_) {
      return null;
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
