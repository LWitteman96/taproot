import 'package:meta/meta.dart';

/// What the user did with a notification.
enum NudgeResponseAction {
  /// "Yes" — tomorrow, as designed. An implementation intention, and the
  /// cheapest confirmation the flow has (growth spec §6).
  confirmed,

  /// "Different day" — a decline is not a failure, it is data. Day-of-week
  /// preference falls out of these within a fortnight (growth spec §8).
  declined,

  /// The notification body itself was tapped: open the check-in.
  opened,
}

/// The identifiers a notification carries back when it is answered.
///
/// A notification response can arrive minutes or hours after the app died, in
/// a background isolate with no providers, so everything needed to record the
/// answer travels in the payload rather than in memory.
@immutable
class NudgePayload {
  const NudgePayload({required this.nudgeId, required this.habitId});

  /// Ledger row this notification belongs to.
  final String nudgeId;

  final String habitId;

  /// `nudge/v1/<nudgeId>/<habitId>`.
  ///
  /// Versioned because payloads outlive the build that wrote them: a
  /// notification scheduled a week ago is parsed by whatever version of the
  /// app happens to be installed when it fires, and an unrecognised shape has
  /// to be *identified* as unrecognised rather than mis-parsed into the wrong
  /// habit's ledger.
  String encode() => 'nudge/$_version/$nudgeId/$habitId';

  /// Null when [raw] is absent, or is not a payload this version wrote.
  static NudgePayload? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('/');
    if (parts.length != 4) return null;
    if (parts[0] != 'nudge' || parts[1] != _version) return null;
    if (parts[2].isEmpty || parts[3].isEmpty) return null;
    return NudgePayload(nudgeId: parts[2], habitId: parts[3]);
  }

  static const String _version = 'v1';

  @override
  bool operator ==(Object other) =>
      other is NudgePayload &&
      other.nudgeId == nudgeId &&
      other.habitId == habitId;

  @override
  int get hashCode => Object.hash(nudgeId, habitId);

  @override
  String toString() => 'NudgePayload($nudgeId, $habitId)';
}

/// Action identifiers, as the platforms see them. Stable strings: they are
/// baked into notifications already sitting in the OS queue.
abstract final class NudgeActionIds {
  static const String confirm = 'nudge_confirm';
  static const String decline = 'nudge_decline';

  /// The Darwin notification category the two actions hang off.
  static const String category = 'taproot_nudge';

  static NudgeResponseAction? actionFor(String? actionId) => switch (actionId) {
    confirm => NudgeResponseAction.confirmed,
    decline => NudgeResponseAction.declined,
    null || '' => NudgeResponseAction.opened,
    _ => null,
  };
}
