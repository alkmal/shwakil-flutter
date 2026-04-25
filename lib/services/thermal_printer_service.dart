import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_model.dart';

class ThermalPrinterDevice {
  const ThermalPrinterDevice({required this.name, required this.macAddress});

  final String name;
  final String macAddress;
}

class ThermalPrinterService {
  static const String _selectedPrinterMacKey = 'thermal_printer_mac';
  static const String _selectedPrinterNameKey = 'thermal_printer_name';

  Future<bool> isSupported() async {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<bool> ensureBluetoothPermission() async {
    return PrintBluetoothThermal.isPermissionBluetoothGranted;
  }

  Future<bool> isBluetoothEnabled() async {
    return PrintBluetoothThermal.bluetoothEnabled;
  }

  Future<List<ThermalPrinterDevice>> pairedDevices() async {
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices
        .map(
          (device) => ThermalPrinterDevice(
            name: device.name.trim().isEmpty ? 'Thermal Printer' : device.name,
            macAddress: device.macAdress,
          ),
        )
        .toList(growable: false);
  }

  Future<void> rememberDevice(ThermalPrinterDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedPrinterMacKey, device.macAddress);
    await prefs.setString(_selectedPrinterNameKey, device.name);
  }

  Future<ThermalPrinterDevice?> selectedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final macAddress = prefs.getString(_selectedPrinterMacKey)?.trim() ?? '';
    if (macAddress.isEmpty) {
      return null;
    }
    final name =
        prefs.getString(_selectedPrinterNameKey)?.trim().isNotEmpty == true
        ? prefs.getString(_selectedPrinterNameKey)!.trim()
        : 'Thermal Printer';
    return ThermalPrinterDevice(name: name, macAddress: macAddress);
  }

  Future<void> clearSelectedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedPrinterMacKey);
    await prefs.remove(_selectedPrinterNameKey);
  }

  Future<bool> connect(ThermalPrinterDevice device) async {
    final connected = await PrintBluetoothThermal.connect(
      macPrinterAddress: device.macAddress,
    );
    if (connected) {
      await rememberDevice(device);
    }
    return connected;
  }

  Future<bool> disconnect() async {
    return PrintBluetoothThermal.disconnect;
  }

  Future<bool> connectionStatus() async {
    return PrintBluetoothThermal.connectionStatus;
  }

  Future<bool> ensureConnected(ThermalPrinterDevice device) async {
    final isConnected = await connectionStatus();
    if (isConnected) {
      return true;
    }
    return connect(device);
  }

  Future<bool> printCardTicket({
    required VirtualCard card,
    required Uint8List ticketPngBytes,
    required String issuerName,
    bool cutPaper = false,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final decoded = img.decodeImage(ticketPngBytes);
    if (decoded == null) {
      return false;
    }

    final bytes = <int>[];
    bytes.addAll(generator.reset());
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.imageRaster(decoded, align: PosAlign.center));
    bytes.addAll(
      generator.text(
        'CARD ${card.barcode}',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(
      generator.text(
        'ISSUER: $issuerName',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(
      generator.text(
        'DATE: ${card.createdAt.toLocal().toString().split('.').first}',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(generator.feed(3));
    if (cutPaper) {
      bytes.addAll(generator.cut());
    }
    return PrintBluetoothThermal.writeBytes(bytes);
  }
}
