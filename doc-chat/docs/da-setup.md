# Doc Chat (Page 10022710201) — Setup bằng Dynamic Action

Chuyển `doc-chat/doc-chat-page.js` (1 IIFE nhồi vào "Execute when Page Loads") sang
**FGVD + Dynamic Action** để né giới hạn ký tự. Cùng pattern với Messenger
(xem `docs/chat-system-da-setup.md`), khác ở vài chỗ đặc thù iframe.

## Phân bổ code (3 chỗ)

| Chỗ trong APEX | Nội dung | File nguồn |
|---|---|---|
| **Function and Global Variable Declaration** | State + hàm + 2 binding giữ lại (apex:chatEvent, unload). Expose `window.dc*`. | `doc-chat/doc-chat-page.fgvd.js` |
| **Execute when Page Loads** | Chỉ `window.dcInit();` | `doc-chat/doc-chat-page.onload.js` |
| **Dynamic Actions** | 19 DA, mỗi DA gọi 1 hàm `window.dcOn*`. | Bảng dưới |

> `window.CHAT_AUS_ID = &G_AUS_ID.;` và `var pageId = $v('pFlowStepId');` đã nằm ở **đầu FGVD**.

## Quy ước chung cho MỌI DA

- **Selection Type:** `jQuery Selector`
- **Event Scope:** `Dynamic` — **Static Container (jQuery Selector):** `#doc-chat-root`
  - ⚠ Bắt buộc với phần tử server render bằng `innerHTML` (`.convo-item`, `.member-suggest-item`,
    `.msg-hover-action`, `.member-chip`, `.lp-filter-chip`). Đặt `Dynamic` cho tất cả là an toàn.
- **Fire on Initialization:** `No`
- **True Action:** `Execute JavaScript Code`.
- Trong ô JS luôn truyền: `this.triggeringElement` và `this.browserEvent`.
- Sự kiện `input`: chọn **Event = `Custom`**, **Custom Event = `input`** (APEX không có sẵn "Input").

---

## Bảng 19 Dynamic Action

| # | Tên DA | Event | jQuery Selector | Ô "Execute JavaScript Code" |
|---|--------|-------|-----------------|------------------------------|
| 1 | Chọn hội thoại | Click | `.convo-item[data-conv-id]` | `window.dcOnConvClick(this.triggeringElement, this.browserEvent);` |
| 2 | Lọc theo loại | Click | `.lp-filter-chip[data-filter], .convo-tab[data-filter]` | `window.dcOnFilter(this.triggeringElement, this.browserEvent);` |
| 3 | Tìm kiếm hội thoại | Custom `input` | `#dc-conv-search` | `window.dcOnConvSearch(this.triggeringElement, this.browserEvent);` |
| 4 | Bật/tắt thanh tìm tin | Click | `#dc-btn-search-toggle` | `window.dcOnSearchToggle(this.triggeringElement, this.browserEvent);` |
| 5 | Tìm trong hội thoại | Custom `input` | `#dc-msg-search-input` | `window.dcOnMsgSearch(this.triggeringElement, this.browserEvent);` |
| 6 | Bật/tắt panel thông tin | Click | `#dc-btn-info` | `window.dcOnToggleInfo(this.triggeringElement, this.browserEvent);` |
| 7 | Bắt đầu trả lời | Click | `.msg-hover-action[data-reply-id]` | `window.dcOnReplyStart(this.triggeringElement, this.browserEvent);` |
| 8 | Hủy trả lời | Click | `#dc-reply-cancel` | `window.dcOnReplyCancel(this.triggeringElement, this.browserEvent);` |
| 9 | Gửi tin nhắn | Click | `#dc-btn-send` | `window.dcOnSend(this.triggeringElement, this.browserEvent);` |
| 10 | Phím trong ô nhập | Key Down | `#dc-msg-input` | `window.dcOnMsgKeydown(this.triggeringElement, this.browserEvent);` |
| 11 | Tự giãn ô nhập | Custom `input` | `#dc-msg-input` | `window.dcOnMsgAutosize(this.triggeringElement, this.browserEvent);` |
| 12 | Chọn/bỏ thành viên | Click | `#dc-member-suggest-list .member-suggest-item` | `window.dcOnMemberToggle(this.triggeringElement, this.browserEvent);` |
| 13 | Bỏ chip thành viên | Click | `.member-chip .x` | `window.dcOnChipRemove(this.triggeringElement, this.browserEvent);` |
| 14 | Tìm danh bạ | Custom `input` | `#dc-contact-search` | `window.dcOnContactSearch(this.triggeringElement, this.browserEvent);` |
| 15 | Đổi loại hội thoại | Change | `input[name="dc-conv-type"]` | `window.dcOnTypeTab(this.triggeringElement, this.browserEvent);` |
| 16 | Mở soạn tin cá nhân | Click | `#dc-btn-dm` | `window.dcOnOpenDM(this.triggeringElement, this.browserEvent);` |
| 17 | Mở soạn nhóm | Click | `#dc-btn-group, #dc-btn-create` | `window.dcOnOpenGroup(this.triggeringElement, this.browserEvent);` |
| 18 | Đóng màn hình soạn | Click | `#dc-compose-back, #dc-compose-close, #dc-create-cancel` | `window.dcOnCloseCompose(this.triggeringElement, this.browserEvent);` |
| 19 | Tạo hội thoại | Click | `#dc-create-submit` | `window.dcOnSubmitCreate(this.triggeringElement, this.browserEvent);` |

### Lưu ý từng DA
- **#10 (Key Down):** chỉ `Ctrl+Enter` mới gửi; logic kiểm tra `ev.ctrlKey` nằm trong hàm —
  KHÔNG đặt "When Key" trong DA, để mọi phím đều gọi hàm (phím khác → báo typing).
- **#3, #5, #11, #14:** dùng `Custom` event tên `input` để bắt cả paste.
- **#7, #13:** hàm tự gọi `ev.stopPropagation()` → bắt buộc truyền `this.browserEvent`.
- **#15 (Change):** `openCompose` KHÔNG còn dùng `.trigger('change')` — nó gọi thẳng `applyConvType()`.
  DA chỉ phụ trách khi user bấm tab đổi loại. (Đây là khác biệt so với bản cũ — xem FGVD.)
- **#17:** gộp `#dc-btn-group` và `#dc-btn-create` (cùng mở chế độ tạo nhóm) vào 1 DA.

---

## KHÔNG làm DA — giữ trong FGVD (đã có sẵn trong file)

| Binding | Vì sao không làm DA |
|---|---|
| `$eventDoc.on('apex:chatEvent', onChatEvent)` | Custom event mang payload qua jQuery trigger của **trang cha** (iframe). DA không lấy được tham số trigger, và phải bind bằng jQuery trang cha — DA framework không làm được. |
| `$(window).on('unload', …)` | Gỡ handler khỏi parent document khi modal đóng, tránh stale handler. Sự kiện `unload` của window không map sang DA. |

> Cả hai dựa vào biến `$eventDoc`/`onChatEvent` trong closure — đặt ở FGVD là đúng chỗ.

---

## Checklist deploy (paste tay — Page 10022710201)

1. **Function and Global Variable Declaration:** xóa nội dung cũ (nếu chỉ có `var pageId=…` thì
   thay luôn), paste toàn bộ `doc-chat-page.fgvd.js`.
2. **Execute when Page Loads:** xóa IIFE `doc-chat-page.js` cũ + dòng `window.CHAT_AUS_ID=…`,
   paste `doc-chat-page.onload.js` (chỉ `window.dcInit();`).
3. **Tạo 19 Dynamic Action** theo bảng (Scope Dynamic / Container `#doc-chat-root` / Fire on Init = No).
4. **Giữ nguyên:** skeleton HTML `#doc-chat-root`, CSS Inline, 7 Ajax Callback hiện có
   (`dcConvListHtml`, `dcMsgThreadHtml`, `dcInfoHtml`, `dcContactsHtml`, `docChatCreate`,
   `docChatSend`, `docChatRead`, `docChatTyping`).
5. **DA mở modal trên trang ERP** (`#Btn_DocChat`) không đổi — vẫn nằm ở trang cha, không thuộc page này.

## Kiểm thử nhanh
- Mở modal từ chứng từ → list load + doc fields hiện (dcInit + injectDocFields).
- Click hội thoại (innerHTML) → mở thread ⇒ xác nhận **Scope Dynamic**.
- "Tạo nhóm" → đổi tab DM/Nhóm (DA#15) → ô tên nhóm ẩn/hiện đúng (xác nhận `applyConvType` thay cho `.trigger('change')`).
- Gửi tin / Ctrl+Enter / reply / tìm trong hội thoại.
- Realtime: tab khác gửi → thread cập nhật; đóng modal rồi mở lại → không double event (unload cleanup).
