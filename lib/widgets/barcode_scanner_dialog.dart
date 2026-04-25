import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../localization/app_localization.dart';
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
    this.resultTitle,
    this.onScanResolved,
  });

  final String title;
  final String description;
  final double height;
  final bool showFrame;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;
  final String? onCancelLabel;
  final String? resultTitle;
  final Future<BarcodeScannerDialogResult?> Function(String value)?
  onScanResolved;

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
  bool _isResolving = false;
  bool _isRunningPrimaryAction = false;
  String? _errorText;
  BarcodeScannerDialogResult? _resolvedResult;

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
    if (_didScan || _isResolving) {
      return;
    }

    final value = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((candidate) => candidate.isNotEmpty, orElse: () => '');
    if (value.isEmpty) {
      return;
    }

    if (widget.onScanResolved == null) {
      _didScan = true;
      if (mounted) {
        Navigator.of(context).pop(value);
      }
      return;
    }

    _didScan = true;
    unawaited(_resolveScan(value));
  }

  Future<void> _resolveScan(String value) async {
    setState(() {
      _isResolving = true;
      _resolvedResult = null;
    });
    await _controller.stop();
    try {
      final result = await widget.onScanResolved?.call(value);
      if (!mounted) {
        return;
      }
      setState(() {
        _resolvedResult =
            result ??
            BarcodeScannerDialogResult.error(
              headline: context.loc.tr('widgets_barcode_scanner_dialog.002'),
              message: context.loc.tr('widgets_barcode_scanner_dialog.003'),
            );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _resolvedResult = BarcodeScannerDialogResult.error(
          headline: context.loc.tr('widgets_barcode_scanner_dialog.002'),
          message: error.toString(),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  Future<void> _resetScanner() async {
    if (!mounted) {
      return;
    }
    try {
      await _controller.stop();
    } catch (_) {
      // Ignore stop errors and continue with resetting the scanner state.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _didScan = false;
      _isResolving = false;
      _isRunningPrimaryAction = false;
      _resolvedResult = null;
      _errorText = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await _startScanner();
  }

  Future<void> _runPrimaryAction() async {
    final callback = _resolvedResult?.onPrimaryAction;
    if (callback == null || _isRunningPrimaryAction) {
      return;
    }
    setState(() => _isRunningPrimaryAction = true);
    try {
      final nextResult = await callback();
      if (!mounted) {
        return;
      }
      if (nextResult == null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _resolvedResult = nextResult;
      });
    } finally {
      if (mounted) {
        setState(() => _isRunningPrimaryAction = false);
      }
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
    final showingResult = _resolvedResult != null;
    final hideDialogHeader =
        showingResult && (_resolvedResult?.hideDialogHeader ?? false);
    final hideDialogDescription =
        showingResult && (_resolvedResult?.hideDialogDescription ?? false);
    final title = showingResult
        ? (widget.resultTitle?.trim().isNotEmpty == true
              ? widget.resultTitle!
              : context.loc.tr('widgets_barcode_scanner_dialog.001'))
        : widget.title;
    final scanner = _buildBodyContent();

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
                  Expanded(
                    child: showingResult
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: ShwakelButton(
                              label: context.loc.tr(
                                'widgets_barcode_scanner_dialog.004',
                              ),
                              isSecondary: true,
                              icon: Icons.qr_code_scanner_rounded,
                              onPressed: _resetScanner,
                            ),
                          )
                        : hideDialogHeader
                        ? const SizedBox.shrink()
                        : Text(title, style: AppTheme.h3),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (!hideDialogDescription) ...[
                const SizedBox(height: 12),
                Text(
                  showingResult
                      ? (_resolvedResult?.description ?? widget.description)
                      : widget.description,
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyAction,
                ),
                const SizedBox(height: 18),
              ] else
                const SizedBox(height: 8),
              scanner,
              if (showingResult &&
                  _resolvedResult?.primaryActionLabel != null) ...[
                const SizedBox(height: 18),
                ShwakelButton(
                  width: double.infinity,
                  label: _resolvedResult!.primaryActionLabel!,
                  icon:
                      _resolvedResult!.primaryActionIcon ??
                      Icons.check_circle_rounded,
                  onPressed: _resolvedResult!.onPrimaryAction == null
                      ? null
                      : _runPrimaryAction,
                  isLoading: _isRunningPrimaryAction,
                ),
              ] else if (widget.onCancelLabel != null) ...[
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

  Widget _buildBodyContent() {
    final radius = widget.borderRadius ?? AppTheme.radiusMd;
    if (_resolvedResult != null) {
      return _ScannerResolvedView(
        result: _resolvedResult!,
        height: widget.height,
        borderRadius: radius,
      );
    }
    if (_isResolving) {
      return _ScannerLoadingView(height: widget.height, borderRadius: radius);
    }

    return ClipRRect(
      borderRadius: radius,
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
                label: Text(
                  _torchEnabled
                      ? context.loc.tr('widgets_barcode_scanner_dialog.005')
                      : context.loc.tr('widgets_barcode_scanner_dialog.006'),
                ),
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
  }
}

class BarcodeScannerDialogResult {
  const BarcodeScannerDialogResult({
    required this.headline,
    required this.description,
    required this.color,
    required this.icon,
    this.items = const [],
    this.customContent,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.hideDialogHeader = false,
    this.hideDialogDescription = false,
  }) : isError = false;

  const BarcodeScannerDialogResult.error({
    required this.headline,
    required String message,
    this.items = const [],
    this.customContent,
  }) : description = message,
       color = AppTheme.error,
       icon = Icons.error_outline_rounded,
       primaryActionLabel = null,
       primaryActionIcon = null,
       onPrimaryAction = null,
       hideDialogHeader = false,
       hideDialogDescription = false,
       isError = true;

  final String headline;
  final String description;
  final Color color;
  final IconData icon;
  final bool isError;
  final List<BarcodeScannerDialogResultItem> items;
  final Widget? customContent;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final Future<BarcodeScannerDialogResult?> Function()? onPrimaryAction;
  final bool hideDialogHeader;
  final bool hideDialogDescription;
}

class BarcodeScannerDialogResultItem {
  const BarcodeScannerDialogResultItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _ScannerLoadingView extends StatelessWidget {
  const _ScannerLoadingView({required this.height, required this.borderRadius});

  final double height;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        color: AppTheme.surfaceVariant,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              context.loc.tr('widgets_barcode_scanner_dialog.007'),
              style: AppTheme.h3,
            ),
            const SizedBox(height: 8),
            Text(
              context.loc.tr('widgets_barcode_scanner_dialog.008'),
              textAlign: TextAlign.center,
              style: AppTheme.bodyAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerResolvedView extends StatelessWidget {
  const _ScannerResolvedView({
    required this.result,
    this.height,
    required this.borderRadius,
  });

  final BarcodeScannerDialogResult result;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    final hasCustomContent = result.customContent != null;
    final hasDescription = result.description.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        constraints: height == null ? null : BoxConstraints(minHeight: height!),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              result.color.withValues(alpha: 0.22),
              result.color.withValues(alpha: 0.07),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          border: Border.all(color: result.color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasCustomContent) ...[
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: result.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(result.icon, color: result.color, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                result.headline,
                style: AppTheme.h2.copyWith(color: result.color),
              ),
              if (hasDescription) const SizedBox(height: 8),
            ],
            if (hasDescription)
              Text(
                result.description,
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
              ),
            if (hasCustomContent) ...[
              const SizedBox(height: 18),
              result.customContent!,
            ],
            if (result.items.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: result.items
                    .map(
                      (item) =>
                          _ScannerResultTile(item: item, color: result.color),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScannerResultTile extends StatelessWidget {
  const _ScannerResultTile({required this.item, required this.color});

  final BarcodeScannerDialogResultItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(item.value, style: AppTheme.bodyBold),
              ],
            ),
          ),
        ],
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
            context.loc.tr('widgets_barcode_scanner_dialog.009'),
            style: AppTheme.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message?.trim().isNotEmpty == true
                ? message!
                : context.loc.tr('widgets_barcode_scanner_dialog.010'),
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
