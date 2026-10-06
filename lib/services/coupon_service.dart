import 'package:cloud_firestore/cloud_firestore.dart';

class CouponResult {
  final String code;
  final double discount;
  final String message;
  const CouponResult({required this.code, required this.discount, required this.message});
}

class CouponService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<CouponResult> apply({required String code, required double subtotal, String? vendorId}) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return const CouponResult(code: '', discount: 0, message: 'Coupon code is empty');
    final snap = await _db.collection('coupons').doc(normalized).get();
    if (!snap.exists) return CouponResult(code: normalized, discount: 0, message: 'Invalid coupon');
    final d = snap.data()!;
    if (d['active'] != true) return CouponResult(code: normalized, discount: 0, message: 'Coupon is not active');
    final min = ((d['minSubtotal'] ?? 0) as num).toDouble();
    if (subtotal < min) return CouponResult(code: normalized, discount: 0, message: 'Minimum order is Rs. ${min.toStringAsFixed(0)}');
    final expires = d['expiresAt'];
    if (expires is Timestamp && expires.toDate().isBefore(DateTime.now())) return CouponResult(code: normalized, discount: 0, message: 'Coupon has expired');
    final allowedVendor = d['vendorId']?.toString();
    if (allowedVendor != null && allowedVendor.isNotEmpty && allowedVendor != vendorId) return CouponResult(code: normalized, discount: 0, message: 'Coupon is not valid for this seller');
    final type = d['type']?.toString() ?? 'fixed';
    final value = ((d['value'] ?? 0) as num).toDouble();
    final maxDiscount = ((d['maxDiscount'] ?? value) as num).toDouble();
    final discount = type == 'percent' ? (subtotal * value / 100).clamp(0, maxDiscount).toDouble() : value.clamp(0, subtotal).toDouble();
    return CouponResult(code: normalized, discount: discount, message: discount > 0 ? 'Coupon applied' : 'Coupon gives no discount');
  }
}
