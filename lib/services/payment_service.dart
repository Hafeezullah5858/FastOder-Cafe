import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class PaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchPaymentMethods() =>
      _db.collection('app_settings').doc('payment_methods').snapshots();

  Future<void> submitProof({
    required String orderId,
    required String transactionRef,
    required XFile proof,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in again.');
    final refText = transactionRef.trim();
    if (refText.length < 5 || refText.length > 80) {
      throw ArgumentError('Transaction ID must be 5 to 80 characters.');
    }

    final bytes = await proof.readAsBytes();
    if (bytes.isEmpty || bytes.length >= 5 * 1024 * 1024) {
      throw ArgumentError('Receipt image must be smaller than 5 MB.');
    }
    final extension = proof.name.toLowerCase().split('.').last;
    const allowed = {'jpg', 'jpeg', 'png', 'webp'};
    if (!allowed.contains(extension)) {
      throw ArgumentError('Please select a JPG, PNG or WEBP receipt image.');
    }
    final contentType = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final proofPath = 'payment_proofs/$uid/$orderId/$fileName';
    final storageRef = _storage.ref(proofPath);
    await storageRef.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );

    try {
      await _functions.httpsCallable('submitManualPaymentProof').call({
        'orderId': orderId,
        'transactionRef': refText,
        'proofPath': proofPath,
      });
    } catch (_) {
      // Keep the uploaded file available for retry; it is owner-scoped and
      // cannot change the order's payment state without the trusted callable.
      rethrow;
    }
  }

  Future<void> reviewRefund({
    required String orderId,
    required bool complete,
    String note = '',
  }) async {
    await _functions.httpsCallable('reviewManualRefund').call({
      'orderId': orderId,
      'decision': complete ? 'complete' : 'reject',
      'note': note.trim(),
    });
  }

  Future<void> review({
    required String orderId,
    required bool approve,
    String note = '',
  }) async {
    await _functions.httpsCallable('reviewManualPayment').call({
      'orderId': orderId,
      'decision': approve ? 'approve' : 'reject',
      'note': note.trim(),
    });
  }
}
