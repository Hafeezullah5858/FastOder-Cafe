import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class PayoutService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRequests(String sellerId) =>
      _db.collection('payout_requests')
          .where('sellerId', isEqualTo: sellerId)
          .orderBy('createdAt', descending: true)
          .snapshots();

  Future<String> request({
    required double amount,
    required String accountTitle,
    required String accountNumber,
    required String bankName,
    required String iban,
  }) async {
    final result = await _functions.httpsCallable('requestSellerPayout').call({
      'amount': amount,
      'accountTitle': accountTitle.trim(),
      'accountNumber': accountNumber.trim(),
      'bankName': bankName.trim(),
      'iban': iban.trim(),
    });
    return (result.data as Map)['requestId'].toString();
  }

  Future<void> review({
    required String requestId,
    required bool paid,
    String reference = '',
    String note = '',
  }) async {
    await _functions.httpsCallable('reviewSellerPayout').call({
      'requestId': requestId,
      'decision': paid ? 'paid' : 'reject',
      'reference': reference.trim(),
      'note': note.trim(),
    });
  }
}
