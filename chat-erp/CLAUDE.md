# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# chat-erp — Module Chat (thiết kế mới, page riêng)

Page APEX **mới** `10022710202`, KHÔNG đụng tới page production `10022710201` của `messenger/`. Tái dùng toàn bộ schema `CHAT_*` đã có. Mọi đọc/ghi dữ liệu (gửi tin, đọc tin, tạo hội thoại, reaction, pin, upload file...) vẫn đi qua Ajax Callback APEX — **real-time dùng CHUNG Node chat-server với `messenger/`** (cùng instance `172.25.10.38:3410`): sau khi 1 callback ghi DB thành công, BROWSER (không phải DB) tự gọi `nodePost('/broadcast-message', ...)` để phát SSE cho thành viên khác, rồi nhận lại qua `apex:chatEvent` giống messenger/. Lý do không dùng UTL_HTTP từ PL/SQL: máy DB Oracle thường không route tới Node (ORA-12535) — xem `messenger/CLAUDE.md` mục "Luồng gửi file thật".

## Files

```
chat-erp/
  chat-modal.html       ← paste vào Static Content Region
  chat-modal.css        ← paste vào Page → CSS → Inline
  chat-modal.fgvd.js    ← paste vào Function and Global Variable Declaration
  chat-modal.onload.js  ← paste vào Execute when Page Loads (chỉ: msInit();)
  CLAUDE.md
  docs/
    schema-additions.sql ← DDL — chạy 1 LẦN, TRƯỚC callbacks.sql
    callbacks.sql         ← 17 Ajax Callback (tạo trên page 10022710202)
    seed-channel-thongbao.sql ← seed tùy chọn: channel "Thông báo" công khai
```

## Deploy lên APEX

### Bước 0 — Database
`docs/schema-additions.sql` — thêm `CHAT_CONVERSATIONS.is_public/parent_conv_id/description` + bảng mới `CHAT_CHANNEL_ROLES` + (mục 5) cột `CHAT_MESSENGERS.fil_id` cho upload file thật. `CHAT_REACTIONS`/`CHAT_PINNED_MSGS`/`fil_id` đã có sẵn nếu `messenger/` đã deploy trên cùng DB — bỏ qua phần trùng, không tạo lại.

### Bước 1 — Tạo Page
- Modal Dialog (hoặc Normal page nếu muốn full-screen riêng), page ID `10022710202`
- Cùng app với `messenger/` (app 1002) để dùng chung session/auth scheme

### Bước 2–5 — Paste files
- Static Content Region → `chat-modal.html`
- Page → CSS → Inline → `chat-modal.css`
- Page → JavaScript → Function and Global Variable Declaration → `chat-modal.fgvd.js`
- Page → JavaScript → Execute when Page Loads → `chat-modal.onload.js`

### Bước 6 — Tạo 17 Ajax Callback (Page → Processing → Ajax Callback)

Tạo từng cái, copy đúng khối PL/SQL tương ứng trong `docs/callbacks.sql` (đánh số 1–15 trong comment đầu file đó). Tên Ajax Callback phải khớp CHÍNH XÁC tên `apexCall()`/`apexCallJson()` gọi trong `chat-modal.fgvd.js`:

| # | Tên callback | Trả về | Gọi bởi |
|---|---|---|---|
| 1 | `msGetCurrentUser` | JSON | `msInit()` |
| 2 | `msConvListHtml` | HTML | `loadConvList()` |
| 3 | `msMsgThreadHtml` | HTML | `openConversation2()`, `sendMessage()`, `sendThreadReply()` |
| 4 | `msSendMsg` | JSON | `sendMessage()`, `sendThreadReply()` |
| 5 | `msMarkRead` | JSON | `openConversation2()` |
| 6 | `msToggleReaction` | JSON | `applyReaction()` (qua `pickReact()` từ react-bar / `toggleReaction()` chip) |
| 7 | `msInfoHtml` | HTML | `openInfo()`, `openCreateSubgroup()` |
| 8 | `msContactsHtml` | HTML | `renderPeople()`, `renderSgMembers()` |
| 9 | `msCreateDM` | JSON | `pickerSubmit()`, `gsPickPerson()` |
| 10 | `msCreateGroup` | JSON | `createGroup()` |
| 11 | `msCreateChannel` | JSON | `createChannel()` |
| 12 | `msCreateSubgroup` | JSON | `createSubgroup()` |
| 13 | `msConvAction` | JSON | `pinConv()`, `deleteConv()` |
| 14 | `msGlobalSearchHtml` | HTML | `renderGlobalResults()` |
| 15 | `msRoleOptionsHtml` | HTML | `msInit()` (nạp `#roleMenu`) |
| 16 | `msUploadFile` | JSON | `uploadOneFile()` (đính kèm ảnh/file thật) |
| 17 | `msMentionList` | JSON | `loadMentionMembers()` (gợi ý @tên — thành viên hội thoại) |

Mỗi callback: **Page → Processing → Create → Ajax Callback**, paste PL/SQL, KHÔNG cần "Items to Submit"/"Items to Return" (client tự gửi `x01..x07`/`f01` qua `apex.server.process`, đọc bằng `apex_application.g_x01..g_x07`/`g_f01`).

### Bước 7 — Real-time (Node chat-server)
`NODE_URL` trong `chat-modal.fgvd.js` trỏ cùng instance Node với `messenger/` (`https://chattest.erp100.vn/api/chat`, deploy thật `172.25.10.38:3410`) — không cần deploy thêm gì phía Node, route `/broadcast-message` đã có sẵn cho messenger/. Nếu page chat-erp chạy nhúng iframe dưới app cha (giống messenger/ dưới app 1503) thì `apex:chatEvent` tự nhận qua jQuery của parent; nếu chạy độc lập (không iframe) thì bind thẳng `document` hiện tại — `chat-modal.fgvd.js` tự dò bằng `window.parent !== window`, không cần chỉnh tay.

### Bước 8 — Test
Mở page, F12 → Network, kiểm tra các request `wwv_flow.ajax` trả về đúng HTML/JSON, không có `ORA-*`. Test theo thứ tự: load list → mở 1 hội thoại → gửi tin → react → đính kèm ảnh/file → tạo DM/Nhóm/Channel/Nhóm con → ghim/xóa hội thoại → ⌘K tìm kiếm. Mở 2 tab (2 user khác nhau, cùng hội thoại) để xác nhận tin nhắn/file tới tức thời không cần F5 (real-time qua SSE).

## Kiến trúc — khác messenger/ ở điểm gì

| | messenger/ | chat-erp/ |
|---|---|---|
| Page | `10022710201` (production) | `10022710202` (mới) |
| Real-time | Node.js SSE — gửi/đọc/typing đi thẳng `nodePost`/`nodeGet` | Node.js SSE CHUNG instance — nhưng mọi GHI DỮ LIỆU vẫn qua APEX callback; browser tự `nodePost('/broadcast-message')` sau khi callback thành công để phát SSE (không có route `nodePost('/send')` riêng như messenger/) |
| Loại hội thoại | `DM` / `CHANNEL` / `DOC` | 4 nhóm sidebar: `chungtu`(=DOC) / `channel`(=CHANNEL+`is_public=1`) / `nhom`(=CHANNEL+`is_public=0`) / `canhan`(=DM) — suy ra bằng CASE, KHÔNG có cột `kind` riêng |
| Nhóm con | không có | `CHAT_CONVERSATIONS.parent_conv_id` tự tham chiếu, 1 cấp |
| Channel theo quyền | không có | `CHAT_CHANNEL_ROLES(conv_id, gus_id)` join `USER_ROLES`/`GROUP_USERS`; không có dòng nào = "Toàn công ty" |
| Left panel | slider S1/S2 hợp nhất DM+Nhóm | sidebar tĩnh 1 màn, 4 section + compose pane riêng cho DM/Nhóm/Channel/Nhóm con (S1↔S2/S3/S4 trong `.compose-pane`) |
| Upload file | base64 qua `msUploadFile` (#21, pkg_upload_file) | base64 qua `msUploadFile` (#16, cùng `pkg_upload_file`) — `onAttachPicked()` → `uploadOneFile()` |
| Typing indicator | có (`#ms-typing-indicator`) | chưa có (xem TODO) |

## Giới hạn đã biết / TODO khi nâng cấp

1. **"Luồng trả lời"** (`openThread()`) lọc trên DOM đã tải bằng `data-reply-to` — chỉ thấy reply nằm trong batch tin đã `FETCH FIRST 100 ROWS` của `msMsgThreadHtml`. Tin trả lời cũ hơn ngoài batch sẽ không hiện.
2. **Nhóm con — chọn thành viên** — `renderSgMembers()` liệt kê TOÀN BỘ user hệ thống qua `msContactsHtml`, không tự tích sẵn thành viên của hội thoại cha (cần callback JOIN `CHAT_PARTICIPANTS` của cha nếu muốn khớp UX "mặc định tích tất cả" của bản thiết kế gốc).
3. **`openDetail()`** chỉ là placeholder — chi tiết chứng từ thật thuộc module ERP gốc (Đơn hàng/Hóa đơn/...), nối API/region tương ứng theo `doc_type/doc_no` khi tích hợp.
4. **Reaction/Pin chưa real-time tức thời** — `msToggleReaction`/`msConvAction` vẫn chỉ ghi DB qua callback, KHÔNG broadcast SSE (giống tình trạng hiện tại của `messenger/`, xem `messenger/CLAUDE.md` "Forward-looking: cần Node broadcast"). Đồng bộ cross-client khi mở lại/refresh thread. Muốn tức thời thì thêm `nodePost('/broadcast-message', {type:'reaction'|'pin', conv_id, msg_id})` ở `applyReaction()`/`pinConv()` tương tự `broadcastMessage()`.
5. **Typing indicator** — chưa wire (messenger/ có `nodePost('/typing/:conv_id/:aus_id')` debounce 600ms → SSE → `#ms-typing-indicator`). Copy nguyên mẫu nếu cần.
6. **Real-time phụ thuộc Node chat-server đang chạy** — nếu deploy ở môi trường không có Node (`172.25.10.38:3410` không reachable), `nodePost`/`startEventPoll` tự log lỗi console và app vẫn hoạt động bình thường (mọi callback APEX không phụ thuộc Node), chỉ mất tính năng "tới ngay không cần F5".

## Message pane — react / reply / mention

- **Căn lề tin grouped:** `.msg .m-av{width:24px}` (= bề rộng `.avatar`) giữ cột cho tin grouped (`<span class="m-av"></span>` rỗng) thẳng hàng với tin đầu cụm. Đừng bỏ width này.
- **React:** nút cảm xúc ở `.hover-actions` gọi `openReactBar(this)` → thanh nổi `#reactBar` (6 emoji `REACT_EMOJIS`), `pickReact(emoji)` → `applyReaction(msgId,emoji)` (optimistic DOM + `msToggleReaction`). Chip `.reaction` mang `data-emoji`; `toggleReaction(chip)` đọc `data-emoji` (không còn hardcode 👍). Server render chip cũng phải có `data-emoji` (đã sửa trong `msMsgThreadHtml`).
- **Reply inline:** nút trả lời gọi `startReply(this)` → set `replyTo` + hiện `#replyPreview` trên composer; `sendMessage` gửi `x03=replyTo.id` (quote render sẵn trong `msMsgThreadHtml`). `openThread()` (side panel "Luồng trả lời") VẪN giữ, là nút thứ 3 trong `.hover-actions`.
- **Mention `@tên`:** chỉ highlight, KHÔNG lưu tag. Composer chèn `<span class="mention-chip" data-name>`; `serializeComposer()` chuyển chip → sentinel `@[tên]` khi gửi; `msMsgThreadHtml` `REGEXP_REPLACE` (trên biến cục bộ đã escape, không cần MATERIALIZE) bọc `@[...]` thành `<span class="mention">`. Danh sách gợi ý từ callback #17 `msMentionList` (thành viên conv, trừ chính mình), nạp ở `openConversation2` qua `loadMentionMembers`. Hệ quả: `last_msg_preview` có thể chứa raw `@[tên]` — chấp nhận tạm.

## Pitfalls (giống messenger/)

- **Mọi `<button>` phải có `type="button"`** — đã fix toàn bộ trong `chat-modal.html`, nhớ giữ khi sửa thêm.
- **`:APP_USER` auth pattern** đầu mọi callback — kiểm tra `NULL`/`'nobody'`, lookup `aus_id` từ `APP_USERS`.
- **`#roleMenu` nạp động** lúc `msInit()` qua `msRoleOptionsHtml` — đừng hard-code lại tên nhóm quyền trong HTML, sẽ lệch `gus_id` thật khi tạo Channel.
