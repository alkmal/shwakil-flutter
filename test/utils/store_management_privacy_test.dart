import 'package:flutter_test/flutter_test.dart';
import 'package:virtual_currency_cards/utils/store_management_privacy.dart';

void main() {
  test('staff snapshots hide purchase costs and margin data recursively', () {
    final snapshot = <String, dynamic>{
      'products': [
        {
          'averagePurchaseCost': 7.5,
          'estimatedStockProfit': 30.0,
          'defaultSalePrice': 10.0,
          'units': [
            {'purchasePrice': 7.5, 'salePrice': 10.0},
          ],
        },
      ],
      'invoices': [
        {
          'id': 'purchase-invoice',
          'type': 'purchase',
          'costTotal': 15.0,
          'profitTotal': 0.0,
          'subtotal': 15.0,
          'discount': 1.0,
          'total': 14.0,
          'paidAmount': 4.0,
          'dueAmount': 10.0,
          'items': [
            {
              'unitPrice': 7.5,
              'lineTotal': 15.0,
              'costTotal': 15.0,
              'profitTotal': 0.0,
            },
          ],
        },
        {
          'id': 'sale-invoice',
          'type': 'sale',
          'costTotal': 7.5,
          'profitTotal': 2.5,
          'items': [
            {'unitPrice': 10.0, 'costTotal': 7.5, 'profitTotal': 2.5},
          ],
        },
      ],
      'payments': [
        {'invoiceId': 'purchase-invoice', 'direction': 'out', 'amount': 4.0},
        {'invoiceId': null, 'direction': 'out', 'amount': 2.0},
        {'invoiceId': 'sale-invoice', 'direction': 'in', 'amount': 5.0},
      ],
      'summary': {'inventoryValue': 100.0, 'profitToday': 20.0},
    };

    final redacted = StoreManagementPrivacy.redactSnapshotForStaff(
      snapshot,
      canViewProfits: false,
    );

    final product = (redacted['products'] as List).single;
    expect(product['averagePurchaseCost'], isNull);
    expect(product['estimatedStockProfit'], isNull);
    expect((product['units'] as List).single['purchasePrice'], isNull);
    expect((product['units'] as List).single['salePrice'], 10.0);

    final purchase = (redacted['invoices'] as List).first;
    expect(purchase['items'].single['unitPrice'], isNull);
    expect(purchase['items'].single['lineTotal'], isNull);
    expect(purchase['costTotal'], isNull);
    expect(purchase['profitTotal'], isNull);
    expect(purchase['subtotal'], isNull);
    expect(purchase['discount'], isNull);
    expect(purchase['total'], isNull);
    expect(purchase['paidAmount'], isNull);
    expect(purchase['dueAmount'], isNull);

    final sale = (redacted['invoices'] as List).last;
    expect(sale['items'].single['unitPrice'], 10.0);
    expect(sale['items'].single['costTotal'], isNull);
    expect(sale['items'].single['profitTotal'], isNull);
    final payments = redacted['payments'] as List;
    expect(payments[0]['amount'], isNull);
    expect(payments[1]['amount'], isNull);
    expect(payments[2]['amount'], 5.0);
    expect(redacted['summary']['inventoryValue'], isNull);
    expect(redacted['summary']['profitToday'], isNull);
  });

  test('primary account snapshots keep the original values', () {
    final snapshot = <String, dynamic>{
      'products': [
        {'averagePurchaseCost': 7.5},
      ],
    };

    final visible = StoreManagementPrivacy.redactSnapshotForStaff(
      snapshot,
      canViewProfits: true,
    );

    expect(visible['products'].single['averagePurchaseCost'], 7.5);
  });
}
