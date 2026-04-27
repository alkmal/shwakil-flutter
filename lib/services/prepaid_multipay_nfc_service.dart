import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

class PrepaidMultipayNfcService {
  const PrepaidMultipayNfcService();

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
}
