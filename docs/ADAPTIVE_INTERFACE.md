# Adaptive interface and receipt comparison

This branch is based on develop and does not include the separate portable-backup
and upload-recovery work from `fix/expense-tracking-reliability`.

## Interface scale

The existing saved preference is retained. Its 60/80/100/120 labels now represent
exact scale factors 0.6/0.8/1.0/1.2 for the interface, rather than approximate
text-only factors. The default 100% uses denser base typography and controls.

`InterfaceScale` supplies inverse layout constraints and a matching MediaQuery
before fitting that coordinate space into the viewport. Layout can therefore
reflow at each scale. Text, icons and spacing scale together; this is not only a
paint transform over the old layout. Keyboard, safe-area, gesture and display
feature coordinates are converted into the same space. System text accessibility
settings remain independent, including the platform's nonlinear TextScaler.

Native control dimensions are defined in the same interface coordinate space,
so a compact percentage reduces button geometry alongside its text and icons.
System text accessibility still grows content and can trigger a different layout.
Receipt sorting/review controls measure their actual localized text
before choosing a row or separate lines. Home headings and totals reflow, and
Tools shortcuts use one to three columns with natural row heights. Taxonomy
actions use labeled icon buttons.

## Amount filter

History now sends `min_display_amount` and `max_display_amount`. These optional,
inclusive bounds use the display currency (`target_currency`, defaulting to the
account currency), the same cached historical FX lookup and two-decimal rounding
as displayed history amounts. SQL applies bounds before sorting and pagination.
Transactions without a total or a cached conversion cannot match the range.
Filtering itself does not contact an exchange-rate provider.

An original-currency restriction is independent and lives under More filters,
alongside source, status, category, subcategory and labels. Removing that currency
restriction retains the display-amount range. The applied range retains its
currency, so an asynchronous profile refresh cannot reinterpret its numeric bounds. Existing API `min_amount` and
`max_amount` keep their original-currency meaning for older clients.

The new backend advertises `Expense-Amount-Filter: display-v1`; CORS exposes it.
The app requires this header when applying a range, so an older backend cannot
silently ignore the new parameters and present an unfiltered list. Deploy this
backend before manually testing amount ranges in the new app. No migration is added.

## Duplicate review

The finder groups connected matching pairs among loaded result pages. Three
copies appear in one group instead of three repeated cards. Loading another page
can extend or join groups; the count describes the receipts loaded so far.
Group membership does not assert that every pair matches. The pair chooser exposes
only real backend matches, and the confidence badge uses the weakest confidence
in the group. Decisions and deletion confirmation still operate on one explicit
pair, retaining the existing ownership, version and storage checks.

The comparison places both receipts and aligned item rows next to each other.
Names/amounts/quantities/unit prices highlight matches and differences, with text
and icons as well as color. Duplicate product lines are preserved; exact lines
are paired first, then remaining equal names expose changed quantities/prices.
This alignment is a presentation aid, not a new duplicate-detection rule.
The differences-only control never hides unequal currencies as equal amounts.
Safe areas protect the finder, comparison actions and taxonomy pages from system
navigation. Actions reflow when their localized labels no longer fit.

## Manual acceptance

1. On a phone with gesture navigation and one with three-button navigation, check
   60/80/100/120%, then repeat 100/120% with larger system text. Check keyboard,
   popup menus, dialogs, rotation, sorting/review placement and bottom actions.
2. Check Appearance's example, Categories, Subcategories, Labels, History and
   Subscription. Change scale, restart, and verify the preference persists.
3. Apply a display-currency amount range across receipts in different currencies;
   check inclusive boundaries, refunds, invalid decimals, loading more, independent
   original currency, clearing each chip and Clear all. Expand More filters,
   select values, reopen and verify that selected advanced filters stay visible.
4. Create three disposable matching receipts. Check one group, choose different
   pairs, compare adjacent quantities/prices, show differences, cancel deletion,
   keep one copy, reload, then resolve the remaining pair. Test Keep both with a
   separate pair. Existing record edits must still trigger conflict/reload checks.
5. Repeat key screens in Russian, German and Arabic in both brightness modes.

Automated tests cover scale geometry, safe-area conversion, touch bounds,
grouping, repeated item alignment, FX bounds before pagination, protocol
negotiation, existing duplicate decisions and large/localized layouts. Preview
generation uses synthetic transactions only.
