-- ===========================================================
-- DOC CHAT MODAL — APEX Ajax Callbacks
-- Tất cả tạo là PAGE-LEVEL AJAX CALLBACK trên page 10022710201
-- (Page 10022710201 → Processing → Ajax Callback)
-- ===========================================================
--
-- LÝ DO: Các callback này ONLY được gọi từ JSX chạy trên chính page 10022710201
-- (APEX Modal Dialog). Dùng page-level callback để dễ kiểm soát và bảo trì;
-- apex.server.process({ pageId: 10022710201 }) hoạt động chính xác vì call và
-- callback cùng nằm trên một page.
--
-- Callbacks relay → Node.js dùng :APP_USER để lấy aus_id (an toàn hơn :G_AUS_ID).
-- Callbacks đọc DB trực tiếp dùng aus_id từ g_x01 hoặc không cần auth.
--
-- LOAD ORDER trong doc-chat-app.jsx:
--   apexCall()    → apex.server.process({ pageId: 10022710201 })  ← 8 callbacks này
--   apexCallApp() → apex.server.process() không có pageId          ← chatContactList (App Process)
-- ===========================================================


-- -----------------------------------------------------------
-- 1. docChatConversations
--    x01=aus_id | x02=doc_type | x03=doc_no
--    Trả danh sách hội thoại gắn với chứng từ này.
-- -----------------------------------------------------------
DECLARE
  l_aus_id   NUMBER        := TO_NUMBER(NVL(apex_application.g_x01,'0'));
  l_doc_type VARCHAR2(50)  := TRIM(apex_application.g_x02);
  l_doc_no   VARCHAR2(100) := TRIM(apex_application.g_x03);
  l_json     VARCHAR2(32767);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF l_aus_id = 0 OR l_doc_type IS NULL OR l_doc_no IS NULL THEN
    HTP.p('{"conversations":[]}'); RETURN;
  END IF;

  -- Subqueries tham chiếu remote tables (APP_USERS, EMPLOYEES) chạy trong correlated subquery
  -- Oracle sẽ execute chúng per-row nên không cần MATERIALIZE ở đây.
  -- display_name và partner_aus_id chỉ cần NVL, không dùng REGEXP_REPLACE (tránh ORA-02000).
  SELECT NVL(
    (
      SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
          'conv_id'          VALUE c.conv_id,
          'conv_type'        VALUE c.conv_type,
          'display_name'     VALUE
            CASE c.conv_type
              WHEN 'CHANNEL' THEN NVL(c.name, '(Không tên)')
              ELSE (
                SELECT NVL(e2.full_name, 'Unknown')
                FROM   CHAT_PARTICIPANTS p2
                JOIN   APP_USERS  u2 ON u2.aus_id = p2.aus_id
                JOIN   EMPLOYEES  e2 ON e2.emp_id = u2.emp_id
                WHERE  p2.conv_id = c.conv_id
                  AND  p2.aus_id != l_aus_id
                FETCH FIRST 1 ROW ONLY
              )
            END,
          'partner_aus_id'   VALUE
            CASE c.conv_type
              WHEN 'DM' THEN (
                SELECT p2.aus_id
                FROM   CHAT_PARTICIPANTS p2
                WHERE  p2.conv_id = c.conv_id
                  AND  p2.aus_id != l_aus_id
                FETCH FIRST 1 ROW ONLY
              )
              ELSE NULL
            END,
          'last_msg_preview' VALUE c.last_msg_preview,
          'last_msg_time'    VALUE TO_CHAR(c.last_msg_date, 'HH24:MI'),
          'last_msg_date'    VALUE TO_CHAR(c.last_msg_date, 'YYYY-MM-DD"T"HH24:MI:SS'),
          'is_admin'         VALUE p.is_admin,
          'member_count'     VALUE (
            SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3
            WHERE  p3.conv_id = c.conv_id
          ),
          'unread_count'     VALUE (
            SELECT COUNT(*) FROM CHAT_MESSENGERS m
            WHERE  m.conv_id    = c.conv_id
              AND  m.delete_date IS NULL
              AND  m.msg_id     > NVL(p.last_read_msg_id, 0)
          )
          ABSENT ON NULL
          RETURNING CLOB
        )
        ORDER BY c.last_msg_date DESC NULLS LAST
        RETURNING CLOB
      )
      FROM CHAT_CONVERSATIONS c
      JOIN CHAT_PARTICIPANTS  p
        ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
      WHERE c.doc_type = l_doc_type
        AND c.doc_no   = l_doc_no
    ),
    JSON_ARRAY()
  )
  INTO l_json FROM DUAL;

  HTP.p('{"conversations":' || l_json || '}');
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('{"conversations":[],"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- -----------------------------------------------------------
-- 2. docChatMessages
--    x01=conv_id | x02=before_id (rỗng = lấy mới nhất) | x03=limit (mặc định 50)
--    Dùng MATERIALIZE để tránh ORA-02000 (REGEXP_REPLACE trên remote columns).
-- -----------------------------------------------------------
DECLARE
  l_conv_id   NUMBER := TO_NUMBER(NVL(apex_application.g_x01,'0'));
  l_before_id NUMBER := CASE WHEN TRIM(apex_application.g_x02) IS NULL
                             THEN NULL
                             ELSE TO_NUMBER(apex_application.g_x02) END;
  l_limit     NUMBER := NVL(TO_NUMBER(NULLIF(TRIM(apex_application.g_x03),'0')), 50);
  l_json      VARCHAR2(32767);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF l_conv_id = 0 THEN
    HTP.p('{"messages":[]}'); RETURN;
  END IF;

  WITH msg_raw AS (
    SELECT /*+ MATERIALIZE */
      m.msg_id,
      m.from_aus_id,
      NVL(e.full_name,  'Unknown') AS from_name,
      m.body,
      m.msg_type,
      m.reply_to_msg_id,
      m.delete_date,
      m.create_date,
      qm.body                      AS reply_body,
      qm.delete_date               AS reply_deleted,
      NVL(qe.full_name, 'Unknown') AS reply_from_name
    FROM (
      SELECT * FROM CHAT_MESSENGERS
      WHERE  conv_id = l_conv_id
        AND  (l_before_id IS NULL OR msg_id < l_before_id)
      ORDER  BY msg_id DESC
      FETCH FIRST l_limit ROWS ONLY
    ) m
    JOIN     APP_USERS    u   ON u.aus_id  = m.from_aus_id
    JOIN     EMPLOYEES    e   ON e.emp_id  = u.emp_id
    LEFT JOIN CHAT_MESSENGERS qm ON qm.msg_id  = m.reply_to_msg_id
    LEFT JOIN APP_USERS    qu  ON qu.aus_id = qm.from_aus_id
    LEFT JOIN EMPLOYEES    qe  ON qe.emp_id = qu.emp_id
  )
  SELECT NVL(
    (
      SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
          'msg_id'          VALUE msg_id,
          'from_aus_id'     VALUE from_aus_id,
          'from_name'       VALUE REGEXP_REPLACE(from_name,       '[[:cntrl:]]', ''),
          'body'            VALUE CASE WHEN delete_date IS NOT NULL THEN NULL ELSE body END,
          'msg_type'        VALUE msg_type,
          'reply_to_msg_id' VALUE reply_to_msg_id,
          'reply_body'      VALUE CASE
                              WHEN reply_to_msg_id IS NULL THEN NULL
                              WHEN reply_deleted  IS NOT NULL THEN '[Tin nhắn đã bị xóa]'
                              ELSE reply_body END,
          'reply_from_name' VALUE CASE WHEN reply_to_msg_id IS NOT NULL
                              THEN REGEXP_REPLACE(reply_from_name, '[[:cntrl:]]', '')
                              ELSE NULL END,
          'create_date'     VALUE TO_CHAR(create_date, 'YYYY-MM-DD"T"HH24:MI:SS')
          ABSENT ON NULL
          RETURNING CLOB
        )
        ORDER BY msg_id ASC
        RETURNING CLOB
      )
      FROM msg_raw
    ),
    JSON_ARRAY()
  )
  INTO l_json FROM DUAL;

  HTP.p('{"messages":' || l_json || '}');
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('{"messages":[],"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- -----------------------------------------------------------
-- 3. docChatMembers
--    x01=conv_id
--    Dùng MATERIALIZE + biến PL/SQL cho INTERVAL (tránh ORA-02000 khi join remote tables).
-- -----------------------------------------------------------
DECLARE
  l_conv_id       NUMBER    := TO_NUMBER(NVL(apex_application.g_x01,'0'));
  l_online_cutoff TIMESTAMP := SYSTIMESTAMP - INTERVAL '35' SECOND;  -- PL/SQL var, không push xuống remote
  l_json          VARCHAR2(32767);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF l_conv_id = 0 THEN
    HTP.p('{"members":[]}'); RETURN;
  END IF;

  WITH members_raw AS (
    SELECT /*+ MATERIALIZE */
      p.aus_id,
      p.is_admin,
      REGEXP_REPLACE(NVL(e.full_name, 'Unknown'), '[[:cntrl:]]', '') AS full_name,
      REGEXP_REPLACE(u.user_name,                 '[[:cntrl:]]', '') AS user_name
    FROM CHAT_PARTICIPANTS p
    JOIN APP_USERS  u ON u.aus_id = p.aus_id
    JOIN EMPLOYEES  e ON e.emp_id = u.emp_id
    WHERE p.conv_id = l_conv_id
  )
  SELECT NVL(
    (
      SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
          'aus_id'    VALUE r.aus_id,
          'full_name' VALUE r.full_name,
          'user_name' VALUE r.user_name,
          'is_admin'  VALUE r.is_admin,
          'presence'  VALUE CASE WHEN o.last_seen >= l_online_cutoff THEN 'online' ELSE 'offline' END
          RETURNING CLOB
        )
        ORDER BY r.is_admin DESC, r.full_name
        RETURNING CLOB
      )
      FROM members_raw r
      LEFT JOIN CHAT_USER_ONLINE o ON o.aus_id = r.aus_id
    ),
    JSON_ARRAY()
  )
  INTO l_json FROM DUAL;

  HTP.p('{"members":' || l_json || '}');
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('{"members":[],"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- -----------------------------------------------------------
-- 4. docChatCreate
--    x01=conv_type | x02=name | x03=members JSON array | x04=doc_type | x05=doc_no
--    Ghi thẳng vào DB, không qua Node.js.
--    DM dedup: nếu DM cùng 2 người + cùng doc scope đã tồn tại → trả conv_id cũ.
-- -----------------------------------------------------------
DECLARE
  l_aus_id     NUMBER;
  l_partner_id NUMBER;
  l_existing   NUMBER;
  l_conv_id    NUMBER;
  l_conv_type  VARCHAR2(10)  := TRIM(apex_application.g_x01);
  l_name       VARCHAR2(200) := TRIM(apex_application.g_x02);
  l_members    VARCHAR2(4000) := NVL(NULLIF(TRIM(apex_application.g_x03),''), '[]');
  l_doc_type   VARCHAR2(50)  := NULLIF(TRIM(apex_application.g_x04),'');
  l_doc_no     VARCHAR2(100) := NULLIF(TRIM(apex_application.g_x05),'');
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"error":"auth"}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  IF l_conv_type NOT IN ('DM','CHANNEL') THEN
    HTP.p('{"error":"invalid_conv_type"}'); RETURN;
  END IF;

  -- DM dedup
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
        AND  NVL(c.doc_type,'__NULL__') = NVL(l_doc_type,'__NULL__')
        AND  NVL(c.doc_no,'__NULL__')   = NVL(l_doc_no,'__NULL__')
        AND  (SELECT COUNT(*) FROM CHAT_PARTICIPANTS p3 WHERE p3.conv_id = c.conv_id) = 2
      FETCH FIRST 1 ROW ONLY;

      HTP.p('{"conv_id":' || l_existing || ',"is_new":false}');
      RETURN;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
  END IF;

  -- Tạo hội thoại mới
  -- Lấy NEXTVAL trước vào biến để tránh ORA-22816 (RETURNING INTO không support trong Application Process)
  l_conv_id := CONV_SEQ.NEXTVAL;
  INSERT INTO CHAT_CONVERSATIONS
    (conv_id, conv_type, name, aus_id, doc_type, doc_no, created_by, create_date)
  VALUES
    (l_conv_id, l_conv_type, l_name, l_aus_id, l_doc_type, l_doc_no, :APP_USER, SYSTIMESTAMP);

  -- Người tạo: is_admin=1
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin, created_by, create_date)
  VALUES (l_conv_id, l_aus_id, 1, :APP_USER, SYSTIMESTAMP);

  -- Thêm các thành viên còn lại (is_admin=0)
  INSERT INTO CHAT_PARTICIPANTS (conv_id, aus_id, is_admin, created_by, create_date)
  SELECT l_conv_id, value, 0, :APP_USER, SYSTIMESTAMP
  FROM JSON_TABLE(l_members, '$[*]' COLUMNS (value NUMBER PATH '$'))
  WHERE value != l_aus_id;

  COMMIT;
  HTP.p('{"conv_id":' || l_conv_id || ',"is_new":true}');
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    HTP.p('{"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;


-- -----------------------------------------------------------
-- 5. docChatSend
--    x01=conv_id | x02=body | x03=reply_to_msg_id | x04=partner_aus_id
--    Relay → Node.js POST /api/chat/send
-- -----------------------------------------------------------
DECLARE
  l_aus_id  NUMBER;
  l_url     VARCHAR2(500);
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
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"error":"user_not_found"}'); RETURN;
  END;

  l_payload := JSON_OBJECT(
    'conv_id'         VALUE TO_NUMBER(apex_application.g_x01),
    'aus_id'          VALUE l_aus_id,
    'username'        VALUE :APP_USER,
    'body'            VALUE apex_application.g_x02,
    'reply_to_msg_id' VALUE NULLIF(TRIM(apex_application.g_x03), ''),
    'partner_aus_id'  VALUE NULLIF(TRIM(apex_application.g_x04), '')
    ABSENT ON NULL
  );

  UTL_HTTP.SET_TRANSFER_TIMEOUT(10);
  l_url := 'http://172.25.10.38:3410/api/chat/send';
  l_req  := UTL_HTTP.BEGIN_REQUEST(l_url, 'POST', 'HTTP/1.1');
  UTL_HTTP.SET_HEADER(l_req, 'Content-Type',   'application/json; charset=utf-8');
  UTL_HTTP.SET_HEADER(l_req, 'Connection',     'close');
  UTL_HTTP.SET_HEADER(l_req, 'Content-Length',  TO_CHAR(UTL_RAW.LENGTH(UTL_RAW.CAST_TO_RAW(l_payload))));
  UTL_HTTP.WRITE_RAW(l_req, UTL_RAW.CAST_TO_RAW(l_payload));
  l_resp := UTL_HTTP.GET_RESPONSE(l_req);
  BEGIN
    LOOP UTL_HTTP.READ_TEXT(l_resp, l_buffer, 32767); l_body := l_body || l_buffer; END LOOP;
  EXCEPTION WHEN UTL_HTTP.END_OF_BODY THEN NULL;
  END;
  UTL_HTTP.END_RESPONSE(l_resp);

  -- Relay nguyên response của Node.js (kể cả {"error":"..."} khi 5xx)
  IF l_resp.status_code BETWEEN 200 AND 299 THEN
    HTP.p(l_body);
  ELSE
    HTP.p('{"error":"Node ' || l_resp.status_code || ': ' || REPLACE(l_body, '"', '''') || '"}');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
    -- ORA-29273 thường do Node.js trả 5xx hoặc mất kết nối
    HTP.p('{"error":"UTL_HTTP: ' || REPLACE(SQLERRM, '"', '''') || '"}');
END;


-- -----------------------------------------------------------
-- 6. docChatRead
--    x01=conv_id
--    Relay → Node.js POST /api/chat/read/:conv_id/:aus_id
-- -----------------------------------------------------------
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
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"status":"skip"}'); RETURN;
  END;

  IF TRIM(apex_application.g_x01) IS NULL THEN
    HTP.p('{"error":"conv_id required"}'); RETURN;
  END IF;

  l_url := 'http://172.25.10.38:3410/api/chat/read/'
           || apex_application.g_x01 || '/' || TO_CHAR(l_aus_id);
  UTL_HTTP.SET_TRANSFER_TIMEOUT(5);
  l_req  := UTL_HTTP.BEGIN_REQUEST(l_url, 'POST', 'HTTP/1.1');
  UTL_HTTP.SET_HEADER(l_req, 'Content-Length', '0');
  l_resp := UTL_HTTP.GET_RESPONSE(l_req);
  BEGIN LOOP UTL_HTTP.READ_TEXT(l_resp, l_tmp, 4000); l_buf := l_buf || l_tmp; END LOOP;
  EXCEPTION WHEN UTL_HTTP.END_OF_BODY THEN NULL; END;
  UTL_HTTP.END_RESPONSE(l_resp);
  HTP.p(l_buf);
EXCEPTION
  WHEN OTHERS THEN
    BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
    HTP.p('{"status":"skip"}');
END;


-- -----------------------------------------------------------
-- 7. docChatTyping
--    x01=conv_id
--    Relay → Node.js POST /api/chat/typing/:conv_id/:aus_id
-- -----------------------------------------------------------
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
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"status":"skip"}'); RETURN;
  END;

  IF TRIM(apex_application.g_x01) IS NULL THEN
    HTP.p('{"error":"conv_id required"}'); RETURN;
  END IF;

  l_url := 'http://172.25.10.38:3410/api/chat/typing/'
           || apex_application.g_x01 || '/' || TO_CHAR(l_aus_id);
  UTL_HTTP.SET_TRANSFER_TIMEOUT(5);
  l_req  := UTL_HTTP.BEGIN_REQUEST(l_url, 'POST', 'HTTP/1.1');
  UTL_HTTP.SET_HEADER(l_req, 'Content-Length', '0');
  l_resp := UTL_HTTP.GET_RESPONSE(l_req);
  BEGIN LOOP UTL_HTTP.READ_TEXT(l_resp, l_tmp, 4000); l_buf := l_buf || l_tmp; END LOOP;
  EXCEPTION WHEN UTL_HTTP.END_OF_BODY THEN NULL; END;
  UTL_HTTP.END_RESPONSE(l_resp);
  HTP.p(l_buf);
EXCEPTION
  WHEN OTHERS THEN
    BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
    HTP.p('{"status":"skip"}');
END;


-- -----------------------------------------------------------
-- 8. docChatEvents  (long-poll 25s)
--    x01=aus_id (ignored — dùng :APP_USER để an toàn)
--    Relay → Node.js GET /api/chat/events/:aus_id
-- -----------------------------------------------------------
DECLARE
  l_aus_id NUMBER;
  l_url    VARCHAR2(500);
  l_req    UTL_HTTP.REQ;
  l_resp   UTL_HTTP.RESP;
  l_body   VARCHAR2(32767) := '';
  l_buffer VARCHAR2(32767);
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  IF :APP_USER IS NULL OR :APP_USER IN ('nobody','NOBODY') THEN
    HTP.p('{"events":[]}'); RETURN;
  END IF;
  BEGIN
    SELECT aus_id INTO l_aus_id FROM APP_USERS
    WHERE LOWER(user_name) = LOWER(:APP_USER);
  EXCEPTION WHEN NO_DATA_FOUND THEN
    HTP.p('{"events":[]}'); RETURN;
  END;

  l_url := 'http://172.25.10.38:3410/api/chat/events/' || TO_CHAR(l_aus_id);
  UTL_HTTP.SET_TRANSFER_TIMEOUT(28);
  l_req  := UTL_HTTP.BEGIN_REQUEST(l_url, 'GET', 'HTTP/1.1');
  UTL_HTTP.SET_HEADER(l_req, 'Connection', 'close');
  l_resp := UTL_HTTP.GET_RESPONSE(l_req);
  BEGIN
    LOOP UTL_HTTP.READ_TEXT(l_resp, l_buffer, 32767); l_body := l_body || l_buffer; END LOOP;
  EXCEPTION WHEN UTL_HTTP.END_OF_BODY THEN NULL;
  END;
  UTL_HTTP.END_RESPONSE(l_resp);
  HTP.p(l_body);
EXCEPTION
  WHEN OTHERS THEN
    BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
    HTP.p('{"events":[]}');
END;
