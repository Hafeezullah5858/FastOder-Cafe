import 'package:cloud_firestore/cloud_firestore.dart';

class OrderModel {
  final String id;
  final String customerId;
  final String vendorId;
  final String riderId;
  final String status;
  final double total;
  final double subtotal;
  final double deliveryFee;
  final double platformFee;
  final double commission;
  final double commissionRate;
  final double sellerPayout;
  final double discount;
  final String couponCode;
  final List<Map<String, dynamic>> items;
  final String address;
  final String paymentMethod;
  final String paymentStatus;
  final String refundStatus;
  final String cancellationReason;
  final DateTime? createdAt;
  final double? deliveryLat;
  final double? deliveryLng;

  const OrderModel({
    required this.id,
    required this.customerId,
    required this.vendorId,
    this.riderId = '',
    required this.status,
    required this.total,
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.platformFee = 0,
    this.commission = 0,
    this.commissionRate = 0.10,
    this.sellerPayout = 0,
    this.discount = 0,
    this.couponCode = '',
    this.items = const [],
    this.address = '',
    this.paymentMethod = 'cash_on_delivery',
    this.paymentStatus = 'pending_cash',
    this.refundStatus = 'not_applicable',
    this.cancellationReason = '',
    this.createdAt,
    this.deliveryLat,
    this.deliveryLng,
  });

  Map<String, dynamic> toMap() => {
    'customerId': customerId, 'vendorId': vendorId, 'riderId': riderId,
    'status': status, 'subtotal': subtotal, 'deliveryFee': deliveryFee, 'platformFee': platformFee, 'commission': commission, 'commissionRate': commissionRate, 'sellerPayout': sellerPayout, 'discount': discount, 'couponCode': couponCode, 'total': total, 'items': items, 'address': address,
    'paymentMethod': paymentMethod, 'paymentStatus': paymentStatus, 'refundStatus': refundStatus, 'cancellationReason': cancellationReason, 'createdAt': FieldValue.serverTimestamp(),
  };

  factory OrderModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final ts = d['createdAt'];
    return OrderModel(
      id: doc.id, customerId: d['customerId'] ?? '', vendorId: d['vendorId'] ?? '', riderId: d['riderId'] ?? '',
      status: d['status'] ?? 'placed', total: ((d['total'] ?? 0) as num).toDouble(), subtotal: ((d['subtotal'] ?? d['total'] ?? 0) as num).toDouble(), deliveryFee: ((d['deliveryFee'] ?? 0) as num).toDouble(), platformFee: ((d['platformFee'] ?? 0) as num).toDouble(), commission: ((d['commission'] ?? 0) as num).toDouble(), discount: ((d['discount'] ?? 0) as num).toDouble(), couponCode: d['couponCode'] ?? '', commissionRate: ((d['commissionRate'] ?? 0.10) as num).toDouble(), sellerPayout: ((d['sellerPayout'] ?? 0) as num).toDouble(),
      items: List<Map<String, dynamic>>.from((d['items'] ?? []).map((e) => Map<String, dynamic>.from(e as Map))),
      address: d['address'] ?? '', paymentMethod: d['paymentMethod'] ?? 'cash_on_delivery', paymentStatus: d['paymentStatus'] ?? 'pending_cash', refundStatus: d['refundStatus'] ?? 'not_applicable', cancellationReason: d['cancellationReason'] ?? '',
      deliveryLat: (d['deliveryLat'] as num?)?.toDouble(), deliveryLng: (d['deliveryLng'] as num?)?.toDouble(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}
