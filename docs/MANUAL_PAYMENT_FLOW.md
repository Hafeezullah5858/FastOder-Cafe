# FastOder Cafe — Manual Payment Flow

## Supported methods
- Cash on Delivery (`cash_on_delivery`) remains available.
- JazzCash manual transfer (`jazzcash_manual`).
- Easypaisa manual transfer (`easypaisa_manual`).
- Bank transfer (`bank_transfer_manual`).

No online payment gateway, card charging, card-number collection, or automatic payment confirmation is implemented.

## Admin setup
1. Sign in with an account whose Firestore `users/{uid}.role` is `admin`.
2. Open Super Admin Dashboard → Payment Setup.
3. Enter the account title and receiving number for JazzCash and Easypaisa. For Bank Transfer enter the bank name, account title, account number and/or IBAN.
4. Save. A method is shown at checkout only when its account is enabled and has a destination number/IBAN.

## Customer flow
1. Select one of the configured manual methods at checkout and place the order.
2. Open Orders and choose Submit payment receipt for the new unpaid manual-payment order.
3. Transfer the exact order amount using the displayed account details.
4. Enter the transaction reference and upload a JPG, PNG or WEBP receipt image smaller than 5 MB.
5. The payment remains `pending_verification`; it is not automatically marked paid.

## Admin verification
1. Open Super Admin Dashboard → Payments.
2. Compare the transaction reference and receipt against the actual receiving wallet/bank account.
3. Approve only after confirming receipt of the exact amount, or reject with a reason.
4. Approval changes the payment and order status to `paid`; rejection changes it to `payment_rejected` so the customer can submit a corrected receipt.

## Server and security controls
- Orders and payment records are created by `createOrderSecure` using server-side product prices.
- Order and payment record creation uses a Firestore transaction.
- Proof uploads are limited to the order owner, the matching order ID and image MIME types under 5 MB.
- `submitManualPaymentProof`, `reviewManualPayment`, `reviewManualRefund` and `assignRiderSecure` are callable Cloud Functions in `asia-south1`.
- Vendors cannot accept or advance a manual-payment order until payment status is `paid`.
- Riders cannot claim or progress an unpaid manual-payment order. Rider assignment is atomic to prevent two riders claiming the same order.
- Admin payment/refund decisions write server-side audit records.

## Release caveat
This document describes source implementation only. Flutter/Dart SDK and Firebase CLI are not present in the current build environment, so Flutter analyze/build, Firebase Emulator rule tests and real-device end-to-end verification have not yet been performed. Do not deploy these rules/functions to the live Firebase project until those tests and a reviewed backup are complete.

## Delivery confirmation and stock controls
- Every order receives a random six-digit delivery OTP. Only the customer can read the OTP document; riders cannot read it.
- The assigned rider can mark an order delivered only by submitting the customer's OTP to `completeDeliveryWithOtp`. The code expires after 24 hours and locks after five incorrect attempts.
- Vendors can set a manual open/closed switch and opening/closing information in Store Settings. The open/closed switch is enforced server-side when a new order is created.
- Vendors can set finite stock quantities per product; `-1` means unlimited. Stock is decremented in the same Firestore transaction that creates the order and restored once if the customer cancels while the order is still `placed`.

## Customer support
- Customers can create a support/complaint ticket with an optional order ID. The server checks that any supplied order belongs to the signed-in customer.
- Admin can move tickets to in-progress, resolved or closed and reply; customers see their own ticket status and reply.
