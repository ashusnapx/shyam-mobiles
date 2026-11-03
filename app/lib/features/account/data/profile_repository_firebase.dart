import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/callable.dart';
import '../../../core/models/models.dart';
import 'address_form.dart' show gstStateCodes;
import 'profile.dart' show displayName, validatePersonName;
import 'profile_repository.dart';

/// users/{uid} and its addresses under the Rules in firebase/firestore.rules (owner: A); account deletion and the
/// data export through the account callables.
class FirebaseProfileRepository implements ProfileRepository {
  FirebaseProfileRepository(this._db, this._functions, this._auth);

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _user(String uid) => _db.doc('users/$uid');
  CollectionReference<Map<String, dynamic>> _book(String uid) => _user(uid).collection('addresses');

  /// users/{uid} is created on the first read after sign-in: Google's name when it passes validatePersonName (else
  /// null, and the app asks), the verified phone and the Google photo, as the Rules allow (docs/FIREBASE.md §4).
  @override
  Future<Profile?> profile(String uid) async {
    var d = await _user(uid).get();
    if (!d.exists) {
      final u = _auth.currentUser;
      final google = u?.displayName == null ? null : displayName(u!.displayName!);
      await _user(uid).set({
        'fullName': google != null && validatePersonName(google) == null ? google : null,
        'phone': ?u?.phoneNumber,
        if (u?.photoURL case final photo? when photo.startsWith('https://') && photo.length <= 500) 'photoUrl': photo,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      d = await _user(uid).get();
    }
    return Profile(id: uid, fullName: d.data()?['fullName'] as String?, phone: d.data()?['phone'] as String?);
  }

  @override
  Future<void> saveFullName(String uid, String? fullName) async {
    await profile(uid); // exists from here on
    await _user(uid).update({'fullName': (fullName?.isEmpty ?? true) ? null : fullName, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Default first, then newest. A default that was deleted falls to the newest address.
  @override
  Future<List<Address>> addresses(String uid) async {
    final (user, book) = await (_user(uid).get(), _book(uid).get()).wait;
    final docs = [...book.docs]
      ..sort((a, b) => (b.data()['createdAt'] as Timestamp? ?? Timestamp.now())
          .compareTo(a.data()['createdAt'] as Timestamp? ?? Timestamp.now()));
    final defaultId = docs.any((d) => d.id == user.data()?['defaultAddressId']) ? user.data()!['defaultAddressId'] : docs.firstOrNull?.id;
    return [
      for (final d in docs) if (d.id == defaultId) _address(d, isDefault: true),
      for (final d in docs) if (d.id != defaultId) _address(d, isDefault: false),
    ];
  }

  /// A new address takes the first free id of a0..a9 (ADDRESS_LIMIT when all ten are used).
  @override
  Future<Address> saveAddress(String uid, Address a) async {
    final book = await _book(uid).get();
    final id = a.id ?? [for (var i = 0; i < 10; i++) 'a$i'].where((id) => book.docs.every((d) => d.id != id)).firstOrNull;
    if (id == null) {
      throw FirebaseFunctionsException(code: 'failed-precondition', message: 'ADDRESS_LIMIT', details: const {'reason': 'ADDRESS_LIMIT'});
    }
    final fields = {
      'name': a.name,
      'phone': a.phone,
      'line1': a.line1,
      if (a.line2 case final v? when v.isNotEmpty) 'line2': v,
      if (a.landmark case final v? when v.isNotEmpty) 'landmark': v,
      'city': a.city,
      if (a.district case final v? when v.isNotEmpty) 'district': v,
      'state': a.state,
      'stateCode': gstStateCodes[a.state],
      'pincode': a.pincode,
      'label': a.label.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final ref = _book(uid).doc(id);
    final batch = _db.batch();
    // set() without merge, so a cleared line2 or landmark goes; createdAt is kept as Rules require.
    final old = book.docs.where((d) => d.id == id).firstOrNull;
    batch.set(ref, {...fields, 'createdAt': old?.data()['createdAt'] ?? FieldValue.serverTimestamp()});
    final isDefault = a.isDefault || book.docs.isEmpty;
    if (isDefault) batch.update(_user(uid), {'defaultAddressId': id, 'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
    return _withId(a, id, isDefault: isDefault);
  }

  @override
  Future<void> setDefaultAddress(String uid, String addressId) =>
      _user(uid).update({'defaultAddressId': addressId, 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Future<void> deleteAddress(String uid, String addressId) => _book(uid).doc(addressId).delete();

  @override
  Future<void> deleteAccount() => callFunction(_functions, 'deleteAccount', const {}, true);

  @override
  Future<Map<String, Object?>> exportMyData(String uid) async =>
      Map<String, Object?>.from((await callFunction(_functions, 'exportMyData'))['data'] as Map);

  static Address _address(QueryDocumentSnapshot<Map<String, dynamic>> d, {required bool isDefault}) =>
      Address.fromJson({...d.data(), 'id': d.id, 'is_default': isDefault});

  static Address _withId(Address a, String id, {required bool isDefault}) =>
      Address.fromJson({...a.toJson(), 'id': id, 'is_default': isDefault});
}
