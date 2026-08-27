# RacaBoonMenu

A **Mythical Boon** manager for [Project Ascension](https://project-ascension.com/) Mythic+ dungeons (WoW 3.3.5).

Tracks the Mythical Boons in your bags, shows them as a clean icon grid with live timers, alerts you before an active buff expires, and shares boon availability with your group so everyone knows what's up.

![WoW](https://img.shields.io/badge/WoW-3.3.5-blue) ![Realm](https://img.shields.io/badge/Realm-Project%20Ascension-orange)

---

## Features

- **Live tracking** of every Mythical Boon in your bags — reserve countdown (10 min) and active buff countdown, with stacks shown while the buff is up.
- **One-click reactivation**: click any icon (in reserve or active) to consume another copy and refresh/stack the buff.
- **"Reactivate now!" alerts**: a raid-warning-style banner plus a glow on the icon when an active buff is about to expire and a spare is available (yours or an ally's).
- **Group sharing**: broadcasts your available boons to the party/raid over addon comms. Two dedicated windows show what allies have — a detailed per-player list, and a combined group total per boon type.
- **Duplicate alert**: warns when 2+ players have the same boon type available, so you can coordinate who stacks it.
- **Auto-show**: windows appear automatically when you enter a Mythic (0+) dungeon and hide when you leave.
- **Fully skinnable**: 3 window styles, adjustable opacity, independent icon size/grid/scale per window, lockable positions.
- **French / English** UI, switchable in options.
- **Built-in test tools**: a preview mode and isolated boon/glow simulator so you can tune everything without running a dungeon.

---

## Installation

1. Download the addon and extract the `RacaBoonMenu` folder into `Interface/AddOns/`.
2. Make sure the path looks like `Interface/AddOns/RacaBoonMenu/RacaBoonMenu.toc`.
3. Restart WoW or `/reload`.

---

## The three windows

| Window | What it shows | Clickable? |
|---|---|---|
| **My Mythical Boons** | Your own boons: icon grid, reserve/active timers, stacks, GCD swipe, glow before expiry. | ✅ Yes — this is the only window that uses/consumes boons. |
| **Allies' Available Boons** | A detailed text list, one line per ally, showing which boons they currently have in reserve (requires them to also run the addon and have sharing enabled). | ❌ Informational only. |
| **Total Boons** | The same icon grid as "My Mythical Boons", but showing the **combined group total** per boon type (you + all allies). Greyed out when nobody has it. | ❌ Informational only. |

Each window can be independently shown/hidden, locked, resized, rescaled, and skinned from the options panel.

---

## Slash commands

| Command | Effect |
|---|---|
| `/rbm` | Show/hide all enabled windows. |
| `/rbm options` | Open the options panel. |
| `/rbm lock` | Toggle position lock on all windows (also hides their close button while locked). |
| `/rbm preview` | Toggle preview mode (simulates all boons + fake allies + a demo active buff, for tuning layout without a dungeon). |
| `/rbm reset` | Reset all window positions to their defaults. |
| `/rbm debug` | Toggle debug printouts (useful for troubleshooting boon detection). |
| `/rbm addboon Mythical Boon: ExactName` | Manually register a boon that isn't in the built-in list, using its exact in-game item name. |

A minimap icon is also available: **left-click** opens options, **right-click** toggles windows, **drag** to move it.

---

## Options reference

Everything below lives in `/rbm options`, organized exactly as it appears in-game.

### Icons — My Mythical Boons / Total Boons
- **Icon size** (20–56) and **Icons per row** (3–13) — set independently for each of the two icon-grid windows. Changes to "My Mythical Boons" are deferred to the end of combat if needed (secure buttons); "Total Boons" applies instantly (not combat-restricted).

### Scale of each window
- Independent scale sliders (0.5–2.0) for **My Mythical Boons**, **Allies' Available Boons**, and **Total Boons**.
- **Options panel** scale (0.5–1.5) — resizes the options window itself. Applied when you release the slider (not live-dragged, to avoid the panel shrinking under your cursor mid-drag).

### Window appearance
- **Style**: Minimal (transparent), Classic (Blizzard dialog look), or Dark (opaque).
- **Lock position** — also hides each window's close button while locked, to prevent accidental closing.
- **Show total boon count in the title** — appends the combined reserve count to "My Mythical Boons"'s title.
- **Show title "…"** — three separate toggles, one per window, to hide/show its title text independently.
- **Window opacity** (0–1) — background/border transparency for all three windows.
- **Language** — Français / English. Changing it updates new text immediately; a `/reload` is recommended to refresh everything already on screen.

### Announcements
- **Announce on pickup** / **Announce on use** — posts a chat message when you loot or consume a boon.
- **Channel** — `/say` or `/p` (party/raid).

### Automation
- **Share my Boons with the group** — broadcasts your reserve to the party over addon comms (required for the two ally windows and duplicate alerts to work).
- **Auto-show in Mythic (0 or +)** — automatically shows enabled windows when entering a Mythic-difficulty dungeon, hides them on leaving.
- **Alert when a boon is duplicated in the group** — raid-warning when 2+ players have the same boon type available.
- **Enable the "Allies' Available Boons" window** / **Enable the "Total Boons" window** — independent on/off switches for each window.

### Preview
- **Enable preview** — simulates every boon in reserve, two fake allies, and one demo active buff, so you can tune size/grid/position without a dungeon.
- **Test alerts** — instantly fires both the "reactivate now" alert and the "duplicate boon" alert with fake data.
- **Simulate 1 boon (30s, see the glow)** — isolates a single boon (doesn't touch the other 12), makes it active for 30 seconds with a simulated ally holding the same boon, so you can watch the full sequence: normal display → glow trigger → alert, in real conditions.

---

## Known limitations

- Ally windows only show players who are **also running RacaBoonMenu** with sharing enabled — there's no way to detect boons on players without the addon.
- The addon cannot force which specific item instance a stacked boon click consumes (that's decided server-side); it can only tell you *when* to click.
- A custom boon added via `/rbm addboon` won't have a built-in icon in the ally-facing windows if its name doesn't match a known entry — the label still displays correctly, just without an icon for that specific case.

---

## Credits

Developed for **Racaillorc** and the Ascension raid community.
