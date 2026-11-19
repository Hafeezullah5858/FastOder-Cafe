import 'package:cloud_functions/cloud_functions.dart';

class AdminService {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Future<void> cancelOrder({required String orderId, required String reason}) async {
    await _functions.httpsCallable('adminCancelOrder').call({
      'orderId': orderId,
      'reason': reason.trim(),
    });
  }

  Future<void> savePaymentSettings(Map<String, dynamic> settings) async {
    await _functions.httpsCallable('savePaymentSettings').call(settings);
  }

  Future<void> setUserRole({required String userId, required String role}) async {
    await _functions.httpsCallable('setUserRole').call({
      'userId': userId,
      'role': role,
    });
  }

  Future<void> reviewHomeChef({required String userId, required bool approved}) async {
    await _functions.httpsCallable('reviewHomeChef').call({
      'userId': userId,
      'approved': approved,
    });
  }

  Future<void> assignRider({required String orderId, required String riderId}) async {
    await _functions.httpsCallable('adminAssignRiderSecure').call({
      'orderId': orderId,
      'riderId': riderId,
    });
  }
}
