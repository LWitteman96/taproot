import 'package:flutter_test/flutter_test.dart';

import '../../utils/fake_repositories.dart';
import '../../utils/store_contract.dart';

/// The fakes are held to exactly the contract the SQLite store is held to.
///
/// Feature tests will run against these, so any behaviour they invent — or
/// quietly drop — would become a passing test for an app that does not work.
void main() {
  group('in-memory fakes', () {
    storeContract(openFakeStore);
  });
}
