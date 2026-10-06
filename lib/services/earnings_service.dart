import 'package:cloud_firestore/cloud_firestore.dart';

class EarningsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSellerEarnings(String sellerId) =>
      _db.collection('seller_earnings').where('sellerId', isEqualTo: sellerId).orderBy('createdAt', descending: true).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSellerPayouts(String sellerId) =>
      _db.collection('payouts').where('sellerId', isEqualTo: sellerId).orderBy('createdAt', descending: true).snapshots();
}
