class StoreManagementPrivacy {
  const StoreManagementPrivacy._();

  static Map<String, dynamic> redactSnapshotForStaff(
    Map<String, dynamic> snapshot, {
    required bool canViewProfits,
  }) {
    if (canViewProfits) return Map<String, dynamic>.from(snapshot);

    final redacted = Map<String, dynamic>.from(snapshot);
    redacted['products'] = _list(snapshot['products']).map((product) {
      final safeProduct = Map<String, dynamic>.from(product);
      safeProduct['averagePurchaseCost'] = null;
      safeProduct['estimatedStockProfit'] = null;
      safeProduct['units'] = _list(product['units']).map((unit) {
        final safeUnit = Map<String, dynamic>.from(unit);
        safeUnit['purchasePrice'] = null;
        return safeUnit;
      }).toList();
      return safeProduct;
    }).toList();
    redacted['invoices'] = _list(snapshot['invoices']).map((invoice) {
      final safeInvoice = Map<String, dynamic>.from(invoice);
      safeInvoice['costTotal'] = null;
      safeInvoice['profitTotal'] = null;
      final isPurchase = invoice['type'] == 'purchase';
      if (isPurchase) {
        safeInvoice['subtotal'] = null;
        safeInvoice['discount'] = null;
        safeInvoice['total'] = null;
        safeInvoice['paidAmount'] = null;
        safeInvoice['dueAmount'] = null;
      }
      safeInvoice['items'] = _list(invoice['items']).map((item) {
        final safeItem = Map<String, dynamic>.from(item);
        safeItem['costTotal'] = null;
        safeItem['profitTotal'] = null;
        if (isPurchase) {
          safeItem['unitPrice'] = null;
          safeItem['lineTotal'] = null;
        }
        return safeItem;
      }).toList();
      return safeInvoice;
    }).toList();
    final purchaseInvoiceIds = _list(snapshot['invoices'])
        .where((invoice) => invoice['type'] == 'purchase')
        .map((invoice) => invoice['id']?.toString())
        .whereType<String>()
        .toSet();
    redacted['payments'] = _list(snapshot['payments']).map((payment) {
      final safePayment = Map<String, dynamic>.from(payment);
      final invoiceId = payment['invoiceId']?.toString();
      if (payment['direction'] == 'out' ||
          (invoiceId != null && purchaseInvoiceIds.contains(invoiceId))) {
        safePayment['amount'] = null;
      }
      return safePayment;
    }).toList();
    final summary = Map<String, dynamic>.from(
      snapshot['summary'] as Map? ?? const {},
    );
    summary['inventoryValue'] = null;
    summary['profitToday'] = null;
    redacted['summary'] = summary;
    return redacted;
  }

  static List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : <Map<String, dynamic>>[];
}
