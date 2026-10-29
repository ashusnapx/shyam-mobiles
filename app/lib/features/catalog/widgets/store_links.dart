import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/widgets.dart';

/// Opens [uri] in another app (dialer, WhatsApp); shows [failure] if nothing can handle it.
Future<void> openExternal(BuildContext context, Uri uri, String failure) async {
  if (!await launchExternal(uri) && context.mounted) showMessage(context, failure);
}

/// wa.me chat with the store, optionally prefilled with [text].
Uri whatsappUri(String storePhone, [String? text]) => Uri.parse(
      'https://wa.me/${storePhone.replaceAll(RegExp(r'\D'), '')}${text == null ? '' : '?text=${Uri.encodeComponent(text)}'}',
    );
