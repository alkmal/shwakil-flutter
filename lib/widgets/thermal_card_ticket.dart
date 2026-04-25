import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';

import '../models/card_model.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';

class ThermalCardTicket extends StatelessWidget {
  const ThermalCardTicket({
    super.key,
    required this.card,
    required this.issuerName,
    required this.title,
  });

  final VirtualCard card;
  final String issuerName;
  final String title;

  String get _typeLabel {
    if (card.isDelivery) {
      return 'بطاقة توصيل';
    }
    if (card.isAppointment) {
      return 'تذكرة موعد';
    }
    if (card.isQueueTicket) {
      return 'تذكرة طابور';
    }
    if (card.isSingleUse) {
      return 'بطاقة دخول';
    }
    return card.isPrivate ? 'بطاقة خاصة' : 'بطاقة عامة';
  }

  String get _originalTypeLabel {
    switch (card.resolvedOriginalCardType) {
      case 'delivery':
        return 'بطاقة توصيل';
      case 'appointment':
        return 'تذكرة موعد';
      case 'queue':
        return 'تذكرة طابور';
      case 'single_use':
        return 'بطاقة دخول';
      default:
        return 'بطاقة رصيد';
    }
  }

  String get _valueLabel {
    return card.isSingleUse
        ? 'استخدام مرة واحدة'
        : card.isAppointment && card.value <= 0
        ? 'حجز موعد'
        : card.isQueueTicket && card.value <= 0
        ? 'تنظيم دور'
        : CurrencyFormatter.ils(card.value);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: 320,
        color: Colors.white,
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.bodyBold.copyWith(
                color: Colors.black,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _typeLabel,
              textAlign: TextAlign.center,
              style: AppTheme.bodyAction.copyWith(
                color: Colors.black87,
                fontSize: 13,
              ),
            ),
            if (card.isLoadedAsDeliveryForDriver) ...[
              const SizedBox(height: 6),
              Text(
                'محمّلة للسائق كسلوك توصيل. النوع الأصلي: $_originalTypeLabel',
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(
                  color: Colors.red.shade700,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (card.title?.trim().isNotEmpty == true) ...[
              Text(
                card.title!.trim(),
                textAlign: TextAlign.center,
                style: AppTheme.bodyBold.copyWith(
                  color: Colors.black,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'القيمة',
                    style: AppTheme.caption.copyWith(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _valueLabel,
                    style: AppTheme.h3.copyWith(
                      color: Colors.black,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            BarcodeWidget(
              data: card.barcode,
              barcode: Barcode.code128(),
              drawText: false,
              height: 56,
              color: Colors.black,
            ),
            const SizedBox(height: 6),
            Text(
              card.barcode,
              textAlign: TextAlign.center,
              style: AppTheme.bodyBold.copyWith(
                color: Colors.black,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'الجهة: $issuerName',
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(
                color: Colors.black87,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            if (card.validUntil != null) ...[
              Text(
                'تنتهي: ${card.validUntil!.toLocal().year}-${card.validUntil!.toLocal().month.toString().padLeft(2, '0')}-${card.validUntil!.toLocal().day.toString().padLeft(2, '0')} ${card.validUntil!.toLocal().hour.toString().padLeft(2, '0')}:${card.validUntil!.toLocal().minute.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(
                  color: Colors.black54,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              'التاريخ: ${card.createdAt.year}-${card.createdAt.month.toString().padLeft(2, '0')}-${card.createdAt.day.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: AppTheme.caption.copyWith(
                color: Colors.black54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
