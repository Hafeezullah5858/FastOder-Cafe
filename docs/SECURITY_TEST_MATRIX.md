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
