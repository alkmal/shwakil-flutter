import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

class PrepaidMultipayNfcPayload {
  const PrepaidMultipayNfcPayload({
    required this.cardNumber,
    required this.expiryMonth,
    required this.expiryYear,
    required this.label,
    required this.issuedAt,
  });

  static const String type = 'prepaid_multipay_card';
  static const String mimeType =
      'application/vnd.shwakil.prepaid-multipay-card+json';

  final String cardNumber;
  final int expiryMonth;
  final int expiryYear;
  final String label;
  final DateTime issuedAt;

  factory PrepaidMultipayNfcPayload.fromCard(Map<String, dynamic> card) {
    return PrepaidMultipayNfcPayload(
      cardNumber: (card['rawCardNumber'] ?? '').toString(),
      expiryMonth: (card['expiryMonth'] as num?)?.toInt() ?? 0,
      expiryYear: (card['expiryYear'] as num?)?.toInt() ?? 0,
      label: (card['label'] ?? '').toString(),
      issuedAt: DateTime.now().toUtc(),
    );
  }

  factory PrepaidMultipayNfcPayload.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException('نوع بطاقة NFC غير مدعوم.');
    }

    return PrepaidMultipayNfcPayload(
      cardNumber: (json['cardNumber'] ?? '').toString().replaceAll(
        RegExp(r'\D+'),
        '',
      ),
      expiryMonth: (json['expiryMonth'] as num?)?.toInt() ?? 0,
      expiryYear: (json['expiryYear'] as num?)?.toInt() ?? 0,
      label: (json['label'] ?? '').toString(),
      issuedAt:
          DateTime.tryParse((json['issuedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'type': type,
      'cardNumber': cardNumber.replaceAll(RegExp(r'\D+'), ''),
      'expiryMonth': expiryMonth,
      'expiryYear': expiryYear,
      'label': label,
      'issuedAt': issuedAt.toUtc().toIso8601String(),
    };
  }
}

class PrepaidMultipayNfcPaymentAuthorization {
  const PrepaidMultipayNfcPaymentAuthorization({
    required this.signedPayload,
    required this.signature,
    required this.issuedAt,
    required this.expiresAt,
    required this.amount,
  });

  static const String type = 'prepaid_multipay_nfc_signed_payment';
  static const String mimeType =
      'application/vnd.shwakil.prepaid-multipay-nfc-payment+json';

  final String signedPayload;
  final String signature;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final double amount;

  factory PrepaidMultipayNfcPaymentAuthorization.fromJson(
    Map<String, dynamic> json,
  ) {
    if (json['type'] != type) {
      throw const FormatException('نوع إذن NFC غير مدعوم.');
    }
    final payload = (json['signedPayload'] ?? '').toString();
    final decodedPayload = jsonDecode(payload);
    final payloadMap = decodedPayload is Map
        ? Map<String, dynamic>.from(decodedPayload)
        : <String, dynamic>{};

    return PrepaidMultipayNfcPaymentAuthorization(
      signedPayload: payload,
      signature: (json['signature'] ?? '').toString(),
      issuedAt:
          DateTime.tryParse((payloadMap['issuedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt:
          DateTime.tryParse((payloadMap['expiresAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      amount: double.tryParse((payloadMap['amount'] ?? '0').toString()) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'type': type,
      'signedPayload': signedPayload,
      'signature': signature,
    };
  }
}

class PrepaidMultipayNfcService {
  const PrepaidMultipayNfcService();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final Ed25519 _ed25519 = Ed25519();

  static String _privateKeyKey(String cardId) =>
      'prepaid_multipay_nfc_private_$cardId';
  static String _publicKeyKey(String cardId) =>
      'prepaid_multipay_nfc_public_$cardId';

  Future<bool> isAvailable() async {
    if (kIsWeb) {
      return false;
    }

    try {
      return await NfcManager.instance.checkAvailability() ==
          NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  Future<void> writeCard(PrepaidMultipayNfcPayload payload) async {
    await _ensureAvailable();

    final completer = Completer<void>();
    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443},
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw Exception('هذا الوسم لا يدعم NDEF.');
          }
          if (!ndef.isWritable) {
            throw Exception('وسم NFC غير قابل للكتابة.');
          }

          final message = _messageFromPayload(payload);
          if (ndef.maxSize > 0 && message.byteLength > ndef.maxSize) {
            throw Exception('حجم بيانات البطاقة أكبر من مساحة وسم NFC.');
          }

          await ndef.write(message: message);
          await NfcManager.instance.stopSession();
          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (error, stackTrace) {
          await NfcManager.instance.stopSession(
            errorMessageIos: error.toString(),
          );
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () async {
        await NfcManager.instance.stopSession(
          errorMessageIos: 'انتهت مهلة NFC.',
        );
        throw TimeoutException('انتهت مهلة NFC.');
      },
    );
  }

  Future<PrepaidMultipayNfcPayload> readCard() async {
    await _ensureAvailable();

    final completer = Completer<PrepaidMultipayNfcPayload>();
    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443},
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw Exception('هذا الوسم لا يدعم NDEF.');
          }

          final message = await ndef.read() ?? ndef.cachedMessage;
          if (message == null) {
            throw Exception('لا توجد بيانات بطاقة شواكل على هذا الوسم.');
          }

          final payload = _payloadFromMessage(message);
          await NfcManager.instance.stopSession();
          if (!completer.isCompleted) {
            completer.complete(payload);
          }
        } catch (error, stackTrace) {
          await NfcManager.instance.stopSession(
            errorMessageIos: error.toString(),
          );
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () async {
        await NfcManager.instance.stopSession(
          errorMessageIos: 'انتهت مهلة NFC.',
        );
        throw TimeoutException('انتهت مهلة NFC.');
      },
    );
  }

  Future<Map<String, String>> getOrCreateSigningKeyPair(String cardId) async {
    final privateKey = await _secureStorage.read(key: _privateKeyKey(cardId));
    final publicKey = await _secureStorage.read(key: _publicKeyKey(cardId));
    if (privateKey != null &&
        privateKey.isNotEmpty &&
        publicKey != null &&
        publicKey.isNotEmpty) {
      return {'privateKey': privateKey, 'publicKey': publicKey};
    }

    final keyPair = await _ed25519.newKeyPair();
    final keyData = await keyPair.extract();
    final generatedPrivateKey = base64Encode(keyData.bytes);
    final generatedPublicKey = base64Encode(keyData.publicKey.bytes);

    await _secureStorage.write(
      key: _privateKeyKey(cardId),
      value: generatedPrivateKey,
    );
    await _secureStorage.write(
      key: _publicKeyKey(cardId),
      value: generatedPublicKey,
    );

    return {'privateKey': generatedPrivateKey, 'publicKey': generatedPublicKey};
  }

  Future<void> deleteSigningKeyPair(String cardId) async {
    await _secureStorage.delete(key: _privateKeyKey(cardId));
    await _secureStorage.delete(key: _publicKeyKey(cardId));
  }

  Future<PrepaidMultipayNfcPaymentAuthorization> signAuthorization({
    required String cardId,
    required Map<String, dynamic> authorization,
  }) async {
    final keyPair = await _keyPairForCard(cardId);
    final signedPayload = jsonEncode(_canonicalize(authorization));
    final signature = await _ed25519.sign(
      utf8.encode(signedPayload),
      keyPair: keyPair,
    );
    final payload = jsonDecode(signedPayload) as Map<String, dynamic>;

    return PrepaidMultipayNfcPaymentAuthorization(
      signedPayload: signedPayload,
      signature: base64Encode(signature.bytes),
      issuedAt:
          DateTime.tryParse((payload['issuedAt'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      expiresAt:
          DateTime.tryParse((payload['expiresAt'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      amount: double.tryParse((payload['amount'] ?? '0').toString()) ?? 0,
    );
  }

  Future<void> writePaymentAuthorization(
    PrepaidMultipayNfcPaymentAuthorization authorization,
  ) async {
    await _ensureAvailable();

    final completer = Completer<void>();
    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443},
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw Exception('هذا الوسم لا يدعم NDEF.');
          }
          if (!ndef.isWritable) {
            throw Exception('وسم NFC غير قابل للكتابة.');
          }

          final message = _paymentMessageFromAuthorization(authorization);
          if (ndef.maxSize > 0 && message.byteLength > ndef.maxSize) {
            throw Exception('حجم إذن الدفع أكبر من مساحة وسم NFC.');
          }

          await ndef.write(message: message);
          await NfcManager.instance.stopSession();
          if (!completer.isCompleted) {
            completer.complete();
          }
        } catch (error, stackTrace) {
          await NfcManager.instance.stopSession(
            errorMessageIos: error.toString(),
          );
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () async {
        await NfcManager.instance.stopSession(
          errorMessageIos: 'انتهت مهلة NFC.',
        );
        throw TimeoutException('انتهت مهلة NFC.');
      },
    );
  }

  Future<PrepaidMultipayNfcPaymentAuthorization>
  readPaymentAuthorization() async {
    await _ensureAvailable();

    final completer = Completer<PrepaidMultipayNfcPaymentAuthorization>();
    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443},
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            throw Exception('هذا الوسم لا يدعم NDEF.');
          }

          final message = await ndef.read() ?? ndef.cachedMessage;
          if (message == null) {
            throw Exception('لا يوجد إذن دفع شواكل على هذا الوسم.');
          }

          final authorization = _paymentAuthorizationFromMessage(message);
          await NfcManager.instance.stopSession();
          if (!completer.isCompleted) {
            completer.complete(authorization);
          }
        } catch (error, stackTrace) {
          await NfcManager.instance.stopSession(
            errorMessageIos: error.toString(),
          );
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () async {
        await NfcManager.instance.stopSession(
          errorMessageIos: 'انتهت مهلة NFC.',
        );
        throw TimeoutException('انتهت مهلة NFC.');
      },
    );
  }

  Future<void> _ensureAvailable() async {
    if (!await isAvailable()) {
      throw Exception('NFC غير متاح أو غير مفعل على هذا الجهاز.');
    }
  }

  NdefMessage _messageFromPayload(PrepaidMultipayNfcPayload payload) {
    final jsonPayload = jsonEncode(payload.toJson());
    return NdefMessage(
      records: [
        NdefRecord(
          typeNameFormat: TypeNameFormat.media,
          type: Uint8List.fromList(
            utf8.encode(PrepaidMultipayNfcPayload.mimeType),
          ),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(utf8.encode(jsonPayload)),
        ),
      ],
    );
  }

  NdefMessage _paymentMessageFromAuthorization(
    PrepaidMultipayNfcPaymentAuthorization authorization,
  ) {
    final jsonPayload = jsonEncode(authorization.toJson());
    return NdefMessage(
      records: [
        NdefRecord(
          typeNameFormat: TypeNameFormat.media,
          type: Uint8List.fromList(
            utf8.encode(PrepaidMultipayNfcPaymentAuthorization.mimeType),
          ),
          identifier: Uint8List(0),
          payload: Uint8List.fromList(utf8.encode(jsonPayload)),
        ),
      ],
    );
  }

  PrepaidMultipayNfcPayload _payloadFromMessage(NdefMessage message) {
    for (final record in message.records) {
      final type = utf8.decode(record.type, allowMalformed: true);
      if (record.typeNameFormat != TypeNameFormat.media ||
          type != PrepaidMultipayNfcPayload.mimeType) {
        continue;
      }

      final decoded = jsonDecode(utf8.decode(record.payload));
      if (decoded is Map) {
        return PrepaidMultipayNfcPayload.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    }

    throw const FormatException('لم يتم العثور على بطاقة شواكل NFC صالحة.');
  }

  PrepaidMultipayNfcPaymentAuthorization _paymentAuthorizationFromMessage(
    NdefMessage message,
  ) {
    for (final record in message.records) {
      final type = utf8.decode(record.type, allowMalformed: true);
      if (record.typeNameFormat != TypeNameFormat.media ||
          type != PrepaidMultipayNfcPaymentAuthorization.mimeType) {
        continue;
      }

      final decoded = jsonDecode(utf8.decode(record.payload));
      if (decoded is Map) {
        return PrepaidMultipayNfcPaymentAuthorization.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    }

    throw const FormatException('لم يتم العثور على إذن دفع NFC صالح.');
  }

  Future<SimpleKeyPairData> _keyPairForCard(String cardId) async {
    final keys = await getOrCreateSigningKeyPair(cardId);
    final publicBytes = base64Decode(keys['publicKey'] ?? '');
    final privateBytes = base64Decode(keys['privateKey'] ?? '');
    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );
  }

  Map<String, dynamic> _canonicalize(Map<String, dynamic> value) {
    final sortedKeys = value.keys.map((key) => key.toString()).toList()..sort();
    return {
      for (final key in sortedKeys)
        key: value[key] is Map<String, dynamic>
            ? _canonicalize(Map<String, dynamic>.from(value[key] as Map))
            : value[key],
    };
  }
}
