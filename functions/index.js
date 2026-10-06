const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const { setGlobalOptions } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
setGlobalOptions({ region: 'asia-south1', maxInstances: 10 });
const db = getFirestore();
const messaging = getMessaging();

const COMMISSION_RATE = 0.10;
const BASE_DELIVERY_FEE = 80;
const FREE_DELIVERY_ABOVE = 2500;
const PLATFORM_FEE = 0;

function money(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function safeQty(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1 || n > 50) {
    throw new HttpsError('invalid-argument', 'Invalid item quantity.');
  }
  return n;
}

function safeText(value, max = 500) {
  const text = String(value ?? '').trim();
  return text.length > max ? text.substring(0, max) : text;
}

/**
 * Trusted order creation endpoint.
 * Product prices, coupon rules and totals are read/calculated server-side.
 * The client can only submit product IDs, quantities and delivery details.
 */
exports.createOrderSecure = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');

  const data = request.data || {};
  const customerId = request.auth.uid;
  const vendorId = safeText(data.vendorId, 128);
  const address = safeText(data.address, 1000);
  const paymentMethod = safeText(data.paymentMethod, 40);
  const couponCode = safeText(data.couponCode, 64).toUpperCase();
  const requestId = safeText(data.requestId, 128);
  const rawItems = Array.isArray(data.items) ? data.items : [];

  if (!vendorId || !address || !requestId || rawItems.length === 0) {
    throw new HttpsError('invalid-argument', 'Vendor, address, request ID and items are required.');
  }
  if (paymentMethod !== 'cash_on_delivery') {
    throw new HttpsError('failed-precondition', 'Online payments are not enabled yet.');
  }
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(requestId)) {
    throw new HttpsError('invalid-argument', 'Invalid request ID.');
  }

  const orderRef = db.collection('orders').doc(requestId);
  const existing = await orderRef.get();
  if (existing.exists) {
    const existingData = existing.data() || {};
    if (existingData.customerId !== customerId) {
      throw new HttpsError('permission-denied', 'This request ID belongs to another account.');
    }
    return {
      orderId: existing.id,
      subtotal: money(existingData.subtotal),
      deliveryFee: money(existingData.deliveryFee),
      platformFee: money(existingData.platformFee),
      commission: money(existingData.commission),
      commissionRate: money(existingData.commissionRate),
      sellerPayout: money(existingData.sellerPayout),
      discount: money(existingData.discount),
      total: money(existingData.total),
      reused: true,
    };
  }

  const quantities = new Map();
  for (const item of rawItems) {
    const productId = safeText(item?.productId || item?.id, 128);
    if (!productId) throw new HttpsError('invalid-argument', 'A product ID is missing.');
    const qty = safeQty(item?.qty);
    quantities.set(productId, (quantities.get(productId) || 0) + qty);
  }

  const productRefs = [...quantities.keys()].map((id) => db.collection('products').doc(id));
  const productDocs = await db.getAll(...productRefs);
  if (productDocs.length !== quantities.size) {
    throw new HttpsError('not-found', 'One or more food items no longer exist.');
  }

  const normalizedItems = [];
  let subtotal = 0;
  let detectedVendor = null;

  for (const doc of productDocs) {
    if (!doc.exists) throw new HttpsError('not-found', 'A selected food item no longer exists.');
    const p = doc.data() || {};
    if (p.active !== true) throw new HttpsError('failed-precondition', `Food item "${p.name || doc.id}" is unavailable.`);
    if (String(p.vendorId || '') !== vendorId) throw new HttpsError('failed-precondition', 'All cart items must belong to the same seller.');
    const price = money(p.price);
    if (price < 0) throw new HttpsError('failed-precondition', 'Invalid seller price.');
    detectedVendor = detectedVendor || String(p.vendorType || 'restaurant');
    const qty = quantities.get(doc.id);
    const lineTotal = price * qty;
    subtotal += lineTotal;
    normalizedItems.push({
      productId: doc.id,
      name: safeText(p.name, 200),
      price,
      qty,
      vendorId,
      vendorType: String(p.vendorType || 'restaurant'),
      imageUrl: safeText(p.imageUrl, 1000),
    });
  }

  if (subtotal <= 0) throw new HttpsError('failed-precondition', 'Order total must be greater than zero.');

  let discount = 0;
  if (couponCode) {
    const couponSnap = await db.collection('coupons').doc(couponCode).get();
    if (!couponSnap.exists) throw new HttpsError('failed-precondition', 'Invalid coupon.');
    const c = couponSnap.data() || {};
    if (c.active !== true) throw new HttpsError('failed-precondition', 'Coupon is not active.');
    if (c.expiresAt && typeof c.expiresAt.toDate === 'function' && c.expiresAt.toDate().getTime() < Date.now()) {
      throw new HttpsError('failed-precondition', 'Coupon has expired.');
    }
    const minSubtotal = money(c.minSubtotal);
    if (subtotal < minSubtotal) throw new HttpsError('failed-precondition', `Minimum order is Rs. ${minSubtotal.toFixed(0)}.`);
    const allowedVendor = safeText(c.vendorId, 128);
    if (allowedVendor && allowedVendor !== vendorId) throw new HttpsError('failed-precondition', 'Coupon is not valid for this seller.');
    const value = Math.max(0, money(c.value));
    const maxDiscount = Math.max(0, money(c.maxDiscount ?? value));
    discount = String(c.type || 'fixed') === 'percent'
      ? Math.min(subtotal * value / 100, maxDiscount)
      : Math.min(value, subtotal);
  }

  // Keep delivery pricing deterministic and server-authoritative.
  // Distance-based pricing can be added later once a trusted route service is configured.
  const deliveryFee = subtotal >= FREE_DELIVERY_ABOVE ? 0 : BASE_DELIVERY_FEE;
  const commission = subtotal * COMMISSION_RATE;
  const total = Math.max(0, subtotal + deliveryFee + PLATFORM_FEE - discount);
  const sellerPayout = Math.max(0, subtotal - commission);

  const lat = data.deliveryLat == null ? null : Number(data.deliveryLat);
  const lng = data.deliveryLng == null ? null : Number(data.deliveryLng);
  if (lat != null && (!Number.isFinite(lat) || lat < -90 || lat > 90)) throw new HttpsError('invalid-argument', 'Invalid delivery latitude.');
  if (lng != null && (!Number.isFinite(lng) || lng < -180 || lng > 180)) throw new HttpsError('invalid-argument', 'Invalid delivery longitude.');

  const order = {
    customerId,
    vendorId,
    vendorType: detectedVendor || 'restaurant',
    riderId: '',
    status: 'placed',
    items: normalizedItems,
    subtotal,
    deliveryFee,
    platformFee: PLATFORM_FEE,
    commission,
    commissionRate: COMMISSION_RATE,
    sellerPayout,
    discount,
    couponCode,
    total,
    address,
    paymentMethod: 'cash_on_delivery',
    deliveryLat: lat,
    deliveryLng: lng,
    paymentStatus: 'pending_cash',
    refundStatus: 'not_applicable',
    cancellationReason: '',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  await orderRef.create(order);
  await db.collection('payments').doc(orderRef.id).set({
    orderId: orderRef.id,
    customerId,
    amount: total,
    method: 'cash_on_delivery',
    status: 'pending_cash',
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: false });
  return { orderId: orderRef.id, subtotal, deliveryFee, platformFee: PLATFORM_FEE, commission, commissionRate: COMMISSION_RATE, sellerPayout, discount, total, reused: false };
});

async function notifyUser({ recipientId, title, body, orderId, eventKey }) {
  if (!recipientId) return;
  const notificationId = `${orderId}_${eventKey}`.replace(/[^A-Za-z0-9_-]/g, '_').substring(0, 140);
  await db.collection('notifications').doc(notificationId).set({
    recipientId,
    title,
    body,
    orderId,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  try {
    const user = await db.collection('users').doc(recipientId).get();
    const token = user.data()?.fcmToken;
    if (token) {
      await messaging.send({
        token,
        notification: { title, body },
        data: { orderId, status: eventKey },
        android: { priority: 'high', notification: { channelId: 'orders' } },
      });
    }
  } catch (error) {
    if (error?.code === 'messaging/registration-token-not-registered' || error?.code === 'messaging/invalid-registration-token') {
      await db.collection('users').doc(recipientId).set({ fcmToken: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
    logger.warn('FCM send failed; in-app notification remains available.', { recipientId, error: String(error) });
  }
}

/**
 * Server-side order event processor. It creates notifications and seller
 * earnings without allowing vendor/rider clients to forge notification docs.
 */
exports.processOrderUpdate = onDocumentUpdated('orders/{orderId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after) return;

  const orderId = event.params.orderId;
  const statusChanged = before.status !== after.status;
  if (statusChanged && after.customerId) {
    const title = after.status === 'accepted' ? 'Order accepted' :
      after.status === 'preparing' ? 'Order is being prepared' :
      after.status === 'ready' ? 'Order is ready' :
      after.status === 'picked_up' ? 'Rider picked up your order' :
      after.status === 'on_the_way' ? 'Your order is on the way' :
      after.status === 'delivered' ? 'Order delivered' :
      after.status === 'cancelled' ? 'Order cancelled' : 'Order updated';
    const body = `Order #${orderId.substring(0, 6)} is now ${after.status.replaceAll('_', ' ')}.`;
    await notifyUser({ recipientId: after.customerId, title, body, orderId, eventKey: after.status });
  }

  if (before.riderId !== after.riderId && after.riderId) {
    await notifyUser({
      recipientId: after.customerId,
      title: 'Rider assigned',
      body: `A rider has been assigned to order #${orderId.substring(0, 6)}.`,
      orderId,
      eventKey: `rider_${after.riderId}`,
    });
  }

  if (before.status !== 'delivered' && after.status === 'delivered' && after.vendorId) {
    const ref = db.collection('seller_earnings').doc(orderId);
    await ref.set({
      orderId,
      sellerId: after.vendorId,
      vendorType: after.vendorType || 'vendor',
      subtotal: money(after.subtotal),
      commissionRate: money(after.commissionRate),
      commission: money(after.commission),
      sellerPayout: money(after.sellerPayout),
      deliveryFee: money(after.deliveryFee),
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: false });
  }

  if (before.status !== 'cancelled' && after.status === 'cancelled' && after.paymentMethod !== 'cash_on_delivery') {
    await db.collection('refund_requests').doc(orderId).set({
      orderId,
      customerId: after.customerId,
      amount: money(after.total),
      reason: after.cancellationReason || 'Customer cancellation',
      status: 'pending_gateway_refund',
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
});
