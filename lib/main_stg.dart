import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'main.dart';

/// Entry point for the stg flavor.
void main() async {
  await dotenv.load(fileName: '.env.stg');
  await runMainApp();
}
