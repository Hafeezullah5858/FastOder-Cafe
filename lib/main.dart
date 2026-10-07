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
    providerAndroid: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    providerApple: kDebugMode ? AppleProvider.debug : AppleProvider.appAttestWithDeviceCheckFallback,
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
          return snap.data == null ? const LoginPage() : const HomePage();
        },
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool loading = false, obscure = true;
  Future<void> login() async {
    if (email.text.trim().isEmpty || pass.text.isEmpty) return _msg('Email اور password درج کریں');
    setState(() => loading = true);
    try { await AuthService().signIn(email.text, pass.text); }
    on FirebaseAuthException catch (e) { _msg(e.message ?? 'Login failed'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  void _msg(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
          ClipRRect(borderRadius: BorderRadius.circular(28), child: Image.asset('assets/fastoder_cafe_logo.png', width: 290, height: 250, fit: BoxFit.cover)),
          const SizedBox(height: 8),
          const Text('Good Food • Fast Delivery', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), const SizedBox(height: 28),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: pass, obscureText: obscure, decoration: InputDecoration(labelText: 'Password', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.visibility), onPressed: () => setState(() => obscure = !obscure)))),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: loading ? null : login, child: loading ? const CircularProgressIndicator() : const Text('Login'))),
          TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SignUpPage())), child: const Text('Create new account')),
          TextButton(onPressed: () async { if (email.text.trim().isEmpty) return _msg('پہلے email درج کریں'); try { await AuthService().sendPasswordReset(email.text); _msg('Password reset email بھیج دی گئی'); } catch (_) { _msg('Reset email نہیں بھیجی جا سکی'); } }, child: const Text('Forgot password?')),
        ])))),
      );
}

class SignUpPage extends StatefulWidget { const SignUpPage({super.key}); @override State<SignUpPage> createState() => _SignUpPageState(); }
class _SignUpPageState extends State<SignUpPage> {
  final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController(); bool loading = false;
  Future<void> signup() async {
    if (name.text.trim().isEmpty || email.text.trim().isEmpty || pass.text.length < 6) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name, valid email اور کم از کم 6 characters password دیں'))); return; }
    setState(() => loading = true);
    try { await AuthService().signUp(name: name.text, email: email.text, password: pass.text); if (mounted) Navigator.pop(context); }
    on FirebaseAuthException catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Signup failed'))); }
    finally { if (mounted) setState(() => loading = false); }
  }
  @override Widget build(BuildContext c) => Scaffold(appBar: AppBar(title: const Text('Create account')), body: ListView(padding: const EdgeInsets.all(24), children: [
    TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())), const SizedBox(height: 12),
    TextField(controller: email, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())), const SizedBox(height: 12),
    TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())), const SizedBox(height: 18),
    FilledButton(onPressed: loading ? null : signup, child: Text(loading ? 'Creating...' : 'Sign Up')),
  ]));
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState() => _HomePageState(); }
class _HomePageState extends State<HomePage> {
  int tab = 0; final cart = <Map<String, dynamic>>[]; bool cartLoading = true;
  @override void initState() { super.initState(); _loadCart(); }
  Future<void> _loadCart() async { final saved = await CartService().load(); if (!mounted) return; setState(() { cart..clear()..addAll(saved); cartLoading = false; }); }
  Future<void> _saveCart() => CartService().save(cart);
  void add(Map<String, dynamic> product) { setState(() { final i = cart.indexWhere((x) => x['productId'] == product['id']); if (i >= 0) cart[i]['qty'] = (cart[i]['qty'] as int) + 1; else cart.add({...product, 'qty': 1}); }); _saveCart(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${product['name']} cart میں add ہو گیا'))); }
  void _cartChanged() { setState(() {}); _saveCart(); }
  @override Widget build(BuildContext c) { final pages = [HomeTab(onAdd: add), const OrdersTab(), const ProfileTab()]; return Scaffold(
    appBar: AppBar(title: const Text('FastOder Cafe', style: TextStyle(fontWeight: FontWeight.bold)), actions: [
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: NotificationService().watch(FirebaseAuth.instance.currentUser!.uid), builder: (context, snap) {
        final unread = (snap.data?.docs ?? []).where((d) => d.data()['read'] != true).length;
        return IconButton(icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)), onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const NotificationsSheet()));
      }),
      IconButton(icon: Badge(isLabelVisible: cart.isNotEmpty, label: Text('${cart.fold<int>(0, (s, x) => s + (x['qty'] as int))}'), child: const Icon(Icons.shopping_cart_outlined)), onPressed: cartLoading ? null : () async { await showModalBottomSheet(context: c, isScrollControlled: true, builder: (_) => CartSheet(items: cart, onChanged: _cartChanged)); if (mounted) setState(() {}); })
    ]),
    body: pages[tab], bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'), NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'), NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile')]),
  ); }
}

class HomeTab extends StatefulWidget {
  final void Function(Map<String, dynamic>) onAdd;
  const HomeTab({super.key, required this.onAdd});
  @override State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  String selected = 'All';
  @override Widget build(BuildContext c) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('products').where('active', isEqualTo: true).snapshots(),
    builder: (c, snap) {
      final docs = snap.data?.docs ?? [];
      final filtered = selected == 'Home Made' ? docs.where((d) => d.data()['vendorType'] == 'home_chef').toList() : docs;
      return ListView(padding: const EdgeInsets.all(16), children: [
        TextField(decoration: InputDecoration(hintText: 'Search food or stores...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)))),
        const SizedBox(height: 18), const Text('Categories', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), Wrap(spacing: 8, children: ['All','Home Made','Pizza','Burger','Biryani','BBQ','Dessert','Drinks'].map((x) => ChoiceChip(label: Text(x), selected: selected == x, onSelected: (_) => setState(() => selected = x))).toList()),
        const SizedBox(height: 18), Text(selected == 'Home Made' ? '🏠 Home Made Food' : 'Menu', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        if (snap.hasError) Text('Products error: ${snap.error}'),
        if (filtered.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('ابھی کوئی food item available نہیں۔'))),
        ...filtered.map((d) { final p = {'id': d.id, ...d.data()}; final isHome = p['vendorType'] == 'home_chef'; return Card(child: ListTile(leading: (p['imageUrl']?.toString().isNotEmpty ?? false) ? Image.network(p['imageUrl'], width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const CircleAvatar(child: Icon(Icons.restaurant))) : const CircleAvatar(child: Icon(Icons.restaurant)), title: Text('${p['name'] ?? ''}'), subtitle: Text('${isHome ? '🏠 Home Made' : 'Restaurant'} • Rs. ${p['price'] ?? 0}'), trailing: FilledButton(onPressed: () => widget.onAdd(p), child: const Text('Add')))); }),
      ]);
    },
  );
}

class CartSheet extends StatefulWidget { final List<Map<String, dynamic>> items; final VoidCallback onChanged; const CartSheet({super.key, required this.items, required this.onChanged}); @override State<CartSheet> createState() => _CartSheetState(); }
class _CartSheetState extends State<CartSheet> {
  bool placing = false; String address = ''; String phone = ''; String selectedAddressId = ''; String couponCode = ''; double discount = 0; String couponMessage = ''; double? deliveryLat; double? deliveryLng;
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
  double get subtotal => widget.items.fold(0, (s, e) => s + (e['price'] as num) * (e['qty'] as num));
  OrderQuote get quote => PricingService().quote(subtotal: subtotal, distanceKm: 0, discount: discount);
  double get total => quote.total;
  Future<void> checkout() async {
    if (widget.items.isEmpty) return; if (address.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery address منتخب کریں یا درج کریں'))); return; }
    final vendorIds = widget.items.map((e) => e['vendorId']?.toString() ?? '').toSet(); if (vendorIds.length != 1 || vendorIds.first.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ایک order میں ایک ہی vendor کی items ہونی چاہئیں'))); return; }
    setState(() => placing = true); try { final pos = await LocationService().currentLocation(); deliveryLat = pos?.latitude; deliveryLng = pos?.longitude; final result = await OrderService().createOrder(customerId: FirebaseAuth.instance.currentUser!.uid, vendorId: vendorIds.first, items: widget.items, couponCode: couponCode, address: address, paymentMethod: 'cash_on_delivery', deliveryLat: deliveryLat, deliveryLng: deliveryLng); final id = result['orderId'].toString(); if (mounted) { Navigator.pop(context); widget.items.clear(); widget.onChanged(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order placed: $id'))); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order failed: $e'))); } finally { if (mounted) setState(() => placing = false); }
  }
  Widget _line(String label, double value, {bool bold = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)), Text('Rs. ${value.toStringAsFixed(0)}', style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))]));

  @override Widget build(BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Text('Your Cart', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    ...widget.items.map((e) => ListTile(title: Text('${e['name']}'), subtitle: Text('Rs. ${e['price']}'), leading: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () { setState(() { if ((e['qty'] as int) > 1) e['qty'] = (e['qty'] as int) - 1; else widget.items.remove(e); }); widget.onChanged(); }), trailing: Text('x${e['qty']}'))),
    if (widget.items.isNotEmpty) ...[
      _line('Subtotal', quote.subtotal),
      _line('Delivery', quote.deliveryFee),
      if (quote.platformFee > 0) _line('Platform fee', quote.platformFee),
      const Divider(),
      _line('Total', quote.total, bold: true),
    ],
    if (widget.items.isNotEmpty) Row(children: [Expanded(child: TextField(controller: couponController, onChanged: (v) => couponCode = v.trim().toUpperCase(), textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Coupon code'))), const SizedBox(width: 8), FilledButton.tonal(onPressed: placing ? null : () async { final r = await CouponService().apply(code: couponCode, subtotal: subtotal, vendorId: widget.items.first['vendorId']?.toString()); if (mounted) setState(() { discount = r.discount; couponMessage = r.message; }); }, child: const Text('Apply'))]),
    if (couponMessage.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(couponMessage))),
    if (discount > 0) _line('Discount', -discount),
    if (widget.items.isNotEmpty) ...[
      Row(children: [Expanded(child: TextButton.icon(onPressed: () async { final picked = await showModalBottomSheet<SavedAddress>(context: c, isScrollControlled: true, builder: (_) => const SavedAddressesSheet()); if (picked != null && mounted) { setState(() { address=picked.address; phone=picked.phone; selectedAddressId=picked.id; deliveryLat=picked.lat; deliveryLng=picked.lng; }); addressController.text = address; phoneController.text = phone; } }, icon: const Icon(Icons.location_on_outlined), label: Text(selectedAddressId.isEmpty ? 'Choose saved address' : 'Change address'))), IconButton(tooltip: 'Pick location on map', onPressed: () async { final p = await Navigator.push<LatLng>(c, MaterialPageRoute(builder: (_) => AddressPickerPage(initialLat: deliveryLat, initialLng: deliveryLng))); if (p != null && mounted) setState(() { deliveryLat=p.latitude; deliveryLng=p.longitude; }); }, icon: const Icon(Icons.map_outlined))]),
      TextField(controller: addressController, onChanged: (v) => address=v, decoration: const InputDecoration(labelText: 'Delivery address', hintText: 'House, street, area, city', border: OutlineInputBorder())),
      const SizedBox(height: 6),
      TextField(controller: phoneController, onChanged: (v)=>phone=v, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Delivery phone', border: OutlineInputBorder())),
    ],
    if (widget.items.isNotEmpty) const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 10), child: Text('Payment: Cash on Delivery'))),
    if (widget.items.isNotEmpty) SizedBox(width: double.infinity, child: FilledButton(onPressed: placing ? null : checkout, child: Text(placing ? 'Placing order...' : 'Place Order'))),
  ]))));
}

class SavedAddressesSheet extends StatelessWidget {
  const SavedAddressesSheet({super.key});
  Future<void> _edit(BuildContext context, [SavedAddress? a]) async {
    final label=TextEditingController(text:a?.label??'Home'); final addr=TextEditingController(text:a?.address??''); final phone=TextEditingController(text:a?.phone??''); bool def=a?.isDefault??false;
    final save=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:Text(a==null?'Add address':'Edit address'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:label,decoration:const InputDecoration(labelText:'Label (Home, Work...)')),TextField(controller:addr,maxLines:2,decoration:const InputDecoration(labelText:'Full address')),TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone')),SwitchListTile(value:def,onChanged:(v)=>setD(()=>def=v),title:const Text('Make default'))])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('Save'))])));
    if(save==true && addr.text.trim().isNotEmpty){await AddressService().save(id:a?.id,label:label.text,address:addr.text,phone:phone.text,isDefault:def,lat:a?.lat,lng:a?.lng);}
  }
  @override Widget build(BuildContext context)=>SafeArea(child:DraggableScrollableSheet(expand:false,initialChildSize:.7,builder:(c,scroll)=>Column(children:[ListTile(title:const Text('Saved Addresses',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),trailing:IconButton(icon:const Icon(Icons.add),onPressed:()=>_edit(context))),Expanded(child:StreamBuilder<List<SavedAddress>>(stream:AddressService().watch(),builder:(c,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());if(s.data!.isEmpty)return const Center(child:Text('No saved addresses'));return ListView.builder(controller:scroll,itemCount:s.data!.length,itemBuilder:(c,i){final a=s.data![i];return ListTile(leading:Icon(a.isDefault?Icons.home:Icons.location_on_outlined),title:Text('${a.label}${a.isDefault?' • Default':''}'),subtitle:Text('${a.address}\n${a.phone}'),isThreeLine:true,onTap:()=>Navigator.pop(context,a),trailing:Wrap(children:[IconButton(icon:const Icon(Icons.edit_outlined),onPressed:()=>_edit(context,a)),IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>AddressService().remove(a.id))]));});}))])));
}

class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});
  @override Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return SafeArea(child: SizedBox(height: MediaQuery.of(context).size.height * .65, child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: NotificationService().watch(uid),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = [...snap.data!.docs]..sort((a,b) { final at=a.data()['createdAt']; final bt=b.data()['createdAt']; if (at is Timestamp && bt is Timestamp) return bt.compareTo(at); return 0; });
        if (docs.isEmpty) return const Center(child: Text('No notifications'));
        return ListView.builder(itemCount: docs.length, itemBuilder: (_, i) { final d=docs[i]; final x=d.data(); return ListTile(leading: Icon(x['read']==true ? Icons.notifications_none : Icons.notifications_active), title: Text(x['title']?.toString() ?? 'Notification'), subtitle: Text(x['body']?.toString() ?? ''), onTap: () => NotificationService().markRead(d.id)); });
      },
    )));
  }
}

class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});

  Future<void> _review(BuildContext context, OrderModel order) async {
    int rating = 5;
    final comment = TextEditingController();
    final save = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      title: const Text('Rate your order'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 4, children: List.generate(5, (i) => IconButton(icon: Icon(i < rating ? Icons.star : Icons.star_border), onPressed: () => setD(() => rating = i + 1)))),
        TextField(controller: comment, maxLines: 3, decoration: const InputDecoration(labelText: 'Review (optional)', border: OutlineInputBorder())),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Submit'))],
    )));
    if (save == true) {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await ReviewService().submitReview(orderId: order.id, customerId: uid, vendorId: order.vendorId, rating: rating, comment: comment.text);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review saved')));
    }
  }

  @override Widget build(BuildContext c) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<List<OrderModel>>(stream: OrderService().watchCustomerOrders(uid), builder: (c, s) {
      if (s.hasError) return Center(child: Text('Orders error: ${s.error}'));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      if (s.data!.isEmpty) return const Center(child: Text('ابھی کوئی order نہیں'));
      return ListView(padding: const EdgeInsets.all(16), children: s.data!.map((o) => Card(child: ListTile(
        leading: const Icon(Icons.delivery_dining),
        title: Text('Order #${o.id.substring(0, 6)}'),
        subtitle: Text('${o.status} • Rs. ${o.total.toStringAsFixed(0)}\n${o.address}'),
        isThreeLine: true,
        trailing: Wrap( children: [
          if (o.status == 'placed') IconButton(icon: const Icon(Icons.cancel_outlined), tooltip: 'Cancel order', onPressed: () async { final reason = await showDialog<String>(context: c, builder: (d) { final ctl = TextEditingController(); return AlertDialog(title: const Text('Cancel order?'), content: TextField(controller: ctl, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason (optional)')), actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Keep')), FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim().isEmpty ? 'Customer cancellation' : ctl.text.trim()), child: const Text('Cancel order'))]); }); if (reason != null) { try { await OrderService().cancelOrder(o.id, reason); if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Order cancelled'))); } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('$e'))); } } }),
          if (o.status == 'delivered') IconButton(icon: const Icon(Icons.star_outline), tooltip: 'Rate order', onPressed: () => _review(c, o)),
          if (o.riderId.isNotEmpty && o.status != 'delivered') IconButton(icon: const Icon(Icons.location_on), tooltip: 'Track rider', onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => OrderTrackingPage(order: o)))),
        ]),
      ))).toList());
    });
  }
}

class ProfileTab extends StatelessWidget { const ProfileTab({super.key}); @override Widget build(BuildContext c) { final u = FirebaseAuth.instance.currentUser; return ListView(padding: const EdgeInsets.all(18), children: [const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)), const SizedBox(height: 10), Center(child: Text(u?.displayName ?? 'FastOder Cafe User', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), Center(child: Text(u?.email ?? '')), const SizedBox(height: 20), Card(child: ListTile(leading: const Icon(Icons.home_work_outlined), title: const Text('Sell Home Made Food'), subtitle: const Text('Apply as a Home Chef and sell food from your kitchen'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const HomeChefApplicationPage())))), Card(child: ListTile(leading: const Icon(Icons.business_center), title: const Text('Business Panel'), subtitle: const Text('Vendor • Home Chef • Rider • Admin'), onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const RoleHubPage())))), Card(child: ListTile(leading: const Icon(Icons.logout), title: const Text('Logout'), onTap: () => AuthService().signOut()))]); } }

class HomeChefApplicationPage extends StatefulWidget {
  const HomeChefApplicationPage({super.key});
  @override State<HomeChefApplicationPage> createState() => _HomeChefApplicationPageState();
}

class _HomeChefApplicationPageState extends State<HomeChefApplicationPage> {
  final kitchen = TextEditingController();
  final phone = TextEditingController();
  final area = TextEditingController();
  final bio = TextEditingController();
  bool loading = false;

  Future<void> submit() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (kitchen.text.trim().isEmpty || phone.text.trim().isEmpty || area.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kitchen name, phone اور area درج کریں')));
      return;
    }
    setState(() => loading = true);
    try {
      await FirebaseFirestore.instance.collection('home_chef_applications').doc(uid).set({
        'userId': uid, 'kitchenName': kitchen.text.trim(), 'phone': phone.text.trim(),
        'area': area.text.trim(), 'bio': bio.text.trim(), 'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application submit ہو گئی۔ Admin approval کے بعد آپ food sell کر سکیں گے۔')));
    } finally { if (mounted) setState(() => loading = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Home Chef Application')), body: ListView(padding: const EdgeInsets.all(20), children: [
    const Text('🏠 Home Made Food Seller', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), const Text('گھر سے بنے کھانے فروخت کرنے کے لیے اپنی basic details دیں۔ Admin approval کے بعد آپ menu upload کر سکیں گے۔'), const SizedBox(height: 20),
    TextField(controller: kitchen, decoration: const InputDecoration(labelText: 'Kitchen / Home Chef Name', border: OutlineInputBorder())), const SizedBox(height: 12),
    TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())), const SizedBox(height: 12),
    TextField(controller: area, decoration: const InputDecoration(labelText: 'Delivery / Pickup Area', border: OutlineInputBorder())), const SizedBox(height: 12),
    TextField(controller: bio, maxLines: 4, decoration: const InputDecoration(labelText: 'About your food (optional)', border: OutlineInputBorder())), const SizedBox(height: 18),
    FilledButton.icon(onPressed: loading ? null : submit, icon: const Icon(Icons.send), label: Text(loading ? 'Submitting...' : 'Submit for Approval')),
  ]));
}

class RoleHubPage extends StatelessWidget { const RoleHubPage({super.key}); @override Widget build(BuildContext context) => FutureBuilder<String>(future: AuthService().getRole(), builder: (context, snap) { if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator())); switch (snap.data) { case 'admin': return const AdminPanel(); case 'vendor': return const VendorPanel(); case 'home_chef': return const VendorPanel(); case 'rider': return const RiderPanel(); default: return const Scaffold(body: Center(child: Text('Business role assigned نہیں ہے۔'))); } }); }

class VendorPanel extends StatefulWidget { const VendorPanel({super.key}); @override State<VendorPanel> createState() => _VendorPanelState(); }
class _VendorPanelState extends State<VendorPanel> {
  final db = FirebaseFirestore.instance; final orderService = OrderService();
  String get vendorId => FirebaseAuth.instance.currentUser!.uid;
  Future<void> _productDialog([DocumentSnapshot<Map<String, dynamic>>? doc]) async {
    final data = doc?.data() ?? {}; final imageUrl = TextEditingController(text: data['imageUrl']?.toString() ?? ''); final name = TextEditingController(text: data['name']?.toString() ?? ''); final price = TextEditingController(text: data['price']?.toString() ?? ''); bool active = data['active'] ?? true;
    final save = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, setD) => AlertDialog(title: Text(doc == null ? 'Add Food Item' : 'Edit Food Item'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Food name')), TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (Rs.)')), TextField(controller: imageUrl, decoration: const InputDecoration(labelText: 'Image URL (optional)')), const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () async { final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80); if (x == null) return; final ref = FirebaseStorage.instance.ref('home_food/${vendorId}/${DateTime.now().millisecondsSinceEpoch}.jpg'); await ref.putData(await x.readAsBytes(), SettableMetadata(contentType: 'image/jpeg')); final url = await ref.getDownloadURL(); setD(() { imageUrl.text = url; }); }, icon: const Icon(Icons.photo_library), label: const Text('Upload food photo'))), SwitchListTile(value: active, onChanged: (v) => setD(() => active = v), title: const Text('Available'))]), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))])));
    if (save != true || name.text.trim().isEmpty || double.tryParse(price.text) == null) return;
    final payload = {'vendorId': vendorId, 'vendorType': (await AuthService().getRole()) == 'home_chef' ? 'home_chef' : 'restaurant', 'name': name.text.trim(), 'price': double.parse(price.text), 'active': active, 'imageUrl': imageUrl.text.trim(), 'updatedAt': FieldValue.serverTimestamp()};
    if (doc == null) await db.collection('products').add({...payload, 'createdAt': FieldValue.serverTimestamp()}); else await db.collection('products').doc(doc.id).update(payload);
  }
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Seller Panel'),
            bottom: const TabBar(
              tabs: [Tab(text: 'Orders'), Tab(text: 'Menu')],
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
                    children: snap.data!.map((o) => Card(
                      child: ListTile(
                        title: Text('Order #${o.id.substring(0, 6)}'),
                        subtitle: Text(
                          '${o.status} • Rs. ${o.total.toStringAsFixed(0)}\n${o.address}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) =>
                              orderService.updateStatus(o.id, v),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'accepted',
                              child: Text('Accept'),
                            ),
                            PopupMenuItem(
                              value: 'preparing',
                              child: Text('Preparing'),
                            ),
                            PopupMenuItem(
                              value: 'ready',
                              child: Text('Ready'),
                            ),
                          ],
                        ),
                      ),
                    )).toList(),
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
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: snap.data!.docs.map((d) {
                        final p = d.data();
                        return Card(
                          child: ListTile(
                            title: Text(p['name'] ?? ''),
                            subtitle: Text('Rs. ${p['price'] ?? 0}'),
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
                                  onPressed: () => db
                                      .collection('products')
                                      .doc(d.id)
                                      .delete(),
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
            ],
          ),
        ),
      );
}

class RiderPanel extends StatefulWidget { const RiderPanel({super.key}); @override State<RiderPanel> createState() => _RiderPanelState(); }
class _RiderPanelState extends State<RiderPanel> {
  bool tracking = false; final location = LocationService(); StreamSubscription? _locationSub;
  Future<void> toggleTracking() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (tracking) {
      await _locationSub?.cancel();
      _locationSub = null;
      if (mounted) setState(() => tracking = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Live location stopped')));
      return;
    }
    final pos = await location.currentLocation();
    if (pos == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission/service available نہیں ہے'))); return; }
    await location.updateRiderLocation(uid, pos.latitude, pos.longitude);
    _locationSub = location.positionStream().listen((p) => location.updateRiderLocation(uid, p.latitude, p.longitude));
    if (mounted) setState(() => tracking = true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Live location tracking started')));
  }
  @override
  void dispose() { _locationSub?.cancel(); super.dispose(); }
  Future<void> accept(String orderId) async { final uid = FirebaseAuth.instance.currentUser!.uid; await OrderService().assignRider(orderId, uid); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Rider Panel'), actions: [IconButton(onPressed: toggleTracking, icon: Icon(tracking ? Icons.location_on : Icons.location_off))]), body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('orders').where('status', whereIn: ['ready', 'picked_up', 'on_the_way']).snapshots(), builder: (context, snap) { if (snap.hasError) return Center(child: Text('Error: ${snap.error}')); if (!snap.hasData) return const Center(child: CircularProgressIndicator()); final uid = FirebaseAuth.instance.currentUser!.uid; return ListView(padding: const EdgeInsets.all(16), children: snap.data!.docs.map((d) { final o = OrderModel.fromDoc(d); final mine = o.riderId == uid; return Card(child: ListTile(title: Text('Order #${o.id.substring(0, 6)}'), subtitle: Text('${o.status}\n${o.address}'), isThreeLine: true, trailing: mine ? PopupMenuButton<String>(onSelected: (v) => OrderService().updateStatus(o.id, v), itemBuilder: (_) => const [PopupMenuItem(value: 'on_the_way', child: Text('On the way')), PopupMenuItem(value: 'delivered', child: Text('Delivered'))]) : (o.status == 'ready' ? FilledButton(onPressed: () => accept(o.id), child: const Text('Accept')) : const SizedBox.shrink()))); }).toList()); }));
}

class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Admin Dashboard'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Orders'),
                Tab(text: 'Users'),
                Tab(text: 'Home Chefs'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('orders')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: snap.data!.docs.map((d) {
                      final o = OrderModel.fromDoc(d);
                      return Card(
                        child: ListTile(
                          title: Text(
                            '#${o.id.substring(0, 6)} • Rs. ${o.total.toStringAsFixed(0)}',
                          ),
                          subtitle: Text(
                            '${o.status}\n'
                            'Customer: ${o.customerId}\n'
                            'Vendor: ${o.vendorId}\n'
                            'Rider: ${o.riderId.isEmpty ? 'Unassigned' : o.riderId}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: snap.data!.docs.map((d) {
                      final u = d.data();
                      return Card(
                        child: ListTile(
                          title: Text(u['name'] ?? u['email'] ?? d.id),
                          subtitle: Text(
                            '${u['email'] ?? ''}\n'
                            'Role: ${u['role'] ?? 'customer'}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('home_chef_applications')
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: snap.data!.docs.map((d) {
                      final a = d.data();
                      return Card(
                        child: ListTile(
                          title: Text(a['kitchenName'] ?? 'Home Chef'),
                          subtitle: Text(
                            '${a['area'] ?? ''}\n'
                            '${a['phone'] ?? ''}\n'
                            '${a['bio'] ?? ''}',
                          ),
                          isThreeLine: true,
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Approve',
                                icon: const Icon(Icons.check_circle),
                                onPressed: () async {
                                  final uid = d.id;
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .update({
                                    'role': 'home_chef',
                                    'sellerApproved': true,
                                    'sellerType': 'home_chef',
                                  });
                                  await d.reference.update({
                                    'status': 'approved',
                                    'approvedAt':
                                        FieldValue.serverTimestamp(),
                                    'approvedBy': FirebaseAuth
                                        .instance.currentUser!.uid,
                                  });
                                },
                              ),
                              IconButton(
                                tooltip: 'Reject',
                                icon: const Icon(Icons.cancel),
                                onPressed: () => d.reference.update({
                                  'status': 'rejected',
                                  'updatedAt': FieldValue.serverTimestamp(),
                                }),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      );
}
