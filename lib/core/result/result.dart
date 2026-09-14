import '../error/failure.dart';

/// Result of an operation that can fail in an *expected* way.
///
/// Repositories/services return `Result<T>` instead of throwing so the UI can
/// render a dedicated error state for every screen without try/catch soup.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.fail(AppFailure failure) = Fail<T>;

  bool get isOk => this is Ok<T>;
  bool get isFailure => this is Fail<T>;

  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Fail<T>() => null,
  };

  AppFailure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Fail<T>(:final failure) => failure,
  };

  R fold<R>({
    required R Function(T value) ok,
    required R Function(AppFailure failure) fail,
  }) {
    return switch (this) {
      Ok<T>(:final value) => ok(value),
      Fail<T>(:final failure) => fail(failure),
    };
  }

  /// Throws only in development/tests; production code should branch instead.
  T get requireValue => switch (this) {
    Ok<T>(:final value) => value,
    Fail<T>(:final failure) => throw ResultAccessException(failure),
  };

  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Ok<T>(:final value) => Result<R>.ok(transform(value)),
      Fail<T>(:final failure) => Result<R>.fail(failure),
    };
  }
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Fail<T> extends Result<T> {
  const Fail(this.failure);
  final AppFailure failure;
}

class ResultAccessException implements Exception {
  const ResultAccessException(this.failure);
  final AppFailure failure;

  @override
  String toString() => 'Result accessed while failed: ${failure.message}';
}
