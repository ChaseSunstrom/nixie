# Nixie design tokens and component inventory

Extracted from `design/Nixie Front Panel.html` (407,761 bytes). Values are quoted verbatim.

## 0. How the file is packaged (read this first)

The file is a **Claude Design canvas export**, not a plain page. The outer HTML is a bundler shell; the actual design is a JSON-encoded string in `<script type="__bundler/template">` (line 384), and every asset (fonts, scripts) is a gzip+base64 blob in `<script type="__bundler/manifest">`. Decoded, the template is 89 KB / 689 lines containing one artboard `<section id="2a">` (canvas label "Direction A, second pass — NixOS blues, three finishes, depth, new mark, new panels") plus a `<script type="text/x-dc">` React-like component that owns state and theme data.

Consequences for re-implementation:

- **All styling is inline `style="..."`.** There are no CSS classes, no stylesheet rules beyond `:root`, `body`, `a`, `::selection`. "Component classes" below are therefore named by me from repeated inline recipes.
- Hover/focus states use the canvas's `style-hover="..."` / `style-focus="..."` attributes.
- Tokens are injected twice: a static `:root` block (Graphite values) and a per-artboard inline `--x:{{ t.x }}` binding fed from a JS `THEMES` object. **The JS `THEMES` object is the real source of truth for all three finishes.**
- There is **no `[data-finish]` / `[data-theme]` attribute, no `@media`, no `prefers-color-scheme`, no `transition`/`animation` CSS anywhere.** Theme switching is JS state (see section 6).
- Manifest assets: 2 design-runtime scripts (`3edde421…` 69 KB canvas runtime, `30f81c89…` 13.5 KB Nixie demo data), React 18.3.1 + ReactDOM UMD (external resources, unpkg), 9 woff2 font files.

## 1. CSS custom properties

### 1.1 Property names (21, identical set in every scope)

`--bg --s1 --s2 --s3 --line --line2 --ink --muted --shadow --glow --brand --brand2 --cpu --mem --net --disk --ok --ice --err --hot --scrim`

Semantics (from the artboard copy): `--bg` base plate; `--s1` raised panel surface; `--s2` inset well / recessed control surface; `--s3` hover / chip surface; `--line` panel border and dividers; `--line2` stronger border (kbd chips, inactive swatch border); `--ink` text; `--muted` secondary text; `--shadow` the single drop-shadow colour ("one recipe: 0 8px 24px −14px, alpha per finish (.45 / .5 / .16)"); `--glow` readout text-shadow ("Readouts glow faintly on dark finishes; on Paper they don't"); `--brand` NixOS blue "selection, focus, primary"; `--brand2` NixOS light "links, glow, CPU"; `--cpu/--mem/--net/--disk` metric families (blue / violet / teal / copper); `--ok` running; `--ice` frozen; `--err` error / over cap; `--hot` GPU hot / warn; `--scrim` modal backdrop.

The JS theme object carries three extra non-CSS keys per finish: `label`, `swatch` (theme-picker swatch colour, equals `bg`), `ramp` (GPU heat gradient, used as an inline `background`), `dark` (boolean used by the heat-colour function).

### 1.2 Base `:root` (static, Graphite values; helmet `<style>`)

```css
:root { --bg:#1f2226; --s1:#292d33; --s2:#181b1e; --s3:#31363d; --line:#383e46; --line2:#4a515b; --ink:#eceae5; --muted:#9a9ea6; --shadow:rgba(0,0,0,0.45); --glow:0 0 14px rgba(126,186,228,0.28); --brand:#5277c3; --brand2:#7ebae4;
  --cpu:#7ebae4; --mem:oklch(78% 0.12 300); --net:oklch(78% 0.11 190); --disk:oklch(78% 0.12 45); --ok:oklch(78% 0.14 150); --ice:oklch(85% 0.06 230); --err:oklch(68% 0.19 25); --hot:oklch(80% 0.15 60); --scrim:rgba(20,22,25,0.7); }
body { margin:0; background:var(--bg); }
a { color:var(--brand2); } a:hover { color:var(--ink); }
::selection { background:var(--brand); color:#fff; }
```

The artboard root re-binds the same 21 names inline:
`--bg:{{ t.bg }};--s1:{{ t.s1 }};--s2:{{ t.s2 }};--s3:{{ t.s3 }};--line:{{ t.line }};--line2:{{ t.line2 }};--ink:{{ t.ink }};--muted:{{ t.muted }};--shadow:{{ t.shadow }};--glow:{{ t.glow }};--brand:{{ t.brand }};--brand2:{{ t.brand2 }};--cpu:{{ t.cpu }};--mem:{{ t.mem }};--net:{{ t.net }};--disk:{{ t.disk }};--ok:{{ t.ok }};--ice:{{ t.ice }};--err:{{ t.err }};--hot:{{ t.hot }};--scrim:{{ t.scrim }}`

### 1.3 Finish variants (verbatim from `const THEMES`)

| token | Graphite (`dark:true`) | Umber (`dark:true`) | Paper (`dark:false`) |
|---|---|---|---|
| label | `Graphite` | `Umber` | `Paper` |
| swatch | `#1f2226` | `#231b16` | `#e4e1da` |
| `--bg` | `#1f2226` | `#231b16` | `#e4e1da` |
| `--s1` | `#292d33` | `#2d241d` | `#f6f4ef` |
| `--s2` | `#181b1e` | `#1a130f` | `#d9d5cc` |
| `--s3` | `#31363d` | `#372c24` | `#fbfaf7` |
| `--line` | `#383e46` | `#42362d` | `#c9c4b9` |
| `--line2` | `#4a515b` | `#57483c` | `#a9a397` |
| `--ink` | `#eceae5` | `#f1e9df` | `#1c1b19` |
| `--muted` | `#9a9ea6` | `#a2968a` | `#5f5c56` |
| `--shadow` | `rgba(0,0,0,0.45)` | `rgba(0,0,0,0.5)` | `rgba(40,30,10,0.16)` |
| `--glow` | `0 0 14px rgba(126,186,228,0.28)` | `0 0 14px rgba(126,186,228,0.28)` | `none` |
| `--brand` | `#5277c3` | `#5277c3` | `#5277c3` |
| `--brand2` | `#7ebae4` | `#7ebae4` | `#3f6bb8` |
| `--cpu` | `#7ebae4` | `#7ebae4` | `#3f6fbf` |
| `--mem` | `oklch(78% 0.12 300)` | `oklch(78% 0.12 300)` | `oklch(50% 0.14 300)` |
| `--net` | `oklch(78% 0.11 190)` | `oklch(78% 0.11 190)` | `oklch(50% 0.11 190)` |
| `--disk` | `oklch(78% 0.12 45)` | `oklch(78% 0.12 45)` | `oklch(55% 0.13 45)` |
| `--ok` | `oklch(78% 0.14 150)` | `oklch(78% 0.14 150)` | `oklch(55% 0.15 150)` |
| `--ice` | `oklch(85% 0.06 230)` | `oklch(85% 0.06 230)` | `oklch(58% 0.08 230)` |
| `--err` | `oklch(68% 0.19 25)` | `oklch(68% 0.19 25)` | `oklch(55% 0.20 25)` |
| `--hot` | `oklch(80% 0.15 60)` | `oklch(80% 0.15 60)` | `oklch(62% 0.16 55)` |
| `--scrim` | `rgba(20,22,25,0.7)` | `rgba(20,14,10,0.7)` | `rgba(60,55,45,0.5)` |
| ramp (not a CSS var) | `linear-gradient(90deg,#181b1e,oklch(45% 0.14 25) 35%,oklch(70% 0.17 45) 70%,oklch(92% 0.10 85))` | `linear-gradient(90deg,#1a130f,oklch(45% 0.14 25) 35%,oklch(70% 0.17 45) 70%,oklch(92% 0.10 85))` | `linear-gradient(90deg,#d9d5cc,oklch(75% 0.12 70) 35%,oklch(55% 0.18 35) 70%,oklch(30% 0.12 25))` |

Note: the Paper swatch card in the token panel prints `d6d2c9` as its third chip but the THEMES value for Paper `--s2` is `#d9d5cc`. Use `#d9d5cc` (the value that actually renders).

The `glow` prop is additionally gated by a boolean canvas prop `glow` (default `true`); when false, `--glow` becomes `none` on any finish.

### 1.4 Hard-coded (non-token) values worth tokenising

- Brand blues used literally in SVG marks and swatches: `#5277c3`, `#7ebae4`, `#fff` (mono mark).
- Radii (from the copy: "6px panels, 4px wells, 3px buttons and chips, 0 on strip, lanes, tables"). Observed: `6px` ×27 (panels), `4px` ×21 (wells, ⌘K button, button group, swatch chips), `3px` ×22 (buttons, kbd, chips, badges, range buttons, heat strips), `5px` ×3 (segmented control tray), `2px` ×9 (progress bars, lane heat strip), `8px` ×2 (command palette), `50%` ×9 (dots), `14px`/`7px` (app icon tiles).
- Shadows (all colours via `var(--shadow)` unless stated): panel `0 8px 24px -14px`; header `0 6px 18px -12px`; command palette `0 24px 60px -20px`; button group `0 4px 12px -8px`; inset well `inset 0 1px 3px`; inset control tray `inset 0 1px 2px`; live dot `0 0 8px var(--ok)`; instance title dot `0 0 10px var(--ok)`.
- Fills: chart area `color-mix(in oklch, var(--cpu) 20%, transparent)` / `var(--mem) 20%`; killswitch chip `color-mix(in oklch, var(--ok) 22%, transparent)`.
- Focus ring: `outline:2px solid var(--brand2)` with `outline-offset` `2px` (buttons), `1px` (small swatch/range buttons), `-2px` (lane rows).
- Blur: **none used** (no `backdrop-filter`, no `filter:blur`). Depth is entirely 1px line + shadow.
- Spacing scale observed: 1, 2, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 48, 56 px. Panel padding `12px 14px` or `10px 14px 12px`; token cards `24px`; screen grid gap `12px`, screen padding `14px 20px 16px`.
- Motion (prose only, no CSS): "120 ms state, 200 ms range re-fit, cursor unsmoothed. No entrance choreography; reduced motion snaps."

## 2. Typography

**Families**: `Archivo, sans-serif` (UI) and `'JetBrains Mono', monospace` (readouts, tick labels, IPs, kbd, terminal). Copy: "Type — Archivo + JetBrains Mono (OFL, bundled)".

**Loading**: `<link rel="preconnect" href="https://fonts.googleapis.com">` followed by an inline `<style>` of Google-Fonts-style `@font-face` blocks, each `src: url("<uuid>") format('woff2')` where the uuid resolves to a woff2 embedded (gzip+base64) in the bundler manifest. So: **self-hosted woff2, `font-display: swap`**, subset by `unicode-range`.

| family | weights declared | subsets | `font-stretch` |
|---|---|---|---|
| Archivo | 400, 500, 600, 700 | vietnamese, latin-ext, latin (700 also cyrillic-ext) | `100%` |
| JetBrains Mono | 400, 500 | cyrillic-ext, cyrillic, greek, vietnamese, latin-ext, latin | — |

Note the manifest ships only 3 Archivo files (shared across the 400–700 declarations — a variable font) and 6 JetBrains Mono files (shared across 400/500).

**Type scale** (from the "Type" token card, verbatim):

| role | size / weight | letter-spacing | line-height |
|---|---|---|---|
| Display | `40px` / `600` | `-0.02em` | `1` |
| Title | `22px` / `500` | `-0.01em` | — |
| Body | `15px` / (400) | — | `1.5` |
| Caption | `13px` / (400), `color:var(--muted)` | — | — |
| Readout (mono) | `28px` JetBrains Mono, `color:var(--cpu)`, `text-shadow:var(--glow)` | — | — |

Other sizes actually used on screens: header stat readouts `18px` mono (unit suffix `11px` muted, `text-shadow:none`); ring gauge value `24px` mono; pool ring value `20px` mono; instance page title `28px` / 600 / `-0.02em`; wordmark `20px` / 600 / `-0.03em` in header, `26px`/`60px` in logo cards; screen base font-size `13px`; table/list rows `12px`; tick labels & hints `11px` mono; palette input `15px`; terminal `13px` mono, `line-height:1.45`; artboard h1 `56px`/600/`-0.025em`; artboard intro `17px`/1.5. Labels are sentence case ("no tracked caps").

## 3. Screens, navigation, and widgets

**Primary nav (in order, from `PAGES` and the `<nav aria-label="Primary">`)**: `Overview`, `Instances`, `Images`, `Profiles`, `Networks`, `Storage`, `Operations` (with a count badge `3`), `Settings`. Active item: `color:var(--ink);border-bottom:2px solid var(--brand2);margin-bottom:-1px`; inactive: `color:var(--muted)` hover `var(--ink)`. Palette hints suggest single-key nav `g o`, `g i`, ... (`'g ' + p[0].toLowerCase()`).

**Instance sub-nav (in order)**: `Overview`, `Configuration`, `Devices 6`, `Snapshots 3`, `Terminal`, `Logs`, `Files`, `Metrics`.

Only two screens are mocked, both 1440 × 900:

### 3.1 "A2 Overview" (key screen)
Header strip (64px) → primary nav (44px) → 12-column grid, rows `198px 252px 1fr`, gap 12px:

| span | widget |
|---|---|
| 3 | **CPU** area/line chart in an inset well, 3 dashed gridlines at y=35/70/105 of 140, value at cursor `{{ cpuAt }} %`, tick row |
| 3 | **Memory** chart, same recipe, `/ 64 GB` |
| 3 | **GPU power** two lines (`--hot` GPU 0, `--disk` GPU 1), red dashed cap line at `280 W` (`--err`), legend row |
| 3 | **GPU temperature** two **ring gauges** (270° arcs, `stroke-dasharray="217 289"`, `rotate(135)`, `stroke-linecap:round`, r=46 sw=10 in a 120 viewBox, 118px), centre value 24px mono, "GPU 0 · util %" caption, colour by `tempColor` (>80 err, >68 hot) |
| 7 | **Instances lanes** — one 21px row per instance: status dot, name, `.ip` suffix, **96-cell CPU heat strip** (`grid-template-columns:repeat(96,1fr);gap:1px;height:11px;border-radius:2px`), CPU at cursor (mono 12px, `--hot` if >40), memory bar + value. Zebra rows (`--s2`/transparent), hover `--s3`, cursor line spans lanes |
| 5 | **vmbr0 bridge topology** SVG (viewBox 520×190): trunk line in `--net`, drops to instances alternating above/below, `pve` root dot in `--ink`, instances as `--ok` dots, `--err` ring = killswitch, `--ice` dot = frozen, dashed drop = frozen, `tailnord` → `internet` in `--ok`; legend LAN / tailnet / killswitch |
| 4 | **Storage · ZFS** three **pool rings** (full circle, r=48 sw=9, `rotate(-90)`, dash `301.6*pct/100 400`, colour `--err` when >85% else `--disk`), percent centre, pool name + `used / size TB` |
| 5 | **GPU utilization heatmap** two 96-cell rows (GPU 0 / GPU 1) with 44px label column, at-cursor readout, tick row |
| 3 | **Operations** list (kind, target, 48px progress bar in `--brand2`, age) + divider + **events** feed (52px mono timestamp, kind in ink, text muted) |

Also: `⌘K` command palette overlay (section 4.12), theme picker, time-range segmented control, "live · HH:MM" indicator.

### 3.2 "A2 Instance ai" (secondary screen, Terminal tab)
Same header (stats become per-instance: CPU limit, Memory, GPU 0/1 util·VRAM, NVLink, Killswitch armed) → primary nav → 72px **page title bar** (breadcrumb `Instances /`, 28px name with glowing status dot, meta line, profile chips `default` `gpu` `killswitch`, **action button group** Stop / Restart / Freeze / Snapshot / Copy / ⋯) → 40px sub-nav → grid `1fr 400px`:
- **Terminal panel**: 36px toolbar (`exec · /bin/bash · 132×38 · operations/77be…/websocket`, New tab / Split / Paste), inset well with `white-space:pre` mono 13px lines, prompt `root@ai` in `--brand2`, live `<input>`.
- Right column: **CPU sparkline** (600×60 viewBox, 56px tall) + **GPU 0·1 utilization** lines + two **VRAM bars** (6px, `--hot`/`--disk`); **Devices** table (name / type in mono `--brand2` / detail); **Snapshots** table (name / created / size, header "@daily · expire 14d").

Pages Images, Profiles, Networks, Storage, Operations, Settings are named but not drawn.

## 4. Component inventory (inline recipes, verbatim)

4.1 **Raised panel** (all cards): `background:var(--s1);border:1px solid var(--line);border-radius:6px;box-shadow:0 8px 24px -14px var(--shadow);padding:12px 14px` (dense variant `padding:10px 14px 12px`; token cards `padding:24px`). Header row: `display:flex;justify-content:space-between;align-items:baseline`, title `font-weight:500`, subtitle `<span style="color:var(--muted);font-weight:400">· …</span>`, right value mono in metric colour.

4.2 **Inset chart well**: `background:var(--s2);border-radius:4px;box-shadow:inset 0 1px 3px var(--shadow);overflow:hidden;position:relative`. Terminal well adds `margin:10px;padding:12px 14px`. Topology well `margin:0 14px 12px`.

4.3 **Chart** (SVG): `viewBox="0 0 600 140"` (or `600 60` sparkline) `preserveAspectRatio="none"`, `width:100%;height:100%;display:block`; gridlines `stroke:var(--line)` `stroke-dasharray="2 4"`; area `fill:color-mix(in oklch, var(--cpu) 20%, transparent)`; line `stroke:var(--cpu);stroke-width:1.5;vector-effect:non-scaling-stroke`; cap line `stroke:var(--err) stroke-dasharray="4 4"`. **Crosshair**: `position:absolute;top:0;bottom:0;width:1px;background:var(--ink);pointer-events:none;left:{{ cursorPct }}%;opacity:{{ cursorOn }}`. Tick row: `display:flex;justify-content:space-between;font-family:'JetBrains Mono';font-size:11px;color:var(--muted)`.

4.4 **Ring gauge (270°)**: `<svg viewBox="0 0 120 120" style="width:118px;height:118px"><circle cx=60 cy=60 r=46 fill=none stroke-width=10 stroke=var(--s2) stroke-dasharray="217 289" transform="rotate(135 60 60)" stroke-linecap=round/><circle … stroke={{color}} stroke-dasharray="{{ (217*min(1,v/max)).toFixed(1) }} 400" …/></svg>`; overlay value `position:absolute;top:36px`, 24px mono + glow, 11px muted caption. **Pool ring (360°)**: r=48 sw=9, `rotate(-90 60 60)`, no linecap, 104px, 20px mono centre.

4.5 **Heat strip / heatmap**: `display:grid;grid-template-columns:repeat(96,1fr);gap:1px;height:11px;border-radius:2px;overflow:hidden` (lane) or `border-radius:3px` rows in a `44px 1fr` grid (GPU heatmap). Cell colour from `heatColor()` (section 6).

4.6 **Instance lane row**: `<a>` `display:grid;grid-template-columns:150px 1fr 56px 96px;gap:12px;align-items:center;padding:0 14px;height:21px;color:var(--ink);background:{{ rowBg }}` hover `background:var(--s3)`, focus `outline:2px solid var(--brand2);outline-offset:-2px`. Column header uses the same grid with `padding:10px 14px 6px`. Cursor line for lanes: `left:calc(176px + (100% - 176px - 190px) * {{ cursorFrac }})`.

4.7 **Status dot**: `width:7px;height:7px;border-radius:50%;background:{{ dotBg }};border:1.5px solid {{ dotBorder }};box-sizing:border-box` — running `[ok, ok]`, frozen `[ice, ice]`, stopped `['transparent', muted]`. Legend size 10px. Live indicator: `width:8px;height:8px;border-radius:50%;background:var(--ok);box-shadow:0 0 8px var(--ok)`.

4.8 **Progress / meter bar**: track `height:5px;border-radius:2px;background:var(--s2)`; fill `display:block;height:100%;border-radius:2px;background:var(--mem)|var(--brand2)|var(--hot)|var(--disk);width:{{pct}}%`. VRAM variant `height:6px`.

4.9 **Header stat readout**: cell `padding:9px 14px;border-right:1px solid var(--line);display:flex;flex-direction:column;justify-content:center;gap:2px;min-width:0;overflow:hidden;white-space:nowrap`; label `color:var(--muted);font-size:12px`; value `font-family:'JetBrains Mono';font-size:18px;color:var(--cpu);text-shadow:var(--glow)`; unit `<span style="font-size:11px;color:var(--muted);text-shadow:none">`.

4.10 **Buttons**
- Theme finish button (large): `display:flex;align-items:center;gap:10px;height:40px;padding:0 14px 0 10px;border-radius:6px;font:inherit;font-size:14px;cursor:pointer;color:var(--ink);background:var(--s1);border:1px solid {{ active ? brand2 : line2 }}` + 20px swatch `border-radius:4px;border:1px solid var(--line2)`.
- Theme swatch button (header): `width:22px;height:22px;border-radius:3px;background:{{ swatch }};border:1px solid {{ border }}` inside tray.
- Segmented control tray: `display:flex;gap:4px|2px;padding:3px;background:var(--s2);border-radius:5px;box-shadow:inset 0 1px 2px var(--shadow)`.
- Range button: `font-family:'JetBrains Mono';font-size:12px;height:24px;padding:0 10px;border:0;border-radius:3px;background:{{ active ? var(--brand) : transparent }};color:{{ active ? #fff : var(--muted) }}`; refresh label `↻ 15s` alongside.
- ⌘K trigger: `height:32px;padding:0 12px;background:var(--s2);border:1px solid var(--line);border-radius:4px;color:var(--muted);font-size:13px;box-shadow:inset 0 1px 2px var(--shadow)` hover `color:var(--ink);border-color:var(--brand)`; inner **kbd** `font-family:'JetBrains Mono';font-size:11px;padding:1px 5px;border:1px solid var(--line2);border-radius:3px`.
- Action button group: wrapper `display:flex;gap:1px;background:var(--line);border:1px solid var(--line);border-radius:4px;overflow:hidden;box-shadow:0 4px 12px -8px var(--shadow)`; each `height:32px;padding:0 14px;background:var(--s1);border:0;color:var(--ink);font:inherit` hover `background:var(--s3)`.
- Palette result row: `display:grid;grid-template-columns:72px 1fr auto;gap:12px;align-items:center;padding:0 16px;height:38px;border:0;background:{{ selected ? var(--s3) : transparent }};color:var(--ink);text-align:left` hover `background:var(--s3)`.

4.11 **Chips / badges**: profile chip `padding:2px 8px;border-radius:3px;background:var(--s3);font-size:12px`; semantic chip `background:color-mix(in oklch, var(--ok) 22%, transparent);color:var(--ok)`; nav count badge `font-family:'JetBrains Mono';font-size:11px;color:#fff;padding:0 5px;border-radius:3px;background:var(--brand)`; artboard id chip `font-size:12px;padding:3px 8px;border:1px solid var(--line2);border-radius:3px`.

4.12 **Command palette (modal)**: scrim `position:absolute;inset:0;z-index:5;background:var(--scrim);display:flex;justify-content:center;padding-top:120px` (click closes); dialog `role="dialog" width:560px;background:var(--s1);border:1px solid var(--brand);border-radius:8px;box-shadow:0 24px 60px -20px var(--shadow);overflow:hidden`; input row `height:48px;padding:0 16px;border-bottom:1px solid var(--line)` with `›` in `--brand2`, `<input>` `background:transparent;border:0;outline:0;color:var(--ink);font:inherit;font-size:15px`, placeholder `stop jellyfin · open terminal on ai · pull debian/12`, `esc` hint; footer `padding:8px 16px;border-top:1px solid var(--line);font-size:12px;color:var(--muted)` → `↑↓ move · ↵ run · N matches`.

4.13 **Tables / lists** (no `<table>`; CSS grids, radius 0): operations `1fr 48px 32px`; events `52px 1fr`; devices `60px 40px 1fr`; snapshots `1fr auto auto`; all `font-size:12px;gap:8–12px`. Divider `border-top:1px solid var(--line);padding-top:8px`.

4.14 **Terminal**: panel toolbar `height:36px;border-bottom:1px solid var(--line);color:var(--muted);font-size:12px`; well `font-family:'JetBrains Mono';font-size:13px;line-height:1.45;white-space:pre;display:flex;flex-direction:column;justify-content:flex-end`; line `min-height:1.45em`; prompt `root@ai` in `--brand2`; input `background:transparent;border:0;outline:0;color:var(--ink);font:inherit;padding:0`.

4.15 **Inputs / toggles / toasts**: only the two transparent text inputs above exist. **No form controls, toggles, checkboxes, selects, or toasts are drawn.** Interactive state is `aria-pressed` on buttons.

4.16 **Topology SVG**: trunk `stroke-width:2 stroke:var(--net)`, drops `1.5`, tailnet path `2.5 stroke:var(--ok)`, node `r=6`, killswitch ring `r=10 stroke-width=2 stroke:var(--err)`, host dot `r=5 fill:var(--ink)`, internet `r=7` outlined `--ok`; labels `font-size=12 font-weight=500 fill:var(--ink)` (frozen node label `--muted`), throughput label `font-size=10 fill:var(--muted)`.

## 5. Logo mark and wordmark

Chosen mark is "1 · Cathode N" ("Refined: mark 1 in the NixOS pair — electrodes in #5277C3, discharge in #7EBAE4"). Note the canvas serialises `viewBox` as `sc-camel-view-box`; restore it to `viewBox` in real HTML.

**Mark (canonical, 72 viewBox):**
```html
<svg width="72" height="72" viewBox="0 0 72 72" fill="none"><rect x="10" y="10" width="11" height="52" rx="3" fill="#5277c3"></rect><rect x="51" y="10" width="11" height="52" rx="3" fill="#5277c3"></rect><circle cx="27" cy="20" r="4.5" fill="#7ebae4"></circle><circle cx="33" cy="31" r="4.5" fill="#7ebae4"></circle><circle cx="39" cy="42" r="4.5" fill="#7ebae4"></circle><circle cx="45" cy="53" r="4.5" fill="#7ebae4"></circle></svg>
```
**Header variant** (26px, dots `r="5"`):
```html
<svg width="26" height="26" viewBox="0 0 72 72" fill="none"><rect x="10" y="10" width="11" height="52" rx="3" fill="#5277c3"></rect><rect x="51" y="10" width="11" height="52" rx="3" fill="#5277c3"></rect><circle cx="27" cy="20" r="5" fill="#7ebae4"></circle><circle cx="33" cy="31" r="5" fill="#7ebae4"></circle><circle cx="39" cy="42" r="5" fill="#7ebae4"></circle><circle cx="45" cy="53" r="5" fill="#7ebae4"></circle></svg>
```
**Mono on blue** (all `#fff`) on tile `background:#5277c3;border-radius:6px`. **App icon**: 64px tile `border-radius:14px;background:#5277c3` with 44px mark, rects `#fff`, dots `#7ebae4`. **Favicon** (three dots, thicker electrodes) on 32px tile `border-radius:7px`:
```html
<svg width="24" height="24" viewBox="0 0 72 72" fill="none"><rect x="8" y="10" width="14" height="52" rx="4" fill="#fff"></rect><rect x="50" y="10" width="14" height="52" rx="4" fill="#fff"></rect><circle cx="30" cy="24" r="6" fill="#7ebae4"></circle><circle cx="36" cy="36" r="6" fill="#7ebae4"></circle><circle cx="42" cy="48" r="6" fill="#7ebae4"></circle></svg>
```
Alternates explored (2 Leaning N, 3 Segment n, 4 Solid N, 5 Gauge, 6 Meter) are in the source at template lines 77–81; not chosen.

**Wordmark**: plain text `nixie` (lowercase), Archivo, `font-weight:600;letter-spacing:-0.03em;line-height:1`; sizes `60px` (lockup, gap 22px to 60px mark), `26px` (gap 12px to 52px mark, stacked), `20px` in the header (gap 12px to 26px mark). "Wordmark is plain; no lit dots."

## 6. JavaScript behaviour

- **Theme switching**: `THEMES` object keyed `graphite|umber|paper`; component state `theme` (initial from canvas prop `theme`, default `'graphite'`), `renderVals()` returns `t` and the artboard root binds each key to `--x`. Picker buttons call `setState({theme:k})`; active swatch border `t.brand2` else `t.line2`. `glow` prop false → `--glow:'none'`.
- **Keyboard**: `Cmd/Ctrl+K` toggles palette (resets query/selection), `Escape` closes; inside palette `ArrowDown/ArrowUp` move selection, `Enter` runs — `Set range…` → range 360, `Toggle light…` → paper⇄graphite. Terminal `Enter` runs `termRun`.
- **Command palette data**: `commands()` = "Go to <Page>" ×8 (hint `g <letter>`), per instance: Open / Open terminal on / Start|Stop / Restart / Snapshot / Dashboard for; plus Pull debian/12, Pull ubuntu/24.04, Create instance (`n`), Toggle light theme (`t`), Set range: last 6h (`r 6h`). `filterCommands`: all words must be substrings of label, max 9 results.
- **Demo data** (`window.__nixieDemo`, seeded, 24 h × 1-min, `N=1440`, `NOW=2026-09-10 21:40`): mulberry32-style `rng(seed)`; `walk(seed,base,amp,min,max,spike)` mean-reverting random walk; `bursty(seed,lo,hi,minLen,maxLen)` on/off square bursts (GPU util); host CPU = base walk + 0.55 × Σ instance CPU. Fixtures: `HOST`, `GPUS`, `POOLS`, `INSTANCES` (10), `RANGES` (`15m/1h/6h/24h`), `OPERATIONS`, `EVENTS`, `SNAPSHOTS`, `DEVICES_AI`, `CONFIG_AI`, `TERM` (canned responses for `nvidia-smi`, `ls`, `uptime`, `free -h`, `systemctl status vllm --no-pager`, `ip a`, `nvidia-smi nvlink`, `echo`, `help`, `clear`).
- **Charts**: hand-rolled SVG paths, no library. `slice(arr, minutes, points=160)` bucket-averages; `linePath(vals,w,h,min,max,pad=1)` emits `M/L` polyline; `areaPath` closes to baseline. Chart W=600, H=140 (sparklines 60). Lanes/heatmaps use 96 buckets. Time ticks `timeTicks(R,2)` → 3 labels.
- **Crosshair**: `onChartMove` sets `cursor` = fraction of element width; every chart, lane and heatmap renders the same `cursorPct`/`cursorFrac`; readouts show the value `at(series, frac)`; "live · HH:MM" shows `fmtTime`.
- **Heat colour**: `heatColor(v, dark)`: t=clamp(v/100); dark → `oklch(${14+76t}% ${0.17*min(1,1.6t)} ${25+60t})`; light → `oklch(${86-56t}% ${0.02+0.16t} ${80-50t})`. Lane strips feed `v*1.6` for running instances, 0 otherwise.
- Gauge dash: `${217*min(1,v/max)} 400`; pool dash `${301.6*pct/100} 400`; temp colour thresholds 80 (`err`) / 68 (`hot`).

## 7. Layout

- Screen frame: `width:1440px;height:900px;background:var(--bg);border:1px solid var(--line);font-size:13px`.
- **Header**: `height:64px;background:var(--s1);border-bottom:1px solid var(--line);box-shadow:0 6px 18px -12px var(--shadow);display:grid;grid-template-columns:200px 1fr auto;z-index:2`. Brand cell `padding:0 20px;border-right:1px solid var(--line)`; stats `grid-template-columns:repeat(6,1fr)`; right cluster `gap:10px;padding:0 16px`.
- **Primary nav bar**: `height:44px;border-bottom:1px solid var(--line);padding:0 20px`, links `gap:26px`.
- **Instance title bar**: `height:72px;padding:0 20px`. **Sub-nav**: `height:40px;gap:24px`.
- **Page body**: `padding:14px 20px 16px;gap:12px`; Overview grid `repeat(12,1fr)` rows `198px 252px 1fr`; Instance grid `1fr 400px`.
- **No sidebar** (top nav only). **No breakpoints / media queries**; single fixed 1440 layout. Artboard canvas: `width:1560px;padding:56px;gap:56px`.

## 8. Installer / setup wizard

Not present. No "install", "wizard", "setup", or first-run content anywhere in the file. Only the Incus front panel (Overview, Instance/Terminal) is designed; the wizard must reuse the tokens, panel/well recipes and type scale above.

## 9. Completeness counts

| scope | custom properties |
|---|---|
| `:root` static block | 21 |
| artboard inline `--x:{{ t.x }}` bindings | 21 |
| `THEMES.graphite` (CSS-bound keys / total keys) | 21 / 25 (+ label, swatch, ramp, dark) |
| `THEMES.umber` | 21 / 25 |
| `THEMES.paper` | 21 / 25 |
| distinct property names across all scopes | 21 |

No other `--*` declarations exist in the file (the bundler shell's own `<style>` defines none).
