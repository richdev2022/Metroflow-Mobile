import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class JitsiCallScreen extends StatefulWidget {
  final String? roomId;
  final String? meetingUrl;
  final String title;
  final VoidCallback? onLeave;

  const JitsiCallScreen({
    super.key,
    this.roomId,
    this.meetingUrl,
    this.title = 'Meeting',
    this.onLeave,
  }) : assert(roomId != null || meetingUrl != null);

  static Future<void> showModal({
    required BuildContext context,
    String? roomId,
    String? meetingUrl,
    String title = 'Meeting',
    VoidCallback? onLeave,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: JitsiCallScreen(
          roomId: roomId,
          meetingUrl: meetingUrl,
          title: title,
          onLeave: onLeave,
        ),
      ),
    );
  }

  @override
  State<JitsiCallScreen> createState() => _JitsiCallScreenState();
}

class _JitsiCallScreenState extends State<JitsiCallScreen> {
  late final WebViewController _controller;
  bool _hasLeft = false;

  @override
  void initState() {
    super.initState();
    final meetingUri = widget.meetingUrl != null
        ? Uri.parse(widget.meetingUrl!)
        : Uri.parse('https://meet.jit.si/${widget.roomId}');
    _controller = WebViewController(
      onPermissionRequest: (request) {
        request.grant();
      },
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('Page started loading: $url');
          },
          onPageFinished: (url) {
            debugPrint('Page finished loading: $url');
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(meetingUri);
  }

  void _leave() {
    if (!_hasLeft) {
      _hasLeft = true;
      widget.onLeave?.call();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _leave,
        ),
        actions: [
          TextButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.call_end),
            label: const Text('Leave'),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
