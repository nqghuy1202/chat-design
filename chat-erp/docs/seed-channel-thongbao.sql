-- ============================================================
-- Tạo hội thoại Channel mẫu "#thong-bao-chung" — công khai toàn công ty
-- (không insert gì vào CHAT_CHANNEL_ROLES => "Toàn công ty", xem msConvListHtml).
-- Đổi &creator_username thành user_name thật của người tạo (vd 'admin').
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_conv_id NUMBER;
BEGIN
  SELECT aus_id INTO l_aus_id
  FROM APP_USERS
  WHERE LOWER(user_name) = LOWER('&creator_username');

  l_conv_id := CONV_SEQ.NEXTVAL;

  INSERT INTO CHAT_CONVERSATIONS (conv_id, conv_type, name, description, aus_id, is_public)
  VALUES (l_conv_id, 'CHANNEL', 'thong-bao-chung', 'Kênh thông báo chung toàn công ty', l_aus_id, 1);

  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin)
  VALUES (l_conv_id, l_aus_id, 1);

  -- KHÔNG insert CHAT_CHANNEL_ROLES => không gán nhóm quyền => "Toàn công ty"
  -- (mọi user đều thấy channel này trong msConvListHtml)

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Đã tạo channel #thong-bao-chung, conv_id = '||l_conv_id);
EXCEPTION WHEN NO_DATA_FOUND THEN
  DBMS_OUTPUT.PUT_LINE('Không tìm thấy user_name = &creator_username trong APP_USERS');
END;
/
