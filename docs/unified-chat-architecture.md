# Unified Chat — Kiến trúc & Luồng hoạt động

> Tài liệu nghiên cứu cho việc hợp nhất `doc-chat` + `messenger` thành **một modal chat dùng chung**, với hai cửa vào và cơ chế "biết tin nhắn ở chứng từ khác khi đang ở chứng từ này" (cross-doc awareness).
>
> Phạm vi đợt này: prototype `nexus-pure-v2.html` + patch server `chat.js`. Việc gộp 2 page APEX để vòng sau (mục 8).

---

## 1. Mục tiêu

1. **Một modal, hai cửa vào** — cùng giao diện, chỉ khác tham số khởi tạo:
   - Icon tin nhắn ở header hệ thống → xem **tất cả** hội thoại.
   - Nút "Trao đổi" ở right column của một chứng từ → mở **scoped** vào chứng từ đó, nhưng chuyển sang "Tất cả" được.
2. **Cross-doc awareness** — đang đọc chứng từ A mà có tin mới ở chứng từ B (hoặc DM/nhóm bất kỳ) thì người dùng vẫn biết và mở được, không phải đóng modal đi tìm.
3. **Tối ưu real-time** dựa trên hạ tầng SSE hiện có, thay đổi backend ở mức additive.

---

## 2. Mô hình dữ liệu — điểm chỉnh quan trọng

Hiểu nhầm phổ biến: "một chứng từ = một hội thoại". **Sai.** Mô hình thật trong DB:

```
CHAT_CONVERSATIONS
  conv_id        PK
  conv_type      DM | CHANNEL
  name           (CHANNEL mới có)
  doc_type       NULL = hội thoại chung; 'SO'/'HD'/'PC'... = gắn chứng từ
  doc_no         số chứng từ
```

→ **Một chứng từ (doc_type + doc_no) có thể có NHIỀU hội thoại**: ví dụ đơn hàng `SO-2024-018` có 1 nhóm "Duyệt đơn", 1 DM kế toán ↔ kho. Cả hai cùng `doc_type='SO', doc_no='SO-2024-018'`.

Hệ quả cho mọi tầng:
- **Sidebar scoped** = list các hội thoại cùng `doc_type+doc_no`, KHÔNG phải một item.
- **Prototype** phải đổi: `voucher` không còn là 1 conversation, mà là **1 document** chứa nhiều conversation. Mỗi conversation có thêm field `docType`, `docNo`, `docLabel`.

---

## 3. Hai cửa vào — tham số khởi tạo

| Cửa vào | Tham số mở | scopeMode mặc định | Sidebar mở đầu |
|---|---|---|---|
| Header icon | `entryDoc = null` | `'all'` | Toàn bộ hội thoại (DM / nhóm / chứng từ / bot), có section |
| Nút "Trao đổi" chứng từ | `entryDoc = { type, no, label }` | `'doc'` | Segmented control **[Chứng từ này] [Tất cả]**, mặc định lọc đúng chứng từ |

Trong APEX thật, `entryDoc` truyền qua `sessionStorage('docChatCtx')` (giống doc-chat hiện tại). Header icon set `sessionStorage` rỗng/null trước khi mở.

**Segmented control** (chỉ hiện khi `entryDoc != null`):
- Tab "Chứng từ này" → `renderConvList()` lọc `c.docNo === entryDoc.no`.
- Tab "Tất cả" → bỏ lọc, render section đầy đủ + một section "Đang xem" ghim hội thoại của chứng từ hiện tại lên đầu.

---

## 4. Cross-doc awareness — luồng event-driven

### 4.1 Vì sao tín hiệu đã sẵn sàng

SSE giữ **1 kết nối / user** keyed theo `aus_id` (`events.js#sseConnections`). `deliverToConv()` đẩy event tới **từng thành viên**, bất kể họ đang mở hội thoại nào:

```
POST /send (conv của chứng từ B)
  → chat.js deliverToConv(convB) → deliverToUser(ausId) cho mỗi member
  → SSE stream của user (đang mở chứng từ A) NHẬN event
```

→ Không cần polling, không cần kết nối thêm. Tín hiệu tới nơi. Vấn đề chỉ là **payload không đủ ngữ cảnh**.

### 4.2 Điểm nghẽn

Payload hiện tại:

```js
{ type: 'message', conv_id, msg }   // thiếu doc_type, doc_no, tên hội thoại
```

Khi đang ở chứng từ A nhận `conv_id` lạ, frontend không biết nó thuộc chứng từ B nếu chưa load full conv list (chế độ scoped thì chưa load). → không render nổi banner "Tin mới ở chứng từ B".

### 4.3 Giải pháp: enrich payload (thay đổi A)

Bổ sung ngữ cảnh vào event tại nguồn:

```js
{
  type: 'message',
  conv_id,
  doc_type,        // 'SO' | null
  doc_no,          // 'SO-2024-018' | null
  conv_type,       // 'DM' | 'CHANNEL'
  conv_name,       // tên hiển thị hội thoại (CHANNEL: name; DM: tên người gửi)
  msg
}
```

Frontend xử lý mỗi event `message`:

```
if (conv_id === activeConvId)        → append vào thread (như cũ)
else                                  → tăng unread[conv_id]; cập nhật badge tổng
   if (scopeMode === 'doc' && doc_no !== entryDoc.no)
        → đẩy vào hàng đợi "ngoài scope" → hiện banner cross-doc
```

Không cần round-trip lookup nào cho mỗi tin tới. Đây là mảnh quan trọng nhất.

### 4.4 Hai lớp hiển thị

1. **Badge tổng** trên icon tin nhắn ở header hệ thống = tổng unread mọi hội thoại. Khởi tạo từ `unread-summary` (thay đổi C), cập nhật tăng dần từ event đã enrich.
2. **Banner trong modal** (dưới chat header): khi `scopeMode === 'doc'` và có tin ngoài scope →
   `ⓘ {n} tin mới ở hội thoại khác → [Xem]`. Bấm [Xem] = chuyển segmented sang "Tất cả" + mở hội thoại mới nhất ngoài scope.

---

## 5. Thay đổi server (đều additive, backward-compatible)

> File: `C:\greensys\chat-server\chat.js`. Không đụng `events.js` / `cqn.js` / `server.js`.
> Buffer replay (`events.js` BUFFERABLE) đã whitelist `message` nên event enrich tự động replay đúng khi reconnect.

### A. Enrich `message` event — POST /send

Tại bước commit, đã `UPDATE CHAT_CONVERSATIONS ... WHERE conv_id`. Thêm một SELECT lấy `doc_type, doc_no, conv_type, name` của conv (hoặc gộp vào RETURNING), rồi đính vào payload `deliverToConv`. `conv_name` cho DM = `from_name` (người gửi); cho CHANNEL = `c.name`.

**Rủi ro:** thấp. Thêm field, client cũ bỏ qua field thừa.

### B. Endpoint conv "tất cả" — GET /conversations

Hiện hard-filter `WHERE c.doc_type IS NULL`. Thêm query param `?scope=all`:
- `scope=all` → bỏ filter, SELECT thêm cột `c.doc_type, c.doc_no`.
- mặc định (không param) → giữ nguyên `doc_type IS NULL` (backward-compat cho messenger cũ).

**Rủi ro:** thấp. Đường cũ không đổi.

### C. Endpoint unread-summary — GET /unread-summary/:aus_id

Route mới, trả:

```json
{ "total": 7,
  "by_conv": [ { "conv_id": 42, "unread": 2, "doc_type": "SO", "doc_no": "SO-2024-018" } ],
  "by_doc":  [ { "doc_type": "SO", "doc_no": "SO-2024-018", "unread": 2 } ] }
```

Dùng cùng công thức `unread_count` (msg_id > last_read_msg_id) đã có trong GET /conversations, gom theo conv và theo doc. Phục vụ badge tổng + số banner lúc mở / sau reconnect.

**Rủi ro:** không (route mới, không chạm route cũ).

---

## 6. State frontend (prototype & React tương lai)

| State | Ý nghĩa |
|---|---|
| `entryDoc` | `null` (header) hoặc `{ type, no, label }` (chứng từ) |
| `scopeMode` | `'all'` \| `'doc'` |
| `activeConvId` | hội thoại đang mở |
| `unread` map | `convId → số chưa đọc` (nguồn cho badge + số dòng) |
| `crossDocQueue` | danh sách `{convId, docNo, convName}` tin tới ngoài scope (nguồn cho banner) |

`renderConvList()` đọc `scopeMode` + `entryDoc` để lọc. `updateGlobalBadge()` = sum(unread). `showCrossDocBanner()` đọc `crossDocQueue`.

---

## 7. UX rationale (research-1.0.0 + đối chiếu Slack/Zalo/Messenger)

- **Segmented control > filter dropdown** cho 2 lựa chọn loại trừ nhau (scoped/all): 1 thao tác, luôn thấy trạng thái hiện tại, không giấu lựa chọn sau menu. (Nielsen: visibility of system status.)
- **Banner thay vì toast** cho cross-doc: toast biến mất, người đang tập trung dễ bỏ lỡ; banner sticky dưới header, không che nội dung, tự gom số (`n tin mới`) → giảm nhiễu so với nhiều toast.
- **Badge tổng tách khỏi badge từng dòng**: badge header = "có việc cần xem ở đâu đó", badge dòng = "ở đúng hội thoại này". Hai mức nhận thức khác nhau, không gộp.
- **"Đang xem" pin ở tab Tất cả**: giữ ngữ cảnh chứng từ vừa rời để quay lại nhanh — giảm tải nhớ (recognition over recall).
- Không tự động nhảy hội thoại khi có tin mới — luôn để người dùng chủ động bấm [Xem]. Tránh giật ngữ cảnh khi đang gõ.

---

## 8. Vòng sau — gộp 2 page APEX (ghi chú, chưa làm)

- Hợp nhất `doc-chat` (page 10022710201) và `messenger` thành **một page**; `entryDoc` quyết định scopeMode lúc `dcInit()/msInit()`.
- Thống nhất bộ callbacks: thêm param `scope` cho conv-list callback; thêm callback `chatUnreadSummary`.
- Giữ `:APP_USER` auth pattern, `type="button"`, MATERIALIZE hint như hiện tại.
- CSS scope chung `#chat-root` thay vì 2 scope `#doc-chat-root` / `#ms-root`.

---

## 9. Checklist triển khai đợt này

- [x] **A** — enrich `message` event trong `chat.js` POST /send
- [x] **B** — `?scope=all` cho GET /conversations
- [x] **C** — route GET /unread-summary/:aus_id
- [x] Prototype: data model document → nhiều conversation (chứng từ SO-2024-018 có 2 hội thoại)
- [x] Prototype: 2 cửa vào (header icon / nút Trao đổi) + segmented control
- [x] Prototype: banner cross-doc + badge tổng + nút giả lập tin mới
- [ ] Test server trên Server B: `npm run test:connection` rồi `pm2 restart chat-server`
- [ ] (vòng sau) gộp 2 page APEX + callback `chatUnreadSummary` + param `scope`
