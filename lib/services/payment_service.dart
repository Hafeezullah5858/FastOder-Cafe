import 'package:cloud_firestore/cloud_firestore.dart';

/// Payment gateway abstraction. COD is active. Online gateways intentionally
/// remain disabled until merchant credentials + server-side verification are configured.
class PaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Payment records are created only by the trusted createOrderSecure
  /// Cloud Function. Client-side payment creation is intentionally disabled.
  Future<String> createPaymentRecord({
    required String orderId,
    required String customerId,
    required double amount,
    required String method,
  }) async {
    throw StateError(
      'Payment records are created by the trusted backend during checkout.',
    );
  }

  Future<void> requestRefund({required String orderId, required String customerId, required double amount, required String reason}) async {
    await _db.collection('refund_requests').doc(orderId).set({
      'orderId': orderId,
      'customerId': customerId,
      'amount': amount,
      'reason': reason,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
