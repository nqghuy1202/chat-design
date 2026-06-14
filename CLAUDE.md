# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A **UI design prototyping workspace** for a Zalo-style fullscreen modal chat interface. The primary deliverable is `index.html` — a self-contained, browser-runnable demo. The eventual production target is React + Tailwind CSS.

## Viewing the Demo

```
Start-Process "D:\chat-design\index.html"   # PowerShell
start index.html                             # Git Bash / cmd
```

No build step, no npm install, no dev server. `index.html` uses Tailwind CDN and Google Fonts via `<link>` tags directly.

## Architecture of index.html

Single file. Structure top-to-bottom:

1. `<head>` — Google Fonts (Outfit 300–700), Tailwind CDN
2. `<style>` block — all custom CSS (Tailwind handles layout; custom CSS handles animations, component-specific styles)
3. `<body>` — three sections:
   - Backdrop + reopen button (fixed overlays)
   - Modal container with three panels (left / center / right)
   - `<script>` block — all vanilla JS

### Three-panel layout

```
Modal Container (fixed, rounded-2xl, max-w-1360px)
├── Left Panel  (268px, #F8FAFC) — conversation list + new-conversation flow
├── Center Panel (flex-1, white) — active chat thread
└── Right Panel (272px, #FAFAFA) — contact info, collapsible
```

### Left Panel: 4-screen slider

The left panel hosts a horizontal slider (`#lp-track`) that translates on the X axis to reveal screens. All screens are 268px wide and live side-by-side in a flex row inside `#lp-track`.

| Screen | translateX | ID | Purpose |
|---|---|---|---|
| S1 | `0` | `#lp-s1` | Conversation list (default) |
| S2 | `-268px` | `#lp-s2` | New Conversation — DM contact picker |
| S3 | `-536px` | `#lp-s3` | Add Members — group multi-select (step 1/2) |
| S4 | `-804px` | `#lp-s4` | Group Info — name + avatar + description (step 2/2) |

Navigation flow: S1 → S2 (via `openNewConv()`), S2 → S1 (via `lpBack()`), S2 → S3 (via `lpOpenGroup()`), S3 → S2 (via `lpGroupBack()`), S3 → S4 (via `lpGroupNext()`), S4 → S3 (via `lpGroupInfoBack()`), S4 → S1 on create (via `lpGroupCreate()`).

Transition: `transform 0.32s cubic-bezier(0.16,1,0.3,1)` on `#lp-track`.

Contact data lives in `NC_CONTACTS` (array of 24 objects: `{ id, name, ini, color, online }`). Group member selection state is `grpSel` (a `Set` of contact IDs).

### Conversation list item structure

Each item in `#lp-conv-list` is a `<button class="dm-item">` with this internal layout:

```
[avatar]  [name]                    [.dm-ts-area]   ← top row
          [last message truncated]  [badge?]         ← bottom row
```

`.dm-ts-area` (top-right) contains two overlapping children:
- `.dm-ts` — the timestamp span (visible by default, fades on hover)
- `.dm-menu-btn` — a `<div role="button">` with 3-dot icon (hidden by default, appears on hover)

On `.dm-item:hover`: timestamp fades to 0, menu button appears. When menu is open, `.dm-item` gets class `menu-open` to keep the button visible and highlighted.

The unread badge lives in the **bottom row** alongside the last message, not the top row.

**Critical:** the outer `dm-item` is itself a `<button>`. Any interactive child element MUST use `<div role="button">` or `<span>`, never `<button>`. Nested `<button>` inside `<button>` is invalid HTML — the browser ejects the inner element and breaks the layout.

### Conversation context menu (`#conv-menu`)

A single `<div id="conv-menu" class="conv-menu">` lives at the end of `<body>`, outside all panels (position: fixed, z-index: 9999). It is populated dynamically by `openConvMenu()` and positioned via `getBoundingClientRect()` of the clicked `.dm-menu-btn`.

Menu items for all conversation types: Ghim hoi thoai, An cuoc tro chuyen, Xoa hoi thoai (danger).
DM-only additional item: Them vao nhom — calls `convAddToGroup()` which pre-selects the contact in S3 by matching `NC_CONTACTS` by name, then slides LP to S3.

State variable `_convMenuId` tracks which conversation's menu is open. Menu closes on: click outside, Escape keydown, or `#lp-conv-list` scroll.

### Center Panel

Chat header → scrollable `#messages` div → input row with formatting toolbar. Messages use a grouped format: the first message in a consecutive sequence from the same sender gets a full row (avatar + name + timestamp); subsequent messages are indented only.

### Right Panel

Four collapsible sections toggled with `toggleSection()`. Panel visibility toggled via the profile icon button in the center header (`toggleRightPanel()`).

## Data

- `CONV_DATA` — array of conversation objects. Each has `{ id, type, name, ini, ... }`. `type` is `'dm'`, `'group'`, or `'voucher'`.
- `activeConvId` — string ID of the currently selected conversation.
- `NC_CONTACTS` — 24 contacts for the New Conversation flow `{ id (number), name, ini, color, online }`. DM convs in `CONV_DATA` share names with some NC_CONTACTS entries (e.g. 'Linh Tran' → id 12, 'Minh An' → id 15).
- `grpSel` — `Set` of NC_CONTACTS numeric IDs currently selected in S3.
- `_convMenuId` — string conv ID of the currently open context menu, or `null`.

## JS Function Reference

| Function | What it does |
|---|---|
| `openNewConv()` | Slide LP to S2 (DM picker) |
| `lpBack()` | Slide LP to S1 |
| `lpOpenDM(id)` | Open DM with contact, return to S1 |
| `lpRenderContacts(q)` | Render A-Z contact list in S2 |
| `lpOpenGroup()` | Reset group state, slide LP to S3 |
| `lpGroupBack()` | Slide LP to S2 |
| `lpRenderGroupContacts(q)` | Render multi-select list in S3 |
| `lpGroupToggle(id)` | Toggle contact selection in S3 |
| `lpGroupRenderChips()` | Render selected-member chips in S3 |
| `lpGroupRemove(id)` | Remove a member chip in S3 |
| `lpGroupUpdateFooter()` | Update count label + enable/disable Next button |
| `lpGroupNext()` | Validate S3 selection, reset S4, slide to S4 |
| `lpGroupInfoBack()` | Slide LP to S3 |
| `lpUpdateGroupAvatar()` | Live avatar preview from group name input |
| `lpGroupCreate()` | Create group, clear state, return to S1 |
| `openConvMenu(id, type, e)` | Open context menu for a conversation item |
| `closeConvMenu()` | Close the context menu and clear `menu-open` state |
| `convPin(id)` / `convHide(id)` / `convDelete(id)` | Stub handlers for menu actions |
| `convAddToGroup(convId)` | Pre-select DM contact in S3, slide LP to S3 |
| `renderConvList()` | Re-render the full conversation list in S1 |
| `selectConv(id)` | Set active conv, re-render list + center + right panel |
| `sendMessage()` | Append message to `#messages`, clear input |
| `toggleRightPanel()` | Show/hide right panel |
| `toggleSection(sectionId, header)` | Collapse/expand a right panel section |
| `toggleSwitch(el)` | Toggle the mute/pin/block switches |
| `copyCode(btn)` | Copy code block content to clipboard |
| `toggleReaction(btn)` | Toggle existing reaction on a message |
| `addReaction(btn)` | Add reaction from emoji picker |
| `openModal()` / `closeModal()` | Show/hide the chat modal overlay |

## Design System

- **Font:** Outfit (Google Fonts, weights 300–700) — never substitute Inter or any other font
- **Accent:** `#2563EB` (Blue-600) — active states, badges, send button, "You" pill, S3/S4 action buttons
- **Sidebar / left panel bg:** `#F8FAFC`
- **Main chat bg:** white
- **Right panel bg:** `#FAFAFA`
- **Borders:** `#E2E8F0` between panels, `#F1F5F9` within sections
- **Text scale:** 13–13.5px body, 10–11px metadata/timestamps
- **Corner radii:** modal `rounded-2xl`, messages `10px`, cards `12px`, input `14px`, send button `9px`, LP group next button `10px`, context menu `10px`, menu items `7px` — do not mix arbitrarily
- **Step indicator pills:** blue `#EFF6FF / #2563EB` for "1/2", green `#F0FDF4 / #16A34A` for "2/2"
- **Context menu shadow:** `0 4px 20px rgba(15,23,42,0.08), 0 1px 4px rgba(15,23,42,0.04)` — two-layer, tinted to near-black not pure black

## Installed Skills

Skills are in `.agents/skills/` and tracked in `skills-lock.json`. All from `Leonxlnx/taste-skill` on GitHub.

| Skill | When to use |
|---|---|
| `design-taste-frontend` | Any new UI design task — invoke first, declare Design Read + Dials |
| `high-end-visual-design` | Supplements design-taste-frontend for premium polish |
| `redesign-existing-projects` | When refactoring existing sections of index.html |
| `minimalist-ui` | If a cleaner/stripped-back direction is requested |
| `stitch-design-taste` | Stitch-specific design guidance |
| `image-to-code` | Implement UI from a screenshot or mockup |

To update skills: `npx skills check` then `npx skills update`.

## Key Constraints

- **No channels.** Left panel is DM/group conversations only — never add # channel items.
- **No dark mode** unless explicitly requested.
- **No Inter font.** Outfit only.
- **No em-dashes (`—`)** anywhere in visible UI text (skill rule, strictly enforced).
- **No modal overlays for multi-step flows** — use the left panel slider pattern (S3/S4) instead. The `#nc-overlay` has been removed; do not recreate it.
- **No nested `<button>` inside `<button>`** in any dynamically generated HTML string — use `<div role="button">` for interactive children of `.dm-item`.
- When converting to React: each panel = its own component; right panel toggle state lives at root layout level; LP slider state (`currentScreen`, `grpSel`) lives in the left panel component; message grouping logic (consecutive same-sender = no avatar) must be preserved; `#conv-menu` becomes a portal rendered at document root.
