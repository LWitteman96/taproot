import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:connectivity_plus/connectivity_plus.dart'
    show Connectivity, ConnectivityResult;

/// The platform connectivity plugin, behind a provider so a test can hand in a
/// stream it controls.
final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

/// Whether the device currently has a network interface up.
///
/// **An interface, not reachability.** connectivity_plus reports what the OS
/// says about the radios and adapters; it cannot tell a working connection from
/// a captive portal, a hotel wifi that wants a login, or a tunnel that is up
/// but going nowhere. So this is a *trigger*, not a guarantee — the honest
/// reading of `true` is "worth trying now", and the sync drain has to survive
/// being wrong about it. That is the same reason the drain is idempotent rather
/// than one-shot.
///
/// The plugin emits a list because a device can hold several interfaces at once
/// — wifi and mobile on a phone, ethernet and vpn on a desktop. Anything other
/// than [ConnectivityResult.none] counts, and an empty list is offline.
final isOnlineProvider = StreamProvider<bool>(
  (ref) =>
      ref.watch(connectivityProvider).onConnectivityChanged.map(isOnlineFrom),
);

/// Whether [results] describes a device with a usable interface.
///
/// Its own function so the rule is testable without a stream, and stated once
/// rather than at each call site.
bool isOnlineFrom(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none);
