import 'dart:async';
import 'dart:io';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/env.dart';
import '../../../core/widgets/widgets.dart';
import '../widgets/policies.dart';

/// One of our hosted pages (privacy, terms...) inside the app, under the app's own bar, so reading them never
/// leaves the app. JavaScript and file access are off (the pages need neither). Only our site loads here: another
/// of our pages opens as its own screen (Back steps through them), any other link opens in its own app.
class PolicyScreen extends StatefulWidget {
  const PolicyScreen({super.key, required this.page, this.base = Env.policiesUrl});

  final String page; // a [policyPages] key
  final String base; // the site, POLICIES_URL

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  late final _site = widget.base.replaceAll(RegExp(r'/+$'), '');
  late final _url = Uri.parse('$_site${policyPath(widget.page)}');
  WebViewController? _web;
  int _progress = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // shortcut: POLICIES_URL is unset until the pages are published; set it in env/*.json before release
    if (_site.isEmpty) return;
    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _navigate,
        onProgress: (p) => _set(() => _progress = p),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) _set(() => _error = SocketException(e.description));
        },
        // the page itself, not a font or the stylesheet
        onHttpError: (e) {
          if (e.request?.uri.path == _url.path) _set(() => _error = StateError('HTTP ${e.response?.statusCode}'));
        },
      ));
    if (web.platform case final AndroidWebViewController android) {
      unawaited(android.setAllowFileAccess(false));
      unawaited(android.setAllowContentAccess(false));
    }
    _web = web..loadRequest(_url);
  }

  /// The WebView can still report after the screen is gone.
  void _set(VoidCallback change) {
    if (mounted) setState(change);
  }

  NavigationDecision _navigate(NavigationRequest request) {
    final uri = Uri.parse(request.url);
    if (uri.scheme == 'https' && uri.host == _url.host) {
      final page = policyPage(uri.path);
      if (page == null || page == widget.page) return NavigationDecision.navigate;
      if (mounted) context.push('/policy/$page');
      return NavigationDecision.prevent;
    }
    unawaited(_openOutside(uri));
    return NavigationDecision.prevent;
  }

  /// tel:, https (WhatsApp, PhonePe...) and, from our own pages only, mailto:.
  Future<void> _openOutside(Uri uri) async {
    final ok = await launchExternal(uri, email: true);
    if (!ok && mounted) showMessage(context, 'Couldn’t open that link.');
  }

  void _retry() {
    setState(() {
      _error = null;
      _progress = 0;
    });
    _web!.loadRequest(_url);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(policyPages[widget.page] ?? 'Shyam Mobiles')),
        body: switch ((_web, _error)) {
          (null, _) => const EmptyState(
              icon: PhosphorIconsRegular.fileText,
              title: 'Coming soon',
              message: 'Our policy pages go live before launch.',
            ),
          (_, final error?) => ErrorView(error: error, onRetry: _retry),
          (final web?, null) => Stack(
              children: [
                WebViewWidget(controller: web),
                if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
              ],
            ),
        },
      );
}
