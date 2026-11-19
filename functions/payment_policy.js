const crypto = require('node:crypto');

const SUPPORTED_PAYMENT_METHODS = new Set([
  'cash_on_delivery',
  'jazzcash_manual',
  'easypaisa_manual',
  'bank_transfer_manual',
]);
const MANUAL_PAYMENT_METHODS = new Set([
  'jazzcash_manual',
  'easypaisa_manual',
  'bank_transfer_manual',
]);

function isSupportedPaymentMethod(method) {
  return SUPPORTED_PAYMENT_METHODS.has(String(method || ''));
}

function isManualPaymentMethod(method) {
  return MANUAL_PAYMENT_METHODS.has(String(method || ''));
}

function isManualAccountConfigured(method, settings) {
  const key = method === 'jazzcash_manual' ? 'jazzcash' :
    method === 'easypaisa_manual' ? 'easypaisa' :
    method === 'bank_transfer_manual' ? 'bank_transfer' : '';
  if (!key) return false;
  const account = settings && settings[key] && typeof settings[key] === 'object' ? settings[key] : {};
  return account.enabled === true && Boolean(String(account.accountNumber || account.iban || '').trim());
}

function manualAccountSnapshot(method, settings) {
  const key = method === 'jazzcash_manual' ? 'jazzcash' :
    method === 'easypaisa_manual' ? 'easypaisa' :
    method === 'bank_transfer_manual' ? 'bank_transfer' : '';
  if (!key) return null;
  const account = settings && settings[key] && typeof settings[key] === 'object' ? settings[key] : {};
  if (account.enabled !== true || !String(account.accountNumber || account.iban || '').trim()) return null;
  return {
    provider: key,
    accountTitle: String(account.accountTitle || '').trim(),
    accountNumber: String(account.accountNumber || '').trim(),
    bankName: String(account.bankName || '').trim(),
    iban: String(account.iban || '').trim(),
  };
}

function initialPaymentStatus(method) {
  if (!isSupportedPaymentMethod(method)) throw new Error('Unsupported payment method');
  return method === 'cash_on_delivery' ? 'pending_cash' : 'awaiting_payment';
}

function canSellerProcessOrder(order) {
  return Boolean(order) && (
    order.paymentMethod === 'cash_on_delivery' || order.paymentStatus === 'paid'
  );
}

function hasAvailableStock(stockQty, requestedQty) {
  if (stockQty == null || stockQty === -1) return true;
  return Number.isInteger(stockQty) && stockQty >= 0 &&
    Number.isInteger(requestedQty) && requestedQty > 0 && stockQty >= requestedQty;
}

function hashDeliveryOtp(code) {
  const value = String(code || '');
  if (!/^\d{6}$/.test(value)) throw new Error('Delivery OTP must be six digits');
  return crypto.createHash('sha256').update(value).digest('hex');
}

function verifyDeliveryOtp(code, storedHash) {
  if (!/^\d{6}$/.test(String(code || ''))) return false;
  const expected = Buffer.from(String(storedHash || ''), 'hex');
  const actual = Buffer.from(hashDeliveryOtp(code), 'hex');
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}

function availablePayoutBalance(earnings, payouts, reservedAmount = 0) {
  const earned = (earnings || []).reduce((sum, item) => sum + Math.max(0, Number(item.sellerPayout || 0)), 0);
  const paid = (payouts || []).reduce((sum, item) => sum + (item.status === 'paid' ? Math.max(0, Number(item.amount || 0)) : 0), 0);
  const reserved = Math.max(0, Number(reservedAmount || 0));
  return Math.max(0, earned - paid - reserved);
}

function isAssignableRole(role) {
  return new Set(['customer', 'vendor', 'home_chef', 'rider']).has(String(role || ''));
}

function canAssignOrder(order, riderId) {
  return Boolean(order) && order.status === 'ready' &&
    (!order.riderId || order.riderId === riderId) &&
    (order.paymentMethod === 'cash_on_delivery' || order.paymentStatus === 'paid');
}

function isValidProofPath(path, uid, orderId) {
  const value = String(path || '');
  return value.startsWith(`payment_proofs/${uid}/${orderId}/`) &&
    /\.(jpg|jpeg|png|webp)$/i.test(value);
}

module.exports = {
  SUPPORTED_PAYMENT_METHODS,
  MANUAL_PAYMENT_METHODS,
  isSupportedPaymentMethod,
  isManualPaymentMethod,
  isManualAccountConfigured,
  manualAccountSnapshot,
  initialPaymentStatus,
  canSellerProcessOrder,
  hasAvailableStock,
  hashDeliveryOtp,
  verifyDeliveryOtp,
  isAssignableRole,
  availablePayoutBalance,
  canAssignOrder,
  isValidProofPath,
};
