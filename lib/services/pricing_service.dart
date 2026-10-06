class OrderQuote {
  final double subtotal;
  final double deliveryFee;
  final double platformFee;
  final double commission;
  final double discount;
  final double total;
  final double sellerPayout;
  final double commissionRate;

  const OrderQuote({required this.subtotal, required this.deliveryFee, required this.platformFee, required this.commission, required this.discount, required this.total, required this.sellerPayout, required this.commissionRate});
}

/// Centralized pricing rules. For production, mirror/enforce these values in a trusted
/// Cloud Function before accepting payment or marking an order as payable.
class PricingService {
  static const double defaultCommissionRate = 0.10; // 10% marketplace commission
  static const double baseDeliveryFee = 80.0;
  static const double perKmDeliveryFee = 20.0;
  static const double freeDeliveryAbove = 2500.0;
  static const double platformFee = 0.0;

  OrderQuote quote({required double subtotal, double distanceKm = 0, double commissionRate = defaultCommissionRate, double discount = 0}) {
    final delivery = subtotal >= freeDeliveryAbove ? 0.0 : baseDeliveryFee + (distanceKm.clamp(0, 30) * perKmDeliveryFee);
    final commission = subtotal * commissionRate;
    final safeDiscount = discount.clamp(0, subtotal).toDouble();
    final total = subtotal + delivery + platformFee - safeDiscount;
    final payout = subtotal - commission;
    return OrderQuote(subtotal: subtotal, deliveryFee: delivery, platformFee: platformFee, commission: commission, discount: safeDiscount, total: total, sellerPayout: payout, commissionRate: commissionRate);
  }
}
