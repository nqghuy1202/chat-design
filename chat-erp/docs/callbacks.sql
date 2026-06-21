-- ============================================================
-- CHAT-ERP (page 10022710202) — APEX Ajax Callbacks
-- Tất cả tạo là PAGE-LEVEL AJAX CALLBACK trên page chat-erp.
-- Page → Processing → Ajax Callback. Chạy docs/schema-additions.sql TRƯỚC.
-- Dùng chung APP_USERS / EMPLOYEES / v_employees_v6 / CHAT_* / CONV_SEQ / MSG_SEQ
-- với messenger/. Real-time dùng CHUNG Node chat-server với messenger/ —
-- mọi đọc/ghi DB vẫn qua callback APEX; sau khi ghi DB thành công, BROWSER
-- (không phải DB) tự gọi nodePost('/broadcast-message') để phát SSE — xem
-- ghi chú đầu chat-modal.fgvd.js và messenger/CLAUDE.md mục "Luồng gửi file thật".
--
-- Danh sách:
--   1. msGetCurrentUser  — user đang login (JSON)
--   2. msConvListHtml    — sidebar 4 nhóm + nhóm con lồng + Đã ghim (HTML)
--   3. msMsgThreadHtml   — thread tin nhắn (HTML)
--   4. msSendMsg         — gửi tin nhắn (JSON enrich đủ trường để broadcast)
--   5. msMarkRead        — đánh dấu đã đọc (JSON {ok:true})
--   6. msToggleReaction  — thả/bỏ reaction 👍 (JSON {mine,count})
--   7. msInfoHtml        — right panel: thành viên/ảnh/file (HTML)
--   8. msContactsHtml    — danh sách người cho compose (HTML)
--   9. msCreateDM        — tạo/dedup DM (JSON {conv_id})
--  10. msCreateGroup     — tạo Nhóm riêng tư (JSON {conv_id})
--  11. msCreateChannel   — tạo Channel theo nhóm quyền (JSON {conv_id})
--  12. msCreateSubgroup  — tạo nhóm con (JSON {conv_id})
--  13. msConvAction      — pin/unpin/hide/delete hội thoại (JSON {ok:true})
--  14. msGlobalSearchHtml — tìm toàn cục ⌘K (HTML)
--  15. msRoleOptionsHtml  — option nhóm quyền thật từ GROUP_USERS (HTML)
--  16. msUploadFile       — upload file thật (base64 → BLOB → FILES), JSON enrich
-- ============================================================


-- ============================================================
-- 1. msGetCurrentUser
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
    SELECT u.aus_id, REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]',''), vf.v_file_name
    INTO   l_aus_id, l_name, l_img
    FROM   APP_USERS u
    JOIN   EMPLOYEES e ON e.emp_id = u.emp_id
    LEFT JOIN v_employees_v6 vf ON vf.emp_id = u.emp_id
    WHERE  LOWER(u.user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;
  HTP.p(JSON_OBJECT('aus_id' VALUE l_aus_id,'username' VALUE :APP_USER,
                     'full_name' VALUE l_name,'img' VALUE l_img ABSENT ON NULL));
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- ============================================================
-- 2. msConvListHtml
--    x01 = filter (all/chungtu/channel/nhom/canhan) | x02 = search text
--    x03 = '1' nếu chỉ hiện chưa đọc
--    Render 5 section giống chat-modal.html: pinned, chungtu, channel, nhom (lồng
--    nhóm con ngay dưới cha), canhan. data-conv/data-name giữ nguyên để
--    filterSidebar() phía client tiếp tục hoạt động (lọc thêm không cần round-trip).
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_filter  VARCHAR2(20)  := NVL(LOWER(TRIM(apex_application.g_x01)), 'all');
  l_search  VARCHAR2(200) := LOWER(TRIM(apex_application.g_x02));
  l_unread  VARCHAR2(1)   := NVL(apex_application.g_x03, '0');
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

  -- HTML cần nhóm theo section (Đã ghim/Chứng từ/Channel/Nhóm/Cá nhân) — lặp riêng từng section,
  -- mỗi section tự query phần của mình (đơn giản hơn group lại 1 cursor trong PL/SQL).
  FOR sec IN (SELECT 'pinned' k, 'Đã ghim' lbl, 'fa-bookmark' ic, CAST(NULL AS VARCHAR2(30)) plus_title, CAST(NULL AS VARCHAR2(40)) plus_fn FROM dual UNION ALL
              SELECT 'chungtu','Chứng từ','fa-file-o', NULL, NULL FROM dual UNION ALL
              SELECT 'channel','Channel','fa-hashtag', 'Tạo kênh', 'openCreateChannel()' FROM dual UNION ALL
              SELECT 'nhom','Nhóm','fa-group', 'Tạo nhóm', 'openCreateGroup()' FROM dual UNION ALL
              SELECT 'canhan','Cá nhân','fa-user', 'Tin nhắn mới', 'openPeoplePicker()' FROM dual)
  LOOP
    DECLARE
      l_has_rows NUMBER := 0;
      l_body     CLOB;
    BEGIN
      FOR conv IN (
        WITH base AS (
          SELECT
            c.conv_id, c.conv_type, c.is_public, c.parent_conv_id,
            CASE WHEN c.conv_type='DOC' THEN 'chungtu' WHEN c.is_public=1 THEN 'channel'
                 WHEN c.conv_type='CHANNEL' THEN 'nhom' ELSE 'canhan' END AS kind,
            NVL(p.is_pinned,0) AS is_pinned,
            CASE WHEN c.conv_type='DM' THEN (
                   SELECT REGEXP_REPLACE(NVL(e2.full_name,'Unknown'),'[[:cntrl:]]','')
                   FROM CHAT_PARTICIPANTS p2 JOIN APP_USERS u2 ON u2.aus_id=p2.aus_id
                     JOIN EMPLOYEES e2 ON e2.emp_id=u2.emp_id
                   WHERE p2.conv_id=c.conv_id AND p2.aus_id != l_aus_id FETCH FIRST 1 ROW ONLY)
                 WHEN c.conv_type='DOC' THEN NVL(c.name, NVL(c.doc_type,'')||CASE WHEN c.doc_type IS NOT NULL THEN '-' END||c.doc_no)
                 ELSE NVL(c.name,'(Không tên)') END AS display_name,
            CASE WHEN c.conv_type='DM' THEN (
                   SELECT vf2.v_file_name
                   FROM CHAT_PARTICIPANTS p2 JOIN APP_USERS u2 ON u2.aus_id=p2.aus_id
                     LEFT JOIN v_employees_v6 vf2 ON vf2.emp_id=u2.emp_id
                   WHERE p2.conv_id=c.conv_id AND p2.aus_id != l_aus_id FETCH FIRST 1 ROW ONLY)
                 ELSE NULL END AS partner_img,
            c.doc_type, c.doc_no, c.last_msg_preview, c.last_msg_date,
            CASE WHEN c.last_msg_date >= TRUNC(SYSDATE) THEN TO_CHAR(c.last_msg_date,'HH24:MI')
                 ELSE TO_CHAR(c.last_msg_date,'DD/MM') END AS display_time,
            (SELECT COUNT(*) FROM CHAT_MESSENGERS m WHERE m.conv_id=c.conv_id AND m.delete_date IS NULL
               AND m.msg_id > NVL(p.last_read_msg_id,0)) AS unread_count,
            (SELECT name FROM CHAT_CONVERSATIONS pc WHERE pc.conv_id = c.parent_conv_id) AS parent_name
          FROM CHAT_CONVERSATIONS c
          JOIN CHAT_PARTICIPANTS  p ON p.conv_id=c.conv_id AND p.aus_id=l_aus_id
          WHERE NVL(p.is_hidden,0)=0
            AND (c.is_public != 1 OR NOT EXISTS (SELECT 1 FROM CHAT_CHANNEL_ROLES r WHERE r.conv_id=c.conv_id)
                 OR EXISTS (SELECT 1 FROM CHAT_CHANNEL_ROLES r JOIN USER_ROLES ur ON ur.gus_id=r.gus_id
                            WHERE r.conv_id=c.conv_id AND ur.aus_id=l_aus_id))
            AND (l_unread != '1' OR (SELECT COUNT(*) FROM CHAT_MESSENGERS m WHERE m.conv_id=c.conv_id
                  AND m.delete_date IS NULL AND m.msg_id>NVL(p.last_read_msg_id,0)) > 0)
        )
        SELECT * FROM base
        WHERE (sec.k = 'pinned' AND is_pinned = 1)
           OR (sec.k != 'pinned' AND kind = sec.k AND is_pinned = 0
               AND (l_filter='all' OR l_filter=sec.k OR l_filter='pinned'))
        ORDER BY parent_conv_id NULLS FIRST, last_msg_date DESC NULLS LAST
      ) LOOP
        IF l_has_rows = 0 THEN
          HTP.p('<div class="sb-section" data-group="'||sec.k||'">');
          HTP.p('<button class="sec-head" type="button" onclick="toggleSection(this)"><span class="caret fa fa-chevron-down"></span><span class="sec-ic fa '||sec.ic||'"></span> '||sec.lbl||
                CASE WHEN sec.plus_fn IS NOT NULL THEN
                  '<span class="plus" title="'||sec.plus_title||'" onclick="event.stopPropagation();'||sec.plus_fn||'">+</span>'
                END||'</button>');
          HTP.p('<div class="sec-body">');
          l_has_rows := 1;
        END IF;
        DECLARE
          l_cls VARCHAR2(50) := CASE WHEN conv.kind='chungtu' THEN 'doc-item' ELSE 'conv two-line' END
                                || CASE WHEN conv.parent_conv_id IS NOT NULL THEN ' subgroup' ELSE '' END;
        BEGIN
          HTP.p('<div class="'||l_cls||'" data-conv="'||conv.conv_id||'" data-name="'||HTF.ESCAPE_SC(LOWER(conv.display_name))||'" onclick="openConversation2('||conv.conv_id||')">');
          IF conv.kind = 'chungtu' THEN
            HTP.p('<span class="di-ic fa fa-file-o"></span><div class="di-main"><div class="di-top"><span class="di-code">'||HTF.ESCAPE_SC(conv.display_name)||'</span><span class="di-time">'||conv.display_time||'</span></div>');
            HTP.p('<div class="di-bottom"><span class="di-prev">'||HTF.ESCAPE_SC(NVL(conv.last_msg_preview,''))||'</span>'||
                  CASE WHEN conv.unread_count>0 THEN '<span class="di-badge">'||conv.unread_count||'</span>' ELSE '' END||'</div></div>');
          ELSE
            IF conv.kind = 'canhan' THEN
              HTP.p('<span class="avatar" style="background:hsl('||MOD(conv.conv_id*47,360)||',55%,52%)">'||
                    UPPER(SUBSTR(conv.display_name,1,1))||
                    CASE WHEN conv.partner_img IS NOT NULL THEN
                      '<img src="'||HTF.ESCAPE_SC(conv.partner_img)||'" alt="" style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%" onerror="this.remove()">'
                    END||'</span>');
            ELSIF conv.parent_conv_id IS NOT NULL THEN
              HTP.p('<span class="sg-arrow">↳</span><span class="grp-av"><span class="a a1" style="background:#0EA5E9">N</span></span>');
            ELSE
              HTP.p('<span class="grp-av"><span class="a a1" style="background:#7C3AED">N</span></span>');
            END IF;
            HTP.p('<div class="conv-main"><div class="conv-top"><span class="name">'||HTF.ESCAPE_SC(conv.display_name)||'</span><span class="conv-time">'||conv.display_time||'</span></div>');
            HTP.p('<div class="conv-prev"><span class="cp-text">'||HTF.ESCAPE_SC(NVL(conv.last_msg_preview,''))||'</span>'||
                  CASE WHEN conv.unread_count>0 THEN '<span class="badge">'||conv.unread_count||'</span>' ELSE '' END||'</div>');
            IF conv.parent_conv_id IS NOT NULL AND conv.parent_name IS NOT NULL THEN
              HTP.p('<div class="conv-src">thuộc '||HTF.ESCAPE_SC(conv.parent_name)||'</div>');
            END IF;
            HTP.p('</div>');
          END IF;
          HTP.p('</div>');
        END;
      END LOOP;
      IF l_has_rows = 1 THEN HTP.p('</div></div>'); END IF;
    END;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="padding:16px;color:#DC2626">Lỗi: '||REPLACE(SQLERRM,'"','')||'</div>');
END;


-- ============================================================
-- 3. msMsgThreadHtml
--    x01 = conv_id
-- ============================================================
DECLARE
  l_aus_id   NUMBER;
  l_conv_id  NUMBER := TO_NUMBER(apex_application.g_x01);
  l_last_day DATE;
  l_prev_from NUMBER;
  l_prev_dt   DATE;
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
  -- xác nhận user là participant
  DECLARE l_cnt NUMBER; BEGIN
    SELECT COUNT(*) INTO l_cnt FROM CHAT_PARTICIPANTS WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
    IF l_cnt = 0 THEN HTP.p('<div style="padding:16px;color:#DC2626">Không có quyền</div>'); RETURN; END IF;
  END;

  FOR msg IN (
    SELECT m.msg_id, m.from_aus_id, u.emp_id,
           REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') AS from_name,
           CASE WHEN m.delete_date IS NOT NULL THEN '[Tin nhắn đã bị xóa]' ELSE m.body END AS body,
           m.reply_to_msg_id,
           TRUNC(m.create_date) AS msg_day, CAST(m.create_date AS DATE) AS msg_dt,
           TO_CHAR(m.create_date,'HH24:MI') AS msg_time,
           CASE WHEN qm.delete_date IS NOT NULL THEN '[Tin nhắn đã bị xóa]' ELSE qm.body END AS reply_body,
           REGEXP_REPLACE(NVL(qe.full_name,''),'[[:cntrl:]]','') AS reply_from_name,
           vf.v_file_name AS sender_img,
           f.file_name AS att_path, f.name AS att_name
    FROM CHAT_MESSENGERS m
    JOIN APP_USERS u ON u.aus_id = m.from_aus_id
    JOIN EMPLOYEES e ON e.emp_id = u.emp_id
    LEFT JOIN v_employees_v6 vf ON vf.emp_id = u.emp_id
    LEFT JOIN CHAT_MESSENGERS qm ON qm.msg_id = m.reply_to_msg_id
    LEFT JOIN APP_USERS qu ON qu.aus_id = qm.from_aus_id
    LEFT JOIN EMPLOYEES qe ON qe.emp_id = qu.emp_id
    LEFT JOIN FILES f ON f.fil_id = m.fil_id
    WHERE m.conv_id = l_conv_id
    ORDER BY m.msg_id ASC
    FETCH FIRST 100 ROWS ONLY
  ) LOOP
    IF l_last_day IS NULL OR msg.msg_day > l_last_day THEN
      l_last_day := msg.msg_day;
      HTP.p('<div class="date-sep">'||TO_CHAR(msg.msg_day,'DD/MM/YYYY')||'</div>');
    END IF;
    DECLARE
      l_grouped VARCHAR2(10) := CASE WHEN l_prev_from = msg.from_aus_id
                                       AND (msg.msg_dt - l_prev_dt)*1440 < 10 THEN ' grouped' ELSE '' END;
      l_av VARCHAR2(4) := UPPER(SUBSTR(REGEXP_SUBSTR(msg.from_name,'\S+$'),1,1));
      l_hue VARCHAR2(10) := TO_CHAR(MOD(msg.from_aus_id*47,360));
      l_reactions_html CLOB := '';
      l_has_react NUMBER := 0;
    BEGIN
      HTP.p('<div class="msg'||l_grouped||'" data-msg-id="'||msg.msg_id||'" data-from-name="'||
            HTF.ESCAPE_SC(msg.from_name)||'" data-reply-to="'||NVL(TO_CHAR(msg.reply_to_msg_id),'')||'">');
      IF l_grouped IS NULL OR l_grouped = '' THEN
        HTP.p('<span class="m-av"><span class="avatar" style="background:hsl('||l_hue||',55%,52%)">'||NVL(l_av,'?')||
              CASE WHEN msg.sender_img IS NOT NULL THEN
                '<img src="'||HTF.ESCAPE_SC(msg.sender_img)||'" alt="" style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%" onerror="this.remove()">'
              END||'</span></span>');
        HTP.p('<div class="body"><div class="meta"><span class="who">'||HTF.ESCAPE_SC(msg.from_name)||'</span><span class="time">'||msg.msg_time||'</span></div>');
      ELSE
        HTP.p('<span class="m-av"></span><div class="body">');
      END IF;
      IF msg.reply_to_msg_id IS NOT NULL THEN
        HTP.p('<div class="text" style="opacity:.7;border-left:2px solid var(--accent);padding-left:8px;margin-bottom:3px">'||
              '<b>'||HTF.ESCAPE_SC(NVL(msg.reply_from_name,''))||'</b> '||HTF.ESCAPE_SC(SUBSTR(NVL(msg.reply_body,''),1,80))||'</div>');
      END IF;
      IF msg.att_path IS NOT NULL THEN
        DECLARE
          l_ext VARCHAR2(10) := LOWER(REGEXP_SUBSTR(msg.att_name,'[^.]+$'));
        BEGIN
          IF l_ext IN ('png','jpg','jpeg','gif','webp') THEN
            HTP.p('<div class="img-msg"><img src="'||HTF.ESCAPE_SC(msg.att_path)||
                  '" alt="'||HTF.ESCAPE_SC(NVL(msg.att_name,''))||'" onclick="openLightbox(this.src)"></div>');
          ELSE
            DECLARE
              -- Nhóm theo họ định dạng — mỗi họ 1 màu nhận diện riêng (xem .file-ic.ft-*
              -- trong chat-modal.css), không còn dùng chung 1 icon xám cho mọi loại file.
              l_ft_cls VARCHAR2(20) := CASE
                WHEN l_ext IN ('doc','docx','rtf','odt') THEN 'ft-word'
                WHEN l_ext IN ('xls','xlsx','csv','ods') THEN 'ft-excel'
                WHEN l_ext IN ('ppt','pptx','odp') THEN 'ft-ppt'
                WHEN l_ext = 'pdf' THEN 'ft-pdf'
                WHEN l_ext IN ('zip','rar','7z') THEN 'ft-zip'
                ELSE 'ft-generic' END;
              l_ft_icon VARCHAR2(20) := CASE
                WHEN l_ext IN ('doc','docx','rtf','odt') THEN 'fa-file-word-o'
                WHEN l_ext IN ('xls','xlsx','csv','ods') THEN 'fa-file-excel-o'
                WHEN l_ext IN ('ppt','pptx','odp') THEN 'fa-file-powerpoint-o'
                WHEN l_ext = 'pdf' THEN 'fa-file-pdf-o'
                WHEN l_ext IN ('zip','rar','7z') THEN 'fa-file-zip-o'
                ELSE 'fa-file-o' END;
            BEGIN
              HTP.p('<a class="file-card" href="'||HTF.ESCAPE_SC(msg.att_path)||'" target="_blank">'||
                    '<span class="file-ic fa '||l_ft_icon||' '||l_ft_cls||'"></span>'||
                    '<div class="file-info"><div class="file-name">'||HTF.ESCAPE_SC(NVL(msg.att_name,''))||
                    '</div><div class="file-sub">'||NVL(l_ext,'FILE')||'</div></div>'||
                    '<span class="fa fa-download file-dl"></span></a>');
            END;
          END IF;
        END;
      END IF;
      IF msg.body IS NOT NULL THEN
        DECLARE
          -- Escape trước (chống injection), rồi highlight sentinel @[tên] do composer chèn
          -- thành <span class="mention">. REGEXP chạy trên biến cục bộ nên không cần MATERIALIZE.
          l_bd VARCHAR2(4000) := HTF.ESCAPE_SC(msg.body);
        BEGIN
          l_bd := REGEXP_REPLACE(l_bd, '@\[([^]]+)\]', '<span class="mention">@\1</span>');
          HTP.p('<div class="text">'||l_bd||'</div>');
        END;
      END IF;
      FOR r IN (SELECT emoji, COUNT(*) cnt, MAX(CASE WHEN aus_id=l_aus_id THEN 1 ELSE 0 END) mine
                FROM CHAT_REACTIONS WHERE msg_id = msg.msg_id GROUP BY emoji) LOOP
        IF l_has_react = 0 THEN l_reactions_html := '<div class="reactions">'; l_has_react := 1; END IF;
        l_reactions_html := l_reactions_html || '<span class="reaction'||CASE WHEN r.mine=1 THEN ' mine' ELSE '' END||
          '" onclick="toggleReaction(this)" data-msg-id="'||msg.msg_id||'" data-emoji="'||r.emoji||'">'||r.emoji||' <span>'||r.cnt||'</span></span>';
      END LOOP;
      IF l_has_react = 1 THEN HTP.p(l_reactions_html||'</div>'); END IF;
      HTP.p('<div class="hover-actions"><button type="button" title="Cảm xúc" onclick="openReactBar(this)"><span class="fa fa-smile-o"></span></button>'||
            '<button type="button" title="Trả lời" onclick="startReply(this)"><span class="fa fa-reply"></span></button>'||
            '<button type="button" title="Luồng trả lời" onclick="openThread('||msg.msg_id||')"><span class="fa fa-comments-o"></span></button></div>');
      HTP.p('</div></div>');
      l_prev_from := msg.from_aus_id; l_prev_dt := msg.msg_dt;
    END;
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="padding:16px;color:#DC2626">Lỗi: '||REPLACE(SQLERRM,'"','')||'</div>');
END;


-- ============================================================
-- 4. msSendMsg
--    x01 = conv_id | x02 = body | x03 = reply_to_msg_id (optional)
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_conv_id NUMBER := TO_NUMBER(apex_application.g_x01);
  l_body    VARCHAR2(4000) := REGEXP_REPLACE(apex_application.g_x02,'[[:cntrl:]]','');
  l_reply   NUMBER := TO_NUMBER(NULLIF(apex_application.g_x03,''));
  l_msg_id  NUMBER;
  l_cnt     NUMBER;
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
  SELECT COUNT(*) INTO l_cnt FROM CHAT_PARTICIPANTS WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
  IF l_cnt = 0 THEN HTP.p('{"error":"forbidden"}'); RETURN; END IF;
  IF l_body IS NULL OR TRIM(l_body) IS NULL THEN HTP.p('{"error":"empty"}'); RETURN; END IF;

  l_msg_id := MSG_SEQ.NEXTVAL;
  INSERT INTO CHAT_MESSENGERS (msg_id, conv_id, from_aus_id, body, reply_to_msg_id, create_date)
  VALUES (l_msg_id, l_conv_id, l_aus_id, l_body, l_reply, SYSTIMESTAMP);

  UPDATE CHAT_CONVERSATIONS
  SET last_msg_preview = SUBSTR(l_body,1,200), last_msg_date = SYSTIMESTAMP
  WHERE conv_id = l_conv_id;

  UPDATE CHAT_PARTICIPANTS SET last_read_msg_id = l_msg_id
  WHERE conv_id = l_conv_id AND aus_id = l_aus_id;

  COMMIT;

  -- Trả đủ trường để BROWSER tự phát SSE qua nodePost('/broadcast-message') —
  -- xem ghi chú đầu chat-modal.fgvd.js. KHÔNG dùng UTL_HTTP ở đây vì máy DB
  -- Oracle thường không route được tới Node (ORA-12535), giống pitfall đã
  -- gặp ở messenger/ khi làm msUploadFile.
  DECLARE
    l_from_name VARCHAR2(200);
    l_conv_type VARCHAR2(20);
    l_conv_name VARCHAR2(200);
    l_doc_type  VARCHAR2(30);
    l_doc_no    VARCHAR2(60);
  BEGIN
    SELECT REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','')
    INTO l_from_name FROM APP_USERS u JOIN EMPLOYEES e ON e.emp_id=u.emp_id WHERE u.aus_id=l_aus_id;
    SELECT conv_type, NVL(name,''), doc_type, doc_no
    INTO l_conv_type, l_conv_name, l_doc_type, l_doc_no
    FROM CHAT_CONVERSATIONS WHERE conv_id = l_conv_id;

    HTP.p(JSON_OBJECT(
      'msg_id' VALUE l_msg_id, 'conv_id' VALUE l_conv_id, 'from_aus_id' VALUE l_aus_id,
      'from_name' VALUE l_from_name, 'body' VALUE l_body,
      'reply_to_msg_id' VALUE l_reply,
      'conv_type' VALUE l_conv_type, 'conv_name' VALUE l_conv_name,
      'doc_type' VALUE l_doc_type, 'doc_no' VALUE l_doc_no
      ABSENT ON NULL));
  END;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- ============================================================
-- 5. msMarkRead
--    x01 = conv_id
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_conv_id NUMBER := TO_NUMBER(apex_application.g_x01);
  l_max_msg NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"error":"auth"}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN; END;

  SELECT MAX(msg_id) INTO l_max_msg FROM CHAT_MESSENGERS WHERE conv_id = l_conv_id;
  UPDATE CHAT_PARTICIPANTS SET last_read_msg_id = NVL(l_max_msg,0)
  WHERE conv_id = l_conv_id AND aus_id = l_aus_id;
  COMMIT;
  HTP.p('{"ok":true}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- ============================================================
-- 6. msToggleReaction
--    x01 = msg_id | x02 = emoji (mặc định 👍)
-- ============================================================
DECLARE
  l_aus_id NUMBER;
  l_msg_id NUMBER := TO_NUMBER(apex_application.g_x01);
  l_emoji  VARCHAR2(16) := NVL(apex_application.g_x02,'👍');
  l_exist  NUMBER;
  l_mine   NUMBER := 0;
  l_count  NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"error":"auth"}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN; END;

  SELECT COUNT(*) INTO l_exist FROM CHAT_REACTIONS
  WHERE msg_id = l_msg_id AND aus_id = l_aus_id AND emoji = l_emoji;

  IF l_exist > 0 THEN
    DELETE FROM CHAT_REACTIONS WHERE msg_id=l_msg_id AND aus_id=l_aus_id AND emoji=l_emoji;
  ELSE
    INSERT INTO CHAT_REACTIONS (msg_id, aus_id, emoji) VALUES (l_msg_id, l_aus_id, l_emoji);
    l_mine := 1;
  END IF;
  COMMIT;
  SELECT COUNT(*) INTO l_count FROM CHAT_REACTIONS WHERE msg_id=l_msg_id AND emoji=l_emoji;
  HTP.p('{"mine":'||CASE WHEN l_mine=1 THEN 'true' ELSE 'false' END||',"count":'||l_count||'}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- ============================================================
-- 7. msInfoHtml  (right panel: Thành viên/Ảnh/File theo kind)
--    x01 = conv_id
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_conv_id NUMBER := TO_NUMBER(apex_application.g_x01);
  l_kind    VARCHAR2(20);
  l_title   VARCHAR2(200);
  l_mem_cnt NUMBER;
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

  SELECT CASE WHEN conv_type='DOC' THEN 'chungtu' WHEN is_public=1 THEN 'channel'
              WHEN conv_type='CHANNEL' THEN 'nhom' ELSE 'canhan' END,
         NVL(name, '(Không tên)')
  INTO l_kind, l_title
  FROM CHAT_CONVERSATIONS WHERE conv_id = l_conv_id;

  SELECT COUNT(*) INTO l_mem_cnt FROM CHAT_PARTICIPANTS WHERE conv_id = l_conv_id;

  HTP.p('<div class="side-head"><span class="st">Thông tin · '||
        CASE l_kind WHEN 'chungtu' THEN 'Chứng từ' WHEN 'channel' THEN 'Channel' WHEN 'nhom' THEN 'Nhóm' ELSE 'Cá nhân' END||
        '</span><span style="flex:1"></span><button class="icon-btn" type="button" onclick="closePanel()" title="Đóng"><span class="fa fa-close"></span></button></div>');
  HTP.p('<div class="side-body">');

  IF l_kind = 'channel' THEN
    HTP.p('<div class="ip-sec" style="cursor:default">Nhóm quyền được xem</div><div class="ip-body">');
    FOR r IN (SELECT gu.name FROM CHAT_CHANNEL_ROLES r JOIN GROUP_USERS gu ON gu.gus_id=r.gus_id WHERE r.conv_id=l_conv_id) LOOP
      HTP.p('<div class="perm-row"><span class="fa fa-shield"></span><span>'||HTF.ESCAPE_SC(r.name)||'</span></div>');
    END LOOP;
    HTP.p('</div>');
  ELSE
    HTP.p('<button class="ip-sec" type="button" onclick="toggleInfoSection(this)"><span class="caret fa fa-chevron-down"></span>Thành viên<span class="ip-count">'||
          l_mem_cnt||'</span></button>');
    HTP.p('<div class="ip-body">');
    FOR mm IN (SELECT u.aus_id, REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') nm, p.is_admin, vf.v_file_name img
               FROM CHAT_PARTICIPANTS p JOIN APP_USERS u ON u.aus_id=p.aus_id JOIN EMPLOYEES e ON e.emp_id=u.emp_id
               LEFT JOIN v_employees_v6 vf ON vf.emp_id=u.emp_id WHERE p.conv_id=l_conv_id ORDER BY p.is_admin DESC, nm) LOOP
      HTP.p('<div class="mem-row"><span class="avatar" style="background:hsl('||MOD(mm.aus_id*47,360)||',55%,52%)">'||UPPER(SUBSTR(mm.nm,1,1))||
            CASE WHEN mm.img IS NOT NULL THEN
              '<img src="'||HTF.ESCAPE_SC(mm.img)||'" alt="" style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%" onerror="this.remove()">'
            END||
            '</span><span>'||HTF.ESCAPE_SC(mm.nm)||'</span>'||
            CASE WHEN mm.is_admin=1 THEN '<span class="mr-role">Quản trị</span>' ELSE '' END||'</div>');
    END LOOP;
    HTP.p('</div>');
  END IF;

  -- ── Ảnh & file đính kèm chia sẻ trong hội thoại — màu icon ĐỒNG BỘ với
  -- .file-ic.ft-* trong msMsgThreadHtml (mục 3) và chat-modal.css, đổi 1 nơi
  -- phải đổi cả 2 nếu không icon sẽ lệch màu giữa bong bóng tin và side panel.
  DECLARE
    l_img_total  NUMBER;
    l_file_total NUMBER;
    l_i          NUMBER := 0;
  BEGIN
    SELECT COUNT(*) INTO l_img_total FROM CHAT_MESSENGERS m JOIN FILES f ON f.fil_id=m.fil_id
    WHERE m.conv_id=l_conv_id AND m.delete_date IS NULL
      AND LOWER(REGEXP_SUBSTR(f.name,'[^.]+$')) IN ('jpg','jpeg','png','gif','webp','bmp','svg');
    SELECT COUNT(*) INTO l_file_total FROM CHAT_MESSENGERS m JOIN FILES f ON f.fil_id=m.fil_id
    WHERE m.conv_id=l_conv_id AND m.delete_date IS NULL
      AND LOWER(REGEXP_SUBSTR(f.name,'[^.]+$')) NOT IN ('jpg','jpeg','png','gif','webp','bmp','svg');

    IF l_img_total > 0 THEN
      HTP.p('<button class="ip-sec" type="button" onclick="toggleInfoSection(this)"><span class="caret fa fa-chevron-down"></span>Ảnh &amp; Video<span class="ip-count">'||l_img_total||'</span></button>');
      HTP.p('<div class="ip-body"><div class="img-grid">');
      FOR im IN (SELECT file_name FROM (
                   SELECT f.file_name FROM CHAT_MESSENGERS m JOIN FILES f ON f.fil_id=m.fil_id
                   WHERE m.conv_id=l_conv_id AND m.delete_date IS NULL
                     AND LOWER(REGEXP_SUBSTR(f.name,'[^.]+$')) IN ('jpg','jpeg','png','gif','webp','bmp','svg')
                   ORDER BY m.create_date DESC
                 ) WHERE ROWNUM <= 8) LOOP
        l_i := l_i + 1;
        HTP.p('<a href="'||HTF.ESCAPE_SC(im.file_name)||'" target="_blank">');
        HTP.p('<img src="'||HTF.ESCAPE_SC(im.file_name)||'" alt="" loading="lazy" onclick="event.preventDefault();openLightbox(this.src)">');
        IF l_i = 8 AND l_img_total > 8 THEN
          HTP.p('<div class="ig-more">+'||(l_img_total-7)||'</div>');
        END IF;
        HTP.p('</a>');
      END LOOP;
      HTP.p('</div></div>');
    END IF;

    IF l_file_total > 0 THEN
      HTP.p('<button class="ip-sec" type="button" onclick="toggleInfoSection(this)"><span class="caret fa fa-chevron-down"></span>File đính kèm<span class="ip-count">'||l_file_total||'</span></button>');
      HTP.p('<div class="ip-body">');
      FOR fl IN (SELECT * FROM (
                   SELECT f.file_name, f.name AS disp_name,
                          LOWER(REGEXP_SUBSTR(f.name,'[^.]+$')) AS ext
                   FROM CHAT_MESSENGERS m JOIN FILES f ON f.fil_id=m.fil_id
                   WHERE m.conv_id=l_conv_id AND m.delete_date IS NULL
                     AND LOWER(REGEXP_SUBSTR(f.name,'[^.]+$')) NOT IN ('jpg','jpeg','png','gif','webp','bmp','svg')
                   ORDER BY m.create_date DESC
                 ) WHERE ROWNUM <= 10) LOOP
        DECLARE
          l_ft_cls VARCHAR2(20) := CASE
            WHEN fl.ext IN ('doc','docx','rtf','odt') THEN 'ft-word'
            WHEN fl.ext IN ('xls','xlsx','csv','ods') THEN 'ft-excel'
            WHEN fl.ext IN ('ppt','pptx','odp') THEN 'ft-ppt'
            WHEN fl.ext = 'pdf' THEN 'ft-pdf'
            WHEN fl.ext IN ('zip','rar','7z') THEN 'ft-zip'
            ELSE 'ft-generic' END;
          l_ft_icon VARCHAR2(20) := CASE
            WHEN fl.ext IN ('doc','docx','rtf','odt') THEN 'fa-file-word-o'
            WHEN fl.ext IN ('xls','xlsx','csv','ods') THEN 'fa-file-excel-o'
            WHEN fl.ext IN ('ppt','pptx','odp') THEN 'fa-file-powerpoint-o'
            WHEN fl.ext = 'pdf' THEN 'fa-file-pdf-o'
            WHEN fl.ext IN ('zip','rar','7z') THEN 'fa-file-zip-o'
            ELSE 'fa-file-o' END;
        BEGIN
          HTP.p('<a class="file-row" href="'||HTF.ESCAPE_SC(fl.file_name)||'" target="_blank">'||
                '<span class="fr-ic fa '||l_ft_icon||' '||l_ft_cls||'"></span>'||
                '<span class="fr-name">'||HTF.ESCAPE_SC(NVL(fl.disp_name,''))||'</span>'||
                '<span class="fr-size">'||UPPER(NVL(fl.ext,''))||'</span></a>');
        END;
      END LOOP;
      HTP.p('</div>');
    END IF;
  END;

  HTP.p('</div>');
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="padding:16px;color:#DC2626">Lỗi: '||REPLACE(SQLERRM,'"','')||'</div>');
END;


-- ============================================================
-- 8. msContactsHtml  (people picker cho compose DM/Nhóm)
--    x01 = search text
-- ============================================================
DECLARE
  l_search VARCHAR2(200) := LOWER(TRIM(apex_application.g_x01));
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');
  FOR p IN (SELECT u.aus_id, REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') nm,
                   e.position_name, vf.v_file_name img
            FROM APP_USERS u JOIN EMPLOYEES e ON e.emp_id = u.emp_id
            LEFT JOIN v_employees_v6 vf ON vf.emp_id = u.emp_id
            WHERE LOWER(u.user_name) != LOWER(:APP_USER)
              AND (l_search IS NULL OR LOWER(e.full_name) LIKE '%'||l_search||'%')
            ORDER BY nm FETCH FIRST 50 ROWS ONLY) LOOP
    HTP.p('<div class="person" data-id="'||p.aus_id||'" data-name="'||HTF.ESCAPE_SC(p.nm)||
          '" data-hue="'||MOD(p.aus_id*47,360)||'" onclick="togglePerson('||p.aus_id||')">'||
          '<span class="pa" style="background:hsl('||MOD(p.aus_id*47,360)||',55%,52%)">'||UPPER(SUBSTR(p.nm,1,1))||
          CASE WHEN p.img IS NOT NULL THEN
            '<img src="'||HTF.ESCAPE_SC(p.img)||'" alt="" style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%" onerror="this.remove()">'
          END||'</span>'||
          '<div class="pinfo"><div class="pn">'||HTF.ESCAPE_SC(p.nm)||'</div><div class="pr">'||HTF.ESCAPE_SC(NVL(p.position_name,''))||'</div></div>'||
          '<span class="ptick">✓</span></div>');
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="padding:16px;color:#DC2626">Lỗi: '||REPLACE(SQLERRM,'"','')||'</div>');
END;


-- ============================================================
-- 9. msCreateDM  (dedup theo cặp user)
--    x01 = partner_aus_id
-- ============================================================
DECLARE
  l_aus_id NUMBER;
  l_partner NUMBER := TO_NUMBER(apex_application.g_x01);
  l_conv_id NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"error":"auth"}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN; END;

  BEGIN
    SELECT c.conv_id INTO l_conv_id
    FROM CHAT_CONVERSATIONS c
    JOIN CHAT_PARTICIPANTS p1 ON p1.conv_id=c.conv_id AND p1.aus_id=l_aus_id
    JOIN CHAT_PARTICIPANTS p2 ON p2.conv_id=c.conv_id AND p2.aus_id=l_partner
    WHERE c.conv_type='DM' AND (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id=c.conv_id)=2
    FETCH FIRST 1 ROW ONLY;
    UPDATE CHAT_PARTICIPANTS SET is_hidden=0 WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
    COMMIT;
    HTP.p('{"conv_id":'||l_conv_id||'}'); RETURN;
  EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
  END;

  l_conv_id := CONV_SEQ.NEXTVAL;
  INSERT INTO CHAT_CONVERSATIONS (conv_id, conv_type, aus_id) VALUES (l_conv_id, 'DM', l_aus_id);
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin) VALUES (l_conv_id, l_aus_id, 1);
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin) VALUES (l_conv_id, l_partner, 0);
  COMMIT;
  HTP.p('{"conv_id":'||l_conv_id||'}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- ============================================================
-- 10. msCreateGroup  (Nhóm riêng tư, is_public=0)
--    x01 = name | x02 = member_aus_ids CSV | x03 = doc_type (optional) | x04 = doc_no (optional)
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_conv_id NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"error":"auth"}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN; END;

  l_conv_id := CONV_SEQ.NEXTVAL;
  INSERT INTO CHAT_CONVERSATIONS (conv_id, conv_type, name, aus_id, is_public, doc_type, doc_no)
  VALUES (l_conv_id, 'CHANNEL', apex_application.g_x01, l_aus_id, 0,
          NULLIF(apex_application.g_x03,''), NULLIF(apex_application.g_x04,''));
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin) VALUES (l_conv_id, l_aus_id, 1);
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin)
  SELECT l_conv_id, TO_NUMBER(REGEXP_SUBSTR(apex_application.g_x02,'[^,]+',1,LEVEL)), 0
  FROM dual CONNECT BY REGEXP_SUBSTR(apex_application.g_x02,'[^,]+',1,LEVEL) IS NOT NULL
  AND TO_NUMBER(REGEXP_SUBSTR(apex_application.g_x02,'[^,]+',1,LEVEL)) != l_aus_id;
  COMMIT;
  HTP.p('{"conv_id":'||l_conv_id||'}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- ============================================================
-- 11. msCreateChannel  (Channel công khai theo nhóm quyền, is_public=1)
--    x01 = name | x02 = description | x03 = gus_ids CSV (rỗng = Toàn công ty)
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_conv_id NUMBER;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"error":"auth"}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN; END;

  l_conv_id := CONV_SEQ.NEXTVAL;
  INSERT INTO CHAT_CONVERSATIONS (conv_id, conv_type, name, description, aus_id, is_public)
  VALUES (l_conv_id, 'CHANNEL', apex_application.g_x01, NULLIF(apex_application.g_x02,''), l_aus_id, 1);
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin) VALUES (l_conv_id, l_aus_id, 1);

  IF apex_application.g_x03 IS NOT NULL THEN
    INSERT INTO CHAT_CHANNEL_ROLES (conv_id, gus_id)
    SELECT l_conv_id, TO_NUMBER(REGEXP_SUBSTR(apex_application.g_x03,'[^,]+',1,LEVEL))
    FROM dual CONNECT BY REGEXP_SUBSTR(apex_application.g_x03,'[^,]+',1,LEVEL) IS NOT NULL;
  END IF;
  COMMIT;
  HTP.p('{"conv_id":'||l_conv_id||'}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- ============================================================
-- 12. msCreateSubgroup  (nhóm con, kế thừa doc_type/doc_no của cha nếu có)
--    x01 = name | x02 = parent_conv_id | x03 = member_aus_ids CSV
-- ============================================================
DECLARE
  l_aus_id   NUMBER;
  l_conv_id  NUMBER;
  l_parent   NUMBER := TO_NUMBER(apex_application.g_x02);
  l_doc_type VARCHAR2(30);
  l_doc_no   VARCHAR2(60);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"error":"auth"}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN; END;

  SELECT doc_type, doc_no INTO l_doc_type, l_doc_no FROM CHAT_CONVERSATIONS WHERE conv_id = l_parent;

  l_conv_id := CONV_SEQ.NEXTVAL;
  INSERT INTO CHAT_CONVERSATIONS (conv_id, conv_type, name, aus_id, is_public, doc_type, doc_no, parent_conv_id)
  VALUES (l_conv_id, 'CHANNEL', apex_application.g_x01, l_aus_id, 0, l_doc_type, l_doc_no, l_parent);
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin) VALUES (l_conv_id, l_aus_id, 1);
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin)
  SELECT l_conv_id, TO_NUMBER(REGEXP_SUBSTR(apex_application.g_x03,'[^,]+',1,LEVEL)), 0
  FROM dual CONNECT BY REGEXP_SUBSTR(apex_application.g_x03,'[^,]+',1,LEVEL) IS NOT NULL
  AND TO_NUMBER(REGEXP_SUBSTR(apex_application.g_x03,'[^,]+',1,LEVEL)) != l_aus_id;
  COMMIT;
  HTP.p('{"conv_id":'||l_conv_id||'}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- ============================================================
-- 13. msConvAction  (pin/unpin/hide/delete — menu "Thêm" ở chat header)
--    x01 = conv_id | x02 = action ('pin'|'unpin'|'hide'|'delete')
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_conv_id NUMBER := TO_NUMBER(apex_application.g_x01);
  l_action  VARCHAR2(10) := LOWER(apex_application.g_x02);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"error":"auth"}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN; END;

  CASE l_action
    WHEN 'pin'    THEN UPDATE CHAT_PARTICIPANTS SET is_pinned=1 WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
    WHEN 'unpin'  THEN UPDATE CHAT_PARTICIPANTS SET is_pinned=0 WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
    WHEN 'hide'   THEN UPDATE CHAT_PARTICIPANTS SET is_hidden=1 WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
    WHEN 'delete' THEN DELETE FROM CHAT_PARTICIPANTS WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
    ELSE NULL;
  END CASE;
  COMMIT;
  HTP.p('{"ok":true}');
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- ============================================================
-- 14. msGlobalSearchHtml  (⌘K — người/kênh/chứng từ)
--    x01 = search text (>= 1 ký tự)
-- ============================================================
DECLARE
  l_aus_id NUMBER;
  l_search VARCHAR2(200) := LOWER(TRIM(apex_application.g_x01));
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN; END;
  IF l_search IS NULL THEN RETURN; END IF;

  HTP.p('<div class="gs-group">Hội thoại</div>');
  FOR c IN (
    SELECT c.conv_id,
           CASE WHEN c.conv_type='DM' THEN (
                  SELECT REGEXP_REPLACE(NVL(e2.full_name,'Unknown'),'[[:cntrl:]]','')
                  FROM CHAT_PARTICIPANTS p2 JOIN APP_USERS u2 ON u2.aus_id=p2.aus_id
                    JOIN EMPLOYEES e2 ON e2.emp_id=u2.emp_id
                  WHERE p2.conv_id=c.conv_id AND p2.aus_id != l_aus_id FETCH FIRST 1 ROW ONLY)
                WHEN c.conv_type='DOC' THEN NVL(c.name, NVL(c.doc_type,'')||CASE WHEN c.doc_type IS NOT NULL THEN '-' END||c.doc_no)
                ELSE NVL(c.name,'(Không tên)') END AS dn,
           CASE WHEN c.conv_type='DOC' THEN 'Chứng từ' WHEN c.is_public=1 THEN 'Channel'
                WHEN c.conv_type='CHANNEL' THEN 'Nhóm' ELSE 'Cá nhân' END AS kind_label
    FROM CHAT_CONVERSATIONS c JOIN CHAT_PARTICIPANTS p ON p.conv_id=c.conv_id AND p.aus_id=l_aus_id
    WHERE NVL(p.is_hidden,0)=0
      AND LOWER(NVL(c.name, '')) || LOWER(NVL(c.doc_no,'')) LIKE '%'||l_search||'%'
    FETCH FIRST 8 ROWS ONLY
  ) LOOP
    HTP.p('<div class="gs-item" onclick="gsPick('||c.conv_id||')"><span class="gs-ic fa fa-comment-o"></span>'||
          '<span class="gs-name">'||HTF.ESCAPE_SC(c.dn)||'</span><span class="gs-kind">'||c.kind_label||'</span></div>');
  END LOOP;

  HTP.p('<div class="gs-group">Người</div>');
  FOR p IN (SELECT u.aus_id, REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') nm
            FROM APP_USERS u JOIN EMPLOYEES e ON e.emp_id=u.emp_id
            WHERE LOWER(e.full_name) LIKE '%'||l_search||'%' AND u.aus_id != l_aus_id
            FETCH FIRST 6 ROWS ONLY) LOOP
    HTP.p('<div class="gs-item" onclick="gsPickPerson('||p.aus_id||')"><span class="gs-ic fa fa-user"></span>'||
          '<span class="gs-name">'||HTF.ESCAPE_SC(p.nm)||'</span><span class="gs-kind">Cá nhân</span></div>');
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div class="gs-empty">Lỗi: '||REPLACE(SQLERRM,'"','')||'</div>');
END;


-- ============================================================
-- 15. msRoleOptionsHtml  (nạp option "nhóm quyền" thật từ GROUP_USERS
--     cho dropdown ở composeChannel — gọi 1 lần lúc msInit())
-- ============================================================
BEGIN
  OWA_UTIL.MIME_HEADER('text/html', TRUE, 'UTF-8');
  FOR r IN (SELECT gus_id, name FROM GROUP_USERS ORDER BY name) LOOP
    HTP.p('<div class="role-item" data-role="'||r.gus_id||'" data-role-name="'||HTF.ESCAPE_SC(r.name)||
          '" onclick="toggleRole(this)"><span class="ri-check fa fa-check"></span> '||HTF.ESCAPE_SC(r.name)||'</div>');
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  HTP.p('<div style="padding:8px;color:#DC2626">Lỗi: '||REPLACE(SQLERRM,'"','')||'</div>');
END;


-- ============================================================
-- 16. msUploadFile  (upload file thật — base64 qua g_f01, giống messenger/)
--    f01 = mảng chunk base64 (mỗi phần tử <= 30000 ký tự)
--    x01 = conv_id | x02 = tên file gốc
-- Lý do KHÔNG dùng item File Browse / Node: xem messenger/CLAUDE.md mục
-- "Luồng gửi file thật" — apex_application_temp_files RỖNG trong AJAX,
-- và pkg_upload_file chỉ tồn tại trong DB của APEX (gọi từ Node → PLS-00201).
-- Yêu cầu: chạy DDL cột CHAT_MESSENGERS.fil_id (cuối file này) TRƯỚC.
-- ============================================================
DECLARE
  l_aus_id   NUMBER;
  l_conv_id  NUMBER := TO_NUMBER(apex_application.g_x01);
  l_fname    VARCHAR2(400) := apex_application.g_x02;
  l_msg_id   NUMBER;
  l_cnt      NUMBER;
  l_clob     CLOB;
  l_blob     BLOB;
  l_fil_id   NUMBER;
  l_error    VARCHAR2(4000);
  l_from_name VARCHAR2(200);
  l_conv_type VARCHAR2(20);
  l_conv_name VARCHAR2(200);
  l_doc_type  VARCHAR2(30);
  l_doc_no    VARCHAR2(60);
  l_file_name VARCHAR2(1000);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"error":"auth"}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"error":"user_not_found"}'); RETURN; END;
  SELECT COUNT(*) INTO l_cnt FROM CHAT_PARTICIPANTS WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
  IF l_cnt = 0 THEN HTP.p('{"error":"forbidden"}'); RETURN; END IF;

  -- Ghép các chunk base64 (g_f01) thành 1 CLOB rồi giải mã ra BLOB
  DBMS_LOB.CREATETEMPORARY(l_clob, TRUE);
  FOR i IN 1 .. apex_application.g_f01.COUNT LOOP
    DBMS_LOB.WRITEAPPEND(l_clob, LENGTH(apex_application.g_f01(i)), apex_application.g_f01(i));
  END LOOP;
  l_blob := apex_web_service.clobbase642blob(l_clob);
  DBMS_LOB.FREETEMPORARY(l_clob);

  -- p_co_id/p_oun_id/p_user_name đọc THẲNG từ global APEX, không nhận từ client.
  -- Signature thật (xác nhận 2026-06-21): p_Name (không phải p_File_Name),
  -- p_Id NUMBER, p_Ffo_Id VARCHAR2.
  pkg_upload_file.UploadFileChat(
    p_Blob => l_blob, p_Name => l_fname, p_Co_Id => :G_CO_ID, p_Oun_Id => :G_OUN_ID_INS,
    p_Module => '01', p_Table => 'CHAT_MESSENGERS', p_User_Name => :G_USER_NAME,
    p_Id => NULL, p_Ffo_Id => NULL, p_Directory => NULL,
    p_fil_id => l_fil_id, p_error => l_error);
  IF l_error IS NOT NULL THEN
    HTP.p('{"error":"'||REPLACE(l_error,'"','')||'"}'); RETURN;
  END IF;

  l_msg_id := MSG_SEQ.NEXTVAL;
  INSERT INTO CHAT_MESSENGERS (msg_id, conv_id, from_aus_id, body, fil_id, create_date)
  VALUES (l_msg_id, l_conv_id, l_aus_id, NULL, l_fil_id, SYSTIMESTAMP);

  UPDATE CHAT_CONVERSATIONS
  SET last_msg_preview = '[Tệp đính kèm] '||l_fname, last_msg_date = SYSTIMESTAMP
  WHERE conv_id = l_conv_id;
  UPDATE CHAT_PARTICIPANTS SET last_read_msg_id = l_msg_id WHERE conv_id=l_conv_id AND aus_id=l_aus_id;
  COMMIT;

  SELECT REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','')
  INTO l_from_name FROM APP_USERS u JOIN EMPLOYEES e ON e.emp_id=u.emp_id WHERE u.aus_id=l_aus_id;
  SELECT conv_type, NVL(name,''), doc_type, doc_no
  INTO l_conv_type, l_conv_name, l_doc_type, l_doc_no
  FROM CHAT_CONVERSATIONS WHERE conv_id=l_conv_id;
  SELECT file_name INTO l_file_name FROM FILES WHERE fil_id = l_fil_id;

  HTP.p(JSON_OBJECT(
    'msg_id' VALUE l_msg_id, 'conv_id' VALUE l_conv_id, 'from_aus_id' VALUE l_aus_id,
    'from_name' VALUE l_from_name,
    'fil_id' VALUE l_fil_id, 'file_name' VALUE l_file_name, 'file_disp_name' VALUE l_fname,
    'conv_type' VALUE l_conv_type, 'conv_name' VALUE l_conv_name,
    'doc_type' VALUE l_doc_type, 'doc_no' VALUE l_doc_no
    ABSENT ON NULL));
EXCEPTION WHEN OTHERS THEN
  ROLLBACK; HTP.p('{"error":"'||REPLACE(SQLERRM,'"','')||'"}');
END;


-- DDL cột fil_id (CHAT_MESSENGERS) cần TRƯỚC khi deploy callback #16 này —
-- xem docs/schema-additions.sql mục 5.


-- ============================================================
-- 17. msMentionList  (danh sách thành viên hội thoại cho gợi ý @tên)
--    x01 = conv_id   →   {"members":[{"name","ini","hue"}, ...]}
--    Chỉ trả thành viên trong conv (trừ chính mình). KHÔNG lưu tag —
--    composer chèn sentinel @[tên], msMsgThreadHtml highlight lại khi render.
-- ============================================================
DECLARE
  l_aus_id  NUMBER;
  l_conv_id NUMBER := TO_NUMBER(apex_application.g_x01);
  l_json    CLOB := '{"members":[';
  l_first   NUMBER := 1;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN HTP.p('{"members":[]}'); RETURN; END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN HTP.p('{"members":[]}'); RETURN; END;

  FOR r IN (
    SELECT p.aus_id,
           REGEXP_REPLACE(NVL(e.full_name,'Unknown'),'[[:cntrl:]]','') AS nm
    FROM   CHAT_PARTICIPANTS p
    JOIN   APP_USERS u ON u.aus_id = p.aus_id
    JOIN   EMPLOYEES e ON e.emp_id = u.emp_id
    WHERE  p.conv_id = l_conv_id
      AND  p.aus_id <> l_aus_id
    ORDER BY nm
  ) LOOP
    IF l_first = 0 THEN l_json := l_json || ','; END IF;
    l_first := 0;
    l_json := l_json
      || '{"name":"' || REPLACE(REPLACE(r.nm,'\','\\'),'"','\"') || '"'
      || ',"ini":"' || UPPER(SUBSTR(REGEXP_SUBSTR(r.nm,'\S+$'),1,1)) || '"'
      || ',"hue":' || TO_CHAR(MOD(r.aus_id*47,360)) || '}';
  END LOOP;

  l_json := l_json || ']}';
  HTP.p(l_json);
EXCEPTION WHEN OTHERS THEN
  HTP.p('{"members":[]}');
END;
