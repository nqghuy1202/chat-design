# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A **UI design prototyping workspace** for a Zalo-style fullscreen modal chat interface embedded in a multi-module ERP system (accounting, HR, production, management). B2B SaaS product. The primary deliverable is `index.html` — a self-contained, browser-runnable demo. The eventual production target is React + Tailwind CSS.

Three APEX modules exist alongside the prototypes — see **APEX Production Modules** below. **`chat-erp/` (page `10022710202`) is the current PRODUCTION chat modal as of 2026-06-22.** `messenger/` (page `10022710201`) and `doc-chat/` are kept for **historical reference only** — don't cut over or edit them in parallel unless explicitly asked. Architecture/UX for unified entry + cross-doc awareness is in `docs/unified-chat-architecture.md`; the `DOC` conv_type (hội thoại theo chứng từ) is detailed per-module in `messenger/CLAUDE.md` and `chat-erp/CLAUDE.md`.

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

Ba module Oracle APEX 24.2 nằm trong repo. **`chat-erp/` (page `10022710202`) hiện là module chat PRODUCTION** (cập nhật 2026-06-22, thay cho messenger/). `messenger/` (page `10022710201`) và `doc-chat/` giờ chỉ giữ để **tham khảo lịch sử** — đừng cutover/sửa song song trừ khi được yêu cầu rõ. Mỗi module là một thư mục độc lập với cấu trúc giống nhau:

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

### doc-chat/ — DEPRECATED, không còn dùng song song

`doc-chat/` là bản CŨ, đã bị thay thế hoàn toàn bởi `messenger/`. Page APEX `10022710201` (vốn của doc-chat) giờ **được tái sử dụng cho chính messenger** — không phải 2 page riêng. Đừng đề xuất khôi phục/sửa song song doc-chat; mọi modal chat trong hệ thống giờ là **một mình messenger**, chỉ khác tham số khởi tạo (xem mục Unified Modal Entry bên dưới). Code/docs trong `doc-chat/` giữ lại để tham khảo lịch sử (cross-frame trap, MATERIALIZE pattern, UTL_HTTP pitfalls vẫn đúng và áp dụng chung).

### messenger/ — Modal chat duy nhất (toàn hệ thống + scoped theo chứng từ)

- **Page ID:** `10022710201` (cùng page từng thuộc doc-chat, APEX Modal Dialog — KHÔNG phải Blank Page)
- **3 conv_type:** `DM` (1-1 chung), `CHANNEL` (nhóm chung), `DOC` (tạo từ nút "Trao đổi" ở trang chứng từ — 1-1 hoặc nhóm, bắt buộc `doc_type/doc_no`). DOC dedup theo đúng `conv_type` + đúng chứng từ + đúng đối phương — khác chứng từ hoặc khác conv_type (vd DM chung đã có với A) đều tạo hội thoại DOC riêng. Vì DOC có thể nhóm, mọi nơi hiển thị dùng `is_group = conv_type='CHANNEL' OR (conv_type='DOC' AND member_count>2)` thay vì so trực tiếp `'CHANNEL'`.
- **Conv scope:** mặc định tất cả hội thoại của user; có thể scope theo `doc_type+doc_no` qua Unified Modal Entry (xem dưới). `msCreateConv` để `doc_type/doc_no = NULL` cho hội thoại chung.
- **DM/DOC dedup:** create đi qua Node `/create` vốn KHÔNG dedup → gây tạo trùng. Fix: frontend `msCreateDM` gọi callback `msFindDM` TRƯỚC (nhận thêm `x02=doc_type, x03=doc_no` khi tạo DOC); tìm thấy hội thoại cũ thì mở lại (tự bỏ ẩn / rejoin), chỉ gọi Node `/create` khi thực sự chưa có. `msCreateConv` (APEX) vẫn giữ dedup nội bộ nhưng không còn là đường tạo chính, chỉ hỗ trợ DM/CHANNEL.
- **Real-time:** SSE qua Node.js chat-server (xem mục Chat Server bên dưới) → relay qua `apex:chatEvent` custom event. **Cross-frame trap:** chạy trong iframe → bind event vào `window.parent.apex.jQuery(window.parent.document)`, không phải `$(document)`.
- **CSS scope:** `#ms-root`. `height: calc(100vh - 42px)` — điều chỉnh nếu APEX nav cao hơn/thấp hơn 42px
- **JS scope:** IIFE trong `messenger.fgvd.js`, expose `window.ms*` cho onclick handlers trong PL/SQL HTML
- **New conversation flow:** LP slider inline hợp nhất (S1→S2, mô hình Messenger), KHÔNG dùng overlay dialog. Xem bên dưới.
- Chi tiết đầy đủ: `messenger/CLAUDE.md` + `messenger/docs/callbacks.sql`

#### messenger/ Unified Modal Entry — 2 cửa vào, 1 page

Một mình messenger phục vụ cả "icon tin nhắn ở header hệ thống" (xem tất cả) lẫn "nút Trao đổi ở trang chứng từ" (scoped 1 chứng từ). Phân biệt hoàn toàn qua `sessionStorage['msEntryDoc']` set TRƯỚC khi gọi `apex.navigation.dialog()` — page ID, callback, mọi thứ khác giữ nguyên:

| Cửa vào | `sessionStorage['msEntryDoc']` | `scopeMode` đọc trong `initEntryDoc()` |
|---|---|---|
| Icon header hệ thống | `removeItem` (hoặc không set) trước khi mở | `'ALL'` |
| Nút "Trao đổi" ở chứng từ | `setItem(JSON.stringify({doc_type,doc_no,doc_label}))` trước khi mở | `'DOC'` |

**1 chứng từ có thể có NHIỀU hội thoại** (DM + nhóm cùng `doc_type+doc_no`) — scope DOC lọc cả tập đó, không phải 1 item. Segmented control "Chứng từ này / Tất cả" (`#ms-scope-box`, `msSetScope()`) chuyển qua lại; khi xem "Tất cả" mà có entryDoc, section "Đang xem" ghim hội thoại của chứng từ đó lên đầu danh sách.

**Cross-doc awareness:** đang scope DOC mà có tin nhắn tới hội thoại NGOÀI chứng từ đang xem → banner `#ms-crossdoc-banner` hiện "Tin mới ở chứng từ X → Xem". Dựa vào event `message` đã được **server enrich** thêm `doc_type/doc_no/conv_type/conv_name` (xem mục Chat Server) — frontend không lookup thêm. Badge số lượng theo chứng từ (`#ms-seg-doc-count`) lấy từ Node `GET /api/chat/unread-summary/:aus_id`.

Chi tiết kiến trúc + code mẫu mở dialog: `messenger/CLAUDE.md` mục "Modal hợp nhất: 2 cửa vào + Cross-doc Awareness" và `docs/unified-chat-architecture.md`.

#### messenger/ Left Panel Slider — mô hình Messenger hợp nhất

`#ms-lp-track` (width: 544px = 272px × 2) slides trong `#ms-left` (overflow: hidden). Đã gộp DM picker + group creator thành **một** màn soạn tin theo recipient (không hỏi "DM hay nhóm" trước):

| Screen | translateX | ID | Purpose |
|---|---|---|---|
| S1 | `0` | `#ms-lp-s1` | Danh sách hội thoại |
| S2 | `-272px` | `#ms-lp-s2` | Soạn tin: ô "Tới:" (chips + tìm) + multi-select. 0–1 người → "Nhắn tin" (DM); ≥2 → reveal ô tên nhóm tùy chọn + "Tạo nhóm" (tên trống → auto-sinh) |

Navigation: `msOpenNewConv()` → S2, `msComposeClose()` (✕ / Esc) → S1. Submit: `msComposeSubmit()` chia nhánh DM/nhóm theo số người chọn (`msCreateDM` nội bộ). Click liên hệ = toggle vào ô "Tới:", KHÔNG tạo DM ngay. **Không dùng overlay/dialog cho bất kỳ flow nào mới.**

#### messenger/ Typing Indicator

`#ms-typing-indicator` nằm giữa `#ms-messages` và `#ms-input-area` trong `messenger.html`. JS render qua `renderTypingIndicator()` trong `messenger.fgvd.js`.

- `_typingUsers` — map `aus_id → { name }`, key timer dạng `aus_id + '_t'`
- `_avatarCache` — map `aus_id → imgUrl` (hoặc `''`). Lần đầu gặp `aus_id` mới → gọi APEX callback `msGetAvatar` (x01=aus_id) để lấy `v_file_name`, cache lại, không gọi lại nữa
- Avatar render qua `avatarHtml(name, ausId, imgUrl, false, 36)` — fallback về chữ cái + màu `hsl` nếu chưa có ảnh
- CSS classes: `.ms-typing-body`, `.ms-typing-dots`, `.ms-typing-label` trong `messenger.css`

**APEX callback #11 `msGetAvatar`** — nhận `x01=aus_id`, trả `{ aus_id, img }`. SQL đầy đủ ở `messenger/docs/callbacks.sql`.

#### messenger/ Conversation Dot-Menu (mỗi dòng hội thoại)

Nút 3-chấm trên `.ms-conv-item` (render là `<div role="button">` để tránh nested button). `msOpenConvMenu(id, type, e)` mở `#ms-conv-menu` (fixed overlay). Options: Ghim (`msConvPin` → `msPinConv` toggle `is_pinned`), Ẩn (`msConvHide` → `msHideConv` set `is_hidden`), Thêm vào nhóm (DM, mở S3 preselect), Xóa (`msConvDelete` → `msDeleteConv` xóa participant row = rời hội thoại). Badge unread đỏ `.ms-ci-badge` (`#EF4444`). `msConvListHtml` order `is_pinned DESC` + section "Ghim", filter `is_hidden=0`.

#### messenger/ Message Actions (react / reply / forward / pin)

`msMsgThreadHtml` render mỗi `.ms-msg-row` với `.ms-msg-hover-actions` 4 nút + chip reactions + dấu "Đã ghim".

- **React (quick 6 emoji):** `msOpenReactBar(msgId, e)` → thanh nổi `#ms-react-bar` (👍❤️😆😮😢🙏); `msToggleReaction(msgId, emoji)` (dùng chung cho chip + bar) cập nhật DOM **optimistic** qua `applyReactionDom()` rồi gọi callback `msToggleReaction`. Chip `.mine` = mình đã thả.
- **Forward:** `msOpenForward(msgId, btn)` → `#ms-forward-modal`, list từ `msForwardListHtml`. Gửi qua `nodePost('/send', {conv_id: đích})` ⇒ **real-time đầy đủ** (tái dùng pipeline `/send`).
- **Pin message:** `msTogglePinMsg(msgId)` → callback `msTogglePinMsg`; banner `#ms-pin-banner` (style theo nexus: nền trắng + thanh nhấn xanh + nút tròn) load qua `msPinnedListHtml`; `msJumpToMsg(msgId)` scroll + `.ms-msg-highlight`. Mọi thành viên ghim được; nhiều tin ghim.

**Append-only thread refresh:** `loadThread()` = full load (chuyển hội thoại); `refreshThread()` = chỉ append tin mới (diff theo `data-msg-id`) + animate `.ms-msg-enter`, giữ scroll nếu user đọc lên trên. Gửi/nhận real-time gọi `refreshThread`, KHÔNG vẽ lại cả thread (tránh flicker). Vì refresh chỉ append, react/pin trên tin cũ cập nhật bằng DOM optimistic, không qua refresh.

**Real-time:** Node chat-server SỬA ĐƯỢC (xem mục Chat Server bên dưới — nguồn local tại `C:\greensys\chat-server`, không còn "ngoài repo"). Forward real-time vì dùng `/send`. React/Pin lưu DB + optimistic, đồng bộ cross-client khi thread refresh; muốn tức thời thì backend Node phải broadcast `{type:'reaction'|'pin', conv_id, msg_id}` (`onChatEvent` đã wire sẵn 2 type này).

**Callbacks hiện tại (19):** render HTML (`msConvListHtml` — nay có thêm tham số scope x03-x06, xem Unified Modal Entry ở trên — `msMsgThreadHtml`, `msInfoHtml`, `msContactsHtml`, `msPinnedListHtml`, `msForwardListHtml`), JSON/action (`msGetCurrentUser`, `msConvHeaderJson`, `msCreateConv`, `msFindDM`, `msGetAvatar`, `msPinConv`, `msHideConv`, `msDeleteConv`, `msToggleReaction`, `msTogglePinMsg`), deprecated relay (`msSendMsg`, `msMarkRead`). Send/read/typing/create/unread-summary đi qua `nodePost`/`nodeGet` (fetch thẳng Node, không qua callback APEX). Nguồn chuẩn: `messenger/docs/callbacks.sql`.

### chat-erp/ — Module chat PRODUCTION (page riêng)

- **Page ID:** `10022710202` (production hiện tại; KHÔNG đụng page cũ `10022710201` của messenger/)
- **Real-time dùng CHUNG Node chat-server với messenger/** (cùng instance) nhưng theo cơ chế khác: mọi đọc/ghi DB vẫn qua Ajax Callback APEX; sau khi callback ghi DB xong, BROWSER (không phải DB qua UTL_HTTP, vì máy DB Oracle thường không route tới Node — ORA-12535) tự gọi `nodePost('/broadcast-message')` để phát SSE, nhận lại qua `apex:chatEvent` giống messenger/.
- **4 nhóm sidebar** thay vì 3 `conv_type`: `chungtu`/`channel`/`nhom`/`canhan` — suy ra bằng CASE từ `conv_type` + cột mới `is_public` (KHÔNG có cột `kind` riêng): `chungtu`=`DOC`, `channel`=`CHANNEL`+`is_public=1`, `nhom`=`CHANNEL`+`is_public=0`, `canhan`=`DM`.
- **Nhóm con:** `CHAT_CONVERSATIONS.parent_conv_id` tự tham chiếu, 1 cấp.
- **Channel theo nhóm quyền:** bảng mới `CHAT_CHANNEL_ROLES(conv_id, gus_id)` join `USER_ROLES`/`GROUP_USERS` có sẵn trong hệ thống — không có dòng nào cho 1 `conv_id` = "Toàn công ty" (công khai).
- **Upload file thật** qua callback `msUploadFile` (base64 → BLOB → `pkg_upload_file.UploadFileChat`, cùng cơ chế `messenger/`), không qua Node.
- **Unified Entry (2 cửa vào) + cross-doc awareness:** icon header = tất cả hội thoại; nút "Trao đổi" chứng từ = scoped theo `doc_type+doc_no` qua `sessionStorage['msEntryDoc']`. Banner cross-doc + badge tổng. DM/CHANNEL/nhóm kín; DOC mở theo chứng từ (lazy-join). Xem `chat-erp/CLAUDE.md`.
- **Hội thoại ảo (virtual room):** mọi luồng tạo (DM/DOC/Nhóm/Channel) chỉ ghi DB khi gửi tin đầu (`openVirtualRoom`/`materializeDraftThenSend`); bỏ đi chưa gửi → không sinh row. Picker DM kiểu Messenger: chọn người đã có DM → load hội thoại cũ, chưa có → phòng ảo.
- **Quan trọng khi paste HTML vào APEX:** nếu chỉ giữ `#layout` (bỏ khung `.modal`/header demo), phải tự cấp `height` cho `#layout` (CSS gốc lấy height từ `.modal{height:100vh}` đã bỏ) và set giá trị Ngũ Hành mặc định trong `:root` (gốc dựa vào `<html data-element="kim">` không còn tồn tại) — nếu không accent color (`--c-main`/`--accent`) sẽ undefined và toàn bộ nút/badge màu accent biến mất.
- **18 Ajax Callback** (mới nhất #18 `msEnsureDocConv` cho phòng ảo DOC). Chi tiết + checklist deploy: `chat-erp/CLAUDE.md` + `chat-erp/docs/callbacks.sql` + `chat-erp/docs/schema-additions.sql` (DDL gồm `uq_doc_main` — chạy TRƯỚC callback). User stories kiểm thử: `chat-erp/docs/user-stories.md` + `chat-erp/docs/virtual-room-stories.md`.

### Chat Server — Node.js real-time relay (repo riêng, sửa được)

Nguồn tại `C:\greensys\chat-server` (sibling repo, KHÔNG nằm trong `C:\chat-design`), deploy trên Server B `172.25.10.38:3410` qua pm2. Files chính: `server.js` (Express + SSE endpoint), `chat.js` (router `/api/chat/*`), `events.js` (SSE connection map + at-least-once buffer), `cqn.js` (Oracle CQN cho notification bell). Chi tiết đầy đủ: `chat-server/CLAUDE.md` trong repo đó.

**Cơ chế deliver:** 1 kết nối SSE/user keyed theo `aus_id`. `deliverToConv()` đẩy event tới TẤT CẢ thành viên hội thoại bất kể họ đang mở hội thoại/chứng từ nào — đây là nền tảng cho cross-doc awareness của messenger.

**3 patch additive đã áp cho Unified Modal Entry** (`chat.js`):
- Enrich `message` event payload thêm `doc_type/doc_no/conv_type/conv_name` (POST `/send`).
- `?scope=all` cho `GET /conversations/:aus_id` (mặc định vẫn giữ `doc_type IS NULL` cho backward-compat).
- Route mới `GET /unread-summary/:aus_id` → `{total, by_conv, by_doc}`.

Deploy thay đổi: `npm run test:connection` rồi `pm2 restart chat-server` trên Server B. Xem `docs/unified-chat-architecture.md` để biết spec đầy đủ.

### Real-time RECEIVE bridge — sống ở APP CHA (1503), KHÔNG ở module chat

Đây là điểm gây nhầm nhất (cả buổi debug). Module chat (`chat-erp/`, `messenger/`) chỉ **GỬI** broadcast (browser `nodePost('/broadcast-message')` sau khi callback ghi DB) và **NGHE** custom event `apex:chatEvent`. Chúng **KHÔNG tự mở kết nối SSE** — Node `/api/sse` khóa origin (`SSE_ORIGIN = erp.greensys.vn:8211`) + cần token HMAC. Bên mở/giữ SSE là **app cha 1503**, qua bộ **chat-system** tại `C:\greensys\chat-system` (sibling repo): `global.js` (chạy ở top window, `if(window.parent!==window) return`) + `sse-worker.js` (SharedWorker, 1 SSE/origin) + 5 Application Process Page-0 (`sseToken`, `getUrlNodeJs`, `loadAppConfig`, `chatHeartbeat`, `notificationCount`) + item `P0_AUS_ID`. `global.js` nhận SSE → `$(document).trigger('apex:chatEvent', [data])` trên parent.document; iframe chat bind qua `_parentWin.apex.jQuery`.

**Hệ quả khi debug "không real-time":** sender broadcast vẫn báo OK (gọi Node trực tiếp) — đánh lừa. Lỗi gần như luôn ở receive: app cha chưa nạp `global.js`, `window.APP_FILES` chưa set (→ `sse-worker.js` 404), `P0_AUS_ID` rỗng, hoặc trùng tên file `global.js` có sẵn của app. Test Node độc lập: `node test-sse.js <aus_id>` trong `chat-server` (mint token từ `.env`, in mọi event) — nếu test này nhận được tin mà browser không, lỗi 100% ở bridge phía app cha. Pitfalls đầy đủ (APP_FILES, SharedWorker 1-token/origin, Brave chặn cross-origin SSE) ở `chat-erp/CLAUDE.md` mục "Pitfalls".

### APEX-specific Rules (áp dụng cho cả ba module)

- **`type="button"` bắt buộc** trên mọi `<button>` tự tạo — trong HTML region, `HTP.p(...)`, và JS-generated HTML. Thiếu `type` → APEX submit form và reload page.
- **`MATERIALIZE` hint** bắt buộc khi `REGEXP_REPLACE` hoặc `INTERVAL` dùng trên remote columns (ORA-02000).
- **ORA-01799:** không dùng subquery trong `LEFT JOIN ... ON (SELECT ...)` — thay bằng scalar subquery trong SELECT hoặc kéo vào CTE.
- **`Connection: close` + `WRITE_RAW`** bắt buộc trong mọi UTL_HTTP POST relay sang Node.js.
- **`HTP.p` vs `HTP.prn`:** dùng `HTP.p` (tự thêm newline). Escape HTML bằng `HTF.ESCAPE_SC`, clean control chars bằng `REGEXP_REPLACE(str,'[[:cntrl:]]','')`.
- **`:APP_USER` auth pattern** bắt buộc đầu mọi callback — kiểm tra `IS NULL OR IN ('nobody','NOBODY')`, sau đó lookup `aus_id` từ `APP_USERS`.

### Shared Database Tables

Cả ba module (`doc-chat`, `messenger`, `chat-erp`) dùng chung schema:
- `CHAT_CONVERSATIONS` — `conv_id, conv_type (DM/CHANNEL/DOC), name, aus_id, doc_type, doc_no, last_msg_preview, last_msg_date` + (chat-erp/) `is_public, parent_conv_id, description`
- `CHAT_MESSENGERS` — bảng tin nhắn (không phải `CHAT_MESSAGES`)
- `CHAT_PARTICIPANTS` — `conv_id, aus_id, is_admin, last_read_msg_id, is_pinned, is_hidden` (`is_pinned`/`is_hidden` thêm cho dot-menu messenger — pin/ẩn ở mức per-user)
- `CHAT_REACTIONS` — `msg_id, aus_id, emoji, create_date` (PK `msg_id+aus_id+emoji`) — reaction per-user
- `CHAT_PINNED_MSGS` — `conv_id, msg_id, aus_id, pin_date` (PK `conv_id+msg_id`) — tin ghim trong hội thoại
- `CHAT_CHANNEL_ROLES` — (chat-erp/, mới) `conv_id, gus_id` — channel nào hiện cho nhóm quyền nào, join `USER_ROLES`/`GROUP_USERS`
- `CHAT_USER_ONLINE` — `aus_id, last_seen` (presence, cutoff 35 giây)
- `CONV_SEQ` — sequence cho `conv_id`
- `v_employees_v6` — view trả `emp_id, v_file_name` (avatar URL)

**DDL cho các bảng/cột mới của messenger/ ở cuối `messenger/docs/callbacks.sql`; của chat-erp/ ở `chat-erp/docs/schema-additions.sql`. Phải chạy DDL TRƯỚC khi cập nhật callback render — nếu không `msMsgThreadHtml`/`msConvListHtml` query bảng/cột thiếu → `ORA-00942`/`ORA-00904` và không render được.**

## Secondary File: nexus-pure-v2.html

`nexus-pure-v2.html` là bản rewrite của `index.html` không dùng Tailwind CDN — mọi Tailwind class đã được chuyển thành inline styles hoặc CSS rules trong `<style>`. Khi chỉnh sửa file này:

- **Không dùng Tailwind class names** — dùng inline `style=""` hoặc thêm rule vào `<style>` block.
- **Button reset đã có:** `button { border: none; background: transparent; ... }` trong global reset. Tailwind Preflight cung cấp rule này mặc định; pure CSS thì không.
- **Conversation list spacing:** `#lp-conv-list`, `#lp-s2-list`, `#lp-s3-list` dùng `display:flex; flex-direction:column; gap:2px` thay cho Tailwind `space-y-0.5`.
- **Right panel option rows** dùng class `.rp-opt-row` cho hover state (thay cho `hover:bg-slate-50`).

## Other Prototype/Scratch Files

- `nexus-pure.html` — earlier draft superseded by `nexus-pure-v2.html` (see below). Treat `v2` as current; don't edit `nexus-pure.html` unless explicitly asked to.
- `messenger-redesign-prototype.html` — standalone exploratory redesign of the messenger UI, not wired to any APEX module. Not referenced by other files.
- `_check.py`, `_conv.py`, `_fix2.py`, `_preview_phase*.html` — one-off scratch scripts/snapshots used while converting `index.html` → `nexus-pure-v2.html` (Tailwind → inline CSS). Not part of the build; safe to ignore unless asked to continue that conversion.

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
