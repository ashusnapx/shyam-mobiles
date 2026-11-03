import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/blocks.dart';
import '../../../core/widgets/widgets.dart';

/// Opens [uri] in another app (dialer, WhatsApp); shows [failure] if nothing can handle it. New code: [openUri].
Future<void> openExternal(BuildContext context, Uri uri, String failure) async {
  if (!await launchExternal(uri) && context.mounted) showMessage(context, failure);
}

/// wa.me chat with the store, optionally prefilled with [text]. New code: [whatsAppUri].
Uri whatsappUri(String storePhone, [String? text]) => whatsAppUri(storePhone, text: text);
