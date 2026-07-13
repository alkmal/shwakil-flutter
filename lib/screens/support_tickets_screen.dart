import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/support_contact_card.dart';

class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key, this.openTracking = false});

  final bool openTracking;

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _details = TextEditingController();
  final TextEditingController _otp = TextEditingController();
  final TextEditingController _message = TextEditingController();
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _myTickets = const [];
  List<Map<String, dynamic>> _phoneTickets = const [];
  String _accessToken = '';
  String _pendingTicketId = '';
  String _pendingPhone = '';
  String _supportWhatsapp = '';
  String _selectedCountryCode = PhoneNumberService.countries.first.dialCode;
  String? _debugOtp;
  bool _phoneOtpPending = false;
  bool _tracking = false;
  bool _loading = true;
  bool _busy = false;
  bool _ticketLoading = false;
  bool _hasFreshMessage = false;
  bool _chatRouteOpen = false;
  StateSetter? _chatRouteSetState;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _tracking = widget.openTracking;
    _notificationSubscription = RealtimeNotificationService.notificationsStream
        .listen(_handleTicketNotification);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _title.dispose();
    _details.dispose();
    _otp.dispose();
    _message.dispose();
    _notificationSubscription?.cancel();
    _stopChatAutoRefresh();
    super.dispose();
  }

  void _handleTicketNotification(Map<String, dynamic> payload) {
    if (!mounted || _busy) {
      return;
    }
    final type = payload['type']?.toString().trim().toLowerCase() ?? '';
    final sourceType =
        payload['sourceType']?.toString().trim().toLowerCase() ?? '';
    final ticketId =
        payload['ticketId']?.toString().trim() ??
        payload['sourceId']?.toString().split(':').first.trim() ??
        '';
    final isSupportTicket =
        type.startsWith('support_ticket') ||
        sourceType == 'support_ticket' ||
        ticketId.isNotEmpty;
    if (!isSupportTicket) {
      return;
    }

    final currentId = _ticket?['id']?.toString() ?? '';
    if (currentId.isNotEmpty && ticketId == currentId) {
      setState(() => _hasFreshMessage = !_chatRouteOpen);
      unawaited(_refreshTicket(silent: true));
      return;
    }
    if (currentId.isEmpty) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final user = await _auth.currentUser();
    var tickets = const <Map<String, dynamic>>[];
    var supportWhatsapp = _supportWhatsapp;
    try {
      final contact = await ContactInfoService.getContactInfo();
      supportWhatsapp = ContactInfoService.supportWhatsapp(contact);
    } catch (_) {}
    if (user != null) {
      try {
        tickets = await _api.getMySupportTickets();
      } catch (_) {}
      _name.text = user['fullName']?.toString() ?? '';
      _phone.text = PhoneNumberService.localDisplay(
        user['whatsapp']?.toString(),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _user = user;
      _myTickets = tickets;
      _supportWhatsapp = supportWhatsapp;
      _loading = false;
    });
  }

  Future<void> _start() async {
    final l = context.loc;
    if (_title.text.trim().length < 3 || _details.text.trim().length < 4) {
      return _error(
        l.text(
          'أدخل عنوان التذكرة وتفاصيل التواصل بوضوح.',
          'Enter a clear ticket title and contact details.',
        ),
      );
    }
    if (_user == null &&
        (_name.text.trim().length < 2 || _phone.text.trim().length < 8)) {
      return _error(
        l.text(
          'أدخل الاسم ورقم واتساب للتواصل.',
          'Enter your name and WhatsApp number for contact.',
        ),
      );
    }
    setState(() => _busy = true);
    try {
      final response = await _api.createSupportTicket(
        name: _name.text,
        whatsapp: _phone.text,
        countryCode: _selectedCountryCode,
        title: _title.text,
        details: _details.text,
      );
      if (!mounted) {
        return;
      }
      if (response['duplicateTicket'] == true) {
        setState(() {
          _tracking = true;
          _pendingTicketId = response['debugOtpCode'] != null
              ? response['ticketId']?.toString() ?? ''
              : '';
          _pendingPhone = PhoneNumberService.localDisplay(
            response['whatsapp']?.toString() ?? _phone.text.trim(),
          );
          _debugOtp = response['debugOtpCode']?.toString();
        });
        await _success(
          response['message']?.toString() ??
              l.text(
                'لديك تذكرة قائمة. تابع نفس التذكرة برقم واتساب و OTP.',
                'You already have an open ticket. Continue it using your WhatsApp number and OTP.',
              ),
        );
        return;
      }
      setState(() {
        _pendingTicketId = response['ticketId']?.toString() ?? '';
        _pendingPhone = PhoneNumberService.localDisplay(
          response['whatsapp']?.toString() ?? _phone.text.trim(),
        );
        _debugOtp = response['debugOtpCode']?.toString();
      });
      await _success(
        response['message']?.toString() ??
            l.text('تم إرسال الرمز.', 'The code was sent.'),
      );
    } catch (error) {
      await _error(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _requestTrackingOtp() async {
    final l = context.loc;
    if (_phone.text.trim().length < 8) {
      return _error(
        l.text(
          'أدخل رقم واتساب الذي تم فتح التذاكر عليه.',
          'Enter the WhatsApp number used to open the tickets.',
        ),
      );
    }
    setState(() => _busy = true);
    try {
      final response = await _api.requestSupportTicketPhoneAccess(
        whatsapp: _phone.text,
        countryCode: _selectedCountryCode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingPhone = PhoneNumberService.localDisplay(
          response['whatsapp']?.toString() ?? _phone.text.trim(),
        );
        _debugOtp = response['debugOtpCode']?.toString();
        _phoneOtpPending = true;
        _phoneTickets = const [];
      });
      await _success(
        response['message']?.toString() ??
            l.text('تم إرسال الرمز.', 'The code was sent.'),
      );
    } catch (error) {
      await _error(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _verify() async {
    final l = context.loc;
    if (_otp.text.trim().length < 4) {
      return _error(l.text('أدخل رمز التحقق.', 'Enter the verification code.'));
    }
    setState(() => _busy = true);
    try {
      final response = _phoneOtpPending
          ? await _api.verifySupportTicketPhoneAccess(
              whatsapp: _pendingPhone,
              otpCode: _otp.text,
              countryCode: _selectedCountryCode,
            )
          : await _api.verifySupportTicket(
              ticketId: _pendingTicketId,
              otpCode: _otp.text,
            );
      if (!mounted) {
        return;
      }
      if (_phoneOtpPending) {
        setState(() {
          _phoneTickets = List<Map<String, dynamic>>.from(
            (response['tickets'] as List? ?? const []).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          );
          _phoneOtpPending = false;
          _pendingPhone = '';
          _otp.clear();
        });
      } else {
        setState(() {
          _accessToken = response['accessToken']?.toString() ?? '';
          _ticket = Map<String, dynamic>.from(response['ticket'] as Map);
          _pendingTicketId = '';
          _otp.clear();
        });
      }
      await _success(
        response['message']?.toString() ??
            l.text('تم فتح الشات.', 'The chat was opened.'),
      );
      await _load();
      unawaited(_openChatRoute());
    } catch (error) {
      await _error(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _openOwnedTicket(String id) async {
    final summary = _myTickets.firstWhere(
      (ticket) => ticket['id']?.toString() == id,
      orElse: () => {'id': id, 'title': '', 'status': ''},
    );
    setState(() {
      _ticket = Map<String, dynamic>.from(summary);
      _accessToken = '';
      _ticketLoading = true;
    });
    unawaited(_openChatRoute());
    try {
      final response = await _api.getSupportTicket(ticketId: id);
      if (!mounted) {
        return;
      }
      setState(() {
        _ticket = Map<String, dynamic>.from(response['ticket'] as Map);
        _accessToken = '';
        _ticketLoading = false;
      });
      _refreshChatRoute();
    } catch (error) {
      await _error(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _ticketLoading = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _openPhoneTicket(Map<String, dynamic> summary) async {
    final id = summary['id']?.toString() ?? '';
    final token = summary['accessToken']?.toString() ?? '';
    if (id.isEmpty || token.isEmpty) {
      return _error(
        context.loc.text(
          'تعذر فتح التذكرة، أعد التحقق من الرقم.',
          'Could not open the ticket. Verify the number again.',
        ),
      );
    }
    setState(() {
      _ticket = Map<String, dynamic>.from(summary);
      _accessToken = token;
      _ticketLoading = true;
    });
    unawaited(_openChatRoute());
    try {
      final response = await _api.getSupportTicket(
        ticketId: id,
        accessToken: token,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _ticket = Map<String, dynamic>.from(response['ticket'] as Map);
        _accessToken = token;
        _ticketLoading = false;
      });
      _refreshChatRoute();
    } catch (error) {
      await _error(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _ticketLoading = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _refreshTicket({bool silent = false}) async {
    final id = _ticket?['id']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    if (!silent) {
      setState(() => _ticketLoading = true);
      _refreshChatRoute();
    }
    try {
      final response = await _api.getSupportTicket(
        ticketId: id,
        accessToken: _accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _ticket = Map<String, dynamic>.from(response['ticket'] as Map);
        if (_chatRouteOpen || !silent) {
          _hasFreshMessage = false;
        }
        _ticketLoading = false;
      });
      _refreshChatRoute();
    } catch (error) {
      if (!silent) {
        await _error(ErrorMessageService.sanitize(error));
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _ticketLoading = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _sendMessage() async {
    final id = _ticket?['id']?.toString() ?? '';
    if (id.isEmpty || _message.text.trim().isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.sendSupportTicketMessage(
        ticketId: id,
        body: _message.text,
        accessToken: _accessToken,
      );
      _message.clear();
      await _refreshTicket();
    } catch (error) {
      await _error(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _openChatRoute() async {
    if (!mounted || _ticket == null || _chatRouteOpen) {
      _refreshChatRoute();
      return;
    }
    _chatRouteOpen = true;
    _startChatAutoRefresh();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, setRouteState) {
            _chatRouteSetState = setRouteState;
            return Scaffold(
              backgroundColor: AppTheme.background,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: _chat(),
                ),
              ),
            );
          },
        ),
      ),
    );
    _stopChatAutoRefresh();
    _chatRouteOpen = false;
    _chatRouteSetState = null;
    if (mounted) {
      setState(() => _ticket = null);
    }
  }

  void _refreshChatRoute() {
    _chatRouteSetState?.call(() {});
  }

  void _startChatAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || !_chatRouteOpen || _ticket == null || _busy) {
        return;
      }
      unawaited(_refreshTicket(silent: true));
    });
  }

  void _stopChatAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  Future<void> _upload() async {
    final id = _ticket?['id']?.toString() ?? '';
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt'],
      withData: true,
    );
    final file = picked?.files.single;
    if (id.isEmpty || file?.bytes == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.uploadSupportTicketAttachment(
        ticketId: id,
        fileName: file!.name,
        bytes: file.bytes!,
        accessToken: _accessToken,
      );
      await _refreshTicket();
    } catch (error) {
      await _error(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> file) async {
    final id = _ticket?['id']?.toString() ?? '';
    final attachmentId = file['id']?.toString() ?? '';
    if (id.isEmpty || attachmentId.isEmpty) {
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await _api.downloadSupportTicketAttachment(
        ticketId: id,
        attachmentId: attachmentId,
        accessToken: _accessToken,
      );
      if (!mounted) {
        return;
      }
      if (_isImageAttachment(file)) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        );
        return;
      }
      await _saveAttachment(file, bytes);
    } catch (error) {
      await _error(ErrorMessageService.sanitize(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveAttachment(
    Map<String, dynamic> file,
    Uint8List bytes,
  ) async {
    final name = _safeFileName(file['name']?.toString() ?? 'support-file');
    final extension = _extensionFor(file);
    await FileSaver.instance.saveFile(
      name: name.replaceFirst(RegExp('\\.$extension\$'), ''),
      bytes: bytes,
      fileExtension: extension,
      mimeType: _fileSaverMime(file),
    );
    if (mounted) {
      await _success(
        context.loc.text(
          'تم تجهيز الملف للفتح أو التحميل من جهازك.',
          'The file is ready to open or download from your device.',
        ),
      );
    }
  }

  Future<void> _error(String message) => AppAlertService.showError(
    context,
    title: context.loc.text('تعذر متابعة التذكرة', 'Could not continue ticket'),
    message: message,
  );

  Future<void> _success(String message) => AppAlertService.showSuccess(
    context,
    title: context.loc.text('تذاكر التواصل', 'Support tickets'),
    message: message,
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final content = _pendingTicketId.isNotEmpty || _phoneOtpPending
        ? _otpStep()
        : _entry();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.loc.text('تذاكر التواصل', 'Support tickets')),
        actions: _user == null
            ? null
            : const [AppNotificationAction(), QuickLogoutAction()],
      ),
      drawer: _user == null ? null : const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          maxWidth: 860,
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: content,
        ),
      ),
    );
  }

  Widget _entry() {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShwakelCard(
          padding: const EdgeInsets.all(24),
          gradient: AppTheme.primaryGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.text('تواصل داخل التطبيق', 'In-app support'),
                style: AppTheme.h2.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(l.text('فتح تذكرة', 'Open ticket')),
              icon: const Icon(Icons.add_comment_rounded),
            ),
            ButtonSegment(
              value: true,
              label: Text(l.text('متابعة تذكرة', 'Track ticket')),
              icon: const Icon(Icons.forum_rounded),
            ),
          ],
          selected: {_tracking},
          onSelectionChanged: (value) =>
              setState(() => _tracking = value.first),
        ),
        const SizedBox(height: 16),
        if (_tracking)
          _trackingForm()
        else ...[
          _newTicketForm(),
          if (_supportWhatsapp.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _directWhatsappSupport(),
          ],
        ],
        if (_phoneTickets.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            l.text('تذاكر الرقم المؤكد', 'Verified number tickets'),
            style: AppTheme.h3,
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _phoneTickets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ticketSummaryTile(
              _phoneTickets[index],
              icon: Icons.mark_chat_unread_outlined,
              onTap: () => _openPhoneTicket(_phoneTickets[index]),
            ),
          ),
        ],
        if (_myTickets.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            l.text('تذاكرك المرتبطة بالحساب', 'Tickets linked to your account'),
            style: AppTheme.h3,
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _myTickets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ticketSummaryTile(
              _myTickets[index],
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () => _openOwnedTicket(_myTickets[index]['id'].toString()),
            ),
          ),
        ],
      ],
    );
  }

  Widget _ticketSummaryTile(
    Map<String, dynamic> ticket, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ShwakelCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ticket['title']?.toString().trim().isNotEmpty == true
                  ? ticket['title'].toString()
                  : context.loc.text('تذكرة دعم', 'Support ticket'),
              style: AppTheme.bodyBold,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            ticket['status']?.toString() ?? '',
            style: AppTheme.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _newTicketForm() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_user == null) ...[
            _field(_name, l.text('الاسم', 'Name'), Icons.badge_outlined),
            const SizedBox(height: 12),
            _countrySelector(),
            const SizedBox(height: 12),
            _field(
              _phone,
              l.text('رقم واتساب', 'WhatsApp number'),
              Icons.phone_outlined,
              phone: true,
            ),
            const SizedBox(height: 12),
          ],
          _field(
            _title,
            l.text('عنوان التذكرة', 'Ticket title'),
            Icons.subject_rounded,
          ),
          const SizedBox(height: 12),
          _field(
            _details,
            l.text('تفاصيل التواصل', 'Contact details'),
            Icons.notes_rounded,
            lines: 5,
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: l.text(
              'إرسال رمز التحقق وفتح التذكرة',
              'Send verification code and open ticket',
            ),
            onPressed: _busy ? null : _start,
            isLoading: _busy,
            icon: Icons.verified_user_rounded,
          ),
        ],
      ),
    );
  }

  Widget _directWhatsappSupport() {
    final l = context.loc;
    return SupportContactCard(
      phoneNumber: _supportWhatsapp,
      title: l.text('دعم فني مباشر عبر واتساب', 'Direct WhatsApp support'),
      message: l.text(
        'للحالات العاجلة يمكنك التواصل مباشرة عبر واتساب، أو فتح تذكرة ليبقى الشات محفوظًا داخل التطبيق.',
        'For urgent cases, contact support directly on WhatsApp, or open a ticket to keep the chat saved inside the app.',
      ),
    );
  }

  Widget _trackingForm() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _countrySelector(),
          const SizedBox(height: 12),
          _field(
            _phone,
            l.text(
              'رقم واتساب لعرض التذاكر',
              'WhatsApp number to view tickets',
            ),
            Icons.phone_outlined,
            phone: true,
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: l.text('إرسال رمز متابعة', 'Send tracking code'),
            onPressed: _busy ? null : _requestTrackingOtp,
            isLoading: _busy,
            icon: Icons.sms_outlined,
          ),
        ],
      ),
    );
  }

  Widget _otpStep() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.text('تأكيد رقم التواصل', 'Confirm contact number'),
            style: AppTheme.h2,
          ),
          const SizedBox(height: 12),
          if ((_debugOtp ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l.text('رمز التجربة: $_debugOtp', 'Test code: $_debugOtp'),
              style: AppTheme.bodyBold,
            ),
          ],
          const SizedBox(height: 16),
          _field(
            _otp,
            l.text('رمز OTP', 'OTP code'),
            Icons.password_rounded,
            phone: true,
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: l.text('تأكيد وفتح الشات', 'Confirm and open chat'),
            onPressed: _busy ? null : _verify,
            isLoading: _busy,
            icon: Icons.lock_open_rounded,
          ),
        ],
      ),
    );
  }

  Widget _countrySelector() {
    final l = context.loc;
    final selected = PhoneNumberService.countries.firstWhere(
      (country) => country.dialCode == _selectedCountryCode,
      orElse: () => PhoneNumberService.countries.first,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _pickCountry,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l.text('الدولة', 'Country'),
          prefixIcon: const Icon(Icons.public_rounded, size: 20),
          suffixIcon: const Icon(Icons.search_rounded),
        ),
        child: Text(
          '${selected.name} (+${selected.dialCode})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodyBold,
        ),
      ),
    );
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<CountryOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => const _SupportCountryPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedCountryCode = picked.dialCode);
  }

  Widget _chat() {
    final l = context.loc;
    final messages = List<Map<String, dynamic>>.from(
      (_ticket?['messages'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final attachments = List<Map<String, dynamic>>.from(
      (_ticket?['attachments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final statusEvents = List<Map<String, dynamic>>.from(
      (_ticket?['statusEvents'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final timeline = _chatTimeline(messages, statusEvents, attachments);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chatHeader(l),
        if (_hasFreshMessage) ...[
          const SizedBox(height: 8),
          Material(
            color: AppTheme.primarySoft,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _refreshTicket(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.mark_chat_unread_rounded,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.text('وصلت رسالة جديدة', 'New message received'),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: _ticketLoading && timeline.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l.text('يتم تحميل المحادثة...', 'Loading chat...'),
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  )
                : timeline.isNotEmpty
                ? ListView.separated(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: timeline.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = timeline[index];
                      return switch (item['_timelineKind']) {
                        'status' => _statusEventTile(item),
                        'attachment' => _attachmentBubble(item),
                        _ => _messageBubble(item),
                      };
                    },
                  )
                : Center(
                    child: Text(
                      l.text(
                        'لا توجد رسائل في هذه التذكرة بعد.',
                        'There are no messages in this ticket yet.',
                      ),
                      style: AppTheme.caption,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        _chatComposer(l),
      ],
    );
  }

  Widget _chatHeader(AppLocalizer l) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: l.text('رجوع', 'Back'),
            onPressed: () {
              if (_chatRouteOpen) {
                Navigator.of(context).maybePop();
              } else {
                setState(() => _ticket = null);
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          const CircleAvatar(
            backgroundColor: AppTheme.primarySoft,
            child: Icon(Icons.support_agent_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _ticket?['title']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 2),
                Text(
                  l.text(
                    '#${_ticket?['id']} - ${_ticket?['statusLabel'] ?? _ticket?['status']}',
                    '#${_ticket?['id']} - ${_ticket?['statusLabel'] ?? _ticket?['status']}',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.text('تحديث', 'Refresh'),
            onPressed: _busy ? null : _refreshTicket,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _chatComposer(AppLocalizer l) {
    return ShwakelCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton.filledTonal(
            tooltip: l.text('إرفاق ملف', 'Attach file'),
            onPressed: _busy ? null : _upload,
            icon: const Icon(Icons.attach_file_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _message,
              onChanged: (_) {
                setState(() {});
                _refreshChatRoute();
              },
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: l.text('اكتب رسالة...', 'Write a message...'),
                filled: true,
                fillColor: AppTheme.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: l.text('إرسال', 'Send'),
            onPressed: _busy || _message.text.trim().isEmpty
                ? null
                : _sendMessage,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> message) {
    final mine = message['senderKind']?.toString() == 'customer';
    final l = context.loc;
    final attachments = List<Map<String, dynamic>>.from(
      (message['attachments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width >= 700 ? 620 : 300,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppTheme.primary : AppTheme.surface,
          border: Border.all(color: mine ? AppTheme.primary : AppTheme.border),
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(18),
            topEnd: const Radius.circular(18),
            bottomStart: Radius.circular(mine ? 18 : 6),
            bottomEnd: Radius.circular(mine ? 6 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine
                  ? l.text('أنت', 'You')
                  : (message['displayName']?.toString() ??
                        l.text('الدعم', 'Support')),
              style: AppTheme.caption.copyWith(
                color: mine ? Colors.white70 : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 5),
            SelectableText(
              message['body']?.toString() ?? '',
              style: AppTheme.bodyText.copyWith(
                color: mine ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final attachment in attachments) ...[
                _attachmentTile(attachment, compact: true),
                const SizedBox(height: 6),
              ],
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _messageStatusIcon(message),
                  size: 14,
                  color: mine ? Colors.white70 : AppTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _messageStatusLabel(message, mine),
                  style: AppTheme.caption.copyWith(
                    color: mine ? Colors.white70 : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _chatTimeline(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> statusEvents,
    List<Map<String, dynamic>> attachments,
  ) {
    final timeline = <Map<String, dynamic>>[
      ...messages.map((item) => {...item, '_timelineKind': 'message'}),
      ...statusEvents.map((item) => {...item, '_timelineKind': 'status'}),
      ...attachments.map((item) => {...item, '_timelineKind': 'attachment'}),
    ];
    timeline.sort(
      (left, right) => (right['createdAt']?.toString() ?? '').compareTo(
        left['createdAt']?.toString() ?? '',
      ),
    );
    return timeline;
  }

  Widget _attachmentBubble(Map<String, dynamic> file) {
    final mine = file['uploaderKind']?.toString() == 'customer';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width >= 700 ? 620 : 330,
        ),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: mine ? AppTheme.primarySoft : AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: _attachmentTile(file, compact: true),
      ),
    );
  }

  IconData _messageStatusIcon(Map<String, dynamic> message) {
    if ((message['readAt']?.toString().trim() ?? '').isNotEmpty) {
      return Icons.done_all_rounded;
    }
    if ((message['deliveredAt']?.toString().trim() ?? '').isNotEmpty) {
      return Icons.done_all_rounded;
    }
    return Icons.done_rounded;
  }

  String _messageStatusLabel(Map<String, dynamic> message, bool mine) {
    final l = context.loc;
    if (!mine) {
      return message['createdAt']?.toString() ?? '';
    }
    if ((message['readAt']?.toString().trim() ?? '').isNotEmpty) {
      return l.text('تمت القراءة', 'Read');
    }
    if ((message['deliveredAt']?.toString().trim() ?? '').isNotEmpty) {
      return l.text('وصلت', 'Delivered');
    }
    return l.text('تم الإرسال', 'Sent');
  }

  Widget _statusEventTile(Map<String, dynamic> event) {
    final l = context.loc;
    final note = event['note']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.14)),
      ),
      child: SelectableText(
        l.text(
          'تم تغيير الحالة إلى ${event['toStatusLabel']} من ${event['actorDisplayName']}${note.isNotEmpty ? '\n$note' : ''}',
          'Status changed to ${event['toStatusLabel']} by ${event['actorDisplayName']}${note.isNotEmpty ? '\n$note' : ''}',
        ),
        style: AppTheme.caption,
      ),
    );
  }

  Widget _attachmentTile(Map<String, dynamic> file, {bool compact = false}) {
    final l = context.loc;
    final image = _isImageAttachment(file);
    final size = _formatBytes(file['sizeBytes']);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: compact ? 0 : 220,
        maxWidth: compact ? double.infinity : 320,
      ),
      child: Material(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _openAttachment(file),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  image ? Icons.image_outlined : Icons.description_outlined,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file['name']?.toString() ??
                            l.text('مرفق', 'Attachment'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyBold,
                      ),
                      Text(
                        image
                            ? l.text(
                                'عرض الصورة مباشرة - $size',
                                'View image directly - $size',
                              )
                            : l.text(
                                'فتح أو تحميل - $size',
                                'Open or download - $size',
                              ),
                        style: AppTheme.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(image ? Icons.visibility_rounded : Icons.download_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isImageAttachment(Map<String, dynamic> file) {
    final mime = file['mimeType']?.toString().toLowerCase() ?? '';
    return mime.startsWith('image/');
  }

  String _extensionFor(Map<String, dynamic> file) {
    final name = file['name']?.toString().toLowerCase() ?? '';
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot + 1).replaceAll(RegExp('[^a-z0-9]'), '');
    }
    final mime = file['mimeType']?.toString().toLowerCase() ?? '';
    if (mime.contains('pdf')) return 'pdf';
    if (mime.contains('png')) return 'png';
    if (mime.contains('webp')) return 'webp';
    if (mime.contains('jpeg')) return 'jpg';
    return 'txt';
  }

  MimeType _fileSaverMime(Map<String, dynamic> file) {
    final mime = file['mimeType']?.toString().toLowerCase() ?? '';
    if (mime.contains('pdf')) return MimeType.pdf;
    if (mime.contains('png')) return MimeType.png;
    if (mime.contains('jpeg')) return MimeType.jpeg;
    return MimeType.other;
  }

  String _safeFileName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'support-file' : cleaned;
  }

  String _formatBytes(dynamic value) {
    final bytes = int.tryParse(value?.toString() ?? '') ?? 0;
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool phone = false,
    int lines = 1,
  }) {
    return TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      keyboardType: phone ? TextInputType.phone : TextInputType.multiline,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}

class _SupportCountryPickerSheet extends StatefulWidget {
  const _SupportCountryPickerSheet();

  @override
  State<_SupportCountryPickerSheet> createState() =>
      _SupportCountryPickerSheetState();
}

class _SupportCountryPickerSheetState
    extends State<_SupportCountryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CountryOption> get _filteredCountries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return PhoneNumberService.countries;
    final digits = query.replaceAll(RegExp(r'\D'), '');
    return PhoneNumberService.countries.where((country) {
      final name = country.name.toLowerCase();
      return name.contains(query) ||
          country.flag.toLowerCase().contains(query) ||
          (digits.isNotEmpty && country.dialCode.contains(digits));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final countries = _filteredCountries;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.text('اختر الدولة', 'Choose Country'), style: AppTheme.h3),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.text(
                  'ابحث باسم الدولة أو كود الاتصال',
                  'Search by country name or calling code',
                ),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: countries.isEmpty
                  ? Center(
                      child: Text(
                        l.text(
                          'لا توجد دولة بهذا البحث',
                          'No country matches this search',
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: countries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final country = countries[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              country.flag,
                              style: AppTheme.caption.copyWith(fontSize: 11),
                            ),
                          ),
                          title: Text(country.name),
                          subtitle: Text('+${country.dialCode}'),
                          onTap: () => Navigator.pop(context, country),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
