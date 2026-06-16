# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Doc Chat Modal — Trao đổi chứng từ

Modal chat gắn với từng chứng từ ERP (SO, PXK, HD…). APEX Modal Dialog Page ID: **10022710201**. Deploy bằng **FGVD + Dynamic Action** — không React, không JSX, không Static Files.

> Module này hoàn toàn tách biệt với Chat System (Messenger). Khác app ID, khác page ID, khác bộ callbacks — đừng nhầm lẫn.

## Files

```
doc-chat/
  doc-chat-page.fgvd.js   ← ACTIVE: paste vào "Function and Global Variable Declaration"
  doc-chat-page.onload.js ← ACTIVE: paste vào "Execute when Page Loads" (chỉ window.dcInit())
  doc-chat.css            ← ACTIVE: paste vào Page → CSS → Inline
  preview.html            ← Preview giao diện trên browser (mock data, không cần APEX)
  CLAUDE.md               ← file này
  docs/
    da-setup.md           Bảng 19 Dynamic Actions + paste checklist
    native.sql            4 HTML-returning callbacks (SQL đầy đủ)
    callbacks.sql         4 action-only callbacks (SQL đầy đủ)
    modal-plan.md         Kế hoạch chuyển từ JSX sang native (tham khảo)
```

## Deploy lên APEX — Quy trình 3 bước

### Bước 1 — Function and Global Variable Declaration
Paste toàn bộ `doc-chat-page.fgvd.js`. File này chứa:
- `window.CHAT_AUS_ID = &G_AUS_ID.;` (server-side substitution — đầu file)
- `var pageId = $v('pFlowStepId');` (bắt buộc đầu file)
- Toàn bộ state + helper functions (trong IIFE)
- Expose `window.dcOn*` cho Dynamic Actions gọi
- Binding `apex:chatEvent` và `unload` (giữ trong FGVD, không phải DA)

### Bước 2 — Execute when Page Loads
Paste `doc-chat-page.onload.js` (chỉ 1 dòng: `window.dcInit();`).

### Bước 3 — Dynamic Actions (19 DA)
Xem bảng đầy đủ trong `docs/da-setup.md`. Mỗi DA là one-liner gọi `window.dcOn*()`.

### CSS
Paste `doc-chat.css` vào Page → CSS → Inline (giới hạn ~32KB).

## Page Items (hidden, trên page 10022710201)

| Item | Dùng trong JS |
|------|--------------|
| `P10022710201_DOC_TYPE` | `$v('P' + pageId + '_DOC_TYPE')` |
| `P10022710201_DOC_NO` | `$v('P' + pageId + '_DOC_NO')` |
| `P10022710201_CONV_ID` | `$v('P' + pageId + '_CONV_ID')` |
| `P10022710201_CONV_FILTER` | filter: ALL / DM / CHANNEL |
| `P10022710201_SEARCH_QUERY` | search text |
| `P10022710201_REPLY_TO_MSG_ID` | reply context |

**Pattern đọc/ghi:**
```javascript
$v('P' + pageId + '_CONV_ID')                    // đọc
$s('P' + pageId + '_CONV_ID', convId)            // ghi
apex.item('P' + pageId + '_CONV_ID').setValue(v) // APEX 24.x
```

## Ajax Callbacks (7 — tạo trên page 10022710201, không phải Application Process)

### HTML-returning (server render HTML, JS swap innerHTML)

| Callback | x01 | x02 | x03 | x04 | Trả về |
|----------|-----|-----|-----|-----|--------|
| `dcConvListHtml` | doc_type | doc_no | filter (ALL/DM/CHANNEL) | search | HTML conv list |
| `dcMsgThreadHtml` | conv_id | search_query | — | — | HTML messages |
| `dcInfoHtml` | conv_id | — | — | — | HTML members panel |
| `dcContactsHtml` | — | — | — | — | HTML contacts checkboxes |

### Action-only (trả JSON + relay sang Node.js)

| Callback | x01 | x02 | x03 | x04 | Relay Node? |
|----------|-----|-----|-----|-----|-------------|
| `docChatCreate` | conv_type | name | members (JSON) | doc_type | No |
| `docChatSend` | conv_id | body | reply_to_msg_id | partner_aus_id | **Yes** |
| `docChatRead` | conv_id | — | — | — | **Yes** |
| `docChatTyping` | conv_id | — | — | — | **Yes** |

SQL đầy đủ: `docs/native.sql` (HTML-returning) + `docs/callbacks.sql` (action-only)

**Gọi từ JS:**
```javascript
apex.server.process('dcMsgThreadHtml', { x01: convId, x02: searchQuery }, {
    pageId: 10022710201,   // hardcode — modal page cố định
    dataType: 'html',
    success: function(html) { document.getElementById('dc-messages').innerHTML = html; }
});
```

## Kiến trúc Frontend

```
FGVD (doc-chat-page.fgvd.js)
  ├── State: activeConvId, AUS_ID, activeFilter, showInfo, typingUsers/Timers, selectedMembers
  ├── dcInit()           — đọc docChatCtx từ sessionStorage, set page items, load conv list
  ├── selectConv(id)     — load thread HTML, load info, mark read, update header
  ├── sendMessage()      — dcJson docChatSend, reload thread + conv list on success
  ├── openCompose(type)  — toggle list/compose screens, load contacts
  ├── applyConvType(t)   — toggle name field, trim selectedMembers for DM
  └── window.dcOn*       — 19 public handlers cho Dynamic Actions gọi

apex:chatEvent (bind trong FGVD — parent document, không phải iframe document):
  var $eventDoc = (inIframe ? window.parent.apex.jQuery : $)(eventWin.document)
  $eventDoc.on('apex:chatEvent', onChatEvent)
  // Cleanup khi modal đóng: $(window).on('unload', ...)
```

**Flow real-time:** SSE → `global.js` (trang cha) → `apex.jQuery(parent.document).trigger('apex:chatEvent', ev)` → handler trong FGVD của iframe.

## CSS Design System

`doc-chat.css` scoped trong `#doc-chat-root`. Đổi màu chỉ qua khối `:root` đầu file.

| Token cục bộ | Map sang hệ thống | Fallback |
|---|---|---|
| `--primary` | `var(--primary-color)` | `#15674C` |
| `--primary-50` | `var(--fourth-color)` | `#E1F0EB` |
| `--primary-25` | `color-mix(in srgb, primary 8%, transparent)` | focus wash nhạt |
| `--surface` | `var(--white-color)` | `#FFFFFF` |
| `--sidebar-bg` | — | `#F7F8FA` (left pane) |
| `--border` | `rgba(0,0,0,.08)` | tinh tế hơn border cứng |
| `--danger` | `var(--red-color)` | `#D81F25` |

**Avatar rules:**
- Nhóm/chứng từ: nền phẳng `var(--primary-color)` — không gradient
- User: `hsl(aus_id * 47 % 360, 55%, 52%)` — dynamically set qua inline style trong PL/SQL HTML

**3 lớp background phân biệt:**
- Left pane sidebar: `var(--sidebar-bg)` = `#F7F8FA`
- Chat center pane: `var(--surface)` = trắng
- Right info pane: `var(--surface)` = trắng

**Preview:** Mở `preview.html` trực tiếp trên browser để xem giao diện với mock data. Có switcher tabs cho các trạng thái: hội thoại, compose DM, compose nhóm, typing, reply.

## Cross-frame Trap — Quan trọng

Doc Chat chạy trong **iframe** bên trong APEX modal. jQuery custom event không cross jQuery instances:

```javascript
// SAI — bind vào iframe's document: handler KHÔNG BAO GIỜ được gọi
$(document).on('apex:chatEvent', handler);

// ĐÚNG — bind vào parent's document + parent's jQuery instance
window.parent.apex.jQuery(window.parent.document).on('apex:chatEvent', handler);
```

## Mở Modal từ ERP Page

Modal cần SSP checksum — generate server-side qua `redirect_page` Application Process:

```javascript
var triggerEl = this.triggeringElement;   // capture trước await
var docCtx = {
    doc_type: 'SO', doc_no: '&P15_SO_NO.',
    doc_label: 'Đơn hàng bán', doc_status: '&P15_STATUS.',
    doc_total: '&P15_TOTAL.'
};
sessionStorage.setItem('docChatCtx', JSON.stringify(docCtx));

let url = await globalHandleAjaxProcess(['redirect_page', {
    x01: 10022710201,
    x02: 'P_DOC_TYPE,P_DOC_NO:' + docCtx.doc_type + ',' + docCtx.doc_no,
    x03: 'G_APP_XXXX_ID'
}, 'text']);

apex.navigation.dialog(url, {
    title: 'Trao đổi chứng từ', height: 860, width: 1480,
    modal: true, resizable: false
}, null, triggerEl);
```

**Tại sao sessionStorage:** Doc fields chứa Unicode, dấu phẩy → không pass được qua APEX URL params.

## :APP_USER Pattern (bắt buộc trong mọi callback)

```sql
IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
  HTP.p('{"error":"auth"}'); RETURN;
END IF;
BEGIN
  SELECT aus_id INTO l_aus_id FROM APP_USERS
  WHERE LOWER(user_name) = LOWER(:APP_USER);
EXCEPTION WHEN NO_DATA_FOUND THEN
  HTP.p('{"error":"user_not_found"}'); RETURN;
END;
```

## MATERIALIZE Pattern (bắt buộc khi JOIN remote tables)

```sql
WITH remote_data AS (
  SELECT /*+ MATERIALIZE */
         u.aus_id,
         REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') AS full_name
  FROM   APP_USERS u JOIN EMPLOYEES e ON e.emp_id = u.emp_id
)
SELECT ... FROM remote_data r LEFT JOIN CHAT_PARTICIPANTS cp ON cp.aus_id = r.aus_id;
```

## Pitfalls Doc Chat

**pageId cố định 10022710201:** Hardcode trong mọi `apex.server.process` call. `window.pageId` cũng có nhưng luôn bằng `10022710201`.

**window.dcOn* chứ không phải hàm private:** DA chạy trong global scope — gọi `window.dcSendMessage()`, không phải `sendMessage()`.

**applyConvType thay cho .trigger('change'):** DA#15 (Change radio) chỉ handle user click. `openCompose()` gọi thẳng `applyConvType()` — không dùng `.trigger('change')` vì DA không nhận trigger giả lập.

**scrollToBottom sau 300ms:** Sau khi swap innerHTML cần `setTimeout(scrollToBottom, 300)` — DOM cần thời gian render trước khi `scrollHeight` chính xác.

**nested-overlay position:** `#dc-create-overlay` phải nằm bên trong `.modal` (có `position:relative`) để `position:absolute; inset:0` bám đúng container, không bị clip ra ngoài.

**UTL_HTTP POST — Connection: close bắt buộc:** `docChatSend`, `docChatRead`, `docChatTyping` relay sang Node qua POST. Thiếu `Connection: close` + `WRITE_RAW` → `BadRequestError: request aborted`. Xem `docs/pitfalls.md` ở root.

**HTF.ESCAPE_SC + VISCII:** Trong PL/SQL HTML-returning callbacks, escape với `HTF.ESCAPE_SC`. Clean VISCII control chars bằng `REGEXP_REPLACE(str,'[[:cntrl:]]','')` — chỉ áp dụng sau khi đã MATERIALIZE.
