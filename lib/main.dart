import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'services/auth_service.dart';
import 'services/order_service.dart';
import 'services/review_service.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/pricing_service.dart';
import 'services/coupon_service.dart';
import 'services/cart_service.dart';
import 'services/payment_service.dart';
import 'services/admin_service.dart';
import 'services/support_service.dart';
import 'services/payout_service.dart';
import 'services/home_chef_service.dart';
import 'services/business_application_service.dart';
import 'models/order.dart';
import 'screens/order_tracking_page.dart';
import 'services/address_service.dart';
import 'screens/address_picker_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  // Use debug providers during local development; production must use Play Integrity/App Attest.
  // This prevents a fresh development install from being blocked by App Check before
  // the Firebase project has been registered for the production package.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const FastOderCafeApp());
}

class FastOderCafeApp extends StatelessWidget {
  const FastOderCafeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FastOder Cafe',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepOrange),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: AuthService().authStateChanges,
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snap.data != null) {
        // Fire-and-forget: login must not be blocked by notification permission.
        NotificationService().initializePushNotifications();
      }
      return snap.data == null
          ? const LoginPage()
          : const AuthenticatedRoleGate();
    },
  );
}

class AuthenticatedRoleGate extends StatelessWidget {
  const AuthenticatedRoleGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: AuthService().getRole(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Account Access')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Account role load نہیں ہو سکا۔ Internet اور Firebase access چیک کریں، پھر دوبارہ کوشش کریں۔',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        switch (snap.data) {
          case 'admin':
            return const AdminPanel();
          case 'vendor':
            return const VendorPanel();
          case 'home_chef':
            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get(),
              builder: (context, userSnap) {
                if (userSnap.hasError) return Scaffold(
                  appBar: AppBar(title: const Text('Seller Access')),
                  body: Center(child: Text('Seller approval status could not be loaded: ${userSnap.error}')),
                );
                if (!userSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
                if (userSnap.data?.data()?['sellerApproved'] != true) return const PendingHomeChefPage();
                return const VendorPanel();
              },
            );
          case 'rider':
            return const RiderPanel();
          default:
            return const HomePage();
        }
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool loading = false, obscure = true;
  Future<void> login() async {
    if (email.text.trim().isEmpty || pass.text.isEmpty)
      return _msg('Email اور password درج کریں');
    setState(() => loading = true);
    try {
      await AuthService().signIn(email.text, pass.text);
    } on FirebaseAuthException catch (e) {
      _msg(e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _msg(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/fastoder_cafe_logo.png',
                  width: 290,
                  height: 250,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Good Food • Fast Delivery',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pass,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.visibility),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: loading ? null : login,
                  child: loading
                      ? const CircularProgressIndicator()
                      : const Text('Login'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute(builder: (_) => const SignUpPage()),
                ),
                child: const Text('Create new account'),
              ),
              TextButton(
                onPressed: () async {
                  if (email.text.trim().isEmpty)
                    return _msg('پہلے email درج کریں');
                  try {
                    await AuthService().sendPasswordReset(email.text);
                    _msg('Password reset email بھیج دی گئی');
                  } catch (_) {
                    _msg('Reset email نہیں بھیجی جا سکی');
                  }
                },
                child: const Text('Forgot password?'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final name = TextEditingController(),
      email = TextEditingController(),
      pass = TextEditingController();
  bool loading = false;
  Future<void> signup() async {
    if (name.text.trim().isEmpty ||
        email.text.trim().isEmpty ||
        pass.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Name, valid email اور کم از کم 6 characters password دیں',
          ),
        ),
      );
      return;
    }
    setState(() => loading = true);
    try {
      await AuthService().signUp(
        name: name.text,
        email: email.text,
        password: pass.text,
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Signup failed')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Create account')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: email,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pass,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: loading ? null : signup,
          child: Text(loading ? 'Creating...' : 'Sign Up'),
        ),
      ],
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  final cart = <Map<String, dynamic>>[];
  bool cartLoading = true;
  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    final saved = await CartService().load();
    if (!mounted) return;
    setState(() {
      cart
        ..clear()
        ..addAll(saved);
      cartLoading = false;
    });
  }

  Future<void> _saveCart() => CartService().save(cart);
  void add(Map<String, dynamic> product) {
    setState(() {
      final i = cart.indexWhere((x) => x['productId'] == product['id']);
      if (i >= 0)
        cart[i]['qty'] = (cart[i]['qty'] as int) + 1;
      else
        cart.add({...product, 'qty': 1});
    });
    _saveCart();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product['name']} cart میں add ہو گیا')),
    );
  }

  void _cartChanged() {
    setState(() {});
    _saveCart();
  }

  @override
  Widget build(BuildContext c) {
    final pages = [HomeTab(onAdd: add), const OrdersTab(), const ProfileTab()];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FastOder Cafe',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: NotificationService().watch(
              FirebaseAuth.instance.currentUser!.uid,
            ),
            builder: (context, snap) {
              final unread = (snap.data?.docs ?? [])
                  .where((d) => d.data()['read'] != true)
                  .length;
              return IconButton(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const NotificationsSheet(),
                ),
              );
            },
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: cart.isNotEmpty,
              label: Text(
                '${cart.fold<int>(0, (s, x) => s + (x['qty'] as int))}',
              ),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            onPressed: cartLoading
                ? null
                : () async {
                    await showModalBottomSheet(
                      context: c,
                      isScrollControlled: true,
                      builder: (_) =>
                          CartSheet(items: cart, onChanged: _cartChanged),
                    );
                    if (mounted) setState(() {});
                  },
          ),
        ],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  final void Function(Map<String, dynamic>) onAdd;
  const HomeTab({super.key, required this.onAdd});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String selected = 'All';
  String searchQuery = '';
  @override
  Widget build(
    BuildContext c,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('products')
        .where('active', isEqualTo: true)
        .snapshots(),
    builder: (c, snap) {
      final docs = (snap.data?.docs ?? []).where((d) {
        final stock = d.data()['stockQty'];
        return stock == null || (stock is num && stock != 0);
      }).toList();
      final byCategory = selected == 'All'
          ? docs
          : docs.where((d) {
              final data = d.data();
              if (selected == 'Home Made') {
                return data['foodCategory'] == 'home_made' ||
                    (data['foodCategory'] == null && data['vendorType'] == 'home_chef');
              }
              return (data['menuCategory']?.toString().toLowerCase() ?? '') == selected.toLowerCase();
            }).toList();
      final filtered = byCategory.where((d) {
        if (searchQuery.isEmpty) return true;
        final data = d.data();
        final name = data['name']?.toString().toLowerCase() ?? '';
        final category = data['menuCategory']?.toString().toLowerCase() ?? '';
        return name.contains(searchQuery) || category.contains(searchQuery);
      }).toList();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search food or category...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onChanged: (value) => setState(() => searchQuery = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 18),
          const Text(
            'Categories',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children:
                [
                      'All',
                      'Home Made',
                      'Pizza',
                      'Burger',
                      'Biryani',
                      'BBQ',
                      'Dessert',
                      'Drinks',
                    ]
                    .map(
                      (x) => ChoiceChip(
                        label: Text(x),
                        selected: selected == x,
                        onSelected: (_) => setState(() => selected = x),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 18),
          Text(
            selected == 'Home Made' ? '🏠 Home Made Food' : 'Menu',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (snap.hasError) Text('Products error: ${snap.error}'),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('ابھی کوئی food item available نہیں۔')),
            ),
          ...filtered.map((d) {
            final p = {'id': d.id, ...d.data()};
            final isHome =
                p['foodCategory'] == 'home_made' ||
                (p['foodCategory'] == null && p['vendorType'] == 'home_chef');
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('vendor_settings').doc(p['vendorId'].toString()).snapshots(),
              builder: (context, storeSnap) {
                final isOpen = storeSnap.data?.data()?['isOpen'] != false;
                return Card(
                  child: ListTile(
                    leading: (p['imageUrl']?.toString().isNotEmpty ?? false)
                        ? Image.network(
                            p['imageUrl'],
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const CircleAvatar(child: Icon(Icons.restaurant)),
                          )
                        : const CircleAvatar(child: Icon(Icons.restaurant)),
                    title: Text('${p['name'] ?? ''}'),
                    subtitle: Text(
                      '${isHome ? '🏠 Home Made' : 'Restaurant'} • Rs. ${p['price'] ?? 0} • ${isOpen ? 'Open' : 'Closed'}',
                    ),
                    trailing: FilledButton(
                      onPressed: isOpen ? () => widget.onAdd(p) : null,
                      child: const Text('Add'),
                    ),
                  ),
                );
              },
            );
          }),
        ],
      );
    },
  );
}

bool _paymentAccountEnabled(dynamic value) {
  if (value is! Map) return false;
  final account = Map<String, dynamic>.from(value);
  return account['enabled'] == true &&
      ((account['accountNumber']?.toString().trim().isNotEmpty ?? false) ||
       (account['iban']?.toString().trim().isNotEmpty ?? false));
}

String _paymentAccountSubtitle(dynamic value) {
  if (!_paymentAccountEnabled(value)) return 'Not configured by admin yet';
  final account = Map<String, dynamic>.from(value as Map);
  final title = account['accountTitle']?.toString().trim() ?? '';
  final number = account['accountNumber']?.toString().trim() ?? '';
  final iban = account['iban']?.toString().trim() ?? '';
  final destination = number.isNotEmpty ? number : iban;
  return title.isEmpty ? destination : '$title • $destination';
}

class CartSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final VoidCallback onChanged;
  const CartSheet({super.key, required this.items, required this.onChanged});
  @override
  State<CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<CartSheet> {
  bool placing = false;
  String address = '';
  String phone = '';
  String selectedAddressId = '';
  String couponCode = '';
  double discount = 0;
  String couponMessage = '';
  String selectedPaymentMethod = 'cash_on_delivery';
  double? deliveryLat;
  double? deliveryLng;
  late final TextEditingController addressController;
  late final TextEditingController phoneController;
  late final TextEditingController couponController;

  @override
  void initState() {
    super.initState();
    addressController = TextEditingController();
    phoneController = TextEditingController();
    couponController = TextEditingController();
  }

  @override
  void dispose() {
    addressController.dispose();
    phoneController.dispose();
    couponController.dispose();
    super.dispose();
  }

  double get subtotal => widget.items.fold(
    0,
    (s, e) => s + (e['price'] as num) * (e['qty'] as num),
  );
  OrderQuote get quote => PricingService().quote(
    subtotal: subtotal,
    distanceKm: 0,
    discount: discount,
  );
  double get total => quote.total;
  Future<void> checkout() async {
    if (widget.items.isEmpty) return;
    if (address.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery address منتخب کریں یا درج کریں'),
        ),
      );
      return;
    }
    final vendorIds = widget.items
        .map((e) => e['vendorId']?.toString() ?? '')
        .toSet();
    if (vendorIds.length != 1 || vendorIds.first.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ایک order میں ایک ہی vendor کی items ہونی چاہئیں'),
        ),
      );
      return;
    }
    setState(() => placing = true);
    try {
      final pos = await LocationService().currentLocation();
      deliveryLat = pos?.latitude;
      deliveryLng = pos?.longitude;
      final result = await OrderService().createOrder(
        customerId: FirebaseAuth.instance.currentUser!.uid,
        vendorId: vendorIds.first,
        items: widget.items,
        couponCode: couponCode,
        address: address,
        paymentMethod: selectedPaymentMethod,
        deliveryLat: deliveryLat,
        deliveryLng: deliveryLng,
      );
      final id = result['orderId'].toString();
      if (mounted) {
        Navigator.pop(context);
        widget.items.clear();
        widget.onChanged();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Order placed: $id')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Order failed: $e')));
    } finally {
      if (mounted) setState(() => placing = false);
    }
  }

  Widget _line(String label, double value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          'Rs. ${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext c) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your Cart',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            ...widget.items.map(
              (e) => ListTile(
                title: Text('${e['name']}'),
                subtitle: Text('Rs. ${e['price']}'),
                leading: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    setState(() {
                      if ((e['qty'] as int) > 1)
                        e['qty'] = (e['qty'] as int) - 1;
                      else
                        widget.items.remove(e);
                    });
                    widget.onChanged();
                  },
                ),
                trailing: Text('x${e['qty']}'),
              ),
            ),
            if (widget.items.isNotEmpty) ...[
              _line('Subtotal', quote.subtotal),
              _line('Delivery', quote.deliveryFee),
              if (quote.platformFee > 0)
                _line('Platform fee', quote.platformFee),
              const Divider(),
              _line('Total', quote.total, bold: true),
            ],
            if (widget.items.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: couponController,
                      onChanged: (v) => couponCode = v.trim().toUpperCase(),
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Coupon code',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: placing
                        ? null
                        : () async {
                            final r = await CouponService().apply(
                              code: couponCode,
                              subtotal: subtotal,
                              vendorId: widget.items.first['vendorId']
                                  ?.toString(),
                            );
                            if (mounted)
                              setState(() {
                                discount = r.discount;
                                couponMessage = r.message;
                              });
                          },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            if (couponMessage.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(couponMessage),
                ),
              ),
            if (discount > 0) _line('Discount', -discount),
            if (widget.items.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await showModalBottomSheet<SavedAddress>(
                          context: c,
                          isScrollControlled: true,
                          builder: (_) => const SavedAddressesSheet(),
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            address = picked.address;
                            phone = picked.phone;
                            selectedAddressId = picked.id;
                            deliveryLat = picked.lat;
                            deliveryLng = picked.lng;
                          });
                          addressController.text = address;
                          phoneController.text = phone;
                        }
                      },
                      icon: const Icon(Icons.location_on_outlined),
                      label: Text(
                        selectedAddressId.isEmpty
                            ? 'Choose saved address'
                            : 'Change address',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Pick location on map',
                    onPressed: () async {
                      final p = await Navigator.push<LatLng>(
                        c,
                        MaterialPageRoute(
                          builder: (_) => AddressPickerPage(
                            initialLat: deliveryLat,
                            initialLng: deliveryLng,
                          ),
                        ),
                      );
                      if (p != null && mounted)
                        setState(() {
                          deliveryLat = p.latitude;
                          deliveryLng = p.longitude;
                        });
                    },
                    icon: const Icon(Icons.map_outlined),
                  ),
                ],
              ),
              TextField(
                controller: addressController,
                onChanged: (v) => address = v,
                decoration: const InputDecoration(
                  labelText: 'Delivery address',
                  hintText: 'House, street, area, city',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: phoneController,
                onChanged: (v) => phone = v,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Delivery phone',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (widget.items.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: 14, bottom: 6),
                  child: Text(
                    'Payment method',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: PaymentService().watchPaymentMethods(),
                builder: (context, settingsSnap) {
                  final settings = settingsSnap.data?.data() ?? {};
                  final options = <Map<String, dynamic>>[
                    {
                      'id': 'cash_on_delivery',
                      'title': 'Cash on Delivery',
                      'subtitle': 'Pay cash when your order arrives',
                      'enabled': true,
                    },
                    {
                      'id': 'jazzcash_manual',
                      'title': 'JazzCash',
                      'subtitle': _paymentAccountSubtitle(settings['jazzcash']),
                      'enabled': _paymentAccountEnabled(settings['jazzcash']),
                    },
                    {
                      'id': 'easypaisa_manual',
                      'title': 'Easypaisa',
                      'subtitle': _paymentAccountSubtitle(settings['easypaisa']),
                      'enabled': _paymentAccountEnabled(settings['easypaisa']),
                    },
                    {
                      'id': 'bank_transfer_manual',
                      'title': 'Bank Transfer',
                      'subtitle': _paymentAccountSubtitle(settings['bank_transfer']),
                      'enabled': _paymentAccountEnabled(settings['bank_transfer']),
                    },
                  ];
                  return Column(
                    children: [
                      if (settingsSnap.hasError)
                        const Text('Payment settings could not be loaded. COD is still available.'),
                      ...options.map((option) => RadioListTile<String>(
                        value: option['id'] as String,
                        groupValue: selectedPaymentMethod,
                        onChanged: option['enabled'] == true
                            ? (value) {
                                if (value != null) setState(() => selectedPaymentMethod = value);
                              }
                            : null,
                        title: Text(option['title'] as String),
                        subtitle: Text(option['subtitle'] as String),
                        dense: true,
                      )),
                      if (selectedPaymentMethod != 'cash_on_delivery')
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Text(
                            'You will transfer the amount yourself and submit the transaction ID and receipt. The order will wait for admin verification.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            if (widget.items.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: placing ? null : checkout,
                  child: Text(placing ? 'Placing order...' : 'Place Order'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class SavedAddressesSheet extends StatelessWidget {
  const SavedAddressesSheet({super.key});
  Future<void> _edit(BuildContext context, [SavedAddress? a]) async {
    final label = TextEditingController(text: a?.label ?? 'Home');
    final addr = TextEditingController(text: a?.address ?? '');
    final phone = TextEditingController(text: a?.phone ?? '');
    bool def = a?.isDefault ?? false;
    final save = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text(a == null ? 'Add address' : 'Edit address'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(
                    labelText: 'Label (Home, Work...)',
                  ),
                ),
                TextField(
                  controller: addr,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Full address'),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                SwitchListTile(
                  value: def,
                  onChanged: (v) => setD(() => def = v),
                  title: const Text('Make default'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true && addr.text.trim().isNotEmpty) {
      await AddressService().save(
        id: a?.id,
        label: label.text,
        address: addr.text,
        phone: phone.text,
        isDefault: def,
        lat: a?.lat,
        lng: a?.lng,
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      builder: (c, scroll) => Column(
        children: [
          ListTile(
            title: const Text(
              'Saved Addresses',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _edit(context),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<SavedAddress>>(
              stream: AddressService().watch(),
              builder: (c, s) {
                if (!s.hasData)
                  return const Center(child: CircularProgressIndicator());
                if (s.data!.isEmpty)
                  return const Center(child: Text('No saved addresses'));
                return ListView.builder(
                  controller: scroll,
                  itemCount: s.data!.length,
                  itemBuilder: (c, i) {
                    final a = s.data![i];
                    return ListTile(
                      leading: Icon(
                        a.isDefault ? Icons.home : Icons.location_on_outlined,
                      ),
                      title: Text(
                        '${a.label}${a.isDefault ? ' • Default' : ''}',
                      ),
                      subtitle: Text('${a.address}\n${a.phone}'),
                      isThreeLine: true,
                      onTap: () => Navigator.pop(context, a),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, a),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => AddressService().remove(a.id),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .65,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: NotificationService().watch(uid),
          builder: (context, snap) {
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());
            final docs = [...snap.data!.docs]
              ..sort((a, b) {
                final at = a.data()['createdAt'];
                final bt = b.data()['createdAt'];
                if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
                return 0;
              });
            if (docs.isEmpty)
              return const Center(child: Text('No notifications'));
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (_, i) {
                final d = docs[i];
                final x = d.data();
                return ListTile(
                  leading: Icon(
                    x['read'] == true
                        ? Icons.notifications_none
                        : Icons.notifications_active,
                  ),
                  title: Text(x['title']?.toString() ?? 'Notification'),
                  subtitle: Text(x['body']?.toString() ?? ''),
                  onTap: () => NotificationService().markRead(d.id),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});

  Future<void> _review(BuildContext context, OrderModel order) async {
    int rating = 5;
    final comment = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Rate your order'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 4,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    icon: Icon(i < rating ? Icons.star : Icons.star_border),
                    onPressed: () => setD(() => rating = i + 1),
                  ),
                ),
              ),
              TextField(
                controller: comment,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Review (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await ReviewService().submitReview(
        orderId: order.id,
        customerId: uid,
        vendorId: order.vendorId,
        rating: rating,
        comment: comment.text,
      );
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Review saved')));
    }
  }

  @override
  Widget build(BuildContext c) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<List<OrderModel>>(
      stream: OrderService().watchCustomerOrders(uid),
      builder: (c, s) {
        if (s.hasError) return Center(child: Text('Orders error: ${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty)
          return const Center(child: Text('ابھی کوئی order نہیں'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: s.data!
              .map(
                (o) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.delivery_dining),
                    title: Text('Order #${o.id.substring(0, 6)}'),
                    subtitle: Text(
                      '${o.status} • Rs. ${o.total.toStringAsFixed(0)}\nPayment: ${o.paymentStatus}\n${o.address}',
                    ),
                    isThreeLine: true,
                    trailing: Wrap(
                      children: [
                        if (o.paymentMethod != 'cash_on_delivery' &&
                            o.paymentStatus != 'paid' &&
                            o.paymentStatus != 'pending_verification' &&
                            o.status == 'placed')
                          IconButton(
                            icon: const Icon(Icons.receipt_long),
                            tooltip: 'Submit payment receipt',
                            onPressed: () => showDialog<bool>(
                              context: c,
                              builder: (_) => ManualPaymentDialog(order: o),
                            ),
                          ),
                        if (o.paymentStatus == 'pending_verification')
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('Payment under review'),
                          ),
                        if (o.status == 'placed')
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            tooltip: 'Cancel order',
                            onPressed: () async {
                              final reason = await showDialog<String>(
                                context: c,
                                builder: (d) {
                                  final ctl = TextEditingController();
                                  return AlertDialog(
                                    title: const Text('Cancel order?'),
                                    content: TextField(
                                      controller: ctl,
                                      maxLines: 2,
                                      decoration: const InputDecoration(
                                        labelText: 'Reason (optional)',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(d),
                                        child: const Text('Keep'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(
                                          d,
                                          ctl.text.trim().isEmpty
                                              ? 'Customer cancellation'
                                              : ctl.text.trim(),
                                        ),
                                        child: const Text('Cancel order'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (reason != null) {
                                try {
                                  await OrderService().cancelOrder(
                                    o.id,
                                    reason,
                                  );
                                  if (c.mounted)
                                    ScaffoldMessenger.of(c).showSnackBar(
                                      const SnackBar(
                                        content: Text('Order cancelled'),
                                      ),
                                    );
                                } catch (e) {
                                  if (c.mounted)
                                    ScaffoldMessenger.of(c).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                }
                              }
                            },
                          ),
                        if (o.status == 'delivered')
                          IconButton(
                            icon: const Icon(Icons.star_outline),
                            tooltip: 'Rate order',
                            onPressed: () => _review(c, o),
                          ),
                        if (o.riderId.isNotEmpty && o.status == 'on_the_way')
                          IconButton(
                            icon: const Icon(Icons.password),
                            tooltip: 'Show delivery OTP',
                            onPressed: () => showDialog<void>(
                              context: c,
                              builder: (_) => DeliveryOtpDialog(orderId: o.id),
                            ),
                          ),
                        if (o.riderId.isNotEmpty && o.status != 'delivered')
                          IconButton(
                            icon: const Icon(Icons.location_on),
                            tooltip: 'Track rider',
                            onPressed: () => Navigator.push(
                              c,
                              MaterialPageRoute(
                                builder: (_) => OrderTrackingPage(order: o),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class DeliveryOtpDialog extends StatelessWidget {
  final String orderId;
  const DeliveryOtpDialog({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delivery confirmation code'),
    content: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('delivery_otps').doc(orderId).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text('OTP could not be loaded: ${snap.error}');
        if (!snap.hasData) return const CircularProgressIndicator();
        final code = snap.data?.data()?['code']?.toString() ?? '';
        if (code.isEmpty) return const Text('Delivery code is not available. Contact support.');
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Share this six-digit code with your rider only when your order has arrived.'),
          const SizedBox(height: 12),
          SelectableText(code, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 6)),
        ]);
      },
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}

class ManualPaymentDialog extends StatefulWidget {
  final OrderModel order;
  const ManualPaymentDialog({super.key, required this.order});

  @override
  State<ManualPaymentDialog> createState() => _ManualPaymentDialogState();
}

class _ManualPaymentDialogState extends State<ManualPaymentDialog> {
  final transactionController = TextEditingController();
  XFile? receipt;
  bool submitting = false;

  @override
  void dispose() {
    transactionController.dispose();
    super.dispose();
  }

  String get methodTitle => switch (widget.order.paymentMethod) {
    'jazzcash_manual' => 'JazzCash',
    'easypaisa_manual' => 'Easypaisa',
    'bank_transfer_manual' => 'Bank Transfer',
    _ => 'Manual Payment',
  };

  Future<void> chooseReceipt() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
      maxWidth: 1600,
    );
    if (picked != null && mounted) setState(() => receipt = picked);
  }

  Future<void> submit() async {
    if (widget.order.paymentAccountSnapshot == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment account details are missing. Contact support before transferring.')));
      return;
    }
    if (receipt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the payment receipt image.')),
      );
      return;
    }
    setState(() => submitting = true);
    try {
      await PaymentService().submitProof(
        orderId: widget.order.id,
        transactionRef: transactionController.text,
        proof: receipt!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt submission failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('$methodTitle payment'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Builder(
          builder: (context) {
            final account = widget.order.paymentAccountSnapshot ?? <String, dynamic>{};
            final accountNumber = account['accountNumber']?.toString() ?? '';
            final accountTitle = account['accountTitle']?.toString() ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (accountNumber.isEmpty && (account['iban']?.toString().isEmpty ?? true))
                  const Text('Payment account snapshot is missing. Please contact support before transferring.'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(accountTitle.isEmpty ? methodTitle : accountTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SelectableText(accountNumber.isEmpty ? 'Account number not configured' : accountNumber),
                        if ((account['bankName']?.toString().isNotEmpty ?? false))
                          Text('Bank: ${account['bankName']}'),
                        if ((account['iban']?.toString().isNotEmpty ?? false))
                          SelectableText('IBAN: ${account['iban']}'),
                        const SizedBox(height: 6),
                        Text('Amount: Rs. ${widget.order.total.toStringAsFixed(0)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: transactionController,
                  decoration: const InputDecoration(
                    labelText: 'Transaction ID / Reference',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: submitting ? null : chooseReceipt,
                  icon: const Icon(Icons.upload_file),
                  label: Text(receipt == null ? 'Choose receipt image' : receipt!.name),
                ),
                const Text(
                  'Only submit after sending the exact order amount. Admin will verify the transfer manually.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: submitting ? null : () => Navigator.pop(context), child: const Text('Later')),
      FilledButton(
        onPressed: submitting ? null : submit,
        child: Text(submitting ? 'Submitting...' : 'Submit receipt'),
      ),
    ],
  );
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});
  @override
  Widget build(BuildContext c) {
    final u = FirebaseAuth.instance.currentUser;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
        const SizedBox(height: 10),
        Center(
          child: Text(
            u?.displayName ?? 'FastOder Cafe User',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        Center(child: Text(u?.email ?? '')),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.business_center),
            title: const Text('Business Panel'),
            subtitle: const Text('Vendor • Home Chef • Rider • Admin'),
            onTap: () => Navigator.push(
              c,
              MaterialPageRoute(builder: (_) => const RoleHubPage()),
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('Become a Home Chef'),
            subtitle: const Text('Apply to sell homemade food'),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const HomeChefApplicationPage())),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Become a Restaurant Vendor'),
            subtitle: const Text('Apply to manage your restaurant menu and orders'),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const BusinessApplicationPage(type: 'vendor'))),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delivery_dining_outlined),
            title: const Text('Become a Rider'),
            subtitle: const Text('Apply to deliver customer orders'),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const BusinessApplicationPage(type: 'rider'))),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Support & Complaints'),
            subtitle: const Text('Create a support ticket and track replies'),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SupportPage())),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () => AuthService().signOut(),
          ),
        ),
      ],
    );
  }
}

class HomeChefApplicationPage extends StatefulWidget {
  const HomeChefApplicationPage({super.key});
  @override
  State<HomeChefApplicationPage> createState() => _HomeChefApplicationPageState();
}

class _HomeChefApplicationPageState extends State<HomeChefApplicationPage> {
  final businessName = TextEditingController();
  final phone = TextEditingController();
  final description = TextEditingController();
  bool sending = false;

  @override
  void dispose() { businessName.dispose(); phone.dispose(); description.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (businessName.text.trim().isEmpty || description.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your business name and a short description.')));
      return;
    }
    setState(() => sending = true);
    try {
      await HomeChefService().submit(businessName: businessName.text, phone: phone.text, description: description.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Home Chef application submitted.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Application failed: $e')));
    } finally { if (mounted) setState(() => sending = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Home Chef Application')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: HomeChefService().watchMyApplication(),
        builder: (context, snap) {
          final data = snap.data?.data();
          if (data == null) return const SizedBox.shrink();
          return Card(child: ListTile(
            title: Text('Application status: ${data['status'] ?? 'pending'}'),
            subtitle: Text(data['adminNote']?.toString() ?? 'Your application is under review.'),
          ));
        },
      ),
      TextField(controller: businessName, decoration: const InputDecoration(labelText: 'Business / kitchen name', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: description, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'What food do you prepare?', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      FilledButton(onPressed: sending ? null : submit, child: Text(sending ? 'Submitting...' : 'Submit application')),
    ]),
  );
}

class BusinessApplicationPage extends StatefulWidget {
  final String type;
  const BusinessApplicationPage({super.key, required this.type});
  @override
  State<BusinessApplicationPage> createState() => _BusinessApplicationPageState();
}

class _BusinessApplicationPageState extends State<BusinessApplicationPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final area = TextEditingController();
  final details = TextEditingController();
  final vehicleType = TextEditingController();
  final vehicleRegistration = TextEditingController();
  bool sending = false;

  bool get isRider => widget.type == 'rider';

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    area.dispose();
    details.dispose();
    vehicleType.dispose();
    vehicleRegistration.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (name.text.trim().isEmpty || phone.text.trim().length < 7 ||
        area.text.trim().isEmpty || details.text.trim().length < 10 ||
        (isRider && vehicleType.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please complete all required fields. Details must be at least 10 characters.'),
      ));
      return;
    }
    setState(() => sending = true);
    try {
      await BusinessApplicationService().submit(
        type: widget.type,
        name: name.text,
        phone: phone.text,
        area: area.text,
        details: details.text,
        vehicleType: vehicleType.text,
        vehicleRegistration: vehicleRegistration.text,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Application submitted. You will be notified after admin review.'),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Application failed: $e')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(isRider ? 'Rider Application' : 'Restaurant Vendor Application')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: BusinessApplicationService().watchMine(widget.type),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Application status error: ${snap.error}'));
        final application = snap.data?.data();
        final status = application?['status']?.toString() ?? '';
        final locked = status == 'pending' || status == 'approved';
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (application != null) Card(child: ListTile(
            leading: Icon(status == 'approved' ? Icons.verified : status == 'rejected' ? Icons.info_outline : Icons.hourglass_top),
            title: Text('Application status: ${status.isEmpty ? 'unknown' : status.toUpperCase()}'),
            subtitle: Text(status == 'rejected' || status == 'suspended'
                ? (application['adminNote']?.toString().isNotEmpty == true ? application['adminNote'].toString() : 'Your application was not approved.')
                : status == 'approved'
                    ? 'Your access has been approved.'
                    : 'Your application is being reviewed by the admin team.'),
          )),
          if (!locked) ...[
            TextField(controller: name, decoration: InputDecoration(labelText: isRider ? 'Full name' : 'Restaurant / business name', border: const OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact phone', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: area, decoration: InputDecoration(labelText: isRider ? 'City / delivery area' : 'Business address / area', border: const OutlineInputBorder())),
            if (isRider) ...[
              const SizedBox(height: 10),
              TextField(controller: vehicleType, decoration: const InputDecoration(labelText: 'Vehicle type (bike, car, etc.)', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: vehicleRegistration, decoration: const InputDecoration(labelText: 'Vehicle registration (optional)', border: OutlineInputBorder())),
            ],
            const SizedBox(height: 10),
            TextField(controller: details, minLines: 3, maxLines: 5, decoration: InputDecoration(labelText: isRider ? 'Delivery experience / availability' : 'Business details and food/service information', border: const OutlineInputBorder())),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: sending ? null : submit,
              icon: const Icon(Icons.send),
              label: Text(sending ? 'Submitting...' : 'Submit for admin approval'),
            ),
          ] else const Padding(
            padding: EdgeInsets.all(12),
            child: Text('You cannot submit another application while this application is pending or already approved.'),
          ),
        ]);
      },
    ),
  );
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final message = TextEditingController();
  final orderId = TextEditingController();
  String category = 'Order issue';
  bool sending = false;

  @override
  void dispose() { message.dispose(); orderId.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (message.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please describe the issue in at least 10 characters.')));
      return;
    }
    setState(() => sending = true);
    try {
      final id = await SupportService().createTicket(category: category, message: message.text, orderId: orderId.text);
      message.clear(); orderId.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Support ticket created: $id')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ticket could not be created: $e')));
    } finally { if (mounted) setState(() => sending = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Support & Complaints')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<String>(
        initialValue: category,
        decoration: const InputDecoration(labelText: 'Issue category', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: 'Order issue', child: Text('Order issue')),
          DropdownMenuItem(value: 'Payment issue', child: Text('Payment issue')),
          DropdownMenuItem(value: 'Delivery issue', child: Text('Delivery issue')),
          DropdownMenuItem(value: 'Account issue', child: Text('Account issue')),
          DropdownMenuItem(value: 'Other', child: Text('Other')),
        ],
        onChanged: (value) { if (value != null) setState(() => category = value); },
      ),
      const SizedBox(height: 10),
      TextField(controller: orderId, decoration: const InputDecoration(labelText: 'Order ID (optional)', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: message, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Describe your issue', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: sending ? null : submit, icon: const Icon(Icons.send), label: Text(sending ? 'Submitting...' : 'Submit ticket')),
      const Divider(height: 28),
      const Text('My support tickets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: SupportService().watchMyTickets(),
        builder: (context, snap) {
          if (snap.hasError) return Text('Tickets error: ${snap.error}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.docs.isEmpty) return const Text('No support tickets yet.');
          return Column(children: snap.data!.docs.map((doc) {
            final data = doc.data();
            final lines = <String>[data['message']?.toString() ?? ''];
            final response = data['adminResponse']?.toString() ?? '';
            if (response.isNotEmpty) lines.add('Admin: $response');
            return Card(child: ListTile(
              title: Text('${data['category'] ?? 'Support'} • ${data['status'] ?? 'open'}'),
              subtitle: Text(lines.join('\n')),
              isThreeLine: true,
            ));
          }).toList());
        },
      ),
    ]),
  );
}

class RoleHubPage extends StatelessWidget {
  const RoleHubPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: AuthService().getRole(),
    builder: (context, snap) {
      if (!snap.hasData)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      switch (snap.data) {
        case 'admin':
          return const AdminPanel();
        case 'vendor':
          return const VendorPanel();
        case 'home_chef':
          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get(),
            builder: (context, userSnap) {
              if (!userSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
              if (userSnap.data?.data()?['sellerApproved'] != true) return const PendingHomeChefPage();
              return const VendorPanel();
            },
          );
        case 'rider':
          return const RiderPanel();
        default:
          return const Scaffold(
            body: Center(child: Text('Business role assigned نہیں ہے۔')),
          );
      }
    },
  );
}

class PendingHomeChefPage extends StatelessWidget {
  const PendingHomeChefPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Home Chef Application')),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.hourglass_top, size: 54),
        const SizedBox(height: 12),
        const Text('Your Home Chef seller access is awaiting admin approval.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () => AuthService().signOut(), child: const Text('Logout')),
      ]),
    )),
  );
}

class VendorPanel extends StatefulWidget {
  const VendorPanel({super.key});
  @override
  State<VendorPanel> createState() => _VendorPanelState();
}

class _VendorPanelState extends State<VendorPanel> {
  final db = FirebaseFirestore.instance;
  final orderService = OrderService();
  String get vendorId => FirebaseAuth.instance.currentUser!.uid;
  Future<void> _productDialog([
    DocumentSnapshot<Map<String, dynamic>>? doc,
  ]) async {
    final data = doc?.data() ?? {};
    final imageUrl = TextEditingController(
      text: data['imageUrl']?.toString() ?? '',
    );
    final name = TextEditingController(text: data['name']?.toString() ?? '');
    final price = TextEditingController(text: data['price']?.toString() ?? '');
    final stock = TextEditingController(text: data['stockQty']?.toString() ?? '-1');
    String menuCategory = data['menuCategory']?.toString() ?? 'Other';
    bool active = data['active'] ?? true;
    String foodCategory =
        data['foodCategory']?.toString() ??
        (data['vendorType'] == 'home_chef' ? 'home_made' : 'restaurant');
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(doc == null ? 'Add Food Item' : 'Edit Food Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Food name'),
              ),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price (Rs.)'),
              ),
              TextField(
                controller: stock,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stock quantity (-1 = unlimited)'),
              ),
              TextField(
                controller: imageUrl,
                decoration: const InputDecoration(
                  labelText: 'Image URL (optional)',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: menuCategory,
                decoration: const InputDecoration(labelText: 'Menu category'),
                items: const [
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                  DropdownMenuItem(value: 'Pizza', child: Text('Pizza')),
                  DropdownMenuItem(value: 'Burger', child: Text('Burger')),
                  DropdownMenuItem(value: 'Biryani', child: Text('Biryani')),
                  DropdownMenuItem(value: 'BBQ', child: Text('BBQ')),
                  DropdownMenuItem(value: 'Dessert', child: Text('Dessert')),
                  DropdownMenuItem(value: 'Drinks', child: Text('Drinks')),
                ],
                onChanged: (value) { if (value != null) setD(() => menuCategory = value); },
              ),
              DropdownButtonFormField<String>(
                initialValue: foodCategory,
                decoration: const InputDecoration(labelText: 'Food category'),
                items: const [
                  DropdownMenuItem(
                    value: 'restaurant',
                    child: Text('Restaurant'),
                  ),
                  DropdownMenuItem(
                    value: 'home_made',
                    child: Text('Home Made'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setD(() => foodCategory = value);
                  }
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final x = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 80,
                    );
                    if (x == null) return;
                    final ref = FirebaseStorage.instance.ref(
                      'home_food/${vendorId}/${DateTime.now().millisecondsSinceEpoch}.jpg',
                    );
                    await ref.putData(
                      await x.readAsBytes(),
                      SettableMetadata(contentType: 'image/jpeg'),
                    );
                    final url = await ref.getDownloadURL();
                    setD(() {
                      imageUrl.text = url;
                    });
                  },
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Upload food photo'),
                ),
              ),
              SwitchListTile(
                value: active,
                onChanged: (v) => setD(() => active = v),
                title: const Text('Available'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save != true ||
        name.text.trim().isEmpty ||
        double.tryParse(price.text) == null ||
        int.tryParse(stock.text) == null ||
        int.parse(stock.text) < -1)
      return;
    final payload = {
      'vendorId': vendorId,
      'vendorType': (await AuthService().getRole()) == 'home_chef'
          ? 'home_chef'
          : 'restaurant',
      'foodCategory': foodCategory,
      'menuCategory': menuCategory,
      'name': name.text.trim(),
      'price': double.parse(price.text),
      'stockQty': int.parse(stock.text),
      'active': active,
      'imageUrl': imageUrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (doc == null)
      await db.collection('products').add({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    else
      await db.collection('products').doc(doc.id).update(payload);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Seller Panel'),
        actions: [
          IconButton(
            tooltip: 'Support',
            icon: const Icon(Icons.support_agent),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportPage())),
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Orders'),
            Tab(text: 'Menu'),
            Tab(text: 'Sales'),
            Tab(text: 'Store Settings'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          StreamBuilder<List<OrderModel>>(
            stream: orderService.watchVendorOrders(vendorId),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: snap.data!
                    .map(
                      (o) => Card(
                        child: ListTile(
                          title: Text('Order #${o.id.substring(0, 6)}'),
                          subtitle: Text(
                            '${o.status} • Rs. ${o.total.toStringAsFixed(0)}\nPayment: ${o.paymentStatus}\n${o.address}',
                          ),
                          isThreeLine: true,
                          trailing: o.paymentMethod != 'cash_on_delivery' && o.paymentStatus != 'paid'
                              ? const Text('Awaiting payment')
                              : PopupMenuButton<String>(
                                  onSelected: (v) => orderService.updateStatus(o.id, v),
                                  itemBuilder: (_) => [
                                    if (o.status == 'placed') const PopupMenuItem(value: 'accepted', child: Text('Accept')),
                                    if (o.status == 'accepted') const PopupMenuItem(value: 'preparing', child: Text('Preparing')),
                                    if (o.status == 'preparing') const PopupMenuItem(value: 'ready', child: Text('Ready')),
                                  ],
                                ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () => _productDialog(),
              child: const Icon(Icons.add),
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('products')
                  .where('vendorId', isEqualTo: vendorId)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: snap.data!.docs.map((d) {
                    final p = d.data();
                    return Card(
                      child: ListTile(
                        title: Text(p['name'] ?? ''),
                        subtitle: Text('Rs. ${p['price'] ?? 0} • Stock: ${((p['stockQty'] ?? -1) == -1) ? 'Unlimited' : p['stockQty']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: p['active'] ?? false,
                              onChanged: (v) => db
                                  .collection('products')
                                  .doc(d.id)
                                  .update({'active': v}),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _productDialog(d),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () =>
                                  db.collection('products').doc(d.id).delete(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          VendorSalesTab(vendorId: vendorId),
          VendorSettingsTab(vendorId: vendorId),
        ],
      ),
    ),
  );
}

class VendorSalesTab extends StatelessWidget {
  final String vendorId;
  const VendorSalesTab({super.key, required this.vendorId});

  Future<void> _request(BuildContext context, double available) async {
    final amount = TextEditingController(text: available.toStringAsFixed(0));
    final title = TextEditingController();
    final number = TextEditingController();
    final bank = TextEditingController();
    final iban = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request seller payout'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (Rs.)')),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Account title')),
          TextField(controller: bank, decoration: const InputDecoration(labelText: 'Bank / wallet name')),
          TextField(controller: number, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Account number (optional if IBAN entered)')),
          TextField(controller: iban, decoration: const InputDecoration(labelText: 'IBAN (optional)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit request')),
        ],
      ),
    );
    if (submit != true) return;
    final value = int.tryParse(amount.text);
    if (value == null || value <= 0 || title.text.trim().isEmpty || (number.text.trim().isEmpty && iban.text.trim().isEmpty)) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount and payout account details.')));
      return;
    }
    try {
      final id = await PayoutService().request(
        amount: value,
        accountTitle: title.text,
        accountNumber: number.text,
        bankName: bank.text,
        iban: iban.text,
      );
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payout request submitted: $id')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payout request failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('seller_earnings').where('sellerId', isEqualTo: vendorId).snapshots(),
    builder: (context, earningsSnap) {
      if (earningsSnap.hasError) return Center(child: Text('Sales error: ${earningsSnap.error}'));
      if (!earningsSnap.hasData) return const Center(child: CircularProgressIndicator());
      final earnings = earningsSnap.data!.docs;
      final totalEarned = earnings.fold<double>(0, (sum, doc) => sum + ((doc.data()['sellerPayout'] ?? 0) as num).toDouble());
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: PayoutService().watchRequests(vendorId),
        builder: (context, payoutSnap) {
          if (payoutSnap.hasError) return Center(child: Text('Payout history error: ${payoutSnap.error}'));
          if (!payoutSnap.hasData) return const Center(child: CircularProgressIndicator());
          final requests = payoutSnap.data!.docs;
          final reserved = requests.where((d) => ['pending', 'paid'].contains(d.data()['status'])).fold<double>(0, (sum, d) => sum + ((d.data()['amount'] ?? 0) as num).toDouble());
          final available = (totalEarned - reserved).clamp(0, double.infinity).toDouble();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(child: ListTile(title: const Text('Total seller earnings'), trailing: Text('Rs. ${totalEarned.toStringAsFixed(0)}'))),
            Card(child: ListTile(title: const Text('Available for payout'), trailing: Text('Rs. ${available.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)))),
            FilledButton.icon(onPressed: available > 0 ? () => _request(context, available) : null, icon: const Icon(Icons.account_balance_wallet), label: const Text('Request payout')),
            const SizedBox(height: 12),
            const Text('Completed orders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ...earnings.map((doc) {
              final data = doc.data();
              return Card(child: ListTile(
                title: Text('Order #${doc.id.substring(0, 6)}'),
                subtitle: Text('Commission: Rs. ${data['commission'] ?? 0}'),
                trailing: Text('Rs. ${data['sellerPayout'] ?? 0}'),
              ));
            }),
            const Divider(height: 28),
            const Text('Payout requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ...requests.map((doc) {
              final data = doc.data();
              return Card(child: ListTile(
                title: Text('Rs. ${data['amount'] ?? 0} • ${data['status'] ?? 'pending'}'),
                subtitle: Text('${data['bankName'] ?? ''} • ${data['accountTitle'] ?? ''} • ${data['accountNumber'] ?? data['iban'] ?? ''}'),
              ));
            }),
          ]);
        },
      );
    },
  );
}

class VendorSettingsTab extends StatefulWidget {
  final String vendorId;
  const VendorSettingsTab({super.key, required this.vendorId});
  @override
  State<VendorSettingsTab> createState() => _VendorSettingsTabState();
}

class _VendorSettingsTabState extends State<VendorSettingsTab> {
  bool isOpen = true;
  bool loading = true;
  bool saving = false;
  final opening = TextEditingController(text: '09:00');
  final closing = TextEditingController(text: '23:00');

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('vendor_settings').doc(widget.vendorId).get();
      final data = doc.data() ?? {};
      if (mounted) setState(() {
        isOpen = data['isOpen'] != false;
        opening.text = data['openingTime']?.toString() ?? '09:00';
        closing.text = data['closingTime']?.toString() ?? '23:00';
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Store settings load failed: $e')));
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _save() async {
    final timePattern = RegExp(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$');
    if (!timePattern.hasMatch(opening.text.trim()) || !timePattern.hasMatch(closing.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter time in HH:MM format.')));
      return;
    }
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('vendor_settings').doc(widget.vendorId).set({
        'vendorId': widget.vendorId,
        'isOpen': isOpen,
        'openingTime': opening.text.trim(),
        'closingTime': closing.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Store settings saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  void dispose() { opening.dispose(); closing.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      SwitchListTile(
        value: isOpen,
        onChanged: (value) => setState(() => isOpen = value),
        title: const Text('Accept new orders'),
        subtitle: Text(isOpen ? 'Your store is open to new orders.' : 'Your store is closed to new orders.'),
      ),
      TextField(controller: opening, decoration: const InputDecoration(labelText: 'Opening time (HH:MM)', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: closing, decoration: const InputDecoration(labelText: 'Closing time (HH:MM)', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      const Text('Opening and closing times are displayed as store information. Use the switch above to immediately pause or resume new orders.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.save), label: Text(saving ? 'Saving...' : 'Save store settings')),
    ]);
  }
}

class RiderPanel extends StatefulWidget {
  const RiderPanel({super.key});
  @override
  State<RiderPanel> createState() => _RiderPanelState();
}

class _RiderPanelState extends State<RiderPanel> {
  bool tracking = false;
  final location = LocationService();
  StreamSubscription? _locationSub;
  StreamSubscription? _assignedOrdersSub;
  String get riderId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _assignedOrdersSub = FirebaseFirestore.instance
        .collection('orders')
        .where('riderId', isEqualTo: riderId)
        .snapshots()
        .listen((_) => location.syncRiderLocationVisibility(riderId));
  }

  Future<void> toggleTracking() async {
    if (tracking) {
      await _locationSub?.cancel();
      _locationSub = null;
      if (mounted) setState(() => tracking = false);
      return;
    }
    final pos = await location.currentLocation();
    if (pos == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission/service available نہیں ہے')),
      );
      return;
    }
    await location.syncRiderLocationVisibility(riderId);
    await location.updateRiderLocation(riderId, pos.latitude, pos.longitude);
    _locationSub = location.positionStream().listen((p) {
      location.updateRiderLocation(riderId, p.latitude, p.longitude);
    });
    if (mounted) setState(() => tracking = true);
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _assignedOrdersSub?.cancel();
    super.dispose();
  }

  Future<void> accept(String orderId) async {
    try {
      await OrderService().assignRider(orderId, riderId);
      await location.syncRiderLocationVisibility(riderId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery assigned to you')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept order: $e')),
      );
    }
  }

  Widget _orderList({required bool mine, bool completed = false}) {
    final query = FirebaseFirestore.instance.collection('orders');
    final stream = mine
        ? completed
            ? query.where('riderId', isEqualTo: riderId)
                .where('status', isEqualTo: 'delivered')
                .snapshots()
            : query.where('riderId', isEqualTo: riderId)
                .where('status', whereIn: ['ready', 'picked_up', 'on_the_way'])
                .snapshots()
        : query.where('status', isEqualTo: 'ready').snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Orders error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs.where((d) {
          final data = d.data();
          final isManual = data['paymentMethod'] != 'cash_on_delivery';
          final paymentAllowed = !isManual || data['paymentStatus'] == 'paid';
          final availableToClaim = mine || (data['riderId'] == null || data['riderId'] == '');
          return paymentAllowed && availableToClaim;
        }).toList();
        if (docs.isEmpty) return Center(
          child: Text(completed ? 'No completed deliveries yet' : mine ? 'No active deliveries' : 'No available paid orders'),
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: docs.map((d) {
            final order = OrderModel.fromDoc(d);
            return Card(
              child: ListTile(
                title: Text('Order #${order.id.substring(0, 6)}'),
                subtitle: Text('${order.status} • Rs. ${order.total.toStringAsFixed(0)}\n${order.address}'),
                isThreeLine: true,
                trailing: mine
                    ? PopupMenuButton<String>(
                        onSelected: (status) async {
                          try {
                            if (status == 'delivered') {
                              final otpController = TextEditingController();
                              final otp = await showDialog<String>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Confirm delivery'),
                                  content: TextField(
                                    controller: otpController,
                                    keyboardType: TextInputType.number,
                                    maxLength: 6,
                                    decoration: const InputDecoration(labelText: 'Customer delivery OTP'),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                                    FilledButton(onPressed: () => Navigator.pop(dialogContext, otpController.text.trim()), child: const Text('Verify & complete')),
                                  ],
                                ),
                              );
                              if (otp == null) return;
                              await OrderService().completeDelivery(orderId: order.id, otp: otp);
                            } else {
                              await OrderService().updateStatus(order.id, status);
                            }
                            await location.syncRiderLocationVisibility(riderId);
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                          }
                        },
                        itemBuilder: (_) => [
                          if (order.status == 'ready') const PopupMenuItem(value: 'picked_up', child: Text('Mark picked up')),
                          if (order.status == 'picked_up') const PopupMenuItem(value: 'on_the_way', child: Text('On the way')),
                          if (order.status == 'on_the_way') const PopupMenuItem(value: 'delivered', child: Text('Delivered')),
                        ],
                      )
                    : FilledButton(
                        onPressed: () => accept(order.id),
                        child: const Text('Accept'),
                      ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Rider Dashboard'),
        actions: [
          IconButton(
            tooltip: tracking ? 'Stop location' : 'Start location',
            onPressed: toggleTracking,
            icon: Icon(tracking ? Icons.location_on : Icons.location_off),
          ),
          IconButton(
            tooltip: 'Support',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportPage())),
            icon: const Icon(Icons.support_agent),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => AuthService().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
        bottom: const TabBar(tabs: [Tab(text: 'Available'), Tab(text: 'Active'), Tab(text: 'Completed')]),
      ),
      body: TabBarView(children: [
        _orderList(mine: false),
        _orderList(mine: true),
        _orderList(mine: true, completed: true),
      ]),
    ),
  );
}

class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 14,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Orders'),
            Tab(text: 'Payments'),
            Tab(text: 'Refunds'),
            Tab(text: 'People'),
            Tab(text: 'Coupons'),
            Tab(text: 'Payment Setup'),
            Tab(text: 'Audit Log'),
            Tab(text: 'Support'),
            Tab(text: 'Payouts'),
            Tab(text: 'Home Chef'),
            Tab(text: 'Vendors'),
            Tab(text: 'Riders'),
            Tab(text: 'Delivery'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          AdminOverviewTab(),
          AdminOrdersTab(),
          AdminPaymentsTab(),
          AdminRefundsTab(),
          AdminPeopleTab(),
          AdminCouponsTab(),
          PaymentSettingsTab(),
          AdminAuditTab(),
          AdminSupportTab(),
          AdminPayoutsTab(),
          AdminHomeChefApplicationsTab(),
          AdminBusinessApplicationsTab(type: 'vendor'),
          AdminBusinessApplicationsTab(type: 'rider'),
          AdminDeliveryTab(),
        ],
      ),
    ),
  );
}

class AdminOverviewTab extends StatelessWidget {
  const AdminOverviewTab({super.key});

  Widget _metric(String title, String value, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon, size: 30),
      title: Text(title),
      subtitle: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('orders').snapshots(),
    builder: (context, ordersSnap) {
      if (ordersSnap.hasError) return Center(child: Text('Overview error: ${ordersSnap.error}'));
      if (!ordersSnap.hasData) return const Center(child: CircularProgressIndicator());
      final orders = ordersSnap.data!.docs.map((doc) => OrderModel.fromDoc(doc)).toList();
      final pending = orders.where((o) => ['placed', 'accepted', 'preparing', 'ready', 'picked_up', 'on_the_way'].contains(o.status)).length;
      final delivered = orders.where((o) => o.status == 'delivered').length;
      final deliveredValue = orders.where((o) => o.status == 'delivered').fold<double>(0, (sum, o) => sum + o.total);
      return ListView(padding: const EdgeInsets.all(16), children: [
        _metric('Total orders', '${orders.length}', Icons.receipt_long),
        _metric('Active orders', '$pending', Icons.pending_actions),
        _metric('Delivered orders', '$delivered', Icons.check_circle_outline),
        _metric('Delivered order value', 'Rs. ${deliveredValue.toStringAsFixed(0)}', Icons.payments_outlined),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('payments').where('status', isEqualTo: 'pending_verification').snapshots(),
          builder: (context, paymentsSnap) => _metric(
            'Payments awaiting review',
            '${paymentsSnap.data?.docs.length ?? 0}',
            Icons.fact_check_outlined,
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('vendor_applications').where('status', isEqualTo: 'pending').snapshots(),
          builder: (context, applicationsSnap) => _metric(
            'Vendor applications awaiting review',
            '${applicationsSnap.data?.docs.length ?? 0}',
            Icons.storefront_outlined,
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('rider_applications').where('status', isEqualTo: 'pending').snapshots(),
          builder: (context, applicationsSnap) => _metric(
            'Rider applications awaiting review',
            '${applicationsSnap.data?.docs.length ?? 0}',
            Icons.delivery_dining_outlined,
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, usersSnap) => _metric(
            'Registered people',
            '${usersSnap.data?.docs.length ?? 0}',
            Icons.people_outline,
          ),
        ),
      ]);
    },
  );
}

class AdminOrdersTab extends StatelessWidget {
  const AdminOrdersTab({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('orders').orderBy('createdAt', descending: true).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Orders error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs;
      final unpaid = docs.where((d) {
        final data = d.data();
        return data['paymentMethod'] != 'cash_on_delivery' && data['paymentStatus'] != 'paid';
      }).length;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: ListTile(
            title: const Text('All orders'),
            subtitle: Text('${docs.length} total • $unpaid manual payments awaiting completion/review'),
          )),
          ...docs.map((d) {
            final order = OrderModel.fromDoc(d);
            return Card(
              child: ListTile(
                title: Text('#${order.id.substring(0, 6)} • Rs. ${order.total.toStringAsFixed(0)}'),
                subtitle: Text(
                  '${order.status} • ${order.paymentMethod}\n'
                  'Payment: ${order.paymentStatus}\n'
                  'Customer: ${order.customerId}\nVendor: ${order.vendorId}\n'
                  'Rider: ${order.riderId.isEmpty ? 'Unassigned' : order.riderId}',
                ),
                isThreeLine: true,
                trailing: ['delivered', 'cancelled'].contains(order.status)
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'cancel') {
                            final reason = TextEditingController(text: 'Cancelled by administrator');
                            final value = await showDialog<String>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Cancel this order?'),
                                content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Back')),
                                  FilledButton(onPressed: () => Navigator.pop(dialogContext, reason.text.trim()), child: const Text('Confirm cancel')),
                                ],
                              ),
                            );
                            if (value == null) return;
                            try {
                              await AdminService().cancelOrder(orderId: order.id, reason: value);
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order cancelled.')));
                            } catch (e) {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cancellation failed: $e')));
                            }
                          }
                        },
                        itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancel order'))],
                      ),
              ),
            );
          }),
        ],
      );
    },
  );
}

class AdminPaymentsTab extends StatelessWidget {
  const AdminPaymentsTab({super.key});

  Future<void> _review(BuildContext context, String orderId, bool approve) async {
    final noteController = TextEditingController();
    if (!approve) {
      final note = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reject payment receipt?'),
          content: TextField(
            controller: noteController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason for customer'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, noteController.text.trim()), child: const Text('Reject')),
          ],
        ),
      );
      if (note == null) return;
      noteController.text = note;
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Approve payment?'),
          content: const Text('Only approve after checking the transaction in your JazzCash, Easypaisa or bank account.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Approve')),
          ],
        ),
      );
      if (confirm != true) return;
    }
    try {
      await PaymentService().review(orderId: orderId, approve: approve, note: noteController.text);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'Payment approved' : 'Payment rejected')),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('payments').where('status', isEqualTo: 'pending_verification').snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Payments error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return const Center(child: Text('No payment receipts awaiting verification.'));
      return ListView(
        padding: const EdgeInsets.all(16),
        children: snap.data!.docs.map((doc) {
          final payment = doc.data();
          final proofPath = payment['proofPath']?.toString() ?? '';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Order #${doc.id.substring(0, 6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Method: ${payment['method'] ?? ''} • Rs. ${payment['amount'] ?? 0}'),
                  Text('Customer: ${payment['customerId'] ?? ''}'),
                  Text('Transaction: ${payment['transactionRef'] ?? 'Not provided'}'),
                  if (proofPath.isNotEmpty)
                    FutureBuilder<String>(
                      future: FirebaseStorage.instance.ref(proofPath).getDownloadURL(),
                      builder: (context, imageSnap) {
                        if (!imageSnap.hasData) return const Padding(padding: EdgeInsets.all(12), child: Text('Loading receipt image...'));
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Image.network(imageSnap.data!, height: 190, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Text('Receipt image could not be opened.')),
                        );
                      },
                    ),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: () => _review(context, doc.id, false), child: const Text('Reject'))),
                      const SizedBox(width: 10),
                      Expanded(child: FilledButton(onPressed: () => _review(context, doc.id, true), child: const Text('Approve'))),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    },
  );
}

class AdminRefundsTab extends StatelessWidget {
  const AdminRefundsTab({super.key});

  Future<void> _review(BuildContext context, String orderId, bool complete) async {
    final noteController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(complete ? 'Confirm refund sent?' : 'Reject refund request?'),
        content: TextField(
          controller: noteController,
          maxLines: 2,
          decoration: InputDecoration(labelText: complete ? 'Payment/reference note (optional)' : 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, noteController.text.trim()), child: Text(complete ? 'Mark completed' : 'Reject')),
        ],
      ),
    );
    if (result == null) return;
    try {
      await PaymentService().reviewRefund(orderId: orderId, complete: complete, note: result);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(complete ? 'Refund marked completed' : 'Refund rejected')),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refund review failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('refund_requests')
        .where('status', whereIn: ['pending_manual_refund_review', 'pending']).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Refunds error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return const Center(child: Text('No refund requests awaiting review.'));
      return ListView(padding: const EdgeInsets.all(16), children: snap.data!.docs.map((doc) {
        final data = doc.data();
        return Card(child: ListTile(
          title: Text('Order #${doc.id.substring(0, 6)} • Rs. ${data['amount'] ?? 0}'),
          subtitle: Text('Customer: ${data['customerId'] ?? ''}\n${data['reason'] ?? 'Refund requested'}'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (value) => _review(context, doc.id, value == 'complete'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'complete', child: Text('Mark refunded')),
              PopupMenuItem(value: 'reject', child: Text('Reject')),
            ],
          ),
        ));
      }).toList());
    },
  );
}

class AdminPeopleTab extends StatelessWidget {
  const AdminPeopleTab({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('People error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      return ListView(
        padding: const EdgeInsets.all(16),
        children: snap.data!.docs.map((doc) {
          final user = doc.data();
          final role = user['role']?.toString() ?? 'customer';
          final approved = user['sellerApproved'] == true;
          final vendorApproved = user['vendorApproved'] != false;
          final riderApproved = user['riderApproved'] != false;
          final accessState = role == 'home_chef' ? (approved ? ' • Approved' : ' • Suspended')
              : role == 'vendor' ? (vendorApproved ? ' • Approved' : ' • Suspended')
              : role == 'rider' ? (riderApproved ? ' • Approved' : ' • Suspended') : '';
          return Card(child: ListTile(
            title: Text(user['name']?.toString() ?? user['email']?.toString() ?? doc.id),
            subtitle: Text('${user['email'] ?? ''}\nRole: $role$accessState'),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                try {
                  if (action.startsWith('role:')) {
                    await AdminService().setUserRole(userId: doc.id, role: action.substring(5));
                  } else if (action == 'approve_home_chef' || action == 'suspend_home_chef') {
                    await AdminService().reviewHomeChef(userId: doc.id, approved: action == 'approve_home_chef');
                  }
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User settings updated.')));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User update failed: $e')));
                }
              },
              itemBuilder: (_) => [
                if (role != 'customer' && role != 'home_chef') const PopupMenuItem(value: 'role:customer', child: Text('Return to Customer / Suspend business access')),
                if (role == 'home_chef' && !approved) const PopupMenuItem(value: 'approve_home_chef', child: Text('Approve Home Chef')),
                if (role == 'home_chef' && approved) const PopupMenuItem(value: 'suspend_home_chef', child: Text('Suspend Home Chef')),
              ],
            ),
          ));
        }).toList(),
      );
    },
  );
}

class AdminCouponsTab extends StatelessWidget {
  const AdminCouponsTab({super.key});

  Future<void> _edit(BuildContext context, [String? existingCode, Map<String, dynamic>? existing]) async {
    final code = TextEditingController(text: existingCode ?? '');
    final value = TextEditingController(text: existing?['value']?.toString() ?? '');
    final minimum = TextEditingController(text: existing?['minSubtotal']?.toString() ?? '0');
    final maximum = TextEditingController(text: existing?['maxDiscount']?.toString() ?? '');
    String type = existing?['type']?.toString() ?? 'fixed';
    bool active = existing?['active'] == true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(existingCode == null ? 'Create coupon' : 'Edit coupon'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, enabled: existingCode == null, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Coupon code')),
            DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Discount type'), items: const [DropdownMenuItem(value: 'fixed', child: Text('Fixed Rs.')), DropdownMenuItem(value: 'percent', child: Text('Percentage'))], onChanged: (v) { if (v != null) setDialog(() => type = v); }),
            TextField(controller: value, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Discount value')),
            TextField(controller: maximum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Maximum discount (optional)')),
            TextField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum order subtotal')),
            SwitchListTile(value: active, onChanged: (v) => setDialog(() => active = v), title: const Text('Active')),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))],
        ),
      ),
    );
    if (saved != true) return;
    final normalized = code.text.trim().toUpperCase();
    final discountValue = double.tryParse(value.text);
    if (normalized.isEmpty || discountValue == null || discountValue <= 0) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid coupon code and discount.')));
      return;
    }
    await FirebaseFirestore.instance.collection('coupons').doc(normalized).set({
      'code': normalized,
      'type': type,
      'value': discountValue,
      'maxDiscount': double.tryParse(maximum.text) ?? discountValue,
      'minSubtotal': double.tryParse(minimum.text) ?? 0,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      if (existingCode == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton(onPressed: () => _edit(context), child: const Icon(Icons.add)),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('coupons').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Coupons error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(padding: const EdgeInsets.all(16), children: snap.data!.docs.map((doc) {
          final data = doc.data();
          return Card(child: ListTile(
            title: Text(doc.id),
            subtitle: Text('${data['type'] ?? 'fixed'} • ${data['value'] ?? 0} • Min Rs. ${data['minSubtotal'] ?? 0}'),
            trailing: Switch(value: data['active'] == true, onChanged: (v) => doc.reference.update({'active': v, 'updatedAt': FieldValue.serverTimestamp()})),
            onTap: () => _edit(context, doc.id, data),
          ));
        }).toList());
      },
    ),
  );
}

class AdminBusinessApplicationsTab extends StatelessWidget {
  final String type;
  const AdminBusinessApplicationsTab({super.key, required this.type});

  String get collection => type == 'vendor' ? 'vendor_applications' : 'rider_applications';
  String get heading => type == 'vendor' ? 'Vendor applications' : 'Rider applications';

  Future<void> _review(BuildContext context, String userId, bool approve) async {
    final note = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve $type application?' : 'Reject $type application?'),
        content: TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Admin note (optional for approval, reason for rejection)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, note.text.trim()), child: Text(approve ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (result == null) return;
    try {
      await BusinessApplicationService().review(type: type, userId: userId, approve: approve, note: result);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$type application ${approve ? 'approved' : 'rejected'}.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Application review failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection(collection).where('status', isEqualTo: 'pending').snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('$heading error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return Center(child: Text('No pending $type applications.'));
      return ListView(padding: const EdgeInsets.all(16), children: snap.data!.docs.map((doc) {
        final data = doc.data();
        final lines = <String>[
          'Applicant: ${data['applicantName'] ?? data['name'] ?? ''}',
          'Email: ${data['email'] ?? ''}',
          'Phone: ${data['phone'] ?? ''}',
          'Area: ${data['area'] ?? ''}',
        ];
        if (type == 'rider') {
          lines.add('Vehicle: ${data['vehicleType'] ?? ''}');
          if ((data['vehicleRegistration'] ?? '').toString().isNotEmpty) lines.add('Registration: ${data['vehicleRegistration']}');
        }
        lines.add(data['details']?.toString() ?? '');
        return Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(data['name']?.toString() ?? heading, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(lines.join('\n')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _review(context, doc.id, false), child: const Text('Reject'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: () => _review(context, doc.id, true), child: const Text('Approve'))),
            ]),
          ]),
        ));
      }).toList());
    },
  );
}

class AdminDeliveryTab extends StatelessWidget {
  const AdminDeliveryTab({super.key});

  Future<void> _assign(BuildContext context, OrderModel order) async {
    try {
      final riders = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'rider').get();
      final eligible = riders.docs.where((doc) => doc.data()['riderApproved'] != false).toList();
      if (eligible.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No approved riders are available. Approve a rider application first.')));
        return;
      }
      String? selected = eligible.first.id;
      final riderId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Assign approved rider'),
          content: DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            items: eligible.map((doc) => DropdownMenuItem(
              value: doc.id,
              child: Text('${doc.data()['name'] ?? doc.data()['email'] ?? doc.id}'),
            )).toList(),
            onChanged: (value) => setDialog(() => selected = value),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: selected == null ? null : () => Navigator.pop(dialogContext, selected), child: const Text('Assign')),
          ],
        )),
      );
      if (riderId == null) return;
      await AdminService().assignRider(orderId: order.id, riderId: riderId);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rider securely assigned to this order.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rider assignment failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('orders').snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Delivery monitor error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final orders = snap.data!.docs.map(OrderModel.fromDoc).where((order) => const ['ready', 'picked_up', 'on_the_way'].contains(order.status)).toList();
      orders.sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      if (orders.isEmpty) return const Center(child: Text('No orders are waiting for or currently in delivery.'));
      return ListView(padding: const EdgeInsets.all(16), children: orders.map((order) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Order #${order.id.substring(0, 6)} • ${order.status.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Customer: ${order.customerId}\nVendor: ${order.vendorId}\nAmount: Rs. ${order.total.toStringAsFixed(0)}\nAddress: ${order.address}\nRider: ${order.riderId.isEmpty ? 'Unassigned' : order.riderId}'),
            if (order.riderId.isNotEmpty) StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('rider_locations').doc(order.riderId).snapshots(),
              builder: (context, locationSnap) {
                final locationData = locationSnap.data?.data();
                if (locationData == null) return const Text('Rider location: waiting for first GPS update');
                final lat = locationData['lat'];
                final lng = locationData['lng'];
                return Text('Rider GPS: ${lat ?? '—'}, ${lng ?? '—'}');
              },
            ),
            if (order.status == 'ready' && order.riderId.isEmpty) Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(onPressed: () => _assign(context, order), icon: const Icon(Icons.person_pin_circle_outlined), label: const Text('Assign rider')),
            ),
          ]),
        ),
      )).toList());
    },
  );
}

class AdminHomeChefApplicationsTab extends StatelessWidget {
  const AdminHomeChefApplicationsTab({super.key});

  Future<void> _review(BuildContext context, String userId, bool approve) async {
    final note = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve Home Chef?' : 'Reject Home Chef application?'),
        content: TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Admin note (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, note.text.trim()), child: Text(approve ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (result == null) return;
    try {
      await HomeChefService().review(userId: userId, approve: approve, note: result);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Home Chef approved' : 'Application rejected')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('home_chef_applications').where('status', isEqualTo: 'pending').snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Applications error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return const Center(child: Text('No pending Home Chef applications.'));
      return ListView(padding: const EdgeInsets.all(16), children: snap.data!.docs.map((doc) {
        final data = doc.data();
        return Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(data['businessName']?.toString() ?? 'Home Chef', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Applicant: ${doc.id}'),
            Text('Phone: ${data['phone'] ?? ''}'),
            Text(data['description']?.toString() ?? ''),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _review(context, doc.id, false), child: const Text('Reject'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: () => _review(context, doc.id, true), child: const Text('Approve'))),
            ]),
          ]),
        ));
      }).toList());
    },
  );
}

class AdminPayoutsTab extends StatelessWidget {
  const AdminPayoutsTab({super.key});

  Future<void> _review(BuildContext context, String requestId, bool paid) async {
    final reference = TextEditingController();
    final note = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(paid ? 'Confirm payout sent' : 'Reject payout request'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (paid) TextField(controller: reference, decoration: const InputDecoration(labelText: 'Bank / wallet transfer reference')),
          TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Admin note (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(paid ? 'Mark paid' : 'Reject')),
        ],
      ),
    );
    if (result != true) return;
    if (paid && reference.text.trim().isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transfer reference is required.')));
      return;
    }
    try {
      await PayoutService().review(requestId: requestId, paid: paid, reference: reference.text, note: note.text);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(paid ? 'Payout marked paid' : 'Payout rejected')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payout review failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('payout_requests').where('status', isEqualTo: 'pending').snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Payouts error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return const Center(child: Text('No pending seller payouts.'));
      return ListView(padding: const EdgeInsets.all(16), children: snap.data!.docs.map((doc) {
        final data = doc.data();
        return Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Rs. ${data['amount'] ?? 0} • ${data['sellerRole'] ?? 'seller'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Seller: ${data['sellerId'] ?? ''}'),
            Text('Account: ${data['accountTitle'] ?? ''}'),
            Text('Bank / Wallet: ${data['bankName'] ?? ''}'),
            SelectableText('Number: ${data['accountNumber'] ?? ''}'),
            if ((data['iban']?.toString().isNotEmpty ?? false)) SelectableText('IBAN: ${data['iban']}'),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _review(context, doc.id, false), child: const Text('Reject'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: () => _review(context, doc.id, true), child: const Text('Mark paid'))),
            ]),
          ]),
        ));
      }).toList());
    },
  );
}

class AdminSupportTab extends StatelessWidget {
  const AdminSupportTab({super.key});

  Future<void> _update(BuildContext context, String ticketId, String status, String existingResponse) async {
    final response = TextEditingController(text: existingResponse);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Update support ticket: $status'),
        content: TextField(controller: response, maxLines: 4, decoration: const InputDecoration(labelText: 'Reply to customer')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, response.text.trim()), child: const Text('Save reply')),
        ],
      ),
    );
    if (result == null) return;
    try {
      await SupportService().reviewTicket(ticketId: ticketId, status: status, response: result);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support ticket updated.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ticket update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('support_tickets').orderBy('createdAt', descending: true).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Support error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return const Center(child: Text('No support tickets.'));
      return ListView(padding: const EdgeInsets.all(16), children: snap.data!.docs.map((doc) {
        final data = doc.data();
        final status = data['status']?.toString() ?? 'open';
        final lines = <String>['Customer: ${data['customerId'] ?? ''}'];
        final orderId = data['orderId']?.toString() ?? '';
        if (orderId.isNotEmpty) lines.add('Order: $orderId');
        lines.add(data['message']?.toString() ?? '');
        final response = data['adminResponse']?.toString() ?? '';
        if (response.isNotEmpty) lines.add('Reply: $response');
        return Card(child: ListTile(
          title: Text('${data['category'] ?? 'Support'} • $status'),
          subtitle: Text(lines.join('\n')),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (next) => _update(context, doc.id, next, data['adminResponse']?.toString() ?? ''),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'in_progress', child: Text('In progress')),
              PopupMenuItem(value: 'resolved', child: Text('Resolved')),
              PopupMenuItem(value: 'closed', child: Text('Close ticket')),
            ],
          ),
        ));
      }).toList());
    },
  );
}

class AdminAuditTab extends StatelessWidget {
  const AdminAuditTab({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('admin_audit_logs').orderBy('createdAt', descending: true).limit(100).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return Center(child: Text('Audit log error: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      if (snap.data!.docs.isEmpty) return const Center(child: Text('No admin actions recorded yet.'));
      return ListView(padding: const EdgeInsets.all(16), children: snap.data!.docs.map((doc) {
        final data = doc.data();
        final stamp = data['createdAt'];
        final time = stamp is Timestamp ? stamp.toDate().toLocal().toString() : 'Time pending';
        final lines = <String>[
          'Target: ${data['targetType'] ?? ''} ${data['targetId'] ?? ''}',
          'By: ${data['actorId'] ?? ''}',
          time,
        ];
        final note = data['note']?.toString() ?? '';
        if (note.isNotEmpty) lines.add('Note: $note');
        return Card(child: ListTile(
          leading: const Icon(Icons.history),
          title: Text(data['action']?.toString() ?? 'Admin action'),
          subtitle: Text(lines.join('\n')),
          isThreeLine: true,
        ));
      }).toList());
    },
  );
}

class PaymentSettingsTab extends StatefulWidget {
  const PaymentSettingsTab({super.key});
  @override
  State<PaymentSettingsTab> createState() => _PaymentSettingsTabState();
}

class _PaymentSettingsTabState extends State<PaymentSettingsTab> {
  final jazzTitle = TextEditingController();
  final jazzNumber = TextEditingController();
  final easyTitle = TextEditingController();
  final easyNumber = TextEditingController();
  final bankName = TextEditingController();
  final bankTitle = TextEditingController();
  final bankNumber = TextEditingController();
  final bankIban = TextEditingController();
  bool loading = true;
  bool saving = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('app_settings').doc('payment_methods').get();
      final data = snap.data() ?? {};
      final jazz = data['jazzcash'] is Map ? Map<String, dynamic>.from(data['jazzcash']) : <String, dynamic>{};
      final easy = data['easypaisa'] is Map ? Map<String, dynamic>.from(data['easypaisa']) : <String, dynamic>{};
      final bank = data['bank_transfer'] is Map ? Map<String, dynamic>.from(data['bank_transfer']) : <String, dynamic>{};
      jazzTitle.text = jazz['accountTitle']?.toString() ?? '';
      jazzNumber.text = jazz['accountNumber']?.toString() ?? '';
      easyTitle.text = easy['accountTitle']?.toString() ?? '';
      easyNumber.text = easy['accountNumber']?.toString() ?? '';
      bankName.text = bank['bankName']?.toString() ?? '';
      bankTitle.text = bank['accountTitle']?.toString() ?? '';
      bankNumber.text = bank['accountNumber']?.toString() ?? '';
      bankIban.text = bank['iban']?.toString() ?? '';
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Settings load failed: $e')));
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await AdminService().savePaymentSettings({
        'jazzcash': {'enabled': jazzNumber.text.trim().isNotEmpty, 'accountTitle': jazzTitle.text.trim(), 'accountNumber': jazzNumber.text.trim()},
        'easypaisa': {'enabled': easyNumber.text.trim().isNotEmpty, 'accountTitle': easyTitle.text.trim(), 'accountNumber': easyNumber.text.trim()},
        'bank_transfer': {'enabled': bankNumber.text.trim().isNotEmpty || bankIban.text.trim().isNotEmpty, 'bankName': bankName.text.trim(), 'accountTitle': bankTitle.text.trim(), 'accountNumber': bankNumber.text.trim(), 'iban': bankIban.text.trim()},
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment account settings saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  Widget _field(TextEditingController controller, String label, {TextInputType type = TextInputType.text}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: controller, keyboardType: type, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
  );

  @override
  void dispose() {
    jazzTitle.dispose(); jazzNumber.dispose(); easyTitle.dispose(); easyNumber.dispose();
    bankName.dispose(); bankTitle.dispose(); bankNumber.dispose(); bankIban.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Customers will see only the account details you save here. No online gateway or automatic card charging is used.', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 12),
      const Text('JazzCash', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      _field(jazzTitle, 'Account title'), _field(jazzNumber, 'JazzCash mobile / account number', type: TextInputType.phone),
      const Divider(height: 28),
      const Text('Easypaisa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      _field(easyTitle, 'Account title'), _field(easyNumber, 'Easypaisa mobile / account number', type: TextInputType.phone),
      const Divider(height: 28),
      const Text('Bank Transfer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      _field(bankName, 'Bank name'), _field(bankTitle, 'Account title'), _field(bankNumber, 'Account number', type: TextInputType.number), _field(bankIban, 'IBAN (optional)'),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.save), label: Text(saving ? 'Saving...' : 'Save payment details')),
    ]);
  }
}
