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
- `POST /send` — gửi tin nhắn text (hỗ trợ `fil_id` nếu file đã upload sẵn)
- `POST /upload-send` — **DEPRECATED** (không dùng nữa). Lý do: `pkg_upload_file` nằm trong DB của APEX, KHÔNG nằm trong DB mà Node kết nối → gọi từ Node `PLS-00201`. File giờ upload qua callback APEX `msUploadFile`. Xem mục "Luồng gửi file thật".
- `POST /attach` — DEPRECATED, không dùng
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

### Danh sách hội thoại — phẳng theo thời gian + filter theo loại

`msConvListHtml` render **danh sách phẳng**, KHÔNG còn chia section (đã bỏ block `ms-section-label` + biến `l_last_type` + CSS `.ms-section-label`). Sắp xếp `ORDER BY is_viewing DESC, is_pinned DESC, last_msg_date DESC` ⇒ hội thoại "Đang xem" (entryDoc) và **đã ghim nổi lên đầu**, phần còn lại mới nhất lên trước. Item đã ghim hiện icon `.ms-ci-pin` (fa-thumbtack nhỏ, xoay 20°) cạnh thời gian thay cho section "Ghim".

**Filter theo loại** (`#ms-filter-row`, chip `.ms-filter-chip`, `activeFilter`→x01): **Tất cả** (`ALL`) / **Trực tiếp** (`DM`) / **Nhóm** (`GROUP`=CHANNEL) / **Chứng từ** (`DOC`). Chip dạng pill, hàng ngang cuộn-ngang-ẩn-scrollbar nếu hẹp. Filter clause trong `msConvListHtml` khớp `c.conv_type`; `UNREAD` vẫn còn hỗ trợ trong SQL (tương thích ngược) nhưng KHÔNG còn chip. Handler chip đã generic (đọc `data-filter`), đổi loại chỉ cần sửa HTML + clause SQL.

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

### Tìm kiếm tin nhắn trong hội thoại — icon ở chat header

Hàng nút `.ms-rp-actions` trong right panel (`msInfoHtml`) đã **bị gỡ hoàn toàn** (cả nhánh DM lẫn nhóm) — right panel giờ chỉ còn avatar/thông tin/tùy chọn/danh sách thành viên. CSS `.ms-rp-action*` cũng đã xóa.

Tìm kiếm chuyển lên **chat header**: nút kính lúp `#ms-header-search-btn` trong `#ms-chat-header-actions` (bên trái nút thông tin) → `onclick="msToggleConvSearch()"`.

- `msToggleConvSearch()` (chỉ chạy khi có `activeConvId`): đang mở thì `msCloseConvSearch`, chưa thì `msOpenConvSearch(activeConvId)`. Nút có class `.active` (nền xanh nhạt) khi ô tìm đang mở.
- Ô tìm `#ms-msgsearch` là **thanh trượt trên `#ms-messages`**; gõ → debounce 280ms → **callback `msSearchMsgsHtml` (#23)** (x01=conv_id, x02=từ khóa) trả HTML ≤40 tin khớp (bỏ tin đã xóa, highlight bằng INSTR literal → an toàn ký tự đặc biệt). Click kết quả → `msJumpFromSearch(msg_id)` → `msJumpToMsg` cuộn + highlight (chỉ cuộn được nếu tin nằm trong ~50 tin đã tải). Đổi hội thoại tự đóng ô tìm (`msSelectConv` gọi `msCloseConvSearch`).

**Code mồ côi (giữ lại, chưa surface ra UI):** `msOpenAddMembers` + callback **`msAddMembers` (#22)** (thêm thành viên vào nhóm) vẫn còn trong repo nhưng KHÔNG còn nút nào gọi — để dành khi cần đưa lại. Khi muốn mở lại chỉ cần thêm 1 nút `onclick="msOpenAddMembers(conv_id)"`.

### Đính kèm file/ảnh — 1 page item duy nhất, 2 luồng khác nhau

Nút "+" (`.ms-attach-menu-wrap > .ms-tb-btn`, `onclick="msTriggerFileUpload()"`) mở THẲNG **1 page item** `P10022710201_UPLOAD_FILE` (APEX File Browse, `<a-file-upload>`) — **không còn dropdown 2 option** "Ảnh / Video" vs "Tệp tin" vì cả hai vốn gọi y hệt nhau, item nhận mọi loại file. (Đã gỡ `#ms-attach-menu`, `msToggleAttachMenu`, `_attachMenuOpen` và CSS `.ms-attach-menu*` — chỉ giữ `.ms-attach-menu-wrap`. Muốn giới hạn loại file thì set "File Types" của item APEX, không phải ở HTML.) **Lưu ý DOM:** input thật là `#P10022710201_UPLOAD_FILE_input`, còn phần hiển thị/click được là `#P10022710201_UPLOAD_FILE_DROPZONE` (khác hẳn id item gốc) — đọc tên/dung lượng/mime qua `.a-FileDrop-heading` / `.a-FileDrop-description` / `[data-mime-type]` trên dropzone, KHÔNG dùng `APEX_APPLICATION_TEMP_FILES` (bảng này chỉ có data sau khi page thật sự submit, không áp dụng cho SPA này).

2 luồng phân biệt bằng biến `_pendingFileSource` (set ngay trước khi trigger click):
- **`'plus'`** (bấm nút "+") → gửi ngay như Zalo, không qua preview. `MutationObserver` trên dropzone thấy `has-files` + nguồn là `'plus'` → gọi thẳng `msSendFileMessage()`.
- **`'paste'`** (paste ảnh/file vào `#ms-chat-input`) → gán file vào input thật qua `DataTransfer` + dispatch `change` thật để APEX tự cập nhật DOM → hiện preview chip trong `#ms-file-preview-bar`, chờ bấm Gửi. `msSendMessage()` kiểm tra dropzone có `has-files` trước, nếu có thì route sang `msSendFileMessage()` thay vì gửi text thuần.

**Preview chip** (`buildFileChip()`): ảnh và file đều render thành thẻ vuông 84×84 đồng nhất (`.ms-file-chip` / `.ms-file-chip--image`) — ảnh hiện thumbnail full qua `URL.createObjectURL(input.files[0])`, file hiện badge màu theo đuôi (`FILE_TYPE_STYLES`: doc/docx xanh dương, xls/xlsx/csv xanh lá, ppt/pptx cam, pdf đỏ, zip/rar/7z vàng, còn lại xám + icon generic). Nút ✕ trên chip bấm hộ `.a-FileDrop-remove` thật của APEX (không tự quản state riêng).

### Luồng gửi file thật — upload qua callback APEX `msUploadFile` (base64), KHÔNG qua Node

> **Lý do gốc (2 lớp, đừng lặp lại):**
> 1. **Temp files rỗng trong AJAX:** item File Browse (`APEX_APPLICATION_TEMP_FILES`) trong `apex.server.process` **KHÔNG gửi bytes** — chỉ form submit thật mới gửi; view `apex_application_temp_files` RỖNG ở mọi request AJAX (`temp_all=0, aaf_cnt=0, wff_cnt=0`). ⇒ Client BẮT BUỘC tự truyền bytes.
> 2. **Package khác DB:** đã thử cho Node tự gọi `pkg_upload_file.UploadFileChat` (route `/upload-send`) nhưng `pkg_upload_file` **nằm trong DB của APEX, KHÔNG nằm trong DB mà Node kết nối** (`dev24@172.25.10.18/pdbgc19c`) → `PLS-00201`. ⇒ Upload phải chạy TỪ callback APEX (đúng DB có package).
>
> Cả route Node `/upload-send`, callback `msUploadAttachment` (#19), `msCreateFileMessage` (#20) giờ **deprecated** (giữ trong repo chỉ để tham khảo lịch sử, KHÔNG deploy/dùng).

Thiết kế hiện tại — cột `fil_id` trực tiếp trên `CHAT_MESSENGERS` (FK thật, DDL cuối `docs/callbacks.sql`); **callback APEX `msUploadFile` (#21) ghi DB cho file**, Node chỉ relay SSE:

```
msSendFileMessage() / uploadOneFile() trong messenger.fgvd.js:
  - Đọc File object thẳng từ #P10022710201_UPLOAD_FILE_input.files (KHÔNG dựa
    vào item value / temp files). Mỗi file = 1 tin nhắn (gửi tuần tự); caption +
    reply gắn file đầu. Dọn item APEX ngay (.a-FileDrop-remove) sau khi giữ ref.
  - FileReader.readAsDataURL → base64 (bỏ prefix "data:...;base64,").
  - Cắt base64 thành chunk ≤ 30000 ký tự (FILE_B64_CHUNK, < 32767 = giới hạn
    phần tử g_f01) → mảng, gửi qua apex.server.process (KHÔNG qua apexCall để
    onDone luôn chạy kể cả lỗi transport → không kẹt vòng gửi tuần tự):
      apex.server.process('msUploadFile', {
        f01: chunkArray, x01: conv_id, x02: file_name,
        x03: caption?, x04: reply_to_msg_id?
      }, { pageId, dataType:'json', success, error })
  - Trả {state:'success'} → refreshThread + loadConvList. Real-time do broadcast.

Callback msUploadFile (#21, docs/callbacks.sql):
  1. Ghép apex_application.g_f01 → CLOB (DBMS_LOB.WRITEAPPEND) →
     apex_web_service.clobbase642blob() → BLOB.
  2. pkg_upload_file.UploadFileChat(p_blob => BLOB, p_co_id => :G_CO_ID,
       p_oun_id => :G_OUN_ID_INS, p_user_name => :G_USER_NAME, p_module='01',
       p_table='CHAT_MESSENGERS', p_id=>NULL, p_ffo_id=>NULL, p_directory=>NULL,
       p_fil_id OUT, p_error OUT) → sinh fil_id, ghi file vật lý, INSERT FILES.
       (co_id/oun_id/user_name đọc THẲNG từ global APEX, KHÔNG nhận từ client.)
  3. INSERT CHAT_MESSENGERS (MSG_SEQ, fil_id) + UPDATE owner FILES + preview +
     last_read; COMMIT.
  4. UTL_HTTP POST Node /api/chat/broadcast-message (Connection:close+WRITE_RAW,
     payload enrich from_name/doc_type/doc_no/conv_type/conv_name) — route CHỈ
     phát SSE, KHÔNG ghi DB. Lỗi broadcast KHÔNG rollback tin.
```

**Package upload** (`pkg_upload_file`): `UploadFileChat` = entry nhận **BLOB trực tiếp** (khác `UploadMultipleFilesChat` vốn đọc từ `apex_application_temp_files` — không dùng được trong AJAX). `WriteFileInfoToDatabaseChat` INSERT FILES: `File_Name = <relative_dir>/<co_id>.<fil_id>.<ext>`, `Name = tên gốc`. `p_id`(owner)/`p_ffo_id` để NULL được (nếu `FILES.Ffo_Id` NOT NULL thì cần folder mặc định — chưa gặp).

**Đánh đổi base64:** phình ~33%, mỗi phần tử `g_f01` ≤ 32KB nên file vài MB = vài chục phần tử (vẫn chạy tốt). Hợp cho ảnh/tài liệu chat; file rất lớn (vài chục MB) mới phải tính cách khác.

**`msMsgThreadHtml` đã JOIN bảng `FILES`** (`LEFT JOIN FILES f ON f.fil_id = m.fil_id`). **2 cột FILES quan trọng** (xác nhận 2026-06-19):
- **`FILES.file_name`** = đường dẫn tương đối ĐẦY ĐỦ → dùng THẲNG làm `href`/`src`, KHÔNG ghép tiền tố.
- **`FILES.name`** = tên file GỐC còn đuôi → suy đuôi phân biệt ảnh (`REGEXP_SUBSTR` trên `f.name`) render `.img-card` vs `.file-card`, và hiển thị tên. Query alias `file_disp_name`.

**Còn lại để DEPLOY:**
1. Chạy DDL cột `fil_id` (cuối `docs/callbacks.sql`) TRƯỚC, rồi cập nhật `msMsgThreadHtml` (#4, đã JOIN FILES) trên page APEX.
2. Tạo callback APEX **`msUploadFile` (#21)** trên page (SQL ở `docs/callbacks.sql`). (#19/#20 + route Node `/upload-send` KHÔNG dùng.)
3. Đảm bảo schema chạy callback (schema parse của page APEX) có quyền `EXECUTE` `pkg_upload_file` + ghi Oracle Directory (BlobToFile) — bình thường có sẵn vì cùng DB APEX. Node `/broadcast-message` đã sẵn, KHÔNG cần deploy lại chat-server cho file.
4. Kiểm tra global APEX `:G_CO_ID` / `:G_OUN_ID_INS` / `:G_USER_NAME` có giá trị trong session messenger (callback #21 dùng để gọi `UploadFileChat`).

**Enhancement tùy chọn (chưa làm):** ảnh mở tab mới (`target="_blank"`) thay vì lightbox in-app (`#ms-lightbox` chưa có).

DDL cột `fil_id` + FK trỏ `FILES(fil_id)` (`NO ACTION`, không `SET NULL`) ở cuối `docs/callbacks.sql` — phải chạy TRƯỚC khi deploy callback `msUploadAttachment`/`msCreateFileMessage` và `msMsgThreadHtml`.

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
