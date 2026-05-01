import 'package:flutter/widgets.dart';

import '../localization/app_localization.dart';

/// Central place for permission labels and their explanations.
///
/// We intentionally keep this in one file because the same permissions are
/// shown in multiple screens (admin customer, sub-users, settings), and we
/// want consistent wording.
class PermissionCatalog {
  static String label(BuildContext context, String key) {
    final l = context.loc;
    final localizedKey = _localizedLabels[key];
    if (localizedKey != null) {
      return l.tr(localizedKey);
    }
    return _arabicLabels[key] ?? key;
  }

  static String description(BuildContext context, String key) {
    final l = context.loc;
    final localizedKey = _localizedDescriptions[key];
    if (localizedKey != null) {
      return l.tr(localizedKey);
    }
    return _arabicDescriptions[key] ?? '';
  }

  // Some screens already ship localized strings (sub users screen).
  static const Map<String, String> _localizedLabels = {
    'canTransfer': 'screens_sub_users_screen.073',
    'canWithdraw': 'screens_sub_users_screen.074',
    'canScanCards': 'screens_sub_users_screen.075',
    'canRedeemCards': 'screens_sub_users_screen.076',
    'canOfflineCardScan': 'screens_sub_users_screen.077',
    'canRequestCardPrinting': 'screens_sub_users_screen.078',
    'canReviewCards': 'screens_sub_users_screen.079',
    'canReadOwnPrivateCardsOnly': 'screens_sub_users_screen.131',
  };

  static const Map<String, String> _localizedDescriptions = {};

  static const Map<String, String> _arabicLabels = {
    'canViewBalance': 'عرض الرصيد',
    'canViewTransactions': 'عرض الحركات المالية',
    'canViewInventory': 'عرض المخزون',
    'canViewQuickTransfer': 'إظهار خدمة التحويل السريع',
    'canTransfer': 'تحويل الرصيد',
    'canWithdraw': 'طلب السحب',
    'canRedeemCards': 'استرداد/سحب رصيد البطاقات',
    'canIssueCards': 'إصدار البطاقات',
    'canIssueSubShekelCards': 'إصدار بطاقات منخفضة القيمة',
    'canIssueHighValueCards': 'إصدار بطاقات عالية القيمة',
    'canIssuePrivateCards': 'إصدار بطاقات خاصة',
    'canIssueSingleUseTickets': 'إصدار تذاكر دخول لمرة واحدة',
    'canIssueAppointmentTickets': 'إصدار تذاكر مواعيد',
    'canIssueQueueTickets': 'إصدار تذاكر طوابير',
    'canScanCards': 'قراءة البطاقات',
    'canOfflineCardScan': 'قراءة البطاقات أوفلاين',
    'canReviewCards': 'مراجعة البطاقات',
    'canViewPrivateCards': 'عرض البطاقات الخاصة',
    'canReadOwnPrivateCardsOnly': 'قراءة بطاقاته الخاصة فقط',
    'canDeleteCards': 'حذف البطاقات',
    'canResellCards': 'إعادة بيع البطاقات',
    'canRequestCardPrinting': 'طلب طباعة البطاقات',
    'canManageCardPrintRequests': 'إدارة طلبات طباعة البطاقات',
    'canUsePrepaidMultipayCards': 'استخدام بطاقات الدفع المسبق',
    'canAcceptPrepaidMultipayPayments': 'قبول دفع البطاقات المسبقة',
    'canUsePrepaidMultipayNfc': 'استخدام NFC للبطاقات المسبقة',
    'canViewCustomers': 'عرض المستخدمين',
    'canLookupMembers': 'البحث عن الأعضاء',
    'canManageUsers': 'إدارة المستخدمين',
    'canFinanceTopup': 'شحن أرصدة المستخدمين (مالية)',
    'canManageMarketingAccounts': 'إدارة حسابات التسويق',
    'canManageSubUsers': 'إدارة المستخدمين الفرعيين',
    'canManageLocations': 'إدارة الفروع والمواقع',
    'canManageSystemSettings': 'إدارة إعدادات النظام',
    'canReviewWithdrawals': 'مراجعة طلبات السحب',
    'canReviewTopups': 'مراجعة عمليات الشحن',
    'canReviewDevices': 'مراجعة الأجهزة',
    'canExportCustomerTransactions': 'تصدير حركات المستخدمين',
    'canViewAffiliateCenter': 'عرض مركز التسويق',
    'canManageDebtBook': 'إدارة دفتر الديون',
  };

  static const Map<String, String> _arabicDescriptions = {
    'canViewBalance': 'إظهار الرصيد داخل التطبيق.',
    'canViewTransactions': 'السماح بعرض سجل الحركات المالية.',
    'canViewInventory': 'السماح بعرض/إدارة المخزون المرتبط بالحساب.',
    'canViewQuickTransfer': 'إظهار شاشة التحويل السريع في القائمة.',
    'canTransfer': 'تنفيذ تحويلات رصيد (إرسال).',
    'canWithdraw': 'إنشاء طلب سحب رصيد من المحفظة.',
    'canRedeemCards': 'اعتماد البطاقة وتحويل قيمتها إلى رصيد (استرداد).',
    'canIssueCards': 'إنشاء/إصدار بطاقات جديدة.',
    'canIssueSubShekelCards': 'السماح بإصدار بطاقات بقيم صغيرة جدا.',
    'canIssueHighValueCards': 'السماح بإصدار بطاقات بقيم عالية.',
    'canIssuePrivateCards': 'السماح بإصدار بطاقات خاصة (مقيدة على مستخدمين).',
    'canIssueSingleUseTickets': 'السماح بإصدار تذكرة/بطاقة خاصة.',
    'canIssueAppointmentTickets': 'السماح بإصدار تذكرة مواعيد بوقت.',
    'canIssueQueueTickets': 'السماح بإصدار تذكرة طابور.',
    'canScanCards': 'السماح بقراءة/فحص البطاقات.',
    'canOfflineCardScan': 'السماح بالفحص بدون اتصال ومزامنة لاحقاً.',
    'canReviewCards': 'السماح بمراجعة/تدقيق عمليات البطاقات.',
    'canViewPrivateCards': 'السماح بعرض/التعامل مع البطاقات الخاصة.',
    'canReadOwnPrivateCardsOnly':
        'يقيد الاستخدام على بطاقات هذا الحساب الخاصة فقط ولا يسمح ببطاقات الآخرين.',
    'canDeleteCards': 'السماح بحذف البطاقات (حسب قيود النظام).',
    'canResellCards': 'إعادة تفعيل/إعادة بيع بطاقة مستخدمة.',
    'canRequestCardPrinting': 'إنشاء طلبات طباعة بطاقات.',
    'canManageCardPrintRequests': 'إدارة واعتماد تجهيز/تسليم طلبات الطباعة.',
    'canUsePrepaidMultipayCards': 'استخدام بطاقات الدفع المسبق داخل التطبيق.',
    'canAcceptPrepaidMultipayPayments':
        'استقبال/قبول مدفوعات الدفع المسبق كتاجر.',
    'canUsePrepaidMultipayNfc': 'تمكين عمليات الدفع المسبق عبر NFC.',
    'canViewCustomers': 'الوصول لقائمة المستخدمين/العملاء في لوحة الإدارة.',
    'canLookupMembers': 'البحث عن أعضاء حسب الاسم/الهاتف.',
    'canManageUsers': 'تعديل حسابات المستخدمين وصلاحياتهم.',
    'canFinanceTopup': 'شحن أرصدة المستخدمين من حساب المالية.',
    'canManageMarketingAccounts': 'إدارة حسابات التسويق والعمولات.',
    'canManageSubUsers': 'إنشاء/تعديل المستخدمين الفرعيين.',
    'canManageLocations': 'إدارة الفروع/المواقع المعتمدة.',
    'canManageSystemSettings': 'تعديل إعدادات النظام العامة.',
    'canReviewWithdrawals': 'مراجعة واعتماد/رفض طلبات السحب.',
    'canReviewTopups': 'مراجعة واعتماد/رفض طلبات الشحن.',
    'canReviewDevices': 'مراجعة واعتماد الأجهزة المرتبطة بالحسابات.',
    'canExportCustomerTransactions': 'تصدير حركات المستخدمين (CSV).',
    'canViewAffiliateCenter': 'فتح شاشة مركز التسويق.',
    'canManageDebtBook': 'إدارة دفتر الديون للحساب.',
  };
}
