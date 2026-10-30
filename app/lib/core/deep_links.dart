import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../features/offers/data/offers.dart';
import 'links.dart';
import 'router.dart';
import 'supabase.dart';
import 'widgets/widgets.dart';

const _pendingKey = 'pending_referral';
const _referrerKey = 'install_referrer_read';

Future<SharedPreferences?> _prefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null; // no plugin (tests)
  }
}

final pendingReferralProvider = NotifierProvider<PendingReferral, void>(PendingReferral.new);

/// A friend's referral code from a shared link, kept on the phone until someone signs in, then applied once.
class PendingReferral extends Notifier<void> {
  bool _busy = false;

  @override
  void build() {
    ref.listen(currentUserIdProvider, (_, id) {
      if (id != null) unawaited(apply());
    }, fireImmediately: true);
  }

  Future<void> remember(String code) async {
    await (await _prefs())?.setString(_pendingKey, code);
    await apply();
  }

  /// Applies the kept code when signed in and still allowed (no friend's code yet, no order yet). Not allowed, or
  /// any REFERRAL_* refusal (own code, unknown, too late): dropped quietly. Offline: kept for the next sign-in or
  /// launch. One try per call, so it never loops.
  Future<void> apply() async {
    if (_busy || ref.read(currentUserIdProvider) == null) return;
    final prefs = await _prefs();
    final code = prefs?.getString(_pendingKey);
    if (prefs == null || code == null) return;
    _busy = true;
    try {
      final api = ref.read(offersApiProvider);
      if ((await api.myReferral()).canEnterCode) {
        final welcome = await api.applyReferral(code);
        ref.invalidate(myReferralProvider);
        ref.invalidate(availableOffersProvider);
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) showMessage(context, friendCodeMessage(welcome));
      }
      await prefs.remove(_pendingKey);
    } on PostgrestException catch (e) {
      if (e.message.startsWith('REFERRAL_')) await prefs.remove(_pendingKey);
    } catch (_) {
      // offline or failing: try again at the next sign-in or launch
    } finally {
      _busy = false;
    }
  }

  /// First launch after a Play install from a shared link: open.html put the link's `p=…&ref=…` in the store
  /// link's `referrer`, and Play hands it back here. Opens that product or offer and keeps the code. Android, once.
  Future<void> followInstallReferrer() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final prefs = await _prefs();
    if (prefs == null || prefs.getBool(_referrerKey) == true) return;
    try {
      final referrer = (await PlayInstallReferrer.installReferrer).installReferrer ?? '';
      final link = openLink(Uri(path: '/open', query: referrer)); // organic installs carry utm_* only
      if (link?.code case final code?) await remember(code);
      if (link == null || link.to == '/') return;
      await WidgetsBinding.instance.endOfFrame; // the router is attached by now
      ref.read(routerProvider).go(link.to);
    } catch (_) {
      // no Play Store (sideloaded) or it timed out: nothing to follow
    } finally {
      await prefs.setBool(_referrerKey, true);
    }
  }
}
