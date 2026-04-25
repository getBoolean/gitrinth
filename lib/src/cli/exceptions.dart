import 'exit_codes.dart';

abstract class GitrinthException implements Exception {
  final String message;
  const GitrinthException(this.message);

  int get exitCode;

  @override
  String toString() => message;
}

class UsageError extends GitrinthException {
  const UsageError(super.message);

  @override
  int get exitCode => exitUsageError;
}

class UserError extends GitrinthException {
  const UserError(super.message);

  @override
  int get exitCode => exitUserError;
}

class ValidationError extends GitrinthException {
  const ValidationError(super.message);

  @override
  int get exitCode => exitValidationError;
}

class CacheCorruptionError extends GitrinthException {
  const CacheCorruptionError(super.message);

  @override
  int get exitCode => exitCacheCorruption;
}
