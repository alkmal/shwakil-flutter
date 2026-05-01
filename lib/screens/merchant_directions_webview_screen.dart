import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/app_theme.dart';

class MerchantDirectionsWebViewScreen extends StatefulWidget {
  const MerchantDirectionsWebViewScreen({
    super.key,
    required this.title,
    required this.destinationLatitude,
    required this.destinationLongitude,
    this.originLatitude,
    this.originLongitude,
  });

  final String title;
  final double destinationLatitude;
  final double destinationLongitude;
  final double? originLatitude;
  final double? originLongitude;

  @override
  State<MerchantDirectionsWebViewScreen> createState() =>
      _MerchantDirectionsWebViewScreenState();
}

class _MerchantDirectionsWebViewScreenState
    extends State<MerchantDirectionsWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        ),
      )
      ..loadRequest(_directionsUri());
  }

  Uri _directionsUri() {
    final destination =
        '${widget.destinationLatitude},${widget.destinationLongitude}';
    final params = <String, String>{
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
    };
    if (widget.originLatitude != null && widget.originLongitude != null) {
      params['origin'] = '${widget.originLatitude},${widget.originLongitude}';
    }
    return Uri.https('www.google.com', '/maps/dir/', params);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
