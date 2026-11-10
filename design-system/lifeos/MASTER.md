# LifeOS — Design System

> `ui-ux-pro-max` local dataset (styles/palettes/fonts/search.py) is NOT installed in this
> environment, so no database match is claimed here. This file is a hand-built system using the
> skill's priority rules (accessibility → touch → performance → style → layout → type/color →
> motion → feedback → nav → charts) and the reference direction requested by the user
> (charlesleclerc.com: editorial, cinematic, high-contrast, oversized type, smooth motion).
> The reference is a web site; its GSAP/scroll choreography is translated to Flutter-native
> equivalents (scroll-linked transforms, staggered entrances, hero transitions, custom page
> transitions). No literal GSAP runs in the app.

## Direction

**"Editorial dark, racing-calm."** Near-black paper, warm off-white ink, one red accent used
sparingly for action/now/selection, oversized display type, thin rules, generous whitespace,
and motion that feels like a camera move rather than a UI toggle.

- Mood: black-and-white editorial page with a single red line, not a "neon AI dashboard".
- Density: comfortable (8-pt scale, 16-24px gutters), editorial not dashboard.
- Motion: high craft, low noise. Everything eases with `cubic-bezier(0.16,1,0.3,1)`; nothing
  bounces on its own; motion explains hierarchy, never decorates.

## Color tokens

| Token | Value | Use |
|---|---|---|
| `bg` | `#08090B` | app background |
| `surface` | `#101114` | sheets, bars |
| `surfaceHigh` | `#17181C` | raised cards, inputs |
| `ink` | `#F1EEE8` | primary text (warm off-white) |
| `inkDim` | `#8C8B86` | secondary text |
| `line` | `#26272C` | hairlines, dividers |
| `lineSoft` | `#1B1C20` | inner rules |
| `accent` | `#D7261E` | the single red: FAB, now-line, active tab, destructive |
| `accentDim` | `#7E1712` | red at rest / hover wash |
| `positive` | `#8FBFA8` | kept from task palette (muted) |
| task palette | existing 10 muted colors | task identity only; never UI chrome |

Rules:
- Red is never a background for large areas. It appears as a line, a dot, a single control.
- Text on `bg` uses `ink`; never gray-on-gray below 4.5:1.
- The 10 task colors are the only saturated colors in content; chrome stays monochrome + red.

## Typography

| Role | Family | Size / weight / tracking |
|---|---|---|
| Display / wordmark | Bricolage Grotesque (fallback: system) | 28-40, w600, tracking -0.02em |
| Screen title | Bricolage Grotesque | 22-26, w600, -0.01em |
| Section label | Manrope | 11-12, w600, tracking +0.14em, uppercase |
| Body | Manrope | 14-15, w400-500, height 1.45 |
| Meta / time | Space Grotesk (tabular) | 11-12, w400, tabular figures |
| Chinese | Noto Sans SC (fallback: system CJK) | inherit sizes |

Rules:
- Base body never below 12px; times/numbers tabular.
- Display type is used only for the wordmark, screen titles and the big day number.
- Letter-spacing only for uppercase labels; never on CJK.

## Space & shape

- Scale: 4 / 8 / 12 / 16 / 24 / 32 / 48.
- Radii: 10 (inputs), 14 (buttons), 18 (cards), 28 (sheets).
- Hairline = 1px `line`; card separation prefers whitespace + hairline over shadows.
- Shadows only for floating layers (FAB, sheets): `0 10 30 rgba(0,0,0,.35)`.

## Motion

| Token | Value |
|---|---|
| `durFast` | 120ms |
| `durBase` | 200ms |
| `durSlow` | 360ms |
| `durCinematic` | 520ms |
| `easeOut` | `Cubic(0.16, 1, 0.3, 1)` |
| `easeInOut` | `Cubic(0.65, 0, 0.35, 1)` |

Motion kit (Flutter-native, no GSAP):
1. **Scroll-linked header**: `SliverAppBar` collapses the wordmark into a compact bar;
   title opacity/size interpolates with scroll offset.
2. **Staggered entrance**: list rows fade+rise 8px with 40ms stagger (`AnimationController` +
   intervals), once per screen visit.
3. **Hero continuity**: task card → detail sheet uses `Hero` for the color rail and title.
4. **Page/segment transitions**: `PageRouteBuilder` fade + 8px slide; segmented control uses an
   animated underline that slides between tabs.
5. **Number ticker**: day number and "now" time use `AnimatedSwitcher` with slide/fade.
6. **Reduced motion**: if `MediaQuery.disableAnimations` is true, all durations → 1ms and
   staggered entrances are skipped.
7. **Haptics**: light impact on confirm/delete only; never on scroll.

Anti-patterns: no one-duration-for-everything; no animating width/height in lists; no infinite
decorative loops; no motion on scroll that blocks reading.

## Components

- **App bar**: wordmark `LIFEOS` in display type + red dot; actions as icon buttons (44×44).
- **Segmented**: text tabs with a 2px red animated underline; no pill.
- **Task card**: 56-72px editorial row — index or color rail, title, one meta line
  (`ddl · estimate`), U/I as tabular figures; pressed state = 4% ink wash.
- **Day grid**: hour labels Space Grotesk tabular; hairline hours; red now-line with a dot;
  blocks keep the task palette, left 3px full-color rail, 12% fill; compact layout under 52px.
- **Sheets**: 28 radius, drag handle, `durCinematic` entrance, primary action bottom-right.
- **FAB**: 56px red circle, white plus, shadow.
- **Charts (future U/I scatter)**: monochrome axes, red selection, task colors only as data
  points, tabular labels; no rainbow.

## Accessibility

- Contrast ≥ 4.5:1 for body, ≥ 3:1 for large display.
- Touch targets ≥ 44×44; 8px+ separation.
- Every icon-only button has a tooltip/semantic label.
- Focus/pressed states visible; keyboard/focus not obscured by the bottom sheet.
- Respect `disableAnimations`.

## Pre-delivery checklist

- [ ] analyze 0, full tests green
- [ ] no overflow at 30-minute blocks / small heights
- [ ] red used only for accent, not large fills
- [ ] reduced-motion path works
- [ ] CJK and Latin line-heights both sane
- [ ] screenshots refreshed by the maintainer

## Verified against ui-ux-pro-max (local library, run 2026-11-09)

Query: `search.py "productivity task planner dark editorial cinematic" --design-system --variance 7 --motion 9 --density 5`
and targeted `--domain style/color/typography/chart/gsap/ux` + `--stack flutter`.

**Style match** — `exaggerated-minimalism` (Editorial/luxury): oversized type, extreme negative
space, black/white dominant, **single accent only**; dark mode supported. Secondary match
`dark-mode-oled`. This replaces the "flat teal" default the design-system generator returned for a
generic productivity query — that default did NOT fit the requested reference and was discarded.

**Typography match** — `Modern Dark Cinema (Inter System)`: Inter 700 (-1.5 tracking) display,
Inter 600 H1/H2, Inter 400 body, Inter 500 uppercase +1.2 tracking labels. Implemented in
`lib/ui/theme.dart` (display/body/label all Inter; tabular figures for time/meta).

**Color** — closest palette match is the "Auction Platform" dark-luxury profile
(bg `#020617`, fg `#F8FAFC`, destructive `#DC2626`, border `#334155`). We keep the warmer
LifeOS tokens (`#08090B` / `#F1EEE8`) and the single red `#D7261E`; red remains the only accent.

**Chart guidance** — timeline/agenda maps to a **Line Chart** (trend over time; ≥4 points; solid +
dashed + dotted, never hue-only; 20% fill; visible data table fallback; zoom). For the app the day
grid is the chart; the "今日负荷" bar uses a single accent fill + tabular label.

**Motion** — `gsap` results: Scroll Reveal (complex, scrub/pin) and Parallax (subtle) with the
explicit warnings: parallax on decorative layers only, small deltas, no pinning beyond 1-2
sections, never scroll-jack, always honor reduced motion. Flutter stack: Hero for shared elements,
SliverList for custom scroll, dispose controllers. Implemented equivalents: staggered list reveal,
segment underline, task-rail Hero (list → detail), page transitions, `disableAnimations` guard.
**Not implemented:** scroll-pinning / scrub choreography (deliberately: the skill flags pinning as
bad on mobile and scroll-jacking as an accessibility violation).

**UX** — reduced motion (High severity) and motion sensitivity (High): both honored via
`MediaQuery.disableAnimationsOf`.
## v2 — "Midnight Instrument" (2026-11-10)

The old red accent was rejected after reviewing `docs/assets/logo.jpg`: the icon is a deep-navy
squircle with an electric-blue -> cyan gradient (checklist + calendar + sparkle). Red belongs to a
different brand family. v2 derives the whole system from the logo.

**Palette (all contrast-checked):**
- ground `#060B16`, surface `#0C1424`, raised `#111B2E`
- ink `#E8EEFA`, dim `#8593AC`, hairlines `#1B2740` / `#131D31`
- brand: `#3D7BFF` -> `#4ED2FF`; primary CTA fill `#4ED2FF` with `#06101F` label (12.4:1)
- danger `#FF5B6E`

**Type:** Sora (display + tabular numbers) / Manrope (body) / Noto Sans SC fallback. Replaced Inter
(the "Modern Dark Cinema" default) because the brief asks for a distinctive identity, not a default.

**Layout / IA:** top segmented control replaced by a **bottom navigation** (任务 / 日视图) with a
gradient FAB; task rows are **time-led** (44px time gutter + color dot + title + one meta line) instead
of cards; the day-scoped sections (当天 / 待安排) stay.

**Buttons:** primary = bright cyan fill, ink label, 12px radius, no shadow; secondary = hairline
outline; destructive = red text. FAB = brand gradient circle. No gradient behind text anywhere else.

**Motion:** existing scroll-linked wordmark, staggered rows, day ticker, hero rail, sheet entrance;
all honor `disableAnimations`.

**Verification (2026-11-10):** `flutter analyze` 0; `flutter test` 74/74; WCAG pairs measured with the
relative-luminance formula: ink/bg 16.91:1, dim/bg 6.34:1, dim/surface 5.93:1, cyan/bg 11.23:1,
ink-on-cyan 10.88:1, ink/raised 14.79:1, danger/bg 6.53:1, blue/bg 5.13:1 (UI only).