import 'package:flutter/material.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminCardPrintRequestsScreen extends StatefulWidget {
  const AdminCardPrintRequestsScreen({super.key});

  @override
  State<AdminCardPrintRequestsScreen> createState() =>
      _AdminCardPrintRequestsScreenState();
}

class _AdminCardPrintRequestsScreenState
    extends State<AdminCardPrintRequestsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final PDFService _pdfService = PDFService();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  String _status = 'all';
  int _page = 1;
  int _lastPage = 1;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final payload = await _apiService.getCardPrintRequests(
        status: _status,
        query: _searchController.text,
        page: _page,
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = List<Map<String, dynamic>>.from(
          payload['requests'] as List? ?? const [],
        );
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: context.loc.tr(
          'screens_admin_card_print_requests_screen.load_error_title',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _handleAction(
    Map<String, dynamic> request,
    String action,
  ) async {
    setState(() => _busyId = request['id']?.toString());
    try {
      switch (action) {
        case 'approve':
          await _apiService.approveCardPrintRequest(request['id'].toString());
          break;
        case 'start':
          await _apiService.startCardPrintRequest(request['id'].toString());
          break;
        case 'ready':
          await _apiService.readyCardPrintRequest(request['id'].toString());
          break;
        case 'complete':
          await _apiService.completeCardPrintRequest(request['id'].toString());
          break;
        case 'reject':
          await _apiService.rejectCardPrintRequest(request['id'].toString());
          break;
      }
      await _load();
    } catch (error) {
      if (mounted) {
        await AppAlertService.showError(
          context,
          title: context.loc.tr(
            'screens_admin_card_print_requests_screen.update_error_title',
          ),
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  List<VirtualCard> _extractCardsFromRequest(Map<String, dynamic> request) {
    const candidateKeys = [
      'cards',
      'issuedCards',
      'printableCards',
      'generatedCards',
      'preparedCards',
      'cardsSnapshot',
    ];

    for (final key in candidateKeys) {
      final raw = request[key];
      if (raw is! List || raw.isEmpty) {
        continue;
      }
      return raw
          .whereType<Map>()
          .map((item) => _cardFromAny(Map<String, dynamic>.from(item)))
          .where((card) => card.barcode.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  VirtualCard _cardFromAny(Map<String, dynamic> item) {
    final normalized = <String, dynamic>{
      'id': item['id'],
      'barcode': item['barcode'],
      'value': item['value'],
      'card_type': item['card_type'] ?? item['cardType'],
      'visibility_scope': item['visibility_scope'] ?? item['visibilityScope'],
      'issue_cost': item['issue_cost'] ?? item['issueCost'],
      'owner_id': item['owner_id'] ?? item['ownerId'],
      'owner_username': item['owner_username'] ?? item['ownerUsername'],
      'issued_by_id': item['issued_by_id'] ?? item['issuedById'],
      'issued_by_username': item['issued_by_username'] ?? item['issuedByUsername'],
      'redeemed_by_id': item['redeemed_by_id'] ?? item['redeemedById'],
      'allowed_user_ids':
          item['allowed_user_ids'] ?? item['allowedUserIds'] ?? const [],
      'allowed_usernames':
          item['allowed_usernames'] ?? item['allowedUsernames'] ?? const [],
      'customer_name': item['customer_name'] ?? item['customerName'],
      'created_at':
          item['created_at'] ?? item['issuedAt'] ?? item['createdAt'],
      'last_resold_at': item['last_resold_at'] ?? item['lastResoldAt'],
      'use_count': item['use_count'] ?? item['useCount'],
      'resale_count': item['resale_count'] ?? item['resaleCount'],
      'total_redeemed_value':
          item['total_redeemed_value'] ?? item['totalRedeemedValue'],
      'status': item['status'],
      'used_at': item['used_at'] ?? item['redeemedAt'],
      'used_by': item['used_by'] ?? item['redeemedByUsername'],
      'sold_price': item['sold_price'],
    };
    return VirtualCard.fromMap(normalized);
  }

  Future<void> _exportRequestPdf(Map<String, dynamic> request) async {
    final l = context.loc;
    final cards = _extractCardsFromRequest(request);
    if (cards.isEmpty) {
      await AppAlertService.showInfo(
        context,
        title: l.tr(
          'screens_admin_card_print_requests_screen.file_unavailable_title',
        ),
        message: l.tr(
          'screens_admin_card_print_requests_screen.export_unavailable_message',
        ),
      );
      return;
    }

    try {
      final currentUser = await _authService.currentUser();
      final printedBy =
          currentUser?['fullName']?.toString().trim().isNotEmpty == true
          ? currentUser!['fullName'].toString().trim()
          : currentUser?['username']?.toString();
      final pdf = await _pdfService.createMultiCardPDF(
        cards,
        printedBy: printedBy,
      );
      final requestId =
          request['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final file = await _pdfService.savePDF(
        pdf,
        'card_print_request_$requestId',
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr(
          'screens_admin_card_print_requests_screen.pdf_generated_title',
        ),
        message: l.tr(
          'screens_admin_card_print_requests_screen.pdf_generated_message',
          params: {'path': file.path},
        ),
      );
      final requestIdValue = request['id']?.toString();
      if (requestIdValue != null && requestIdValue.isNotEmpty) {
        try {
          await _apiService.markCardPrintRequestPrinted(requestIdValue);
          await _load();
        } catch (_) {}
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr(
          'screens_admin_card_print_requests_screen.pdf_failed_title',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _printRequestCards(Map<String, dynamic> request) async {
    final l = context.loc;
    final cards = _extractCardsFromRequest(request);
    if (cards.isEmpty) {
      await AppAlertService.showInfo(
        context,
        title: l.tr(
          'screens_admin_card_print_requests_screen.file_unavailable_title',
        ),
        message: l.tr(
          'screens_admin_card_print_requests_screen.print_unavailable_message',
        ),
      );
      return;
    }

    try {
      final currentUser = await _authService.currentUser();
      final printedBy =
          currentUser?['fullName']?.toString().trim().isNotEmpty == true
          ? currentUser!['fullName'].toString().trim()
          : currentUser?['username']?.toString();
      await _pdfService.printCards(cards, printedBy: printedBy);
      final requestId = request['id']?.toString();
      if (requestId != null && requestId.isNotEmpty) {
        try {
          await _apiService.markCardPrintRequestPrinted(requestId);
          await _load();
        } catch (_) {}
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr(
          'screens_admin_card_print_requests_screen.print_failed_title',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_admin_card_print_requests_screen.001')),
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShwakelCard(
                  padding: const EdgeInsets.all(28),
                  gradient: AppTheme.primaryGradient,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.tr(
                          'screens_admin_card_print_requests_screen.hero_title',
                        ),
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.tr(
                          'screens_admin_card_print_requests_screen.hero_subtitle',
                        ),
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AdminSectionHeader(
                  title: l.tr('screens_admin_card_print_requests_screen.002'),
                  subtitle: l.tr(
                    'screens_admin_card_print_requests_screen.section_subtitle',
                  ),
                  icon: Icons.print_rounded,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 760;
                    final searchField = Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_card_print_requests_screen.search_label',
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                        onSubmitted: (_) {
                          _page = 1;
                          _load();
                        },
                      ),
                    );
                    final filterField = SizedBox(
                      width: stacked ? double.infinity : 190,
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_card_print_requests_screen.003',
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(
                              l.tr(
                                'screens_admin_card_print_requests_screen.004',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'pending_review',
                            child: Text(
                              l.tr(
                                'screens_admin_card_print_requests_screen.005',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'approved',
                            child: Text(
                              l.tr(
                                'screens_admin_card_print_requests_screen.006',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'printing',
                            child: Text(
                              l.tr(
                                'screens_admin_card_print_requests_screen.007',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'ready',
                            child: Text(
                              l.tr(
                                'screens_admin_card_print_requests_screen.008',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text(
                              l.tr(
                                'screens_admin_card_print_requests_screen.009',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'rejected',
                            child: Text(
                              l.tr(
                                'screens_admin_card_print_requests_screen.010',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'archive',
                            child: Text(
                              l.tr(
                                'screens_admin_card_print_requests_screen.029',
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _status = value;
                            _page = 1;
                          });
                          _load();
                        },
                      ),
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          Row(children: [searchField]),
                          const SizedBox(height: 12),
                          filterField,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        searchField,
                        const SizedBox(width: 12),
                        filterField,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _summaryChip(
                      l.tr('screens_admin_card_print_requests_screen.011'),
                      (_summary['pendingReviewCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      l.tr('screens_admin_card_print_requests_screen.012'),
                      (_summary['approvedCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      l.tr('screens_admin_card_print_requests_screen.013'),
                      (_summary['printingCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      l.tr('screens_admin_card_print_requests_screen.014'),
                      (_summary['readyCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      l.tr('screens_admin_card_print_requests_screen.030'),
                      (_summary['completedCount'] as num?)?.toInt() ?? 0,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_requests.isEmpty)
                  ShwakelCard(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Text(
                        l.tr(
                          'screens_admin_card_print_requests_screen.empty_state',
                        ),
                        style: AppTheme.bodyAction,
                      ),
                    ),
                  )
                else ...[
                  ..._requests.map(_buildRequestCard),
                  const SizedBox(height: 24),
                  AdminPaginationFooter(
                    currentPage: _page,
                    lastPage: _lastPage,
                    onPageChanged: (page) {
                      setState(() => _page = page);
                      _load();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final l = context.loc;
    final status = request['status']?.toString() ?? 'pending_review';
    final busy = _busyId == request['id']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ShwakelCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['fullName']?.toString().trim().isNotEmpty ==
                                true
                            ? request['fullName'].toString()
                            : (request['username']?.toString() ??
                                  l.tr(
                                    'screens_admin_card_print_requests_screen.015',
                                  )),
                        style: AppTheme.h3,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request['whatsapp']?.toString() ?? '',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
                _statusChip(request['statusLabel']?.toString() ?? status),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metaItem(
                  l.tr('screens_admin_card_print_requests_screen.016'),
                  request['id']?.toString() ?? '-',
                ),
                _metaItem(
                  l.tr('screens_admin_card_print_requests_screen.017'),
                  request['cardType'] == 'single_use'
                      ? l.tr('screens_admin_card_print_requests_screen.018')
                      : l.tr('screens_admin_card_print_requests_screen.019'),
                ),
                _metaItem(
                  l.tr('screens_admin_card_print_requests_screen.020'),
                  l.tr(
                    'screens_admin_card_print_requests_screen.quantity_label',
                    params: {'count': '${request['quantity'] ?? 0}'},
                  ),
                ),
                _metaItem(
                  l.tr('screens_admin_card_print_requests_screen.021'),
                  CurrencyFormatter.ils(
                    (request['cardValue'] as num?)?.toDouble() ?? 0,
                  ),
                ),
                _metaItem(
                  l.tr('screens_admin_card_print_requests_screen.022'),
                  CurrencyFormatter.ils(
                    (request['totalAmount'] as num?)?.toDouble() ?? 0,
                  ),
                ),
                _metaItem(
                  l.tr('screens_admin_card_print_requests_screen.031'),
                  _sourceLabel(request['sourceType']?.toString() ?? 'app'),
                ),
                _metaItem(
                  l.tr('screens_admin_card_print_requests_screen.032'),
                  '${request['printCount'] ?? 0}',
                ),
                _metaItem(
                  l.tr('screens_admin_card_print_requests_screen.033'),
                  _formatDateTime(request['lastPrintedAt']?.toString()),
                ),
              ],
            ),
            if ((request['customerNotes']?.toString().trim().isNotEmpty ??
                false))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  l.tr(
                    'screens_admin_card_print_requests_screen.customer_notes',
                    params: {'notes': request['customerNotes'].toString()},
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _printRequestCards(request),
                  icon: const Icon(Icons.print_rounded),
                  label: Text(
                    l.tr('screens_admin_card_print_requests_screen.print_now'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _exportRequestPdf(request),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: Text(
                    l.tr('screens_admin_card_print_requests_screen.export_pdf'),
                  ),
                ),
                if (status == 'pending_review')
                  _actionButton(
                    l.tr('screens_admin_card_print_requests_screen.023'),
                    busy,
                    () => _handleAction(request, 'approve'),
                  ),
                if (status == 'pending_review')
                  _actionButton(
                    l.tr('screens_admin_card_print_requests_screen.024'),
                    busy,
                    () => _handleAction(request, 'reject'),
                  ),
                if (status == 'approved')
                  _actionButton(
                    l.tr('screens_admin_card_print_requests_screen.025'),
                    busy,
                    () => _handleAction(request, 'start'),
                  ),
                if (status == 'printing')
                  _actionButton(
                    l.tr('screens_admin_card_print_requests_screen.026'),
                    busy,
                    () => _handleAction(request, 'ready'),
                  ),
                if (status == 'ready')
                  _actionButton(
                    l.tr('screens_admin_card_print_requests_screen.027'),
                    busy,
                    () => _handleAction(request, 'complete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, bool busy, VoidCallback onPressed) {
    final l = context.loc;
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      child: Text(
        busy ? l.tr('screens_admin_card_print_requests_screen.028') : label,
      ),
    );
  }

  Widget _summaryChip(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          Text('$count', style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  String _sourceLabel(String source) {
    final l = context.loc;
    return source == 'local'
        ? l.tr('screens_admin_card_print_requests_screen.034')
        : l.tr('screens_admin_card_print_requests_screen.035');
  }

  String _formatDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.loc.tr('screens_admin_card_print_requests_screen.036');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final year = parsed.year.toString().padLeft(4, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'approved' => AppTheme.primary,
      'printing' => AppTheme.warning,
      'ready' => AppTheme.success,
      'completed' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status == 'pending_review'
            ? context.loc.tr(
                'screens_admin_card_print_requests_screen.pending_status',
              )
            : status,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
