const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const { setGlobalOptions } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');
const crypto = require('node:crypto');
const { isSupportedPaymentMethod, initialPaymentStatus, isManualPaymentMethod, manualAccountSnapshot, isValidProofPath, canAssignOrder, hasAvailableStock, hashDeliveryOtp, verifyDeliveryOtp, availablePayoutBalance } = require('./payment_policy');

initializeApp();
setGlobalOptions({ region: 'asia-south1', maxInstances: 10 });
const db = getFirestore();
const messaging = getMessaging();
const storageBucket = getStorage().bucket();

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
  if (!isSupportedPaymentMethod(paymentMethod)) {
    throw new HttpsError('invalid-argument', 'Unsupported payment method.');
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

  const vendorSettings = await db.collection('vendor_settings').doc(vendorId).get();
  if (vendorSettings.exists && vendorSettings.data()?.isOpen === false) {
    throw new HttpsError('failed-precondition', 'This seller is currently closed and cannot accept new orders.');
  }
  let paymentAccountSnapshot = null;
  if (paymentMethod !== 'cash_on_delivery') {
    const settingsSnap = await db.collection('app_settings').doc('payment_methods').get();
    paymentAccountSnapshot = manualAccountSnapshot(paymentMethod, settingsSnap.data() || {});
    if (!paymentAccountSnapshot) {
      throw new HttpsError('failed-precondition', 'This manual payment method is not configured by the administrator yet.');
    }
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
      menuCategory: safeText(p.menuCategory || 'Other', 50),
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

  const paymentStatusAtCreation = initialPaymentStatus(paymentMethod);
  const deliveryOtp = String(crypto.randomInt(100000, 1000000));
  const deliveryOtpHash = hashDeliveryOtp(deliveryOtp);

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
    paymentMethod,
    paymentAccountSnapshot,
    deliveryLat: lat,
    deliveryLng: lng,
    paymentStatus: paymentStatusAtCreation,
    refundStatus: 'not_applicable',
    cancellationReason: '',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  const paymentRef = db.collection('payments').doc(orderRef.id);
  const deliveryOtpRef = db.collection('delivery_otps').doc(orderRef.id);
  const deliveryOtpSecretRef = db.collection('delivery_otp_secrets').doc(orderRef.id);
  const transactionResult = await db.runTransaction(async (tx) => {
    const current = await tx.get(orderRef);
    if (current.exists) {
      const currentData = current.data() || {};
      if (currentData.customerId !== customerId) {
        throw new HttpsError('permission-denied', 'This request ID belongs to another account.');
      }
      return { reused: true, order: currentData };
    }

    // Re-check store state and inventory inside the same transaction as order
    // creation so a concurrent close/stock update cannot slip through.
    const currentVendorSettings = await tx.get(db.collection('vendor_settings').doc(vendorId));
    if (currentVendorSettings.exists && currentVendorSettings.data()?.isOpen === false) {
      throw new HttpsError('failed-precondition', 'This seller is currently closed and cannot accept new orders.');
    }
    const freshProducts = await Promise.all(productRefs.map((ref) => tx.get(ref)));
    if (couponCode) {
      const currentCouponSnap = await tx.get(db.collection('coupons').doc(couponCode));
      if (!currentCouponSnap.exists) throw new HttpsError('aborted', 'Coupon changed while placing your order.');
      const currentCoupon = currentCouponSnap.data() || {};
      if (currentCoupon.active !== true) throw new HttpsError('failed-precondition', 'Coupon is no longer active.');
      if (currentCoupon.expiresAt && typeof currentCoupon.expiresAt.toDate === 'function' && currentCoupon.expiresAt.toDate().getTime() < Date.now()) {
        throw new HttpsError('failed-precondition', 'Coupon has expired.');
      }
      const currentMinimum = money(currentCoupon.minSubtotal);
      const currentVendor = safeText(currentCoupon.vendorId, 128);
      if (subtotal < currentMinimum || (currentVendor && currentVendor !== vendorId)) {
        throw new HttpsError('failed-precondition', 'Coupon is no longer valid for this order.');
      }
      const currentValue = Math.max(0, money(currentCoupon.value));
      const currentMax = Math.max(0, money(currentCoupon.maxDiscount ?? currentValue));
      const currentDiscount = String(currentCoupon.type || 'fixed') === 'percent'
        ? Math.min(subtotal * currentValue / 100, currentMax)
        : Math.min(currentValue, subtotal);
      if (Math.abs(currentDiscount - discount) > 0.01) {
        throw new HttpsError('aborted', 'Coupon terms changed while placing your order. Please retry.');
      }
    }
    for (const fresh of freshProducts) {
      if (!fresh.exists) throw new HttpsError('not-found', 'A selected food item no longer exists.');
      const product = fresh.data() || {};
      const requestedQty = quantities.get(fresh.id) || 0;
      const expected = normalizedItems.find((item) => item.productId === fresh.id);
      if (product.active !== true || String(product.vendorId || '') !== vendorId || money(product.price) !== expected.price) {
        throw new HttpsError('aborted', 'A food item changed while placing your order. Please refresh the menu and try again.');
      }
      if (product.stockQty != null && (!Number.isInteger(product.stockQty) || product.stockQty < -1)) {
        throw new HttpsError('failed-precondition', `Invalid stock configuration for ${product.name || fresh.id}.`);
      }
      if (!hasAvailableStock(product.stockQty, requestedQty)) {
        throw new HttpsError('failed-precondition', `Not enough stock for ${product.name || fresh.id}.`);
      }
      if (Number.isInteger(product.stockQty) && product.stockQty >= 0) {
        tx.update(fresh.ref, {
          stockQty: product.stockQty - requestedQty,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    tx.create(orderRef, order);
    tx.create(paymentRef, {
      orderId: orderRef.id,
      customerId,
      amount: total,
      method: paymentMethod,
      paymentAccountSnapshot,
      status: paymentStatusAtCreation,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(deliveryOtpRef, {
      orderId: orderRef.id,
      customerId,
      code: deliveryOtp,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.create(deliveryOtpSecretRef, {
      orderId: orderRef.id,
      codeHash: deliveryOtpHash,
      attempts: 0,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { reused: false, order };
  });
  const resultOrder = transactionResult.order || order;
  return {
    orderId: orderRef.id,
    subtotal: money(resultOrder.subtotal),
    deliveryFee: money(resultOrder.deliveryFee),
    platformFee: money(resultOrder.platformFee),
    commission: money(resultOrder.commission),
    commissionRate: money(resultOrder.commissionRate),
    sellerPayout: money(resultOrder.sellerPayout),
    discount: money(resultOrder.discount),
    total: money(resultOrder.total),
    reused: transactionResult.reused,
  };
});

function requireRole(uid, expectedRole) {
  return db.collection('users').doc(uid).get().then((snap) => {
    const role = snap.exists ? String((snap.data() || {}).role || '') : '';
    if (role !== expectedRole) throw new HttpsError('permission-denied', 'This action is not allowed for your account.');
    return role;
  });
}

async function requireActiveRider(uid) {
  const snap = await db.collection('users').doc(uid).get();
  const user = snap.exists ? (snap.data() || {}) : {};
  if (user.role !== 'rider' || user.riderApproved === false) {
    throw new HttpsError('permission-denied', 'Your rider account is not approved or is suspended.');
  }
  return user;
}

async function refreshRiderLocationVisibility(riderId) {
  const orders = await db.collection('orders').where('riderId', '==', riderId).get();
  const customerIds = [...new Set(orders.docs
    .filter((doc) => ['ready', 'picked_up', 'on_the_way'].includes(String(doc.data()?.status || '')))
    .map((doc) => String(doc.data()?.customerId || ''))
    .filter(Boolean))].slice(0, 20);
  await db.collection('rider_locations').doc(riderId).set({
    visibleToCustomerIds: customerIds,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

exports.submitManualPaymentProof = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  const uid = request.auth.uid;
  const orderId = safeText(request.data?.orderId, 128);
  const transactionRef = safeText(request.data?.transactionRef, 80);
  const proofPath = safeText(request.data?.proofPath, 500);
  if (!orderId || transactionRef.length < 5 || !proofPath) {
    throw new HttpsError('invalid-argument', 'Order, transaction reference and receipt are required.');
  }
  if (!isValidProofPath(proofPath, uid, orderId)) {
    throw new HttpsError('invalid-argument', 'Invalid payment receipt path.');
  }
  const proofFile = storageBucket.file(proofPath);
  const [proofExists] = await proofFile.exists();
  if (!proofExists) throw new HttpsError('failed-precondition', 'Payment receipt upload was not found. Please upload it again.');
  const [proofMetadata] = await proofFile.getMetadata();
  if (Number(proofMetadata.size || 0) > 5 * 1024 * 1024 || !/^image\/(jpeg|png|webp)$/i.test(proofMetadata.contentType || '')) {
    throw new HttpsError('invalid-argument', 'Payment receipt must be an image smaller than 5 MB.');
  }

  const orderRef = db.collection('orders').doc(orderId);
  const paymentRef = db.collection('payments').doc(orderId);
  await db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) throw new HttpsError('not-found', 'Order not found.');
    const order = orderSnap.data() || {};
    if (order.customerId !== uid) throw new HttpsError('permission-denied', 'This order does not belong to you.');
    if (!isManualPaymentMethod(order.paymentMethod)) throw new HttpsError('failed-precondition', 'This order does not use manual payment.');
    if (order.status !== 'placed') throw new HttpsError('failed-precondition', 'Payment proof can only be submitted before seller acceptance.');
    if (!['awaiting_payment', 'payment_rejected'].includes(order.paymentStatus)) {
      throw new HttpsError('failed-precondition', 'Payment proof is already submitted or the order is paid.');
    }
    tx.set(paymentRef, {
      orderId,
      customerId: uid,
      amount: money(order.total),
      method: order.paymentMethod,
      status: 'pending_verification',
      transactionRef,
      proofPath,
      submittedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.update(orderRef, {
      paymentStatus: 'pending_verification',
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true, status: 'pending_verification' };
});

exports.requestSellerPayout = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  const sellerId = request.auth.uid;
  const userSnap = await db.collection('users').doc(sellerId).get();
  const role = String(userSnap.data()?.role || '');
  if (!['vendor', 'home_chef'].includes(role)) throw new HttpsError('permission-denied', 'Only approved sellers can request payouts.');
  if (role === 'home_chef' && userSnap.data()?.sellerApproved !== true) {
    throw new HttpsError('permission-denied', 'Your Home Chef account is not approved yet.');
  }
  const amount = money(request.data?.amount);
  const accountTitle = safeText(request.data?.accountTitle, 120);
  const accountNumber = safeText(request.data?.accountNumber, 80);
  const bankName = safeText(request.data?.bankName, 100);
  const iban = safeText(request.data?.iban, 80);
  if (amount <= 0 || !accountTitle || !(accountNumber || iban)) {
    throw new HttpsError('invalid-argument', 'Enter a valid amount and payout account details.');
  }
  const userRef = db.collection('users').doc(sellerId);
  const earningsQuery = db.collection('seller_earnings').where('sellerId', '==', sellerId);
  const payoutsQuery = db.collection('payouts').where('sellerId', '==', sellerId);
  const balanceRef = db.collection('seller_payout_balances').doc(sellerId);
  const requestRef = db.collection('payout_requests').doc();
  await db.runTransaction(async (tx) => {
    const [currentUserSnap, earningsSnap, payoutsSnap, balanceSnap] = await Promise.all([
      tx.get(userRef), tx.get(earningsQuery), tx.get(payoutsQuery), tx.get(balanceRef),
    ]);
    const currentUser = currentUserSnap.data() || {};
    if (!['vendor', 'home_chef'].includes(currentUser.role) || (currentUser.role === 'home_chef' && currentUser.sellerApproved !== true)) {
      throw new HttpsError('permission-denied', 'Only active approved sellers can request payouts.');
    }
    const balance = balanceSnap.data() || {};
    const reservedAmount = money(balance.reservedAmount);
    const available = availablePayoutBalance(
      earningsSnap.docs.map((d) => d.data()),
      payoutsSnap.docs.map((d) => d.data()),
      reservedAmount,
    );
    if (amount > available) throw new HttpsError('failed-precondition', `Requested amount exceeds available balance Rs. ${available.toFixed(0)}.`);
    tx.set(balanceRef, {
      sellerId,
      reservedAmount: reservedAmount + amount,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.create(requestRef, {
      sellerId,
      sellerRole: String(currentUser.role),
      amount,
      accountTitle,
      accountNumber,
      bankName,
      iban,
      status: 'pending',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true, requestId: requestRef.id };
});

exports.reviewSellerPayout = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const requestId = safeText(request.data?.requestId, 128);
  const decision = safeText(request.data?.decision, 16);
  const reference = safeText(request.data?.reference, 120);
  const note = safeText(request.data?.note, 300);
  if (!requestId || !['paid', 'reject'].includes(decision)) throw new HttpsError('invalid-argument', 'Payout request and valid decision are required.');
  if (decision === 'paid' && !reference) throw new HttpsError('invalid-argument', 'Enter the bank/wallet transfer reference before marking paid.');
  const requestRef = db.collection('payout_requests').doc(requestId);
  const payoutRef = db.collection('payouts').doc(requestId);
  let sellerId = '';
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(requestRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Payout request not found.');
    const payoutRequest = snap.data() || {};
    if (payoutRequest.status !== 'pending') throw new HttpsError('failed-precondition', 'This payout request has already been reviewed.');
    sellerId = String(payoutRequest.sellerId || '');
    const balanceRef = db.collection('seller_payout_balances').doc(sellerId);
    const balanceSnap = await tx.get(balanceRef);
    const balance = balanceSnap.data() || {};
    const amount = money(payoutRequest.amount);
    const nextReserved = Math.max(0, money(balance.reservedAmount) - amount);
    const paid = decision === 'paid';
    tx.set(balanceRef, { sellerId, reservedAmount: nextReserved, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.update(requestRef, {
      status: paid ? 'paid' : 'rejected',
      paymentReference: reference,
      reviewNote: note,
      reviewedBy: request.auth.uid,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (paid) tx.create(payoutRef, {
      requestId,
      sellerId,
      amount,
      method: 'manual_bank_transfer',
      paymentReference: reference,
      status: 'paid',
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: paid ? 'seller_payout_paid' : 'seller_payout_rejected',
      targetType: 'payout_request',
      targetId: requestId,
      note: reference || note,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  await notifyUser({
    recipientId: sellerId,
    title: decision === 'paid' ? 'Payout sent' : 'Payout request rejected',
    body: decision === 'paid' ? 'Your seller payout has been marked as sent.' : 'Your seller payout request was rejected.',
    orderId: requestId,
    eventKey: `payout_${decision}`,
  });
  return { success: true, status: decision === 'paid' ? 'paid' : 'rejected' };
});

exports.createSupportTicket = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  const customerId = request.auth.uid;
  const category = safeText(request.data?.category, 40);
  const message = safeText(request.data?.message, 2000);
  const orderId = safeText(request.data?.orderId, 128);
  if (!category || message.length < 10) {
    throw new HttpsError('invalid-argument', 'Choose a category and enter at least 10 characters.');
  }
  if (orderId) {
    const order = await db.collection('orders').doc(orderId).get();
    if (!order.exists || order.data()?.customerId !== customerId) {
      throw new HttpsError('permission-denied', 'The selected order does not belong to your account.');
    }
  }
  const ticketRef = db.collection('support_tickets').doc();
  await ticketRef.create({
    customerId,
    orderId: orderId || '',
    category,
    message,
    status: 'open',
    adminResponse: '',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { success: true, ticketId: ticketRef.id };
});

exports.reviewSupportTicket = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const ticketId = safeText(request.data?.ticketId, 128);
  const status = safeText(request.data?.status, 20);
  const response = safeText(request.data?.response, 1000);
  if (!ticketId || !['in_progress', 'resolved', 'closed'].includes(status)) {
    throw new HttpsError('invalid-argument', 'Ticket and valid status are required.');
  }
  const ticketRef = db.collection('support_tickets').doc(ticketId);
  let ticketCustomerId = '';
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ticketRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Support ticket not found.');
    ticketCustomerId = String(snap.data()?.customerId || '');
    tx.update(ticketRef, {
      status,
      adminResponse: response,
      reviewedBy: request.auth.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: 'support_ticket_updated',
      targetType: 'support_ticket',
      targetId: ticketId,
      note: status,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  await notifyUser({
    recipientId: ticketCustomerId,
    title: 'Support ticket updated',
    body: `Your support ticket is now ${status}.`,
    orderId: ticketId,
    eventKey: `support_${status}`,
  });
  return { success: true, ticketId, status };
});

exports.savePaymentSettings = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const input = request.data || {};
  const cleanAccount = (key) => {
    const raw = input[key] && typeof input[key] === 'object' ? input[key] : {};
    return {
      enabled: raw.enabled === true,
      accountTitle: safeText(raw.accountTitle, 120),
      accountNumber: safeText(raw.accountNumber, 80),
      bankName: safeText(raw.bankName, 100),
      iban: safeText(raw.iban, 80),
    };
  };
  const jazzcash = cleanAccount('jazzcash');
  const easypaisa = cleanAccount('easypaisa');
  const bankTransfer = cleanAccount('bank_transfer');
  if (jazzcash.enabled && !jazzcash.accountNumber) throw new HttpsError('invalid-argument', 'JazzCash account number is required when enabled.');
  if (easypaisa.enabled && !easypaisa.accountNumber) throw new HttpsError('invalid-argument', 'Easypaisa account number is required when enabled.');
  if (bankTransfer.enabled && !(bankTransfer.accountNumber || bankTransfer.iban)) throw new HttpsError('invalid-argument', 'Bank account number or IBAN is required when enabled.');
  const batch = db.batch();
  batch.set(db.collection('app_settings').doc('payment_methods'), {
    jazzcash,
    easypaisa,
    bank_transfer: bankTransfer,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: request.auth.uid,
  }, { merge: true });
  batch.create(db.collection('admin_audit_logs').doc(), {
    actorId: request.auth.uid,
    action: 'manual_payment_settings_updated',
    targetType: 'app_settings',
    targetId: 'payment_methods',
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { success: true };
});

exports.setUserRole = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const targetUid = safeText(request.data?.userId, 128);
  const role = safeText(request.data?.role, 32);
  if (!targetUid || role !== 'customer') {
    throw new HttpsError('failed-precondition', 'Business and rider access can only be granted through an approved application. This action may only return an account to customer access.');
  }
  if (targetUid === request.auth.uid) throw new HttpsError('failed-precondition', 'You cannot change your own admin role here.');
  const userRef = db.collection('users').doc(targetUid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) throw new HttpsError('not-found', 'User not found.');
    const current = snap.data() || {};
    if (current.role === 'admin') throw new HttpsError('failed-precondition', 'Admin roles must be managed separately.');
    if (['vendor', 'home_chef', 'rider'].includes(String(current.role || ''))) {
      const field = current.role === 'rider' ? 'riderId' : 'vendorId';
      const activeStatuses = current.role === 'rider'
        ? ['ready', 'picked_up', 'on_the_way']
        : ['placed', 'accepted', 'preparing', 'ready'];
      const activeOrders = await tx.get(
        db.collection('orders').where(field, '==', targetUid).where('status', 'in', activeStatuses),
      );
      if (!activeOrders.empty) {
        throw new HttpsError('failed-precondition', 'This account still has active orders. Complete, cancel or reassign those orders before suspending access.');
      }
      if (current.role === 'vendor' || current.role === 'rider') {
        const applicationCollection = current.role === 'vendor' ? 'vendor_applications' : 'rider_applications';
        const applicationRef = db.collection(applicationCollection).doc(targetUid);
        const applicationSnap = await tx.get(applicationRef);
        if (applicationSnap.exists) {
          tx.update(applicationRef, {
            status: 'suspended',
            adminNote: 'Business access was suspended by an administrator.',
            reviewedBy: request.auth.uid,
            reviewedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      }
    }
    tx.update(userRef, {
      role,
      vendorApproved: false,
      riderApproved: false,
      ...(current.role === 'home_chef' ? { sellerApproved: false } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: 'user_role_changed',
      targetType: 'user',
      targetId: targetUid,
      note: `Role changed from ${current.role || 'customer'} to ${role}`,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true, userId: targetUid, role };
});

exports.reviewHomeChefApplication = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const targetUid = safeText(request.data?.userId, 128);
  const decision = safeText(request.data?.decision, 16);
  const note = safeText(request.data?.note, 300);
  if (!targetUid || !['approve', 'reject'].includes(decision)) throw new HttpsError('invalid-argument', 'Applicant and approve/reject decision are required.');
  const applicationRef = db.collection('home_chef_applications').doc(targetUid);
  const userRef = db.collection('users').doc(targetUid);
  await db.runTransaction(async (tx) => {
    const [applicationSnap, userSnap] = await Promise.all([tx.get(applicationRef), tx.get(userRef)]);
    if (!applicationSnap.exists || !userSnap.exists) throw new HttpsError('not-found', 'Home Chef application or user not found.');
    const application = applicationSnap.data() || {};
    const applicant = userSnap.data() || {};
    if (application.status !== 'pending' || application.userId !== targetUid) throw new HttpsError('failed-precondition', 'This application is not pending review.');
    if (decision === 'approve' && !['customer', 'home_chef'].includes(applicant.role)) throw new HttpsError('failed-precondition', 'Only customer accounts can be approved as a new Home Chef.');
    const approved = decision === 'approve';
    tx.update(applicationRef, {
      status: approved ? 'approved' : 'rejected',
      adminNote: note,
      reviewedBy: request.auth.uid,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (approved) tx.update(userRef, {
      role: 'home_chef',
      sellerApproved: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
    else if (applicant.role === 'home_chef' && applicant.sellerApproved !== true) tx.update(userRef, {
      role: 'customer',
      sellerApproved: false,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: approved ? 'home_chef_application_approved' : 'home_chef_application_rejected',
      targetType: 'user',
      targetId: targetUid,
      note,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  await notifyUser({
    recipientId: targetUid,
    title: decision === 'approve' ? 'Home Chef application approved' : 'Home Chef application update',
    body: decision === 'approve' ? 'Your Home Chef seller account is approved.' : 'Your Home Chef application was not approved. Please review the admin note.',
    orderId: targetUid,
    eventKey: `home_chef_application_${decision}`,
  });
  return { success: true, status: decision === 'approve' ? 'approved' : 'rejected' };
});

exports.reviewBusinessApplication = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const type = safeText(request.data?.type, 16);
  const targetUid = safeText(request.data?.userId, 128);
  const decision = safeText(request.data?.decision, 16);
  const note = safeText(request.data?.note, 300);
  if (!['vendor', 'rider'].includes(type) || !targetUid || !['approve', 'reject'].includes(decision)) {
    throw new HttpsError('invalid-argument', 'A valid vendor/rider application and decision are required.');
  }
  const collection = type === 'vendor' ? 'vendor_applications' : 'rider_applications';
  const applicationRef = db.collection(collection).doc(targetUid);
  const userRef = db.collection('users').doc(targetUid);
  const approved = decision === 'approve';
  await db.runTransaction(async (tx) => {
    const [applicationSnap, userSnap] = await Promise.all([tx.get(applicationRef), tx.get(userRef)]);
    if (!applicationSnap.exists || !userSnap.exists) throw new HttpsError('not-found', 'Application or user account not found.');
    const application = applicationSnap.data() || {};
    const user = userSnap.data() || {};
    if (application.userId !== targetUid || application.status !== 'pending') {
      throw new HttpsError('failed-precondition', 'This application is not waiting for review.');
    }
    if (approved && !['customer', type].includes(String(user.role || 'customer'))) {
      throw new HttpsError('failed-precondition', 'This account already has a different business role.');
    }
    tx.update(applicationRef, {
      status: approved ? 'approved' : 'rejected',
      adminNote: note,
      reviewedBy: request.auth.uid,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (approved) {
      tx.update(userRef, {
        role: type,
        ...(type === 'vendor' ? { vendorApproved: true } : { riderApproved: true }),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: `${type}_application_${approved ? 'approved' : 'rejected'}`,
      targetType: 'user',
      targetId: targetUid,
      note,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  await notifyUser({
    recipientId: targetUid,
    title: `${type === 'vendor' ? 'Vendor' : 'Rider'} application ${approved ? 'approved' : 'update'}`,
    body: approved
      ? `Your ${type} account is approved. Sign in again to open your dashboard.`
      : `Your ${type} application was not approved. ${note}`.trim(),
    orderId: `${type}_${targetUid}`,
    eventKey: `${type}_application_${decision}`,
  });
  return { success: true, status: approved ? 'approved' : 'rejected', role: approved ? type : 'customer' };
});

exports.reviewHomeChef = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const targetUid = safeText(request.data?.userId, 128);
  const approved = request.data?.approved === true;
  if (!targetUid) throw new HttpsError('invalid-argument', 'User ID is required.');
  const userRef = db.collection('users').doc(targetUid);
  const applicationRef = db.collection('home_chef_applications').doc(targetUid);
  await db.runTransaction(async (tx) => {
    const [snap, applicationSnap] = await Promise.all([tx.get(userRef), tx.get(applicationRef)]);
    if (!snap.exists) throw new HttpsError('not-found', 'User not found.');
    const user = snap.data() || {};
    if (user.role !== 'home_chef') throw new HttpsError('failed-precondition', 'This user is not a Home Chef.');
    tx.update(userRef, { sellerApproved: approved, updatedAt: FieldValue.serverTimestamp() });
    if (applicationSnap.exists && applicationSnap.data()?.status === 'pending') {
      tx.update(applicationRef, { status: approved ? 'approved' : 'rejected', reviewedBy: request.auth.uid, reviewedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    }
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: approved ? 'home_chef_approved' : 'home_chef_suspended',
      targetType: 'user',
      targetId: targetUid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true, userId: targetUid, approved };
});

exports.adminCancelOrder = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const orderId = safeText(request.data?.orderId, 128);
  const reason = safeText(request.data?.reason, 300) || 'Cancelled by administrator';
  if (!orderId) throw new HttpsError('invalid-argument', 'Order ID is required.');
  const orderRef = db.collection('orders').doc(orderId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) throw new HttpsError('not-found', 'Order not found.');
    const order = snap.data() || {};
    if (['delivered', 'cancelled'].includes(order.status)) throw new HttpsError('failed-precondition', 'This order can no longer be cancelled.');
    const refundStatus = order.paymentMethod !== 'cash_on_delivery' && order.paymentStatus === 'paid' ? 'pending' : 'not_applicable';
    tx.update(orderRef, {
      status: 'cancelled',
      cancellationReason: reason,
      refundStatus,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: 'order_cancelled_by_admin',
      targetType: 'order',
      targetId: orderId,
      note: reason,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true, orderId, status: 'cancelled' };
});

exports.reviewManualPayment = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const orderId = safeText(request.data?.orderId, 128);
  const decision = safeText(request.data?.decision, 16);
  const note = safeText(request.data?.note, 300);
  if (!orderId || !['approve', 'reject'].includes(decision)) {
    throw new HttpsError('invalid-argument', 'Order and approve/reject decision are required.');
  }
  const orderRef = db.collection('orders').doc(orderId);
  const paymentRef = db.collection('payments').doc(orderId);
  let paymentCustomerId = '';
  await db.runTransaction(async (tx) => {
    const [orderSnap, paymentSnap] = await Promise.all([tx.get(orderRef), tx.get(paymentRef)]);
    if (!orderSnap.exists || !paymentSnap.exists) throw new HttpsError('not-found', 'Payment record not found.');
    const order = orderSnap.data() || {};
    paymentCustomerId = String(order.customerId || '');
    const payment = paymentSnap.data() || {};
    if (!isManualPaymentMethod(order.paymentMethod) || payment.status !== 'pending_verification' || order.paymentStatus !== 'pending_verification') {
      throw new HttpsError('failed-precondition', 'This payment is not awaiting verification.');
    }
    const approved = decision === 'approve';
    const nextPaymentStatus = approved ? 'paid' : 'payment_rejected';
    tx.update(paymentRef, {
      status: nextPaymentStatus,
      reviewNote: note,
      reviewedBy: request.auth.uid,
      reviewedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.update(orderRef, {
      paymentStatus: nextPaymentStatus,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const auditRef = db.collection('admin_audit_logs').doc();
    tx.create(auditRef, {
      actorId: request.auth.uid,
      action: approved ? 'manual_payment_approved' : 'manual_payment_rejected',
      targetType: 'order',
      targetId: orderId,
      note,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  await notifyUser({
    recipientId: paymentCustomerId,
    title: decision === 'approve' ? 'Payment verified' : 'Payment needs correction',
    body: decision === 'approve' ? `Payment for order #${orderId.substring(0, 6)} was verified.` : `Payment for order #${orderId.substring(0, 6)} was rejected. Check the note and submit again.`,
    orderId,
    eventKey: `payment_${decision}`,
  });
  return { success: true, status: decision === 'approve' ? 'paid' : 'payment_rejected' };
});

exports.reviewManualRefund = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const orderId = safeText(request.data?.orderId, 128);
  const decision = safeText(request.data?.decision, 16);
  const note = safeText(request.data?.note, 300);
  if (!orderId || !['complete', 'reject'].includes(decision)) {
    throw new HttpsError('invalid-argument', 'Order and complete/reject decision are required.');
  }
  const refundRef = db.collection('refund_requests').doc(orderId);
  const orderRef = db.collection('orders').doc(orderId);
  let refundCustomerId = '';
  await db.runTransaction(async (tx) => {
    const [refundSnap, orderSnap] = await Promise.all([tx.get(refundRef), tx.get(orderRef)]);
    if (!refundSnap.exists || !orderSnap.exists) throw new HttpsError('not-found', 'Refund request not found.');
    const refund = refundSnap.data() || {};
    const order = orderSnap.data() || {};
    refundCustomerId = String(order.customerId || '');
    if (!['pending_manual_refund_review', 'pending'].includes(refund.status) || order.paymentStatus !== 'paid') {
      throw new HttpsError('failed-precondition', 'This refund is not awaiting manual review.');
    }
    const completed = decision === 'complete';
    tx.update(refundRef, {
      status: completed ? 'refund_completed' : 'refund_rejected',
      reviewNote: note,
      reviewedBy: request.auth.uid,
      reviewedAt: FieldValue.serverTimestamp(),
    });
    tx.update(orderRef, {
      refundStatus: completed ? 'completed' : 'rejected',
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: completed ? 'manual_refund_completed' : 'manual_refund_rejected',
      targetType: 'order',
      targetId: orderId,
      note,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  await notifyUser({
    recipientId: refundCustomerId,
    title: decision === 'complete' ? 'Refund marked completed' : 'Refund request rejected',
    body: decision === 'complete' ? `Your refund for order #${orderId.substring(0, 6)} was marked completed.` : `Your refund request for order #${orderId.substring(0, 6)} was rejected.`,
    orderId,
    eventKey: `refund_${decision}`,
  });
  return { success: true, status: decision === 'complete' ? 'refund_completed' : 'refund_rejected' };
});

exports.adminAssignRiderSecure = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  await requireRole(request.auth.uid, 'admin');
  const orderId = safeText(request.data?.orderId, 128);
  const riderId = safeText(request.data?.riderId, 128);
  if (!orderId || !riderId) throw new HttpsError('invalid-argument', 'Order and approved rider are required.');
  const orderRef = db.collection('orders').doc(orderId);
  const riderRef = db.collection('users').doc(riderId);
  const locationRef = db.collection('rider_locations').doc(riderId);
  await db.runTransaction(async (tx) => {
    const [orderSnap, riderSnap, locationSnap] = await Promise.all([tx.get(orderRef), tx.get(riderRef), tx.get(locationRef)]);
    if (!orderSnap.exists) throw new HttpsError('not-found', 'Order not found.');
    if (!riderSnap.exists || riderSnap.data()?.role !== 'rider' || riderSnap.data()?.riderApproved === false) {
      throw new HttpsError('failed-precondition', 'Selected rider is not approved or is suspended.');
    }
    const order = orderSnap.data() || {};
    if (order.status !== 'ready' || (order.riderId && order.riderId !== '')) {
      throw new HttpsError('failed-precondition', 'Only ready and unassigned orders can be assigned.');
    }
    if (order.paymentMethod !== 'cash_on_delivery' && order.paymentStatus !== 'paid') {
      throw new HttpsError('failed-precondition', 'The customer payment has not been verified yet.');
    }
    const visibleToCustomerIds = Array.isArray(locationSnap.data()?.visibleToCustomerIds)
      ? locationSnap.data().visibleToCustomerIds.map(String) : [];
    if (order.customerId) visibleToCustomerIds.push(String(order.customerId));
    tx.update(orderRef, {
      riderId,
      riderAssignedBy: request.auth.uid,
      riderAssignedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(locationRef, {
      visibleToCustomerIds: [...new Set(visibleToCustomerIds)].slice(0, 20),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.create(db.collection('admin_audit_logs').doc(), {
      actorId: request.auth.uid,
      action: 'rider_assigned_by_admin',
      targetType: 'order',
      targetId: orderId,
      note: `Assigned rider ${riderId}`,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true, orderId, riderId };
});

exports.assignRiderSecure = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  const riderId = request.auth.uid;
  await requireActiveRider(riderId);
  const orderId = safeText(request.data?.orderId, 128);
  if (!orderId) throw new HttpsError('invalid-argument', 'Order ID is required.');
  const orderRef = db.collection('orders').doc(orderId);
  const locationRef = db.collection('rider_locations').doc(riderId);
  await db.runTransaction(async (tx) => {
    const [snap, locationSnap] = await Promise.all([tx.get(orderRef), tx.get(locationRef)]);
    if (!snap.exists) throw new HttpsError('not-found', 'Order not found.');
    const order = snap.data() || {};
    if (!canAssignOrder(order, riderId)) {
      if (order.paymentMethod !== 'cash_on_delivery' && order.paymentStatus !== 'paid') {
        throw new HttpsError('failed-precondition', 'The customer payment has not been verified yet.');
      }
      throw new HttpsError('aborted', 'This order has already been assigned or is no longer available.');
    }
    const visibleToCustomerIds = Array.isArray(locationSnap.data()?.visibleToCustomerIds)
      ? locationSnap.data().visibleToCustomerIds.map(String) : [];
    if (order.customerId) visibleToCustomerIds.push(String(order.customerId));
    tx.update(orderRef, { riderId, updatedAt: FieldValue.serverTimestamp() });
    tx.set(locationRef, {
      visibleToCustomerIds: [...new Set(visibleToCustomerIds)].slice(0, 20),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { success: true, orderId, riderId };
});

exports.completeDeliveryWithOtp = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  const riderId = request.auth.uid;
  await requireActiveRider(riderId);
  const orderId = safeText(request.data?.orderId, 128);
  const code = safeText(request.data?.code, 6);
  if (!orderId || !/^\d{6}$/.test(code)) throw new HttpsError('invalid-argument', 'A six-digit delivery OTP is required.');
  const orderRef = db.collection('orders').doc(orderId);
  const secretRef = db.collection('delivery_otp_secrets').doc(orderId);
  let otpWasIncorrect = false;
  await db.runTransaction(async (tx) => {
    const [snap, secretSnap] = await Promise.all([tx.get(orderRef), tx.get(secretRef)]);
    if (!snap.exists || !secretSnap.exists) throw new HttpsError('not-found', 'Order delivery verification record not found.');
    const order = snap.data() || {};
    const secret = secretSnap.data() || {};
    if (order.riderId !== riderId || order.status !== 'on_the_way') {
      throw new HttpsError('permission-denied', 'Only the assigned rider can complete an order that is on the way.');
    }
    const attempts = Number(secret.attempts || 0);
    if (attempts >= 5) throw new HttpsError('resource-exhausted', 'Delivery OTP is locked after five incorrect attempts. Contact support.');
    const createdAt = order.createdAt && typeof order.createdAt.toDate === 'function' ? order.createdAt.toDate().getTime() : 0;
    if (createdAt && Date.now() - createdAt > 24 * 60 * 60 * 1000) {
      throw new HttpsError('deadline-exceeded', 'Delivery OTP expired. Contact support.');
    }
    if (!verifyDeliveryOtp(code, secret.codeHash)) {
      tx.update(secretRef, { attempts: attempts + 1, updatedAt: FieldValue.serverTimestamp() });
      otpWasIncorrect = true;
      return;
    }
    tx.update(orderRef, {
      status: 'delivered',
      deliveredAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.delete(secretRef);
  });
  if (otpWasIncorrect) throw new HttpsError('permission-denied', 'Delivery OTP is incorrect.');
  await refreshRiderLocationVisibility(riderId);
  return { success: true, orderId, status: 'delivered' };
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

  // A customer may cancel only while the order is still placed. Restore any
  // finite stock exactly once when that reservation is cancelled.
  if (before.status === 'placed' && after.status === 'cancelled') {
    const quantities = new Map();
    for (const item of (before.items || [])) {
      const productId = safeText(item.productId, 128);
      const qty = Number(item.qty);
      if (productId && Number.isInteger(qty) && qty > 0) {
        quantities.set(productId, (quantities.get(productId) || 0) + qty);
      }
    }
    const markerRef = db.collection('inventory_restocks').doc(orderId);
    const refs = [...quantities.keys()].map((id) => db.collection('products').doc(id));
    await db.runTransaction(async (tx) => {
      const marker = await tx.get(markerRef);
      if (marker.exists) return;
      const products = await Promise.all(refs.map((ref) => tx.get(ref)));
      for (const productSnap of products) {
        if (!productSnap.exists) continue;
        const product = productSnap.data() || {};
        if (Number.isInteger(product.stockQty) && product.stockQty >= 0) {
          tx.update(productSnap.ref, {
            stockQty: product.stockQty + (quantities.get(productSnap.id) || 0),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      }
      tx.create(markerRef, {
        orderId,
        restoredAt: FieldValue.serverTimestamp(),
      });
    });
  }
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

  if (statusChanged && after.riderId && ['delivered', 'cancelled'].includes(after.status)) {
    try {
      await refreshRiderLocationVisibility(after.riderId);
    } catch (error) {
      logger.warn('Could not refresh rider location visibility after order closure.', { orderId, riderId: after.riderId, error: String(error) });
    }
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

  if (before.status !== 'cancelled' && after.status === 'cancelled' && after.paymentMethod !== 'cash_on_delivery' && before.paymentStatus === 'paid') {
    await db.collection('refund_requests').doc(orderId).set({
      orderId,
      customerId: after.customerId,
      amount: money(after.total),
      reason: after.cancellationReason || 'Customer cancellation',
      status: 'pending_manual_refund_review',
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
});
