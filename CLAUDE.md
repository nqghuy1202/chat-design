# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A **UI design prototyping workspace** for a Zalo-style fullscreen modal chat interface embedded in a multi-module ERP system (accounting, HR, production, management). B2B SaaS product. The primary deliverable is `index.html` — a self-contained, browser-runnable demo. The eventual production target is React + Tailwind CSS.

## Viewing the Demo

```powershell
Start-Process "C:\chat-design\index.html"   # PowerShell
start index.html                             # Git Bash / cmd
```

No build step, no npm install, no dev server. `index.html` uses Tailwind CDN and Google Fonts via `<link>` tags directly.

## Architecture of index.html

Single file (~3600+ lines). Structure top-to-bottom:

1. `<head>` — Google Fonts (Outfit 300–700), Tailwind CDN
2. `<style>` block — all custom CSS. Tailwind handles layout; custom CSS handles animations, component-specific styles. **New rules go before `/* ===== NGU HANH THEME OVERRIDES =====*/`**. Theme overrides go after that marker.
3. `<body>` — four layers:
   - Backdrop + reopen button (fixed overlays)
   - Modal container với ba panel (left / center / right)
   - Fixed overlays outside modal: `#global-search`, `#forward-modal`, `#shortcuts-modal`, `#task-toast`
   - `<script>` block — all vanilla JS

### Three-panel layout

```
Modal Container (fixed, rounded-2xl, max-w-1360px, position:relative)
├── Left Panel  (268px, #F8FAFC) — conversation list + new-conversation flow
├── Center Panel (#center-panel, flex-1, white, position:relative) — active chat thread
└── Right Panel (272px, #FAFAFA) — contact info, collapsible
```

### Left Panel: 4-screen slider

`#lp-track` translates on X axis. All screens 268px wide in a flex row.

| Screen | translateX | ID | Purpose |
|---|---|---|---|
| S1 | `0` | `#lp-s1` | Conversation list with sections |
| S2 | `-268px` | `#lp-s2` | New Conversation — DM contact picker |
| S3 | `-536px` | `#lp-s3` | Add Members — group multi-select (step 1/2) |
| S4 | `-804px` | `#lp-s4` | Group Info — name + avatar + description (step 2/2) |

Navigation: S1→S2 (`openNewConv()`), S2→S1 (`lpBack()`), S2→S3 (`lpOpenGroup()`), S3→S2 (`lpGroupBack()`), S3→S4 (`lpGroupNext()`), S4→S3 (`lpGroupInfoBack()`), S4→S1 on create (`lpGroupCreate()`).

**S1 conversation list** is rendered with sections by an IIFE that overrides `renderConvList()` at the bottom of the script. Sections: `Tin nhắn trực tiếp` / `Nhóm` / `Chứng từ ERP` / `Thông báo & Bot`. A `c.pinned` flag creates a `Ghim` section if present.

### Conversation list item structure

Each `#lp-conv-list` item is `<button class="dm-item">`. Interactive children (3-dot menu) MUST use `<div role="button">`, never `<button>` — nested buttons are invalid HTML and break layout.

### Conversation types

`CONV_DATA` items have `type`: `'dm'` | `'group'` | `'voucher'` | `'bot'`.

| Type | Avatar shape | Right panel renderer |
|---|---|---|
| `dm` | circle | `renderRPDM(conv)` |
| `group` | rounded square | `renderRPGroup(conv)` |
| `voucher` | rounded square | `renderRPVoucher(conv)` |
| `bot` | rounded square, blue gradient | `renderRPBot(conv)` |

`updateCenterHeader(conv)` handles all four types. When adding a new type, update both functions.

### Center Panel layout

```
#center-panel (position:relative)
├── #drop-overlay (absolute fill, shown on file dragenter)
├── Chat Header (64px)
├── #pin-banner (hidden by default, shown via .visible class)
├── Messages wrapper (flex-1, position:relative, overflow:hidden)
│   ├── #messages (absolute inset-0, overflow-y:auto)
│   └── #jump-latest (.jump-latest-btn, shown via .visible when scrolled up 180px+)
└── Input Area
    └── .input-box
        ├── #file-preview-bar (shown via .has-files when files pending)
        ├── #reply-preview (shown via .rp-active)
        ├── Formatting toolbar
        ├── #chat-input (contenteditable)
        └── Bottom row (attach / image / .emoji-picker-wrap / mention / send)
```

### Message action buttons

Each `.message-group` has `.msg-actions` with 3 buttons wired by `initMsgIds()`:
- btn[0]: React (emoji)
- btn[1]: `data-action="reply"` → `startReply(btn)`
- btn[2]: `data-action="forward"` → `openForwardModal(btn)`

`initMsgIds()` must be called after every `updateMessages()` (already done).

### Reply feature

`replyTo = null | { id, senderName, content, type }`. `#reply-preview` gets `.rp-active` when set. `sendMessage()` reads `replyTo` and injects a quote block. Quote styles: `.reply-quote-me` (semi-transparent rgba whites, works on any theme), `.reply-quote-other` (themed via CSS vars).

### Right Panel

Collapsible sections via `toggleSection()`. Toggled via profile icon (`toggleRightPanel()`).

### Fixed overlays (outside modal, z-index 9998–9999)

| Element | Trigger | Close |
|---|---|---|
| `#global-search` | Ctrl+K / LP search click | Esc / click backdrop |
| `#forward-modal` | `data-action="forward"` on msg | Esc / click backdrop / Cancel |
| `#shortcuts-modal` | Ctrl+/ / settings button | Esc / click backdrop |
| `#lightbox` | click `.img-card` | Esc / click backdrop |
| `#conv-menu` | `.dm-menu-btn` click | click outside / Esc / list scroll |

### Global Search (`#global-search`)

`SEARCH_INDEX` array indexes people, groups, messages, files, vouchers. `doSearch(q)` filters and renders grouped results. `gsOpen(convId)` closes search and calls `selectConv()`.

### Status Picker (`#status-picker`)

`position:absolute` inside the LP user footer row. Five status options (online/busy/meeting/leave/offline) stored in `STATUS_CONFIG`. `setUserStatus(status)` updates the dot color and label text.

### ERP Bot Channel

`type: 'bot'`, id `'erp-bot'`. Messages in `CONV_MESSAGES['erp-bot']` use `.bot-event` card style — inline system event notifications. Right panel via `renderRPBot()`.

### Keyboard Shortcuts

Global `keydown` handler at bottom of script:
- `Ctrl+K` → global search
- `Ctrl+/` → shortcuts modal
- `Alt+Up/Down` → navigate conversations
- `Esc` → close topmost open panel/modal

## Data

- `CONV_DATA` — array of conversation objects. Current IDs: `linh-tran`, `minh-an`, `quan-nguyen`, `thu-ha`, `design-team`, `erp-bot`, `hd-2024-001`, `pc-2024-047`.
- `CONV_MESSAGES` — object keyed by conv ID → static HTML string for that conversation's messages.
- `SEARCH_INDEX` — flat array of searchable items for global search.
- `NC_CONTACTS` — 24 contacts `{ id (number), name, ini, color, online }` for new conversation flow.
- `PINNED_MSGS` — object `{ convId: 'text' }` for pin banner content.
- `THEMES` — `{ kim, moc, thuy, hoa, tho }` each with `{ main, hover, tint, border, medium, dark, focus }`.
- `STATUS_CONFIG` — `{ online, busy, meeting, leave, offline }` each with `{ dot, label, cls }`.
- `activeConvId` — currently selected conversation ID.
- `replyTo` — `null | { id, senderName, content, type }`.
- `grpSel` — `Set` of NC_CONTACTS numeric IDs selected in S3.
- `_pendingFiles` — array of File objects queued in file preview bar.
- `_emojiOpen`, `_dragCounter`, `_convMenuId`, `_fwdSelected`, `_userStatus`, `_msgCounter` — misc state.

## JS Function Reference

### Navigation
| Function | What it does |
|---|---|
| `openNewConv()` | Slide LP to S2 |
| `lpBack()` | Slide LP to S1 |
| `lpOpenDM(id)` | Open DM with contact, return to S1 |
| `lpOpenGroup()` | Reset group state, slide LP to S3 |
| `lpGroupBack()` | Slide LP to S2 |
| `lpGroupNext()` | Validate S3 selection, slide to S4 |
| `lpGroupInfoBack()` | Slide LP to S3 |
| `lpGroupCreate()` | Create group, return to S1 |
| `selectConv(id)` | Set active conv, re-render all three panels |
| `renderConvList()` | Re-render S1 conv list with sections (overridden by IIFE) |

### Chat
| Function | What it does |
|---|---|
| `sendMessage()` | Append message to `#messages`, clear input, cancel reply |
| `startReply(btn)` | Set `replyTo`, show `#reply-preview` |
| `cancelReply()` | Clear `replyTo`, hide preview bar |
| `scrollToMsg(msgId)` | Smooth-scroll + `.msg-highlight` animation |
| `initMsgIds()` | Wire `data-msg-id` and action `data-action` on all message groups |
| `updateMessages(conv)` | Set innerHTML from CONV_MESSAGES, inject unread divider, update pin banner |
| `jumpToLatest()` | Scroll to bottom |

### Overlays & Panels
| Function | What it does |
|---|---|
| `openGlobalSearch()` / `closeGlobalSearch(e)` | Toggle `#global-search` |
| `doSearch(q)` | Filter SEARCH_INDEX, render results in `#gs-body` |
| `openForwardModal(btn)` / `closeForwardModal(e)` | Toggle `#forward-modal` |
| `sendForward()` | Send forward action, show toast |
| `openShortcuts()` / `closeShortcuts(e)` | Toggle `#shortcuts-modal` |
| `openLightbox(src)` / `closeLightbox()` | Toggle `#lightbox` |
| `openConvMenu(id, type, e)` / `closeConvMenu()` | Toggle `#conv-menu` |
| `toggleRightPanel()` | Show/hide right panel |
| `toggleStatusPicker(e)` | Toggle `#status-picker` |
| `setUserStatus(status)` | Update user status dot + label |

### Files & Emoji
| Function | What it does |
|---|---|
| `addFilePreview(file)` | Add thumbnail to `#file-preview-bar` |
| `removeFileThumb(idx)` | Remove a pending file |
| `toggleEmojiPicker(e)` | Toggle `#emoji-picker` |
| `filterEmoji(q)` / `renderEmojiGrid(q)` | Search + render emoji grid |
| `insertEmoji(em)` | Insert emoji at cursor in `#chat-input` |

### ERP / Tasks
| Function | What it does |
|---|---|
| `createTaskFromMsg(btn)` | Extract message text, show task-created toast |
| `showTaskToast(msg)` | Show `#task-toast` for 3.5s |
| `updatePinBanner(conv)` | Show/hide `#pin-banner` based on `PINNED_MSGS` |
| `closePinBanner()` | Hide pin banner |

### Theme & UI
| Function | What it does |
|---|---|
| `applyTheme(name)` | Apply ngũ hành theme — sets CSS vars on `:root` |
| `toggleSection(sectionId, header)` | Collapse/expand right panel section |
| `toggleSwitch(el)` | Toggle mute/pin/block switches |
| `copyCode(btn)` | Copy code block to clipboard |
| `toggleReaction(btn)` / `addReaction(btn)` | Reaction handling |
| `openModal()` / `closeModal()` | Show/hide the chat modal overlay |

## Design System

- **Font:** Outfit (Google Fonts, weights 300–700) — never substitute Inter or any other font
- **Accent:** CSS custom property `--c-main` (default `#2563EB`). Do NOT hardcode accent colors in new rules — use `var(--c-main)`.
- **Left panel bg:** `#F8FAFC` | **Main chat bg:** white | **Right panel bg:** `#FAFAFA`
- **Borders:** `#E2E8F0` between panels, `#F1F5F9` within sections
- **Text scale:** 13–13.5px body, 10–11px metadata/timestamps
- **Corner radii:** modal `rounded-2xl`, messages `10px`, cards `12px`, input `14px`, send button `9px`, context menu `10px`, menu items `7px`
- **Shadows:** overlays use `0 24px 64px rgba(15,23,42,0.22), 0 4px 16px rgba(15,23,42,0.08)`. Context menu uses `0 4px 20px rgba(15,23,42,0.08), 0 1px 4px rgba(15,23,42,0.04)`.

### Ngũ Hành Theme System

`THEMES` object keys: `kim` (#2563EB), `moc` (#16A34A), `thuy` (#B45309), `hoa` (#DC2626), `tho` (#7B4F24). Each has 7 CSS variables: `main, hover, tint, border, medium, dark, focus`.

CSS override layer at the bottom of `<style>` (`/* ===== NGU HANH THEME OVERRIDES =====*/`) wins over base rules. New themed elements: add to that block, never hardcode hex values.

`applyTheme()` also imperatively updates: `#user-avatar` background, `.app-logo-icon` gradient.

### ERP Context Cards (`.erp-card`)

For inline ERP record previews in messages. Structure: header (module badge + status pill) → title → meta row → action buttons row. Use `erpCard(config)` helper if adding new ones. Colors are semantic (`--c-success: #16A34A`, `--c-warning: #D97706`, `--c-error: #DC2626`) not from theme.

## CSS Organization

The `<style>` block is organized in this order:
1. Theme variables (`:root`)
2. Global resets + scrollbar
3. Animations (`@keyframes`)
4. Message / chat components
5. Left panel components
6. Input & toolbar
7. Right panel
8. Modal & overlay components (conv-menu, reply-preview, etc.)
9. Phase 1 additions: unread-divider, jump-latest, drop-overlay, file-preview-bar, emoji-picker, pin-banner, lightbox, skeleton
10. Phase 2–3 additions: global-search, erp-card, status-picker, forward-modal, shortcuts-modal, lp-section-label, bot-event, task-toast
11. `/* ===== NGU HANH THEME OVERRIDES =====*/` — all `!important` accent overrides

## Installed Skills

Skills are in `.agents/skills/` and tracked in `skills-lock.json`.

| Skill | When to use |
|---|---|
| `design-taste-frontend` | Any new UI design task — invoke first, declare Design Read + Dials |
| `high-end-visual-design` | Supplements design-taste-frontend for premium polish |
| `redesign-existing-projects` | When refactoring existing sections of index.html |
| `minimalist-ui` | If a cleaner/stripped-back direction is requested |
| `image-to-code` | Implement UI from a screenshot or mockup |

To update skills: `npx skills check` then `npx skills update`.

## APEX Production Modules

Hai module đã được triển khai thực tế trên Oracle APEX 24.2. Mỗi module là một thư mục độc lập với cấu trúc giống nhau:

```
<module>/
  <module>.html       ← paste vào Static Content Region
  <module>.css        ← paste vào Page → CSS → Inline
  <module>.fgvd.js    ← paste vào Function and Global Variable Declaration
  <module>.onload.js  ← paste vào Execute when Page Loads
  CLAUDE.md           ← hướng dẫn riêng cho module
  docs/
    callbacks.sql     ← PL/SQL Ajax Callbacks tạo trên APEX page
```

### doc-chat/ — Modal chat gắn với chứng từ ERP

- **Page ID:** `10022710201` (APEX Modal Dialog, hardcode trong mọi `apex.server.process`)
- **Mở từ:** ERP page qua `apex.navigation.dialog()` + `sessionStorage.setItem('docChatCtx', ...)`
- **Conv scope:** filter theo `doc_type + doc_no` — chỉ hiện hội thoại liên quan đến chứng từ đó
- **Cross-frame trap:** chạy trong iframe → bind event vào `window.parent.apex.jQuery(window.parent.document)`, không phải `$(document)`
- **Real-time:** SSE → Node.js `http://172.25.10.38:3410` → relay qua `apex:chatEvent` custom event
- **CSS scope:** `#doc-chat-root`
- Chi tiết đầy đủ: `doc-chat/CLAUDE.md` + `doc-chat/docs/`

### messenger/ — Fullscreen messenger (toàn hệ thống)

- **Page type:** APEX Blank Page (Normal, không phải Modal)
- **Conv scope:** tất cả hội thoại của user — không filter doc. `msCreateConv` để `doc_type/doc_no = NULL`
- **DM dedup:** kiểm tra `doc_type IS NULL AND doc_no IS NULL` — tránh nhầm với doc-chat DM
- **Real-time:** cùng Node.js relay, long-poll qua `msChatEvents` callback
- **CSS scope:** `#ms-root`. `height: calc(100vh - 42px)` — điều chỉnh nếu APEX nav cao hơn/thấp hơn 42px
- **JS scope:** IIFE trong `messenger.fgvd.js`, expose `window.ms*` cho onclick handlers trong PL/SQL HTML
- **New conversation flow:** LP slider inline (S1→S2→S3), KHÔNG dùng overlay dialog. Xem bên dưới.
- Chi tiết đầy đủ: `messenger/CLAUDE.md` + `messenger/docs/callbacks.sql`

#### messenger/ Left Panel Slider

`#ms-lp-track` (width: 816px = 272px × 3) slides trong `#ms-left` (overflow: hidden):

| Screen | translateX | ID | Purpose |
|---|---|---|---|
| S1 | `0` | `#ms-lp-s1` | Danh sách hội thoại |
| S2 | `-272px` | `#ms-lp-s2` | Chọn liên hệ DM — click → tạo DM ngay; nút "Tạo nhóm" → S3 |
| S3 | `-544px` | `#ms-lp-s3` | Tạo nhóm: nhập tên + multi-select ≥2 thành viên + nút tạo |

Navigation: `msOpenNewConv()` → S2, `msNewConvBack()` → S1, `msOpenNewGroup()` → S3, `msGroupBack()` → S2. Tạo DM: `msCreateDM(ausId)`. Tạo nhóm: `msCreateGroup()`. **Không dùng overlay/dialog cho bất kỳ flow nào mới.**

#### messenger/ Typing Indicator

`#ms-typing-indicator` nằm giữa `#ms-messages` và `#ms-input-area` trong `messenger.html`. JS render qua `renderTypingIndicator()` trong `messenger.fgvd.js`.

- `_typingUsers` — map `aus_id → { name }`, key timer dạng `aus_id + '_t'`
- `_avatarCache` — map `aus_id → imgUrl` (hoặc `''`). Lần đầu gặp `aus_id` mới → gọi APEX callback `msGetAvatar` (x01=aus_id) để lấy `v_file_name`, cache lại, không gọi lại nữa
- Avatar render qua `avatarHtml(name, ausId, imgUrl, false, 36)` — fallback về chữ cái + màu `hsl` nếu chưa có ảnh
- CSS classes: `.ms-typing-body`, `.ms-typing-dots`, `.ms-typing-label` trong `messenger.css`

**APEX callback #11 `msGetAvatar`** — nhận `x01=aus_id`, trả `{ aus_id, img }`. SQL đầy đủ ở `messenger/docs/callbacks.sql`.

### APEX-specific Rules (áp dụng cho cả hai module)

- **`type="button"` bắt buộc** trên mọi `<button>` tự tạo — trong HTML region, `HTP.p(...)`, và JS-generated HTML. Thiếu `type` → APEX submit form và reload page.
- **`MATERIALIZE` hint** bắt buộc khi `REGEXP_REPLACE` hoặc `INTERVAL` dùng trên remote columns (ORA-02000).
- **ORA-01799:** không dùng subquery trong `LEFT JOIN ... ON (SELECT ...)` — thay bằng scalar subquery trong SELECT hoặc kéo vào CTE.
- **`Connection: close` + `WRITE_RAW`** bắt buộc trong mọi UTL_HTTP POST relay sang Node.js.
- **`HTP.p` vs `HTP.prn`:** dùng `HTP.p` (tự thêm newline). Escape HTML bằng `HTF.ESCAPE_SC`, clean control chars bằng `REGEXP_REPLACE(str,'[[:cntrl:]]','')`.
- **`:APP_USER` auth pattern** bắt buộc đầu mọi callback — kiểm tra `IS NULL OR IN ('nobody','NOBODY')`, sau đó lookup `aus_id` từ `APP_USERS`.

### Shared Database Tables

Cả `doc-chat` và `messenger` dùng chung schema:
- `CHAT_CONVERSATIONS` — `conv_id, conv_type (DM/CHANNEL), name, aus_id, doc_type, doc_no, last_msg_preview, last_msg_date`
- `CHAT_MESSENGERS` — bảng tin nhắn (không phải `CHAT_MESSAGES`)
- `CHAT_PARTICIPANTS` — `conv_id, aus_id, is_admin, last_read_msg_id`
- `CHAT_USER_ONLINE` — `aus_id, last_seen` (presence, cutoff 35 giây)
- `CONV_SEQ` — sequence cho `conv_id`
- `v_employees_v6` — view trả `emp_id, v_file_name` (avatar URL)

## Secondary File: nexus-pure-v2.html

`nexus-pure-v2.html` là bản rewrite của `index.html` không dùng Tailwind CDN — mọi Tailwind class đã được chuyển thành inline styles hoặc CSS rules trong `<style>`. Khi chỉnh sửa file này:

- **Không dùng Tailwind class names** — dùng inline `style=""` hoặc thêm rule vào `<style>` block.
- **Button reset đã có:** `button { border: none; background: transparent; ... }` trong global reset. Tailwind Preflight cung cấp rule này mặc định; pure CSS thì không.
- **Conversation list spacing:** `#lp-conv-list`, `#lp-s2-list`, `#lp-s3-list` dùng `display:flex; flex-direction:column; gap:2px` thay cho Tailwind `space-y-0.5`.
- **Right panel option rows** dùng class `.rp-opt-row` cho hover state (thay cho `hover:bg-slate-50`).

## Right Panel: Voucher (`renderRPVoucher`)

Phần "Luồng phê duyệt" (`apv-timeline`, `apv-step`) đã bị **xóa** khỏi right panel chứng từ. CSS classes `.apv-*` còn trong `<style>` nhưng không được dùng. Nếu cần thêm lại, phải tái tạo cả block JS (map qua `conv.approvers`) lẫn HTML section trong `renderRPVoucher()`.

## Key Constraints

- **No dark mode** unless explicitly requested.
- **No Inter font.** Outfit only.
- **No em-dashes (`—`)** anywhere in visible UI text.
- **No nested `<button>` inside `<button>`** — use `<div role="button">` for interactive children of `.dm-item`.
- **No modal overlays for multi-step flows** — use the LP slider pattern (S3/S4). `#nc-overlay` has been removed; do not recreate it.
- **No hardcoded accent hex** in new CSS rules — always `var(--c-main)`.
- **Reply quote semi-transparency:** `.reply-quote-me` uses `rgba` white overlays so it works on all 5 themes including red and brown.
- **New conversation types:** must update `updateCenterHeader()`, `renderRightPanel()`, `convItemHtml()` in the IIFE, and add a case in the section-based `renderConvList()` override.
- **`renderConvList` is overridden by IIFE** near the bottom of the script. The IIFE immediately calls `renderConvList()` after overriding to sync the initial render.

## React Migration Notes

- Each panel = its own component; right panel toggle state at root layout level
- LP slider state (`currentScreen`, `grpSel`) in left panel component
- `#conv-menu`, `#global-search`, `#forward-modal`, `#shortcuts-modal`, `#lightbox` → portals at document root
- `replyTo` state in center panel component
- `_pendingFiles` state in center panel component  
- Theme (`applyTheme`) → context/store at root
- `SEARCH_INDEX` → would come from API; currently static
- `CONV_MESSAGES` → would be fetched per conversation; currently static HTML strings
- Message grouping logic (consecutive same-sender = no avatar repeat) must be preserved
