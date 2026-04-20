import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/app_theme.dart';
import 'shwakel_button.dart';
import 'shwakel_card.dart';

class BarcodeScannerDialog extends StatefulWidget {
  const BarcodeScannerDialog({
    super.key,
    required this.title,
    required this.description,
    this.height = 320,
    this.showFrame = false,
    this.backgroundColor,
    this.borderRadius,
    this.onCancelLabel,
  });

  final String title;
  final String description;
  final double height;
  final bool showFrame;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;
  final String? onCancelLabel;

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _torchEnabled = false;
  bool _didScan = false;
  bool _isStarting = false;
  bool _isDisposed = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startScanner());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !_controller.value.hasCameraPermission) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_startScanner());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_controller.stop());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _startScanner() async {
    if (_isDisposed || _isStarting || _didScan) {
      return;
    }

    _isStarting = true;
    try {
      await _controller.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      _isStarting = false;
    }
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_didScan) {
      return;
    }

    final value = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((candidate) => candidate.isNotEmpty, orElse: () => '');
    if (value.isEmpty) {
      return;
    }

    _didScan = true;
    if (mounted) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ClipRRect(
      borderRadius: widget.borderRadius ?? AppTheme.radiusMd,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _handleDetect,
              errorBuilder: (context, error) {
                return _ScannerErrorView(
                  message: _errorText ?? error.errorDetails?.message,
                );
              },
            ),
            Positioned(
              top: 14,
              left: 14,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await _controller.toggleTorch();
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _torchEnabled = !_torchEnabled;
                  });
                },
                icon: Icon(
                  _torchEnabled
                      ? Icons.flash_off_rounded
                      : Icons.flash_on_rounded,
                ),
                label: Text(_torchEnabled ? 'إطفاء الإضاءة' : 'تشغيل الإضاءة'),
              ),
            ),
            if (widget.showFrame)
              Center(
                child: IgnorePointer(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.92),
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: widget.backgroundColor ?? Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ShwakelCard(
          padding: const EdgeInsets.all(24),
          borderRadius: widget.borderRadius is BorderRadius
              ? widget.borderRadius as BorderRadius
              : AppTheme.radiusMd,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(widget.title, style: AppTheme.h3)),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: AppTheme.bodyAction,
              ),
              const SizedBox(height: 18),
              scanner,
              if (widget.onCancelLabel != null) ...[
                const SizedBox(height: 18),
                ShwakelButton(
                  label: widget.onCancelLabel!,
                  isSecondary: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerErrorView extends StatelessWidget {
  const _ScannerErrorView({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceVariant,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.camera_alt_outlined,
            size: 36,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'تعذر تشغيل الكاميرا',
            style: AppTheme.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message?.trim().isNotEmpty == true
                ? message!
                : 'أغلق أي تطبيق آخر يستخدم الكاميرا ثم أعد المحاولة.',
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
