import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/account/data/profile_repository.dart';

import 'fake.dart';

class FakeProfileRepository with Fake implements ProfileRepository {
  final profiles = <String, Profile>{};
  final addressBook = <String, List<Address>>{}; // uid → addresses, default first
  bool hasActiveOrders = false;
  var _next = 0;

  @override
  Future<Profile?> profile(String uid) async {
    record('profile $uid');
    return profiles[uid];
  }

  @override
  Future<void> saveFullName(String uid, String? fullName) async {
    record('saveFullName $uid');
    profiles[uid] = Profile(id: uid, fullName: fullName, phone: profiles[uid]?.phone);
  }

  @override
  Future<List<Address>> addresses(String uid) async {
    record('addresses $uid');
    return [...?addressBook[uid]];
  }

  @override
  Future<Address> saveAddress(String uid, Address address) async {
    record('saveAddress $uid');
    final list = addressBook.putIfAbsent(uid, () => []);
    final saved = _withId(address, address.id ?? 'a${_next++}', isDefault: address.isDefault || list.isEmpty);
    final i = list.indexWhere((a) => a.id == saved.id);
    i < 0 ? list.add(saved) : list[i] = saved;
    return saved;
  }

  @override
  Future<void> setDefaultAddress(String uid, String addressId) async {
    record('setDefaultAddress $uid $addressId');
    final list = addressBook[uid] ?? [];
    addressBook[uid] = [
      for (final a in list) if (a.id == addressId) _withId(a, a.id!, isDefault: true),
      for (final a in list) if (a.id != addressId) _withId(a, a.id!, isDefault: false),
    ];
  }

  @override
  Future<void> deleteAddress(String uid, String addressId) async {
    record('deleteAddress $uid $addressId');
    addressBook[uid]?.removeWhere((a) => a.id == addressId);
  }

  @override
  Future<void> deleteAccount() async {
    record('deleteAccount');
    if (hasActiveOrders) throw reason('ACTIVE_ORDERS');
  }

  static Address _withId(Address a, String id, {required bool isDefault}) => Address(
        id: id,
        name: a.name,
        phone: a.phone,
        line1: a.line1,
        line2: a.line2,
        landmark: a.landmark,
        city: a.city,
        district: a.district,
        state: a.state,
        pincode: a.pincode,
        label: a.label,
        isDefault: isDefault,
      );
}
