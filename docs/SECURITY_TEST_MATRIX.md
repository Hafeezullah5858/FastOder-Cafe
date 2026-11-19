# Security Test Matrix

| Area | Test | Expected |
|---|---|---|
| Users | Customer attempts to set role=admin/vendor | Denied |
| Products | Seller edits another seller's product | Denied |
| Orders | Customer changes total/subtotal/commission | Denied |
| Orders | Rider changes order belonging to another rider | Denied |
| Reviews | User reviews undelivered order | Denied |
| Payments | Payment amount exceeds order total | Denied |
| Notifications | Customer creates notification for another user | Denied |
| Storage | Unapproved Home Chef uploads food image | Denied |
| Addresses | User reads another user's address | Denied |
| Refunds | User requests refund for another user's order | Denied |
| Applications | Customer submits own vendor/rider application | Allowed only for own customer account |
| Applications | Customer self-approves vendor/rider application | Denied |
| Applications | Admin approves pending vendor/rider application | Trusted callable only; role and approval flag updated atomically |
| Roles | Admin tries to grant vendor/rider through generic role setter | Denied; must approve application |
| Rider assignment | Two riders claim same ready order concurrently | Exactly one assignment succeeds |
| Rider assignment | Admin assigns an unapproved/suspended rider | Denied |
| Rider assignment | Admin assigns an unpaid manual-payment order | Denied |
| Rider tracking | Customer reads location of rider assigned to their active order | Allowed |
| Rider tracking | Unrelated customer reads another rider's location | Denied |
| Rider tracking | Suspended rider publishes location | Denied |
| Delivery | Rider marks order delivered without customer OTP | Denied |
