import 'dart:math';
import 'package:barcode/barcode.dart';

class BarcodeService {
  static final BarcodeService _instance = BarcodeService._internal();
  factory BarcodeService() {
    return _instance;
  }
  BarcodeService._internal();
  final Random _random = Random();
  String generateBarcode() {
    return _generateDigits(16);
  }

  String generateCardCode() {
    return _generateDigits(12);
  }

  String _generateDigits(int length) {
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }

  Future<String?> generateBarcodeImage(String barcode) async {
    try {
      final bc = Barcode.code128();
      return bc.toSvg(barcode, width: 200, height: 100);
    } catch (_) {
      return null;
    }
  }

  bool isValidBarcode(String barcode) {
    return RegExp(r'^\d{16}$').hasMatch(barcode);
  }
}
