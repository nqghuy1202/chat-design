-- ============================================================
-- chat-erp (page 10022710202) — bổ sung schema trên CHAT_* dùng chung với messenger/
-- Chạy TOÀN BỘ block này TRƯỚC khi tạo các Ajax Callback trong callbacks.sql.
-- Idempotent: chạy 1 lần. Không xóa/đổi cột nào của messenger/ — chỉ ADD.
-- ============================================================

-- 1) Phân biệt "Channel" (công khai, theo nhóm quyền) vs "Nhóm" (riêng tư, ad-hoc)
--    Cả hai vẫn dùng conv_type='CHANNEL' (tương thích ngược với messenger/).
--    is_public=0/NULL (mặc định) = Nhóm | is_public=1 = Channel
ALTER TABLE CHAT_CONVERSATIONS ADD (
  is_public      NUMBER(1) DEFAULT 0,
  parent_conv_id NUMBER,
  description    VARCHAR2(500)
);
ALTER TABLE CHAT_CONVERSATIONS ADD CONSTRAINT fk_conv_parent
  FOREIGN KEY (parent_conv_id) REFERENCES CHAT_CONVERSATIONS(conv_id);
CREATE INDEX ix_chat_conv_parent ON CHAT_CONVERSATIONS(parent_conv_id);

-- 2) Channel theo nhóm quyền — ai thuộc role thì THẤY channel (không phải participant cố định).
--    Không có dòng nào cho 1 conv_id => "Toàn công ty" (channel công khai cho tất cả).
--    USER_ROLES(aus_id, gus_id) và GROUP_USERS(gus_id, name) đã có sẵn trong hệ thống.
CREATE TABLE CHAT_CHANNEL_ROLES (
  conv_id NUMBER NOT NULL,
  gus_id  NUMBER NOT NULL,
  CONSTRAINT pk_chat_channel_roles PRIMARY KEY (conv_id, gus_id),
  CONSTRAINT fk_ccr_conv FOREIGN KEY (conv_id) REFERENCES CHAT_CONVERSATIONS(conv_id),
  CONSTRAINT fk_ccr_gus  FOREIGN KEY (gus_id)  REFERENCES GROUP_USERS(gus_id)
);

-- 3) Reactions + pinned messages — GIỐNG HỆT messenger/ (nếu DB đã chạy DDL của messenger/
--    thì BỎ QUA 2 block này, không tạo trùng bảng).
-- CREATE TABLE CHAT_REACTIONS (
--   msg_id      NUMBER          NOT NULL,
--   aus_id      NUMBER          NOT NULL,
--   emoji       VARCHAR2(16)    NOT NULL,
--   create_date TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
--   CONSTRAINT pk_chat_reactions PRIMARY KEY (msg_id, aus_id, emoji)
-- );
-- CREATE INDEX ix_chat_reactions_msg ON CHAT_REACTIONS(msg_id);
--
-- CREATE TABLE CHAT_PINNED_MSGS (
--   conv_id  NUMBER NOT NULL,
--   msg_id   NUMBER NOT NULL,
--   aus_id   NUMBER NOT NULL,
--   pin_date TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
--   CONSTRAINT pk_chat_pinned PRIMARY KEY (conv_id, msg_id)
-- );

-- 4) Sidebar pin riêng cho chat-erp (khác is_pinned per-user của messenger/ ở chỗ đây
--    là mục "Đã ghim" hiển thị xuyên suốt 4 nhóm) -- tái dùng CHAT_PARTICIPANTS.is_pinned
--    sẵn có, KHÔNG cần cột mới. Nếu DB chưa có cột này (chưa deploy messenger/) thì:
-- ALTER TABLE CHAT_PARTICIPANTS ADD (is_pinned NUMBER(1) DEFAULT 0, is_hidden NUMBER(1) DEFAULT 0);

-- 5) Gửi file thật (msUploadFile, callback #16 trong callbacks.sql) — GIỐNG HỆT
--    messenger/. Nếu DB đã chạy DDL này cho messenger/ rồi thì BỎ QUA, không tạo trùng cột.
-- ALTER TABLE CHAT_MESSENGERS ADD fil_id NUMBER;
-- ALTER TABLE CHAT_MESSENGERS ADD CONSTRAINT fk_chat_msg_fil FOREIGN KEY (fil_id) REFERENCES FILES(fil_id);

COMMIT;
