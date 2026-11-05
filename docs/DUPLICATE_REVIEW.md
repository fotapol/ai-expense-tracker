# Duplicate review

Duplicate finder is available to every user under Tools. A saved transaction also
shows a review link when matching purchases are found. Unsaved edits must be saved
before opening its comparison.

The backend compares only the current user's completed receipts and manual or
imported transactions. It uses original amounts and currencies, purchase dates,
normalized merchant names, and item names, amounts, quantities and units. Item
matches preserve repeated lines and exclude adjustments. Adjacent purchase dates
require stronger item evidence; different receipt baskets reduce false positives.
Results include qualitative confidence and reasons rather than a percentage.

The worker computes SHA-256 from downloaded bytes. Only server-verified hashes
can establish an identical-file match. Existing unverified hashes are ignored;
older history can still match through purchase details. No old receipt images are
downloaded automatically. Matching itself makes no additional AI calls. A second
upload still goes through the scan pipeline and uses the existing scan allowance.

Keep both remembers the canonical transaction pair for that user and preserves
both expenses. Keep selected requires a selection and explicit confirmation. It
removes the other transaction, its items, label links, extraction, and receipt
photo; it does not combine fields. Record versions and current matching evidence
are checked again while locking both records. Changed or dismissed comparisons
return HTTP 409 and must be reloaded. Storage cleanup failures preserve database
records. Decisions are removed automatically when their transactions are deleted.

Deploy the backend migration before using the feature:

```bash
cd backend
uv run alembic upgrade head
```

The migration adds `receipts.sha256_verified`, an index, and the
`duplicate_dismissals` table. Historical receipt hashes default to unverified.
