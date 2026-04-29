import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../models/card_model.dart';
import '../services/pdf_service.dart';
import '../utils/app_theme.dart';

class _PrintPreviewPalette {
  final Color primary;
  final Color value;
  final Color soft;
  final Color border;
  final Color accent;

  const _PrintPreviewPalette({
    required this.primary,
    required this.value,
    required this.soft,
    required this.border,
    required this.accent,
  });
}

class PrintCardPreview extends StatelessWidget {
  const PrintCardPreview({
    super.key,
    required this.card,
    required this.serialNumber,
    required this.printedBy,
    required this.designSettings,
  });

  final VirtualCard card;
  final int serialNumber;
  final String printedBy;
  final CardDesignSettings designSettings;

  static const List<_PrintPreviewPalette> _palettes = [
    _PrintPreviewPalette(
      primary: Color(0xFF0F766E),
      value: Color(0xFF047857),
      soft: Color(0xFFDDF7F1),
      border: Color(0xFF5EEAD4),
      accent: Color(0xFF14B8A6),
    ),
    _PrintPreviewPalette(
      primary: Color(0xFF0F766E),
      value: Color(0xFF1E40AF),
      soft: Color(0xFFCCFBF1),
      border: Color(0xFF93C5FD),
      accent: Color(0xFF60A5FA),
    ),
    _PrintPreviewPalette(
      primary: Color(0xFFB45309),
      value: Color(0xFF92400E),
      soft: Color(0xFFFFEDD5),
      border: Color(0xFFFDBA74),
      accent: Color(0xFFFB923C),
    ),
    _PrintPreviewPalette(
      primary: Color(0xFFBE123C),
      value: Color(0xFF9F1239),
      soft: Color(0xFFFFE4E6),
      border: Color(0xFFFDA4AF),
      accent: Color(0xFFFB7185),
    ),
  ];

  _PrintPreviewPalette get _palette {
    final roundedValue = card.value.round();
    final index = roundedValue > 0 ? (roundedValue - 1) % _palettes.length : 0;
    return _palettes[index];
  }

  bool get _isLocationSpecific {
    final scope = card.visibilityScope.trim().toLowerCase();
    return scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
  }

  bool get _isTicketCard =>
      card.isSingleUse || card.isAppointment || card.isQueueTicket;

  String get _privacyLabel => card.isPrivate ? 'خاصة' : 'عامة';

  String get _cardKindLabel {
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

  String get _logoText {
    final text = designSettings.logoText?.trim() ?? '';
    return text.isEmpty ? 'شواكل' : text;
  }

  String get _stampText {
    final text = designSettings.stampText?.trim() ?? '';
    return text.isEmpty ? 'صالح للتداول' : text;
  }

  String get _cardTypeLabel {
    if (_isLocationSpecific) {
      return '$_cardKindLabel مخصصة لمكان محدد';
    }
    return '$_cardKindLabel $_privacyLabel';
  }

  String get _cardBadgeLabel {
    if (_isLocationSpecific) {
      return 'مكان محدد - $_cardKindLabel';
    }
    return '$_privacyLabel - $_cardKindLabel';
  }

  String get _cardTitle {
    if (_isTicketCard) {
      final title = card.title?.trim() ?? '';
      return title.isNotEmpty ? title : _cardKindLabel;
    }
    return '${card.value.toStringAsFixed(2)} شيكل';
  }

  String get _cardSubtitle {
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
    return number.toString();
  }

  String get _printedByLabel {
    final name = printedBy.trim();
    return name.isEmpty ? 'الجهة الطابعة: غير محددة' : 'الجهة الطابعة: $name';
  }

  String get _originLabel {
    final origin = printedBy.trim();
    return origin.isEmpty ? 'غير محددة' : origin;
  }

  String get _serialLabel => serialNumber.toString().padLeft(4, '0');

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final dateText =
        '${card.createdAt.year.toString().padLeft(4, '0')}-${card.createdAt.month.toString().padLeft(2, '0')}-${card.createdAt.day.toString().padLeft(2, '0')}';

    return AspectRatio(
      aspectRatio: 0.814,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EC),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: palette.soft, width: 1),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              left: 0,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: palette.primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 22,
              left: 14,
              child: Opacity(
                opacity: 0.10,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.primary, width: 1.2),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 22,
              child: Opacity(
                opacity: 0.10,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.accent, width: 1.2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    palette: palette,
                    showLogo: designSettings.showLogo,
                    logoText: _logoText,
                    badgeText: _cardBadgeLabel,
                    logoUrl: designSettings.logoUrl,
                    isPrivate: card.isPrivate,
                  ),
                  const Spacer(),
                  Column(
                    children: [
                      if (_isTicketCard)
                        Text(
                          _cardTitle,
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyBold.copyWith(
                            fontSize: 18,
                            color: palette.primary,
                          ),
                        ),
                      Text(
                        _isTicketCard
                            ? _cardSubtitle
                            : 'بطاقة رقمية للاستخدام الداخلي',
                        textAlign: TextAlign.center,
                        style: AppTheme.caption.copyWith(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      if (!_isTicketCard) ...[
                        const SizedBox(height: 10),
                        Text(
                          _cardTitle,
                          textAlign: TextAlign.center,
                          style: AppTheme.h1.copyWith(
                            fontSize: 32,
                            color: palette.value,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _cardSubtitle,
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyBold.copyWith(
                            fontSize: 13,
                            color: palette.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        card.isDelivery
                            ? 'بطاقة رصيد عامة يمكن استخدامها للمدفوعات'
                            : _isTicketCard
                            ? 'صالحة للمستفيدين المحددين فقط'
                            : 'قيمة داخلية صالحة للاستخدام داخل النظام',
                        textAlign: TextAlign.center,
                        style: AppTheme.caption.copyWith(
                          fontSize: 11,
                          color: const Color(0xFF16302B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.border),
                        ),
                        child: SizedBox(
                          height: 56,
                          child: BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: card.barcode,
                            drawText: false,
                            color: const Color(0xFF16302B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        card.barcode,
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyBold.copyWith(
                          fontSize: 13,
                          color: const Color(0xFF16302B),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: palette.soft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'الرقم المتسلسل: $_serialLabel',
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyBold.copyWith(
                            fontSize: 12,
                            color: palette.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _printedByLabel,
                        textAlign: TextAlign.right,
                        style: AppTheme.bodyBold.copyWith(
                          fontSize: 11,
                          color: palette.primary,
                        ),
                      ),
                      Text(
                        'نوع البطاقة: $_cardTypeLabel',
                        textAlign: TextAlign.right,
                        style: AppTheme.caption.copyWith(
                          fontSize: 10.5,
                          color: palette.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (card.issueCost > 0)
                        Text(
                          'تكلفة الإصدار: ${card.issueCost.toStringAsFixed(2)} شيكل',
                          textAlign: TextAlign.right,
                          style: AppTheme.caption.copyWith(
                            fontSize: 10,
                            color: palette.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(height: 3),
                      Text(
                        'تاريخ الإصدار: $dateText',
                        textAlign: TextAlign.right,
                        style: AppTheme.caption.copyWith(
                          fontSize: 10.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        'منشأ البطاقة: $_originLabel',
                        textAlign: TextAlign.right,
                        style: AppTheme.caption.copyWith(
                          fontSize: 10.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'shwakil.alkmal.com',
                        textAlign: TextAlign.center,
                        style: AppTheme.caption.copyWith(
                          fontSize: 11,
                          color: palette.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (designSettings.showStamp)
              Positioned(
                top: 74,
                left: 10,
                child: Transform.rotate(
                  angle: -0.22,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.40),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _stampText,
                      style: AppTheme.caption.copyWith(
                        fontSize: 10,
                        color: const Color(0xFFDC2626).withValues(alpha: 0.84),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.palette,
    required this.showLogo,
    required this.logoText,
    required this.badgeText,
    required this.logoUrl,
    required this.isPrivate,
  });

  final _PrintPreviewPalette palette;
  final bool showLogo;
  final String logoText;
  final String badgeText;
  final String? logoUrl;
  final bool isPrivate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isPrivate ? const Color(0xFFFFE4E6) : palette.soft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPrivate ? const Color(0xFFFB7185) : palette.border,
            ),
          ),
          child: Text(
            badgeText,
            style: AppTheme.caption.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: isPrivate ? const Color(0xFFBE123C) : palette.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (showLogo) ...[
                _LogoBox(logoUrl: logoUrl),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  logoText,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyBold.copyWith(
                    fontSize: 18,
                    color: const Color(0xFF16302B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogoBox extends StatelessWidget {
  const _LogoBox({required this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = logoUrl?.trim() ?? '';
    final hasNetworkLogo = resolvedUrl.isNotEmpty;
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasNetworkLogo
          ? Image.network(
              resolvedUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const _FallbackLogo(),
            )
          : const _FallbackLogo(),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Image.asset('assets/images/shwakel_app_icon.png'),
    );
  }
}
