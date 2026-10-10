import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:virtual_currency_cards/widgets/barcode_scanner_dialog.dart';

void main() {
  late MobileScannerPlatform original;
  late _ScannerPlatform platform;

  setUp(() {
    original = MobileScannerPlatform.instance;
    platform = _ScannerPlatform();
    MobileScannerPlatform.instance = platform;
  });

  tearDown(() {
    MobileScannerPlatform.instance = original;
  });

  Future<void> open(
    WidgetTester tester,
    Future<BarcodeScannerDialogResult?> Function(String) resolve,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeScannerDialog(
            title: 'Scan',
            description: 'Scan a card',
            onScanResolved: resolve,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unsupported torch is disabled', (tester) async {
    await open(tester, (_) async => null);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('a camera stop error does not prevent resolving a card', (
    tester,
  ) async {
    platform.failStop = true;
    var resolved = 0;
    await open(tester, (_) async {
      resolved++;
      return const BarcodeScannerDialogResult.error(
        headline: 'Resolved card',
        message: 'Result',
      );
    });
    platform.captures.add(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '12345')]),
    );
    await tester.pumpAndSettle();
    expect(resolved, 1);
    expect(find.text('Resolved card'), findsOneWidget);
    expect(tester.takeException(), isNull);
    platform.failStop = false;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('failed result action shows an error and releases loading', (
    tester,
  ) async {
    await open(
      tester,
      (_) async => BarcodeScannerDialogResult(
        headline: 'Card',
        description: 'Ready',
        color: Colors.green,
        icon: Icons.check,
        primaryActionLabel: 'Perform action',
        onPrimaryAction: () async => throw Exception('Network timeout'),
      ),
    );
    platform.captures.add(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '12345')]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perform action'));
    await tester.pumpAndSettle();
    expect(find.text('Perform action'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

class _ScannerPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture>.broadcast();
  bool failStop = false;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream =>
      Stream.value(TorchState.unavailable);
  @override
  Stream<double> get zoomScaleStateStream => Stream.value(1);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async =>
      const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.unavailable,
        size: Size(200, 200),
        numberOfCameras: 1,
      );
  @override
  Widget buildCameraView() => const SizedBox.square(dimension: 200);
  @override
  Future<void> stop() async {
    if (failStop) throw StateError('Camera already disconnected');
  }

  @override
  Future<void> dispose() async => captures.close();
}
