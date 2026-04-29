import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/index.dart';

class CardDesignSettings {
  bool showLogo;
  bool showStamp;
  String? logoText;
  String? logoUrl;
  String? stampText;
  CardDesignSettings({
    this.showLogo = true,
    this.showStamp = true,
    this.logoText = 'شواكل',
    this.stampText = 'صالح للتداول',
  });
}

class _DenominationPalette {
  final PdfColor primary;
  final PdfColor value;
  final PdfColor soft;
  final PdfColor border;
  final PdfColor accent;
  const _DenominationPalette({
    required this.primary,
    required this.value,
    required this.soft,
    required this.border,
    required this.accent,
  });
}

class PDFService {
  static final PDFService _instance = PDFService._internal();
  static const int _cardsPerPage = 30;
  static const int _rowsPerPage = 6;
  static const int _columnsPerPage = 5;
  static const PdfColor _pageBackground = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor _cardBackground = PdfColor.fromInt(0xFFFFF8EC);
  static const PdfColor _titleColor = PdfColor.fromInt(0xFF16302B);
  static const PdfColor _mutedColor = PdfColor.fromInt(0xFF64748B);
  static const PdfColor _stampColor = PdfColor.fromInt(0xFFDC2626);
  static const List<_DenominationPalette> _palettes = [
    _DenominationPalette(
      primary: PdfColor.fromInt(0xFF0F766E),
      value: PdfColor.fromInt(0xFF047857),
      soft: PdfColor.fromInt(0xFFDDF7F1),
      border: PdfColor.fromInt(0xFF5EEAD4),
      accent: PdfColor.fromInt(0xFF14B8A6),
    ),
    _DenominationPalette(
      primary: PdfColor.fromInt(0xFF0F766E),
      value: PdfColor.fromInt(0xFF1E40AF),
      soft: PdfColor.fromInt(0xFFCCFBF1),
      border: PdfColor.fromInt(0xFF93C5FD),
      accent: PdfColor.fromInt(0xFF60A5FA),
    ),
    _DenominationPalette(
      primary: PdfColor.fromInt(0xFFB45309),
      value: PdfColor.fromInt(0xFF92400E),
      soft: PdfColor.fromInt(0xFFFFEDD5),
      border: PdfColor.fromInt(0xFFFDBA74),
      accent: PdfColor.fromInt(0xFFFB923C),
    ),
    _DenominationPalette(
      primary: PdfColor.fromInt(0xFFBE123C),
      value: PdfColor.fromInt(0xFF9F1239),
      soft: PdfColor.fromInt(0xFFFFE4E6),
      border: PdfColor.fromInt(0xFFFDA4AF),
      accent: PdfColor.fromInt(0xFFFB7185),
    ),
  ];
  factory PDFService() => _instance;
  PDFService._internal();
  final CardDesignSettings designSettings = CardDesignSettings();
  pw.Font? _regularFont;
  pw.Font? _boldFont;
  pw.MemoryImage? _defaultLogoImage;
  pw.MemoryImage? _accountLogoImage;
  String? _loadedLogoSource;
  Future<void> _ensureFontsLoaded() async {
    _regularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    _boldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );
    _defaultLogoImage ??= pw.MemoryImage(
      (await rootBundle.load(
        'assets/images/shwakel_app_icon.png',
      )).buffer.asUint8List(),
    );
    await _ensureLogoLoaded();
  }

  Future<void> _ensureLogoLoaded() async {
    final logoUrl = designSettings.logoUrl?.trim() ?? '';
    if (logoUrl.isNotEmpty &&
        _loadedLogoSource == logoUrl &&
        _accountLogoImage != null) {
      return;
    }
    if (logoUrl.isEmpty && _loadedLogoSource == 'none') {
      return;
    }

    if (logoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(logoUrl));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _accountLogoImage = pw.MemoryImage(
            Uint8List.fromList(response.bodyBytes),
          );
          _loadedLogoSource = logoUrl;
          return;
        }
      } catch (_) {}
    }

    _accountLogoImage = null;
    _loadedLogoSource = 'none';
  }

  pw.TextStyle _textStyle({
    double fontSize = 10,
    bool bold = false,
    PdfColor? color,
    pw.Font? font,
  }) {
    return pw.TextStyle(
      fontSize: fontSize,
      color: color ?? _titleColor,
      font: font ?? (bold ? _boldFont : _regularFont),
      fontFallback: [?_regularFont, ?_boldFont],
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
  }

  _DenominationPalette _paletteForCard(VirtualCard card) {
    final roundedValue = card.value.round();
    final index = roundedValue > 0 ? (roundedValue - 1) % _palettes.length : 0;
    return _palettes[index];
  }

  String _formatSerialNumber(int serialNumber) {
    return serialNumber.toString().padLeft(4, '0');
  }

  String _resolvedLogoText() {
    final text = designSettings.logoText?.trim() ?? '';
    return text.isEmpty ? 'شواكل' : text;
  }

  String _resolvedStampText() {
    final text = designSettings.stampText?.trim() ?? '';
    return text.isEmpty ? 'صالح للتداول' : text;
  }

  double _headerTitleSize(bool compact) {
    final length = _resolvedLogoText().runes.length;
    if (compact) {
      if (length > 26) {
        return 5.6;
      }
      if (length > 18) {
        return 6.2;
      }
      return 7.2;
    }
    if (length > 30) {
      return 12.8;
    }
    if (length > 20) {
      return 14.6;
    }
    return 16.5;
  }

  String _valueInArabicWords(double value) {
    final rounded = value.round();
    if ((value - rounded).abs() < 0.001) {
      return '${_integerToArabicWords(rounded)} شيكل';
    }
    return '${value.toStringAsFixed(2)} شيكل';
  }

  String _integerToArabicWords(int number) {
    if (number == 0) {
      return 'صفر';
    }
    const units = <int, String>{
      1: 'واحد',
      2: 'اثنان',
      3: 'ثلاثة',
      4: 'أربعة',
      5: 'خمسة',
      6: 'ستة',
      7: 'سبعة',
      8: 'ثمانية',
      9: 'تسعة',
      10: 'عشرة',
      11: 'أحد عشر',
      12: 'اثنا عشر',
      13: 'ثلاثة عشر',
      14: 'أربعة عشر',
      15: 'خمسة عشر',
      16: 'ستة عشر',
      17: 'سبعة عشر',
      18: 'ثمانية عشر',
      19: 'تسعة عشر',
    };
    const tens = <int, String>{
      20: 'عشرون',
      30: 'ثلاثون',
      40: 'أربعون',
      50: 'خمسون',
      60: 'ستون',
      70: 'سبعون',
      80: 'ثمانون',
      90: 'تسعون',
    };
    const hundreds = <int, String>{
      100: 'مائة',
      200: 'مائتان',
      300: 'ثلاثمائة',
      400: 'أربعمائة',
      500: 'خمسمائة',
      600: 'ستمائة',
      700: 'سبعمائة',
      800: 'ثمانمائة',
      900: 'تسعمائة',
    };
    if (number < 20) {
      return units[number]!;
    }
    if (number < 100) {
      final tenValue = (number ~/ 10) * 10;
      final unitValue = number % 10;
      if (unitValue == 0) {
        return tens[tenValue]!;
      }
      return '${units[unitValue]} و${tens[tenValue]}';
    }
    if (number < 1000) {
      final hundredValue = (number ~/ 100) * 100;
      final remainder = number % 100;
      if (remainder == 0) {
        return hundreds[hundredValue]!;
      }
      return '${hundreds[hundredValue]} و${_integerToArabicWords(remainder)}';
    }
    if (number < 1000000) {
      final thousands = number ~/ 1000;
      final remainder = number % 1000;
      String thousandsLabel;
      if (thousands == 1) {
        thousandsLabel = 'ألف';
      } else if (thousands == 2) {
        thousandsLabel = 'ألفان';
      } else if (thousands <= 10) {
        thousandsLabel = '${_integerToArabicWords(thousands)} آلاف';
      } else {
        thousandsLabel = '${_integerToArabicWords(thousands)} ألف';
      }
      if (remainder == 0) {
        return thousandsLabel;
      }
      return '$thousandsLabel و${_integerToArabicWords(remainder)}';
    }
    return number.toString();
  }

  String _printedByLabel(String? printedBy) {
    final name = (printedBy ?? '').trim();
    return name.isEmpty ? 'الجهة الطابعة: غير محددة' : 'الجهة الطابعة: $name';
  }

  String _originLabel(String? printedBy) {
    final origin = (printedBy ?? '').trim();
    return origin.isEmpty ? 'غير محددة' : origin;
  }

  bool _isLocationSpecific(VirtualCard card) {
    final scope = card.visibilityScope.trim().toLowerCase();
    return scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
  }

  bool _isTicketCard(VirtualCard card) =>
      card.isSingleUse || card.isAppointment || card.isQueueTicket;

  String _privacyLabel(VirtualCard card) => card.isPrivate ? 'خاصة' : 'عامة';

  String _cardKindLabel(VirtualCard card) {
    if (card.isDelivery) {
      return 'بطاقة رصيد توصيل';
    }
    if (card.isSingleUse) {
      return 'تذكرة دخول';
    }
    if (card.isAppointment) {
      return 'تذكرة موعد';
    }
    if (card.isQueueTicket) {
      return 'تذكرة طابور';
    }
    return 'بطاقة رصيد';
  }

  String _cardTypeLabel(VirtualCard card) {
    if (_isLocationSpecific(card)) {
      return '${_cardKindLabel(card)} مخصصة لمكان محدد';
    }
    return '${_cardKindLabel(card)} ${_privacyLabel(card)}';
  }

  String _cardBadgeLabel(VirtualCard card) {
    if (_isLocationSpecific(card)) {
      return 'مكان محدد - ${_cardKindLabel(card)}';
    }
    return '${_privacyLabel(card)} - ${_cardKindLabel(card)}';
  }

  String _cardTitle(VirtualCard card) {
    if (_isTicketCard(card)) {
      final title = card.title?.trim() ?? '';
      return title.isNotEmpty ? title : _cardKindLabel(card);
    }
    return '${card.value.toStringAsFixed(2)} شيكل';
  }

  String _cardSubtitle(VirtualCard card) {
    if (card.isDelivery) {
      return 'بطاقة رصيد عامة للتوصيل والمدفوعات';
    }
    if (card.isSingleUse) {
      return 'تذكرة خاصة لاستخدام واحد داخل النظام';
    }
    if (card.isAppointment) {
      return 'تذكرة موعد خاصة لمستفيدين محددين';
    }
    if (card.isQueueTicket) {
      return 'تذكرة طابور خاصة لمستفيدين محددين';
    }
    return card.isPrivate
        ? 'بطاقة رصيد خاصة لمستفيدين محددين'
        : 'بطاقة رصيد عامة - ${_valueInArabicWords(card.value)}';
  }

  pw.Widget _topHeader(
    _DenominationPalette palette, {
    required bool compact,
    required VirtualCard card,
  }) {
    final shwakelLogoSize = compact ? 24.0 : 58.0;
    final accountLogoSize = compact ? 24.0 : 54.0;
    final titleSize = _headerTitleSize(compact);
    final badgeFont = compact ? 4.8 : 8.8;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: compact ? 3.8 : 8,
            vertical: compact ? 1.3 : 3,
          ),
          decoration: pw.BoxDecoration(
            color: card.isPrivate
                ? const PdfColor.fromInt(0xFFFFE4E6)
                : palette.soft,
            borderRadius: pw.BorderRadius.circular(compact ? 6 : 10),
            border: pw.Border.all(
              color: card.isPrivate
                  ? const PdfColor.fromInt(0xFFFB7185)
                  : palette.border,
              width: compact ? 0.45 : 0.9,
            ),
          ),
          child: pw.Text(
            _cardBadgeLabel(card),
            textDirection: pw.TextDirection.rtl,
            style: _textStyle(
              fontSize: badgeFont,
              bold: true,
              color: card.isPrivate
                  ? const PdfColor.fromInt(0xFFBE123C)
                  : palette.primary,
            ),
          ),
        ),
        pw.SizedBox(width: compact ? 4 : 10),
        pw.Expanded(
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (_accountLogoImage != null) ...[
                _buildHeaderLogoBox(
                  _accountLogoImage!,
                  size: accountLogoSize,
                  compact: compact,
                ),
                pw.SizedBox(width: compact ? 4 : 7),
              ],
              if (_defaultLogoImage != null) ...[
                _buildHeaderLogoBox(
                  _defaultLogoImage!,
                  size: shwakelLogoSize,
                  compact: compact,
                ),
                pw.SizedBox(width: compact ? 5 : 10),
              ],
              pw.Flexible(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      _resolvedLogoText(),
                      maxLines: compact ? 2 : 3,
                      textAlign: pw.TextAlign.right,
                      textDirection: pw.TextDirection.rtl,
                      style: _textStyle(
                        fontSize: titleSize,
                        bold: true,
                        color: palette.primary,
                      ),
                    ),
                    pw.SizedBox(height: compact ? 1.2 : 2.5),
                    pw.Text(
                      card.isDelivery
                          ? 'بطاقة رصيد عامة للتوصيل والمدفوعات'
                          : _isTicketCard(card)
                          ? 'تذكرة خاصة داخل النظام'
                          : 'بطاقة رصيد رقمية',
                      textDirection: pw.TextDirection.rtl,
                      textAlign: pw.TextAlign.right,
                      style: _textStyle(
                        fontSize: compact ? 4.2 : 7.2,
                        color: _mutedColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildHeaderLogoBox(
    pw.MemoryImage image, {
    required double size,
    required bool compact,
  }) {
    return pw.Container(
      width: size,
      height: size,
      padding: pw.EdgeInsets.all(compact ? 1.8 : 3.0),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(compact ? 3 : 8),
      ),
      child: pw.Image(image, fit: pw.BoxFit.contain),
    );
  }

  pw.Widget _buildStampBadge({required bool compact}) {
    final borderRadius = compact ? 4.0 : 8.0;
    return pw.Transform.rotateBox(
      angle: compact ? -0.22 : -0.26,
      child: pw.Opacity(
        opacity: compact ? 0.38 : 0.34,
        child: pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: compact ? 3.6 : 8.0,
            vertical: compact ? 1.8 : 4.2,
          ),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _stampColor, width: compact ? 0.7 : 1),
            borderRadius: pw.BorderRadius.circular(borderRadius),
          ),
          child: pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: compact ? 2.2 : 4.6,
              vertical: compact ? 1.0 : 2.2,
            ),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: _stampColor,
                width: compact ? 0.45 : 0.7,
              ),
              borderRadius: pw.BorderRadius.circular(
                compact ? 2.4 : borderRadius - 2,
              ),
            ),
            child: pw.Text(
              _resolvedStampText(),
              textAlign: pw.TextAlign.center,
              textDirection: pw.TextDirection.rtl,
              style: _textStyle(
                fontSize: compact ? 4.2 : 8.8,
                bold: true,
                color: _stampColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<pw.Document> createCardPDF(
    VirtualCard card, {
    String? printedBy,
    int serialNumber = 1,
  }) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          100 * PdfPageFormat.mm,
          65 * PdfPageFormat.mm,
        ),
        theme: pw.ThemeData.withFont(
          base: _regularFont!,
          bold: _boldFont!,
          fontFallback: [_regularFont!, _boldFont!],
        ),
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: _buildCardContainer(
            card,
            printedBy: printedBy,
            serialNumber: serialNumber,
          ),
        ),
      ),
    );
    return pdf;
  }

  Future<pw.Document> createMultiCardPDF(
    List<VirtualCard> cards, {
    String? printedBy,
  }) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();
    for (int i = 0; i < cards.length; i += _cardsPerPage) {
      final pageCards = cards.sublist(
        i,
        (i + _cardsPerPage).clamp(0, cards.length),
      );
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          theme: pw.ThemeData.withFont(
            base: _regularFont!,
            bold: _boldFont!,
            fontFallback: [_regularFont!, _boldFont!],
          ),
          build: (context) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              color: _pageBackground,
              child: pw.Column(
                children: _buildCardRows(
                  pageCards,
                  printedBy: printedBy,
                  startSerialNumber: i + 1,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return pdf;
  }

  List<pw.Widget> _buildCardRows(
    List<VirtualCard> cards, {
    String? printedBy,
    int startSerialNumber = 1,
  }) {
    final rows = <pw.Widget>[];
    for (int rowIndex = 0; rowIndex < _rowsPerPage; rowIndex++) {
      final start = rowIndex * _columnsPerPage;
      final end = (start + _columnsPerPage).clamp(0, cards.length);
      final rowCards = start < cards.length
          ? cards.sublist(start, end)
          : <VirtualCard>[];
      rows.add(
        pw.Expanded(
          child: pw.Padding(
            padding: pw.EdgeInsets.only(
              bottom: rowIndex == _rowsPerPage - 1 ? 0 : 2.5,
            ),
            child: pw.Row(
              children: List.generate(_columnsPerPage, (columnIndex) {
                return pw.Expanded(
                  child: pw.Padding(
                    padding: pw.EdgeInsetsDirectional.only(
                      start: columnIndex == 0 ? 0 : 2,
                      end: columnIndex == _columnsPerPage - 1 ? 0 : 2,
                    ),
                    child: columnIndex < rowCards.length
                        ? _buildSmallCardWidget(
                            rowCards[columnIndex],
                            printedBy: printedBy,
                            serialNumber:
                                startSerialNumber + start + columnIndex,
                          )
                        : pw.SizedBox.expand(),
                  ),
                );
              }),
            ),
          ),
        ),
      );
    }
    return rows;
  }

  pw.Widget _buildSmallCardWidget(
    VirtualCard card, {
    String? printedBy,
    required int serialNumber,
  }) {
    final palette = _paletteForCard(card);
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _cardBackground,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: palette.border, width: 1),
      ),
      child: pw.Stack(
        children: [
          pw.Positioned(
            top: 0,
            right: 0,
            left: 0,
            child: pw.Container(
              height: 3,
              decoration: pw.BoxDecoration(
                color: palette.primary,
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(4),
                  topRight: pw.Radius.circular(4),
                ),
              ),
            ),
          ),
          pw.Positioned(
            top: 8,
            left: 4,
            child: pw.Opacity(
              opacity: 0.12,
              child: pw.Container(
                width: 15,
                height: 15,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: palette.primary, width: 1),
                ),
              ),
            ),
          ),
          pw.Positioned(
            bottom: 6,
            right: 4,
            child: pw.Opacity(
              opacity: 0.10,
              child: pw.Container(
                width: 13,
                height: 13,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: palette.accent, width: 1),
                ),
              ),
            ),
          ),
          pw.Positioned.fill(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(3.4, 5.5, 3.4, 2.8),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _topHeader(palette, compact: true, card: card),
                  pw.Column(
                    children: [
                      if (_isTicketCard(card))
                        pw.Text(
                          _cardTitle(card),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 5.7,
                            bold: true,
                            color: palette.primary,
                          ),
                        ),
                      pw.Text(
                        _isTicketCard(card)
                            ? _cardSubtitle(card)
                            : 'بطاقة رقمية للاستخدام الداخلي',
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(fontSize: 5.2, color: _mutedColor),
                      ),
                      if (!_isTicketCard(card)) ...[
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          _cardTitle(card),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 14.5,
                            bold: true,
                            color: palette.value,
                          ),
                        ),
                        pw.SizedBox(height: 1),
                        pw.Text(
                          _cardSubtitle(card),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 5,
                            bold: true,
                            color: palette.primary,
                          ),
                        ),
                      ],
                      pw.SizedBox(height: 1.5),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 2.2,
                          vertical: 1.4,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(4),
                          border: pw.Border.all(
                            color: palette.border,
                            width: 0.9,
                          ),
                        ),
                        child: pw.SizedBox(
                          height: 15,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.code128(),
                            data: card.barcode,
                            drawText: false,
                            color: _titleColor,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        card.barcode,
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.ltr,
                        style: _textStyle(
                          fontSize: 5.7,
                          color: _titleColor,
                          font: pw.Font.courier(),
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1.2,
                        ),
                        decoration: pw.BoxDecoration(
                          color: palette.soft,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          'التسلسل: ${_formatSerialNumber(serialNumber)}',
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 4.4,
                            bold: true,
                            color: palette.primary,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 0.7),
                      pw.Text(
                        _printedByLabel(printedBy),
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(
                          fontSize: 4.2,
                          bold: true,
                          color: palette.primary,
                        ),
                      ),
                      pw.SizedBox(height: 0.4),
                      pw.Text(
                        'تاريخ الإصدار: ${DateFormat('dd/MM/yyyy').format(card.createdAt)}',
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(fontSize: 4.1, color: _mutedColor),
                      ),
                      pw.Text(
                        'منشأ البطاقة: ${_originLabel(printedBy)}',
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(fontSize: 4.1, color: _mutedColor),
                      ),
                      pw.Text(
                        'نوع البطاقة: ${_cardTypeLabel(card)}',
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(
                          fontSize: 4.1,
                          color: palette.primary,
                        ),
                      ),
                      if (card.issueCost > 0)
                        pw.Text(
                          'تكلفة الإصدار: ${card.issueCost.toStringAsFixed(2)} شيكل',
                          textAlign: pw.TextAlign.right,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 4.0,
                            color: palette.primary,
                          ),
                        ),
                      pw.SizedBox(height: 0.3),
                      pw.Text(
                        'shwakil.alkmal.com',
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.ltr,
                        style: _textStyle(
                          fontSize: 4.2,
                          color: palette.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (designSettings.showStamp)
            pw.Positioned(
              top: 20,
              left: 1,
              child: _buildStampBadge(compact: true),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildCardContainer(
    VirtualCard card, {
    String? printedBy,
    required int serialNumber,
  }) {
    final palette = _paletteForCard(card);
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _cardBackground,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: palette.border, width: 1.5),
      ),
      child: pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: palette.soft, width: 0.8),
              ),
            ),
          ),
          pw.Positioned(
            top: 0,
            right: 0,
            left: 0,
            child: pw.Container(
              height: 8,
              decoration: pw.BoxDecoration(
                color: palette.primary,
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(6),
                  topRight: pw.Radius.circular(6),
                ),
              ),
            ),
          ),
          pw.Positioned(
            top: 14,
            left: 10,
            child: pw.Opacity(
              opacity: 0.10,
              child: pw.Container(
                width: 52,
                height: 52,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: palette.primary, width: 1.2),
                ),
              ),
            ),
          ),
          pw.Positioned(
            right: 12,
            bottom: 16,
            child: pw.Opacity(
              opacity: 0.10,
              child: pw.Container(
                width: 42,
                height: 42,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: palette.accent, width: 1.2),
                ),
              ),
            ),
          ),
          pw.Positioned.fill(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _topHeader(palette, compact: false, card: card),
                  pw.Column(
                    children: [
                      if (_isTicketCard(card))
                        pw.Text(
                          _cardTitle(card),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 10.5,
                            bold: true,
                            color: palette.primary,
                          ),
                        ),
                      pw.Text(
                        _isTicketCard(card)
                            ? _cardSubtitle(card)
                            : 'بطاقة رقمية للاستخدام الداخلي',
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(fontSize: 9.2, color: _mutedColor),
                      ),
                      if (!_isTicketCard(card)) ...[
                        pw.SizedBox(height: 7),
                        pw.Text(
                          _cardTitle(card),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 24,
                            bold: true,
                            color: palette.value,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          _cardSubtitle(card),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 10,
                            bold: true,
                            color: palette.primary,
                          ),
                        ),
                      ],
                      pw.SizedBox(height: 4),
                      pw.Text(
                        card.isDelivery
                            ? 'بطاقة رصيد عامة يمكن استخدامها للمدفوعات'
                            : _isTicketCard(card)
                            ? 'صالحة للمستفيدين المحددين فقط'
                            : 'قيمة داخلية صالحة للاستخدام داخل النظام',
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(fontSize: 8.2, color: _titleColor),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(6),
                          border: pw.Border.all(
                            color: palette.border,
                            width: 1,
                          ),
                        ),
                        child: pw.SizedBox(
                          height: 44,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.code128(),
                            data: card.barcode,
                            drawText: false,
                            color: _titleColor,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        card.barcode,
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.ltr,
                        style: _textStyle(
                          fontSize: 12.4,
                          color: _titleColor,
                          font: pw.Font.courier(),
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: pw.BoxDecoration(
                          color: palette.soft,
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Text(
                          'الرقم المتسلسل: ${_formatSerialNumber(serialNumber)}',
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 8.6,
                            bold: true,
                            color: palette.primary,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        _printedByLabel(printedBy),
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(
                          fontSize: 8.1,
                          bold: true,
                          color: palette.primary,
                        ),
                      ),
                      pw.Text(
                        'نوع البطاقة: ${_cardTypeLabel(card)}',
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(
                          fontSize: 7.9,
                          color: palette.primary,
                        ),
                      ),
                      if (card.issueCost > 0)
                        pw.Text(
                          'تكلفة الإصدار: ${card.issueCost.toStringAsFixed(2)} شيكل',
                          textAlign: pw.TextAlign.right,
                          textDirection: pw.TextDirection.rtl,
                          style: _textStyle(
                            fontSize: 7.6,
                            color: palette.primary,
                          ),
                        ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'تاريخ الإصدار: ${DateFormat('yyyy-MM-dd').format(card.createdAt)}',
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(fontSize: 7.8, color: _mutedColor),
                      ),
                      pw.Text(
                        'منشأ البطاقة: ${_originLabel(printedBy)}',
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(fontSize: 7.8, color: _mutedColor),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'shwakil.alkmal.com',
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.ltr,
                        style: _textStyle(fontSize: 8, color: palette.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (designSettings.showStamp)
            pw.Positioned(
              top: 52,
              left: 8,
              child: _buildStampBadge(compact: false),
            ),
        ],
      ),
    );
  }

  Future<void> printCards(List<VirtualCard> cards, {String? printedBy}) async {
    final pdf = await createMultiCardPDF(cards, printedBy: printedBy);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<File> savePDF(pw.Document pdf, String filename) async {
    final dir = await _documentsExportDirectory();
    final safeName = _safeFileName(filename);
    final file = File('${dir.path}/$safeName.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  Future<Directory> _documentsExportDirectory() async {
    final candidates = <Directory>[];

    if (Platform.isAndroid) {
      candidates.add(Directory('/storage/emulated/0/Documents/shwakil'));
    } else {
      final documentsDir = await getApplicationDocumentsDirectory();
      candidates.add(Directory('${documentsDir.path}/shwakil'));
    }

    final fallbackDir = await getApplicationDocumentsDirectory();
    candidates.add(Directory('${fallbackDir.path}/shwakil'));

    for (final candidate in candidates) {
      try {
        if (!await candidate.exists()) {
          await candidate.create(recursive: true);
        }
        final probe = File(
          '${candidate.path}/.write_test_${DateTime.now().microsecondsSinceEpoch}',
        );
        await probe.writeAsString('ok');
        await probe.delete();
        return candidate;
      } catch (_) {}
    }

    return fallbackDir;
  }

  String _safeFileName(String filename) {
    final normalized = filename
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return normalized.isEmpty
        ? 'shwakil_cards_${DateTime.now().millisecondsSinceEpoch}'
        : normalized;
  }

  void setDesignSettings(CardDesignSettings settings) {
    designSettings.showLogo = settings.showLogo;
    designSettings.showStamp = settings.showStamp;
    designSettings.logoText = settings.logoText;
    designSettings.logoUrl = settings.logoUrl;
    designSettings.stampText = settings.stampText;
    _loadedLogoSource = null;
  }
}
