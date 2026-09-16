import 'package:flutter_test/flutter_test.dart';

import 'package:taproot/app/connectivity/connectivity_providers.dart';

void main() {
  group('isOnlineFrom', () {
    test('any interface that is not none counts as online', () {
      expect(isOnlineFrom(const [ConnectivityResult.wifi]), isTrue);
      expect(isOnlineFrom(const [ConnectivityResult.mobile]), isTrue);
      expect(isOnlineFrom(const [ConnectivityResult.ethernet]), isTrue);
      expect(isOnlineFrom(const [ConnectivityResult.vpn]), isTrue);
    });

    test('none is offline, and so is nothing at all', () {
      expect(isOnlineFrom(const [ConnectivityResult.none]), isFalse);
      expect(isOnlineFrom(const []), isFalse);
    });

    test('a device holding several interfaces is online', () {
      // The reason the plugin hands back a list rather than one value: wifi and
      // mobile on a phone, ethernet and a vpn on a desktop.
      expect(
        isOnlineFrom(const [ConnectivityResult.wifi, ConnectivityResult.vpn]),
        isTrue,
      );
    });

    test('one live interface alongside none is still online', () {
      expect(
        isOnlineFrom(const [ConnectivityResult.none, ConnectivityResult.wifi]),
        isTrue,
      );
    });
  });
}
