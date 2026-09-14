/// Normalised, user-presentable error type shared by every layer above data.
enum FailureKind {
  offline,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  quotaExhausted,
  paymentRequired,
  storage,
  validation,
  parse,
  unsupportedHardware,
  cancelled,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure({
    required this.kind,
    required this.message,
    this.detail,
    this.recoverable = true,
  });

  const AppFailure.offline([this.detail = 'No connection'])
    : kind = FailureKind.offline,
      message = 'You are offline. Progress is saved on this device.',
      recoverable = true;

  const AppFailure.validation(this.message, [this.detail = 'invalid input'])
    : kind = FailureKind.validation,
      recoverable = true;

  const AppFailure.unknown([this.detail = 'Unknown error'])
    : kind = FailureKind.unknown,
      message = 'Something went wrong.',
      recoverable = true;

  final FailureKind kind;

  /// Safe to show to a child/parent. Never put server noise or secrets here.
  final String message;

  /// Debug-only extra context (logged, never rendered verbatim).
  final String? detail;
  final bool recoverable;

  bool get isAuthRelated =>
      kind == FailureKind.unauthorized || kind == FailureKind.forbidden;

  @override
  @override
  String toString() => 'AppFailure(${kind.name}): $message${detail == null ? "" : " ($detail)"}';
}
