# Receipt history search and filters

Receipt search and filters are available to every user. Submit the search field
with the keyboard search action to search merchants and stored item names,
including original, expanded and normalized names, brands and product types.
Search is case insensitive and treats `%`, `_` and backslashes as literal text.
The legacy `merchant_name_search` API parameter remains available.

The filter sheet adds original currency, minimum/maximum total, entry type
(scanned, manual or imported), and status (needs save or saved). These combine
with the existing dates, categories, subcategories, labels and review toggle.
Amounts are inclusive and require an explicit original currency. Zero and
negative totals are supported; missing totals do not match an amount range.
Comma decimal separators are accepted in the app. Amount sorting still uses the
user's display currency.

The API adds `search` (maximum 200 characters), `min_amount` and `max_amount` to
`GET /v1/transactions`. Amount bounds accept up to two decimal places. Missing
currency or an inverted range returns HTTP 422. Existing `currency`, `source`
and `status` parameters supply the other filters. All predicates run before
sorting and pagination. Analytics API scopes use the same new predicates.
Loading more retains every filter, and changes reset the history to page one.
Removing the currency chip also removes its amount bounds. Clearing the filter
sheet clears its scoped selections while retaining the chosen period; the
history's Clear all filters action also clears search, period and review state.
No new database migration is required for this feature.

## Manual checks on develop

Deploy the backend and rebuild the app from the same develop revision. Apply
outstanding migrations first, including the duplicate-review migration described
in [Duplicate review](DUPLICATE_REVIEW.md).

1. Search for a merchant, then an item found only in an older receipt. Load more
   and change sorting; verify results and filters stay consistent.
2. Combine EUR, a 10.25–50.50 range, manual entry and saved status. Reopen the
   sheet, remove individual chips, then clear all filters.
3. Try an amount without currency, a reversed range, and more than two decimal
   places. Each must stay in the sheet with an error. Try a refund range and a
   comma decimal separator.
4. Combine custom dates, categories, subcategories, labels and Needs review with
   the new filters. Verify an empty result can be cleared.
5. Review duplicate purchases in Tools: compare details/photos, keep both, and
   test Keep selected on disposable records. Verify only the chosen duplicate is
   deleted. Save editor changes before entering comparison.
6. Check receipt history beyond 50 records, all sort options, retrying a failed
   load-more request, and display-currency totals.

7. Switch the app language and check sorting, filters, validation messages and
   duplicate review. Check German with larger text and Arabic with right-to-left
   controls. Amount range chips should use localized decimal separators; decimal
   keyboards using commas or Arabic digits must still submit exact amounts.
