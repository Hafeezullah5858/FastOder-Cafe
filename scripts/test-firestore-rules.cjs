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
        ['customer1', { uid: 'customer1', role: 'customer' }],
        ['chefApproved', {
          uid: 'chefApproved', role: 'home_chef', sellerApproved: true,
        }],
        ['chefPending', {
          uid: 'chefPending', role: 'home_chef', sellerApproved: false,
        }],
        ['admin1', { uid: 'admin1', role: 'admin' }],
      ];

      for (const [uid, data] of users) {
        await setDoc(doc(db, 'users', uid), data);
      }

      const product = (vendorId, vendorType = 'restaurant') => ({
        vendorId,
        vendorType,
        foodCategory: vendorType === 'home_chef' ? 'home_made' : 'restaurant',
        name: 'Test food',
        price: 100,
        active: true,
        imageUrl: '',
      });

      await setDoc(doc(db, 'products/productA'), product('vendorA'));
      await setDoc(doc(db, 'products/productB'), product('vendorB'));
    });

    const vendor = env.authenticatedContext('vendorA').firestore();
    const customer = env.authenticatedContext('customer1').firestore();
    const approvedChef = env.authenticatedContext('chefApproved').firestore();
    const pendingChef = env.authenticatedContext('chefPending').firestore();
    const admin = env.authenticatedContext('admin1').firestore();

    check('Vendor can read own user role', () =>
      assertSucceeds(getDoc(doc(vendor, 'users/vendorA'))));

    check('Public can read products', () =>
      assertSucceeds(getDoc(doc(customer, 'products/productA'))));

    check('Vendor can create valid own product', () =>
      assertSucceeds(setDoc(doc(vendor, 'products/newProduct'), {
        vendorId: 'vendorA',
        vendorType: 'restaurant',
        foodCategory: 'restaurant',
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
        name: 'Pending chef food',
        price: 250,
        active: true,
        imageUrl: '',
      })));

    check('Customer can submit own Home Chef application', () =>
      assertSucceeds(setDoc(doc(customer, 'home_chef_applications/customer1'), {
        userId: 'customer1',
        status: 'pending',
      })));

    check('Customer cannot submit an application for another user', () =>
      assertFails(setDoc(doc(customer, 'home_chef_applications/vendorB'), {
        userId: 'vendorB',
        status: 'pending',
      })));

    check('Applicant can read own application', () =>
      assertSucceeds(getDoc(doc(customer, 'home_chef_applications/customer1'))));

    check('Admin can read an application', () =>
      assertSucceeds(getDoc(doc(admin, 'home_chef_applications/customer1'))));

    check('Different user cannot read private application', () =>
      assertFails(getDoc(doc(vendor, 'home_chef_applications/customer1'))));

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
