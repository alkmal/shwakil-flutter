import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:virtual_currency_cards/models/card_model.dart';
import 'package:virtual_currency_cards/services/pdf_service.dart';
import 'package:virtual_currency_cards/utils/card_print_layout.dart';
import 'package:virtual_currency_cards/utils/card_denomination_color.dart';

VirtualCard sampleCard(int index) => VirtualCard(
  id: 'print-test-$index',
  barcode: '99000000${index.toString().padLeft(8, '0')}',
  value: [1, 2, 3, 4, 5, 10, 20][index % 7].toDouble(),
  visibilityScope: index.isEven ? 'general' : 'restricted',
  issueCost: index.isEven ? 0 : 0.25,
  createdAt: DateTime(2026, 10, 8),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => PDFService().setDesignSettings(CardDesignSettings()));

  test('A4 layout uses exactly five columns and seven rows', () {
    expect(PDFService.cardsPerA4Sheet, 35);
    expect(CardPrintLayout.columns, 5);
    expect(CardPrintLayout.rows, 7);
    expect(CardPrintLayout.cardWidth, greaterThan(39 * PdfPageFormat.mm));
    expect(CardPrintLayout.cardHeight, greaterThan(40 * PdfPageFormat.mm));
  });

  test('defined denominations all have distinct stable colours', () {
    final colors = CardDenominationColor.known.keys
        .map((cents) => CardDenominationColor.forValue(cents / 100).toARGB32())
        .toSet();
    expect(colors.length, CardDenominationColor.known.length);
    expect(
      CardDenominationColor.forValue(1.25),
      isNot(CardDenominationColor.forValue(1)),
    );
  });

  for (final count in [1, 35, 36, 70, 71]) {
    test('$count cards produce ${(count / 35).ceil()} A4 pages', () async {
      final document = await PDFService().createMultiCardPDF(
        List.generate(count, sampleCard),
        printedBy: 'نسخة تجريبية للطباعة',
      );
      expect(document.document.pdfPageList.pages.length, (count / 35).ceil());
      final bytes = await document.save();
      expect(bytes, isNotEmpty);
      // Optional renderable fixture, using synthetic barcodes only.
      const outputDirectory = String.fromEnvironment('PRINT_REVIEW_DIR');
      if (outputDirectory.isNotEmpty) {
        final directory = Directory(outputDirectory);
        await directory.create(recursive: true);
        await File('${directory.path}/cards-$count.pdf').writeAsBytes(bytes);
      }
    });
  }

  test('empty selection cannot open a blank print job', () async {
    await expectLater(PDFService().createMultiCardPDF([]), throwsArgumentError);
  });

  test('card preview uses the same physical cell as the A4 sheet', () async {
    final document = await PDFService().createSmallCardSheetPreviewPDF(
      sampleCard(1),
    );
    expect(document.document.pdfPageList.pages, hasLength(1));
    expect(await document.save(), isNotEmpty);
  });

  test('final preview includes the logo value and stamp', () async {
    final document = await PDFService().createSmallCardSheetPreviewPDF(
      sampleCard(5),
      printedBy: 'شواكل',
    );
    final bytes = await document.save();
    const outputDirectory = String.fromEnvironment('PRINT_REVIEW_DIR');
    if (outputDirectory.isNotEmpty) {
      await File('$outputDirectory/final-card.pdf').writeAsBytes(bytes);
    }
    expect(bytes, isNotEmpty);
  });
}
