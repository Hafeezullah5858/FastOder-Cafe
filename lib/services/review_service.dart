import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> submitReview({required String orderId, required String customerId, required String vendorId, required int rating, required String comment}) async {
    final existing = await _db.collection('reviews').where('orderId', isEqualTo: orderId).where('customerId', isEqualTo: customerId).limit(1).get();
    final payload = {
      'orderId': orderId,
      'customerId': customerId,
      'vendorId': vendorId,
      'rating': rating,
      'comment': comment.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (existing.docs.isEmpty) {
      await _db.collection('reviews').add(payload);
    } else {
      await existing.docs.first.reference.update(payload);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchVendorReviews(String vendorId) =>
      _db.collection('reviews').where('vendorId', isEqualTo: vendorId).snapshots();
}
