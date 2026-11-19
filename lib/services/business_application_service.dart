import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BusinessApplicationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  String _collection(String type) {
    if (type == 'vendor') return 'vendor_applications';
    if (type == 'rider') return 'rider_applications';
    throw ArgumentError.value(type, 'type', 'Unsupported application type');
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchMine(String type) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in first.');
    return _db.collection(_collection(type)).doc(uid).snapshots();
  }

  Future<void> submit({
    required String type,
    required String name,
    required String phone,
    required String area,
    required String details,
    String vehicleType = '',
    String vehicleRegistration = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in again.');
    final userRef = _db.collection('users').doc(uid);
    final applicationRef = _db.collection(_collection(type)).doc(uid);
    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final applicationSnap = await tx.get(applicationRef);
      final role = userSnap.data()?['role']?.toString() ?? 'customer';
      if (role != 'customer') {
        throw StateError('Only customer accounts can submit this application.');
      }
      if (applicationSnap.exists &&
          applicationSnap.data()?['status'] == 'pending') {
        throw StateError('Your application is already waiting for review.');
      }
      final existingCreatedAt = applicationSnap.data()?['createdAt'];

      tx.set(applicationRef, {
        'userId': uid,
        'applicantName': userSnap.data()?['name'] ?? '',
        'email': userSnap.data()?['email'] ?? '',
        'name': name.trim(),
        'phone': phone.trim(),
        'area': area.trim(),
        'details': details.trim(),
        if (type == 'rider') 'vehicleType': vehicleType.trim(),
        if (type == 'rider') 'vehicleRegistration': vehicleRegistration.trim(),
        'status': 'pending',
        'createdAt': existingCreatedAt ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> review({
    required String type,
    required String userId,
    required bool approve,
    String note = '',
  }) async {
    if (type != 'vendor' && type != 'rider') {
      throw ArgumentError.value(type, 'type', 'Unsupported application type');
    }
    await _functions.httpsCallable('reviewBusinessApplication').call({
      'type': type,
      'userId': userId,
      'decision': approve ? 'approve' : 'reject',
      'note': note.trim(),
    });
  }
}
