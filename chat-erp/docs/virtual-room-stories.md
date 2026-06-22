# chat-erp — User Stories: Hội thoại ảo (Virtual Room)

> Kiểm thử cho mô hình "hội thoại ảo": hội thoại chỉ ghi DB khi gửi tin đầu tiên. Áp dụng cho DOC / DM / Nhóm / Channel.
> Severity (research-1.0.0): 1=Cosmetic · 2=Minor · 3=Major · 4=Catastrophic. AC dạng Given-When-Then.
> Trạng thái: ✅ code xong · 🧪 cần test trên APEX.

## Nguyên tắc chung
- Giữ bước nhập metadata (tên + thành viên/quyền) ở compose; chỉ **hoãn INSERT** tới khi gửi tin đầu.
- Bỏ phòng ảo (chọn hội thoại khác / đóng modal) mà chưa gửi tin → **không ghi gì** vào DB.
- Materialize qua: DM→`msCreateDM` (dedup), DOC→`msEnsureDocConv` (find-or-create + unique index), Nhóm→`msCreateGroup`, Channel→`msCreateChannel`; rồi `msSendMsg` gửi tin đầu + broadcast.

---

## Epic 1 — Phòng ảo DM

### US-1.1 Picker kiểu Messenger: load cũ hoặc tạo ảo
> Là nhân viên, tôi muốn gõ tên ở ô "Tới", chọn người: nếu đã từng chat thì thấy ngay lịch sử, chưa có thì vào phòng trống để gõ.
- **AC1** ✅ Given chọn 1 người **đã có DM**, When bấm "Nhắn tin", Then **load hội thoại cũ** (hiện lịch sử) — không mở phòng ảo. Dựa `data-conv` do `msContactsHtml` trả về.
- **AC2** ✅ Given chọn 1 người **chưa có DM**, When bấm "Nhắn tin", Then mở phòng ảo (header = tên người, nhãn "Mới", composer bật), KHÔNG có row DB.
- **AC3** ✅ Given phòng ảo DM, When gửi tin đầu, Then `msCreateDM` (dedup) tạo DM + gửi tin + hiện ở sidebar.
- **AC4** ✅ Given phòng ảo DM, When chọn hội thoại khác, Then `draftConv` bị hủy, không có row. (Severity 3)
- **AC5** ✅ Global search (⌘K) chọn người: cùng logic — `gsPickPerson` load DM cũ nếu có (`dm_conv`), chưa có thì phòng ảo.
- **Edge:** giữa lúc đang ở phòng ảo có người khác tạo DM với mình rồi mình gửi → `msCreateDM` dedup vẫn về đúng 1 DM. (Severity 3)

---

## Epic 2 — Phòng ảo DOC (chứng từ)

### US-2.1 Mở "Trao đổi" chứng từ chưa có phòng
> Là người liên quan chứng từ, tôi muốn mở "Trao đổi" là gõ được ngay, chỉ tạo phòng khi tôi thực sự nhắn.
- **AC1** ✅ Given vào từ chứng từ (scope='doc') và chưa có phòng chung, When modal load xong, Then tự mở phòng ảo DOC (tên = mã chứng từ).
- **AC2** ✅ Given phòng ảo DOC, When gửi tin đầu, Then `msEnsureDocConv` tạo phòng chung + lazy-join + gửi tin.
- **AC3** ✅ Given đã có phòng chung của chứng từ, When mở "Trao đổi", Then mở thẳng phòng THẬT (không tạo ảo).
- **Edge (Severity 4):** 2 người mở cùng chứng từ rồi cùng gửi tin đầu → chỉ 1 phòng chung (UNIQUE INDEX `uq_doc_main` + bắt `DUP_VAL_ON_INDEX` → dùng phòng có sẵn).
- **Edge:** ai vào được chứng từ đều tạo/tham gia được (không kiểm tra quyền tạo). (Severity 2)

---

## Epic 3 — Phòng ảo Nhóm

### US-3.1 Tạo nhóm hoãn ghi DB
> Là người tạo nhóm, tôi muốn nhập tên + thành viên rồi vào phòng, nhưng nhóm chỉ tồn tại khi tôi gửi tin đầu.
- **AC1** ✅ Given nhập tên + ≥1 thành viên, When bấm "Tạo nhóm", Then mở phòng ảo (header = tên nhóm), KHÔNG có row.
- **AC2** ✅ Given phòng ảo nhóm, When gửi tin đầu, Then `msCreateGroup` tạo conversation + participants (gồm người được chọn) + gửi tin.
- **AC3** ✅ Given phòng ảo nhóm, When rời đi không gửi, Then không tạo nhóm/participant nào. (Severity 3)
- **Edge:** tên trống / chưa chọn ai → vẫn chặn ở bước nhập (không vào phòng ảo). (Severity 2)
- **Edge:** gắn chứng từ (attachedDoc) được giữ và truyền vào lúc materialize. (Severity 2)

---

## Epic 4 — Phòng ảo Channel

### US-4.1 Tạo channel hoãn ghi DB
> Là trưởng nhóm, tôi muốn nhập tên + nhóm quyền rồi vào phòng, channel chỉ tạo khi tôi gửi tin đầu.
- **AC1** ✅ Given nhập tên (+ tùy chọn nhóm quyền), When bấm "Tạo kênh", Then mở phòng ảo (header = `#slug`), KHÔNG có row.
- **AC2** ✅ Given phòng ảo channel, When gửi tin đầu, Then `msCreateChannel` tạo channel + roles + gửi tin.
- **AC3** ✅ Given để trống nhóm quyền, When tạo, Then channel "Toàn công ty".
- **Edge:** rời đi không gửi → không tạo channel/role. (Severity 3)

---

## Epic 5 — Ràng buộc & regression

### US-5.1 Nhóm con cần phòng cha thật
- **AC** ✅ Given đang ở phòng ảo (chưa gửi tin), When bấm "Tạo nhóm con", Then bị chặn ("Mở 1 hội thoại trước") — nhóm con KHÔNG ảo hóa đợt này, parent phải thật. (Severity 2)

### US-5.2 Regression hội thoại có sẵn
- **AC** ✅ Given hội thoại đã tồn tại, When mở/gửi, Then hoạt động như cũ (không qua draft).

---

## Ma trận kiểm thử nhanh
| # | Kịch bản | Kỳ vọng | Trạng thái |
|---|---|---|---|
| V1 | Mở DM ảo → rời đi | DB không có row | 🧪 |
| V2 | DM ảo → gửi tin | tạo/lấy DM (dedup) + tin | 🧪 |
| V3 | "Trao đổi" chứng từ mới → gõ Enter | tạo phòng chung + tin | 🧪 |
| V4 | 2 user cùng gửi tin đầu 1 chứng từ | chỉ 1 phòng chung | 🧪 (cần DDL uq_doc_main) |
| V5 | Nhóm ảo → rời đi | không tạo nhóm | 🧪 |
| V6 | Nhóm ảo → gửi tin | tạo nhóm + thành viên + tin | 🧪 |
| V7 | Channel ảo → gửi tin | tạo channel + roles + tin | 🧪 |
| V8 | Nhóm con khi ở phòng ảo | bị chặn | 🧪 |
</content>
