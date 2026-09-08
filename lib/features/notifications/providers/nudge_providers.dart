import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:taproot/app/database/database_provider.dart';
import 'package:taproot/features/notifications/domain/nudge_repository.dart';
import 'package:taproot/features/notifications/services/local_nudge_service.dart';

final nudgeServiceProvider = Provider<NudgeRepository>(
  (ref) => LocalNudgeService(database: ref.watch(appDatabaseProvider)),
);
