import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeChefService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMyApplication() => _db
      .collection('home_chef_applications')
      .doc(FirebaseAuth.instance.currentUser!.uid)
      .snapshots();

  Future<void> submit({required String businessName, required String description, required String phone}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in again.');
    final user = await _db.collection('users').doc(uid).get();
    if ((user.data()?['role'] ?? 'customer') != 'customer') {
      throw StateError('Only customer accounts can submit a new Home Chef application.');
    }
    await _db.collection('home_chef_applications').doc(uid).set({
      'userId': uid,
      'businessName': businessName.trim(),
      'description': description.trim(),
      'phone': phone.trim(),
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> review({required String userId, required bool approve, String note = ''}) async {
    await _functions.httpsCallable('reviewHomeChefApplication').call({
      'userId': userId,
      'decision': approve ? 'approve' : 'reject',
      'note': note.trim(),
    });
  }
}
