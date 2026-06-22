# chat-erp — User Stories & Kịch bản kiểm thử (bmad)

> Tài liệu nghiên cứu luồng + kiểm thử cho module chat production `chat-erp/` (APEX page 10022710202).
> Mục tiêu: đơn giản nhưng đủ chức năng. Mức nghiêm trọng (Severity) theo research-1.0.0: 1=Cosmetic, 2=Minor, 3=Major, 4=Catastrophic.
> AC viết dạng Given-When-Then. Trạng thái: ✅ đã xử lý đợt này · 🔜 Phase 2 · 🧪 cần kiểm thử thủ công trên APEX.

---

## Epic 1 — Hai cửa vào (Unified Entry) 🔜

**Mục tiêu:** một modal, hai cửa vào, chỉ khác tham số khởi tạo (`sessionStorage['msEntryDoc']`).

### US-1.1 — Mở từ icon tin nhắn ở header hệ thống
> Là **nhân viên**, tôi muốn bấm icon chat ở header để xem **tất cả** hội thoại của mình, để nắm toàn bộ trao đổi ở một nơi.

- **AC1** — Given không set `msEntryDoc`, When mở modal, Then `scopeMode='all'`, sidebar hiện đủ 4 section (chứng từ/channel/nhóm/cá nhân), KHÔNG hiện segmented control.
- **AC2** — Given scopeMode='all', When có hội thoại mới/đổi, Then danh sách cập nhật bình thường.
- **Edge:** `msEntryDoc` tồn tại nhưng JSON hỏng → fallback `'all'`, không vỡ giao diện. (Severity 3)

### US-1.2 — Mở từ nút "Trao đổi" ở trang chứng từ
> Là **người xử lý chứng từ**, tôi muốn bấm "Trao đổi" để mở đúng hội thoại của chứng từ đang xem, để khỏi phải tìm trong danh sách.

- **AC1** — Given `msEntryDoc={doc_type,doc_no,doc_label}` set trước khi mở, When modal mở, Then `scopeMode='doc'`, sidebar lọc đúng `doc_type+doc_no`, hiện segmented `[Chứng từ này][Tất cả]` (mặc định "Chứng từ này").
- **AC2** — Given 1 chứng từ có nhiều hội thoại (DM kế toán↔kho + nhóm "Duyệt đơn"), When scope DOC, Then thấy **cả tập** hội thoại cùng chứng từ, không phải 1 item.
- **Edge:** chứng từ chưa có hội thoại nào → empty-state "Chưa có trao đổi cho chứng từ này" + nút tạo. (Severity 3)

### US-1.3 — Chuyển "Chứng từ này" ↔ "Tất cả"
> Là người dùng đang scope chứng từ, tôi muốn xem nhanh tất cả hội thoại khác rồi quay lại, để không mất ngữ cảnh chứng từ.

- **AC1** — Given scope DOC, When bấm "Tất cả", Then bỏ lọc + section "Đang xem" ghim hội thoại của chứng từ hiện tại lên đầu.
- **AC2** — When bấm lại "Chứng từ này", Then lọc về đúng chứng từ.
- **Edge:** đổi scope khi đang mở 1 hội thoại → giữ nguyên thread đang mở, chỉ đổi danh sách bên trái. (Severity 2)

---

## Epic 2 — Cross-doc awareness 🔜

**Mục tiêu:** đang scope chứng từ A mà có tin ở B/DM/nhóm khác thì vẫn biết và phản hồi được.

### US-2.1 — Nhận biết tin ngoài scope
> Là người dùng đang đọc chứng từ A, tôi muốn được báo khi có tin ở hội thoại khác, để không bỏ lỡ.

- **AC1** — Given scope DOC-A, When tới event `message` của conv ngoài scope (đã enrich `doc_type/doc_no/conv_type/conv_name`), Then badge tổng ở icon header tăng + banner `n tin mới ở hội thoại khác → [Xem]`.
- **AC2** — Given nhiều tin từ nhiều hội thoại, When dồn, Then banner gom số (không spam nhiều toast).
- **Edge:** tin của chính hội thoại đang mở → append vào thread, KHÔNG đẩy banner. (Severity 3)
- **Edge:** SSE reconnect → khởi tạo lại badge/số từ `GET /unread-summary/:aus_id`. (Severity 3)

### US-2.2 — Xem & phản hồi tin ngoài scope
> Là người dùng, tôi muốn 1 chạm để nhảy tới hội thoại có tin mới rồi trả lời.

- **AC1** — When bấm [Xem] trên banner, Then segmented chuyển "Tất cả" + mở hội thoại mới nhất ngoài scope; gửi trả lời được ngay.
- **AC2** — Given đang gõ ở hội thoại hiện tại, When có tin mới ngoài scope, Then KHÔNG tự nhảy (chỉ báo) — tránh giật ngữ cảnh.
- **Severity 4** nếu tự nhảy làm mất nội dung đang soạn.

---

## Epic 3 — Tạo hội thoại (DM / Nhóm / Channel / Nhóm con)

### US-3.1 — Tạo Channel từ menu compose ✅
> Là **trưởng nhóm**, tôi muốn tạo channel công khai theo nhóm quyền, để thông tin tới đúng đối tượng.

- **AC1** — ✅ Given mở menu compose, When chọn "Channel mới", Then hiện pane tạo channel (`#composeChannel`).
- **AC2** — 🧪 Given để trống nhóm quyền, When tạo, Then channel hiện cho **toàn công ty**.
- **AC3** — 🧪 Given chọn nhóm quyền, When tạo, Then chỉ user thuộc `CHAT_CHANNEL_ROLES` thấy channel (logic `msConvListHtml` đã có).
- **Edge:** tên trống → báo lỗi `#chErr`, không tạo. (Severity 2)
- **Edge:** trùng tên channel → cho phép (phân biệt bằng conv_id) hoặc cảnh báo — quyết định: cho phép. (Severity 1)

### US-3.2 — DM / Nhóm / Nhóm con 🧪
- **AC** — chọn 1 người → DM; ≥2 người → nhóm; từ menu hội thoại → nhóm con (`parent_conv_id`).
- **Edge:** nhóm con kế thừa `doc_type/doc_no` của cha. (Severity 2)

---

## Epic 4 — Quyền chat theo chứng từ ✅ (logic) / 🔜 (discovery)

### US-4.1 — Ai vào được chứng từ đều chat được ✅
> Là **người liên quan chứng từ**, tôi muốn mở "Trao đổi" là đọc & gửi được, dù chưa từng tham gia.

- **AC1** — ✅ Given user chưa là participant của hội thoại `conv_type='DOC'`, When mở thread, Then ĐỌC được (không còn "Không có quyền").
- **AC2** — ✅ When mở/gửi lần đầu, Then tự thêm vào `CHAT_PARTICIPANTS` (lazy-join) → có unread/last_read + xuất hiện ở danh sách "Chứng từ".
- **AC3** — ✅ Given hội thoại DM/CHANNEL/nhóm (không phải DOC), When người ngoài mở, Then VẪN chặn "Không có quyền".
- **Edge (🔜):** user chưa-participant cần **thấy** hội thoại DOC trong danh sách trước khi mở → `msConvListHtml` lọc theo `doc_type+doc_no` ở scope DOC (Phase 2). (Severity 3)
- **Edge:** chứng từ có nhiều hội thoại DOC → mở cái nào lazy-join cái đó. (Severity 2)

---

## Epic 5 — Hiển thị info & nhịp tin nhắn ✅

### US-5.1 — DM không hiện danh sách thành viên ✅
- **AC** — ✅ Given hội thoại `canhan` (DM), When mở info panel, Then KHÔNG có mục "Thành viên"; nhóm/channel/chứng từ vẫn có.
- **Edge:** channel vẫn hiện "Nhóm quyền được xem". (Severity 1)

### US-5.2 — Nhịp khoảng cách tin nhắn hợp lý ✅
- **AC1** — ✅ Given các tin liên tiếp cùng người trong <10 phút, When render, Then sát nhau (grouped, 1px).
- **AC2** — ✅ Given tin đầu cụm (có avatar+tên), When render, Then tách cụm trên bằng `margin-top:10px`, không hở lớn.
- **AC3** — ✅ Given tin ngay sau dải ngày/`unread-divider`, Then không bị đẩy xa thêm.
- **Edge:** ngưỡng gom nhóm hiện 10 phút — giữ nguyên trừ khi user yêu cầu nâng. (Severity 1)

---

## Ma trận kiểm thử nhanh (regression)

| # | Kịch bản | Kỳ vọng | Trạng thái |
|---|---|---|---|
| T1 | Menu compose | có "Channel mới" | ✅ |
| T2 | Tạo channel trống quyền | toàn công ty thấy | 🧪 |
| T3 | Tạo channel có quyền | chỉ role được chọn thấy | 🧪 |
| T4 | User ngoài mở "Trao đổi" chứng từ | đọc & gửi được, tự join | ✅ logic / 🧪 APEX |
| T5 | User ngoài mở DM người khác | "Không có quyền" | ✅ |
| T6 | Info panel DM | không có "Thành viên" | ✅ |
| T7 | Info panel nhóm/channel/chứng từ | giữ "Thành viên"/"Nhóm quyền" | ✅ |
| T8 | Thread 3 tin cùng người | co sát, nhịp đều | ✅ (kiểm thử thị giác) |
| T9 | Mở từ chứng từ | scope DOC + segmented | 🔜 Phase 2 |
| T10 | Tin ở hội thoại khác khi scope DOC | banner + badge | 🔜 Phase 2 |
</content>
