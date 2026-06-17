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
- `POST /send` — gửi tin nhắn (hỗ trợ `is_file:true` để body rỗng cho tin nhắn file)
- `POST /attach` — broadcast SSE `{type:'attachment'}` sau khi file đã upload xong (KHÔNG ghi DB, xem mục Input Toolbar)
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
  ├── msComposeSubmit()    — 1 người → msCreateDM; ≥2 → tạo nhóm (tên auto-sinh nếu trống).
  │                          entryDoc set → conv_type='DOC' thay vì DM/CHANNEL (xem dưới)
  ├── msCreateDM(ausId)    — nodePost('/create', {conv_type:'DM'|'DOC',...})
  └── msComposeClose()     — slide LP về S1 (nút ✕ / Esc)
```

### Left Panel Slider — mô hình Messenger hợp nhất

`#ms-lp-track` (width: 544px = 272px × 2) dịch chuyển trong `#ms-left` (overflow: hidden). Chỉ còn **2 màn** — đã gộp DM picker + group creator thành một màn soạn tin theo recipient:

| Screen | translateX | ID | Purpose |
|---|---|---|---|
| S1 | `0` | `#ms-lp-s1` | Danh sách hội thoại |
| S2 | `-272px` | `#ms-lp-s2` | Soạn tin: ô "Tới:" (chips + tìm), multi-select. 0–1 người → nút "Nhắn tin" (DM); ≥2 → reveal ô tên nhóm (tùy chọn) + nút "Tạo nhóm" |

**Không hỏi "DM hay nhóm" trước** — loại hội thoại suy ra từ số người chọn. Click liên hệ = toggle vào ô "Tới:" (KHÔNG tạo DM ngay). Tên nhóm để trống → auto-sinh từ tên thành viên. Thoát về danh sách: nút ✕ hoặc Esc (1 thao tác). `_lpScreen` ∈ {1, 2}; `_memberMeta` cache tên/hue để chip giữ tên khi liên hệ bị lọc khỏi danh sách.

## Modal hợp nhất: 2 cửa vào + Cross-doc Awareness

Messenger là **modal chat duy nhất** trong hệ thống — không còn module `doc-chat` riêng (đã bỏ). 2 cửa vào khác nhau chỉ ở tham số khởi tạo qua `sessionStorage['msEntryDoc']`:

| Cửa vào | Set trước khi mở | scopeMode mặc định |
|---|---|---|
| Icon tin nhắn header hệ thống | `sessionStorage.removeItem('msEntryDoc')` (hoặc không set) | `'ALL'` |
| Nút "Trao đổi" ở trang chứng từ | `sessionStorage.setItem('msEntryDoc', JSON.stringify({doc_type,doc_no,doc_label}))` | `'DOC'` |

**Mở từ trang chứng từ** (ví dụ trang đơn hàng bán) — gọi trước `apex.navigation.dialog()`:
```javascript
sessionStorage.setItem('msEntryDoc', JSON.stringify({
  doc_type: 'SO', doc_no: '&P15_SO_NO.', doc_label: 'Đơn hàng bán'
}));
apex.navigation.dialog(url_to_messenger_page, {
  title: 'Trao đổi', height: 860, width: 1480, modal: true, resizable: false
}, null, this.triggeringElement);
```
sessionStorage là per-origin (không per-app) nên `messenger.fgvd.js` đọc trực tiếp `sessionStorage.getItem('msEntryDoc')` trong `initEntryDoc()` lúc `msInit()` — không cần truyền qua URL param hay page item.

**1 chứng từ có thể có NHIỀU hội thoại** (DM + nhóm cùng `doc_type+doc_no`) — `msConvListHtml` khi `scope=DOC` lọc đúng tập đó, không phải 1 item.

**Segmented "Chứng từ này / Tất cả"** (`#ms-scope-box`, chỉ hiện khi có `entryDoc`): `msSetScope('DOC'|'ALL')` gọi lại `loadConvList()` với `x03=scope, x04=doc_type, x05=doc_no`. Khi xem "Tất cả" mà có `entryDoc`, `x06='1'` để server ghim section "Đang xem" lên đầu danh sách.

**Cross-doc banner** (`#ms-crossdoc-banner`): khi `scopeMode==='DOC'` và event `message` tới từ hội thoại có `doc_no` khác `entryDoc.doc_no` → đẩy vào `crossDocQueue`, hiện banner "Tin mới ở chứng từ X → [Xem]". Payload event đã được **server enrich** thêm `doc_type/doc_no/conv_type/conv_name` (xem `C:\greensys\chat-server\chat.js` POST `/send`) — frontend không cần lookup thêm.

**Badge unread theo chứng từ** (`#ms-seg-doc-count`): lấy từ `GET /api/chat/unread-summary/:aus_id` (Node, gọi qua `nodeGet`) lúc `msInit()` và sau mỗi event `message` ngoài conv đang mở — KHÔNG qua callback APEX.

### conv_type = 'DOC' — hội thoại tạo từ trang chứng từ

Khi `entryDoc` đang set (modal mở từ "Trao đổi"), MỌI hội thoại mới tạo trong S2 (`msComposeSubmit`) đều `conv_type='DOC'` thay vì `DM`/`CHANNEL`, kèm bắt buộc `doc_type/doc_no`. Áp dụng cho cả 1-1 lẫn nhóm — không phân biệt DM/CHANNEL trong ngữ cảnh chứng từ. Logic theo `entryDoc`, KHÔNG theo `scopeMode` đang chọn (vì entryDoc nghĩa là cả phiên modal này gắn với 1 chứng từ).

**Dedup:** chỉ so khớp trong cùng `conv_type` + cùng `doc_type/doc_no` + cùng đối phương (`chat.js` POST `/create`, `msFindDM` callback nhận thêm `x02=doc_type, x03=doc_no`). Hệ quả: đã có DM chung với A → tạo DOC với A (cùng hoặc khác chứng từ) vẫn luôn ra hội thoại DOC riêng; 2 chứng từ khác nhau với cùng A cũng ra 2 hội thoại DOC khác nhau. DOC nhóm (≥2 người), giống CHANNEL, không dedup.

**Hiển thị:** vì DOC có thể 1-1 hoặc nhóm, mọi nơi render (`msConvListHtml`, `msConvHeaderJson`, `msInfoHtml`, `msForwardListHtml`, `GET /conversations`, `GET /doc-conversations`) dùng khái niệm `is_group = conv_type='CHANNEL' OR (conv_type='DOC' AND member_count>2)` thay vì so trực tiếp `conv_type='CHANNEL'`. DOC 1-1 hiển thị như DM (avatar tròn, tên đối phương) + badge nhỏ `.ms-ci-docbadge` ghi `doc_no` trong `msConvListHtml`. DOC nhóm hiển thị như CHANNEL (avatar icon nhóm, tên `c.name`).

## Input Toolbar (bottom row của `.ms-input-box`)

`#ms-fmt-toolbar` (bold/italic/code/link/list) **ẩn mặc định**, chỉ hiện khi `#ms-chat-input` focus (class `.visible`, JS `setFmtToolbarVisible()` debounce 150ms khi blur để không đóng ngay lúc bấm nút trong toolbar). Bottom row chia 2 nhóm: trái = `.ms-attach-menu-wrap` (nút "+"), phải = `.ms-emoji-picker-wrap` + `#ms-send-btn`.

### Đính kèm file/ảnh — 1 page item duy nhất, 2 luồng khác nhau

Cả "Ảnh / Video" và "Tệp tin" trong `#ms-attach-menu` đều gọi `msTriggerFileUpload()` → click vào **1 page item** `P10022710201_UPLOAD_FILE` (APEX File Browse, `<a-file-upload>`). **Lưu ý DOM:** input thật là `#P10022710201_UPLOAD_FILE_input`, còn phần hiển thị/click được là `#P10022710201_UPLOAD_FILE_DROPZONE` (khác hẳn id item gốc) — đọc tên/dung lượng/mime qua `.a-FileDrop-heading` / `.a-FileDrop-description` / `[data-mime-type]` trên dropzone, KHÔNG dùng `APEX_APPLICATION_TEMP_FILES` (bảng này chỉ có data sau khi page thật sự submit, không áp dụng cho SPA này).

2 luồng phân biệt bằng biến `_pendingFileSource` (set ngay trước khi trigger click):
- **`'plus'`** (bấm nút "+") → gửi ngay như Zalo, không qua preview. `MutationObserver` trên dropzone thấy `has-files` + nguồn là `'plus'` → gọi thẳng `msSendFileMessage()`.
- **`'paste'`** (paste ảnh/file vào `#ms-chat-input`) → gán file vào input thật qua `DataTransfer` + dispatch `change` thật để APEX tự cập nhật DOM → hiện preview chip trong `#ms-file-preview-bar`, chờ bấm Gửi. `msSendMessage()` kiểm tra dropzone có `has-files` trước, nếu có thì route sang `msSendFileMessage()` thay vì gửi text thuần.

**Preview chip** (`buildFileChip()`): ảnh và file đều render thành thẻ vuông 84×84 đồng nhất (`.ms-file-chip` / `.ms-file-chip--image`) — ảnh hiện thumbnail full qua `URL.createObjectURL(input.files[0])`, file hiện badge màu theo đuôi (`FILE_TYPE_STYLES`: doc/docx xanh dương, xls/xlsx/csv xanh lá, ppt/pptx cam, pdf đỏ, zip/rar/7z vàng, còn lại xám + icon generic). Nút ✕ trên chip bấm hộ `.a-FileDrop-remove` thật của APEX (không tự quản state riêng).

### Luồng gửi file thật — 3 bước (giải quyết vấn đề thứ tự owner_id)

Bảng file riêng của hệ thống có `fil_id, owner_id (→ CHAT_MESSENGERS.msg_id), owner_table_name='CHAT_MESSENGERS', file_name (path)`. Vì `owner_id` cần `msg_id` đã tồn tại trước, **không thể** insert file trước rồi mới tạo tin nhắn — bắt buộc thứ tự ngược:

```
msSendFileMessage() trong messenger.fgvd.js:
  1. nodePost('/send', {conv_id, aus_id, body: caption, is_file: true}) → lấy msg_id
     (Node /send đã nới validate: body được phép rỗng khi is_file=true)
  2. apexCall('msUploadAttachment', {x01: msg_id}, ...) → callback APEX insert file
     với owner_id=msg_id, owner_table_name='CHAT_MESSENGERS' → trả fil_id/file_name/mime_type/file_size
     ⚠️ TODO: 'msUploadAttachment' là tên TẠM — đổi thành tên callback upload thật đã viết sẵn
  3. nodePost('/attach', {conv_id, msg_id, fil_id, file_name, mime_type, file_size})
     → route Node MỚI (chat-server/chat.js), KHÔNG ghi DB, chỉ broadcast SSE {type:'attachment'}
     để client khác load lại thread (người gửi tự refreshThread() ngay, không cần đợi broadcast)
```

Client nhận `type:'attachment'` trong `onChatEvent()` → `loadThread(activeConvId)` nếu đúng hội thoại đang mở (để `msMsgThreadHtml` — đã JOIN file table — render ra file).

**⚠️ TODO còn thiếu để hoàn thiện:** `msMsgThreadHtml` (PL/SQL trong `callbacks.sql`) cần JOIN bảng file theo `owner_id=msg_id AND owner_table_name='CHAT_MESSENGERS'`, render bằng pattern `.file-card`/`.img-card` (tham khảo `nexus-pure-v2.html` dòng ~1690) — chưa làm vì chưa có cấu trúc SELECT hiện tại của `msMsgThreadHtml`.

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
