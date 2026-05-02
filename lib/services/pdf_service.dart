import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/index.dart';
import '../utils/currency_formatter.dart';

class CardDesignSettings {
  bool showLogo;
  bool showStamp;
  String? logoText;
  String? logoUrl;
  String? stampText;
  String? valueUnitText;
  CardDesignSettings({
    this.showLogo = true,
    this.showStamp = true,
    this.logoText = 'شواكل',
    this.stampText = 'صالح للتداول',
    this.valueUnitText,
  });
}

class PdfSaveResult {
  const PdfSaveResult(this.path);

  final String path;
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
  static const double _a4PagePrintMargin = 3.5 * PdfPageFormat.mm;
  static const double _cardCutGap = 0.6 * PdfPageFormat.mm;
  static const PdfColor _pageBackground = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor _cardBackground = PdfColor.fromInt(0xFFFFF8EC);
  static const PdfColor _titleColor = PdfColor.fromInt(0xFF16302B);
  static const String _fallbackBrandName = 'شواكل';
  static const String _appDomain = 'shwakil.alkmal.com';
  static const String _trustedDigitalCardText = 'شواكل بطاقتك الرقمية الموثقة';
  static const int _maxBrandNameLength = 24;
  static const int _maxValueUnitLength = 10;
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

  String _resolvedStampText() {
    final text = designSettings.stampText?.trim() ?? '';
    return text.isEmpty ? 'صالح للتداول' : text;
  }

  String _brandName(String? printedBy) {
    final displayName = (printedBy ?? '').trim();
    final rawName = displayName.isNotEmpty
        ? displayName
        : (designSettings.logoText?.trim() ?? '');
    final resolvedName = rawName.isEmpty ? _fallbackBrandName : rawName;
    return _limitText(resolvedName, _maxBrandNameLength);
  }

  String _limitText(String value, int maxLength) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return normalized.substring(0, maxLength).trim();
  }

  String _valueUnitText() {
    final text = designSettings.valueUnitText?.trim() ?? '';
    return _limitText(text, _maxValueUnitLength);
  }

  String _formattedCardValue(VirtualCard card) {
    final valueText = CurrencyFormatter.formatAmount(card.value);
    final unitText = _valueUnitText();
    if (unitText.isEmpty) {
      return valueText;
    }
    final numericValue = card.value == card.value.roundToDouble()
        ? card.value.round().toString()
        : card.value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$numericValue $unitText';
  }

  String _internalUseLabel(VirtualCard card) {
    return _isTicketCard(card)
        ? _cardSubtitle(card)
        : 'بطاقة رقمية للاستخدام الداخلي';
  }

  pw.TextDirection _cardTitleDirection(VirtualCard card) {
    return !_isTicketCard(card) && _valueUnitText().isNotEmpty
        ? pw.TextDirection.ltr
        : pw.TextDirection.rtl;
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

  bool _isVisuallyPrivate(VirtualCard card) =>
      card.isPrivate || _isLocationSpecific(card) || _isTicketCard(card);

  String _privacyLabel(VirtualCard card) =>
      _isVisuallyPrivate(card) ? 'خاصة' : 'عامة';

  String _cardKindLabel(VirtualCard card) {
    if (card.isDelivery) {
      return 'بطاقة رصيد توصيل';
    }
    if (card.isSingleUse) {
      return 'بطاقة خاصة';
    }
    if (card.isAppointment) {
      return 'تذكرة موعد';
    }
    if (card.isQueueTicket) {
      return 'تذكرة طابور';
    }
    return 'بطاقة رصيد';
  }

  String _cardSubtitle(VirtualCard card) {
    if (card.isDelivery) {
      return _isVisuallyPrivate(card)
          ? 'بطاقة توصيل خاصة لمستفيدين محددين'
          : 'بطاقة رصيد عامة للتوصيل والمدفوعات';
    }
    if (card.isSingleUse) {
      return 'بطاقة خاصة داخل النظام';
    }
    if (card.isAppointment) {
      return 'تذكرة موعد خاصة لمستفيدين محددين';
    }
    if (card.isQueueTicket) {
      return 'تذكرة طابور خاصة لمستفيدين محددين';
    }
    return _isVisuallyPrivate(card)
        ? 'بطاقة رصيد خاصة لمستفيدين محددين'
        : 'بطاقة رصيد عامة';
  }

  String _cardBadgeLabel(VirtualCard card) {
    if (card.isSingleUse) {
      return 'بطاقة خاصة';
    }
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
    return _formattedCardValue(card);
  }

  pw.Widget _topHeader(
    _DenominationPalette palette, {
    required bool compact,
    required VirtualCard card,
    String? printedBy,
  }) {
    final badgeFont = compact ? 4.8 : 8.8;
    return pw.SizedBox(
      height: compact ? 12 : 24,
      child: pw.Stack(
        children: [
          pw.Positioned(
            right: 0,
            top: 0,
            child: pw.Container(
              padding: pw.EdgeInsets.symmetric(
                horizontal: compact ? 3.8 : 8,
                vertical: compact ? 1.3 : 3,
              ),
              decoration: pw.BoxDecoration(
                color: _isVisuallyPrivate(card)
                    ? const PdfColor.fromInt(0xFFFFE4E6)
                    : palette.soft,
                borderRadius: pw.BorderRadius.circular(compact ? 6 : 10),
                border: pw.Border.all(
                  color: _isVisuallyPrivate(card)
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
                  color: _isVisuallyPrivate(card)
                      ? const PdfColor.fromInt(0xFFBE123C)
                      : palette.primary,
                ),
              ),
            ),
          ),
          pw.Positioned(
            left: 0,
            top: compact ? 0.3 : 1,
            child: pw.SizedBox(
              width: compact ? 52 : 124,
              child: pw.Text(
                _brandName(printedBy),
                maxLines: 2,
                textAlign: pw.TextAlign.left,
                textDirection: pw.TextDirection.rtl,
                style: _textStyle(
                  fontSize: compact ? 5.4 : 10.2,
                  bold: true,
                  color: palette.primary,
                ),
              ),
            ),
          ),
        ],
      ),
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

  pw.Widget _cardTitleWithLogo(
    VirtualCard card,
    _DenominationPalette palette, {
    required bool compact,
  }) {
    final isTicket = _isTicketCard(card);
    final logoSize = compact ? 23.0 : 50.0;
    final titleFontSize = isTicket
        ? (compact ? 7.1 : 12.5)
        : (compact ? 15.0 : 26.0);
    final logoImage = _accountLogoImage ?? _defaultLogoImage;

    return pw.SizedBox(
      height: compact ? 28 : 60,
      child: pw.Stack(
        children: [
          if (designSettings.showLogo && logoImage != null)
            pw.Positioned(
              right: 0,
              top: compact ? 2.5 : 5,
              child: _buildHeaderLogoBox(
                logoImage,
                size: logoSize,
                compact: compact,
              ),
            ),
          pw.Center(
            child: pw.Padding(
              padding: pw.EdgeInsets.only(
                right: designSettings.showLogo
                    ? logoSize + (compact ? 3 : 8)
                    : 0,
                left: designSettings.showLogo
                    ? logoSize + (compact ? 3 : 8)
                    : 0,
              ),
              child: pw.Text(
                _cardTitle(card),
                maxLines: 2,
                textAlign: pw.TextAlign.center,
                textDirection: _cardTitleDirection(card),
                style: _textStyle(
                  fontSize: titleFontSize,
                  bold: true,
                  color: isTicket ? palette.primary : palette.value,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _postBarcodeFooter({required bool compact}) {
    return pw.Column(
      children: [
        pw.Text(
          _resolvedStampText(),
          textAlign: pw.TextAlign.center,
          textDirection: pw.TextDirection.rtl,
          style: _textStyle(
            fontSize: compact ? 4.9 : 9.4,
            bold: true,
            color: const PdfColor.fromInt(0xFF991B1B),
          ),
        ),
        pw.SizedBox(height: compact ? 0.3 : 1.2),
        pw.Text(
          _appDomain,
          maxLines: 1,
          textAlign: pw.TextAlign.center,
          textDirection: pw.TextDirection.ltr,
          style: _textStyle(
            fontSize: compact ? 5.5 : 10.5,
            bold: true,
            color: _titleColor,
            font: pw.Font.helveticaBold(),
          ),
        ),
        pw.SizedBox(height: compact ? 0.35 : 1.1),
        pw.Text(
          _trustedDigitalCardText,
          maxLines: 1,
          textAlign: pw.TextAlign.center,
          textDirection: pw.TextDirection.rtl,
          style: _textStyle(
            fontSize: compact ? 5.1 : 10,
            bold: true,
            color: _titleColor,
          ),
        ),
      ],
    );
  }

  String _dateLabel(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';
  }

  pw.Widget _cardMetadataFooter(
    VirtualCard card, {
    String? printedBy,
    required int serialNumber,
    required _DenominationPalette palette,
    required bool compact,
  }) {
    final origin = (printedBy ?? '').trim();
    final printedByLabel = origin.isEmpty
        ? 'الجهة الطابعة: غير محددة'
        : 'الجهة الطابعة: $origin';
    final originLabel = origin.isEmpty ? 'غير محددة' : origin;
    final serialLabel = serialNumber.toString().padLeft(4, '0');
    final fontSize = compact ? 4.1 : 8.0;
    final boldFontSize = compact ? 4.3 : 8.2;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: compact ? 3 : 6,
            vertical: compact ? 1.2 : 2.2,
          ),
          decoration: pw.BoxDecoration(
            color: palette.soft,
            borderRadius: pw.BorderRadius.circular(compact ? 4 : 6),
          ),
          child: pw.Text(
            'التسلسل: $serialLabel',
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.rtl,
            style: _textStyle(
              fontSize: boldFontSize,
              bold: true,
              color: palette.primary,
            ),
          ),
        ),
        pw.SizedBox(height: compact ? 0.6 : 1.5),
        pw.Text(
          printedByLabel,
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
          style: _textStyle(
            fontSize: boldFontSize,
            bold: true,
            color: palette.primary,
          ),
        ),
        pw.SizedBox(height: compact ? 0.3 : 0.8),
        pw.Text(
          'تاريخ الإصدار: ${_dateLabel(card.createdAt)}',
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
          style: _textStyle(
            fontSize: fontSize,
            color: const PdfColor.fromInt(0xFF64748B),
          ),
        ),
        pw.Text(
          'منشأ البطاقة: $originLabel',
          maxLines: 1,
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
          style: _textStyle(
            fontSize: fontSize,
            color: const PdfColor.fromInt(0xFF64748B),
          ),
        ),
        pw.Text(
          'نوع البطاقة: ${_cardTypeLabel(card)}',
          maxLines: 1,
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
          style: _textStyle(
            fontSize: fontSize,
            bold: true,
            color: palette.primary,
          ),
        ),
        if (card.issueCost > 0)
          pw.Text(
            !_isTicketCard(card)
                ? 'رسوم عند الاستخدام: ${CurrencyFormatter.formatAmount(card.issueCost)}'
                : 'تكلفة الإصدار: ${CurrencyFormatter.formatAmount(card.issueCost)}',
            maxLines: 1,
            textAlign: pw.TextAlign.right,
            textDirection: pw.TextDirection.rtl,
            style: _textStyle(
              fontSize: fontSize,
              bold: true,
              color: palette.primary,
            ),
          ),
      ],
    );
  }

  String _cardTypeLabel(VirtualCard card) {
    if (_isLocationSpecific(card)) {
      return '${_cardKindLabel(card)} مخصصة لمكان محدد';
    }
    return '${_cardKindLabel(card)} ${_privacyLabel(card)}';
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
          margin: const pw.EdgeInsets.all(_a4PagePrintMargin),
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

  /// Creates a single-page A4 PDF that renders the exact same "small card"
  /// layout used inside the 30-cards-per-page sheet. This is used for an
  /// accurate on-screen preview (rasterized from this PDF) so the user sees
  /// exactly what will be printed.
  Future<pw.Document> createSmallCardSheetPreviewPDF(
    VirtualCard card, {
    String? printedBy,
    int serialNumber = 1,
  }) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();

    final availableWidth = PdfPageFormat.a4.width - (2 * _a4PagePrintMargin);
    final availableHeight = PdfPageFormat.a4.height - (2 * _a4PagePrintMargin);
    final cellWidth = availableWidth / _columnsPerPage;
    final cellHeight = availableHeight / _rowsPerPage;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(cellWidth, cellHeight),
        margin: pw.EdgeInsets.zero,
        theme: pw.ThemeData.withFont(
          base: _regularFont!,
          bold: _boldFont!,
          fontFallback: [_regularFont!, _boldFont!],
        ),
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Container(
            color: _pageBackground,
            child: pw.SizedBox(
              width: cellWidth,
              height: cellHeight,
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(_cardCutGap),
                child: _buildSmallCardWidget(
                  card,
                  printedBy: printedBy,
                  serialNumber: serialNumber,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return pdf;
  }

  List<pw.Widget> _buildCardRows(
    List<VirtualCard> cards, {
    String? printedBy,
    int startSerialNumber = 1,
  }) {
    return List.generate(_rowsPerPage, (rowIndex) {
      return pw.Expanded(
        child: pw.Row(
          children: List.generate(_columnsPerPage, (columnIndex) {
            final cardIndex = (rowIndex * _columnsPerPage) + columnIndex;
            return pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(_cardCutGap),
                child: cardIndex < cards.length
                    ? _buildSmallCardWidget(
                        cards[cardIndex],
                        printedBy: printedBy,
                        serialNumber: startSerialNumber + cardIndex,
                      )
                    : pw.SizedBox.expand(),
              ),
            );
          }),
        ),
      );
    });
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
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _topHeader(
                    palette,
                    compact: true,
                    card: card,
                    printedBy: printedBy,
                  ),
                  pw.SizedBox(height: 1.8),
                  pw.Column(
                    children: [
                      _cardTitleWithLogo(card, palette, compact: true),
                      pw.SizedBox(height: 0.7),
                      pw.Text(
                        _internalUseLabel(card),
                        maxLines: 1,
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(
                          fontSize: 4.6,
                          color: const PdfColor.fromInt(0xFF64748B),
                        ),
                      ),
                      pw.SizedBox(height: 1.2),
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
                      if (designSettings.showStamp) ...[
                        pw.SizedBox(height: 0.4),
                        _postBarcodeFooter(compact: true),
                      ],
                    ],
                  ),
                  pw.Spacer(),
                  _cardMetadataFooter(
                    card,
                    printedBy: printedBy,
                    serialNumber: serialNumber,
                    palette: palette,
                    compact: true,
                  ),
                ],
              ),
            ),
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
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _topHeader(
                    palette,
                    compact: false,
                    card: card,
                    printedBy: printedBy,
                  ),
                  pw.SizedBox(height: 10),
                  pw.Column(
                    children: [
                      _cardTitleWithLogo(card, palette, compact: false),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        _internalUseLabel(card),
                        maxLines: 1,
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                        style: _textStyle(
                          fontSize: 8.6,
                          color: const PdfColor.fromInt(0xFF64748B),
                        ),
                      ),
                      pw.SizedBox(height: 7),
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
                      if (designSettings.showStamp) ...[
                        pw.SizedBox(height: 2),
                        _postBarcodeFooter(compact: false),
                      ],
                    ],
                  ),
                  pw.Spacer(),
                  _cardMetadataFooter(
                    card,
                    printedBy: printedBy,
                    serialNumber: serialNumber,
                    palette: palette,
                    compact: false,
                  ),
                ],
              ),
            ),
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

  Future<void> printPdfBytes(Uint8List pdfBytes) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }

  Future<PdfSaveResult> savePDF(pw.Document pdf, String filename) async {
    final safeName = _safeFileName(filename);
    final bytes = await pdf.save();
    if (kIsWeb) {
      final path = await FileSaver.instance.saveFile(
        name: safeName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      return PdfSaveResult(path.isEmpty ? '$safeName.pdf' : path);
    }

    final selectedPath = await FileSaver.instance.saveAs(
      name: safeName,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      throw Exception('لم يتم اختيار مكان لحفظ الملف.');
    }
    return PdfSaveResult(selectedPath);
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
    designSettings.valueUnitText = _limitText(
      settings.valueUnitText ?? '',
      _maxValueUnitLength,
    );
    _loadedLogoSource = null;
  }
}
