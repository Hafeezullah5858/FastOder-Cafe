const fs = require('node:fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, getDoc, updateDoc, deleteDoc,
} = require('firebase/firestore');

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-fastoder-rules',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync('firestore.rules', 'utf8'),
    },
  });

  let failures = 0;
  const checks = [];

  const check = (name, operation) => checks.push([name, operation]);

  try {
    await env.clearFirestore();

    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();

      const users = [
        ['vendorA', { uid: 'vendorA', role: 'vendor' }],
        ['vendorB', { uid: 'vendorB', role: 'vendor' }],
        ['customer1', { uid: 'customer1', role: 'customer', name: 'Customer One', email: 'customer@example.test' }],
        ['customer2', { uid: 'customer2', role: 'customer', name: 'Customer Two', email: 'customer2@example.test' }],
        ['chefApproved', {
          uid: 'chefApproved', role: 'home_chef', sellerApproved: true,
        }],
        ['chefPending', {
          uid: 'chefPending', role: 'home_chef', sellerApproved: false,
        }],
        ['admin1', { uid: 'admin1', role: 'admin' }],
        ['rider1', { uid: 'rider1', role: 'rider', riderApproved: true }],
        ['riderSuspended', { uid: 'riderSuspended', role: 'rider', riderApproved: false }],
      ];

      for (const [uid, data] of users) {
        await setDoc(doc(db, 'users', uid), data);
      }

      const product = (vendorId, vendorType = 'restaurant') => ({
        vendorId,
        vendorType,
        foodCategory: vendorType === 'home_chef' ? 'home_made' : 'restaurant',
        menuCategory: 'Other',
        stockQty: -1,
        name: 'Test food',
        price: 100,
        active: true,
        imageUrl: '',
      });

      await setDoc(doc(db, 'products/productA'), product('vendorA'));
      await setDoc(doc(db, 'products/productB'), product('vendorB'));
      await setDoc(doc(db, 'orders/manualUnpaid'), {
        customerId: 'customer1', vendorId: 'vendorA', riderId: '', status: 'placed',
        items: [], total: 100, subtotal: 100, deliveryFee: 0, platformFee: 0,
        commission: 0, commissionRate: 0.1, sellerPayout: 100, discount: 0,
        couponCode: '', address: 'Test address', paymentMethod: 'jazzcash_manual',
        paymentStatus: 'awaiting_payment', refundStatus: 'not_applicable',
        cancellationReason: '', deliveryLat: null, deliveryLng: null,
      });
      await setDoc(doc(db, 'orders/readyCOD'), {
        customerId: 'customer1', vendorId: 'vendorA', riderId: '', status: 'ready',
        items: [], total: 100, subtotal: 100, deliveryFee: 0, platformFee: 0,
        commission: 0, commissionRate: 0.1, sellerPayout: 100, discount: 0,
        couponCode: '', address: 'Test address', paymentMethod: 'cash_on_delivery',
        paymentStatus: 'pending_cash', refundStatus: 'not_applicable',
        cancellationReason: '', deliveryLat: null, deliveryLng: null,
      });
      await setDoc(doc(db, 'rider_locations/rider1'), {
        lat: 31.5204, lng: 74.3587, visibleToCustomerIds: ['customer1'],
      });
    });

    const vendor = env.authenticatedContext('vendorA').firestore();
    const customer = env.authenticatedContext('customer1').firestore();
    const otherCustomer = env.authenticatedContext('customer2').firestore();
    const approvedChef = env.authenticatedContext('chefApproved').firestore();
    const pendingChef = env.authenticatedContext('chefPending').firestore();
    const admin = env.authenticatedContext('admin1').firestore();
    const rider = env.authenticatedContext('rider1').firestore();
    const suspendedRider = env.authenticatedContext('riderSuspended').firestore();

    check('Vendor can read own user role', () =>
      assertSucceeds(getDoc(doc(vendor, 'users/vendorA'))));

    check('Admin cannot directly edit a user role in Firestore', () =>
      assertFails(updateDoc(doc(admin, 'users/customer1'), { role: 'rider', riderApproved: true })));

    check('Public can read products', () =>
      assertSucceeds(getDoc(doc(customer, 'products/productA'))));

    check('Vendor can create valid own product', () =>
      assertSucceeds(setDoc(doc(vendor, 'products/newProduct'), {
        vendorId: 'vendorA',
        vendorType: 'restaurant',
        foodCategory: 'restaurant',
        menuCategory: 'Pizza',
        stockQty: 10,
        name: 'New food',
        price: 120,
        active: true,
        imageUrl: '',
      })));

    check('Vendor can edit own product fields', () =>
      assertSucceeds(updateDoc(doc(vendor, 'products/productA'), {
        name: 'Updated food',
        price: 125,
      })));

    check('Vendor cannot set a negative price', () =>
      assertFails(updateDoc(doc(vendor, 'products/productA'), {
        price: -10,
      })));

    check('Vendor cannot transfer product ownership', () =>
      assertFails(updateDoc(doc(vendor, 'products/productA'), {
        vendorId: 'vendorB',
      })));

    check('Vendor cannot update another vendor product', () =>
      assertFails(updateDoc(doc(vendor, 'products/productB'), {
        name: 'Unauthorized edit',
      })));

    check('Vendor cannot delete another vendor product', () =>
      assertFails(deleteDoc(doc(vendor, 'products/productB'))));

    check('Vendor can delete own product', () =>
      assertSucceeds(deleteDoc(doc(vendor, 'products/productA'))));

    check('Customer cannot create a product', () =>
      assertFails(setDoc(doc(customer, 'products/customerProduct'), {
        vendorId: 'customer1',
        vendorType: 'restaurant',
        foodCategory: 'restaurant',
        name: 'Invalid seller product',
        price: 10,
        active: true,
        imageUrl: '',
      })));

    check('Approved Home Chef can create a product', () =>
      assertSucceeds(setDoc(doc(approvedChef, 'products/chefProduct'), {
        vendorId: 'chefApproved',
        vendorType: 'home_chef',
        foodCategory: 'home_made',
        menuCategory: 'Other',
        stockQty: -1,
        name: 'Home food',
        price: 250,
        active: true,
        imageUrl: '',
      })));

    check('Unapproved Home Chef cannot create a product', () =>
      assertFails(setDoc(doc(pendingChef, 'products/pendingChefProduct'), {
        vendorId: 'chefPending',
        vendorType: 'home_chef',
        foodCategory: 'home_made',
        menuCategory: 'Other',
        stockQty: -1,
        name: 'Pending chef food',
        price: 250,
        active: true,
        imageUrl: '',
      })));

    check('Customer can submit own Home Chef application', () =>
      assertSucceeds(setDoc(doc(customer, 'home_chef_applications/customer1'), {
        userId: 'customer1',
        businessName: 'Test Kitchen',
        description: 'I prepare homemade meals for customers.',
        phone: '03000000000',
        status: 'pending',
      })));

    check('Customer cannot submit an application for another user', () =>
      assertFails(setDoc(doc(customer, 'home_chef_applications/vendorB'), {
        userId: 'vendorB',
        businessName: 'Other Kitchen',
        description: 'This is not my account application.',
        phone: '03000000000',
        status: 'pending',
      })));

    check('Applicant can read own application', () =>
      assertSucceeds(getDoc(doc(customer, 'home_chef_applications/customer1'))));

    check('Admin can read an application', () =>
      assertSucceeds(getDoc(doc(admin, 'home_chef_applications/customer1'))));

    check('Different user cannot read private application', () =>
      assertFails(getDoc(doc(vendor, 'home_chef_applications/customer1'))));

    check('Customer can submit a vendor application for self', () =>
      assertSucceeds(setDoc(doc(customer, 'vendor_applications/customer1'), {
        userId: 'customer1', applicantName: 'Customer One', email: 'customer@example.test',
        name: 'Customer Cafe', phone: '03000000000', area: 'Lahore',
        details: 'A restaurant serving fresh meals every day.', status: 'pending',
      })));

    check('Customer can submit a rider application for self', () =>
      assertSucceeds(setDoc(doc(customer, 'rider_applications/customer1'), {
        userId: 'customer1', applicantName: 'Customer One', email: 'customer@example.test',
        name: 'Customer One', phone: '03000000000', area: 'Lahore',
        details: 'Available for evening and weekend deliveries.', vehicleType: 'Motorbike',
        vehicleRegistration: 'ABC-123', status: 'pending',
      })));

    check('Customer cannot self-approve a vendor application', () =>
      assertFails(setDoc(doc(customer, 'vendor_applications/customer2'), {
        userId: 'customer2', name: 'Fake Vendor', phone: '03000000000', area: 'Lahore',
        details: 'Trying to approve my own account.', status: 'approved',
      })));

    check('Admin can read pending vendor and rider applications', async () => {
      await getDoc(doc(admin, 'vendor_applications/customer1'));
      await getDoc(doc(admin, 'rider_applications/customer1'));
    });

    check('Vendor can create store settings for self', () =>
      assertSucceeds(setDoc(doc(vendor, 'vendor_settings/vendorA'), {
        vendorId: 'vendorA', isOpen: true, openingTime: '09:00', closingTime: '23:00',
      })));

    check('Vendor cannot change another seller store settings', () =>
      assertFails(setDoc(doc(vendor, 'vendor_settings/vendorB'), {
        vendorId: 'vendorB', isOpen: false, openingTime: '09:00', closingTime: '23:00',
      })));

    check('Customer cannot change public payment account settings', () =>
      assertFails(setDoc(doc(customer, 'app_settings/payment_methods'), { jazzcash: { enabled: true } })));

    check('Admin can configure manual payment accounts', () =>
      assertSucceeds(setDoc(doc(admin, 'app_settings/payment_methods'), { jazzcash: { enabled: true, accountNumber: '03000000000' } })));

    check('Customer cannot create payment records directly', () =>
      assertFails(setDoc(doc(customer, 'payments/manualUnpaid'), { customerId: 'customer1', status: 'paid' })));

    check('Rider cannot directly assign a ready order to self', () =>
      assertFails(updateDoc(doc(rider, 'orders/readyCOD'), { riderId: 'rider1', status: 'picked_up' })));

    check('Customer assigned to a rider can read that rider live location', () =>
      assertSucceeds(getDoc(doc(customer, 'rider_locations/rider1'))));

    check('Unrelated customer cannot read another customer rider location', () =>
      assertFails(getDoc(doc(otherCustomer, 'rider_locations/rider1'))));

    check('Approved rider can update own GPS location and visibility list', () =>
      assertSucceeds(updateDoc(doc(rider, 'rider_locations/rider1'), {
        lat: 31.521, lng: 74.359, visibleToCustomerIds: ['customer1'],
      })));

    check('Suspended rider cannot publish live location', () =>
      assertFails(setDoc(doc(suspendedRider, 'rider_locations/riderSuspended'), {
        lat: 31.52, lng: 74.35, visibleToCustomerIds: ['customer1'],
      })));

    check('Vendor cannot accept an unpaid manual payment order', () =>
      assertFails(updateDoc(doc(vendor, 'orders/manualUnpaid'), { status: 'accepted' })));

    check('Customer cannot read another user delivery OTP', () =>
      assertFails(getDoc(doc(vendor, 'delivery_otps/orderOwnedByCustomer'))));

    check('Customer cannot write support tickets directly', () =>
      assertFails(setDoc(doc(customer, 'support_tickets/ticket1'), { customerId: 'customer1', message: 'Hi there this is a test' })));

    for (const [name, operation] of checks) {
      try {
        await operation();
        console.log(`PASS: ${name}`);
      } catch (e) {
        failures++;
        console.error(`FAIL: ${name}: ${e.message}`);
      }
    }

    console.log(`RESULT: ${checks.length - failures}/${checks.length} passed`);
    if (failures) process.exitCode = 1;
  } finally {
    await env.cleanup();
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
