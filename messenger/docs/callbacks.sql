-- ============================================================
-- MESSENGER FULLSCREEN — APEX Ajax Callbacks
-- Tất cả tạo là PAGE-LEVEL AJAX CALLBACK trên messenger page
-- Page → Processing → Ajax Callback
--
-- Danh sách callbacks:
--   1. msGetCurrentUser   — thông tin user đang login
--   2. msConvListHtml     — danh sách hội thoại (HTML)
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

  HTP.p(JSON_OBJECT(
    'aus_id'    VALUE l_aus_id,
    'username'  VALUE :APP_USER,
    'full_name' VALUE l_name,
    'img'       VALUE l_img
    ABSENT ON NULL
  ));
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 2. msConvListHtml
--    Trả HTML danh sách hội thoại của user (không filter theo doc).
--    x01=filter (ALL/UNREAD/GROUP) | x02=search text
-- ============================================================
DECLARE
  l_aus_id        NUMBER;
  l_filter        VARCHAR2(20)  := NVL(UPPER(TRIM(apex_application.g_x01)), 'ALL');
  l_search        VARCHAR2(200) := LOWER(TRIM(apex_application.g_x02));
  l_online_cutoff TIMESTAMP     := SYSTIMESTAMP - INTERVAL '35' SECOND;
  l_last_type     VARCHAR2(20)  := '~~INIT~~';
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
        c.last_msg_date,
        c.last_msg_preview,
        p.last_read_msg_id,
        -- Display name
        CASE c.conv_type
          WHEN 'CHANNEL' THEN NVL(c.name,'(Không tên)')
          ELSE (
            SELECT REGEXP_REPLACE(NVL(e2.full_name,'Unknown'),'[[:cntrl:]]','')
            FROM   CHAT_PARTICIPANTS p2
            JOIN   APP_USERS u2 ON u2.aus_id = p2.aus_id
            JOIN   EMPLOYEES e2 ON e2.emp_id = u2.emp_id
            WHERE  p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
            FETCH FIRST 1 ROW ONLY
          )
        END AS display_name,
        -- Partner aus_id (DM only)
        CASE c.conv_type
          WHEN 'DM' THEN (
            SELECT p2.aus_id FROM CHAT_PARTICIPANTS p2
            WHERE  p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
            FETCH FIRST 1 ROW ONLY
          )
          ELSE NULL
        END AS partner_aus_id,
        -- Partner avatar image (DM only) — scalar subquery tránh ORA-01799
        CASE c.conv_type
          WHEN 'DM' THEN (
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
        ) AS unread_count
      FROM CHAT_CONVERSATIONS c
      JOIN CHAT_PARTICIPANTS  p ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
      WHERE (l_filter != 'UNREAD' OR
             (SELECT COUNT(*) FROM CHAT_MESSENGERS m
              WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
                AND m.msg_id > NVL(p.last_read_msg_id,0)) > 0)
        AND (l_filter != 'GROUP' OR c.conv_type = 'CHANNEL')
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
    ORDER  BY r.last_msg_date DESC NULLS LAST
  ) LOOP
    DECLARE
      l_name    VARCHAR2(200) := REGEXP_REPLACE(NVL(conv.display_name,'?'),'[[:cntrl:]]','');
      l_initl   VARCHAR2(4)   := UPPER(SUBSTR(REGEXP_SUBSTR(l_name,'\S+$'),1,1));
      l_hue     VARCHAR2(10)  := TO_CHAR(MOD(NVL(conv.partner_aus_id, conv.conv_id)*47, 360));
      l_unread  BOOLEAN       := conv.unread_count > 0;
      l_cls     VARCHAR2(200);
    BEGIN
      IF NVL(l_initl,'') = '' THEN l_initl := '?'; END IF;

      -- Section label
      IF conv.conv_type != l_last_type THEN
        l_last_type := conv.conv_type;
        HTP.p('<div class="ms-section-label">'
              || CASE conv.conv_type WHEN 'DM' THEN 'Tin nhắn trực tiếp' ELSE 'Nhóm' END
              || '</div>');
      END IF;

      -- Conv item classes
      l_cls := 'ms-conv-item'
             || CASE WHEN l_unread          THEN ' unread' END
             || CASE WHEN conv.conv_type = 'CHANNEL' THEN ' group' END;

      HTP.p('<button type="button" class="' || l_cls || '"'
            || ' data-conv-id="'   || conv.conv_id   || '"'
            || ' data-conv-type="' || conv.conv_type || '"'
            || ' onclick="msSelectConv(' || conv.conv_id
            || ',''' || conv.conv_type || ''')">');

      -- Avatar
      HTP.p('  <div class="ms-ci-av' || CASE WHEN conv.conv_type='CHANNEL' THEN ' group' END || '"'
            || ' style="background:hsl(' || l_hue || ',55%,52%)">');
      IF conv.conv_type = 'CHANNEL' THEN
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
      HTP.p('      <span class="ms-ci-time">' || NVL(conv.display_time,'') || '</span>');
      HTP.p('    </div>');
      HTP.p('    <div class="ms-ci-row2">');
      HTP.p('      <span class="ms-ci-preview">'
            || HTF.ESCAPE_SC(SUBSTR(NVL(conv.last_msg_preview,''),1,55)) || '</span>');
      IF l_unread THEN
        HTP.p('      <span class="ms-ci-badge">' || conv.unread_count || '</span>');
      END IF;
      HTP.p('    </div>');
      HTP.p('  </div>');

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

  SELECT c.conv_type,
         CASE c.conv_type
           WHEN 'CHANNEL' THEN NVL(c.name,'(Không tên)')
           ELSE (SELECT REGEXP_REPLACE(NVL(e2.full_name,'Unknown'),'[[:cntrl:]]','')
                 FROM CHAT_PARTICIPANTS p2
                 JOIN APP_USERS u2 ON u2.aus_id = p2.aus_id
                 JOIN EMPLOYEES e2 ON e2.emp_id = u2.emp_id
                 WHERE p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
                 FETCH FIRST 1 ROW ONLY)
         END
  INTO l_type, l_name
  FROM CHAT_CONVERSATIONS c WHERE c.conv_id = l_conv_id;

  SELECT COUNT(*) INTO l_member_count FROM CHAT_PARTICIPANTS WHERE conv_id = l_conv_id;

  IF l_type = 'DM' THEN
    DECLARE l_partner_id NUMBER; l_partner_emp NUMBER;
    BEGIN
      SELECT p2.aus_id INTO l_partner_id FROM CHAT_PARTICIPANTS p2
      WHERE p2.conv_id = l_conv_id AND p2.aus_id != l_aus_id FETCH FIRST 1 ROW ONLY;

      SELECT CASE WHEN last_seen >= l_online_cutoff THEN 1 ELSE 0 END
      INTO l_online FROM CHAT_USER_ONLINE WHERE aus_id = l_partner_id;

      SELECT vf.v_file_name INTO l_img
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
  l_conv_id  NUMBER       := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_aus_id   NUMBER;
  l_last_day DATE         := NULL;
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
        TO_CHAR(m.create_date,'HH24:MI') AS msg_time,
        CASE WHEN qm.delete_date IS NOT NULL THEN '[Tin nhắn đã bị xóa]' ELSE qm.body END AS reply_body,
        REGEXP_REPLACE(NVL(qe.full_name,''),'[[:cntrl:]]','') AS reply_from_name
      FROM   CHAT_MESSENGERS m
      JOIN   APP_USERS       u  ON u.aus_id  = m.from_aus_id
      JOIN   EMPLOYEES       e  ON e.emp_id  = u.emp_id
      LEFT JOIN CHAT_MESSENGERS qm ON qm.msg_id = m.reply_to_msg_id
      LEFT JOIN APP_USERS    qu  ON qu.aus_id = qm.from_aus_id
      LEFT JOIN EMPLOYEES    qe  ON qe.emp_id = qu.emp_id
      WHERE  m.conv_id = l_conv_id
      ORDER  BY m.msg_id ASC
      FETCH FIRST 50 ROWS ONLY
    )
    SELECT mr.*, vf.v_file_name AS sender_img
    FROM   msg_raw mr
    LEFT JOIN v_employees_v6 vf ON vf.emp_id = mr.emp_id
  ) LOOP
    -- Date divider
    IF l_last_day IS NULL OR msg.msg_day > l_last_day THEN
      l_last_day := msg.msg_day;
      HTP.p('<div class="ms-day-divider"><span>' || TO_CHAR(msg.msg_day,'DD/MM/YYYY') || '</span></div>');
    END IF;

    DECLARE
      l_mine     BOOLEAN      := (msg.from_aus_id = l_aus_id);
      l_cls      VARCHAR2(60) := 'ms-msg-row' || CASE WHEN l_mine THEN ' mine' END;
      l_av       VARCHAR2(4)  := UPPER(SUBSTR(REGEXP_SUBSTR(msg.from_name,'\S+$'),1,1));
      l_hue      VARCHAR2(10) := TO_CHAR(MOD(msg.from_aus_id * 47, 360));
      l_body_esc VARCHAR2(32767);
    BEGIN
      IF NVL(l_av,'') = '' THEN l_av := '?'; END IF;

      HTP.p('<div class="' || l_cls || '" data-msg-id="' || msg.msg_id || '">');

      -- Avatar
      IF l_mine THEN
        HTP.p('  <div class="ms-msg-av hidden"></div>');
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

      -- Meta (sender name + time)
      HTP.p('    <div class="ms-msg-meta">');
      IF NOT l_mine THEN
        HTP.p('      <span class="ms-msg-meta-name">' || HTF.ESCAPE_SC(msg.from_name) || '</span>');
      END IF;
      HTP.p('      <span>' || msg.msg_time || '</span>');
      HTP.p('    </div>');

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
        l_body_esc := REPLACE(REPLACE(
          REPLACE(REPLACE(HTF.ESCAPE_SC(NVL(msg.body,'')), '&#38;', '&amp;'),
          '&#60;', '&lt;'), CHR(13), ''), CHR(10), '<br>');
        HTP.p('    <div class="ms-msg-bubble">' || l_body_esc || '</div>');
      END IF;

      -- Hover: reply button
      IF msg.delete_date IS NULL THEN
        HTP.p('    <div class="ms-msg-hover-actions">');
        HTP.p('      <button type="button" class="ms-msg-hover-btn" title="Trả lời"'
              || ' data-reply-id="'   || msg.msg_id || '"'
              || ' data-reply-name="' || HTF.ESCAPE_SC(msg.from_name) || '"'
              || ' data-reply-body="' || REPLACE(SUBSTR(NVL(msg.body,''),1,100),'"','&quot;') || '">'
              || '<i class="fa fa-reply"></i></button>');
        HTP.p('    </div>');
      END IF;

      HTP.p('  </div>');
      HTP.p('</div>');
    END;
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

  -- ── DM: Profile Card ─────────────────────────────────────────
  IF l_conv_type = 'DM' THEN
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
    HTP.p('  <div style="width:64px;height:64px;border-radius:50%;'
          || 'background:hsl(' || l_partner_hue || ',55%,52%);'
          || 'color:#fff;display:flex;align-items:center;justify-content:center;'
          || 'font-weight:700;font-size:22px;position:relative;overflow:hidden;'
          || 'margin-bottom:12px;flex-shrink:0">');
    IF l_partner_img IS NOT NULL THEN
      HTP.p('<img src="' || HTF.ESCAPE_SC(l_partner_img) || '"'
            || ' style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%"'
            || ' onerror="this.remove()">');
    END IF;
    HTP.p(l_partner_av);
    -- Presence dot
    HTP.p('    <span style="position:absolute;bottom:3px;right:3px;width:12px;height:12px;'
          || 'border-radius:50%;border:2.5px solid #FAFAFA;'
          || 'background:' || CASE WHEN l_partner_pres='online' THEN '#22C55E' ELSE '#CBD5E1' END || '"></span>');
    HTP.p('  </div>');

    -- Tên
    HTP.p('  <div style="font-weight:700;font-size:15px;color:#0F172A;text-align:center;margin-bottom:4px">'
          || HTF.ESCAPE_SC(l_partner_name) || '</div>');

    -- Trạng thái online
    HTP.p('  <div style="display:flex;align-items:center;gap:5px;font-size:12px;'
          || CASE WHEN l_partner_pres='online' THEN 'color:#16A34A' ELSE 'color:#94A3B8' END || '">');
    HTP.p('    <span style="width:6px;height:6px;border-radius:50%;background:'
          || CASE WHEN l_partner_pres='online' THEN '#22C55E' ELSE '#CBD5E1' END
          || ';display:inline-block"></span>');
    HTP.p('    ' || CASE WHEN l_partner_pres='online' THEN 'Đang hoạt động' ELSE 'Không hoạt động' END);
    HTP.p('  </div>');

    -- Phòng ban (nếu có)
    IF l_partner_dept IS NOT NULL AND l_partner_dept != '' THEN
      HTP.p('  <div style="margin-top:6px;font-size:12px;color:#64748B">'
            || HTF.ESCAPE_SC(l_partner_dept) || '</div>');
    END IF;

    -- Action buttons
    HTP.p('  <div class="ms-rp-actions" style="margin-top:16px;">');
    -- Tắt thông báo
    HTP.p('    <button type="button" class="ms-rp-action-btn" title="Tắt thông báo">');
    HTP.p('      <div class="ms-rp-action-icon">');
    HTP.p('        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>');
    HTP.p('      </div>');
    HTP.p('      <span class="ms-rp-action-label">Thông báo</span>');
    HTP.p('    </button>');
    -- Tìm kiếm
    HTP.p('    <button type="button" class="ms-rp-action-btn" title="Tìm kiếm tin nhắn">');
    HTP.p('      <div class="ms-rp-action-icon">');
    HTP.p('        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>');
    HTP.p('      </div>');
    HTP.p('      <span class="ms-rp-action-label">Tìm kiếm</span>');
    HTP.p('    </button>');
    -- Thêm (Khác)
    HTP.p('    <button type="button" class="ms-rp-action-btn" title="Thêm tùy chọn">');
    HTP.p('      <div class="ms-rp-action-icon">');
    HTP.p('        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/></svg>');
    HTP.p('      </div>');
    HTP.p('      <span class="ms-rp-action-label">Khác</span>');
    HTP.p('    </button>');
    HTP.p('  </div>');

    HTP.p('</div>');

    -- Section Thông tin liên lạc
    HTP.p('<div style="border-top:1px solid #F1F5F9;padding:4px 0;">');
    HTP.p('  <div class="ms-info-section-title">Thông tin liên lạc</div>');

    -- Chức vụ
    IF l_partner_pos IS NOT NULL AND l_partner_pos != '' THEN
      HTP.p('  <div style="display:flex;align-items:center;gap:10px;padding:7px 16px;">');
      HTP.p('    <div style="width:30px;height:30px;border-radius:8px;background:#F1F5F9;'
            || 'display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#475569">');
      HTP.p('      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            || '<rect x="2" y="7" width="20" height="14" rx="2"/>'
            || '<path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/></svg>');
      HTP.p('    </div>');
      HTP.p('    <div style="min-width:0">');
      HTP.p('      <div style="font-size:10.5px;color:#94A3B8">Chức vụ</div>');
      HTP.p('      <div style="font-size:12.5px;color:#334155;font-weight:500">'
            || HTF.ESCAPE_SC(l_partner_pos) || '</div>');
      HTP.p('    </div>');
      HTP.p('  </div>');
    END IF;

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

  -- ── CHANNEL: Group Header + Member List ──────────────────────
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
            || 'font-weight:700;font-size:22px;margin-bottom:12px;flex-shrink:0">');
      HTP.p('    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
            || '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>'
            || '<path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>');
      HTP.p('  </div>');
      HTP.p('  <div style="font-weight:700;font-size:15px;color:#0F172A;text-align:center;margin-bottom:4px">'
            || HTF.ESCAPE_SC(l_conv_name) || '</div>');
      HTP.p('  <div style="font-size:12px;color:#94A3B8">' || l_member_count || ' thành viên</div>');

      -- Action buttons nhóm
      HTP.p('  <div class="ms-rp-actions" style="margin-top:16px;width:100%">');
      -- Thêm thành viên
      HTP.p('    <button type="button" class="ms-rp-action-btn" onclick="msOpenCompose()" title="Thêm thành viên">');
      HTP.p('      <div class="ms-rp-action-icon"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="8.5" cy="7" r="4"/><line x1="20" y1="8" x2="20" y2="14"/><line x1="23" y1="11" x2="17" y2="11"/></svg></div>');
      HTP.p('      <span class="ms-rp-action-label">Thêm TV</span>');
      HTP.p('    </button>');
      -- Tìm kiếm
      HTP.p('    <button type="button" class="ms-rp-action-btn" title="Tìm kiếm tin nhắn">');
      HTP.p('      <div class="ms-rp-action-icon"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg></div>');
      HTP.p('      <span class="ms-rp-action-label">Tìm kiếm</span>');
      HTP.p('    </button>');
      -- Thông báo
      HTP.p('    <button type="button" class="ms-rp-action-btn" title="Tắt thông báo">');
      HTP.p('      <div class="ms-rp-action-icon"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg></div>');
      HTP.p('      <span class="ms-rp-action-label">Thông báo</span>');
      HTP.p('    </button>');
      -- Khác
      HTP.p('    <button type="button" class="ms-rp-action-btn" title="Thêm tùy chọn">');
      HTP.p('      <div class="ms-rp-action-icon"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/></svg></div>');
      HTP.p('      <span class="ms-rp-action-label">Khác</span>');
      HTP.p('    </button>');
      HTP.p('  </div>');

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
