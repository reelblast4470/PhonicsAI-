import 'package:flutter/foundation.dart';

/// An account on the PhonicsAI service. `isGuest` means "this device only":
/// progress still saves locally, but nothing can be synced or shared.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayName,
    this.email,
    required this.isGuest,
    required this.createdAt,
  });

  factory AuthUser.guest() => AuthUser(
    id: 'guest_device',
    displayName: 'This device',
    isGuest: true,
    createdAt: DateTime(1970),
  );

  final String id;
  final String displayName;
  final String? email;
  final bool isGuest;
  final DateTime createdAt;

  bool get canSync => !isGuest;

  String? get emailOrName => email ?? displayName;

  AuthUser copyWith({String? displayName, String? email}) => AuthUser(
    id: id,
    displayName: displayName ?? this.displayName,
    email: email ?? this.email,
    isGuest: isGuest,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': displayName,
    if (email != null) 'email': email,
    'guest': isGuest,
    'created': createdAt.toIso8601String(),
  };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    displayName: json['name'] as String? ?? 'Family',
    email: json['email'] as String?,
    isGuest: json['guest'] as bool? ?? false,
    createdAt:
        DateTime.tryParse(json['created'] as String? ?? '') ?? DateTime.now(),
  );

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.displayName == displayName &&
      other.email == email &&
      other.isGuest == isGuest;

  @override
  int get hashCode => Object.hash(id, displayName, email, isGuest);
}

@immutable
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.user,
    this.expiresAt,
  });

  /// Short-lived, minted by our backend. The client never holds an AI key.
  final String accessToken;
  final AuthUser user;
  final DateTime? expiresAt;

  bool isExpired([DateTime? now]) =>
      expiresAt != null && (now ?? DateTime.now()).isAfter(expiresAt!);
}

enum AuthStatus { unknown, signedOut, guest, signedIn }

@immutable
class AuthState {
  const AuthState({required this.status, this.user, this.session});

  const AuthState.unknown()
    : status = AuthStatus.unknown,
      user = null,
      session = null;

  const AuthState.signedOut()
    : status = AuthStatus.signedOut,
      user = null,
      session = null;

  factory AuthState.signedIn(AuthUser user, AuthSession session) => AuthState(
    status: user.isGuest ? AuthStatus.guest : AuthStatus.signedIn,
    user: user,
    session: session,
  );

  final AuthStatus status;
  final AuthUser? user;
  final AuthSession? session;

  bool get isSignedIn =>
      status == AuthStatus.signedIn || status == AuthStatus.guest;
  bool get hasRealAccount => status == AuthStatus.signedIn;
}
