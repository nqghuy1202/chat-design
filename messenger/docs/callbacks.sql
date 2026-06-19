-- ============================================================
-- MESSENGER FULLSCREEN — APEX Ajax Callbacks
-- Tất cả tạo là PAGE-LEVEL AJAX CALLBACK trên messenger page
-- Page → Processing → Ajax Callback
--
-- Danh sách callbacks:
--   1. msGetCurrentUser   — thông tin user đang login
--   2. msConvListHtml     — danh sách hội thoại (HTML). Hỗ trợ scope theo
--      chứng từ (x03/x04/x05/x06) cho modal hợp nhất — xem chi tiết tại
--      block callback bên dưới. Tổng unread cho badge/segmented đi qua
--      Node.js GET /api/chat/unread-summary/:aus_id (nodeGet trong JS),
--      không qua callback APEX riêng.
--   3. msConvHeaderJson   — header info của conv được chọn (JSON)
--   4. msMsgThreadHtml    — thread tin nhắn (HTML)
--   5. msSendMsg          — gửi tin nhắn → relay Node.js
--   6. msMarkRead         — đánh dấu đã đọc → relay Node.js
--   7. (đã xóa — long-poll thay bằng SSE qua apex:chatEvent)
--   8. msInfoHtml         — right panel: thành viên (HTML)
--   9. msContactsHtml     — danh sách contacts cho compose (HTML)
--  10. msCreateConv       — tạo hội thoại mới
--  11. msGetAvatar        — lấy avatar URL theo aus_id (x01)
-- ============================================================


-- ============================================================
-- 1. msGetCurrentUser
--    Trả JSON thông tin user đang đăng nhập.
--    Không nhận tham số — dùng :APP_USER.
-- ============================================================
DECLARE
  l_aus_id NUMBER;
  l_name   VARCHAR2(200);
  l_img    VARCHAR2(1000);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;

  BEGIN
    SELECT u.aus_id,
           REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]',''),
           vf.v_file_name
    INTO   l_aus_id, l_name, l_img
    FROM   APP_USERS u
    JOIN   EMPLOYEES e ON e.emp_id = u.emp_id
    LEFT JOIN v_employees_v6 vf ON vf.emp_id = u.emp_id
    WHERE  LOWER(u.user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  -- co_id/oun_id/user_name: global APEX cần cho upload file qua Node
  -- (Node gọi pkg_upload_file.UploadFileChat cần 3 tham số này). Client cache
  -- lại lúc init rồi gửi kèm khi POST /api/chat/upload-send.
  HTP.p(JSON_OBJECT(
    'aus_id'    VALUE l_aus_id,
    'username'  VALUE :APP_USER,
    'full_name' VALUE l_name,
    'img'       VALUE l_img,
    'co_id'     VALUE TO_CHAR(:G_CO_ID),
    'oun_id'    VALUE TO_CHAR(:G_OUN_ID_INS),
    'user_name' VALUE :G_USER_NAME
    ABSENT ON NULL
  ));
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 2. msConvListHtml
--    Trả HTML danh sách hội thoại của user.
--    x01=filter loại (ALL/DM/GROUP/DOC) | x02=search text
--    x03=scope (DOC/ALL) | x04=doc_type | x05=doc_no
--      - scope=DOC: CHỈ hiện hội thoại có doc_type=x04 AND doc_no=x05
--        (1 chứng từ có thể có NHIỀU hội thoại — DM lẫn nhóm)
--      - scope=ALL (mặc định): hiện mọi hội thoại như cũ
--    x06='1': khi scope=ALL và có entryDoc (modal mở từ 1 chứng từ) — thêm
--      section "Đang xem" ghim hội thoại của chứng từ đó lên đầu danh sách
--      (dùng x04/x05 làm chứng từ "đang xem"). '0' hoặc trống = bỏ qua.
--    x07='1': toggle "Chưa đọc" — kết hợp AND với x01 (loại), KHÔNG loại trừ
--      nhau (vd loại=GROUP + chưa đọc=1 → nhóm có tin chưa đọc). x01 không
--      còn nhận giá trị UNREAD (2 chip cũ gộp lại độc lập, xem messenger.html
--      filter dropdown + toggle).
-- ============================================================
DECLARE
  l_aus_id        NUMBER;
  l_filter        VARCHAR2(20)  := NVL(UPPER(TRIM(apex_application.g_x01)), 'ALL');
  l_search        VARCHAR2(200) := LOWER(TRIM(apex_application.g_x02));
  l_scope         VARCHAR2(10)  := NVL(UPPER(TRIM(apex_application.g_x03)), 'ALL');
  l_doc_type      VARCHAR2(30)  := NULLIF(TRIM(apex_application.g_x04), '');
  l_doc_no        VARCHAR2(60)  := NULLIF(TRIM(apex_application.g_x05), '');
  l_viewing_flag  VARCHAR2(1)   := NVL(apex_application.g_x06, '0');
  l_unread_only   VARCHAR2(1)   := NVL(apex_application.g_x07, '0');
  l_online_cutoff TIMESTAMP     := SYSTIMESTAMP - INTERVAL '35' SECOND;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('<div style="padding:16px;color:#DC2626">Phiên đăng nhập hết hạn</div>'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE  LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('<div style="padding:16px;color:#DC2626">Không tìm thấy user</div>'); RETURN;
  END;

  FOR conv IN (
    WITH conv_raw AS (
      SELECT /*+ MATERIALIZE */
        c.conv_id,
        c.conv_type,
        c.doc_type,
        c.doc_no,
        c.last_msg_date,
        c.last_msg_preview,
        p.last_read_msg_id,
        CASE WHEN l_viewing_flag = '1' AND c.doc_type = l_doc_type AND c.doc_no = l_doc_no
             THEN 1 ELSE 0 END AS is_viewing,
        -- Số thành viên — dùng để phân biệt DOC 1-1 (như DM) vs DOC nhóm (như CHANNEL)
        (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) AS member_count,
        -- Display name: CHANNEL hoặc DOC nhóm (>2 người) dùng name, còn lại dùng tên người kia
        CASE
          WHEN c.conv_type = 'CHANNEL' THEN NVL(c.name,'(Không tên)')
          WHEN c.conv_type = 'DOC' AND (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) > 2
            THEN NVL(c.name,'(Không tên)')
          ELSE (
            SELECT REGEXP_REPLACE(NVL(e2.full_name,'Unknown'),'[[:cntrl:]]','')
            FROM   CHAT_PARTICIPANTS p2
            JOIN   APP_USERS u2 ON u2.aus_id = p2.aus_id
            JOIN   EMPLOYEES e2 ON e2.emp_id = u2.emp_id
            WHERE  p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
            FETCH FIRST 1 ROW ONLY
          )
        END AS display_name,
        -- Partner aus_id (DM, hoặc DOC 1-1)
        CASE
          WHEN c.conv_type = 'DM' THEN (
            SELECT p2.aus_id FROM CHAT_PARTICIPANTS p2
            WHERE  p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
            FETCH FIRST 1 ROW ONLY
          )
          WHEN c.conv_type = 'DOC' AND (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) <= 2 THEN (
            SELECT p2.aus_id FROM CHAT_PARTICIPANTS p2
            WHERE  p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
            FETCH FIRST 1 ROW ONLY
          )
          ELSE NULL
        END AS partner_aus_id,
        -- Partner avatar image (DM, hoặc DOC 1-1) — scalar subquery tránh ORA-01799
        CASE
          WHEN c.conv_type = 'DM' THEN (
            SELECT vf2.v_file_name
            FROM   CHAT_PARTICIPANTS p2
            JOIN   APP_USERS u2 ON u2.aus_id = p2.aus_id
            JOIN   v_employees_v6 vf2 ON vf2.emp_id = u2.emp_id
            WHERE  p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
            FETCH FIRST 1 ROW ONLY
          )
          WHEN c.conv_type = 'DOC' AND (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) <= 2 THEN (
            SELECT vf2.v_file_name
            FROM   CHAT_PARTICIPANTS p2
            JOIN   APP_USERS u2 ON u2.aus_id = p2.aus_id
            JOIN   v_employees_v6 vf2 ON vf2.emp_id = u2.emp_id
            WHERE  p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
            FETCH FIRST 1 ROW ONLY
          )
          ELSE NULL
        END AS partner_img,
        -- Display time
        CASE
          WHEN c.last_msg_date >= TRUNC(SYSDATE) THEN TO_CHAR(c.last_msg_date,'HH24:MI')
          ELSE TO_CHAR(c.last_msg_date,'DD/MM')
        END AS display_time,
        -- Unread count
        (SELECT COUNT(*) FROM CHAT_MESSENGERS m
         WHERE  m.conv_id = c.conv_id AND m.delete_date IS NULL
           AND  m.msg_id > NVL(p.last_read_msg_id, 0)
        ) AS unread_count,
        NVL(p.is_pinned, 0) AS is_pinned
      FROM CHAT_CONVERSATIONS c
      JOIN CHAT_PARTICIPANTS  p ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
      WHERE NVL(p.is_hidden, 0) = 0
        -- Scope=DOC: chỉ hội thoại của ĐÚNG chứng từ đang xem (1 chứng từ có thể nhiều hội thoại)
        AND (l_scope != 'DOC' OR (c.doc_type = l_doc_type AND c.doc_no = l_doc_no))
        -- Filter theo loại: ALL (tất cả) / DM (cá nhân) / GROUP (nhóm chung=CHANNEL)
        -- / DOC (theo chứng từ)
        AND (l_filter = 'ALL'
             OR (l_filter = 'DM'    AND c.conv_type = 'DM')
             OR (l_filter = 'GROUP' AND c.conv_type = 'CHANNEL')
             OR (l_filter = 'DOC'   AND c.conv_type = 'DOC'))
        -- Toggle "Chưa đọc" — độc lập với filter loại, kết hợp AND
        AND (l_unread_only != '1' OR
             (SELECT COUNT(*) FROM CHAT_MESSENGERS m
              WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
                AND m.msg_id > NVL(p.last_read_msg_id,0)) > 0)
        AND (l_search IS NULL
             OR LOWER(NVL(c.name,''))             LIKE '%'||l_search||'%'
             OR LOWER(NVL(c.last_msg_preview,'')) LIKE '%'||l_search||'%'
             OR EXISTS (
                  SELECT 1 FROM CHAT_PARTICIPANTS ps
                  JOIN   APP_USERS  us ON us.aus_id = ps.aus_id
                  JOIN   EMPLOYEES  es ON es.emp_id = us.emp_id
                  WHERE  ps.conv_id = c.conv_id AND ps.aus_id != l_aus_id
                    AND (LOWER(NVL(es.full_name,'')) LIKE '%'||l_search||'%'
                      OR LOWER(NVL(us.user_name,'')) LIKE '%'||l_search||'%')
             ))
    )
    SELECT r.*,
           CASE WHEN o.last_seen >= l_online_cutoff THEN 'online' ELSE 'offline' END AS presence
    FROM   conv_raw r
    LEFT JOIN CHAT_USER_ONLINE o ON o.aus_id = r.partner_aus_id
    ORDER  BY r.is_viewing DESC, r.is_pinned DESC, r.last_msg_date DESC NULLS LAST
  ) LOOP
    DECLARE
      l_name    VARCHAR2(200) := REGEXP_REPLACE(NVL(conv.display_name,'?'),'[[:cntrl:]]','');
      l_initl   VARCHAR2(4)   := UPPER(SUBSTR(REGEXP_SUBSTR(l_name,'\S+$'),1,1));
      l_hue     VARCHAR2(10)  := TO_CHAR(MOD(NVL(conv.partner_aus_id, conv.conv_id)*47, 360));
      l_unread  BOOLEAN       := conv.unread_count > 0;
      l_is_group BOOLEAN      := conv.conv_type = 'CHANNEL'
                                  OR (conv.conv_type = 'DOC' AND conv.member_count > 2);
      l_cls     VARCHAR2(200);
    BEGIN
      IF NVL(l_initl,'') = '' THEN l_initl := '?'; END IF;

      -- Danh sách phẳng, sắp theo thời gian (ORDER BY ... last_msg_date DESC).
      -- KHÔNG còn chia section: hội thoại "Đang xem" + đã ghim vẫn nổi lên đầu
      -- nhờ is_viewing/is_pinned trong ORDER BY; dấu ghim hiển thị ngay trên item.

      -- Conv item classes
      l_cls := 'ms-conv-item'
             || CASE WHEN l_unread  THEN ' unread' END
             || CASE WHEN l_is_group THEN ' group' END;

      HTP.p('<button type="button" class="' || l_cls || '"'
            || ' data-conv-id="'    || conv.conv_id   || '"'
            || ' data-conv-type="'  || conv.conv_type || '"'
            || ' data-partner-id="' || NVL(TO_CHAR(conv.partner_aus_id),'') || '"'
            || ' onclick="msSelectConv(' || conv.conv_id
            || ',''' || conv.conv_type || ''')">');

      -- Avatar
      HTP.p('  <div class="ms-ci-av' || CASE WHEN l_is_group THEN ' group' END || '"'
            || ' style="background:hsl(' || l_hue || ',55%,52%)">');
      IF l_is_group THEN
        HTP.p('<i class="fa fa-users" style="font-size:16px"></i>');
      ELSE
        IF conv.partner_img IS NOT NULL THEN
          HTP.p('<img src="' || HTF.ESCAPE_SC(conv.partner_img) || '"'
                || ' style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%"'
                || ' onerror="this.remove()">');
        END IF;
        HTP.p(NVL(l_initl,'?'));
        HTP.p('<span class="ms-presence ' || conv.presence || '"></span>');
      END IF;
      HTP.p('  </div>');

      -- Body
      HTP.p('  <div class="ms-ci-body">');
      HTP.p('    <div class="ms-ci-row1">');
      HTP.p('      <span class="ms-ci-name">' || HTF.ESCAPE_SC(l_name) || '</span>');
      IF conv.is_pinned = 1 THEN
        HTP.p('      <i class="fa fa-thumbtack ms-ci-pin" title="Đã ghim"></i>');
      END IF;
      HTP.p('      <span class="ms-ci-time">' || NVL(conv.display_time,'') || '</span>');
      HTP.p('    </div>');
      IF conv.conv_type = 'DOC' THEN
        HTP.p('    <div class="ms-ci-docbadge">' || HTF.ESCAPE_SC(NVL(conv.doc_no,'')) || '</div>');
      END IF;
      HTP.p('    <div class="ms-ci-row2">');
      HTP.p('      <span class="ms-ci-preview">'
            || HTF.ESCAPE_SC(SUBSTR(NVL(conv.last_msg_preview,''),1,55)) || '</span>');
      IF l_unread THEN
        HTP.p('      <span class="ms-ci-badge">'
              || CASE WHEN conv.unread_count > 99 THEN '99+'
                      ELSE TO_CHAR(conv.unread_count) END
              || '</span>');
      END IF;
      HTP.p('    </div>');
      HTP.p('  </div>');

      -- Dot-menu (div role=button — tránh nested button trong .ms-conv-item)
      HTP.p('  <div role="button" tabindex="-1" class="ms-ci-menu-btn"'
            || ' onclick="msOpenConvMenu(' || conv.conv_id
            || ',''' || conv.conv_type || ''',event)" title="Tùy chọn">'
            || '<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">'
            || '<circle cx="12" cy="5" r="2"/><circle cx="12" cy="12" r="2"/>'
            || '<circle cx="12" cy="19" r="2"/></svg></div>');

      HTP.p('</button>');
    END;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="padding:16px;color:#DC2626">Lỗi: ' || HTF.ESCAPE_SC(SQLERRM) || '</div>');
END;


-- ============================================================
-- 3. msConvHeaderJson
--    Trả JSON thông tin header của conv: name, type, online, member_count.
--    x01=conv_id
-- ============================================================
DECLARE
  l_conv_id       NUMBER    := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_aus_id        NUMBER;
  l_online_cutoff TIMESTAMP := SYSTIMESTAMP - INTERVAL '35' SECOND;
  l_name          VARCHAR2(200);
  l_type          VARCHAR2(20);
  l_img           VARCHAR2(1000);
  l_online        NUMBER := 0;
  l_member_count  NUMBER := 0;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF l_conv_id = 0 THEN HTP.p('{"error":"no_conv"}'); RETURN; END IF;

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  SELECT COUNT(*) INTO l_member_count FROM CHAT_PARTICIPANTS WHERE conv_id = l_conv_id;

  SELECT c.conv_type,
         CASE
           WHEN c.conv_type = 'CHANNEL' THEN NVL(c.name,'(Không tên)')
           WHEN c.conv_type = 'DOC' AND l_member_count > 2 THEN NVL(c.name,'(Không tên)')
           ELSE (SELECT REGEXP_REPLACE(NVL(e2.full_name,'Unknown'),'[[:cntrl:]]','')
                 FROM CHAT_PARTICIPANTS p2
                 JOIN APP_USERS u2 ON u2.aus_id = p2.aus_id
                 JOIN EMPLOYEES e2 ON e2.emp_id = u2.emp_id
                 WHERE p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
                 FETCH FIRST 1 ROW ONLY)
         END
  INTO l_type, l_name
  FROM CHAT_CONVERSATIONS c WHERE c.conv_id = l_conv_id;

  IF l_type = 'DM' OR (l_type = 'DOC' AND l_member_count <= 2) THEN
    DECLARE l_partner_id NUMBER; l_partner_emp NUMBER;
    BEGIN
      SELECT p2.aus_id INTO l_partner_id FROM CHAT_PARTICIPANTS p2
      WHERE p2.conv_id = l_conv_id AND p2.aus_id != l_aus_id FETCH FIRST 1 ROW ONLY;

      -- Online: dùng MAX (aggregate) → LUÔN trả 1 dòng, KHÔNG ném NO_DATA_FOUND
      -- khi partner chưa có bản ghi presence (offline). Trước đây lỗi ở đây
      -- nhảy ra EXCEPTION làm câu lấy avatar phía dưới bị bỏ qua → mất ảnh khi offline.
      SELECT NVL(MAX(CASE WHEN last_seen >= l_online_cutoff THEN 1 ELSE 0 END), 0)
      INTO l_online FROM CHAT_USER_ONLINE WHERE aus_id = l_partner_id;

      -- Avatar: cũng dùng MAX để offline vẫn lấy được ảnh (độc lập với presence)
      SELECT MAX(vf.v_file_name) INTO l_img
      FROM APP_USERS u JOIN v_employees_v6 vf ON vf.emp_id = u.emp_id
      WHERE u.aus_id = l_partner_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
  END IF;

  HTP.p(JSON_OBJECT(
    'name'         VALUE REGEXP_REPLACE(NVL(l_name,'?'),'[[:cntrl:]]',''),
    'type'         VALUE l_type,
    'member_count' VALUE l_member_count,
    'online'       VALUE l_online,
    'img'          VALUE l_img
    ABSENT ON NULL
  ));
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 4. msMsgThreadHtml
--    Trả HTML danh sách tin nhắn trong hội thoại.
--    x01=conv_id
--    Dùng MATERIALIZE vì REGEXP_REPLACE trên remote columns.
-- ============================================================
DECLARE
  l_conv_id   NUMBER       := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_aus_id    NUMBER;
  l_last_day  DATE         := NULL;
  -- Gom nhóm kiểu Messenger: chỉ hiện avatar + tên + giờ khi BẮT ĐẦU nhóm mới.
  -- Nhóm mới = đổi người gửi, HOẶC cách tin trước ≥ 10 phút, HOẶC sang ngày mới.
  l_prev_from NUMBER       := NULL;   -- from_aus_id của tin liền trước
  l_prev_dt   DATE         := NULL;   -- thời điểm tin liền trước
  l_new_grp   BOOLEAN;                -- tin hiện tại có bắt đầu nhóm mới không
  -- FILES.file_name LÀ đường dẫn tương đối đầy đủ (vd /i/FILE_UPLOAD/.../383.90681)
  -- → dùng thẳng làm href, KHÔNG ghép tiền tố. Tên + đuôi gốc nằm ở cột FILES.name.
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  IF l_conv_id = 0 THEN
    HTP.p('<div style="text-align:center;color:#94A3B8;margin-top:60px;font-size:13px">Chọn hội thoại để xem tin nhắn</div>');
    RETURN;
  END IF;

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('<div style="padding:16px;color:#DC2626">Phiên đăng nhập hết hạn</div>'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('<div style="padding:16px;color:#DC2626">Không tìm thấy user</div>'); RETURN;
  END;

  FOR msg IN (
    WITH msg_raw AS (
      SELECT /*+ MATERIALIZE */
        m.msg_id,
        m.from_aus_id,
        u.emp_id,
        REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') AS from_name,
        CASE WHEN m.delete_date IS NOT NULL THEN NULL ELSE m.body END AS body,
        m.delete_date,
        m.reply_to_msg_id,
        TRUNC(m.create_date)              AS msg_day,
        CAST(m.create_date AS DATE)       AS msg_dt,
        TO_CHAR(m.create_date,'HH24:MI') AS msg_time,
        CASE WHEN qm.delete_date IS NOT NULL THEN '[Tin nhắn đã bị xóa]' ELSE qm.body END AS reply_body,
        REGEXP_REPLACE(NVL(qe.full_name,''),'[[:cntrl:]]','') AS reply_from_name,
        (SELECT COUNT(*) FROM CHAT_PINNED_MSGS pp
         WHERE pp.conv_id = m.conv_id AND pp.msg_id = m.msg_id) AS is_pinned,
        m.fil_id,
        f.file_name,                       -- đường dẫn tương đối đầy đủ (href)
        f.name        AS file_disp_name,    -- tên gốc còn đuôi (hiển thị + suy đuôi)
        f.file_size,
        LOWER(REGEXP_SUBSTR(f.name, '\.([^.]+)$', 1, 1, NULL, 1)) AS file_ext
      FROM   CHAT_MESSENGERS m
      JOIN   APP_USERS       u  ON u.aus_id  = m.from_aus_id
      JOIN   EMPLOYEES       e  ON e.emp_id  = u.emp_id
      LEFT JOIN CHAT_MESSENGERS qm ON qm.msg_id = m.reply_to_msg_id
      LEFT JOIN APP_USERS    qu  ON qu.aus_id = qm.from_aus_id
      LEFT JOIN EMPLOYEES    qe  ON qe.emp_id = qu.emp_id
      LEFT JOIN FILES        f   ON f.fil_id  = m.fil_id
      WHERE  m.conv_id = l_conv_id
      ORDER  BY m.msg_id ASC
      FETCH FIRST 50 ROWS ONLY
    )
    SELECT mr.*, vf.v_file_name AS sender_img
    FROM   msg_raw mr
    LEFT JOIN v_employees_v6 vf ON vf.emp_id = mr.emp_id
  ) LOOP
    -- Date divider (sang ngày mới luôn mở nhóm mới)
    l_new_grp := FALSE;
    IF l_last_day IS NULL OR msg.msg_day > l_last_day THEN
      l_last_day := msg.msg_day;
      HTP.p('<div class="ms-day-divider"><span>' || TO_CHAR(msg.msg_day,'DD/MM/YYYY') || '</span></div>');
      l_new_grp := TRUE;
    END IF;

    -- Nhóm mới nếu: tin đầu, đổi người gửi, hoặc cách tin trước ≥ 10 phút
    IF l_prev_from IS NULL
       OR msg.from_aus_id <> l_prev_from
       OR (msg.msg_dt - l_prev_dt) * 1440 >= 10 THEN
      l_new_grp := TRUE;
    END IF;

    DECLARE
      l_mine     BOOLEAN      := (msg.from_aus_id = l_aus_id);
      l_cls      VARCHAR2(60) := 'ms-msg-row'
                                 || CASE WHEN l_mine THEN ' mine' END
                                 || CASE WHEN NOT l_new_grp THEN ' cont' END;
      l_av       VARCHAR2(4)  := UPPER(SUBSTR(REGEXP_SUBSTR(msg.from_name,'\S+$'),1,1));
      l_hue      VARCHAR2(10) := TO_CHAR(MOD(msg.from_aus_id * 47, 360));
      l_body_esc VARCHAR2(32767);
    BEGIN
      IF NVL(l_av,'') = '' THEN l_av := '?'; END IF;

      HTP.p('<div class="' || l_cls || '" data-msg-id="' || msg.msg_id || '">');

      -- Avatar: tin của mình luôn ẩn; tin người khác chỉ hiện ở đầu nhóm,
      -- các tin nối tiếp dùng spacer để giữ canh lề.
      IF l_mine THEN
        HTP.p('  <div class="ms-msg-av hidden"></div>');
      ELSIF NOT l_new_grp THEN
        HTP.p('  <div class="ms-msg-av spacer"></div>');
      ELSE
        HTP.p('  <div class="ms-msg-av" style="background:hsl(' || l_hue || ',55%,52%)">');
        IF msg.sender_img IS NOT NULL THEN
          HTP.p('<img src="' || HTF.ESCAPE_SC(msg.sender_img) || '"'
                || ' style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%"'
                || ' onerror="this.remove()">');
        END IF;
        HTP.p(NVL(l_av,'?') || '</div>');
      END IF;

      HTP.p('  <div class="ms-msg-col">');

      -- Dấu ghim
      IF msg.is_pinned > 0 THEN
        HTP.p('    <div class="ms-msg-pinned-mark">'
              || '<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 17v5"/><path d="M5 8.5A5.5 5.5 0 0 1 10.5 3h3A5.5 5.5 0 0 1 19 8.5v.5l1.5 3.5H3.5L5 9z"/></svg>'
              || 'Đã ghim</div>');
      END IF;

      -- Meta (tên người gửi + giờ): chỉ hiện ở đầu nhóm.
      -- Tin nối tiếp (< 10 phút, cùng người) bỏ meta — giống Messenger.
      IF l_new_grp THEN
        HTP.p('    <div class="ms-msg-meta">');
        IF NOT l_mine THEN
          HTP.p('      <span class="ms-msg-meta-name">' || HTF.ESCAPE_SC(msg.from_name) || '</span>');
        END IF;
        HTP.p('      <span>' || msg.msg_time || '</span>');
        HTP.p('    </div>');
      END IF;

      -- Reply context
      IF msg.reply_to_msg_id IS NOT NULL THEN
        HTP.p('    <div class="ms-msg-reply">');
        IF msg.reply_from_name IS NOT NULL THEN
          HTP.p('      <span class="name">' || HTF.ESCAPE_SC(msg.reply_from_name) || '</span>');
        END IF;
        HTP.p(HTF.ESCAPE_SC(SUBSTR(NVL(msg.reply_body,''),1,80)));
        HTP.p('    </div>');
      END IF;

      -- Bubble
      IF msg.delete_date IS NOT NULL THEN
        HTP.p('    <div class="ms-msg-bubble deleted">[Tin nhắn đã bị thu hồi]</div>');
      ELSE
        -- Caption (rỗng nếu tin chỉ có file, không có chữ kèm theo)
        IF msg.body IS NOT NULL THEN
          l_body_esc := REPLACE(REPLACE(
            REPLACE(REPLACE(HTF.ESCAPE_SC(msg.body), '&#38;', '&amp;'),
            '&#60;', '&lt;'), CHR(13), ''), CHR(10), '<br>');
          HTP.p('    <div class="ms-msg-bubble">' || l_body_esc || '</div>');
        END IF;

        -- File/ảnh đính kèm (fil_id NOT NULL): ảnh dùng .img-card, file khác dùng .file-card
        IF msg.fil_id IS NOT NULL THEN
          DECLARE
            l_url        VARCHAR2(500) := msg.file_name;  -- file_name đã là đường dẫn đầy đủ
            l_is_image   BOOLEAN := msg.file_ext IN ('jpg','jpeg','png','gif','webp','bmp','svg');
            l_size_txt   VARCHAR2(30);
            -- Bảng màu/nhãn theo đuôi file — ĐỒNG BỘ với FILE_TYPE_STYLES trong
            -- messenger.fgvd.js (dùng cho preview chip lúc soạn tin). Đổi 1 bên
            -- phải đổi bên kia, không thì icon chip lúc soạn và icon trong tin
            -- nhắn đã gửi sẽ lệch màu nhau.
            l_icon_bg    VARCHAR2(10);
            l_icon_color VARCHAR2(10);
            l_icon_label VARCHAR2(4);
          BEGIN
            IF msg.file_size IS NULL THEN
              l_size_txt := '';
            ELSIF msg.file_size < 1024*1024 THEN
              l_size_txt := ROUND(msg.file_size/1024) || ' KB';
            ELSE
              l_size_txt := ROUND(msg.file_size/1024/1024, 1) || ' MB';
            END IF;

            CASE msg.file_ext
              WHEN 'doc'  THEN l_icon_bg := '#EFF6FF'; l_icon_color := '#2563EB'; l_icon_label := 'DOC';
              WHEN 'docx' THEN l_icon_bg := '#EFF6FF'; l_icon_color := '#2563EB'; l_icon_label := 'DOC';
              WHEN 'xls'  THEN l_icon_bg := '#ECFDF5'; l_icon_color := '#15803D'; l_icon_label := 'XLS';
              WHEN 'xlsx' THEN l_icon_bg := '#ECFDF5'; l_icon_color := '#15803D'; l_icon_label := 'XLS';
              WHEN 'csv'  THEN l_icon_bg := '#ECFDF5'; l_icon_color := '#15803D'; l_icon_label := 'CSV';
              WHEN 'ppt'  THEN l_icon_bg := '#FFF7ED'; l_icon_color := '#C2410C'; l_icon_label := 'PPT';
              WHEN 'pptx' THEN l_icon_bg := '#FFF7ED'; l_icon_color := '#C2410C'; l_icon_label := 'PPT';
              WHEN 'pdf'  THEN l_icon_bg := '#FEF2F2'; l_icon_color := '#DC2626'; l_icon_label := 'PDF';
              WHEN 'zip'  THEN l_icon_bg := '#FFFBEB'; l_icon_color := '#B45309'; l_icon_label := 'ZIP';
              WHEN 'rar'  THEN l_icon_bg := '#FFFBEB'; l_icon_color := '#B45309'; l_icon_label := 'RAR';
              WHEN '7z'   THEN l_icon_bg := '#FFFBEB'; l_icon_color := '#B45309'; l_icon_label := '7Z';
              ELSE                  l_icon_bg := '#F1F5F9'; l_icon_color := '#475569'; l_icon_label := NULL;
            END CASE;

            IF l_is_image THEN
              -- TODO: hiện đang mở ảnh tab mới; nếu muốn lightbox in-app, cần thêm
              -- #ms-lightbox overlay + JS msOpenLightbox() vào messenger.fgvd.js trước
              HTP.p('    <a class="img-card" href="' || HTF.ESCAPE_SC(l_url) || '" target="_blank">');
              HTP.p('      <img src="' || HTF.ESCAPE_SC(l_url) || '" alt="'
                    || HTF.ESCAPE_SC(NVL(msg.file_disp_name,'')) || '" loading="lazy">');
              HTP.p('    </a>');
            ELSE
              HTP.p('    <a class="file-card" href="' || HTF.ESCAPE_SC(l_url)
                    || '" download="' || HTF.ESCAPE_SC(NVL(msg.file_disp_name,''))
                    || '" target="_blank" style="text-decoration:none">');
              IF l_icon_label IS NOT NULL THEN
                -- Có nhãn đuôi rút gọn (DOC/XLS/PDF...) → hiện badge chữ, không cần SVG
                HTP.p('      <div class="file-icon file-icon--label" style="background:'
                      || l_icon_bg || ';color:' || l_icon_color || '">' || l_icon_label || '</div>');
              ELSE
                -- Đuôi lạ / không xác định → icon trang giấy chung, màu xám trung tính
                HTP.p('      <div class="file-icon" style="background:' || l_icon_bg || '">'
                      || '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="' || l_icon_color
                      || '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'
                      || '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg></div>');
              END IF;
              HTP.p('      <div style="flex:1;min-width:0">');
              HTP.p('        <div style="color:#1E293B;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px">'
                    || HTF.ESCAPE_SC(NVL(msg.file_disp_name,'Tệp đính kèm')) || '</div>');
              HTP.p('        <div style="color:#94A3B8;font-size:11px">' || l_size_txt || '</div>');
              HTP.p('      </div>');
              HTP.p('    </a>');
            END IF;
          END;
        END IF;
      END IF;

      -- Reactions (chip tổng hợp theo emoji)
      DECLARE
        l_has_rx NUMBER := 0;
      BEGIN
        FOR rx IN (
          SELECT emoji, COUNT(*) AS cnt,
                 MAX(CASE WHEN aus_id = l_aus_id THEN 1 ELSE 0 END) AS mine
          FROM   CHAT_REACTIONS
          WHERE  msg_id = msg.msg_id
          GROUP  BY emoji
          ORDER  BY MIN(create_date)
        ) LOOP
          IF l_has_rx = 0 THEN
            HTP.p('    <div class="ms-msg-reactions" data-msg-id="' || msg.msg_id || '">');
            l_has_rx := 1;
          END IF;
          HTP.p('      <button type="button" class="ms-reaction-chip'
                || CASE WHEN rx.mine = 1 THEN ' mine' END || '"'
                || ' data-emoji="' || rx.emoji || '"'
                || ' onclick="msToggleReaction(' || msg.msg_id || ',this.dataset.emoji)">'
                || '<span>' || rx.emoji || '</span>'
                || '<span class="ms-reaction-count">' || rx.cnt || '</span></button>');
        END LOOP;
        IF l_has_rx = 1 THEN HTP.p('    </div>'); END IF;
      END;

      -- Hover actions: react / reply / forward / pin
      IF msg.delete_date IS NULL THEN
        HTP.p('    <div class="ms-msg-hover-actions">');
        -- React (mở thanh 6 emoji)
        HTP.p('      <button type="button" class="ms-msg-hover-btn" title="Bày tỏ cảm xúc"'
              || ' onclick="msOpenReactBar(' || msg.msg_id || ',event)">'
              || '<i class="fa fa-smile-o"></i></button>');
        -- Reply
        HTP.p('      <button type="button" class="ms-msg-hover-btn" title="Trả lời"'
              || ' data-reply-id="'   || msg.msg_id || '"'
              || ' data-reply-name="' || HTF.ESCAPE_SC(msg.from_name) || '"'
              || ' data-reply-body="' || REPLACE(SUBSTR(NVL(msg.body,''),1,100),'"','&quot;') || '">'
              || '<i class="fa fa-reply"></i></button>');
        -- Forward
        HTP.p('      <button type="button" class="ms-msg-hover-btn" title="Chuyển tiếp"'
              || ' onclick="msOpenForward(' || msg.msg_id || ',this)"'
              || ' data-fwd-body="' || REPLACE(SUBSTR(NVL(msg.body,''),1,400),'"','&quot;') || '">'
              || '<i class="fa fa-share"></i></button>');
        -- Pin / unpin
        HTP.p('      <button type="button" class="ms-msg-hover-btn"'
              || ' title="' || CASE WHEN msg.is_pinned > 0 THEN 'Bỏ ghim' ELSE 'Ghim' END || '"'
              || ' onclick="msTogglePinMsg(' || msg.msg_id || ')">'
              || '<i class="fa fa-thumb-tack"></i></button>');
        HTP.p('    </div>');
      END IF;

      HTP.p('  </div>');
      HTP.p('</div>');
    END;

    -- Ghi nhớ tin vừa render để tính nhóm cho tin kế tiếp
    l_prev_from := msg.from_aus_id;
    l_prev_dt   := msg.msg_dt;
  END LOOP;

  IF l_last_day IS NULL THEN
    HTP.p('<div style="text-align:center;color:#94A3B8;margin-top:60px;font-size:13px">Chưa có tin nhắn nào. Hãy bắt đầu!</div>');
  END IF;
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="padding:16px;color:#DC2626">Lỗi: ' || HTF.ESCAPE_SC(SQLERRM) || '</div>');
END;


-- ============================================================
-- 5. msSendMsg
--    Gửi tin nhắn → relay sang Node.js POST /api/chat/send
--    x01=conv_id | x02=body | x03=reply_to_msg_id
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_url     VARCHAR2(500) := 'http://172.25.10.38:3410/api/chat/send';
  l_req     UTL_HTTP.REQ;
  l_resp    UTL_HTTP.RESP;
  l_body    VARCHAR2(32767) := '';
  l_buffer  VARCHAR2(32767);
  l_payload VARCHAR2(4000);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  IF TRIM(apex_application.g_x01) IS NULL THEN
    HTP.p('{"error":"conv_id required"}'); RETURN;
  END IF;
  IF TRIM(apex_application.g_x02) IS NULL THEN
    HTP.p('{"error":"body required"}'); RETURN;
  END IF;

  l_payload := JSON_OBJECT(
    'conv_id'         VALUE TO_NUMBER(TRIM(apex_application.g_x01)),
    'aus_id'          VALUE l_aus_id,
    'username'        VALUE :APP_USER,
    'body'            VALUE TRIM(apex_application.g_x02),
    'reply_to_msg_id' VALUE NULLIF(TRIM(apex_application.g_x03),'')
    ABSENT ON NULL
  );

  UTL_HTTP.SET_TRANSFER_TIMEOUT(10);
  l_req := UTL_HTTP.BEGIN_REQUEST(l_url, 'POST', 'HTTP/1.1');
  UTL_HTTP.SET_HEADER(l_req, 'Content-Type',   'application/json; charset=utf-8');
  UTL_HTTP.SET_HEADER(l_req, 'Connection',      'close');
  UTL_HTTP.SET_HEADER(l_req, 'Content-Length',  TO_CHAR(UTL_RAW.LENGTH(UTL_RAW.CAST_TO_RAW(l_payload))));
  UTL_HTTP.WRITE_RAW(l_req, UTL_RAW.CAST_TO_RAW(l_payload));
  l_resp := UTL_HTTP.GET_RESPONSE(l_req);
  BEGIN
    LOOP UTL_HTTP.READ_TEXT(l_resp, l_buffer, 32767); l_body := l_body || l_buffer; END LOOP;
  EXCEPTION WHEN UTL_HTTP.END_OF_BODY THEN NULL;
  END;
  UTL_HTTP.END_RESPONSE(l_resp);

  IF l_resp.status_code BETWEEN 200 AND 299 THEN
    HTP.p(l_body);
  ELSE
    HTP.p('{"error":"Node ' || l_resp.status_code || ': ' || REPLACE(l_body,'"','''') || '"}');
  END IF;
EXCEPTION WHEN OTHERS THEN
  BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
  HTP.p('{"error":"UTL_HTTP: ' || REPLACE(SQLERRM,'"','''') || '"}');
END;


-- ============================================================
-- 6. msMarkRead
--    Đánh dấu đã đọc → relay Node.js POST /api/chat/read/:conv_id/:aus_id
--    x01=conv_id
-- ============================================================
DECLARE
  l_aus_id NUMBER;
  l_url    VARCHAR2(500);
  l_req    UTL_HTTP.REQ;
  l_resp   UTL_HTTP.RESP;
  l_buf    VARCHAR2(4000) := '';
  l_tmp    VARCHAR2(4000);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"status":"skip"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"status":"skip"}'); RETURN;
  END;

  IF TRIM(apex_application.g_x01) IS NULL THEN
    HTP.p('{"error":"conv_id required"}'); RETURN;
  END IF;

  l_url := 'http://172.25.10.38:3410/api/chat/read/'
           || TRIM(apex_application.g_x01) || '/' || TO_CHAR(l_aus_id);
  UTL_HTTP.SET_TRANSFER_TIMEOUT(5);
  l_req := UTL_HTTP.BEGIN_REQUEST(l_url, 'POST', 'HTTP/1.1');
  UTL_HTTP.SET_HEADER(l_req, 'Content-Length', '0');
  UTL_HTTP.SET_HEADER(l_req, 'Connection',     'close');
  l_resp := UTL_HTTP.GET_RESPONSE(l_req);
  BEGIN
    LOOP UTL_HTTP.READ_TEXT(l_resp, l_tmp, 4000); l_buf := l_buf || l_tmp; END LOOP;
  EXCEPTION WHEN UTL_HTTP.END_OF_BODY THEN NULL;
  END;
  UTL_HTTP.END_RESPONSE(l_resp);
  HTP.p(NVL(NULLIF(l_buf,''), '{"status":"ok"}'));
EXCEPTION WHEN OTHERS THEN
  BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
  HTP.p('{"status":"skip"}');
END;


-- ============================================================
-- 7. (Đã xóa) msChatEvents — Long-poll cũ
--    Real-time giờ nhận qua SSE: global.js → apex:chatEvent → onChatEvent()
--    Xóa callback này khỏi APEX page nếu còn tồn tại.
-- ============================================================


-- ============================================================
-- 8. msInfoHtml
--    Trả HTML right panel theo loại conv:
--    - DM      → profile card (avatar lớn + tên + phòng ban + trạng thái)
--    - CHANNEL → group header (avatar nhóm + tên + member count) + member list
--    x01=conv_id
--    Dùng MATERIALIZE + l_online_cutoff.
-- ============================================================
DECLARE
  l_conv_id       NUMBER    := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_online_cutoff TIMESTAMP := SYSTIMESTAMP - INTERVAL '35' SECOND;
  l_aus_id        NUMBER;
  l_conv_name     VARCHAR2(200);
  l_conv_type     VARCHAR2(20);
  l_member_count  NUMBER := 0;

  -- DM partner info
  l_partner_id    NUMBER;
  l_partner_name  VARCHAR2(200);
  l_partner_dept  VARCHAR2(200);
  l_partner_pos   VARCHAR2(200);
  l_partner_email VARCHAR2(200);
  l_partner_phone VARCHAR2(50);
  l_partner_img   VARCHAR2(1000);
  l_partner_hue   VARCHAR2(10);
  l_partner_av    VARCHAR2(4);
  l_partner_pres  VARCHAR2(10);

  -- ── Ảnh & Video + File đính kèm chia sẻ trong hội thoại (dùng chung DM/CHANNEL) ──
  -- Bảng màu icon theo đuôi file: ĐỒNG BỘ với FILE_TYPE_STYLES (messenger.fgvd.js,
  -- preview chip lúc soạn tin) và CASE trong msMsgThreadHtml (mục 4, icon file-card
  -- trong tin nhắn). Đổi 1 nơi phải đổi cả 3, không thì icon lệch màu giữa 3 chỗ.
  PROCEDURE render_shared_media(p_conv_id NUMBER) IS
    l_img_total  NUMBER := 0;
    l_file_total NUMBER := 0;
    l_i          NUMBER := 0;
    l_bg         VARCHAR2(10);
    l_color      VARCHAR2(10);
    l_label      VARCHAR2(4);
    l_size_txt   VARCHAR2(30);
  BEGIN
    SELECT COUNT(*) INTO l_img_total
    FROM CHAT_MESSENGERS m JOIN FILES f ON f.fil_id = m.fil_id
    WHERE m.conv_id = p_conv_id AND m.delete_date IS NULL
      AND LOWER(REGEXP_SUBSTR(f.name,'\.([^.]+)$',1,1,NULL,1)) IN ('jpg','jpeg','png','gif','webp','bmp','svg');

    SELECT COUNT(*) INTO l_file_total
    FROM CHAT_MESSENGERS m JOIN FILES f ON f.fil_id = m.fil_id
    WHERE m.conv_id = p_conv_id AND m.delete_date IS NULL
      AND LOWER(REGEXP_SUBSTR(f.name,'\.([^.]+)$',1,1,NULL,1)) NOT IN ('jpg','jpeg','png','gif','webp','bmp','svg');

    -- ── Ảnh & Video: lưới 3 cột, tối đa 6 ô, ô thứ 6 phủ "+N còn lại" ──
    IF l_img_total > 0 THEN
      HTP.p('<div class="ms-info-section">');
      HTP.p('  <div class="ms-info-section-title"><span>Ảnh &amp; Video (' || l_img_total || ')</span></div>');
      HTP.p('  <div class="ms-media-grid">');
      l_i := 0;
      FOR im IN (
        SELECT file_name FROM (
          SELECT f.file_name
          FROM CHAT_MESSENGERS m JOIN FILES f ON f.fil_id = m.fil_id
          WHERE m.conv_id = p_conv_id AND m.delete_date IS NULL
            AND LOWER(REGEXP_SUBSTR(f.name,'\.([^.]+)$',1,1,NULL,1)) IN ('jpg','jpeg','png','gif','webp','bmp','svg')
          ORDER BY m.create_date DESC
        ) WHERE ROWNUM <= 6
      ) LOOP
        l_i := l_i + 1;
        HTP.p('    <a class="ms-media-thumb" href="' || HTF.ESCAPE_SC(im.file_name) || '" target="_blank">');
        HTP.p('      <img src="' || HTF.ESCAPE_SC(im.file_name) || '" alt="" loading="lazy">');
        IF l_i = 6 AND l_img_total > 6 THEN
          HTP.p('      <div class="ms-media-more">+' || (l_img_total - 5) || '</div>');
        END IF;
        HTP.p('    </a>');
      END LOOP;
      HTP.p('  </div>');
      HTP.p('</div>');
    END IF;

    -- ── File đính kèm: icon màu theo đuôi, tên + dung lượng + nút tải ──
    IF l_file_total > 0 THEN
      HTP.p('<div class="ms-info-section">');
      HTP.p('  <div class="ms-info-section-title"><span>File đính kèm (' || l_file_total || ')</span></div>');
      FOR fl IN (
        SELECT * FROM (
          SELECT f.file_name, f.name AS disp_name, f.file_size,
                 LOWER(REGEXP_SUBSTR(f.name,'\.([^.]+)$',1,1,NULL,1)) AS ext
          FROM CHAT_MESSENGERS m JOIN FILES f ON f.fil_id = m.fil_id
          WHERE m.conv_id = p_conv_id AND m.delete_date IS NULL
            AND LOWER(REGEXP_SUBSTR(f.name,'\.([^.]+)$',1,1,NULL,1)) NOT IN ('jpg','jpeg','png','gif','webp','bmp','svg')
          ORDER BY m.create_date DESC
        ) WHERE ROWNUM <= 10
      ) LOOP
        CASE fl.ext
          WHEN 'doc'  THEN l_bg := '#EFF6FF'; l_color := '#2563EB'; l_label := 'DOC';
          WHEN 'docx' THEN l_bg := '#EFF6FF'; l_color := '#2563EB'; l_label := 'DOC';
          WHEN 'xls'  THEN l_bg := '#ECFDF5'; l_color := '#15803D'; l_label := 'XLS';
          WHEN 'xlsx' THEN l_bg := '#ECFDF5'; l_color := '#15803D'; l_label := 'XLS';
          WHEN 'csv'  THEN l_bg := '#ECFDF5'; l_color := '#15803D'; l_label := 'CSV';
          WHEN 'ppt'  THEN l_bg := '#FFF7ED'; l_color := '#C2410C'; l_label := 'PPT';
          WHEN 'pptx' THEN l_bg := '#FFF7ED'; l_color := '#C2410C'; l_label := 'PPT';
          WHEN 'pdf'  THEN l_bg := '#FEF2F2'; l_color := '#DC2626'; l_label := 'PDF';
          WHEN 'zip'  THEN l_bg := '#FFFBEB'; l_color := '#B45309'; l_label := 'ZIP';
          WHEN 'rar'  THEN l_bg := '#FFFBEB'; l_color := '#B45309'; l_label := 'RAR';
          WHEN '7z'   THEN l_bg := '#FFFBEB'; l_color := '#B45309'; l_label := '7Z';
          ELSE                  l_bg := '#F1F5F9'; l_color := '#475569'; l_label := NULL;
        END CASE;

        IF fl.file_size IS NULL THEN
          l_size_txt := '';
        ELSIF fl.file_size < 1024*1024 THEN
          l_size_txt := ROUND(fl.file_size/1024) || ' KB';
        ELSE
          l_size_txt := ROUND(fl.file_size/1024/1024, 1) || ' MB';
        END IF;

        HTP.p('  <a class="ms-shared-file-row" href="' || HTF.ESCAPE_SC(fl.file_name)
              || '" download="' || HTF.ESCAPE_SC(NVL(fl.disp_name,'')) || '" target="_blank">');
        IF l_label IS NOT NULL THEN
          HTP.p('    <div class="ms-shared-file-icon ms-shared-file-icon--label" style="background:'
                || l_bg || ';color:' || l_color || '">' || l_label || '</div>');
        ELSE
          HTP.p('    <div class="ms-shared-file-icon" style="background:' || l_bg || '">'
                || '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="' || l_color
                || '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'
                || '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg></div>');
        END IF;
        HTP.p('    <div class="ms-shared-file-info">');
        HTP.p('      <div class="ms-shared-file-name">' || HTF.ESCAPE_SC(NVL(fl.disp_name,'Tệp đính kèm')) || '</div>');
        HTP.p('      <div class="ms-shared-file-size">' || l_size_txt || '</div>');
        HTP.p('    </div>');
        HTP.p('    <div class="ms-shared-file-dl"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg></div>');
        HTP.p('  </a>');
      END LOOP;
      HTP.p('</div>');
    END IF;
  END render_shared_media;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  IF l_conv_id = 0 THEN
    HTP.p('<div style="padding:32px 16px;text-align:center;color:#94A3B8;font-size:13px">Chọn hội thoại để xem thông tin</div>');
    RETURN;
  END IF;
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN;
  END;

  SELECT conv_type, NVL(name,'(Không tên)') INTO l_conv_type, l_conv_name
  FROM CHAT_CONVERSATIONS WHERE conv_id = l_conv_id;

  SELECT COUNT(*) INTO l_member_count FROM CHAT_PARTICIPANTS WHERE conv_id = l_conv_id;

  -- ── DM (hoặc DOC 1-1): Profile Card ───────────────────────────
  IF l_conv_type = 'DM' OR (l_conv_type = 'DOC' AND l_member_count <= 2) THEN
    BEGIN
      -- MATERIALIZE tách remote columns ra trước, tránh ORA-00904 khi CASE WHEN bị push sang DB link
      WITH partner_base AS (
        SELECT /*+ MATERIALIZE */
          p.aus_id, u.emp_id,
          REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','')  AS full_name,
          REGEXP_REPLACE(NVL(d.dep_name,''),'[[:cntrl:]]','')          AS dep_name,
          REGEXP_REPLACE(NVL(pos.position_name,''),'[[:cntrl:]]','')   AS pos_name,
          REGEXP_REPLACE(NVL(e.email_address, e.email_company),'[[:cntrl:]]','') AS email,
          REGEXP_REPLACE(NVL(e.mobile,''),'[[:cntrl:]]','')            AS mobile
        FROM CHAT_PARTICIPANTS p
        JOIN APP_USERS    u   ON u.aus_id  = p.aus_id
        JOIN EMPLOYEES    e   ON e.emp_id  = u.emp_id
        LEFT JOIN DEPARTMENTS d   ON d.dep_id  = e.dep_id
        LEFT JOIN POSITIONS   pos ON pos.pos_id = e.emp_position
        WHERE p.conv_id = l_conv_id AND p.aus_id != l_aus_id
        FETCH FIRST 1 ROW ONLY
      )
      SELECT b.aus_id, b.full_name, b.dep_name, b.pos_name, b.email, b.mobile,
             vf.v_file_name,
             CASE WHEN o.last_seen >= l_online_cutoff THEN 'online' ELSE 'offline' END
      INTO   l_partner_id, l_partner_name, l_partner_dept, l_partner_pos,
             l_partner_email, l_partner_phone, l_partner_img, l_partner_pres
      FROM   partner_base b
      LEFT JOIN v_employees_v6   vf ON vf.emp_id = b.emp_id
      LEFT JOIN CHAT_USER_ONLINE o  ON o.aus_id  = b.aus_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      l_partner_name := 'Unknown';
      l_partner_pres := 'offline';
    END;

    l_partner_hue := TO_CHAR(MOD(NVL(l_partner_id,0) * 47, 360));
    l_partner_av  := UPPER(SUBSTR(REGEXP_SUBSTR(NVL(l_partner_name,'?'),'\S+$'),1,1));
    IF NVL(l_partner_av,'') = '' THEN l_partner_av := '?'; END IF;

    -- Avatar lớn + tên + phòng ban
    HTP.p('<div style="display:flex;flex-direction:column;align-items:center;padding:28px 16px 20px;border-bottom:1px solid #F1F5F9;">');

    -- Avatar 64px
    -- Wrapper (không overflow) để chấm trạng thái nằm ngoài, không bị cắt
    HTP.p('  <div style="position:relative;margin-bottom:12px;flex-shrink:0">');
    -- Vòng avatar — overflow:hidden chỉ để clip ảnh thành hình tròn
    HTP.p('    <div style="width:64px;height:64px;border-radius:50%;'
          || 'background:hsl(' || l_partner_hue || ',55%,52%);'
          || 'color:#fff;display:flex;align-items:center;justify-content:center;'
          || 'font-weight:700;font-size:22px;position:relative;overflow:hidden;'
          || 'box-shadow:0 4px 14px rgba(15,23,42,.10)">');
    IF l_partner_img IS NOT NULL THEN
      HTP.p('<img src="' || HTF.ESCAPE_SC(l_partner_img) || '"'
            || ' style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%"'
            || ' onerror="this.remove()">');
    END IF;
    HTP.p(l_partner_av);
    HTP.p('    </div>');
    -- Chấm trạng thái — nằm NGOÀI vòng avatar
    HTP.p('    <span style="position:absolute;bottom:3px;right:3px;width:14px;height:14px;'
          || 'border-radius:50%;border:2.5px solid #FAFAFA;'
          || 'background:' || CASE WHEN l_partner_pres='online' THEN '#22C55E' ELSE '#CBD5E1' END || '"></span>');
    HTP.p('  </div>');

    -- Tên
    HTP.p('  <div style="font-weight:700;font-size:15px;color:#0F172A;text-align:center;margin-bottom:2px">'
          || HTF.ESCAPE_SC(l_partner_name) || '</div>');

    -- Chức vụ (dòng phụ ngay dưới tên — nhận diện thân thiện hơn)
    IF l_partner_pos IS NOT NULL AND l_partner_pos != '' THEN
      HTP.p('  <div style="font-size:12px;color:#64748B;text-align:center;margin-bottom:6px">'
            || HTF.ESCAPE_SC(l_partner_pos) || '</div>');
    END IF;

    -- Trạng thái online
    HTP.p('  <div style="display:flex;align-items:center;gap:5px;font-size:12px;'
          || CASE WHEN l_partner_pres='online' THEN 'color:#16A34A' ELSE 'color:#94A3B8' END || '">');
    HTP.p('    <span style="width:6px;height:6px;border-radius:50%;background:'
          || CASE WHEN l_partner_pres='online' THEN '#22C55E' ELSE '#CBD5E1' END
          || ';display:inline-block"></span>');
    HTP.p('    ' || CASE WHEN l_partner_pres='online' THEN 'Đang hoạt động' ELSE 'Không hoạt động' END);
    HTP.p('  </div>');

    HTP.p('</div>');

    -- Section Thông tin liên lạc
    HTP.p('<div style="border-top:1px solid #F1F5F9;padding:4px 0;">');
    HTP.p('  <div class="ms-info-section-title">Thông tin liên lạc</div>');

    -- Phòng ban
    IF l_partner_dept IS NOT NULL AND l_partner_dept != '' THEN
      HTP.p('  <div style="display:flex;align-items:center;gap:10px;padding:7px 16px;">');
      HTP.p('    <div style="width:30px;height:30px;border-radius:8px;background:#F1F5F9;'
            || 'display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#475569">');
      HTP.p('      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            || '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>'
            || '<polyline points="9 22 9 12 15 12 15 22"/></svg>');
      HTP.p('    </div>');
      HTP.p('    <div style="min-width:0">');
      HTP.p('      <div style="font-size:10.5px;color:#94A3B8">Phòng ban</div>');
      HTP.p('      <div style="font-size:12.5px;color:#334155;font-weight:500">'
            || HTF.ESCAPE_SC(l_partner_dept) || '</div>');
      HTP.p('    </div>');
      HTP.p('  </div>');
    END IF;

    -- Email
    IF l_partner_email IS NOT NULL AND l_partner_email != '' THEN
      HTP.p('  <div style="display:flex;align-items:center;gap:10px;padding:7px 16px;">');
      HTP.p('    <div style="width:30px;height:30px;border-radius:8px;background:#F1F5F9;'
            || 'display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#475569">');
      HTP.p('      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            || '<path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/>'
            || '<polyline points="22,6 12,13 2,6"/></svg>');
      HTP.p('    </div>');
      HTP.p('    <div style="min-width:0;overflow:hidden">');
      HTP.p('      <div style="font-size:10.5px;color:#94A3B8">Email</div>');
      HTP.p('      <a href="mailto:' || HTF.ESCAPE_SC(l_partner_email) || '"'
            || ' style="font-size:12.5px;color:#2563EB;font-weight:500;white-space:nowrap;'
            || 'overflow:hidden;text-overflow:ellipsis;display:block;text-decoration:none">'
            || HTF.ESCAPE_SC(l_partner_email) || '</a>');
      HTP.p('    </div>');
      HTP.p('  </div>');
    END IF;

    -- Điện thoại
    IF l_partner_phone IS NOT NULL AND l_partner_phone != '' THEN
      HTP.p('  <div style="display:flex;align-items:center;gap:10px;padding:7px 16px 10px;">');
      HTP.p('    <div style="width:30px;height:30px;border-radius:8px;background:#F1F5F9;'
            || 'display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#475569">');
      HTP.p('      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            || '<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.69 12'
            || ' 19.79 19.79 0 0 1 1.61 3.39 2 2 0 0 1 3.6 1.21h3a2 2 0 0 1 2 1.72'
            || 'c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L7.91 9a16 16 0 0 0 6 6'
            || 'l1.15-1.15a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92z"/></svg>');
      HTP.p('    </div>');
      HTP.p('    <div style="min-width:0">');
      HTP.p('      <div style="font-size:10.5px;color:#94A3B8">Điện thoại</div>');
      HTP.p('      <div style="font-size:12.5px;color:#334155;font-weight:500">'
            || HTF.ESCAPE_SC(l_partner_phone) || '</div>');
      HTP.p('    </div>');
      HTP.p('  </div>');
    END IF;

    HTP.p('</div>');

    render_shared_media(l_conv_id);

    -- Section Tùy chọn
    HTP.p('<div style="border-top:1px solid #F1F5F9;padding-top:4px;">');
    HTP.p('  <div class="ms-info-section-title" style="margin-bottom:2px">Tùy chọn</div>');

    -- Thông báo (toggle)
    HTP.p('  <div class="ms-rp-opt">');
    HTP.p('    <div class="ms-rp-opt-left">');
    HTP.p('      <div class="ms-rp-opt-icon"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg></div>');
    HTP.p('      <span class="ms-rp-opt-label">Thông báo</span>');
    HTP.p('    </div>');
    HTP.p('    <div class="ms-rp-toggle" onclick="this.classList.toggle(''off'')"><div class="ms-rp-toggle-thumb"></div></div>');
    HTP.p('  </div>');

    -- Ghim
    HTP.p('  <div class="ms-rp-opt">');
    HTP.p('    <div class="ms-rp-opt-left">');
    HTP.p('      <div class="ms-rp-opt-icon"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg></div>');
    HTP.p('      <span class="ms-rp-opt-label">Ghim cuộc trò chuyện</span>');
    HTP.p('    </div>');
    HTP.p('  </div>');

    -- Chặn
    HTP.p('  <div class="ms-rp-opt" style="padding-bottom:12px">');
    HTP.p('    <div class="ms-rp-opt-left">');
    HTP.p('      <div class="ms-rp-opt-icon danger"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg></div>');
    HTP.p('      <span class="ms-rp-opt-label danger">Chặn người dùng</span>');
    HTP.p('    </div>');
    HTP.p('  </div>');

    HTP.p('</div>');

  -- ── CHANNEL (hoặc DOC nhóm >2): Group Header + Member List ────
  ELSE
    DECLARE
      l_grp_initl VARCHAR2(4) := UPPER(SUBSTR(NVL(l_conv_name,'?'),1,1));
      l_grp_hue   VARCHAR2(10) := TO_CHAR(MOD(l_conv_id * 47, 360));
    BEGIN
      -- Group header
      HTP.p('<div style="display:flex;flex-direction:column;align-items:center;padding:28px 16px 20px;border-bottom:1px solid #F1F5F9;">');
      HTP.p('  <div style="width:64px;height:64px;border-radius:18px;'
            || 'background:hsl(' || l_grp_hue || ',55%,52%);'
            || 'color:#fff;display:flex;align-items:center;justify-content:center;'
            || 'font-weight:700;font-size:22px;flex-shrink:0;'
            || 'box-shadow:0 4px 14px rgba(15,23,42,.10);margin-bottom:12px">');
      HTP.p('    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            || '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>'
            || '<path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>');
      HTP.p('  </div>');
      HTP.p('  <div style="font-weight:700;font-size:15px;color:#0F172A;text-align:center;margin-bottom:4px">'
            || HTF.ESCAPE_SC(l_conv_name) || '</div>');
      HTP.p('  <div style="font-size:12px;color:#94A3B8">' || l_member_count || ' thành viên</div>');

      HTP.p('</div>');
    END;

    -- Member list
    HTP.p('<div class="ms-info-section">');
    HTP.p('  <div class="ms-info-section-title">');
    HTP.p('    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">'
          || '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>'
          || '<path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>');
    HTP.p('    Thành viên (' || l_member_count || ')');
    HTP.p('  </div>');

    FOR mem IN (
      WITH members_raw AS (
        SELECT /*+ MATERIALIZE */
          p.aus_id, p.is_admin, u.emp_id,
          REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') AS full_name,
          REGEXP_REPLACE(NVL(d.dep_name,''),'[[:cntrl:]]','')         AS dep_name
        FROM CHAT_PARTICIPANTS p
        JOIN APP_USERS   u ON u.aus_id = p.aus_id
        JOIN EMPLOYEES   e ON e.emp_id = u.emp_id
        LEFT JOIN DEPARTMENTS d ON d.dep_id = e.dep_id
        WHERE p.conv_id = l_conv_id
      )
      SELECT r.aus_id, r.is_admin, r.full_name, r.dep_name, vf.v_file_name AS img,
             CASE WHEN o.last_seen >= l_online_cutoff THEN 'online' ELSE 'offline' END AS presence
      FROM   members_raw r
      LEFT JOIN CHAT_USER_ONLINE o  ON o.aus_id  = r.aus_id
      LEFT JOIN v_employees_v6   vf ON vf.emp_id = r.emp_id
      ORDER BY r.is_admin DESC, r.full_name
    ) LOOP
      DECLARE
        l_av  VARCHAR2(4)  := UPPER(SUBSTR(REGEXP_SUBSTR(mem.full_name,'\S+$'),1,1));
        l_hue VARCHAR2(10) := TO_CHAR(MOD(mem.aus_id * 47, 360));
        l_me  BOOLEAN      := (mem.aus_id = l_aus_id);
      BEGIN
        IF NVL(l_av,'') = '' THEN l_av := '?'; END IF;
        HTP.p('<div class="ms-member-row">');
        HTP.p('  <div class="ms-member-av" style="background:hsl(' || l_hue || ',55%,52%)">');
        IF mem.img IS NOT NULL THEN
          HTP.p('<img src="' || HTF.ESCAPE_SC(mem.img) || '" onerror="this.remove()">');
        END IF;
        HTP.p(NVL(l_av,'?'));
        HTP.p('<span class="ms-presence ' || mem.presence || '"></span>');
        HTP.p('  </div>');
        HTP.p('  <div class="ms-member-info">');
        HTP.p('    <div class="ms-member-name">'
              || HTF.ESCAPE_SC(mem.full_name)
              || CASE WHEN l_me THEN ' <span style="color:#94A3B8;font-size:11px;font-weight:400">(bạn)</span>' END
              || '</div>');
        IF mem.dep_name IS NOT NULL AND mem.dep_name != '' THEN
          HTP.p('    <div class="ms-member-role">' || HTF.ESCAPE_SC(mem.dep_name) || '</div>');
        END IF;
        HTP.p('  </div>');
        IF mem.is_admin = 1 THEN
          HTP.p('  <span class="ms-member-badge admin">QUẢN TRỊ</span>');
        END IF;
        HTP.p('</div>');
      END;
    END LOOP;

    HTP.p('</div>');

    render_shared_media(l_conv_id);

    -- Section Tùy chọn (CHANNEL)
    HTP.p('<div style="border-top:1px solid #F1F5F9;padding-top:4px;padding-bottom:4px;">');
    HTP.p('  <div class="ms-info-section-title" style="margin-bottom:2px">Tùy chọn</div>');

    -- Thông báo toggle
    HTP.p('  <div class="ms-rp-opt">');
    HTP.p('    <div class="ms-rp-opt-left">');
    HTP.p('      <div class="ms-rp-opt-icon"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg></div>');
    HTP.p('      <span class="ms-rp-opt-label">Thông báo</span>');
    HTP.p('    </div>');
    HTP.p('    <div class="ms-rp-toggle" onclick="this.classList.toggle(''off'')"><div class="ms-rp-toggle-thumb"></div></div>');
    HTP.p('  </div>');

    -- Ghim
    HTP.p('  <div class="ms-rp-opt">');
    HTP.p('    <div class="ms-rp-opt-left">');
    HTP.p('      <div class="ms-rp-opt-icon"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg></div>');
    HTP.p('      <span class="ms-rp-opt-label">Ghim cuộc trò chuyện</span>');
    HTP.p('    </div>');
    HTP.p('  </div>');

    -- Rời nhóm
    HTP.p('  <div class="ms-rp-opt" style="padding-bottom:12px">');
    HTP.p('    <div class="ms-rp-opt-left">');
    HTP.p('      <div class="ms-rp-opt-icon danger"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg></div>');
    HTP.p('      <span class="ms-rp-opt-label danger">Rời nhóm</span>');
    HTP.p('    </div>');
    HTP.p('  </div>');

    HTP.p('</div>');
  END IF;

EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="color:#DC2626;padding:16px">Lỗi: ' || HTF.ESCAPE_SC(SQLERRM) || '</div>');
END;


-- ============================================================
-- 9. msContactsHtml
--    Trả HTML danh sách contacts cho compose overlay.
--    x01=search text (optional)
--    Dùng MATERIALIZE + l_online_cutoff.
-- ============================================================
DECLARE
  l_aus_id        NUMBER;
  l_search        VARCHAR2(200) := LOWER(TRIM(apex_application.g_x01));
  l_online_cutoff TIMESTAMP     := SYSTIMESTAMP - INTERVAL '35' SECOND;
  l_prev_dep      VARCHAR2(200) := '~~init~~';
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('<div style="padding:16px;color:#DC2626">Phiên đăng nhập hết hạn</div>'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('<div style="padding:16px;color:#DC2626">Không tìm thấy user</div>'); RETURN;
  END;

  FOR usr IN (
    WITH users_raw AS (
      SELECT /*+ MATERIALIZE */
        u.aus_id, u.emp_id,
        REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') AS full_name,
        REGEXP_REPLACE(NVL(d.dep_name,'Khác'),    '[[:cntrl:]]','') AS dep_name
      FROM APP_USERS u
      JOIN EMPLOYEES e ON e.emp_id = u.emp_id
      LEFT JOIN DEPARTMENTS d ON d.dep_id = e.dep_id
      WHERE u.aus_id != l_aus_id
        AND (l_search IS NULL
             OR LOWER(NVL(e.full_name,'')) LIKE '%'||l_search||'%'
             OR LOWER(NVL(d.dep_name,''))  LIKE '%'||l_search||'%')
    )
    SELECT r.aus_id, r.full_name, r.dep_name, vf.v_file_name AS img,
           CASE WHEN o.last_seen >= l_online_cutoff THEN 'online' ELSE 'offline' END AS presence
    FROM   users_raw r
    LEFT JOIN CHAT_USER_ONLINE o  ON o.aus_id  = r.aus_id
    LEFT JOIN v_employees_v6   vf ON vf.emp_id = r.emp_id
    ORDER  BY r.dep_name, r.full_name
  ) LOOP
    -- Department header
    IF usr.dep_name <> l_prev_dep THEN
      l_prev_dep := usr.dep_name;
      HTP.p('<div class="ms-dept-header">' || HTF.ESCAPE_SC(usr.dep_name) || '</div>');
    END IF;

    DECLARE
      l_av   VARCHAR2(4)    := UPPER(SUBSTR(REGEXP_SUBSTR(usr.full_name,'\S+$'),1,1));
      l_hue  VARCHAR2(10)   := TO_CHAR(MOD(usr.aus_id * 47, 360));
      l_name VARCHAR2(200)  := HTF.ESCAPE_SC(usr.full_name);
      l_dept VARCHAR2(200)  := HTF.ESCAPE_SC(usr.dep_name);
    BEGIN
      IF NVL(l_av,'') = '' THEN l_av := '?'; END IF;
      HTP.p('<div class="ms-contact-item"'
            || ' data-aus-id="' || usr.aus_id || '"'
            || ' data-name="'   || REPLACE(l_name,'"','&quot;') || '"'
            || ' data-dept="'   || REPLACE(l_dept,'"','&quot;') || '"'
            || ' data-hue="'    || l_hue || '">');
      HTP.p('  <div class="ms-contact-av" style="background:hsl(' || l_hue || ',55%,52%)">');
      IF usr.img IS NOT NULL THEN
        HTP.p('<img src="' || HTF.ESCAPE_SC(usr.img) || '" onerror="this.remove()">');
      END IF;
      HTP.p(NVL(l_av,'?'));
      HTP.p('<span class="ms-presence ' || usr.presence || '"></span>');
      HTP.p('  </div>');
      HTP.p('  <div class="ms-contact-info">');
      HTP.p('    <div class="ms-contact-name">' || l_name || '</div>');
      HTP.p('    <div class="ms-contact-dept">' || l_dept || '</div>');
      HTP.p('  </div>');
      HTP.p('  <div class="ms-contact-check"></div>');
      HTP.p('</div>');
    END;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="padding:16px;color:#DC2626">Lỗi: ' || HTF.ESCAPE_SC(SQLERRM) || '</div>');
END;


-- ============================================================
-- 10. msCreateConv
--     Tạo hội thoại mới (DM hoặc CHANNEL).
--     x01=conv_type | x02=name | x03=members JSON array
--     DM dedup: nếu đã tồn tại → trả conv_id cũ.
--     Messenger không gắn doc_type/doc_no.
-- ============================================================
DECLARE
  l_aus_id     NUMBER;
  l_partner_id NUMBER;
  l_existing   NUMBER;
  l_conv_id    NUMBER;
  l_conv_type  VARCHAR2(10)  := TRIM(apex_application.g_x01);
  l_name       VARCHAR2(200) := TRIM(apex_application.g_x02);
  l_members    VARCHAR2(4000) := NVL(NULLIF(TRIM(apex_application.g_x03),''), '[]');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  IF l_conv_type NOT IN ('DM','CHANNEL') THEN
    HTP.p('{"error":"invalid_conv_type"}'); RETURN;
  END IF;

  -- DM dedup (messenger: không filter doc_type/doc_no)
  IF l_conv_type = 'DM' THEN
    BEGIN
      SELECT value INTO l_partner_id
      FROM JSON_TABLE(l_members, '$[*]' COLUMNS (value NUMBER PATH '$'))
      FETCH FIRST 1 ROW ONLY;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      HTP.p('{"error":"no_partner"}'); RETURN;
    END;

    BEGIN
      SELECT c.conv_id INTO l_existing
      FROM   CHAT_CONVERSATIONS c
      JOIN   CHAT_PARTICIPANTS p1 ON p1.conv_id = c.conv_id AND p1.aus_id = l_aus_id
      JOIN   CHAT_PARTICIPANTS p2 ON p2.conv_id = c.conv_id AND p2.aus_id = l_partner_id
      WHERE  c.conv_type = 'DM'
        AND  c.doc_type IS NULL  -- messenger conv không có doc context
        AND  c.doc_no   IS NULL
        AND  (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) = 2
      FETCH FIRST 1 ROW ONLY;
      HTP.p('{"conv_id":' || l_existing || ',"is_new":false}');
      RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
  END IF;

  -- Tạo mới
  l_conv_id := CONV_SEQ.NEXTVAL;
  INSERT INTO CHAT_CONVERSATIONS
    (conv_id, conv_type, name, aus_id, doc_type, doc_no, created_by, create_date)
  VALUES
    (l_conv_id, l_conv_type, l_name, l_aus_id, NULL, NULL, :APP_USER, SYSTIMESTAMP);

  -- Người tạo: is_admin=1
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin, created_by, create_date)
  VALUES (l_conv_id, l_aus_id, 1, :APP_USER, SYSTIMESTAMP);

  -- Thêm thành viên
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin, created_by, create_date)
  SELECT l_conv_id, value, 0, :APP_USER, SYSTIMESTAMP
  FROM JSON_TABLE(l_members, '$[*]' COLUMNS (value NUMBER PATH '$'))
  WHERE value != l_aus_id;

  COMMIT;
  HTP.p('{"conv_id":' || l_conv_id || ',"is_new":true}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 10b. msFindDM  (chống trùng DM/DOC 1-1 — gọi TRƯỚC khi tạo qua Node)
--     x01 = aus_id của đối phương.
--     x02 = doc_type | x03 = doc_no (optional — chỉ truyền khi tạo từ trang chứng từ)
--     - x02/x03 trống: tìm DM chung cũ (doc_type/doc_no NULL) — hành vi gốc.
--     - x02/x03 có giá trị: tìm hội thoại DOC 1-1 cũ ĐÚNG chứng từ này với đối phương.
--     - Tìm thấy: bỏ ẩn (is_hidden=0) hoặc rejoin nếu đã rời, trả {found:true, conv_id}.
--     - Không thấy: trả {found:false} → frontend gọi Node /create (giữ real-time).
--     Lý do tồn tại: create đi qua Node (ngoài repo) vốn KHÔNG dedup, gây
--     tạo nhiều hội thoại trùng. Pre-check này đưa dedup về phía APEX (trong tầm kiểm soát).
-- ============================================================
DECLARE
  l_aus_id     NUMBER;
  l_partner_id NUMBER := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_doc_type   VARCHAR2(30) := NULLIF(TRIM(apex_application.g_x02), '');
  l_doc_no     VARCHAR2(60) := NULLIF(TRIM(apex_application.g_x03), '');
  l_conv_type  VARCHAR2(10) := CASE WHEN l_doc_type IS NOT NULL AND l_doc_no IS NOT NULL THEN 'DOC' ELSE 'DM' END;
  l_found      NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  IF l_partner_id = 0 OR l_partner_id = l_aus_id THEN
    HTP.p('{"found":false}'); RETURN;
  END IF;

  -- (1) Hội thoại mà cả hai còn là participant (bao gồm cả khi mình đã Ẩn — is_hidden=1)
  BEGIN
    SELECT c.conv_id INTO l_found
    FROM   CHAT_CONVERSATIONS c
    JOIN   CHAT_PARTICIPANTS p1 ON p1.conv_id = c.conv_id AND p1.aus_id = l_aus_id
    JOIN   CHAT_PARTICIPANTS p2 ON p2.conv_id = c.conv_id AND p2.aus_id = l_partner_id
    WHERE  c.conv_type = l_conv_type
      AND  ((l_doc_type IS NULL AND c.doc_type IS NULL) OR c.doc_type = l_doc_type)
      AND  ((l_doc_no   IS NULL AND c.doc_no   IS NULL) OR c.doc_no   = l_doc_no)
      AND  (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) = 2
    ORDER  BY c.conv_id ASC
    FETCH FIRST 1 ROW ONLY;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    l_found := NULL;
  END;

  -- (2) Fallback: mình đã RỜI (xóa participant row) nhưng mình là người tạo conv
  IF l_found IS NULL THEN
    BEGIN
      SELECT c.conv_id INTO l_found
      FROM   CHAT_CONVERSATIONS c
      JOIN   CHAT_PARTICIPANTS p2 ON p2.conv_id = c.conv_id AND p2.aus_id = l_partner_id
      WHERE  c.conv_type = l_conv_type
        AND  ((l_doc_type IS NULL AND c.doc_type IS NULL) OR c.doc_type = l_doc_type)
        AND  ((l_doc_no   IS NULL AND c.doc_no   IS NULL) OR c.doc_no   = l_doc_no)
        AND  c.aus_id   = l_aus_id
      ORDER  BY c.conv_id ASC
      FETCH FIRST 1 ROW ONLY;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      l_found := NULL;
    END;
  END IF;

  IF l_found IS NULL THEN
    HTP.p('{"found":false}'); RETURN;
  END IF;

  -- Mở lại: bỏ ẩn nếu đang ẩn; rejoin nếu đã rời (row bị xóa)
  UPDATE CHAT_PARTICIPANTS SET is_hidden = 0
  WHERE  conv_id = l_found AND aus_id = l_aus_id;
  IF SQL%ROWCOUNT = 0 THEN
    INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin, created_by, create_date)
    VALUES (l_found, l_aus_id, 0, :APP_USER, SYSTIMESTAMP);
  END IF;
  COMMIT;

  HTP.p('{"found":true,"conv_id":' || l_found || '}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 11. msGetAvatar
--     Trả JSON { aus_id, img } theo aus_id truyền vào x01.
--     Dùng cho typing indicator — cache phía client.
-- ============================================================
DECLARE
  l_aus_id NUMBER := TO_NUMBER(apex_application.g_x01);
  l_img    VARCHAR2(1000);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;

  BEGIN
    SELECT vf.v_file_name
    INTO   l_img
    FROM   APP_USERS u
    JOIN   v_employees_v6 vf ON vf.emp_id = u.emp_id
    WHERE  u.aus_id = l_aus_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"aus_id":' || l_aus_id || '}'); RETURN;
  END;

  HTP.p(JSON_OBJECT(
    'aus_id' VALUE l_aus_id,
    'img'    VALUE l_img
    ABSENT ON NULL
  ));
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- SCHEMA — bổ sung cột cho dot-menu (chạy 1 lần)
-- ============================================================
--   Pin / Hide ở mức per-user → lưu trên CHAT_PARTICIPANTS.
--   "Xóa hội thoại" = rời cuộc trò chuyện (DELETE participant row).
--
--   ALTER TABLE CHAT_PARTICIPANTS ADD (
--     is_pinned NUMBER(1) DEFAULT 0 NOT NULL,
--     is_hidden NUMBER(1) DEFAULT 0 NOT NULL
--   );
--
--   Lưu ý: msConvListHtml đã filter NVL(p.is_hidden,0)=0 và
--   ORDER BY is_pinned DESC, section "Ghim" đứng trước.


-- ============================================================
-- SCHEMA — conv_type thêm giá trị 'DOC' (hội thoại theo chứng từ)
-- ============================================================
--   Trước khi deploy: kiểm tra CHAT_CONVERSATIONS.CONV_TYPE có CHECK
--   constraint giới hạn IN ('DM','CHANNEL') hay không:
--
--   SELECT constraint_name, search_condition
--   FROM   user_constraints
--   WHERE  table_name = 'CHAT_CONVERSATIONS' AND constraint_type = 'C';
--
--   Nếu có, nới constraint (đổi <constraint_name> theo kết quả query trên):
--
--   ALTER TABLE CHAT_CONVERSATIONS DROP CONSTRAINT <constraint_name>;
--   ALTER TABLE CHAT_CONVERSATIONS ADD CONSTRAINT <constraint_name>
--     CHECK (conv_type IN ('DM','CHANNEL','DOC'));
--
--   Không cần thêm cột mới — doc_type/doc_no đã tồn tại sẵn trên bảng này.


-- ============================================================
-- 12. msPinConv  — toggle ghim hội thoại (per-user)
--     x01 = conv_id
-- ============================================================
DECLARE
  l_conv_id NUMBER := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_aus_id  NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);

  UPDATE CHAT_PARTICIPANTS
  SET    is_pinned = CASE WHEN NVL(is_pinned,0) = 1 THEN 0 ELSE 1 END
  WHERE  conv_id = l_conv_id AND aus_id = l_aus_id;
  COMMIT;

  HTP.p('{"status":"ok"}');
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 13. msHideConv  — ẩn hội thoại khỏi danh sách (per-user)
--     x01 = conv_id
-- ============================================================
DECLARE
  l_conv_id NUMBER := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_aus_id  NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);

  UPDATE CHAT_PARTICIPANTS
  SET    is_hidden = 1
  WHERE  conv_id = l_conv_id AND aus_id = l_aus_id;
  COMMIT;

  HTP.p('{"status":"ok"}');
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 14. msDeleteConv  — xóa hội thoại khỏi danh sách = rời cuộc trò chuyện
--     x01 = conv_id. Chỉ xóa participant row của chính user.
-- ============================================================
DECLARE
  l_conv_id NUMBER := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_aus_id  NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);

  DELETE FROM CHAT_PARTICIPANTS
  WHERE  conv_id = l_conv_id AND aus_id = l_aus_id;
  COMMIT;

  HTP.p('{"status":"ok"}');
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- SCHEMA — bảng cho React + Pin tin nhắn (chạy 1 lần)
-- ============================================================
--   CREATE TABLE CHAT_REACTIONS (
--     msg_id      NUMBER          NOT NULL,
--     aus_id      NUMBER          NOT NULL,
--     emoji       VARCHAR2(16)    NOT NULL,
--     create_date TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
--     CONSTRAINT pk_chat_reactions PRIMARY KEY (msg_id, aus_id, emoji)
--   );
--   CREATE INDEX ix_chat_reactions_msg ON CHAT_REACTIONS(msg_id);
--
--   CREATE TABLE CHAT_PINNED_MSGS (
--     conv_id  NUMBER NOT NULL,
--     msg_id   NUMBER NOT NULL,
--     aus_id   NUMBER NOT NULL,           -- ai ghim
--     pin_date TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
--     CONSTRAINT pk_chat_pinned PRIMARY KEY (conv_id, msg_id)
--   );


-- ============================================================
-- 15. msToggleReaction — thêm/bỏ reaction của user trên 1 tin
--     x01 = msg_id | x02 = emoji
-- ============================================================
DECLARE
  l_msg_id NUMBER       := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_emoji  VARCHAR2(16) := SUBSTR(apex_application.g_x02, 1, 16);
  l_aus_id NUMBER;
  l_exist  NUMBER := 0;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);

  IF l_msg_id = 0 OR l_emoji IS NULL THEN HTP.p('{"error":"bad_input"}'); RETURN; END IF;

  SELECT COUNT(*) INTO l_exist FROM CHAT_REACTIONS
  WHERE  msg_id = l_msg_id AND aus_id = l_aus_id AND emoji = l_emoji;

  IF l_exist > 0 THEN
    DELETE FROM CHAT_REACTIONS
    WHERE  msg_id = l_msg_id AND aus_id = l_aus_id AND emoji = l_emoji;
    COMMIT;
    HTP.p('{"status":"ok","reacted":0}');
  ELSE
    INSERT INTO CHAT_REACTIONS (msg_id, aus_id, emoji)
    VALUES (l_msg_id, l_aus_id, l_emoji);
    COMMIT;
    HTP.p('{"status":"ok","reacted":1}');
  END IF;
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 16. msTogglePinMsg — ghim/bỏ ghim 1 tin trong hội thoại
--     x01 = conv_id | x02 = msg_id. Mọi thành viên đều ghim được.
-- ============================================================
DECLARE
  l_conv_id NUMBER := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_msg_id  NUMBER := TO_NUMBER(NVL(TRIM(apex_application.g_x02),'0'));
  l_aus_id  NUMBER;
  l_member  NUMBER := 0;
  l_exist   NUMBER := 0;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);

  -- Chỉ thành viên hội thoại mới được ghim
  SELECT COUNT(*) INTO l_member FROM CHAT_PARTICIPANTS
  WHERE  conv_id = l_conv_id AND aus_id = l_aus_id;
  IF l_member = 0 THEN HTP.p('{"error":"not_member"}'); RETURN; END IF;

  SELECT COUNT(*) INTO l_exist FROM CHAT_PINNED_MSGS
  WHERE  conv_id = l_conv_id AND msg_id = l_msg_id;

  IF l_exist > 0 THEN
    DELETE FROM CHAT_PINNED_MSGS WHERE conv_id = l_conv_id AND msg_id = l_msg_id;
    COMMIT;
    HTP.p('{"status":"ok","pinned":0}');
  ELSE
    INSERT INTO CHAT_PINNED_MSGS (conv_id, msg_id, aus_id)
    VALUES (l_conv_id, l_msg_id, l_aus_id);
    COMMIT;
    HTP.p('{"status":"ok","pinned":1}');
  END IF;
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 17. msPinnedListHtml — danh sách tin đã ghim của hội thoại (HTML)
--     x01 = conv_id
-- ============================================================
DECLARE
  l_conv_id NUMBER := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_aus_id  NUMBER;
  l_count   NUMBER := 0;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p(''); RETURN;
  END IF;

  HTP.p('<div data-pin-count="0" id="ms-pin-data" style="display:none"></div>');

  FOR p IN (
    SELECT m.msg_id,
           REGEXP_REPLACE(NVL(e.full_name,'?'),'[[:cntrl:]]','') AS from_name,
           CASE WHEN m.delete_date IS NOT NULL THEN '[Tin nhắn đã bị thu hồi]'
                ELSE SUBSTR(NVL(m.body,''),1,120) END AS body
    FROM   CHAT_PINNED_MSGS pp
    JOIN   CHAT_MESSENGERS  m ON m.msg_id = pp.msg_id
    JOIN   APP_USERS  u ON u.aus_id = m.from_aus_id
    JOIN   EMPLOYEES  e ON e.emp_id = u.emp_id
    WHERE  pp.conv_id = l_conv_id
    ORDER  BY pp.pin_date DESC
  ) LOOP
    l_count := l_count + 1;
    HTP.p('<div class="ms-pin-item" data-msg-id="' || p.msg_id || '"'
          || ' onclick="msJumpToMsg(' || p.msg_id || ')">');
    HTP.p('  <div class="ms-pin-item-main">');
    HTP.p('    <div class="ms-pin-item-name">' || HTF.ESCAPE_SC(p.from_name) || '</div>');
    HTP.p('    <div class="ms-pin-item-body">' || HTF.ESCAPE_SC(p.body) || '</div>');
    HTP.p('  </div>');
    HTP.p('  <button type="button" class="ms-pin-unpin" title="Bỏ ghim"'
          || ' onclick="event.stopPropagation();msTogglePinMsg(' || p.msg_id || ')">'
          || '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>'
          || '</button>');
    HTP.p('</div>');
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('');
END;


-- ============================================================
-- 18. msForwardListHtml — danh sách hội thoại để chuyển tiếp (HTML)
--     x01 = search. Item có data-conv-id + data-conv-name.
-- ============================================================
DECLARE
  l_search VARCHAR2(200) := LOWER(TRIM(apex_application.g_x01));
  l_aus_id NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p(''); RETURN;
  END IF;
  SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);

  FOR c IN (
    SELECT c.conv_id, c.conv_type,
           (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) AS member_count,
           CASE
             WHEN c.conv_type = 'CHANNEL' THEN NVL(c.name,'(Không tên)')
             WHEN c.conv_type = 'DOC' AND (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) > 2
               THEN NVL(c.name,'(Không tên)')
             ELSE (
               SELECT REGEXP_REPLACE(NVL(e2.full_name,'Unknown'),'[[:cntrl:]]','')
               FROM   CHAT_PARTICIPANTS p2
               JOIN   APP_USERS u2 ON u2.aus_id = p2.aus_id
               JOIN   EMPLOYEES e2 ON e2.emp_id = u2.emp_id
               WHERE  p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
               FETCH FIRST 1 ROW ONLY
             )
           END AS display_name
    FROM   CHAT_CONVERSATIONS c
    JOIN   CHAT_PARTICIPANTS  p ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
    WHERE  NVL(p.is_hidden,0) = 0
    ORDER  BY c.last_msg_date DESC NULLS LAST
  ) LOOP
    IF l_search IS NULL OR LOWER(NVL(c.display_name,'')) LIKE '%'||l_search||'%' THEN
      DECLARE
        l_initl    VARCHAR2(4)  := UPPER(SUBSTR(REGEXP_SUBSTR(c.display_name,'\S+$'),1,1));
        l_hue      VARCHAR2(10) := TO_CHAR(MOD(c.conv_id*47, 360));
        l_is_group BOOLEAN      := c.conv_type = 'CHANNEL' OR (c.conv_type = 'DOC' AND c.member_count > 2);
      BEGIN
        HTP.p('<div class="ms-fwd-item" data-conv-id="' || c.conv_id || '"'
              || ' data-conv-name="' || HTF.ESCAPE_SC(c.display_name) || '"'
              || ' onclick="msSelectForward(this)">');
        HTP.p('  <div class="ms-fwd-av' || CASE WHEN l_is_group THEN ' group' END
              || '" style="background:hsl(' || l_hue || ',55%,52%)">'
              || CASE WHEN l_is_group THEN '<i class="fa fa-users"></i>'
                      ELSE NVL(l_initl,'?') END || '</div>');
        HTP.p('  <div style="flex:1;min-width:0"><div class="ms-fwd-name">'
              || HTF.ESCAPE_SC(c.display_name) || '</div></div>');
        HTP.p('</div>');
      END;
    END IF;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('');
END;


-- ============================================================
-- 19. msUploadAttachment
--     CHỈ làm upload file, KHÔNG insert gì vào CHAT_MESSENGERS.
--     Đây là callback DUY NHẤT được phép tham chiếu :P10022710201_UPLOAD_FILE
--     — đã xác nhận qua thực tế: tham chiếu item File Browse "Optimized for
--     Images" từ MỘT callback gộp nhiều việc khác (insert/update/UTL_HTTP)
--     gây ORA-01403 "ajax_set_session_state" dù đã khai báo pageItems đầy đủ
--     ở JS. Tách upload ra callback riêng, đơn giản nhất có thể, là cách né
--     lỗi này — không có lời giải thích chắc chắn từ tài liệu APEX công khai
--     cho hành vi này, chỉ biết tách ra thì hết lỗi.
--     Không nhận tham số x01-x03. Trả {fil_id, file_name} hoặc {error}.
-- ============================================================
DECLARE
  l_fil_id    NUMBER(15);
  l_mess      VARCHAR2(2000);
  l_file_nm   VARCHAR2(600);
  -- DIAGNOSTIC: xác nhận item upload có giá trị ở server không + còn file ở
  -- temp table không, để biết vì sao UploadMultipleFilesChat trả fil_id NULL.
  -- Item File Browse KHÔNG serialize qua pageItems trong AJAX -> bind
  -- :P10022710201_UPLOAD_FILE NULL. Tên file (key trong temp table) được client
  -- gửi qua x05 (string thường). Fallback về bind nếu chạy trong page submit thật.
  l_item_val  VARCHAR2(4000) := NVL(apex_application.g_x05, :P10022710201_UPLOAD_FILE);
  l_temp_cnt  NUMBER := 0;
  l_temp_all  NUMBER := 0;        -- tổng temp file trong session (bất kể tên)
  l_temp_nms  VARCHAR2(4000);     -- danh sách tên temp file để đối chiếu
  l_aaf_cnt   NUMBER := 0;        -- apex_application_files (store rộng hơn)
  l_wff_cnt   NUMBER := 0;        -- wwv_flow_files raw theo filename
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;

  -- Chẩn đoán nơi file thực sự nằm. apex_application_temp_files chỉ show file
  -- của REQUEST hiện tại; nếu file upload ở 1 request AJAX riêng trước đó thì
  -- có thể KHÔNG thấy ở đây -> phải đọc wwv_flow_files / cách khác.
  BEGIN
    SELECT COUNT(*),
           LISTAGG(name, ' | ') WITHIN GROUP (ORDER BY name)
    INTO   l_temp_all, l_temp_nms
    FROM   apex_application_temp_files;
  EXCEPTION WHEN OTHERS THEN l_temp_all := -1; l_temp_nms := SQLERRM;
  END;

  BEGIN
    SELECT COUNT(*) INTO l_temp_cnt
    FROM   apex_application_temp_files
    WHERE  l_item_val IS NOT NULL
      AND  INSTR(':' || l_item_val || ':', ':' || name || ':') > 0;
  EXCEPTION WHEN OTHERS THEN l_temp_cnt := -1;
  END;

  -- Probe store rộng hơn: bytes file có nằm đâu đó server không?
  BEGIN
    SELECT COUNT(*) INTO l_aaf_cnt FROM apex_application_files
    WHERE  l_item_val IS NOT NULL AND name = l_item_val;
  EXCEPTION WHEN OTHERS THEN l_aaf_cnt := -1;
  END;
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM wwv_flow_files WHERE filename = :1 OR name = :1'
      INTO l_wff_cnt USING l_item_val, l_item_val;
  EXCEPTION WHEN OTHERS THEN l_wff_cnt := -1;
  END;

  pkg_upload_file.UploadMultipleFilesChat(
    p_file_names  => l_item_val,   -- = g_x05 (tên file client gửi), KHÔNG dùng bind
    p_co_id       => :G_CO_ID,
    p_oun_id      => :G_OUN_ID_INS,
    p_module      => '01',
    p_table       => 'CHAT_MESSENGERS',
    p_user_name   => :G_USER_NAME,
    p_id          => NULL,
    p_total_files => NULL,
    p_ffo_id      => NULL,
    p_fil_id      => l_fil_id,
    p_error       => l_mess);

  IF l_fil_id IS NULL THEN
    ROLLBACK;
    -- Trả kèm chẩn đoán: item_val (tên file ở server), temp_cnt (số BLOB temp
    -- khớp), co_id/oun_id/user_name (các tham số có thể đang NULL), proc_mess.
    HTP.p(JSON_OBJECT(
      'error'     VALUE NVL(l_mess,'upload_failed'),
      'item_val'  VALUE NVL(l_item_val,'(NULL)'),
      'temp_cnt'  VALUE l_temp_cnt,
      'temp_all'  VALUE l_temp_all,
      'temp_nms'  VALUE NVL(l_temp_nms,'(none)'),
      'aaf_cnt'   VALUE l_aaf_cnt,
      'wff_cnt'   VALUE l_wff_cnt,
      'co_id'     VALUE TO_CHAR(:G_CO_ID),
      'oun_id'    VALUE TO_CHAR(:G_OUN_ID_INS),
      'user_name' VALUE :G_USER_NAME,
      'proc_mess' VALUE l_mess
    ));
    RETURN;
  END IF;

  -- UploadMultipleFilesChat KHÔNG tự COMMIT — bắt buộc commit ở đây vì
  -- msCreateFileMessage chạy ở 1 request/session APEX khác, cần thấy được
  -- row FILES vừa insert ngay.
  COMMIT;

  SELECT file_name INTO l_file_nm FROM FILES WHERE fil_id = l_fil_id;

  HTP.p(JSON_OBJECT(
    'fil_id'    VALUE l_fil_id,
    'file_name' VALUE l_file_nm
  ));
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','''') || '"}');
END;


-- ============================================================
-- 20. msCreateFileMessage
--     Nhận fil_id đã upload xong (từ msUploadAttachment) -> insert
--     CHAT_MESSENGERS -> gắn ngược owner_id/owner_table_name trên FILES ->
--     cập nhật last_msg_preview/last_msg_date -> COMMIT -> broadcast
--     real-time best-effort. KHÔNG tham chiếu bất kỳ page item nào — chỉ
--     nhận NUMBER/VARCHAR2 thường qua x01-x04, nên an toàn, không lặp lại
--     lỗi ORA-01403 của mục 19.
--     x01 = conv_id | x02 = caption (optional) | x03 = reply_to_msg_id
--     (optional) | x04 = fil_id (bắt buộc, lấy từ msUploadAttachment)
--
--     ⚠️ Cần Node.js route mới POST /api/chat/broadcast-message
--     (chat-server/chat.js, sibling repo C:\greensys\chat-server) — route
--     CHỈ phát SSE type:'message' (giống enrichment của /send), KHÔNG ghi DB.
--     Xem code mẫu trong messenger/CLAUDE.md mục "Luồng gửi file thật".
--
--     ⚠️ TODO: xác nhận đúng tên sequence msg_id (giả định MSG_SEQ bên dưới,
--     đổi nếu DDL gốc của CHAT_MESSENGERS dùng tên khác).
-- ============================================================
DECLARE
  l_aus_id    NUMBER;
  l_conv_id   NUMBER         := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_caption   VARCHAR2(4000) := NULLIF(TRIM(apex_application.g_x02), '');
  l_reply_id  NUMBER         := TO_NUMBER(NULLIF(TRIM(apex_application.g_x03), ''));
  l_fil_id    NUMBER(15)     := TO_NUMBER(NULLIF(TRIM(apex_application.g_x04), ''));
  l_member    NUMBER         := 0;
  l_fil_exist NUMBER         := 0;
  l_msg_id    NUMBER;
  l_file_name VARCHAR2(600);   -- đường dẫn (FILES.file_name)
  l_file_disp VARCHAR2(600);   -- tên gốc còn đuôi (FILES.name)
  l_file_ext  VARCHAR2(20);
  l_is_image  BOOLEAN;
  l_preview   VARCHAR2(200);
  l_mess      VARCHAR2(2000);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  IF l_conv_id = 0 THEN
    HTP.p('{"error":"conv_id required"}'); RETURN;
  END IF;
  IF l_fil_id IS NULL THEN
    HTP.p('{"error":"fil_id required"}'); RETURN;
  END IF;

  SELECT COUNT(*) INTO l_member FROM CHAT_PARTICIPANTS
  WHERE conv_id = l_conv_id AND aus_id = l_aus_id;
  IF l_member = 0 THEN
    HTP.p('{"error":"not_member"}'); RETURN;
  END IF;

  SELECT COUNT(*) INTO l_fil_exist FROM FILES WHERE fil_id = l_fil_id;
  IF l_fil_exist = 0 THEN
    HTP.p('{"error":"fil_id_not_found"}'); RETURN;
  END IF;

  -- 1) Insert CHAT_MESSENGERS với fil_id đã có (1 INSERT duy nhất)
  l_msg_id := MSG_SEQ.NEXTVAL;

  INSERT INTO CHAT_MESSENGERS
    (msg_id, conv_id, from_aus_id, body, fil_id, reply_to_msg_id, create_date)
  VALUES
    (l_msg_id, l_conv_id, l_aus_id, l_caption, l_fil_id, l_reply_id, SYSTIMESTAMP);

  -- 2) Gắn ngược owner_id/owner_table_name cho FILES
  UPDATE FILES
  SET    owner_id = l_msg_id, owner_table_name = 'CHAT_MESSENGERS'
  WHERE  fil_id = l_fil_id;

  -- 3) Cập nhật preview hội thoại (để msConvListHtml hiện đúng dòng cuối)
  --    file_name = đường dẫn; name = tên gốc còn đuôi → suy đuôi + hiển thị từ name
  SELECT file_name, name INTO l_file_name, l_file_disp FROM FILES WHERE fil_id = l_fil_id;
  l_file_ext := LOWER(REGEXP_SUBSTR(l_file_disp, '\.([^.]+)$', 1, 1, NULL, 1));
  l_is_image := l_file_ext IN ('jpg','jpeg','png','gif','webp','bmp','svg');
  l_preview  := NVL(l_caption,
                     CASE WHEN l_is_image THEN '[Hình ảnh]'
                          ELSE '[Tệp tin] ' || l_file_disp END);

  UPDATE CHAT_CONVERSATIONS
  SET    last_msg_preview = SUBSTR(l_preview, 1, 200),
         last_msg_date    = SYSTIMESTAMP
  WHERE  conv_id = l_conv_id;

  COMMIT;  -- tin nhắn đã lưu chắc chắn, không phụ thuộc bước broadcast bên dưới

  -- 4) Broadcast real-time (best-effort) — lỗi ở đây KHÔNG rollback tin nhắn
  BEGIN
    DECLARE
      l_conv_type VARCHAR2(10);
      l_doc_type  VARCHAR2(30);
      l_doc_no    VARCHAR2(60);
      l_conv_name VARCHAR2(200);
      l_payload   VARCHAR2(4000);
      l_req       UTL_HTTP.REQ;
      l_resp      UTL_HTTP.RESP;
    BEGIN
      SELECT conv_type, doc_type, doc_no, name
      INTO   l_conv_type, l_doc_type, l_doc_no, l_conv_name
      FROM   CHAT_CONVERSATIONS WHERE conv_id = l_conv_id;

      l_payload := JSON_OBJECT(
        'conv_id'         VALUE l_conv_id,
        'msg_id'          VALUE l_msg_id,
        'aus_id'          VALUE l_aus_id,
        'body'            VALUE l_caption,
        'fil_id'          VALUE l_fil_id,
        'file_name'       VALUE l_file_name,   -- đường dẫn (href)
        'file_disp_name'  VALUE l_file_disp,   -- tên gốc còn đuôi
        'reply_to_msg_id' VALUE l_reply_id,
        'doc_type'        VALUE l_doc_type,
        'doc_no'          VALUE l_doc_no,
        'conv_type'       VALUE l_conv_type,
        'conv_name'       VALUE l_conv_name
        ABSENT ON NULL
      );

      UTL_HTTP.SET_TRANSFER_TIMEOUT(5);
      l_req := UTL_HTTP.BEGIN_REQUEST(
        'https://chattest.erp100.vn/api/chat/broadcast-message', 'POST', 'HTTP/1.1');
      UTL_HTTP.SET_HEADER(l_req, 'Content-Type',  'application/json; charset=utf-8');
      UTL_HTTP.SET_HEADER(l_req, 'Connection',     'close');
      UTL_HTTP.SET_HEADER(l_req, 'Content-Length',
        TO_CHAR(UTL_RAW.LENGTH(UTL_RAW.CAST_TO_RAW(l_payload))));
      UTL_HTTP.WRITE_RAW(l_req, UTL_RAW.CAST_TO_RAW(l_payload));
      l_resp := UTL_HTTP.GET_RESPONSE(l_req);
      UTL_HTTP.END_RESPONSE(l_resp);
    EXCEPTION WHEN OTHERS THEN
      NULL; -- broadcast thất bại không sao, message đã lưu; client khác thấy khi tự refresh
    END;
  END;

  HTP.p(JSON_OBJECT(
    'state'   VALUE 'success',
    'msg_id'  VALUE l_msg_id,
    'fil_id'  VALUE l_fil_id,
    'conv_id' VALUE l_conv_id
  ));
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  l_mess := pkg_mess.get_mess(926, SQLERRM, :G_LANGUAGE);
  HTP.p(JSON_OBJECT('state' VALUE 'error', 'message' VALUE l_mess));
END;


-- ============================================================
-- 21. msUploadFile  ★ LUỒNG GỬI FILE HIỆN HÀNH (thay #19 + #20 + Node /upload-send)
--     Upload TRỰC TIẾP trên page APEX — vì pkg_upload_file nằm trong DB của
--     APEX, KHÔNG nằm trong DB mà Node chat-server kết nối. Gọi package từ
--     callback này là gọi đúng chỗ, không cần grant/DB link/ORDS.
--
--     Cách truyền bytes (né bế tắc temp-files của #19): client đọc File →
--     base64 → cắt chunk ≤ 30.000 ký tự → apex.server.process('msUploadFile',
--     { f01: chunkArray, x01:conv_id, x02:file_name, x03:caption, x04:reply }).
--     APEX nạp chunk vào apex_application.g_f01; callback ghép lại thành CLOB
--     rồi clobbase642blob() → BLOB → UploadFileChat (biến thể nhận BLOB).
--
--     x01 = conv_id (bắt buộc) | x02 = file_name (bắt buộc, tên gốc còn đuôi)
--     x03 = caption (optional) | x04 = reply_to_msg_id (optional)
--     f01 = mảng base64 chunks (bắt buộc)
--
--     co_id/oun_id/user_name lấy thẳng từ global APEX (:G_CO_ID/:G_OUN_ID_INS/
--     :G_USER_NAME) — KHÔNG nhận từ client (an toàn hơn, khớp #19 cũ).
--
--     Real-time: COMMIT xong → UTL_HTTP POST Node /api/chat/broadcast-message
--     (route CHỈ phát SSE, KHÔNG ghi DB) — lỗi broadcast không rollback tin.
-- ============================================================
DECLARE
  l_aus_id    NUMBER;
  l_conv_id   NUMBER         := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_file_name VARCHAR2(600)  := NULLIF(TRIM(apex_application.g_x02), '');
  l_caption   VARCHAR2(4000) := NULLIF(TRIM(apex_application.g_x03), '');
  l_reply_id  NUMBER         := TO_NUMBER(NULLIF(TRIM(apex_application.g_x04), ''));
  l_b64       CLOB;
  l_blob      BLOB;
  l_member    NUMBER         := 0;
  l_fil_id    NUMBER(15);
  l_up_mess   VARCHAR2(2000);
  l_msg_id    NUMBER;
  l_path      VARCHAR2(600);   -- FILES.file_name (đường dẫn href)
  l_disp      VARCHAR2(600);   -- FILES.name (tên gốc còn đuôi)
  l_file_ext  VARCHAR2(20);
  l_is_image  BOOLEAN;
  l_preview   VARCHAR2(200);
  l_mess      VARCHAR2(2000);
  -- Field enrich trả về browser để browser tự gọi Node /broadcast-message
  -- (DB không route tới được Node -> ORA-12535; browser thì tới được).
  l_conv_type VARCHAR2(10);
  l_doc_type  VARCHAR2(30);
  l_doc_no    VARCHAR2(60);
  l_conv_name VARCHAR2(200);
  l_from_name VARCHAR2(200);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  IF l_conv_id = 0 THEN
    HTP.p('{"error":"conv_id required"}'); RETURN;
  END IF;
  IF l_file_name IS NULL THEN
    HTP.p('{"error":"file_name required"}'); RETURN;
  END IF;
  IF apex_application.g_f01.COUNT = 0 THEN
    HTP.p('{"error":"file bytes required"}'); RETURN;
  END IF;

  SELECT COUNT(*) INTO l_member FROM CHAT_PARTICIPANTS
  WHERE conv_id = l_conv_id AND aus_id = l_aus_id;
  IF l_member = 0 THEN
    HTP.p('{"error":"not_member"}'); RETURN;
  END IF;

  -- 1) Ghép base64 chunks → CLOB → BLOB
  DBMS_LOB.CREATETEMPORARY(l_b64, TRUE);
  FOR i IN 1 .. apex_application.g_f01.COUNT LOOP
    DBMS_LOB.WRITEAPPEND(l_b64, LENGTH(apex_application.g_f01(i)), apex_application.g_f01(i));
  END LOOP;
  l_blob := apex_web_service.clobbase642blob(l_b64);
  DBMS_LOB.FREETEMPORARY(l_b64);

  IF l_blob IS NULL OR DBMS_LOB.GETLENGTH(l_blob) = 0 THEN
    HTP.p('{"error":"empty_blob"}'); RETURN;
  END IF;

  -- 2) Upload qua package hệ thống (biến thể nhận BLOB trực tiếp) → fil_id
  pkg_upload_file.UploadFileChat(
    p_blob      => l_blob,
    p_name      => l_file_name,
    p_co_id     => :G_CO_ID,
    p_oun_id    => :G_OUN_ID_INS,
    p_module    => '01',
    p_table     => 'CHAT_MESSENGERS',
    p_user_name => :G_USER_NAME,
    p_id        => NULL,
    p_ffo_id    => NULL,
    p_directory => NULL,
    p_fil_id    => l_fil_id,
    p_error     => l_up_mess);

  IF l_fil_id IS NULL THEN
    ROLLBACK;
    HTP.p(JSON_OBJECT('error' VALUE NVL(l_up_mess,'upload_failed')));
    RETURN;
  END IF;

  -- 3) INSERT CHAT_MESSENGERS với fil_id (1 INSERT, giống #20)
  l_msg_id := MSG_SEQ.NEXTVAL;
  INSERT INTO CHAT_MESSENGERS
    (msg_id, conv_id, from_aus_id, body, fil_id, reply_to_msg_id, create_date)
  VALUES
    (l_msg_id, l_conv_id, l_aus_id, l_caption, l_fil_id, l_reply_id, SYSTIMESTAMP);

  -- 4) Gắn ngược owner cho FILES (tham chiếu ngược, không phải nguồn query chính)
  UPDATE FILES
  SET    owner_id = l_msg_id, owner_table_name = 'CHAT_MESSENGERS'
  WHERE  fil_id = l_fil_id;

  -- 5) Preview hội thoại (name = tên gốc còn đuôi → suy đuôi phân biệt ảnh/file)
  SELECT file_name, name INTO l_path, l_disp FROM FILES WHERE fil_id = l_fil_id;
  l_file_ext := LOWER(REGEXP_SUBSTR(l_disp, '\.([^.]+)$', 1, 1, NULL, 1));
  l_is_image := l_file_ext IN ('jpg','jpeg','png','gif','webp','bmp','svg');
  l_preview  := NVL(l_caption,
                     CASE WHEN l_is_image THEN '[Hình ảnh]'
                          ELSE '[Tệp tin] ' || l_disp END);

  UPDATE CHAT_CONVERSATIONS
  SET    last_msg_preview = SUBSTR(l_preview, 1, 200),
         last_msg_date    = SYSTIMESTAMP
  WHERE  conv_id = l_conv_id;

  UPDATE CHAT_PARTICIPANTS SET last_read_msg_id = l_msg_id
  WHERE  conv_id = l_conv_id AND aus_id = l_aus_id;

  COMMIT;  -- tin nhắn đã lưu chắc chắn, không phụ thuộc bước broadcast

  -- 6) Nạp field enrich để TRẢ VỀ browser. KHÔNG tự UTL_HTTP sang Node ở đây:
  --    máy DB không route tới được Node (ORA-12535 timeout). Browser của user
  --    nhận response này rồi tự gọi Node /broadcast-message (browser tới được
  --    Node — chính là đường mà /send text vẫn đang dùng real-time).
  BEGIN
    SELECT conv_type, doc_type, doc_no, name
    INTO   l_conv_type, l_doc_type, l_doc_no, l_conv_name
    FROM   CHAT_CONVERSATIONS WHERE conv_id = l_conv_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
  END;
  BEGIN
    SELECT REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','')
    INTO   l_from_name
    FROM   APP_USERS u JOIN EMPLOYEES e ON e.emp_id = u.emp_id
    WHERE  u.aus_id = l_aus_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN l_from_name := 'Unknown';
  END;

  HTP.p(JSON_OBJECT(
    'state'          VALUE 'success',
    'msg_id'         VALUE l_msg_id,
    'fil_id'         VALUE l_fil_id,
    'conv_id'        VALUE l_conv_id,
    'aus_id'         VALUE l_aus_id,
    'from_name'      VALUE l_from_name,
    'body'           VALUE l_caption,
    'file_name'      VALUE l_path,
    'file_disp_name' VALUE l_disp,
    'reply_to_msg_id' VALUE l_reply_id,
    'doc_type'       VALUE l_doc_type,
    'doc_no'         VALUE l_doc_no,
    'conv_type'      VALUE l_conv_type,
    'conv_name'      VALUE l_conv_name
    ABSENT ON NULL
  ));
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  HTP.p(JSON_OBJECT('error' VALUE REPLACE(SQLERRM,'"','''')));
END;


-- ============================================================
-- SCHEMA — cột fil_id cho tin nhắn file/ảnh (chạy 1 lần, TRƯỚC khi
-- deploy msSendFileAttachment (mục 19) và msMsgThreadHtml bên trên
-- đã có JOIN sẵn FILES)
-- ============================================================
--   Thay thế cơ chế owner_id/owner_table_name làm nguồn sự thật chính
--   (polymorphic association, không có FK thật) bằng FK trực tiếp trên
--   CHAT_MESSENGERS, trỏ tới bảng FILES có sẵn của hệ thống. owner_id/
--   owner_table_name vẫn được gán (mục 19, bước 3) cho mục đích tham
--   chiếu ngược, nhưng fil_id trên CHAT_MESSENGERS mới là cột dùng để
--   query/JOIN (msMsgThreadHtml). Luồng gửi file: upload TRƯỚC (p_id=NULL,
--   callback trả fil_id) -> 1 INSERT duy nhất vào CHAT_MESSENGERS đã có
--   sẵn fil_id -> update owner_id/owner_table_name ngược lại trên FILES
--   (xem msSendFileAttachment, mục 19, và msSendFileMessage() trong
--   messenger.fgvd.js).
--
--   ALTER TABLE CHAT_MESSENGERS ADD fil_id NUMBER(15);
--
--   ALTER TABLE CHAT_MESSENGERS
--     ADD CONSTRAINT fk_chat_msg_fil
--     FOREIGN KEY (fil_id) REFERENCES FILES(fil_id);
--     -- KHÔNG dùng ON DELETE SET NULL (sẽ làm tin nhắn "biến hình" ngầm
--     -- từ file thành text). FILES không có cột soft-delete sẵn — mặc định
--     -- NO ACTION nghĩa là Oracle sẽ CHẶN xóa file nếu còn tin nhắn tham
--     -- chiếu (ORA-02292) — đây là hành vi an toàn chấp nhận được, không
--     -- bắt buộc phải thêm cột is_deleted ngay.
--
--   CREATE INDEX ix_chat_msg_fil_id ON CHAT_MESSENGERS(fil_id);
--
--   msMsgThreadHtml (mục 4 phía trên) ĐÃ cập nhật JOIN FILES theo
--   CHAT_MESSENGERS.fil_id = FILES.fil_id, render .img-card (ảnh) hoặc
--   .file-card (file khác). Phân biệt 2 cột FILES:
--     - FILES.file_name = đường dẫn tương đối đầy đủ → dùng THẲNG làm href/src
--       (KHÔNG ghép tiền tố — l_file_url_prefix đã bỏ).
--     - FILES.name = tên gốc còn đuôi → suy đuôi (ảnh vs file) + hiển thị tên.


-- ============================================================
-- 22. msAddMembers  ★ Thêm thành viên vào nhóm sẵn có (nút "Thêm TV" right panel)
--     x01 = conv_id, x02 = JSON mảng aus_id, vd "[12,34]"
--     Chèn participant chưa có vào CHAT_PARTICIPANTS. Người gọi phải là thành
--     viên của hội thoại. KHÔNG cần DDL (bảng đã có sẵn). Real-time cho TV mới:
--     deliverToConv (Node) đọc danh sách thành viên lúc gửi nên tin kế tiếp họ
--     nhận được ngay; muốn họ thấy hội thoại tức thì có thể gửi 1 tin hệ thống.
-- ============================================================
DECLARE
  l_aus_id   NUMBER;
  l_conv_id  NUMBER         := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_members  VARCHAR2(4000) := NVL(NULLIF(TRIM(apex_application.g_x02),''), '[]');
  l_member   NUMBER         := 0;
  l_added    NUMBER         := 0;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  IF l_conv_id = 0 THEN
    HTP.p('{"error":"conv_id required"}'); RETURN;
  END IF;

  -- Người gọi phải là thành viên hội thoại mới được thêm người
  SELECT COUNT(*) INTO l_member FROM CHAT_PARTICIPANTS
  WHERE conv_id = l_conv_id AND aus_id = l_aus_id;
  IF l_member = 0 THEN
    HTP.p('{"error":"not_member"}'); RETURN;
  END IF;

  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin, is_pinned, is_hidden)
  SELECT l_conv_id, jt.aid, 0, 0, 0
  FROM   JSON_TABLE(l_members, '$[*]' COLUMNS (aid NUMBER PATH '$')) jt
  WHERE  jt.aid IS NOT NULL
    AND  NOT EXISTS (SELECT 1 FROM CHAT_PARTICIPANTS p
                     WHERE p.conv_id = l_conv_id AND p.aus_id = jt.aid);
  l_added := SQL%ROWCOUNT;
  COMMIT;

  HTP.p(JSON_OBJECT('state' VALUE 'success', 'added' VALUE l_added));
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  HTP.p(JSON_OBJECT('error' VALUE REPLACE(SQLERRM,'"','''')));
END;


-- ============================================================
-- 23. msSearchMsgsHtml  ★ Tìm kiếm tin nhắn trong 1 hội thoại (nút "Tìm kiếm")
--     x01 = conv_id, x02 = từ khóa. Trả HTML danh sách kết quả (tối đa 40 tin
--     mới nhất khớp). Mỗi dòng onclick="msJumpFromSearch(msg_id)". Bỏ tin đã xóa.
--     Highlight bằng INSTR (literal, không regex) -> an toàn với ký tự đặc biệt.
-- ============================================================
DECLARE
  l_aus_id   NUMBER;
  l_conv_id  NUMBER         := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_q        VARCHAR2(400)  := TRIM(apex_application.g_x02);
  l_member   NUMBER         := 0;
  l_pos      NUMBER;
  l_body     VARCHAR2(4000);
  l_html     VARCHAR2(4000);
  l_qlen     NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN;
  END;

  IF l_conv_id = 0 OR l_q IS NULL THEN RETURN; END IF;

  SELECT COUNT(*) INTO l_member FROM CHAT_PARTICIPANTS
  WHERE conv_id = l_conv_id AND aus_id = l_aus_id;
  IF l_member = 0 THEN RETURN; END IF;

  l_qlen := LENGTH(l_q);

  FOR r IN (
    SELECT m.msg_id,
           REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') AS from_name,
           REGEXP_REPLACE(m.body,'[[:cntrl:]]',' ')                    AS body,
           TO_CHAR(m.create_date,'DD/MM HH24:MI')                      AS msg_dt
    FROM   CHAT_MESSENGERS m
    JOIN   APP_USERS u ON u.aus_id = m.from_aus_id
    JOIN   EMPLOYEES e ON e.emp_id = u.emp_id
    WHERE  m.conv_id = l_conv_id
      AND  m.delete_date IS NULL
      AND  m.body IS NOT NULL
      AND  LOWER(m.body) LIKE '%' || LOWER(l_q) || '%'
    ORDER  BY m.msg_id DESC
    FETCH FIRST 40 ROWS ONLY
  ) LOOP
    l_body := SUBSTR(r.body, 1, 300);
    l_pos  := INSTR(LOWER(l_body), LOWER(l_q));
    IF l_pos > 0 THEN
      l_html := HTF.ESCAPE_SC(SUBSTR(l_body, 1, l_pos - 1))
             || '<mark>' || HTF.ESCAPE_SC(SUBSTR(l_body, l_pos, l_qlen)) || '</mark>'
             || HTF.ESCAPE_SC(SUBSTR(l_body, l_pos + l_qlen));
    ELSE
      l_html := HTF.ESCAPE_SC(l_body);
    END IF;

    HTP.p('<button type="button" class="ms-cs-item" onclick="msJumpFromSearch(' || r.msg_id || ')">');
    HTP.p('  <div class="ms-cs-item-top">');
    HTP.p('    <span class="ms-cs-item-name">' || HTF.ESCAPE_SC(r.from_name) || '</span>');
    HTP.p('    <span class="ms-cs-item-date">' || r.msg_dt || '</span>');
    HTP.p('  </div>');
    HTP.p('  <div class="ms-cs-item-body">' || l_html || '</div>');
    HTP.p('</button>');
  END LOOP;
END;
