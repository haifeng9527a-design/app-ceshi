import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AppWebViewPage extends StatefulWidget {
  const AppWebViewPage({
    super.key,
    required this.url,
    this.title,
    this.allowedHosts = const <String>[],
    this.apiBaseUrl,
    this.authToken,
  });

  final String url;
  final String? title;
  final List<String> allowedHosts;
  /// 后端 API 地址，供 HTML 调用接口时使用
  final String? apiBaseUrl;
  /// Firebase ID Token，供 HTML 调用需鉴权接口时使用
  final String? authToken;

  @override
  State<AppWebViewPage> createState() => _AppWebViewPageState();
}

class _AppWebViewPageState extends State<AppWebViewPage> {
  late final WebViewController _controller;
  late final Uri _initialUri;
  bool _loading = true;
  String? _pageTitle;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _initialUri = Uri.parse(widget.url);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _errorText = null;
              });
            }
          },
          onPageFinished: (_) async {
            await _injectCurrentUserIfAllowed();
            if (!mounted) return;
            final t = await _controller.getTitle();
            setState(() {
              _loading = false;
              _pageTitle = t;
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _errorText = error.description;
            });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            final sameHost = uri.host.toLowerCase() == _initialUri.host.toLowerCase();
            if (!sameHost) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(_initialUri);
  }

  bool _isAllowedHost(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (widget.allowedHosts.isEmpty) return host == _initialUri.host.toLowerCase();
    return widget.allowedHosts.map((e) => e.toLowerCase()).contains(host);
  }

  Future<void> _injectCurrentUserIfAllowed() async {
    if (!_isAllowedHost(_initialUri)) return;
    final u = FirebaseAuth.instance.currentUser;
    final user = <String, dynamic>{
      'uid': u?.uid,
      'isAnonymous': u?.isAnonymous ?? true,
    };
    final apiBaseUrl = widget.apiBaseUrl;
    final authToken = widget.authToken;
    final payload = jsonEncode({
      'user': user,
      'app': {'name': 'teacher_hub', 'version': '0.1.1'},
      if (apiBaseUrl != null && apiBaseUrl.isNotEmpty) 'apiBaseUrl': apiBaseUrl,
      if (authToken != null && authToken.isNotEmpty) 'authToken': authToken,
    });
    await _controller.runJavaScript('''
      window.TeacherHub = $payload;
      window.getTeacherHubCurrentUser = function() {
        return window.TeacherHub ? window.TeacherHub.user : null;
      };
      window.dispatchEvent(new CustomEvent('TeacherHubReady', { detail: window.TeacherHub }));
    ''');
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : (_pageTitle?.trim().isNotEmpty == true
            ? _pageTitle!.trim()
            : Uri.tryParse(widget.url)?.host ?? 'Web');
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Stack(
        children: [
          if (_errorText == null)
            WebViewWidget(controller: _controller)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorText!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _errorText = null;
                        });
                        _controller.loadRequest(_initialUri);
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

Future<void> openInAppWebView(
  BuildContext context, {
  required String url,
  String? title,
  List<String> allowedHosts = const <String>[],
  String? apiBaseUrl,
  String? authToken,
}) async {
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AppWebViewPage(
        url: url,
        title: title,
        allowedHosts: allowedHosts,
        apiBaseUrl: apiBaseUrl,
        authToken: authToken,
      ),
    ),
  );
}
