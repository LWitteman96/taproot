import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/features/reflection/domain/reflection_repository.dart';
import 'package:taproot/features/reflection/services/local_reflection_service.dart';

final reflectionServiceProvider = Provider<ReflectionRepository>(
  (ref) => LocalReflectionService(database: ref.watch(appDatabaseProvider)),
);
