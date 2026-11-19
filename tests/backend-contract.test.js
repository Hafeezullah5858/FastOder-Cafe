const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const policy = require('../functions/payment_policy');

const root = path.resolve(__dirname, '..');

test('supports only COD and the three manual transfer methods', () => {
  for (const method of ['cash_on_delivery', 'jazzcash_manual', 'easypaisa_manual', 'bank_transfer_manual']) {
    assert.equal(policy.isSupportedPaymentMethod(method), true);
  }
  for (const method of ['card', 'stripe', 'jazzcash', 'easypaisa', '']) {
    assert.equal(policy.isSupportedPaymentMethod(method), false);
  }
});

test('manual payment options require admin-configured account details', () => {
  assert.equal(policy.isManualAccountConfigured('jazzcash_manual', { jazzcash: { enabled: true, accountNumber: '03001234567' } }), true);
  assert.equal(policy.isManualAccountConfigured('easypaisa_manual', { easypaisa: { enabled: true, accountNumber: '' } }), false);
  assert.equal(policy.isManualAccountConfigured('bank_transfer_manual', { bank_transfer: { enabled: true, iban: 'PK00TEST' } }), true);
  assert.equal(policy.isManualAccountConfigured('cash_on_delivery', {}), false);
  assert.deepEqual(policy.manualAccountSnapshot('bank_transfer_manual', { bank_transfer: { enabled: true, bankName: 'Example Bank', accountTitle: 'FastOder', iban: 'PK00TEST' } }), { provider: 'bank_transfer', accountTitle: 'FastOder', accountNumber: '', bankName: 'Example Bank', iban: 'PK00TEST' });
});

test('manual transfers remain unpaid until admin verification', () => {
  assert.equal(policy.initialPaymentStatus('cash_on_delivery'), 'pending_cash');
  assert.equal(policy.initialPaymentStatus('jazzcash_manual'), 'awaiting_payment');
  assert.equal(policy.initialPaymentStatus('easypaisa_manual'), 'awaiting_payment');
  assert.equal(policy.initialPaymentStatus('bank_transfer_manual'), 'awaiting_payment');
  assert.throws(() => policy.initialPaymentStatus('card'));
});

test('vendors and riders cannot process unpaid manual orders', () => {
  assert.equal(policy.canSellerProcessOrder({ paymentMethod: 'cash_on_delivery', paymentStatus: 'pending_cash' }), true);
  assert.equal(policy.canSellerProcessOrder({ paymentMethod: 'jazzcash_manual', paymentStatus: 'awaiting_payment' }), false);
  assert.equal(policy.canSellerProcessOrder({ paymentMethod: 'jazzcash_manual', paymentStatus: 'paid' }), true);
  assert.equal(policy.canAssignOrder({ status: 'ready', riderId: '', paymentMethod: 'bank_transfer_manual', paymentStatus: 'awaiting_payment' }, 'r1'), false);
  assert.equal(policy.canAssignOrder({ status: 'ready', riderId: '', paymentMethod: 'bank_transfer_manual', paymentStatus: 'paid' }, 'r1'), true);
});

test('delivery OTP is six digits, hashed and compared safely', () => {
  const hash = policy.hashDeliveryOtp('042861');
  assert.equal(policy.verifyDeliveryOtp('042861', hash), true);
  assert.equal(policy.verifyDeliveryOtp('042862', hash), false);
  assert.equal(policy.verifyDeliveryOtp('12345', hash), false);
  assert.throws(() => policy.hashDeliveryOtp('abc123'));
});

test('admin role assignment cannot grant admin from the ordinary people menu', () => {
  for (const role of ['customer', 'vendor', 'home_chef', 'rider']) assert.equal(policy.isAssignableRole(role), true);
  assert.equal(policy.isAssignableRole('admin'), false);
});

test('seller payout balance subtracts paid and reserved requests', () => {
  assert.equal(policy.availablePayoutBalance([{ sellerPayout: 1000 }], [{ status: 'paid', amount: 200 }], 300), 500);
  assert.equal(policy.availablePayoutBalance([{ sellerPayout: 100 }], [], 150), 0);
});

test('stock-limited products cannot oversell; -1 and legacy missing stock remain unlimited', () => {
  assert.equal(policy.hasAvailableStock(3, 2), true);
  assert.equal(policy.hasAvailableStock(1, 2), false);
  assert.equal(policy.hasAvailableStock(0, 1), false);
  assert.equal(policy.hasAvailableStock(-1, 100), true);
  assert.equal(policy.hasAvailableStock(null, 100), true);
  assert.equal(policy.hasAvailableStock(-2, 1), false);
});

test('proof uploads are constrained to the authenticated customer/order folder', () => {
  assert.equal(policy.isValidProofPath('payment_proofs/u1/o1/receipt.jpg', 'u1', 'o1'), true);
  assert.equal(policy.isValidProofPath('payment_proofs/u2/o1/receipt.jpg', 'u1', 'o1'), false);
  assert.equal(policy.isValidProofPath('payment_proofs/u1/o2/receipt.jpg', 'u1', 'o1'), false);
  assert.equal(policy.isValidProofPath('payment_proofs/u1/o1/receipt.pdf', 'u1', 'o1'), false);
});

test('Firestore rules gate vendor progress on verified manual payment', () => {
  const rules = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  assert.match(rules, /resource\.data\.paymentMethod == 'cash_on_delivery' \|\| resource\.data\.paymentStatus == 'paid'/);
  assert.match(rules, /resource\.data\.riderId == request\.auth\.uid && request\.resource\.data\.status == 'picked_up'/);
  assert.match(rules, /allow update, delete: if false;/);
  assert.match(rules, /match \/app_settings\/{settingId}/);
  assert.match(rules, /match \/seller_earnings\/{earningId}/);
  assert.match(rules, /match \/delivery_otps\/{orderId}/);
  assert.match(rules, /match \/delivery_otp_secrets\/{orderId}/);
  const functions = fs.readFileSync(path.join(root, 'functions/index.js'), 'utf8');
  assert.doesNotMatch(functions, /deliveryOtpHash,\s*refundStatus/);
  assert.match(functions, /delivery_otp_secrets/);
  assert.match(rules, /match \/vendor_settings\/{vendorId}/);
  assert.match(rules, /match \/support_tickets\/{ticketId}/);
  assert.match(rules, /match \/payout_requests\/{requestId}/);
  assert.match(rules, /match \/seller_payout_balances\/{sellerId}/);
  assert.match(rules, /resource\.data\.customerId == request\.auth\.uid/);
});

test('trusted backend endpoints exist for payments, refunds, delivery, roles, support and payouts', () => {
  const source = fs.readFileSync(path.join(root, 'functions/index.js'), 'utf8');
  for (const endpoint of ['submitManualPaymentProof', 'reviewManualPayment', 'reviewManualRefund', 'adminCancelOrder', 'assignRiderSecure', 'completeDeliveryWithOtp', 'setUserRole', 'reviewHomeChef', 'reviewHomeChefApplication', 'savePaymentSettings', 'createSupportTicket', 'reviewSupportTicket', 'requestSellerPayout', 'reviewSellerPayout']) {
    assert.match(source, new RegExp('exports\\.' + endpoint + '\\s*=\\s*onCall'));
  }
  assert.match(source, /inventory_restocks/);
});

test('Storage rules restrict payment proof uploads to owner and image files', () => {
  const rules = fs.readFileSync(path.join(root, 'storage.rules'), 'utf8');
  assert.match(rules, /payment_proofs\/{uid}\/{orderId}\/{fileName}/);
  assert.match(rules, /request\.resource\.size < 5 \* 1024 \* 1024/);
  assert.match(rules, /resource == null/);
  assert.match(rules, /paymentStatus in \['awaiting_payment', 'payment_rejected'\]/);
  assert.match(rules, /image\/\(jpeg\|png\|webp\)/);
});

test('vendor and rider access can only be granted by reviewing a pending application', () => {
  const functions = fs.readFileSync(path.join(root, 'functions/index.js'), 'utf8');
  const rules = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const appService = fs.readFileSync(path.join(root, 'lib/services/business_application_service.dart'), 'utf8');
  const main = fs.readFileSync(path.join(root, 'lib/main.dart'), 'utf8');
  assert.match(functions, /exports\.reviewBusinessApplication\s*=\s*onCall/);
  assert.match(functions, /role !== 'customer'/);
  assert.match(functions, /status: 'suspended'/);
  assert.match(functions, /where\('status', 'in', activeStatuses\)/);
  assert.match(functions, /if \(!activeOrders\.empty\)/);
  assert.match(functions, /application\.status !== 'pending'/);
  assert.match(functions, /vendorApproved: true/);
  assert.match(functions, /riderApproved: true/);
  assert.match(rules, /match \/vendor_applications\/{uid}/);
  assert.match(rules, /match \/rider_applications\/{uid}/);
  assert.match(appService, /reviewBusinessApplication/);
  assert.match(main, /AdminBusinessApplicationsTab\(type: 'vendor'\)/);
  assert.match(main, /AdminBusinessApplicationsTab\(type: 'rider'\)/);
  assert.match(main, /BusinessApplicationPage\(type: 'vendor'\)/);
  assert.match(main, /BusinessApplicationPage\(type: 'rider'\)/);
});

test('admin rider assignment is server-authoritative and restricted to approved riders and ready unpaid-safe orders', () => {
  const functions = fs.readFileSync(path.join(root, 'functions/index.js'), 'utf8');
  const adminService = fs.readFileSync(path.join(root, 'lib/services/admin_service.dart'), 'utf8');
  const main = fs.readFileSync(path.join(root, 'lib/main.dart'), 'utf8');
  assert.match(functions, /exports\.adminAssignRiderSecure\s*=\s*onCall/);
  assert.match(functions, /await requireRole\(request\.auth\.uid, 'admin'\)/);
  assert.match(functions, /riderSnap\.data\(\)\?\.riderApproved === false/);
  assert.match(functions, /visibleToCustomerIds: \[\.\.\.new Set\(visibleToCustomerIds\)\]/);
  assert.match(functions, /order\.status !== 'ready'/);
  assert.match(functions, /order\.paymentStatus !== 'paid'/);
  assert.match(adminService, /adminAssignRiderSecure/);
  assert.match(main, /class AdminDeliveryTab/);
});

test('customer live tracking is authorized only for customers assigned to the rider location', () => {
  const rules = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
  const locationService = fs.readFileSync(path.join(root, 'lib/services/location_service.dart'), 'utf8');
  const trackingPage = fs.readFileSync(path.join(root, 'lib/screens/order_tracking_page.dart'), 'utf8');
  assert.match(rules, /resource\.data\.visibleToCustomerIds\.hasAny\(\[request\.auth\.uid\]\)/);
  assert.match(rules, /request\.resource\.data\.visibleToCustomerIds is list/);
  assert.match(locationService, /syncRiderLocationVisibility/);
  assert.match(locationService, /visibleToCustomerIds/);
  assert.match(trackingPage, /\.collection\('orders'\)/);
  assert.match(trackingPage, /_watchRider\(next\.riderId\)/);
});
