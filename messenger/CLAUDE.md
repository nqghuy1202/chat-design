# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Messenger Fullscreen — Module Chat

Modal Dialog chạy trong **app 1002**, embed dưới dạng iframe trong app cha **app 1503** (erp.greensys.vn:8211).

## Files

```
messenger/
  messenger.html       ← paste vào Static Content Region
  messenger.css        ← paste vào Page → CSS → Inline
  messenger.fgvd.js    ← paste vào Function and Global Variable Declaration
  messenger.onload.js  ← paste vào Execute when Page Loads (chỉ: window.msInit())
  CLAUDE.md
  docs/
    callbacks.sql      ← 9 APEX Ajax Callbacks (tạo trên messenger page)
```

## Deploy lên APEX

### Bước 1 — Tạo Page
- Modal Dialog page trong app 1002
- Page ID tùy (ví dụ 200)

### Bước 2–4 — Paste files
- Static Content Region → `messenger.html`
- Page → CSS → Inline → `messenger.css`
- Page → JavaScript → Function and Global Variable Declaration → `messenger.fgvd.js`
- Page → JavaScript → Execute when Page Loads → `messenger.onload.js`

### Bước 5 — Ajax Callbacks (9 callbacks, tạo trên messenger page)

| Tên | x01 | x02 | x03 | Gọi Node.js? |
|-----|-----|-----|-----|-------------|
| `msGetCurrentUser` | — | — | — | No |
| `msConvListHtml` | filter | search | — | No |
| `msConvHeaderJson` | conv_id | — | — | No |
| `msMsgThreadHtml` | conv_id | — | — | No |
| `msInfoHtml` | conv_id | — | — | No |
| `msContactsHtml` | search | — | — | No |
| `msCreateConv` | conv_type | name | members JSON | No |
| `msSendMsg` | conv_id | body | reply_to_msg_id | **Yes** (đã deprecated — thay bằng fetch) |
| `msMarkRead` | conv_id | — | — | **Yes** (đã deprecated — thay bằng fetch) |

SQL đầy đủ: `docs/callbacks.sql`

## Kiến trúc API — Hybrid

```
HTML render  → apexCall(proc)           → APEX Ajax Callback → Oracle PL/SQL
JSON actions → nodePost(path, body)     → fetch thẳng Node.js https://chattest.erp100.vn/api/chat/*
```

**Các call dùng `nodePost` (fetch trực tiếp):**
- `POST /send` — gửi tin nhắn
- `POST /read/:conv_id/:aus_id` — mark as read
- `POST /typing/:conv_id/:aus_id` — typing indicator
- `POST /create` — tạo DM hoặc CHANNEL

**Các call dùng `apexCall` (APEX PL/SQL render HTML):**
- `msConvListHtml`, `msMsgThreadHtml`, `msInfoHtml`, `msContactsHtml` — render HTML
- `msGetCurrentUser`, `msConvHeaderJson` — JSON từ Oracle session

## Cross-App iframe Pattern — Quan trọng

App 1002 (messenger) chạy trong iframe, app 1503 (ERP) là parent. **2 jQuery instance khác nhau.**

`global.js` ở app 1503 trigger `apex:chatEvent` bằng jQuery của 1503. Messenger phải bind bằng jQuery của parent:

```javascript
// Ở đầu IIFE — đọc AUS_ID và parentWin
var _inIframe  = window.parent && window.parent !== window;
var _parentWin = _inIframe ? window.parent : window;
var AUS_ID     = Number((_inIframe ? _parentWin.$v('P0_AUS_ID') : $v('P0_AUS_ID')) || 0);

// Trong startEventPoll()
var parentJQ  = _parentWin.apex ? _parentWin.apex.jQuery : _parentWin.$;
parentJQ(_parentWin.document).on('apex:chatEvent', onChatEvent);
```

`$v('P0_AUS_ID')` không hoạt động trong iframe vì P0_AUS_ID DOM nằm ở parent. Luôn dùng `_parentWin.$v('P0_AUS_ID')`.

## Kiến trúc Frontend

```
IIFE (messenger.fgvd.js)
  ├── State: activeConvId, activeFilter, replyTo, selectedMembers, _lpScreen, _infoVisible
  ├── apexCall(proc, params, dataType, onSuccess)  — APEX Ajax helper
  ├── nodePost(path, body, onSuccess, onError)      — fetch Node.js helper
  ├── msInit()             — entry point: loadCurrentUser, loadConvList, bindEvents, startEventPoll
  ├── msSelectConv(id)     — chọn conv: load header + thread + mark read (nodePost)
  ├── msSendMessage()      — gửi tin → nodePost('/send')
  ├── sendTyping()         — debounce 600ms → nodePost('/typing/:conv_id/:aus_id')
  ├── msOpenNewConv()      — slide LP sang S2 (màn soạn tin hợp nhất)
  ├── msComposeSubmit()    — 1 người → msCreateDM; ≥2 → tạo nhóm (tên auto-sinh nếu trống)
  ├── msCreateDM(ausId)    — nodePost('/create', {conv_type:'DM',...})
  └── msComposeClose()     — slide LP về S1 (nút ✕ / Esc)
```

### Left Panel Slider — mô hình Messenger hợp nhất

`#ms-lp-track` (width: 544px = 272px × 2) dịch chuyển trong `#ms-left` (overflow: hidden). Chỉ còn **2 màn** — đã gộp DM picker + group creator thành một màn soạn tin theo recipient:

| Screen | translateX | ID | Purpose |
|---|---|---|---|
| S1 | `0` | `#ms-lp-s1` | Danh sách hội thoại |
| S2 | `-272px` | `#ms-lp-s2` | Soạn tin: ô "Tới:" (chips + tìm), multi-select. 0–1 người → nút "Nhắn tin" (DM); ≥2 → reveal ô tên nhóm (tùy chọn) + nút "Tạo nhóm" |

**Không hỏi "DM hay nhóm" trước** — loại hội thoại suy ra từ số người chọn. Click liên hệ = toggle vào ô "Tới:" (KHÔNG tạo DM ngay). Tên nhóm để trống → auto-sinh từ tên thành viên. Thoát về danh sách: nút ✕ hoặc Esc (1 thao tác). `_lpScreen` ∈ {1, 2}; `_memberMeta` cache tên/hue để chip giữ tên khi liên hệ bị lọc khỏi danh sách.

## Real-time — Typing Indicator

```
User gõ → debounce 600ms → nodePost('/typing/:conv_id/:aus_id')
  → Node.js broadcast {type:'typing', conv_id, aus_id, name}
  → SSE → global.js (app 1503) trigger apex:chatEvent trên parent.document
  → messenger bind bằng parentJQ → showTypingIndicator()
  → render vào #ms-typing-indicator (nằm giữa #ms-messages và #ms-input-area)
```

Node.js tự gửi `typing_stop` sau 4s không có heartbeat tiếp theo.

## CSS

`#ms-root` dùng `height: calc(100vh - 42px)` — trừ APEX top navigation bar 42px.
CSS scope: `#ms-root`. Không hardcode màu — dùng token hệ thống ERP (`--primary-color`, `--fourth-color`, v.v.).

## Khác biệt so với doc-chat

| | doc-chat | messenger |
|---|---|---|
| App | app 1002 (same) | app 1002 |
| Parent app | app 1503 | app 1503 |
| Filter conv | theo `doc_type + doc_no` | `doc_type IS NULL` (chung) |
| CSS scope | `#doc-chat-root` | `#ms-root` |
| Send/Read/Typing | apexCall → UTL_HTTP | nodePost (fetch trực tiếp) |

## Pitfalls

- **Mọi `<button>` phải có `type="button"`** — APEX page là `<form>`, thiếu type → submit page.
- **Không dùng `$v('P0_AUS_ID')` trực tiếp trong iframe** — phải dùng `_parentWin.$v(...)`.
- **Không dùng `$(document).on('apex:chatEvent',...)`** — phải dùng jQuery của parent.
- **`msCreateConv` callback (APEX)** đã deprecated cho create — thay bằng `nodePost('/create')`. Callback vẫn còn trong `callbacks.sql` để backward compat.
