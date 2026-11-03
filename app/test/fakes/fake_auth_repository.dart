import 'dart:async';

import 'package:shyam_mobiles/features/auth/data/auth_repository.dart';

import 'fake.dart';

/// Signed out until [signIn] or a sign-in method; any phone code equal to [code] works.
class FakeAuthRepository with Fake implements AuthRepository {
  FakeAuthRepository({this.user, this.role});

  AppUser? user;
  StaffRole? role;
  String code = '123456';
  final _changes = StreamController<AppUser?>.broadcast();

  void signIn(AppUser signedIn) => _changes.add(user = signedIn);

  @override
  Stream<AppUser?> userChanges() async* {
    yield user;
    yield* _changes.stream;
  }

  @override
  AppUser? get currentUser => user;

  @override
  Future<StaffRole?> staffRole() async => user == null ? null : role;

  @override
  Future<bool> signInWithGoogle() async {
    record('google');
    signIn(const AppUser(id: 'google-user', email: 'ravi@example.com', displayName: 'Ravi Kumar'));
    return true;
  }

  @override
  Future<PhoneCodeRequest> requestPhoneCode(String phone, {PhoneCodeRequest? resend}) async {
    record('requestPhoneCode $phone');
    return PhoneCodeRequest(phone: phone, verificationId: 'v-$phone');
  }

  @override
  Future<void> verifyPhoneCode(PhoneCodeRequest request, String code) async {
    record('verifyPhoneCode ${request.phone}');
    if (code != this.code) throw const FormatException('wrong code');
    signIn(AppUser(id: 'phone-${request.phone}', phone: request.phone));
  }

  @override
  Future<void> requestEmailCode(String email) async => record('requestEmailCode $email');

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    record('verifyEmailCode $email');
    signIn(AppUser(id: 'email-$email', email: email));
  }

  @override
  Future<void> signInForDev(String email, String password) async {
    record('dev $email');
    signIn(AppUser(id: 'dev-$email', email: email));
  }

  @override
  Future<void> signOut() async {
    record('signOut');
    _changes.add(user = null);
  }
}
