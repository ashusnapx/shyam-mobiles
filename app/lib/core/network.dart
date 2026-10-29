import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'env.dart';

/// How much the app downloads. Saver: thumbnails, no hero auto-advance, smaller search pages, no prefetching.
enum DataMode { full, saver }

/// The customer's choice in Account → Data saver.
enum DataSaverSetting {
  auto('Auto'),
  on('On'),
  off('Off');

  const DataSaverSetting(this.label);

  final String label;
}

/// connectivity_plus boiled down. [unknown] before the first check, or for VPN/Bluetooth alone.
enum NetType { unknown, none, mobile, wifi }

NetType netTypeOf(List<ConnectivityResult> r) => r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)
    ? NetType.wifi
    : r.contains(ConnectivityResult.mobile)
        ? NetType.mobile
        : r.every((x) => x == ConnectivityResult.none)
            ? NetType.none
            : NetType.unknown;

/// A fresh HTTPS request (DNS + TLS + one round trip) slower than this means roughly a 200 ms+ round trip.
const slowLatencyMs = 800;

/// Auto saves data on low-RAM phones and slow networks. Mobile data counts as slow until a probe has measured it;
/// going offline changes nothing (saved photos show either way).
DataMode decideDataMode({
  required DataSaverSetting setting,
  required NetType net,
  int? latencyMs,
  bool lowRam = false,
}) =>
    switch (setting) {
      DataSaverSetting.on => DataMode.saver,
      DataSaverSetting.off => DataMode.full,
      DataSaverSetting.auto =>
        lowRam || (latencyMs == null ? net == NetType.mobile : latencyMs > slowLatencyMs) ? DataMode.saver : DataMode.full,
    };

typedef NetSignals = ({DataSaverSetting setting, NetType net, int? latencyMs, bool lowRam});

/// Watches the setting, connectivity, a latency probe and the device. Does nothing until [start] (main() calls it),
/// so tests stay in full mode, online, with no platform calls.
class NetworkMonitor extends Notifier<NetSignals> {
  static const _settingKey = 'data_saver';
  static const _latencyKey = 'net_latency_ms'; // last probe, so a cold start doesn't guess
  static const probeEvery = Duration(minutes: 3);

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;
  bool _probing = false;

  @override
  NetSignals build() {
    ref.onDispose(() {
      _sub?.cancel();
      _timer?.cancel();
    });
    return (setting: DataSaverSetting.auto, net: NetType.unknown, latencyMs: null, lowRam: false);
  }

  void _set({DataSaverSetting? setting, NetType? net, int? latencyMs}) => state = (
        setting: setting ?? state.setting,
        net: net ?? state.net,
        latencyMs: latencyMs ?? state.latencyMs,
        lowRam: state.lowRam,
      );

  /// Quick reads (setting, device, connectivity) before the first frame; the probe runs in the background.
  Future<void> start() async {
    if (_sub != null) return;
    final prefs = await _prefs();
    var lowRam = false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        lowRam = (await DeviceInfoPlugin().androidInfo).isLowRamDevice;
      } catch (_) {}
    }
    if (lowRam) capImageCache();
    final connectivity = Connectivity();
    var net = NetType.unknown;
    try {
      net = netTypeOf(await connectivity.checkConnectivity());
    } catch (_) {}
    state = (
      setting: DataSaverSetting.values.asNameMap()[prefs?.getString(_settingKey)] ?? DataSaverSetting.auto,
      net: net,
      latencyMs: prefs?.getInt(_latencyKey),
      lowRam: lowRam,
    );
    _sub = connectivity.onConnectivityChanged.listen((r) {
      final now = netTypeOf(r);
      if (now == state.net) return;
      _set(net: now);
      unawaited(_probe()); // a different network: measure it again
    }, onError: (Object _) {});
    _timer = Timer.periodic(probeEvery, (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) unawaited(_probe());
    });
    unawaited(_probe());
  }

  /// Times the auth health endpoint: tiny, public, and on the same host as everything else.
  Future<void> _probe() async {
    if (_probing || state.net == NetType.none) return;
    _probing = true;
    final watch = Stopwatch()..start();
    int? ms;
    try {
      await http.get(
        Uri.parse('${Env.supabaseUrl}/auth/v1/health'),
        headers: {'apikey': Env.supabasePublishableKey},
      ).timeout(const Duration(seconds: 5));
      ms = watch.elapsedMilliseconds;
    } on TimeoutException {
      ms = watch.elapsedMilliseconds;
    } catch (_) {
      // unreachable right now: keep the last reading
    } finally {
      _probing = false;
    }
    if (ms == null || !ref.mounted) return;
    _set(latencyMs: ms);
    await (await _prefs())?.setInt(_latencyKey, ms);
  }

  Future<void> setSetting(DataSaverSetting s) async {
    _set(setting: s);
    await (await _prefs())?.setString(_settingKey, s.name);
  }
}

Future<SharedPreferences?> _prefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null; // no plugin (tests): settings just aren't remembered
  }
}

/// Low-RAM (Android Go) phones: a smaller decoded-image cache than Flutter's 100 MB / 1000 images.
void capImageCache() {
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 32 << 20
    ..maximumSize = 200;
}

final networkProvider = NotifierProvider<NetworkMonitor, NetSignals>(NetworkMonitor.new);

final dataSaverProvider = Provider<DataMode>((ref) {
  final s = ref.watch(networkProvider);
  return decideDataMode(setting: s.setting, net: s.net, latencyMs: s.latencyMs, lowRam: s.lowRam);
});

/// For the "You're offline" banner.
final offlineProvider = Provider<bool>((ref) => ref.watch(networkProvider).net == NetType.none);

// Saved payloads ------------------------------------------------------------------

/// The last good copy of a small public payload (home, store settings), as JSON in shared_preferences.
Future<Object?> readSaved(String key) async {
  try {
    final s = (await _prefs())?.getString('saved:$key');
    return s == null ? null : jsonDecode(s);
  } catch (_) {
    return null;
  }
}

Future<void> writeSaved(String key, Object? json) async {
  try {
    await (await _prefs())?.setString('saved:$key', jsonEncode(json));
  } catch (_) {} // a cache: losing it only costs a skeleton next time
}

final _served = <String>{};
final _fresh = <String, Object?>{};

/// Stale-while-revalidate for a FutureProvider: the first load of the session returns the saved copy at once (when
/// there is one) and refetches in the background, then rebuilds the provider with the fresh data. Later loads fetch.
/// [fetch] returns plain JSON (PostgREST rows), which is what gets saved; [parse] turns it into the model.
Future<T> savedOrFetch<T>(Ref ref, String key, Future<Object?> Function() fetch, T Function(Object? json) parse) async {
  if (_fresh.containsKey(key)) return parse(_fresh.remove(key));
  if (_served.add(key)) {
    final saved = await readSaved(key);
    if (saved != null) {
      try {
        final value = parse(saved);
        unawaited(fetch().then((json) {
          unawaited(writeSaved(key, json));
          if (!ref.mounted) return;
          _fresh[key] = json;
          ref.invalidateSelf();
        }, onError: (Object _) {})); // offline or failing: keep showing the saved copy
        return value;
      } catch (_) {} // saved by an older version in another shape: fetch instead
    }
  }
  final json = await fetch();
  unawaited(writeSaved(key, json));
  return parse(json);
}
