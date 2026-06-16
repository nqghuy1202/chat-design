-- ============================================================
-- DOC CHAT MODAL — Native APEX Page Callbacks (HTML-returning)
-- Tất cả là PAGE-LEVEL AJAX CALLBACK trên page 10022710201
-- Khác với doc-chat-callbacks.sql (trả JSON), các callback
-- này trả HTML trực tiếp để JS dùng innerHTML swap.
-- ============================================================
-- Gọi từ doc-chat-page.js: dataType: 'text'
-- apex.server.process(proc, params, { pageId: 10022710201, dataType: 'text', success: fn })
--
-- Callback mới (thay thế docChatConversations/Messages/Members):
--   dcConvListHtml   x01=doc_type | x02=doc_no | x03=filter | x04=search
--   dcMsgThreadHtml  x01=conv_id  | x02=search_query
--   dcInfoHtml       x01=conv_id
--   dcContactsHtml   (không tham số — trả danh sách users để tạo cuộc trò chuyện)
--
-- Giữ nguyên (trả JSON, không đổi):
--   docChatCreate / docChatSend / docChatRead / docChatTyping
-- ============================================================


-- ============================================================
-- 1. dcConvListHtml
--    Trả HTML danh sách hội thoại (convo-pane nội dung)
--    x01=doc_type | x02=doc_no | x03=filter(ALL/UNREAD/CHANNEL) | x04=search
-- ============================================================
DECLARE
  l_aus_id        NUMBER;
  l_doc_type      VARCHAR2(50)  := TRIM(apex_application.g_x01);
  l_doc_no        VARCHAR2(100) := TRIM(apex_application.g_x02);
  l_filter        VARCHAR2(20)  := NVL(UPPER(TRIM(apex_application.g_x03)), 'ALL');
  l_search        VARCHAR2(200) := LOWER(TRIM(apex_application.g_x04));
  l_online_cutoff TIMESTAMP     := SYSTIMESTAMP - INTERVAL '35' SECOND;
  l_ch_count      NUMBER        := 0;
  l_dm_count      NUMBER        := 0;
  l_total_count   NUMBER        := 0;
  l_dummy         NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('<div class="dc-err">Phiên đăng nhập hết hạn</div>'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('<div class="dc-err">Không tìm thấy user</div>'); RETURN;
  END;

  IF l_doc_type IS NULL OR l_doc_no IS NULL THEN
    HTP.p('<div class="dc-err">Thiếu doc_type/doc_no</div>'); RETURN;
  END IF;

  -- Pre-count mỗi section để hiển thị số lượng trong header
  IF l_filter IN ('ALL', 'CHANNEL', 'UNREAD') THEN
    SELECT COUNT(*) INTO l_ch_count
    FROM CHAT_CONVERSATIONS c
    JOIN CHAT_PARTICIPANTS p ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
    WHERE c.doc_type = l_doc_type AND c.doc_no = l_doc_no AND c.conv_type = 'CHANNEL'
      AND (l_filter != 'UNREAD' OR
           (SELECT COUNT(*) FROM CHAT_MESSENGERS m
            WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
            AND m.msg_id > NVL(p.last_read_msg_id, 0)) > 0)
      AND (l_search IS NULL
           OR LOWER(NVL(c.name,'')) LIKE '%' || l_search || '%'
           OR LOWER(NVL(c.last_msg_preview,'')) LIKE '%' || l_search || '%'
           OR EXISTS (
                SELECT 1 FROM CHAT_PARTICIPANTS ps
                JOIN   APP_USERS  us ON us.aus_id = ps.aus_id
                JOIN   EMPLOYEES  es ON es.emp_id = us.emp_id
                WHERE  ps.conv_id = c.conv_id
                  AND  ps.aus_id != l_aus_id
                  AND (LOWER(NVL(es.full_name,'')) LIKE '%' || l_search || '%'
                    OR LOWER(NVL(us.user_name,'')) LIKE '%' || l_search || '%')));
  END IF;

  IF l_filter IN ('ALL', 'UNREAD') THEN
    SELECT COUNT(*) INTO l_dm_count
    FROM CHAT_CONVERSATIONS c
    JOIN CHAT_PARTICIPANTS p ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
    WHERE c.doc_type = l_doc_type AND c.doc_no = l_doc_no AND c.conv_type = 'DM'
      AND (l_filter != 'UNREAD' OR
           (SELECT COUNT(*) FROM CHAT_MESSENGERS m
            WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
            AND m.msg_id > NVL(p.last_read_msg_id, 0)) > 0)
      AND (l_search IS NULL
           OR LOWER(NVL(c.last_msg_preview,'')) LIKE '%' || l_search || '%'
           OR EXISTS (
                SELECT 1 FROM CHAT_PARTICIPANTS ps
                JOIN   APP_USERS  us ON us.aus_id = ps.aus_id
                JOIN   EMPLOYEES  es ON es.emp_id = us.emp_id
                WHERE  ps.conv_id = c.conv_id
                  AND  ps.aus_id != l_aus_id
                  AND (LOWER(NVL(es.full_name,'')) LIKE '%' || l_search || '%'
                    OR LOWER(NVL(us.user_name,'')) LIKE '%' || l_search || '%')));
  END IF;

  -- Total count (always ALL, no filter) for the badge on "Tất cả"
  SELECT COUNT(*) INTO l_total_count
  FROM CHAT_CONVERSATIONS c
  JOIN CHAT_PARTICIPANTS p ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
  WHERE c.doc_type = l_doc_type AND c.doc_no = l_doc_no;

  -- Toolbar: search + lp-filter-row
  HTP.p('<div class="convo-toolbar">');
  HTP.p('  <label class="convo-search">');
  HTP.p('    <span class="fa fa-search" style="color:var(--text-4);font-size:13px"></span>');
  HTP.p('    <input type="text" id="dc-conv-search" placeholder="Tìm hội thoại, tin nhắn..." value="'
        || HTF.ESCAPE_SC(NVL(apex_application.g_x04,'')) || '"/>');
  HTP.p('  </label>');
  HTP.p('  <div class="lp-filter-row">');
  HTP.p('    <button type="button" class="lp-filter-chip' || CASE WHEN l_filter='ALL' THEN ' active' END || '" data-filter="ALL">');
  HTP.p('      Tất cả');
  IF l_total_count > 0 THEN
    HTP.p('      <span class="lp-chip-count">' || l_total_count || '</span>');
  END IF;
  HTP.p('      <span class="lp-chip-caret fa fa-chevron-down"></span>');
  HTP.p('    </button>');
  HTP.p('    <button type="button" class="lp-filter-chip' || CASE WHEN l_filter='UNREAD' THEN ' active' END || '" data-filter="UNREAD">');
  HTP.p('      <span class="fa fa-circle" style="font-size:6px"></span> Chưa đọc');
  HTP.p('    </button>');
  HTP.p('    <button type="button" class="lp-filter-chip' || CASE WHEN l_filter='CHANNEL' THEN ' active' END || '" data-filter="CHANNEL">');
  HTP.p('      <span class="fa fa-users" style="font-size:11px"></span> Nhóm');
  HTP.p('    </button>');
  HTP.p('  </div>');
  HTP.p('</div>');

  -- Doc context bar
  HTP.p('<div class="dc-ctx-bar">');
  HTP.p('  <span class="fa fa-hashtag" style="font-size:11px"></span>');
  HTP.p('  Đang xem: <b style="color:var(--primary-700)">'
        || HTF.ESCAPE_SC(l_doc_type || '-' || l_doc_no) || '</b>');
  HTP.p('</div>');

  HTP.p('<div class="convo-list" id="dc-conv-list-inner">');

  IF l_ch_count + l_dm_count = 0 THEN
    HTP.p('<div style="text-align:center;color:var(--text-3);padding:32px 16px;font-size:13px">');
    IF l_filter = 'UNREAD' THEN
      HTP.p('  Không có tin nhắn chưa đọc.');
    ELSE
      HTP.p('  Chưa có hội thoại nào.<br>Nhấn "Nhắn tin" hoặc "Tạo nhóm" để bắt đầu.');
    END IF;
    HTP.p('</div>');
  ELSE

    -- ── CHANNEL SECTION ──────────────────────────────────────────
    IF l_ch_count > 0 THEN
      HTP.p('<div class="convo-section-label">NHÓM TRAO ĐỔI &middot; ' || l_ch_count || '</div>');
      FOR conv IN (
        SELECT c.conv_id,
               NVL(c.name,'(Không tên)') AS display_name,
               c.last_msg_preview,
               CASE WHEN c.last_msg_date >= TRUNC(SYSDATE) THEN TO_CHAR(c.last_msg_date,'HH24:MI')
                    ELSE TO_CHAR(c.last_msg_date,'DD/MM') END AS display_time,
               p.last_read_msg_id,
               -- aus_id người gửi tin cuối (local table)
               (SELECT m.from_aus_id FROM CHAT_MESSENGERS m
                WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
                ORDER BY m.msg_id DESC FETCH FIRST 1 ROW ONLY) AS last_sender_aus_id,
               -- tên ngắn người gửi cuối (để hiển thị mini-badge + preview prefix)
               (SELECT REGEXP_SUBSTR(REGEXP_REPLACE(NVL(e3.full_name,'?'),'[[:cntrl:]]',''),'\S+$')
                FROM CHAT_MESSENGERS m3
                JOIN APP_USERS u3 ON u3.aus_id = m3.from_aus_id
                JOIN EMPLOYEES e3 ON e3.emp_id = u3.emp_id
                WHERE m3.conv_id = c.conv_id AND m3.delete_date IS NULL
                ORDER BY m3.msg_id DESC FETCH FIRST 1 ROW ONLY) AS last_sender_word,
               -- ảnh avatar người gửi tin cuối (mini-badge) — nguồn v_employees_v6.v_file_name
               (SELECT vf.v_file_name
                FROM CHAT_MESSENGERS m4
                JOIN APP_USERS u4 ON u4.aus_id = m4.from_aus_id
                JOIN v_employees_v6 vf ON vf.emp_id = u4.emp_id
                WHERE m4.conv_id = c.conv_id AND m4.delete_date IS NULL
                ORDER BY m4.msg_id DESC FETCH FIRST 1 ROW ONLY) AS last_sender_img,
               (SELECT COUNT(*) FROM CHAT_MESSENGERS m
                WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
                AND m.msg_id > NVL(p.last_read_msg_id, 0)) AS unread_count
        FROM CHAT_CONVERSATIONS c
        JOIN CHAT_PARTICIPANTS p ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
        WHERE c.doc_type = l_doc_type AND c.doc_no = l_doc_no AND c.conv_type = 'CHANNEL'
          AND (l_filter != 'UNREAD' OR
               (SELECT COUNT(*) FROM CHAT_MESSENGERS m
                WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
                AND m.msg_id > NVL(p.last_read_msg_id, 0)) > 0)
          AND (l_search IS NULL
               OR LOWER(NVL(c.name,'')) LIKE '%' || l_search || '%'
               OR LOWER(NVL(c.last_msg_preview,'')) LIKE '%' || l_search || '%'
               OR EXISTS (
                    SELECT 1 FROM CHAT_PARTICIPANTS ps
                    JOIN   APP_USERS  us ON us.aus_id = ps.aus_id
                    JOIN   EMPLOYEES  es ON es.emp_id = us.emp_id
                    WHERE  ps.conv_id = c.conv_id
                      AND  ps.aus_id != l_aus_id
                      AND (LOWER(NVL(es.full_name,'')) LIKE '%' || l_search || '%'
                        OR LOWER(NVL(us.user_name,'')) LIKE '%' || l_search || '%')))
        ORDER BY c.last_msg_date DESC NULLS LAST
      ) LOOP
        DECLARE
          l_name        VARCHAR2(200) := REGEXP_REPLACE(NVL(conv.display_name,'?'),'[[:cntrl:]]','');
          l_unread      BOOLEAN       := conv.unread_count > 0;
          l_cls         VARCHAR2(100) := 'convo-item' || CASE WHEN l_unread THEN ' unread' END;
          l_badge_hue   VARCHAR2(10)  := TO_CHAR(MOD(NVL(conv.last_sender_aus_id,0)*47,360));
          l_badge_initl VARCHAR2(4)   := UPPER(SUBSTR(NVL(conv.last_sender_word,'?'),1,1));
          l_is_mine     BOOLEAN       := (conv.last_sender_aus_id = l_aus_id);
          l_sender_lbl  VARCHAR2(200);
        BEGIN
          IF l_is_mine THEN l_sender_lbl := 'Bạn';
          ELSIF conv.last_sender_word IS NOT NULL THEN l_sender_lbl := conv.last_sender_word;
          END IF;
          HTP.p('<div class="' || l_cls || '" data-conv-id="' || conv.conv_id || '" data-partner-aus-id="">');
          HTP.p('  <div class="convo-avatar-wrap">');
          HTP.p('    <div class="convo-avatar group"><span class="fa fa-users"></span></div>');
          -- Mini-badge: avatar người gửi tin cuối (bottom-right của group icon)
          IF conv.last_sender_aus_id IS NOT NULL THEN
            HTP.p('    <div class="convo-sender-badge" style="background:hsl('
                  || l_badge_hue || ',55%,52%)">');
            IF conv.last_sender_img IS NOT NULL THEN
              HTP.p('<img class="av-img" loading="lazy" onerror="this.remove()" src="'
                    || HTF.ESCAPE_SC(conv.last_sender_img) || '">');
            END IF;
            HTP.p(l_badge_initl || '</div>');
          END IF;
          HTP.p('  </div>');
          HTP.p('  <div class="convo-content">');
          HTP.p('    <div class="convo-row1">');
          HTP.p('      <span class="convo-name">' || HTF.ESCAPE_SC(l_name) || '</span>');
          HTP.p('      <span class="convo-time">' || NVL(conv.display_time,'') || '</span>');
          HTP.p('    </div>');
          HTP.p('    <div class="convo-row2">');
          HTP.p('      <span class="convo-preview">'
                || CASE WHEN l_sender_lbl IS NOT NULL
                   THEN '<span class="convo-sender-name">' || HTF.ESCAPE_SC(l_sender_lbl) || ':</span> '
                   END
                || HTF.ESCAPE_SC(SUBSTR(NVL(conv.last_msg_preview,''),1,55)) || '</span>');
          IF l_unread THEN
            HTP.p('      <div class="convo-meta"><span class="convo-badge">' || conv.unread_count || '</span></div>');
          END IF;
          HTP.p('    </div>');
          HTP.p('  </div>');
          HTP.p('</div>');
        END;
      END LOOP;
    END IF; -- CHANNEL section

    -- ── DM SECTION ───────────────────────────────────────────────
    IF l_dm_count > 0 THEN
      HTP.p('<div class="convo-section-label"' || CASE WHEN l_ch_count > 0 THEN ' style="margin-top:4px"' END
            || '>TRAO ĐỔI CÁ NHÂN &middot; ' || l_dm_count || '</div>');
      FOR conv IN (
        SELECT c.conv_id,
               (SELECT NVL(e2.full_name,'Unknown')
                FROM CHAT_PARTICIPANTS p2
                JOIN APP_USERS u2 ON u2.aus_id = p2.aus_id
                JOIN EMPLOYEES e2 ON e2.emp_id = u2.emp_id
                WHERE p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
                FETCH FIRST 1 ROW ONLY) AS display_name,
               (SELECT vf.v_file_name
                FROM CHAT_PARTICIPANTS p2
                JOIN APP_USERS u2 ON u2.aus_id = p2.aus_id
                JOIN v_employees_v6 vf ON vf.emp_id = u2.emp_id
                WHERE p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
                FETCH FIRST 1 ROW ONLY) AS partner_img,
               c.last_msg_preview,
               CASE WHEN c.last_msg_date >= TRUNC(SYSDATE) THEN TO_CHAR(c.last_msg_date,'HH24:MI')
                    ELSE TO_CHAR(c.last_msg_date,'DD/MM') END AS display_time,
               p.last_read_msg_id,
               (SELECT p2.aus_id FROM CHAT_PARTICIPANTS p2
                WHERE p2.conv_id = c.conv_id AND p2.aus_id != l_aus_id
                FETCH FIRST 1 ROW ONLY) AS partner_aus_id,
               (SELECT COUNT(*) FROM CHAT_MESSENGERS m
                WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
                AND m.msg_id > NVL(p.last_read_msg_id, 0)) AS unread_count
        FROM CHAT_CONVERSATIONS c
        JOIN CHAT_PARTICIPANTS p ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
        WHERE c.doc_type = l_doc_type AND c.doc_no = l_doc_no AND c.conv_type = 'DM'
          AND (l_filter != 'UNREAD' OR
               (SELECT COUNT(*) FROM CHAT_MESSENGERS m
                WHERE m.conv_id = c.conv_id AND m.delete_date IS NULL
                AND m.msg_id > NVL(p.last_read_msg_id, 0)) > 0)
          AND (l_search IS NULL
               OR LOWER(NVL(c.last_msg_preview,'')) LIKE '%' || l_search || '%'
               OR EXISTS (
                    SELECT 1 FROM CHAT_PARTICIPANTS ps
                    JOIN   APP_USERS  us ON us.aus_id = ps.aus_id
                    JOIN   EMPLOYEES  es ON es.emp_id = us.emp_id
                    WHERE  ps.conv_id = c.conv_id
                      AND  ps.aus_id != l_aus_id
                      AND (LOWER(NVL(es.full_name,'')) LIKE '%' || l_search || '%'
                        OR LOWER(NVL(us.user_name,'')) LIKE '%' || l_search || '%')))
        ORDER BY c.last_msg_date DESC NULLS LAST
      ) LOOP
        DECLARE
          l_name     VARCHAR2(200) := REGEXP_REPLACE(NVL(conv.display_name,'?'),'[[:cntrl:]]','');
          l_initl    VARCHAR2(4)   := UPPER(SUBSTR(REGEXP_SUBSTR(l_name,'\S+$'),1,1));
          l_hue      VARCHAR2(10)  := TO_CHAR(MOD(NVL(conv.partner_aus_id,0)*47,360));
          l_unread   BOOLEAN       := conv.unread_count > 0;
          l_cls      VARCHAR2(100) := 'convo-item' || CASE WHEN l_unread THEN ' unread' END;
          l_online   BOOLEAN       := FALSE;
          l_presence VARCHAR2(10);
        BEGIN
          -- Presence check: CHAT_USER_ONLINE là local table, không qua DB link
          IF conv.partner_aus_id IS NOT NULL THEN
            BEGIN
              SELECT 1 INTO l_dummy FROM CHAT_USER_ONLINE
              WHERE aus_id = conv.partner_aus_id AND last_seen >= l_online_cutoff;
              l_online := TRUE;
            EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
            END;
          END IF;
          l_presence := CASE WHEN l_online THEN 'online' ELSE 'offline' END;
          HTP.p('<div class="' || l_cls || '" data-conv-id="' || conv.conv_id
                || '" data-partner-aus-id="' || NVL(conv.partner_aus_id,'') || '">');
          HTP.p('  <div class="convo-avatar-wrap">');
          HTP.p('    <div class="convo-avatar" style="background:hsl(' || l_hue || ',55%,52%)">');
          IF conv.partner_img IS NOT NULL THEN
            HTP.p('<img class="av-img" loading="lazy" onerror="this.remove()" src="' || HTF.ESCAPE_SC(conv.partner_img) || '">');
          END IF;
          HTP.p(NVL(l_initl,'?') || '<span class="presence ' || l_presence || '"></span></div>');
          HTP.p('  </div>');
          HTP.p('  <div class="convo-content">');
          HTP.p('    <div class="convo-row1">');
          HTP.p('      <span class="convo-name">' || HTF.ESCAPE_SC(l_name) || '</span>');
          HTP.p('      <span class="convo-time">' || NVL(conv.display_time,'') || '</span>');
          HTP.p('    </div>');
          HTP.p('    <div class="convo-row2">');
          HTP.p('      <span class="convo-preview">'
                || HTF.ESCAPE_SC(SUBSTR(NVL(conv.last_msg_preview,''),1,60)) || '</span>');
          IF l_unread THEN
            HTP.p('      <div class="convo-meta"><span class="convo-badge">' || conv.unread_count || '</span></div>');
          END IF;
          HTP.p('    </div>');
          HTP.p('  </div>');
          HTP.p('</div>');
        END;
      END LOOP;
    END IF; -- DM section

  END IF; -- total > 0

  HTP.p('</div>'); -- .convo-list
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('<div class="dc-err">Lỗi: ' || HTF.ESCAPE_SC(SQLERRM) || '</div>');
END;


-- ============================================================
-- 2. dcMsgThreadHtml
--    Trả HTML danh sách tin nhắn (chat-messages nội dung)
--    x01=conv_id | x02=search_query (rỗng = tắt filter)
--    Dùng MATERIALIZE vì REGEXP_REPLACE trên remote column.
-- ============================================================
DECLARE
  l_conv_id  NUMBER       := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_search   VARCHAR2(200) := LOWER(TRIM(apex_application.g_x02));
  l_aus_id   NUMBER;
  l_last_day DATE := NULL;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  IF l_conv_id = 0 THEN
    HTP.p('<div style="text-align:center;color:var(--text-3);margin-top:60px;font-size:13px">← Chọn hội thoại</div>');
    RETURN;
  END IF;

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('<div class="dc-err">Phiên đăng nhập hết hạn</div>'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('<div class="dc-err">Không tìm thấy user</div>'); RETURN;
  END;

  IF l_search IS NOT NULL THEN
    HTP.p('<div style="padding:6px 16px 2px;font-size:12px;color:var(--text-3)">');
    HTP.p('  Kết quả tìm kiếm: <strong>' || HTF.ESCAPE_SC(apex_application.g_x02) || '</strong>');
    HTP.p('</div>');
  END IF;

  -- Render messages
  FOR msg IN (
    WITH msg_raw AS (
      SELECT /*+ MATERIALIZE */
        m.msg_id,
        m.from_aus_id,
        u.emp_id,
        REGEXP_REPLACE(NVL(e.full_name,'Unknown'), '[[:cntrl:]]', '') AS from_name,
        CASE WHEN m.delete_date IS NOT NULL THEN NULL ELSE m.body END AS body,
        m.delete_date,
        m.reply_to_msg_id,
        TRUNC(m.create_date)               AS msg_day,
        TO_CHAR(m.create_date, 'HH24:MI')  AS msg_time,
        CASE WHEN qm.delete_date IS NOT NULL THEN '[Tin nhắn đã bị xóa]' ELSE qm.body END AS reply_body,
        REGEXP_REPLACE(NVL(qe.full_name,''), '[[:cntrl:]]', '') AS reply_from_name
      FROM   CHAT_MESSENGERS m
      JOIN   APP_USERS       u  ON u.aus_id  = m.from_aus_id
      JOIN   EMPLOYEES       e  ON e.emp_id  = u.emp_id
      LEFT JOIN CHAT_MESSENGERS qm ON qm.msg_id  = m.reply_to_msg_id
      LEFT JOIN APP_USERS    qu  ON qu.aus_id = qm.from_aus_id
      LEFT JOIN EMPLOYEES    qe  ON qe.emp_id = qu.emp_id
      WHERE  m.conv_id = l_conv_id
        AND  (l_search IS NULL OR LOWER(m.body) LIKE '%' || l_search || '%')
      ORDER  BY m.msg_id ASC
      FETCH FIRST 50 ROWS ONLY
    )
    SELECT mr.*, vf.v_file_name AS img
    FROM   msg_raw mr
    LEFT JOIN v_employees_v6 vf ON vf.emp_id = mr.emp_id
  ) LOOP
    -- Date divider
    IF l_last_day IS NULL OR msg.msg_day > l_last_day THEN
      l_last_day := msg.msg_day;
      HTP.p('<div class="chat-day-divider">' || TO_CHAR(msg.msg_day,'DD/MM/YYYY') || '</div>');
    END IF;

    DECLARE
      l_mine     BOOLEAN      := (msg.from_aus_id = l_aus_id);
      l_cls      VARCHAR2(50) := 'msg-row' || CASE WHEN l_mine THEN ' mine' END;
      l_av       VARCHAR2(4);
      l_body_esc VARCHAR2(32767);
    BEGIN
      -- Avatar initial (last word of full_name)
      l_av := UPPER(SUBSTR(REGEXP_SUBSTR(msg.from_name, '\S+$'), 1, 1));
      IF l_av IS NULL THEN l_av := '?'; END IF;

      HTP.p('<div class="' || l_cls || '" data-msg-id="' || msg.msg_id || '">');

      -- Avatar (ẩn với tin nhắn của mình)
      IF l_mine THEN
        HTP.p('  <div class="msg-avatar hidden"></div>');
      ELSE
        HTP.p('  <div class="msg-avatar" style="background:hsl(' || MOD(msg.from_aus_id * 47, 360) || ',55%,52%)">');
        IF msg.img IS NOT NULL THEN
          HTP.p('<img class="av-img" loading="lazy" onerror="this.remove()" src="' || HTF.ESCAPE_SC(msg.img) || '">');
        END IF;
        HTP.p(l_av || '</div>');
      END IF;

      HTP.p('  <div class="msg-col">');

      -- Sender name + time
      HTP.p('    <div class="msg-meta">');
      IF NOT l_mine THEN
        HTP.p('      <span class="msg-meta-name">' || HTF.ESCAPE_SC(msg.from_name) || '</span>');
      END IF;
      HTP.p('      <span class="msg-meta-time">' || msg.msg_time || '</span>');
      HTP.p('    </div>');

      -- Reply context
      IF msg.reply_to_msg_id IS NOT NULL THEN
        HTP.p('    <div class="msg-reply-context">');
        IF msg.reply_from_name IS NOT NULL THEN
          HTP.p('      <span class="name">' || HTF.ESCAPE_SC(msg.reply_from_name) || '</span> ');
        END IF;
        HTP.p('      <span class="body">' || HTF.ESCAPE_SC(SUBSTR(NVL(msg.reply_body,''),1,80)) || '</span>');
        HTP.p('    </div>');
      END IF;

      -- Message body
      IF msg.delete_date IS NOT NULL THEN
        HTP.p('    <div class="msg-bubble deleted">[Tin nhắn đã bị thu hồi]</div>');
      ELSE
        -- Escape HTML, convert newlines to <br>
        l_body_esc := REPLACE(REPLACE(
          REPLACE(REPLACE(HTF.ESCAPE_SC(NVL(msg.body,'')), '&#38;', '&amp;'),
          '&#60;', '&lt;'), CHR(13), ''), CHR(10), '<br>');
        HTP.p('    <div class="msg-bubble">' || l_body_esc || '</div>');
      END IF;

      -- Hover actions (reply button)
      IF msg.delete_date IS NULL THEN
        HTP.p('    <div class="msg-hover-actions">');
        HTP.p('      <button type="button" class="msg-hover-action" title="Trả lời"');
        HTP.p('              data-reply-id="' || msg.msg_id || '"');
        HTP.p('              data-reply-body="' || REPLACE(SUBSTR(NVL(msg.body,''),1,100),'"','&quot;') || '">');
        HTP.p('        <span class="fa fa-reply"></span>');
        HTP.p('      </button>');
        HTP.p('    </div>');
      END IF;

      HTP.p('  </div>'); -- .msg-col
      HTP.p('</div>'); -- .msg-row
    END;
  END LOOP;

  -- Empty state
  IF l_last_day IS NULL THEN
    IF l_search IS NOT NULL THEN
      HTP.p('<div style="text-align:center;color:var(--text-3);margin-top:60px;font-size:13px">Không tìm thấy tin nhắn nào.</div>');
    ELSE
      HTP.p('<div style="text-align:center;color:var(--text-3);margin-top:60px;font-size:13px">Chưa có tin nhắn. Hãy bắt đầu cuộc trò chuyện!</div>');
    END IF;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('<div class="dc-err">Lỗi: ' || HTF.ESCAPE_SC(SQLERRM) || '</div>');
END;


-- ============================================================
-- 3. dcInfoHtml
--    Trả HTML cho info panel bên phải.
--    Section 1: Doc summary card (shell) — JS điền nội dung từ sessionStorage
--    Section 2: Thao tác nhanh (quick actions)
--    Section 3: Thành viên (members với CSS classes đúng)
--    x01=conv_id
--    Dùng MATERIALIZE + biến l_online_cutoff (tránh ORA-02000).
-- ============================================================
DECLARE
  l_conv_id       NUMBER    := TO_NUMBER(NVL(TRIM(apex_application.g_x01),'0'));
  l_online_cutoff TIMESTAMP := SYSTIMESTAMP - INTERVAL '35' SECOND;
  l_aus_id        NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  -- ── SECTION 1: Doc summary card ──────────────────────────────
  -- Shell được JS điền vào qua injectDocFields() sau khi render xong
  HTP.p('<div class="info-section">');
  HTP.p('  <div class="info-section-title"><span class="fa fa-file-text-o"></span> Chứng từ</div>');
  HTP.p('  <div class="doc-summary-card">');
  HTP.p('    <div class="doc-summary-no"><span class="label" id="dc-doc-no">—</span><span class="status" id="dc-doc-status"></span></div>');
  HTP.p('    <div class="doc-summary-type" id="dc-doc-label"></div>');
  HTP.p('    <div class="doc-summary-rows" id="dc-doc-fields-placeholder"><div class="dc-loading" style="padding:8px 0">Đang tải...</div></div>');
  HTP.p('    <hr class="doc-summary-divider">');
  HTP.p('    <div class="doc-summary-row"><span class="k">Giá trị</span><span class="v money" id="dc-doc-total">—</span></div>');
  HTP.p('  </div>');
  HTP.p('</div>');

  -- ── SECTION 2: Quick actions ──────────────────────────────────
  HTP.p('<div class="info-section">');
  HTP.p('  <div class="info-section-title"><span class="fa fa-bolt"></span> Thao tác nhanh</div>');
  HTP.p('  <div class="quick-action" id="dc-qa-open"><div class="quick-action-icon"><span class="fa fa-external-link"></span></div>Mở chứng từ</div>');
  HTP.p('  <div class="quick-action" id="dc-qa-approve"><div class="quick-action-icon"><span class="fa fa-check-circle-o"></span></div>Duyệt chứng từ</div>');
  HTP.p('  <div class="quick-action" id="dc-qa-print"><div class="quick-action-icon"><span class="fa fa-print"></span></div>In chứng từ</div>');
  HTP.p('  <div class="quick-action" id="dc-qa-pdf"><div class="quick-action-icon"><span class="fa fa-download"></span></div>Tải PDF</div>');
  HTP.p('</div>');

  IF l_conv_id = 0 THEN
    HTP.p('<div class="info-section" style="color:var(--text-3);font-size:13px">Chọn hội thoại để xem thành viên</div>');
    RETURN;
  END IF;

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN;
  END;

  -- ── SECTION 3: Members ────────────────────────────────────────
  DECLARE
    l_count NUMBER := 0;
  BEGIN
    HTP.p('<div class="info-section">');
    HTP.p('  <div class="info-section-title">');
    HTP.p('    <span class="fa fa-users"></span> Thành viên');
    HTP.p('    <span class="count" id="dc-member-count">…</span>');
    HTP.p('  </div>');
    FOR mem IN (
      WITH members_raw AS (
        SELECT /*+ MATERIALIZE */
          p.aus_id,
          p.is_admin,
          u.emp_id,
          REGEXP_REPLACE(NVL(e.full_name,'Unknown'), '[[:cntrl:]]', '') AS full_name,
          REGEXP_REPLACE(NVL(d.dep_name,''),          '[[:cntrl:]]', '') AS dep_name
        FROM CHAT_PARTICIPANTS p
        JOIN APP_USERS   u ON u.aus_id  = p.aus_id
        JOIN EMPLOYEES   e ON e.emp_id  = u.emp_id
        LEFT JOIN DEPARTMENTS d ON d.dep_id = e.dep_id
        WHERE p.conv_id = l_conv_id
      )
      SELECT r.aus_id, r.is_admin, r.full_name, r.dep_name, vf.v_file_name AS img,
             CASE WHEN o.last_seen >= l_online_cutoff THEN 'online' ELSE 'offline' END AS presence
      FROM members_raw r
      LEFT JOIN CHAT_USER_ONLINE o ON o.aus_id = r.aus_id
      LEFT JOIN v_employees_v6 vf ON vf.emp_id = r.emp_id
      ORDER BY r.is_admin DESC, r.full_name
    ) LOOP
      l_count := l_count + 1;
      DECLARE
        l_av  VARCHAR2(4)  := UPPER(SUBSTR(REGEXP_SUBSTR(mem.full_name,'\S+$'),1,1));
        l_hue VARCHAR2(10) := TO_CHAR(MOD(mem.aus_id * 47, 360));
        l_me  BOOLEAN      := (mem.aus_id = l_aus_id);
      BEGIN
        HTP.p('<div class="member-row">');
        HTP.p('  <div class="member-avatar" style="background:hsl(' || l_hue || ',55%,52%)">');
        IF mem.img IS NOT NULL THEN
          HTP.p('    <img class="av-img" loading="lazy" onerror="this.remove()" src="' || HTF.ESCAPE_SC(mem.img) || '">');
        END IF;
        HTP.p('    ' || NVL(l_av,'?'));
        HTP.p('    <span class="presence ' || mem.presence || '"></span>');
        HTP.p('  </div>');
        HTP.p('  <div class="member-info">');
        HTP.p('    <div class="member-name">'
              || HTF.ESCAPE_SC(mem.full_name)
              || CASE WHEN l_me THEN ' <span style="color:var(--text-3);font-size:11px;font-weight:400">(bạn)</span>' END
              || '</div>');
        IF mem.dep_name IS NOT NULL THEN
          HTP.p('    <div class="member-role">' || HTF.ESCAPE_SC(mem.dep_name) || '</div>');
        END IF;
        HTP.p('  </div>');
        IF mem.is_admin = 1 THEN
          HTP.p('  <span class="member-badge admin">QUẢN TRỊ</span>');
        END IF;
        HTP.p('</div>');
      END;
    END LOOP;

    -- Update count badge via inline script
    HTP.p('<script>(function(){ var el=document.getElementById("dc-member-count"); if(el) el.textContent=' || l_count || '; })();</script>');
    HTP.p('</div>'); -- .info-section members

    -- ── SECTION 4: Files placeholder ─────────────────────────────
    HTP.p('<div class="info-section">');
    HTP.p('  <div class="info-section-title"><span class="fa fa-paperclip"></span> File đã chia sẻ<span class="count">0</span></div>');
    HTP.p('  <div style="text-align:center;padding:16px 0;color:var(--text-4);font-size:12.5px">');
    HTP.p('    <span class="fa fa-inbox" style="font-size:22px;display:block;margin-bottom:6px"></span>Chưa có file nào');
    HTP.p('  </div>');
    HTP.p('</div>');
  END;
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('<div class="dc-err">Lỗi: ' || HTF.ESCAPE_SC(SQLERRM) || '</div>');
END;


-- ============================================================
-- 4. dcContactsHtml
--    Trả HTML form chọn thành viên để tạo hội thoại.
--    Không tham số. Dùng MATERIALIZE + l_online_cutoff.
--    JS trong doc-chat-page.js xử lý toàn bộ interaction.
-- ============================================================
DECLARE
  l_aus_id        NUMBER;
  l_online_cutoff TIMESTAMP := SYSTIMESTAMP - INTERVAL '35' SECOND;
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('<div class="dc-err">Phiên đăng nhập hết hạn</div>'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('<div class="dc-err">Không tìm thấy user</div>'); RETURN;
  END;

  -- 1. Doc context banner (JS sẽ điền text qua injectCreateContext())
  HTP.p('<div class="dc-create-context">');
  HTP.p('  <span class="fa fa-hashtag" style="font-size:11px"></span>');
  HTP.p('  Hội thoại gắn với chứng từ <b id="dc-create-doc-ref">—</b>');
  HTP.p('</div>');

  -- 2. Conv type tabs
  HTP.p('<div class="form-field">');
  HTP.p('  <span class="form-label">Loại hội thoại</span>');
  HTP.p('  <div class="dc-type-tabs" style="margin-top:4px">');
  HTP.p('    <label class="dc-type-tab active"><input type="radio" name="dc-conv-type" value="DM" checked><span class="fa fa-user"></span> Nhắn tin riêng</label>');
  HTP.p('    <label class="dc-type-tab"><input type="radio" name="dc-conv-type" value="CHANNEL"><span class="fa fa-users"></span> Tạo nhóm</label>');
  HTP.p('  </div>');
  HTP.p('</div>');

  -- 3. Group name (hidden until CHANNEL selected)
  HTP.p('<div id="dc-create-name-wrap" class="form-field" style="display:none">');
  HTP.p('  <span class="form-label">Tên nhóm <span style="color:var(--danger)">*</span></span>');
  HTP.p('  <input type="text" id="dc-create-name" class="form-input" placeholder="Ví dụ: Duyệt giá &amp; chiết khấu"/>');
  HTP.p('  <span style="font-size:11px;color:var(--text-3)">Nhập tên nhóm, hoặc để trống để lấy mặc định.</span>');
  HTP.p('</div>');

  -- 4. Selected chips area
  HTP.p('<div class="form-field">');
  HTP.p('  <span class="form-label">Đã chọn (<span id="dc-selected-count">0</span>)</span>');
  HTP.p('  <div class="member-pick" id="dc-selected-chips">');
  HTP.p('    <span style="color:var(--text-4);font-size:13px;padding:4px">Chưa chọn thành viên nào</span>');
  HTP.p('  </div>');
  HTP.p('</div>');

  -- 5. Search input
  HTP.p('<div class="form-field" style="gap:6px">');
  HTP.p('  <input type="text" class="form-input" id="dc-contact-search" placeholder="Tìm theo tên hoặc phòng ban..."/>');
  HTP.p('</div>');

  -- 6. Member list — nhóm theo phòng ban
  HTP.p('<div class="member-suggest" id="dc-member-suggest-list">');
  DECLARE
    l_prev_dep VARCHAR2(200) := '~~init~~';
  BEGIN
    FOR usr IN (
      WITH users_raw AS (
        SELECT /*+ MATERIALIZE */
          u.aus_id,
          u.emp_id,
          REGEXP_REPLACE(NVL(e.full_name,'Unknown'), '[[:cntrl:]]', '') AS full_name,
          REGEXP_REPLACE(NVL(d.dep_name,'Khác'),     '[[:cntrl:]]', '') AS dep_name
        FROM APP_USERS u
        JOIN EMPLOYEES e ON e.emp_id = u.emp_id
        LEFT JOIN DEPARTMENTS d ON d.dep_id = e.dep_id
        WHERE u.aus_id != l_aus_id
      )
      SELECT r.aus_id, r.full_name, r.dep_name, vf.v_file_name AS img,
             CASE WHEN o.last_seen >= l_online_cutoff THEN 'online' ELSE 'offline' END AS presence
      FROM   users_raw r
      LEFT JOIN CHAT_USER_ONLINE o ON o.aus_id = r.aus_id
      LEFT JOIN v_employees_v6 vf ON vf.emp_id = r.emp_id
      ORDER  BY r.dep_name, r.full_name
    ) LOOP
      IF usr.dep_name <> l_prev_dep THEN
        HTP.p('<div class="dc-dept-h" data-dept-header="1">' || HTF.ESCAPE_SC(usr.dep_name) || '</div>');
        l_prev_dep := usr.dep_name;
      END IF;
      DECLARE
        l_av   VARCHAR2(4)    := UPPER(SUBSTR(REGEXP_SUBSTR(usr.full_name,'\S+$'),1,1));
        l_hue  VARCHAR2(10)   := TO_CHAR(MOD(usr.aus_id * 47, 360));
        l_name VARCHAR2(200)  := HTF.ESCAPE_SC(usr.full_name);
        l_dept VARCHAR2(200)  := HTF.ESCAPE_SC(usr.dep_name);
        l_img  VARCHAR2(1000) := usr.img;
      BEGIN
        HTP.p('<div class="member-suggest-item"');
        HTP.p('     data-aus-id="' || usr.aus_id || '"');
        HTP.p('     data-name="'   || REPLACE(l_name,'"','&quot;') || '"');
        HTP.p('     data-dept="'   || REPLACE(l_dept,'"','&quot;') || '"');
        HTP.p('     data-img="'    || HTF.ESCAPE_SC(NVL(l_img,'')) || '"');
        HTP.p('     data-hue="'    || l_hue || '">');
        HTP.p('  <div class="member-avatar" style="width:32px;height:32px;font-size:12px;background:hsl(' || l_hue || ',55%,52%)">');
        IF l_img IS NOT NULL THEN
          HTP.p('    <img class="av-img" loading="lazy" onerror="this.remove()" src="' || HTF.ESCAPE_SC(l_img) || '">');
        END IF;
        HTP.p('    ' || NVL(l_av,'?'));
        HTP.p('    <span class="presence ' || usr.presence || '"></span>');
        HTP.p('  </div>');
        HTP.p('  <div class="member-info">');
        HTP.p('    <div class="member-name">' || l_name || '</div>');
        HTP.p('    <div class="member-role">' || l_dept || '</div>');
        HTP.p('  </div>');
        HTP.p('  <div class="dc-checkbox"></div>');
        HTP.p('</div>');
      END;
    END LOOP;
  END;
  HTP.p('</div>'); -- #dc-member-suggest-list
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('<div class="dc-err">Lỗi: ' || HTF.ESCAPE_SC(SQLERRM) || '</div>');
END;
