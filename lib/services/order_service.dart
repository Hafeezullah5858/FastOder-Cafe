import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/order.dart';

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> createOrder({
    required String customerId,
    required String vendorId,
    required List<Map<String, dynamic>> items,
    required String address,
    required String paymentMethod,
    double? deliveryLat,
    double? deliveryLng,
    String couponCode = '',
  }) async {
    if (FirebaseAuth.instance.currentUser?.uid != customerId) {
      throw Exception('Customer session mismatch.');
    }
    final requestId = '${DateTime.now().microsecondsSinceEpoch}_${customerId.substring(0, 8)}';
    final callable = FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('createOrderSecure');
    final result = await callable.call({
      'requestId': requestId,
      'vendorId': vendorId,
      'items': items.map((item) => {
        'productId': item['productId'] ?? item['id'],
        'qty': item['qty'],
      }).toList(),
      'address': address,
      'paymentMethod': paymentMethod,
      'couponCode': couponCode,
      'deliveryLat': deliveryLat,
      'deliveryLng': deliveryLng,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Stream<List<OrderModel>> watchCustomerOrders(String customerId) =>
      _db.collection('orders').where('customerId', isEqualTo: customerId).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(OrderModel.fromDoc).toList());

  Stream<List<OrderModel>> watchVendorOrders(String vendorId) =>
      _db.collection('orders').where('vendorId', isEqualTo: vendorId).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(OrderModel.fromDoc).toList());

  Future<void> cancelOrder(String orderId, String reason) async {
    final ref = _db.collection('orders').doc(orderId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Order not found');
    final data = snap.data()!;
    if (data['customerId'] != FirebaseAuth.instance.currentUser?.uid) throw Exception('Not your order');
    if (data['status'] != 'placed') throw Exception('Order cancellation is only available before vendor acceptance.');
    final paymentMethod = data['paymentMethod'] ?? 'cash_on_delivery';
    await ref.update({
      'status': 'cancelled',
      'cancellationReason': reason.trim(),
      'refundStatus': paymentMethod == 'cash_on_delivery' ? 'not_applicable' : 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateStatus(String orderId, String status) async {
    final ref = _db.collection('orders').doc(orderId);
    await ref.update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> assignRider(String orderId, String riderId) async {
    final ref = _db.collection('orders').doc(orderId);
    await ref.update({'riderId': riderId, 'status': 'picked_up', 'updatedAt': FieldValue.serverTimestamp()});
  }
}
