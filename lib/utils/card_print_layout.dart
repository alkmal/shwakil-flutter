import 'package:pdf/pdf.dart';

/// Physical sheet geometry shared by card printing and its previews.
abstract final class CardPrintLayout {
  static const columns = 5;
  static const rows = 7;
  static const cardsPerSheet = columns * rows;
  static const margin = 3.5 * PdfPageFormat.mm;
  static const cutGap = 0.6 * PdfPageFormat.mm;
  static final cellWidth = (PdfPageFormat.a4.width - 2 * margin) / columns;
  static final cellHeight = (PdfPageFormat.a4.height - 2 * margin) / rows;
  static final cardWidth = cellWidth - 2 * cutGap;
  static final cardHeight = cellHeight - 2 * cutGap;

  static int pageCount(int cardCount) => (cardCount / cardsPerSheet).ceil();
}
