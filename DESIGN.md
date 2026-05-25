# AI Expense Tracker Design System

## Overview
AI Expense Tracker keeps the layout minimal and finance-focused. Large surfaces stay neutral. Accent color is used intentionally to improve recognition, selection state clarity, and chart readability without turning the app into a rainbow UI.

## Core Palette

### Base surfaces
- `pageBackground`: light `#F6F7F8`, dark `#111418`
- `sectionBackground`: light `#FFFFFF`, dark `#161A20`
- `standardSurface`: light `#FFFFFF`, dark `#1C2128`
- `elevatedSurface`: light `#F1F2F4`, dark `#242A32`
- `inputSurface`: light `#F6F7F9`, dark `#2B313A`
- `border`: light `#E2E4E8`, dark `#343B45`
- `divider`: light `#E0E3E8`, dark `#3A424D`
- `textPrimary`: light `#191716`, dark `#F2F5F7`
- `textSecondary`: light `#555C67`, dark `#C9D0D8`
- `textMuted`: light `#767A84`, dark `#929CAA`

### Fixed semantic status colors
- Success stays green.
- Error stays red.
- Premium and warning moments stay amber.
- Accent themes do not remap success, error, or premium status semantics.

## Accent Philosophy
- The app has exactly three accent themes: `Mix`, `Neutral`, and `Purple`.
- `Mix` is the default.
- Accent is applied to selected controls, primary CTA moments, semantic category and label badges, charts, and focused interactive moments.
- Accent is not used to tint every card or page background.
- Categories are always theme-managed semantic colors.
- Labels support two display modes:
  - `Raw colors` is the default and uses the saved label hex value.
  - `Accent-aware colors` remaps labels into the active accent system while keeping each label stable.
- Accent randomness is allowed only for the Home Scan Receipt hero in `Mix`, and only once per app launch.

## Accent Themes

### Mix
- Default accent theme for the app.
- Uses a controlled multi-accent system instead of one global brand color.
- Primary buttons, selected controls, scan FABs, and settings selections use the Mix primary accent.
- Categories use fixed recognizable colors.
- Category charts reuse the same category colors.
- Labels use raw saved colors by default. In accent-aware mode they map to a stable Mix label palette.
- The Home Scan Receipt hero picks one accent from a curated palette once per launch and keeps it for the full session.

### Neutral
- Monochrome alternative for users who want a calmer interface.
- Selected controls still have clear active styling, but the palette stays grayscale.
- Category and label themed colors are remapped to black, white, and gray slots.
- Category charts and trend charts use a true grayscale palette with more separation than the previous repeated ramp.
- Neutral must feel designed, not like color was disabled.

### Purple
- Keeps the same layout and information hierarchy as Mix and Neutral.
- Primary accent, selected controls, hero accents, and accent-aware semantic colors shift into a restrained purple family.
- Category and label differentiation is preserved through multiple purple-led tones rather than one flat purple.
- Purple must feel visibly different from Neutral even when large surfaces remain neutral.

## Semantic Category Mapping

### Source of truth
- Category color logic lives in `expense_tracker_app/lib/core/app_color_semantics.dart`.
- Widgets should resolve category tones through shared helpers in `expense_tracker_app/lib/core/redesign_system.dart`.

### Built-in category mapping in Mix
| Category code | Mix base color |
|---|---|
| `FOOD` | `#E27A3F` |
| `TRANSPORT` | `#5979B6` |
| `HEALTH` | `#2D9A74` |
| `UTILITIES` | `#2F8C8B` |
| `ENTERTAINMENT` | `#C49734` |
| `HOME` | `#4C66C8` |
| `ELECTRONICS` | `#2E8AAE` |
| `EDUCATION` | `#8462D8` |
| `CLOTHING` | `#C05F94` |
| `PERSONAL_CARE` | `#D46575` |
| `FLOWERS` | `#A96BBE` |
| `OTHER` / `UNCATEGORIZED` | `#748291` |

### Category resolution rules
- Built-in top-level category codes always map to fixed slots.
- Custom or unknown categories hash into the same curated slot set so they remain stable.
- Subcategories inherit the parent family when they do not have a direct top-level mapping.
- Widgets should not hardcode category colors locally.

### Category tone usage
- Use `tone.base` for chart segments, dots, and strong icon color.
- Use `tone.container` or `tone.containerStrong` for chip and badge backgrounds.
- Use `tone.border` for semantic chip borders.
- Use `tone.foreground` for chip text and icon strokes on tinted containers.
- Use `tone.onSolid` only when the background is the solid base color.

## Label Semantic Mapping

### Source of truth
- Label display color logic also lives in `expense_tracker_app/lib/core/app_color_semantics.dart`.
- Widgets must resolve label tones through shared helpers instead of parsing hex inline.

### Raw colors
- Default label display mode.
- Use the saved backend hex if valid.
- If the stored hex is missing or invalid, fall back to the stable themed label slot.
- Raw colors are preserved in storage even if the UI is currently using accent-aware mode.

### Accent-aware colors
- Labels are mapped to a stable slot based on label id and name.
- The same label keeps the same accent-aware color everywhere in the app.
- `Mix` uses a balanced multi-color label palette.
- `Neutral` uses grayscale slots.
- `Purple` uses a purple-led label palette.

## Chart Behavior

### Category charts
- Home donut, analytics donut, category rows, and similar category breakdown visuals must use category semantic colors.
- Category charts use `tone.base`.
- Aggregated `Other` uses a dedicated chart fallback color, not a random extra slot.

### Trend charts
- Trend line charts and time-based bar charts use the theme trend palette, not category colors.
- Current implementation uses the first tone of the theme trend palette for the single visible series.
- Future multi-series charts should keep using the ordered trend palette from the same semantic source.

### Neutral chart rules
- Neutral charts use true grayscale slots with stronger separation than the old 6-step ramp.
- Do not repeat nearly identical shades when there are enough slots available.
- Donut, bar, and category micro-chart states must remain readable in both light and dark mode.

### Purple chart rules
- Purple charts use a family of purple-led tones.
- They must preserve category differentiation.
- They must not collapse to one flat purple.

## Accent Usage Rules

### Use accent color for
- Filled primary buttons
- Selected segmented controls and section selectors
- Active bottom navigation icon and label
- Accent-aware settings choice states
- Category badges, category icon containers, and category dots
- Label badges and label icon containers
- Analytics charts
- Scan FABs
- Home Scan Receipt hero

### Do not use accent color for
- Full-page backgrounds
- Standard cards by default
- Every secondary button
- Success and error semantics
- Random category or label reassignment
- Per-render randomization

## Home Scan Receipt Hero
- The Home Scan Receipt hero is the only rotating accent surface.
- In `Mix`, it picks one accent from a curated palette once per app launch.
- The chosen accent stays fixed for that session.
- It may change on the next app launch.
- `Neutral` uses a graphite-first hero treatment.
- `Purple` uses a purple hero treatment.
- Shell and settings scan FABs do not rotate; they always use the normal theme primary accent.

## Implementation Source Of Truth
- `expense_tracker_app/lib/core/app_color_semantics.dart`
  - Accent families
  - Category palettes
  - Label palettes
  - Neutral grayscale palettes
  - Purple tonal palettes
  - Trend palettes
  - Home hero accent palette
- `expense_tracker_app/lib/core/theme_provider.dart`
  - Accent persistence
  - Mix default migration
  - Label color mode persistence
  - Session-stable Mix hero accent selection
- `expense_tracker_app/lib/core/redesign_system.dart`
  - Shared context-based accessors for semantic tones and hero styling

## Guardrails For Future Work
- Do not add new accent themes unless they can be meaningfully applied across semantic colors, charts, and selected controls.
- Do not add widget-local category or label color maps.
- Do not reintroduce grayscale hashing for category charts.
- Do not let primary actions fall back to neutral hardcoded fills when they should follow the current theme accent.
- If a new category or label surface is added, wire it through the shared semantic helpers before shipping.

## Public Website Rules
- The public website uses the same neutral surface palette as the app: light backgrounds from `#F6F7F8` to white, dark backgrounds from `#111418` through `#242A32`.
- The website must not use green as a brand accent. Green remains reserved for success states inside the app.
- The website accent is the Mix preview gradient: purple to pink to orange to yellow.
- The website should stay customer-facing. Do not expose implementation notes such as source markdown filenames, repository structure, generated-page explanations, or internal deployment details.
- The website header uses the app favicon and `logo-login-*` brand assets from `expense_tracker_app`.
- The website typography target is Google Sans, with safe system fallbacks when the font is unavailable.
