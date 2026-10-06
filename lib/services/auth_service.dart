import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn(String email, String password) async {
    return _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<UserCredential> signUp({required String email, required String password, required String name}) async {
    final credential = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    final user = credential.user!;
    await user.updateDisplayName(name.trim());
    await _db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name.trim(),
      'email': email.trim(),
      'role': 'customer',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return credential;
  }

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());
  Future<void> signOut() => _auth.signOut();

  Future<String> getRole() async {
    final user = currentUser;
    if (user == null) return 'customer';
    final snap = await _db.collection('users').doc(user.uid).get();
    return (snap.data()?['role'] as String?) ?? 'customer';
  }
}
