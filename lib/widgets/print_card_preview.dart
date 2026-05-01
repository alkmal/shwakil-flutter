import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../models/card_model.dart';
import '../services/pdf_service.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';

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

  static const double _a4CardAspectRatio = 42 / 49.5;
  static const double _printCardBaseWidth = 119.06;
  static const double _printCardBaseHeight = 140.32;

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

  bool get _isBalanceCard => !_isTicketCard;

  bool get _isVisuallyPrivate =>
      card.isPrivate || _isLocationSpecific || _isTicketCard;

  String get _privacyLabel => _isVisuallyPrivate ? 'خاصة' : 'عامة';

  String get _cardKindLabel {
    if (card.isDelivery) {
      return 'بطاقة رصيد توصيل';
    }
    if (card.isSingleUse) {
      return 'بطاقة خاصة لاستخدام واحد';
    }
    if (card.isAppointment) {
      return 'تذكرة موعد';
    }
    if (card.isQueueTicket) {
      return 'تذكرة طابور';
    }
    return 'بطاقة رصيد';
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
    if (card.isSingleUse) {
      return 'بطاقة خاصة';
    }
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
    return CurrencyFormatter.formatAmount(card.value);
  }

  String get _cardSubtitle {
    if (card.isDelivery) {
      return _isVisuallyPrivate
          ? 'بطاقة توصيل خاصة لمستفيدين محددين'
          : 'بطاقة رصيد عامة للتوصيل والمدفوعات';
    }
    if (card.isSingleUse) {
      return 'بطاقة خاصة لاستخدام واحد داخل النظام';
    }
    if (card.isAppointment) {
      return 'تذكرة موعد خاصة لمستفيدين محددين';
    }
    if (card.isQueueTicket) {
      return 'تذكرة طابور خاصة لمستفيدين محددين';
    }
    return _isVisuallyPrivate
        ? 'بطاقة رصيد خاصة لمستفيدين محددين'
        : 'بطاقة رصيد عامة - ${_valueInArabicWords(card.value)}';
  }

  String _valueInArabicWords(double value) {
    final rounded = value.round();
    if ((value - rounded).abs() < 0.001) {
      return _integerToArabicWords(rounded);
    }
    return CurrencyFormatter.formatAmount(value);
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
        '${card.createdAt.day.toString().padLeft(2, '0')}/${card.createdAt.month.toString().padLeft(2, '0')}/${card.createdAt.year.toString().padLeft(4, '0')}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AspectRatio(
        aspectRatio: _a4CardAspectRatio,
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: _printCardBaseWidth,
            height: _printCardBaseHeight,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8EC),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: palette.border),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    right: 0,
                    left: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: palette.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 4,
                    child: Opacity(
                      opacity: 0.12,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.primary),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 6,
                    child: Opacity(
                      opacity: 0.10,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.accent),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(3.4, 5.5, 3.4, 2.8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          palette: palette,
                          showLogo: false,
                          logoText: '',
                          subtitleText: '',
                          badgeText: _cardBadgeLabel,
                          logoUrl: designSettings.logoUrl,
                          isPrivate: _isVisuallyPrivate,
                        ),
                        const SizedBox(height: 2.6),
                        Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (designSettings.showLogo) ...[
                                  _LogoBox(
                                    logoUrl: designSettings.logoUrl,
                                    size: 26,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    _cardTitle,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: (_isTicketCard
                                            ? AppTheme.bodyBold
                                            : AppTheme.h1)
                                        .copyWith(
                                      fontSize: _isTicketCard ? 7.1 : 14.2,
                                      height: 1.05,
                                      color: _isTicketCard
                                          ? palette.primary
                                          : palette.value,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1.6),
                            Text(
                              _isTicketCard
                                  ? _cardSubtitle
                                  : 'بطاقة رقمية للاستخدام الداخلي',
                              textAlign: TextAlign.center,
                              style: AppTheme.caption.copyWith(
                                fontSize: 5.2,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            if (!_isTicketCard) ...[
                              const SizedBox(height: 1.5),
                              Text(
                                _cardSubtitle,
                                textAlign: TextAlign.center,
                                style: AppTheme.bodyBold.copyWith(
                                  fontSize: 5,
                                  color: palette.primary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 1.5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2.2,
                                vertical: 1.4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: palette.border,
                                  width: 0.9,
                                ),
                              ),
                              child: SizedBox(
                                height: 15,
                                child: BarcodeWidget(
                                  barcode: Barcode.code128(),
                                  data: card.barcode,
                                  drawText: false,
                                  color: const Color(0xFF16302B),
                                ),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              card.barcode,
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.ltr,
                              style: AppTheme.bodyBold.copyWith(
                                fontSize: 5.7,
                                color: const Color(0xFF16302B),
                                fontFamily: 'monospace',
                                letterSpacing: 0.3,
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
                                horizontal: 3,
                                vertical: 1.2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.soft,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'التسلسل: $_serialLabel',
                                textAlign: TextAlign.center,
                                style: AppTheme.bodyBold.copyWith(
                                  fontSize: 4.4,
                                  color: palette.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 0.7),
                            Text(
                              _printedByLabel,
                              textAlign: TextAlign.right,
                              style: AppTheme.bodyBold.copyWith(
                                fontSize: 4.2,
                                color: palette.primary,
                              ),
                            ),
                            const SizedBox(height: 0.4),
                            Text(
                              'تاريخ الإصدار: $dateText',
                              textAlign: TextAlign.right,
                              style: AppTheme.caption.copyWith(
                                fontSize: 4.1,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              'منشأ البطاقة: $_originLabel',
                              textAlign: TextAlign.right,
                              style: AppTheme.caption.copyWith(
                                fontSize: 4.1,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              'نوع البطاقة: $_cardTypeLabel',
                              textAlign: TextAlign.right,
                              style: AppTheme.caption.copyWith(
                                fontSize: 4.1,
                                color: palette.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (card.issueCost > 0)
                              Text(
                                _isBalanceCard
                                    ? 'رسوم عند الاستخدام: ${CurrencyFormatter.formatAmount(card.issueCost)}'
                                    : 'تكلفة الإصدار: ${CurrencyFormatter.formatAmount(card.issueCost)}',
                                textAlign: TextAlign.right,
                                style: AppTheme.caption.copyWith(
                                  fontSize: 4,
                                  color: palette.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            const SizedBox(height: 0.3),
                            Text(
                              'shwakil.alkmal.com',
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.ltr,
                              style: AppTheme.caption.copyWith(
                                fontSize: 4.2,
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
                      top: 20,
                      left: 1,
                      child: Transform.rotate(
                        angle: -0.22,
                        child: Opacity(
                          opacity: 0.38,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3.6,
                              vertical: 1.8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFFDC2626),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2.2,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFDC2626),
                                  width: 0.45,
                                ),
                                borderRadius: BorderRadius.circular(2.4),
                              ),
                              child: Text(
                                _stampText,
                                textAlign: TextAlign.center,
                                style: AppTheme.caption.copyWith(
                                  fontSize: 4.2,
                                  color: const Color(0xFFDC2626),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
    required this.subtitleText,
    required this.badgeText,
    required this.logoUrl,
    required this.isPrivate,
  });

  final _PrintPreviewPalette palette;
  final bool showLogo;
  final String logoText;
  final String subtitleText;
  final String badgeText;
  final String? logoUrl;
  final bool isPrivate;

  @override
  Widget build(BuildContext context) {
    final resolvedLogoUrl = logoUrl?.trim() ?? '';
    final hasNetworkLogo = resolvedLogoUrl.isNotEmpty;
    final hasHeaderBrand =
        showLogo || logoText.trim().isNotEmpty || subtitleText.trim().isNotEmpty;
    if (!hasHeaderBrand) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3.8, vertical: 1.3),
          decoration: BoxDecoration(
            color: isPrivate ? const Color(0xFFFFE4E6) : palette.soft,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isPrivate ? const Color(0xFFFB7185) : palette.border,
              width: 0.45,
            ),
          ),
          child: Text(
            badgeText,
            style: AppTheme.caption.copyWith(
              fontSize: 4.8,
              fontWeight: FontWeight.w800,
              color: isPrivate ? const Color(0xFFBE123C) : palette.primary,
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3.8, vertical: 1.3),
          decoration: BoxDecoration(
            color: isPrivate ? const Color(0xFFFFE4E6) : palette.soft,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isPrivate ? const Color(0xFFFB7185) : palette.border,
              width: 0.45,
            ),
          ),
          child: Text(
            badgeText,
            style: AppTheme.caption.copyWith(
              fontSize: 4.8,
              fontWeight: FontWeight.w800,
              color: isPrivate ? const Color(0xFFBE123C) : palette.primary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showLogo) ...[
                if (hasNetworkLogo) ...[
                  _LogoBox(logoUrl: resolvedLogoUrl),
                  const SizedBox(width: 4),
                ],
                const _LogoBox(logoUrl: null),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      logoText,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyBold.copyWith(
                        fontSize: 7.2,
                        height: 1.15,
                        color: palette.primary,
                      ),
                    ),
                    const SizedBox(height: 1.2),
                    Text(
                      subtitleText,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                        fontSize: 4.2,
                        height: 1.25,
                        color: const Color(0xFF64748B),
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
}

class _LogoBox extends StatelessWidget {
  const _LogoBox({required this.logoUrl, this.size = 24});

  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = logoUrl?.trim() ?? '';
    final hasNetworkLogo = resolvedUrl.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasNetworkLogo
          ? Padding(
              padding: const EdgeInsets.all(1.8),
              child: Image.network(
                resolvedUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const _FallbackLogo(),
              ),
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
      padding: const EdgeInsets.all(1.8),
      child: Image.asset('assets/images/shwakel_app_icon.png'),
    );
  }
}
