# Receipt Image Variants

Server-side persistence for cropped and processed receipt images is intentionally
deferred for the ML Kit scanner MVP.

The current backend stores a single object per receipt through
`receipts.storage_bucket` and `receipts.storage_key`. The worker downloads that
one object for extraction, `view-url` returns that same object for receipt photo
review, and receipt/account deletion cleanup removes that one object.

For this MVP, the mobile app uploads only the locally processed image. The
cropped ML Kit scan remains local for preview and is deleted from the app cache
after replacement, successful upload/navigation, or screen disposal where safe.

Future backend support should add a compatible variant model such as:

- `receipt_image_variants` table keyed by `receipt_id`, or nullable fields on
  `receipts`.
- Stored object keys for `cropped_object_key` and `processed_object_key`.
- `selected_extraction_object_key` to make the worker input explicit.
- Presigned upload support for both variants during receipt creation.
- `view-url` defaulting to the cropped/user-reviewed object.
- Backward compatibility for existing receipts that only have `storage_key`.
- Receipt deletion and account deletion cleanup that delete every stored
  variant object.
- A product decision on storage quota/usage: count only the processed image, or
  count both cropped and processed variants.

Any future migration should keep the current single-object path readable until
all existing receipts have either been migrated or intentionally left in legacy
mode.
