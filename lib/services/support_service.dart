import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SupportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyTickets() => _db
      .collection('support_tickets')
      .where('customerId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .orderBy('createdAt', descending: true)
      .snapshots();

  Future<String> createTicket({
    required String category,
    required String message,
    String orderId = '',
  }) async {
    final result = await _functions.httpsCallable('createSupportTicket').call({
      'category': category,
      'message': message.trim(),
      'orderId': orderId.trim(),
    });
    return (result.data as Map)['ticketId'].toString();
  }

  Future<void> reviewTicket({
    required String ticketId,
    required String status,
    required String response,
  }) async {
    await _functions.httpsCallable('reviewSupportTicket').call({
      'ticketId': ticketId,
      'status': status,
      'response': response.trim(),
    });
  }
}
