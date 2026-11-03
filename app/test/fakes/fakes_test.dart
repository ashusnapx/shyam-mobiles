import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shyam_mobiles/core/errors.dart';
import 'package:shyam_mobiles/core/models/models.dart';
import 'package:shyam_mobiles/features/account/data/profile_repository.dart';
import 'package:shyam_mobiles/features/auth/data/auth_repository.dart';
import 'package:shyam_mobiles/features/orders/data/orders_repository.dart';
import 'package:shyam_mobiles/features/repairs/data/repairs_repository.dart';

import 'fake_auth_repository.dart';
import 'fake_orders_repository.dart';
import 'fake_profile_repository.dart';
import 'fake_repairs_repository.dart';

// How widget tests use the fakes: override the repository provider (the DI seam) with a seeded fake, then check
// what the screen asked for in `calls`.
void main() {
  test('a fake replaces the repository behind its provider', () async {
    final orders = FakeOrdersRepository()
      ..nextQuote = const Quote(subtotalPaise: 50000, deliveryFeePaise: 4900, discountPaise: 0, totalPaise: 54900);
    final c = ProviderContainer(overrides: [ordersRepositoryProvider.overrideWithValue(orders)]);
    addTearDown(c.dispose);

    final quote = await c.read(ordersRepositoryProvider).quote(method: PaymentMethod.cod);
    expect(quote.totalPaise, 54900);
    expect(await c.read(ordersRepositoryProvider).placeOrder('a0', PaymentMethod.cod), 'o1');
    expect(orders.calls, ['quote - cod', 'placeOrder a0 cod -']);
  });

  test('a seam without an override says so (Phase 1 wires the real ones)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(() => c.read(ordersRepositoryProvider), throwsA(anything));
  });

  test('refusals carry the reason the app shows copy for', () async {
    final profile = FakeProfileRepository()..hasActiveOrders = true;
    final repairs = FakeRepairsRepository()..limit = 0;
    Future<String> copyOf(Future<void> f) => f.then((_) => '', onError: (Object e) => friendlyError(e));

    expect(await copyOf(profile.deleteAccount()), contains('You have orders or repairs in progress'));
    expect(
        await copyOf(repairs.book(
            deviceBrand: 'Samsung',
            deviceModel: 'A15',
            issue: RepairIssue.screen,
            description: '',
            preferredDate: '2026-11-05',
            slot: RepairSlot.morning,
            contactPhone: '+919876543210')),
        contains('3 repairs open'));
  });

  test('addresses: the first is the default, and a new default moves first', () async {
    final p = FakeProfileRepository();
    const home = Address(name: 'Ravi', phone: '+919876543210', line1: '1 Rajeev Complex', city: 'Waidhan', state: 'Madhya Pradesh', pincode: '486886');
    final a = await p.saveAddress('u1', home);
    final b = await p.saveAddress('u1', home);
    expect(a.isDefault, isTrue);
    await p.setDefaultAddress('u1', b.id!);
    expect([for (final x in await p.addresses('u1')) (x.id, x.isDefault)], [(b.id, true), (a.id, false)]);
  });

  test('phone sign-in', () async {
    final auth = FakeAuthRepository();
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
      repairsRepositoryProvider.overrideWithValue(FakeRepairsRepository()),
    ]);
    addTearDown(c.dispose);
    final req = await auth.requestPhoneCode('+919876543210');
    await auth.verifyPhoneCode(req, '123456');
    expect(auth.currentUser?.phone, '+919876543210');
    expect(await auth.staffRole(), isNull);
  });
}
