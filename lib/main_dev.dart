import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'main.dart';

/// Entry point for the dev flavor.
void main() async {
  await dotenv.load(fileName: '.env.dev');
  await runMainApp();
}
