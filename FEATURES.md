# Danh sách chức năng - Nexus Chat

## 1. Danh sách hội thoại (Left Panel)

### Hội thoại
- Hiển thị danh sách hội thoại chia theo nhóm: Ghim / Tin nhắn trực tiếp / Nhóm / Chứng từ ERP / Thông báo & Bot
- Avatar hình tròn cho DM, hình vuông bo tròn cho nhóm/chứng từ/bot
- Hiển thị tên, tin nhắn cuối, thời gian, số tin chưa đọc
- Click để mở hội thoại
- Menu 3 chấm trên mỗi hội thoại (chuột qua để hiện): Xem thông tin, Ghim, Tắt thông báo, Xóa

### Tìm kiếm hội thoại
- Ô tìm kiếm tại header left panel
- Mở Global Search (`Ctrl+K`) khi click

### Tạo hội thoại mới
- Nút "+" tại header left panel
- Luồng 4 màn hình (slider S1 → S2 → S3 → S4):
  - S1: Danh sách hội thoại
  - S2: Chọn liên hệ để nhắn tin trực tiếp (DM)
  - S3: Chọn nhiều thành viên để tạo nhóm (có tìm kiếm)
  - S4: Đặt tên nhóm, chọn avatar, thêm mô tả

### Trạng thái người dùng
- Chấm trạng thái màu sắc tại avatar người dùng (footer left panel)
- Click để chọn trạng thái: Đang hoạt động / Đang bận / Đang họp / Nghỉ phép / Offline

---

## 2. Khung chat (Center Panel)

### Hiển thị tin nhắn
- Hiển thị lịch sử tin nhắn
- Nhóm tin nhắn từ cùng người gửi (không lặp lại avatar)
- Đường kẻ "Tin nhắn chưa đọc" phân chia tin mới
- Timestamp theo nhóm ngày

### Gửi tin nhắn
- Ô nhập liệu có định dạng (contenteditable)
- Gửi bằng phím `Enter`, xuống dòng bằng `Shift+Enter`
- Nút gửi

### Thanh công cụ định dạng (Formatting toolbar)
- In đậm (Bold)
- In nghiêng (Italic)
- Gạch chân (Underline)
- Gạch xuyên (Strikethrough)
- Code inline
- Khối code (Code block, có nút copy)
- Danh sách dấu chấm
- Danh sách có đánh số

### Đính kèm file / ảnh
- Nút đính kèm file (mở file picker)
- Nút chọn ảnh (mở image picker)
- Kéo-thả file vào khung chat (drag & drop, hiện overlay)
- Thanh xem trước file (file-preview-bar) hiện khi có file đang chờ gửi, có thể xóa từng file

### Emoji picker
- Nút emoji mở picker
- Tìm kiếm emoji
- Chọn emoji chèn vào ô nhập

### Mention
- Nút "@" để tag thành viên

### Trả lời trích dẫn (Reply)
- Hover vào tin nhắn → nút "Reply"
- Hiện banner trích dẫn tin nhắn gốc trong ô nhập
- Nút hủy reply
- Tin gửi đi hiện block trích dẫn phía trên

### Chuyển tiếp tin nhắn (Forward)
- Hover vào tin nhắn → nút "Forward"
- Modal chọn hội thoại để chuyển tiếp
- Tìm kiếm hội thoại trong modal forward
- Hiện toast xác nhận sau khi chuyển tiếp

### Reaction emoji
- Hover vào tin nhắn → nút React
- Chọn emoji reaction, hiện số lượng

### Ghim tin nhắn (Pin)
- Banner ghim hiện ở đầu khung chat nếu có tin được ghim
- Nút đóng banner ghim

### Nhảy xuống tin mới nhất
- Nút "Jump to latest" hiện khi cuộn lên cách đáy 180px+
- Click để cuộn về cuối

### Ảnh trong tin nhắn
- Hiển thị ảnh thumbnail trong chat
- Click để xem ảnh phóng to (Lightbox)
- Đóng lightbox bằng Esc hoặc click ra ngoài

### Code block
- Hiển thị đoạn code có định dạng
- Nút "Copy" sao chép code

### ERP Context Card
- Thẻ inline hiển thị thông tin chứng từ ERP (hóa đơn, phiếu chi...)
- Có badge module, trạng thái, meta, nút hành động

### Tạo task từ tin nhắn
- Menu hover tin nhắn → "Tạo task"
- Toast thông báo tạo task thành công

### Typing indicator
- Hiển thị "... đang gõ" với animation 3 chấm nhảy

---

## 3. Panel thông tin (Right Panel)

- Mở/đóng bằng nút icon ở header trung tâm
- Có thể thu gọn từng section bằng click

### DM (Tin nhắn trực tiếp)
- Avatar, tên, trạng thái online
- Số điện thoại, email
- Các nút: Xem trang cá nhân, Tìm kiếm, Tắt thông báo, Hơn nữa
- Section "File đã chia sẻ"
- Toggle Tắt thông báo, Ghim, Chặn

### Nhóm
- Ảnh nhóm, tên nhóm, số thành viên
- Các nút: Thêm thành viên, Tìm kiếm, Tắt thông báo, Hơn nữa
- Danh sách thành viên (5 người, nút "Xem thêm")
- Toggle Tắt thông báo, Ghim
- Section "File đã chia sẻ"

### Chứng từ ERP (Voucher)
- Mã chứng từ, loại, trạng thái
- Các nút: Xem chứng từ, Tìm kiếm, Ghim, Hơn nữa
- Thông tin chứng từ: người tạo, ngày, giá trị, trạng thái duyệt
- Danh sách người liên quan
- Lịch sử thay đổi

### ERP Bot
- Logo bot, tên kênh, mô tả
- Các nút: Cài đặt, Tìm kiếm, Ghim
- Thông tin kênh: loại sự kiện, module ERP
- Toggle thông báo theo module

---

## 4. Overlays & Modal

### Global Search (`Ctrl+K`)
- Tìm kiếm toàn cục: người, nhóm, tin nhắn, file, chứng từ
- Kết quả chia nhóm (Mọi người / Nhóm / Tin nhắn / File / Chứng từ)
- Click kết quả để mở hội thoại tương ứng
- Đóng bằng Esc hoặc click ra ngoài

### Forward Modal
- Danh sách hội thoại để chuyển tiếp
- Tìm kiếm trong modal
- Chọn nhiều người nhận
- Nút Gửi và Hủy

### Shortcuts Modal (`Ctrl+/`)
- Hiển thị bảng phím tắt đầy đủ
- Đóng bằng Esc hoặc click ra ngoài

---

## 5. Phím tắt (Keyboard Shortcuts)

| Phím tắt | Chức năng |
|---|---|
| `Ctrl+K` | Mở Global Search |
| `Ctrl+/` | Mở bảng phím tắt |
| `Alt+Up` | Chuyển hội thoại phía trên |
| `Alt+Down` | Chuyển hội thoại phía dưới |
| `Esc` | Đóng panel/modal đang mở |
| `Enter` | Gửi tin nhắn |
| `Shift+Enter` | Xuống dòng mới |

---

## 6. Giao diện & Ngũ Hành

- 5 theme màu theo Ngũ Hành:
  - Kim (Xanh dương `#2563EB`)
  - Mộc (Xanh lá `#16A34A`)
  - Thủy (Nâu vàng `#B45309`)
  - Hỏa (Đỏ `#DC2626`)
  - Thổ (Nâu đất `#7B4F24`)
- Đổi theme bằng dropdown trong settings (header trung tâm)
- Tất cả màu accent dùng CSS variable, đổi theo theme tức thì

---

## 7. Các loại hội thoại

| Loại | Mô tả |
|---|---|
| DM | Tin nhắn trực tiếp 1-1 |
| Nhóm | Hội thoại nhiều thành viên |
| Chứng từ ERP | Kênh liên kết với hóa đơn / phiếu chi |
| ERP Bot | Kênh thông báo tự động từ hệ thống ERP |
