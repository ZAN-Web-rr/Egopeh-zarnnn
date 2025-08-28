import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CheckOutPage extends StatefulWidget {
  final String url;
  const CheckOutPage({Key? key, required this.url}) : super(key: key);

  @override
  State<CheckOutPage> createState() => _CheckOutPageState();
}

class _CheckOutPageState extends State<CheckOutPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Called when the WebView is about to navigate to a new url.
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;

            if (url.startsWith('https://success.com')) {
              // return a value to the previous route and prevent further navigation
              Navigator.of(context).pop('success');
              return NavigationDecision.prevent;
            } else if (url.startsWith('https://cancel.com')) {
              Navigator.of(context).pop('cancel');
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            // optional: show loader, etc.
          },
          onPageFinished: (String url) {
            // optional: hide loader, etc.
          },
          onProgress: (int progress) {
            // optional: update a progress indicator
          },
          onWebResourceError: (WebResourceError error) {
            // optional: handle errors
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // You can add an AppBar, progress indicator, etc.
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
