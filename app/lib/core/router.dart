import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../features/account/screens/account_screen.dart';
import '../features/account/screens/address_form_screen.dart';
import '../features/account/screens/addresses_screen.dart';
import '../features/account/screens/profile_screen.dart';
import '../features/admin/screens/admin_banners_screen.dart';
import '../features/admin/screens/admin_catalogue_screen.dart';
import '../features/admin/screens/admin_dashboard_screen.dart';
import '../features/admin/screens/admin_feedback_screen.dart';
import '../features/admin/screens/admin_groups_screen.dart';
import '../features/admin/screens/admin_offers_screen.dart';
import '../features/admin/screens/admin_order_screen.dart';
import '../features/admin/screens/admin_orders_screen.dart';
import '../features/admin/screens/admin_product_edit_screen.dart';
import '../features/admin/screens/admin_products_screen.dart';
import '../features/admin/screens/admin_repair_screen.dart';
import '../features/admin/screens/admin_repairs_screen.dart';
import '../features/admin/screens/admin_settings_screen.dart';
import '../features/auth/screens/sign_in_screen.dart';
import '../features/auth/screens/verify_code_screen.dart';
import '../features/cart/data/cart.dart';
import '../features/cart/screens/cart_screen.dart';
import '../features/catalog/screens/home_screen.dart';
import '../features/catalog/screens/product_screen.dart';
import '../features/catalog/screens/search_screen.dart';
import '../features/checkout/screens/checkout_result_screen.dart';
import '../features/checkout/screens/checkout_screen.dart';
import '../features/offers/screens/offers_screen.dart';
import '../features/offers/screens/refer_screen.dart';
import '../features/orders/screens/order_detail_screen.dart';
import '../features/notifications/screens/notifications_screen.dart';
import '../features/orders/screens/orders_screen.dart';
import '../features/repairs/screens/repair_detail_screen.dart';
import '../features/repairs/screens/repair_form_screen.dart';
import '../features/repairs/screens/repairs_screen.dart';
import '../features/wishlist/screens/wishlist_screen.dart';
import 'deep_links.dart';
import 'links.dart';
import 'supabase.dart';
import 'widgets/widgets.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Signed-out users hitting these go to /sign-in and come back after. Tab roots
/// (/cart, /repairs, /account) stay open and show a SignInPrompt instead.
const _authOnly = ['/checkout', '/orders', '/wishlist', '/admin', '/repairs/', '/account/', '/notifications'];

/// Only same-app paths, so `from` can't bounce the user to another host.
String? safeReturnPath(String? from) =>
    from != null && from.startsWith('/') && !from.startsWith('//') && !from.startsWith('/sign-in') ? from : null;

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresh = _StreamListenable(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  GoRoute sub(String path, Widget Function(GoRouterState s) build, {List<RouteBase> routes = const []}) =>
      GoRoute(path: path, parentNavigatorKey: rootNavigatorKey, builder: (_, s) => build(s), routes: routes);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: refresh,
    redirect: (context, state) {
      // a shared link (https://<LINK_HOST>/open?…, shyammobiles://open?…): keep the friend's code, show the page
      if (openLink(state.uri) case final link?) {
        if (link.code case final code?) unawaited(ref.read(pendingReferralProvider.notifier).remember(code));
        return link.to;
      }
      final signedIn = auth.currentSession != null;
      final path = state.matchedLocation;
      if (!signedIn && _authOnly.any(path.startsWith)) {
        return '/sign-in?from=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (signedIn && path.startsWith('/sign-in')) return safeReturnPath(state.uri.queryParameters['from']) ?? '/';
      // Server enforces admin rights; this just keeps non-staff out of screens they can't use.
      if (path.startsWith('/admin') && ref.read(isAdminProvider).value == false) return '/';
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/search',
              builder: (_, s) => SearchScreen(
                key: ValueKey(s.uri.query),
                query: s.uri.queryParameters['q'],
                category: s.uri.queryParameters['category'],
                brand: s.uri.queryParameters['brand'],
                sort: s.uri.queryParameters['sort'],
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/repairs', builder: (_, _) => const RepairsScreen(), routes: [
              sub('new', (_) => const RepairFormScreen()),
              sub(':id', (s) => RepairDetailScreen(bookingId: s.pathParameters['id']!)),
            ]),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/cart', builder: (_, _) => const CartScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/account', builder: (_, _) => const AccountScreen(), routes: [
              sub('profile', (_) => const ProfileScreen()),
              sub('refer', (_) => const ReferScreen()),
              sub('addresses', (_) => const AddressesScreen(), routes: [
                sub('new', (_) => const AddressFormScreen()),
                sub(':id', (s) => AddressFormScreen(addressId: s.pathParameters['id'])),
              ]),
            ]),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin', builder: (_, _) => const AdminDashboardScreen(), routes: [
              sub('products', (_) => const AdminProductsScreen(), routes: [
                sub('new', (_) => const AdminProductEditScreen()),
                sub(':id', (s) => AdminProductEditScreen(productId: s.pathParameters['id'])),
              ]),
              sub('orders', (s) => AdminOrdersScreen(status: s.uri.queryParameters['status']), routes: [
                sub(':id', (s) => AdminOrderScreen(orderId: s.pathParameters['id']!)),
              ]),
              sub('repairs', (_) => const AdminRepairsScreen(), routes: [
                sub(':id', (s) => AdminRepairScreen(bookingId: s.pathParameters['id']!)),
              ]),
              sub('catalogue', (_) => const AdminCatalogueScreen()),
              sub('offers', (_) => const AdminOffersScreen(), routes: [
                sub('new', (s) => AdminOfferEditScreen(copyOf: s.uri.queryParameters['copy'])),
                sub(':id', (s) => AdminOfferEditScreen(promotionId: s.pathParameters['id'])),
              ]),
              sub('groups', (_) => const AdminGroupsScreen(), routes: [
                sub('new', (_) => const AdminGroupEditScreen()),
                sub(':id', (s) => AdminGroupEditScreen(groupId: s.pathParameters['id'])),
              ]),
              sub('banners', (_) => const AdminBannersScreen(), routes: [
                sub('new', (_) => const AdminBannerEditScreen()),
                sub(':id', (s) => AdminBannerEditScreen(bannerId: s.pathParameters['id'])),
              ]),
              sub('settings', (_) => const AdminSettingsScreen()),
              sub('feedback', (s) => AdminFeedbackScreen(productId: s.uri.queryParameters['product']), routes: [
                sub(':id', (s) => AdminFeedbackDetailScreen(feedbackId: s.pathParameters['id']!)),
              ]),
            ]),
          ]),
        ],
      ),
      GoRoute(path: '/product/:slug', builder: (_, s) => ProductScreen(slug: s.pathParameters['slug']!)),
      GoRoute(path: '/offers', builder: (_, _) => const OffersScreen(), routes: [
        GoRoute(path: ':id', builder: (_, s) => OfferDetailScreen(offerId: s.pathParameters['id']!)),
      ]),
      GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen(), routes: [
        GoRoute(path: 'result/:orderId', builder: (_, s) => CheckoutResultScreen(orderId: s.pathParameters['orderId']!)),
      ]),
      GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen(), routes: [
        GoRoute(path: ':id', builder: (_, s) => OrderDetailScreen(orderId: s.pathParameters['id']!)),
      ]),
      GoRoute(path: '/wishlist', builder: (_, _) => const WishlistScreen()),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(
        path: '/sign-in',
        builder: (_, s) => SignInScreen(from: s.uri.queryParameters['from']),
        routes: [
          GoRoute(
            path: 'verify',
            builder: (_, s) => VerifyCodeScreen(
              phone: s.uri.queryParameters['phone'],
              email: s.uri.queryParameters['email'],
              from: s.uri.queryParameters['from'],
            ),
          ),
        ],
      ),
    ],
  );
});

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider).value ?? false;
    final cartCount = ref.watch(cartCountProvider);
    final destinations = [
      const NavigationDestination(
        icon: Icon(PhosphorIconsRegular.house),
        selectedIcon: Icon(PhosphorIconsFill.house),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(PhosphorIconsRegular.magnifyingGlass),
        selectedIcon: Icon(PhosphorIconsBold.magnifyingGlass),
        label: 'Search',
      ),
      const NavigationDestination(
        icon: Icon(PhosphorIconsRegular.wrench),
        selectedIcon: Icon(PhosphorIconsFill.wrench),
        label: 'Repairs',
      ),
      NavigationDestination(
        icon: Bump(
          trigger: cartCount, // pops when something lands in the cart
          child: Badge(
            isLabelVisible: cartCount > 0,
            label: Text('$cartCount'),
            child: const Icon(PhosphorIconsRegular.shoppingBag),
          ),
        ),
        selectedIcon: Bump(
          trigger: cartCount,
          child: Badge(
            isLabelVisible: cartCount > 0,
            label: Text('$cartCount'),
            child: const Icon(PhosphorIconsFill.shoppingBag),
          ),
        ),
        label: 'Cart',
        tooltip: cartCount > 0 ? 'Cart, $cartCount items' : 'Cart',
      ),
      const NavigationDestination(
        icon: Icon(PhosphorIconsRegular.user),
        selectedIcon: Icon(PhosphorIconsFill.user),
        label: 'Account',
      ),
      if (isAdmin)
        const NavigationDestination(
          icon: Icon(PhosphorIconsRegular.storefront),
          selectedIcon: Icon(PhosphorIconsFill.storefront),
          label: 'Admin',
        ),
    ];
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex < destinations.length ? shell.currentIndex : 0,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: destinations,
      ),
    );
  }
}
