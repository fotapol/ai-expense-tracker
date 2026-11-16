# Interface polish after phone testing

These changes continue `fix/adaptive-interface` after `fe250fa`. They only change
Flutter presentation, navigation and translations. The deployed `dev-fe250fa`
backend already supports the app; no new backend image or migration is needed.

## Decisions

- Home's introductory sentence wraps in full. Quick actions measure localized
  labels and use one row, a full-width primary action with two secondary actions,
  or individual rows according to available space. They retain normal typography
  instead of shrinking labels to fit fixed-height tiles. A marquee is avoided
  because users would have to wait to read an ordinary instruction.
- Tools lists each action once. Scan, Receipt Manager and Analytics use an accent
  icon, outline and a small pin with a localized tooltip in the common list.
- Analytics uses one moving tab indicator driven by the PageController, including
  swipe gestures. Root tabs slide while retaining their state; visited analytics
  pages retain loaded data and scroll position. Android/desktop routes use Flutter's
  native fade-forward transition. iOS keeps its platform transition. New motion
  honors the system's disabled-animations preference.
- Overview shows the actual current and previous date ranges and their totals.
  Zero previous totals explain why a percentage is unavailable; missing or negative
  previous totals do not imply a percentage or an unchanged amount. Metrics have
  equal dimensions calculated from localized text and platform text scaling. Wide
  layouts use columns; compact layouts use rows or vertically arranged content.
- Period, receipt source/status/currency and appearance scale use a shared
  controlled choice field. Rounded menus attach below the input when possible,
  scroll within available space, and may flip above in a short viewport. A canceled
  custom date picker does not change the displayed period. Labels sit outside
  clipped materials so their upper halves cannot be cut off.
- Category and label selections use checks and stronger outlines; chosen
  subcategories also have clear check/delete controls. Advanced fields stretch
  to the leading edge, including their subcategory picker and selected chips.
- Needs review is represented by its toggle alone, with an icon and accessible
  tooltip at narrow sizes. It is excluded from the filter badge and removable
  chips. Other active filters keep their existing chips. Monthly subtotals and
  the trailing summary use the full available width to align with card edges.
- Duplicate finder has explicit loading, empty and error surfaces. Empty results
  have a refresh action and pull-to-refresh; matching groups and deletion decisions
  retain the existing behavior.
- Rounded press feedback is also applied to language, currency, category, help,
  about and feature-request rows. Home copy previously copied from Italian was
  corrected in Polish, Serbian, Portuguese, Turkish, Dutch, Swedish, Czech,
  Romanian, Hungarian, Indonesian, Malay and Vietnamese.

## Manual acceptance

1. Check Home and Tools at 60/80/100/120% in German, Russian and English. Repeat
   with larger Android text. Read the whole subtitle and use all three actions.
   Verify the three highlighted tools occur only once and still open their pages.
2. Switch Home/Tools/Settings quickly and return after scrolling. In Analytics,
   tap distant sections, swipe, interrupt a transition with another tap, scroll,
   and return to the Overview. Filters and section persistence must remain correct.
   Disable system animations and check that switching stays usable and immediate.
3. Check equal metric cards in compact and wide layouts. Compare a custom period
   with earlier data, with a zero previous total, and with refunds. All Time must
   explain why a finite comparison period is needed. Current and previous dates
   should be recognizable without remembering another screen.
4. Open period menus and scroll to Custom period. Apply dates, reopen and cancel.
   Repeat after opening the amount keyboard and in landscape. The input must stay
   visible. Test outside-tap dismissal and changing Appearance's scale.
5. Expand advanced filters; select/unselect categories, subcategories and tags.
   Reopen to verify persistence, clear individual chips, then clear everything.
   Check checks, outlines, delete-icon contrast and leading alignment in both
   themes, including Arabic reading direction.
6. Activate Needs review alone: there should be no duplicate removable chip or
   filter-count badge for it. Add other filters and verify their chips/counts.
   Check the right edges of monthly totals and the receipt count/savings footer.
7. With no duplicate candidates, refresh and pull down. Add disposable duplicate
   receipts and review their group; confirm the list design and bottom safe area.
8. Hold rounded controls (especially sorting and More filters) to inspect their
   highlight shape. Repeat in light/dark themes and three-button navigation.

Automated widget checks use synthetic records and cover all 24 supported locales,
four interface scales, large text, menu bounds, comparison dates, root-tab state,
analytics data retention and reduced motion. Phone acceptance remains a manual step.
