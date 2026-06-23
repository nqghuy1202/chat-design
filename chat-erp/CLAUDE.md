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
| 18 | `msEnsureDocConv` | JSON | `materializeDraftThenSend()` (phòng ảo DOC — find-or-create phòng chung chứng từ) |
| 19 | `msRenameConv` | JSON | `renameConvFromMenu()` (đổi tên hội thoại — menu "Thêm" → "Đổi tên", chỉ participant) |

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

## Unified Entry (2 cửa vào) + Cross-doc awareness

Mô hình giống `messenger/` (xem `docs/unified-chat-architecture.md`), implement trong chat-erp:

- **2 cửa vào** phân biệt qua `sessionStorage['msEntryDoc']` set TRƯỚC khi mở modal (do trang chứng từ của app ERP cha set — NGOÀI file chat-erp):
  - Không set / rỗng → `scopeMode='all'` (icon header hệ thống, xem tất cả).
  - `setItem(JSON.stringify({doc_type,doc_no,doc_label}))` → `scopeMode='doc'` (nút "Trao đổi" chứng từ).
  - `initEntryDoc()` đọc giá trị này lúc `msInit()`, JSON hỏng → fallback `'all'`.
- **Segmented control** `#scopeBox` (`.scope-tab` data-scope `doc`/`all`, `setScope()`), chỉ hiện khi `entryDoc!=null`.
- **`msConvListHtml` nhận thêm `x04=scopeMode, x05=doc_type, x06=doc_no`.** `scope='doc'` lọc đúng chứng từ và dùng **LEFT JOIN** `CHAT_PARTICIPANTS` để người CHƯA tham gia vẫn THẤY hội thoại của chứng từ (đồng bộ chính sách mở theo chứng từ); `scope='all'` giữ nguyên (yêu cầu participant). Khi sửa, đừng đổi lại thành INNER JOIN.
- **Cross-doc:** `onChatEvent()` dùng payload đã enrich (`doc_type/doc_no/conv_type/conv_name` — broadcast ở `broadcastMessage()`); tin ngoài hội thoại đang mở → `unreadMap` + badge tổng; nếu `scopeMode='doc'` và `doc_no` khác chứng từ đang xem → `crossDocQueue` + banner `#crossdocBanner` (`viewCrossDoc()` chuyển "Tất cả" + mở hội thoại đó). KHÔNG tự nhảy hội thoại.
- **Badge tổng:** `updateGlobalBadge()` cập nhật `#msgTotalBadge` trong modal (nếu có) + gọi hook `window.msSetChatBadge(total)` của app cha để cập nhật icon launcher ở header hệ thống (DOM đó nằm ngoài chat-erp). Khởi tạo từ Node `GET /unread-summary/:aus_id` qua `initUnreadSummary()`.
- **Quyền chat chứng từ (mở hoàn toàn):** `msMsgThreadHtml` KHÔNG còn chặn người chưa-participant với `conv_type='DOC'` — thay vào đó **lazy-join** (`INSERT CHAT_PARTICIPANTS`) để có unread/last_read. DM/CHANNEL/nhóm vẫn kín.
- **Phụ thuộc:** server patch A/B/C (`docs/unified-chat-architecture.md` mục 5) phải đã deploy trên Server B (`pm2 restart chat-server`).

## Hội thoại ảo (Virtual Room) — tạo khi gửi tin đầu

Mọi luồng tạo hội thoại (DM/DOC/Nhóm/Channel) KHÔNG còn ghi DB ngay. Thay vào đó mở **phòng ảo** (chỉ state frontend), chỉ INSERT khi **gửi tin đầu tiên**. Bỏ đi mà chưa gửi → không sinh row (tránh rác). Chi tiết kiểm thử: `docs/virtual-room-stories.md`.

- **State:** `draftConv = {kind:'dm'|'doc'|'nhom'|'channel', title, ...metadata}` trong `chat-modal.fgvd.js`.
- **`openVirtualRoom(draft)`**: set header + empty-state `.ve-empty` + bật composer, `activeConvId=null`, KHÔNG đụng DB/sidebar. Nhãn `.new-chip` "Mới" ở header.
- **`sendMessage()`**: nếu `!activeConvId && draftConv` → `materializeDraftThenSend()` (tạo thật theo kind rồi `_doSend`), ngược lại gửi như cũ.
- **Materialize:** dm→`msCreateDM` (dedup), doc→`msEnsureDocConv` (#18, find-or-create + lazy-join, race-safe), nhom→`msCreateGroup`, channel→`msCreateChannel`.
- **Hủy draft:** `openConversation2()` set `draftConv=null` (mở hội thoại thật = bỏ phòng ảo). `closeCompose()` KHÔNG hủy draft (để openVirtualRoom dùng được).
- **DOC entry:** `maybeOpenDocRoom()` chạy 1 lần sau `loadConvList` đầu khi scope='doc' — mở phòng THẬT nếu đã có (`.doc-item:not(.subgroup)`), hoặc phòng ảo nếu chưa.
- **Race phòng chung DOC:** UNIQUE INDEX `uq_doc_main` (functional, chỉ ràng buộc `conv_type='DOC' AND parent_conv_id IS NULL`) trong `schema-additions.sql` — **chạy DDL TRƯỚC** khi tạo callback `msEnsureDocConv`.
- **Nhóm con:** KHÔNG ảo hóa — parent phải là phòng thật (giữ guard `activeConvId` trong `openCreateSubgroup`).
- **Các callback `msCreateDM/Group/Channel` giữ nguyên**, chỉ đổi thời điểm frontend gọi (lúc gửi tin đầu).
- **Picker DM kiểu Messenger:** `msContactsHtml` (và `msGlobalSearchHtml` phần "Người") trả thêm `data-conv`/tham số `dm_conv` = conv_id của DM đã tồn tại với người đó. `pickerSubmit`/`gsPickPerson`: có DM cũ → `openConversation2(dm)` (load lịch sử); chưa có → `openVirtualRoom` DM. Tránh mở phòng ảo trống khi đã có hội thoại.
- **Thanh "Tới:" + dropdown nhân viên giàu thông tin (kiểu Messenger, thay cho picker pane):** `compose-btn` (và ⌘N) gọi `startNewConversation()` → mở thanh `#newConvBar` (label "Tới:" + chips `#ncChips` + `<input id="ncInput">` + dropdown `#ncList`) ngay trên đầu khung chat, ĐỒNG THỜI hiện phòng chat ảo trống + composer sẵn sàng. **Dropdown là panel tùy biến (KHÔNG dùng `<datalist>` native):** `ncSearch(q)` gọi `msContactsHtml`, parse `.person` → `ncDir[id]={name,hue,dm,code,pos,online,avInner}` rồi `ncRenderRows()` dựng dòng = **avatar (ảnh thật/chữ cái) + chấm online + tên + mã NV (mono) + chức danh + nút ＋**. Có skeleton loading (`ncRenderSkeleton`), empty state, hover/active, điều hướng bàn phím (`ncInputKey`: ↑↓ `ncMoveActive`, Enter `ncPick`, Esc đóng list, Backspace xóa chip cuối). Click ra ngoài thanh → đóng list (bỏ qua `.compose-btn`). Chọn người = `ncPick→addRecipient` (chip vào ô "Tới:", list làm mới bỏ người đã chọn). Mỗi lần thêm/bớt gọi `applyDraftFromSelection()`: 0 người → empty-state; 1 người có DM cũ → `openConversation2(dm, true)` (load lịch sử, GIỮ thanh "Tới:" qua `keepCompose`); 1 chưa có DM → `openVirtualRoom({kind:'dm'})`; ≥2 → `openVirtualRoom({kind:'nhom'})` tên tự sinh `autoGroupName()`. Gửi tin đầu (`_doSend`) / điều hướng hội thoại khác → `exitComposeBar()`. Esc (ngoài list) → `cancelNewConv()`.
- **Avatar nhóm ghép thành viên (kiểu Zalo):** `msConvListHtml` có hàm lồng `grp_avatar(conv_id)` ghép tối đa 2 avatar thành viên (ảnh thật + fallback chữ cái, ưu tiên người KHÁC mình) vào `.grp-av > .a1/.a2`. Áp dụng cho **nhóm riêng tư + nhóm con**; **channel** giữ icon `#` (công khai, có thể rất đông); DOC vẫn dùng icon file. Trước đây avatar nhóm bị hardcode chữ "N" tím — nay đã nối dữ liệu thật. CSS `.grp-av .a img` + `.a1:only-child` (1 thành viên → căn giữa) trong `chat-modal.css`. **Cần paste đè callback #2 `msConvListHtml` khi deploy.**
  - **Callback `msContactsHtml` (#8) cập nhật:** thêm `data-code` (mã NV — hiện = `TO_CHAR(e.emp_id)`, đổi token nếu có cột mã người-đọc-được), `data-pos` (chức danh), `data-online` (join `CHAT_USER_ONLINE`, cutoff 35s) trên mỗi `.person`; tìm kiếm match cả mã. Cấu trúc `.person/.pa/.pinfo/.ptick` giữ nguyên cho picker cũ. **Cần paste đè callback #8 + thêm cột mã/online khi deploy.**
- **Pane cũ `#composePicker`/`#composeGroup` + hàm `openPeoplePicker/renderPeople/togglePerson/pickerSubmit/openCreateGroup` giờ KHÔNG còn lối vào** (giữ lại trong file, không hiển thị) — đừng nối lại; flow soạn mới đi qua `#newConvBar`/`startNewConversation`. "Channel mới" nay là nút trong `#newConvBar` (gọi `openCreateChannel()`).
- **Đổi tên hội thoại sau khi tạo:** menu "Thêm" (`#moreMenu`) có mục "Đổi tên" (`#mmRename`, ẩn với DM qua `activeConvKind!=='canhan'`) → `renameConvFromMenu()`. Nếu đang ở phòng ảo (`draftConv && !activeConvId`) chỉ cập nhật state cục bộ (`draftConv.name/title`), tên thật được ghi khi materialize gửi tin đầu. Nếu hội thoại đã thật → gọi callback `msRenameConv` (#19, chỉ participant mới đổi được) rồi refresh `hName` + `loadConvList()`.

## Info panel & nhịp tin nhắn

- **DM (canhan) KHÔNG hiện danh sách "Thành viên"** — `msInfoHtml` rẽ nhánh `ELSIF l_kind <> 'canhan'`. Channel giữ "Nhóm quyền", nhóm/chứng từ giữ "Thành viên".
- **Nhịp tin:** `.msg` padding dọc nhỏ (2px); tách cụm bằng `.msg:not(.grouped){margin-top:10px}`; tin sau `.date-sep`/`.unread-divider` không bị đẩy xa. Ngưỡng gom nhóm `<10 phút` ở `msMsgThreadHtml`.
- **Tạo Channel** truy cập trực tiếp từ menu compose (`#composeMenu` → "Channel mới" → `openCreateChannel()`).

## Message pane — react / reply / mention

- **Căn lề tin grouped:** `.msg .m-av{width:24px}` (= bề rộng `.avatar`) giữ cột cho tin grouped (`<span class="m-av"></span>` rỗng) thẳng hàng với tin đầu cụm. Đừng bỏ width này.
- **React:** nút cảm xúc ở `.hover-actions` gọi `openReactBar(this)` → thanh nổi `#reactBar` (6 emoji `REACT_EMOJIS`), `pickReact(emoji)` → `applyReaction(msgId,emoji)` (optimistic DOM + `msToggleReaction`). Chip `.reaction` mang `data-emoji`; `toggleReaction(chip)` đọc `data-emoji` (không còn hardcode 👍). Server render chip cũng phải có `data-emoji` (đã sửa trong `msMsgThreadHtml`).
- **Reply inline:** nút trả lời gọi `startReply(this)` → set `replyTo` + hiện `#replyPreview` trên composer; `sendMessage` gửi `x03=replyTo.id` (quote render sẵn trong `msMsgThreadHtml`). `openThread()` (side panel "Luồng trả lời") VẪN giữ, là nút thứ 3 trong `.hover-actions`.
- **Mention `@tên`:** chỉ highlight, KHÔNG lưu tag. Composer chèn `<span class="mention-chip" data-name>`; `serializeComposer()` chuyển chip → sentinel `@[tên]` khi gửi; `msMsgThreadHtml` `REGEXP_REPLACE` (trên biến cục bộ đã escape, không cần MATERIALIZE) bọc `@[...]` thành `<span class="mention">`. Danh sách gợi ý từ callback #17 `msMentionList` (thành viên conv, trừ chính mình), nạp ở `openConversation2` qua `loadMentionMembers`. Hệ quả: `last_msg_preview` có thể chứa raw `@[tên]` — chấp nhận tạm.

## Pitfalls (giống messenger/)

- **Real-time NHẬN phụ thuộc app cha (1503), KHÔNG phải chat-erp.** chat-erp chỉ NGHE `apex:chatEvent` mà `global.js`/`sse-worker.js` của app cha phát ra (xem mục "Kênh NHẬN"). Chuỗi bootstrap dễ đứt nhất — đã gây mất cả buổi debug:
  1. **`window.APP_FILES` PHẢI được set trên app cha 1503.** `global.js:13` dựng worker URL = `(window.APP_FILES||'') + 'sse-worker.js'`. Nếu `APP_FILES` undefined → URL tương đối `sse-worker.js` → 404 trả HTML → `SharedWorker` chết với `Uncaught SyntaxError: Unexpected token '<'` → **không SSE → không ai nhận tin** (broadcast của sender vẫn "OK" vì gọi Node trực tiếp, đánh lừa là đang chạy). `apex.env.APP_FILES` = undefined trong APEX 24.2 — đừng dùng.
  2. **Page 0 (Global Page) KHÔNG có ô "Function and Global Variable Declaration".** Set `window.APP_FILES` bằng **Static Content Region trên Page 0** với `<script>window.APP_FILES="#APP_FILES#";</script>` (source region được substitution; chạy trong body trước `global.js` vốn chờ `$(document).ready`).
  3. **`#APP_FILES#` chỉ substitution ở vùng render qua engine** (page attribute / region source / template) — KHÔNG trong file tĩnh `.js` hay mục "JavaScript → File URLs". Đặt nhầm chỗ → ra literal `#APP_FILES#sse-worker.js`.
  4. **`sse-worker.js` phải upload vào Static Application Files của CHÍNH app 1503** (vì `#APP_FILES#` resolve theo app đang chạy global.js), không phải app 1002.
  - **Chẩn đoán nhanh** (console cửa sổ CHA người nhận): `sseToken` mint ra token 2 phần `abc.def` = secret OK; `chrome://inspect/#workers` không thấy worker chạy / console worker báo lỗi `<` = sai URL; raw SSE stream `data:{"type":"message",...}` xuất hiện trong Network của worker = SSE đã nhận → nếu vẫn không refresh thì lỗi nằm ở `onChatEvent` của iframe. EventSource mở TRONG SharedWorker nên KHÔNG hiện ở Network của trang — phải xem qua `chrome://inspect`. State worker (chạy trong console của worker): `console.log({has_EventSource:!!_es,_connecting,_tokenRequested,ports:ports.length})` — `has_EventSource:false`+`_connecting:true` = kẹt chờ token (tab leader chết).

- **Test 2 user phải DÙNG 2 TRÌNH DUYỆT/PROFILE/ẩn-danh KHÁC NHAU.** `sse-worker.js` là SharedWorker dùng chung mọi tab cùng origin trong 1 trình duyệt, chỉ giữ **1 SSE = 1 token = 1 aus_id** (leader mint). 2 user cùng 1 browser → chỉ user-leader nhận được → real-time **một chiều** (B→A chạy, A→B không). Đây là giới hạn bản chất, không phải bug — production mỗi user 1 máy nên không gặp.

- **Cross-origin SSE bị Brave (và privacy browser) chặn.** Trang APEX `erp.greensys.vn:8211` ↔ SSE `chattest.erp100.vn` là **khác domain**; Brave Shields chặn cookie/connection cross-site → worker nạp được (static cùng origin) nhưng `/api/sse` cross-origin **không mở / không có `: ping`**, không báo lỗi rõ. Test bằng Chrome/Edge/Firefox hoặc tắt Shields. **Khuyến nghị dài hạn:** reverse-proxy SSE về **cùng origin** với APEX (vd `erp.greensys.vn:8211/chat-api/` → Node), nginx PHẢI có `proxy_buffering off` + `proxy_read_timeout` dài cho SSE; rồi đổi `system_paras.NODEJS` + `NODE_URL` sang same-origin → hết CORS + hết Brave.

- **Mọi `<button>` phải có `type="button"`** — đã fix toàn bộ trong `chat-modal.html`, nhớ giữ khi sửa thêm.
- **`:APP_USER` auth pattern** đầu mọi callback — kiểm tra `NULL`/`'nobody'`, lookup `aus_id` từ `APP_USERS`.
- **`#roleMenu` nạp động** lúc `msInit()` qua `msRoleOptionsHtml` — đừng hard-code lại tên nhóm quyền trong HTML, sẽ lệch `gus_id` thật khi tạo Channel.
