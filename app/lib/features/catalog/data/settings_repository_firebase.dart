import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/models.dart';
import 'settings_repository.dart';

/// settings/store and settings/business (functions/src/model/settings.ts). The store's phone and address shown to
/// customers come from settings/business, the one place invoices and the policy pages read them too.
class FirebaseSettingsRepository implements SettingsRepository {
  const FirebaseSettingsRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _store => _db.doc('settings/store');
  DocumentReference<Map<String, dynamic>> get _business => _db.doc('settings/business');

  @override
  Future<StoreSettings> storeSettings() async {
    final (store, business) = await (_store.get(), businessProfile()).wait;
    final s = store.data() ?? (throw StateError('settings/store is missing'));
    final pin = s['mapPin'] as Map?;
    final referral = Map<String, dynamic>.from(s['referral'] as Map? ?? const {});
    return StoreSettings(
      deliveryFeePaise: (s['deliveryFeePaise'] as num).toInt(),
      freeDeliveryMinPaise: (s['freeDeliveryMinPaise'] as num).toInt(),
      codEnabled: s['codEnabled'] == true,
      codMaxPaise: (s['codMaxPaise'] as num).toInt(),
      storePhone: business?.phone ?? '',
      storeAddress: business?.address ?? '',
      storeLat: (pin?['lat'] as num?)?.toDouble(),
      storeLng: (pin?['lng'] as num?)?.toDouble(),
      storeMapsUrl: s['mapsUrl'] as String?,
      storePhotos: [...?(s['storePhotos'] as List?)?.cast<String>()],
      storeHours: s['storeHours'] as String? ?? '',
      repairNote: s['repairNote'] as String? ?? '',
      returnsPolicy: s['returnsPolicy'] as String? ?? '',
      referralEnabled: referral['enabled'] == true,
      referralFriendPaise: (referral['friendPaise'] as num?)?.toInt() ?? 20000,
      referralRewardPaise: (referral['rewardPaise'] as num?)?.toInt() ?? 20000,
      referralMinOrderPaise: (referral['minOrderPaise'] as num?)?.toInt() ?? 199900,
      referralMonthlyCap: (referral['monthlyCap'] as num?)?.toInt() ?? 10,
    );
  }

  /// Phone and address are not written here: they belong to [saveBusinessProfile].
  @override
  Future<void> saveStoreSettings(StoreSettings s) => _store.update({
        'deliveryFeePaise': s.deliveryFeePaise,
        'freeDeliveryMinPaise': s.freeDeliveryMinPaise,
        'codEnabled': s.codEnabled,
        'codMaxPaise': s.codMaxPaise,
        'mapPin': s.storeLat == null || s.storeLng == null ? null : {'lat': s.storeLat, 'lng': s.storeLng},
        'mapsUrl': s.storeMapsUrl,
        'storeHours': s.storeHours,
        'repairNote': s.repairNote,
        'returnsPolicy': s.returnsPolicy,
        'referral': {
          'enabled': s.referralEnabled,
          'friendPaise': s.referralFriendPaise,
          'rewardPaise': s.referralRewardPaise,
          'minOrderPaise': s.referralMinOrderPaise,
          'monthlyCap': s.referralMonthlyCap,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> saveStorePhotos(List<String> paths) =>
      _store.update({'storePhotos': paths, 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Future<BusinessProfile?> businessProfile() async {
    final b = (await _business.get()).data();
    if (b == null) return null;
    final a = Map<String, dynamic>.from(b['address'] as Map);
    return BusinessProfile(
      tradeName: b['tradeName'] as String,
      legalName: b['legalName'] as String,
      gstin: b['gstin'] as String,
      phone: b['phone'] as String,
      email: b['email'] as String?,
      line1: a['line1'] as String,
      city: a['city'] as String,
      district: a['district'] as String,
      state: a['state'] as String,
      pincode: a['pincode'] as String,
    );
  }

  /// Brand name, business types and the invoice prefix aren't on the form, so they keep their saved values.
  @override
  Future<void> saveBusinessProfile(BusinessProfile p) => _business.update({
        'tradeName': p.tradeName,
        'legalName': p.legalName,
        'gstin': p.gstin,
        'stateCode': p.stateCode,
        'phone': p.phone,
        'email': p.email,
        'address': {'line1': p.line1, 'city': p.city, 'district': p.district, 'state': p.state, 'pincode': p.pincode},
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
