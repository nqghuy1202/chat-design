# Trao đổi chứng từ — Doc Chat Modal

Tài liệu tổng hợp toàn bộ thiết kế, quyết định kiến trúc, và code cần implement cho tính năng chat gắn với chứng từ ERP.

---

## 1. Tổng quan

Modal "Trao đổi chứng từ" mở ra từ sidebar phải của các ERP page (Lập đơn hàng bán, Phiếu xuất kho, ...). Mỗi chứng từ có riêng một tập hội thoại, không tái sử dụng chéo giữa các chứng từ.

**Prototype thiết kế:** `Chat in ERP System (Apex Oracle 24.2)/`

---

## 2. Kiến trúc tổng thể

```
Mỗi ERP page
  │  window.openDocChatLazy()  ← click nút sidebar
  ▼
Doc Chat Modal (JSX — #APP_FILES#doc-chat/)
  │
  ├── LOAD DATA (apex.server.process → PL/SQL → DB trực tiếp)
  │     docChatConversations, docChatMessages, docChatMembers
  │     ↓
  │     Ajax Callbacks trên MODAL PAGE (không qua Node.js)
  │
  └── REAL-TIME (apex.server.process → PL/SQL → UTL_HTTP → Node.js)
        docChatSend, docChatEvents, docChatTyping, docChatRead
```

### Quyết định kiến trúc quan trọng

| Loại thao tác | Cơ chế | Lý do |
|---|---|---|
| Load conversations, messages, members | `apex.server.process` → PL/SQL → DB | Không cần Node.js, latency thấp |
| Send message | `apex.server.process` → PL/SQL → UTL_HTTP → Node.js | Cần push real-time tới waiters |
| Long-poll events | `apex.server.process` → UTL_HTTP → Node.js 25s | Bắt buộc, in-memory waiter queue |
| Typing, Heartbeat | `apex.server.process` → UTL_HTTP fire-and-forget | Node.js giữ state |
| Create conversation | `apex.server.process` → PL/SQL → DB | Không cần Node.js |

### Tại sao không dùng ORDS trực tiếp từ browser

ORDS trên môi trường này yêu cầu auth riêng (403 Forbidden khi gọi từ browser dù module đã Published, không có privilege mapping). Thay vào đó dùng `apex.server.process` — chuẩn cho app trong APEX, auth qua APEX session.

---

## 3. Database Changes

### 3a. Chạy DDL (user DEV24)

```sql
-- CHAT_CONVERSATIONS: thêm cột doc reference
ALTER TABLE CHAT_CONVERSATIONS ADD (
  doc_type  VARCHAR2(50)   NULL,
  doc_no    VARCHAR2(100)  NULL
);

COMMENT ON COLUMN CHAT_CONVERSATIONS.doc_type
  IS 'Loại chứng từ: SO, PXK, HD, BH... NULL = hội thoại chung';
COMMENT ON COLUMN CHAT_CONVERSATIONS.doc_no
  IS 'Số chứng từ, VD: SO-2601/010. NULL = hội thoại chung';

-- Index cho query lọc theo chứng từ
CREATE INDEX idx_chat_conv_doc
  ON CHAT_CONVERSATIONS(doc_type, doc_no);

-- Bảng online presence (thay thế Node.js in-memory onlineUsers)
CREATE TABLE CHAT_USER_ONLINE (
  aus_id     NUMBER    NOT NULL,
  last_seen  TIMESTAMP NOT NULL,
  CONSTRAINT pk_chat_user_online
    PRIMARY KEY (aus_id),
  CONSTRAINT fk_chat_user_online_aus
    FOREIGN KEY (aus_id) REFERENCES APP_USERS(aus_id)
    ON DELETE CASCADE
);

COMMENT ON TABLE  CHAT_USER_ONLINE
  IS 'Online presence. Heartbeat MERGE vào đây mỗi 20s.';
COMMENT ON COLUMN CHAT_USER_ONLINE.last_seen
  IS 'last_seen trong 35s = online, quá 35s = offline';
```

### 3b. Xác nhận sau khi chạy

```sql
SELECT column_name, data_type, nullable
FROM   user_tab_columns
WHERE  table_name = 'CHAT_CONVERSATIONS'
  AND  column_name IN ('DOC_TYPE', 'DOC_NO');

SELECT table_name FROM user_tables WHERE table_name = 'CHAT_USER_ONLINE';
```

### 3c. Quy ước

- `doc_type IS NULL` + `doc_no IS NULL` → hội thoại chung (chat tổng, Messenger page)
- `doc_type IS NOT NULL` + `doc_no IS NOT NULL` → hội thoại gắn với chứng từ (chỉ hiện trong doc modal)

---

## 4. Backend Changes (chat-server/chat.js)

### 4a. Đã thực hiện

**`GET /conversations/:aus_id`** — thêm filter để ẩn doc-scoped conversations khỏi chat tổng:
```sql
WHERE c.doc_type IS NULL   -- ← đã thêm
```

**`GET /doc-conversations`** — endpoint mới, trả conversations theo doc_type + doc_no + aus_id.

**`POST /create`** — nhận thêm `doc_type` + `doc_no`; DM dedup theo scope (chung vs doc).

### 4b. Endpoint mới trên Node.js

```
GET  /api/chat/doc-conversations?doc_type=SO&doc_no=SO-2601%2F010&aus_id=123
```

*(Endpoint này được dùng bởi APEX callback `docChatConversations` thông qua UTL_HTTP nếu cần, nhưng hiện tại PL/SQL query thẳng DB)*

---

## 5. APEX Setup

### 5a. Modal Page

Tạo một APEX page riêng làm modal (Page Type: **Modal Dialog**). Tất cả Ajax Callbacks của doc-chat đặt trên page này.

**Số page modal:** *(ghi lại sau khi tạo)*

### 5b. Danh sách Ajax Callbacks trên Modal Page

| Callback | x01 | x02 | x03 | x04 | x05 | Relay Node.js? |
|---|---|---|---|---|---|---|
| `docChatConversations` | doc_type | doc_no | aus_id | — | — | Không |
| `docChatMessages` | conv_id | before_id | limit | — | — | Không |
| `docChatMembers` | conv_id | — | — | — | — | Không |
| `docChatCreate` | conv_type | name | members (JSON) | doc_type | doc_no | Không |
| `docChatSend` | conv_id | body | reply_to_msg_id | partner_aus_id | — | **Có** |
| `docChatRead` | conv_id | — | — | — | — | **Có** |
| `docChatTyping` | conv_id | — | — | — | — | **Có** |
| `docChatEvents` | aus_id | — | — | — | — | **Có** (long-poll 25s) |

### 5c. Code PL/SQL — `docChatConversations`

```sql
DECLARE
  l_aus_id   NUMBER        := TO_NUMBER(apex_application.g_x01);
  l_doc_type VARCHAR2(50)  := apex_application.g_x02;
  l_doc_no   VARCHAR2(100) := apex_application.g_x03;
  l_json     CLOB;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  SELECT JSON_OBJECT(
    'conversations' VALUE JSON_ARRAYAGG(
      JSON_OBJECT(
        'conv_id'          VALUE c.conv_id,
        'conv_type'        VALUE c.conv_type,
        'display_name'     VALUE
          CASE c.conv_type
            WHEN 'CHANNEL' THEN c.name
            ELSE (SELECT NVL(e2.full_name,'Unknown')
                  FROM   CHAT_PARTICIPANTS p2
                  JOIN   APP_USERS  u2 ON u2.aus_id = p2.aus_id
                  JOIN   EMPLOYEES  e2 ON e2.emp_id = u2.emp_id
                  WHERE  p2.conv_id = c.conv_id
                    AND  p2.aus_id != l_aus_id
                  FETCH FIRST 1 ROW ONLY)
          END,
        'last_msg_preview' VALUE c.last_msg_preview,
        'last_msg_time'    VALUE TO_CHAR(c.last_msg_date,'HH24:MI'),
        'last_msg_date'    VALUE c.last_msg_date,
        'is_admin'         VALUE p.is_admin,
        'unread_count'     VALUE (
          SELECT COUNT(*) FROM CHAT_MESSENGERS m
          WHERE  m.conv_id     = c.conv_id
            AND  m.delete_date IS NULL
            AND  m.msg_id      > NVL(p.last_read_msg_id, 0)
        ),
        'member_count'     VALUE (
          SELECT COUNT(*) FROM CHAT_PARTICIPANTS p2
          WHERE  p2.conv_id = c.conv_id
        )
        RETURNING CLOB
      )
      ORDER BY c.last_msg_date DESC NULLS LAST
      RETURNING CLOB
    )
    RETURNING CLOB
  )
  INTO l_json
  FROM CHAT_CONVERSATIONS c
  JOIN CHAT_PARTICIPANTS  p
    ON p.conv_id = c.conv_id AND p.aus_id = l_aus_id
  WHERE c.doc_type = l_doc_type
    AND c.doc_no   = l_doc_no;

  HTP.p(NVL(l_json, '{"conversations":[]}'));
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('{"conversations":[],"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;
```

### 5d. Code PL/SQL — `docChatMessages`

```sql
DECLARE
  l_conv_id   NUMBER := TO_NUMBER(apex_application.g_x01);
  l_before_id NUMBER := CASE WHEN apex_application.g_x02 IS NULL
                             THEN NULL
                             ELSE TO_NUMBER(apex_application.g_x02) END;
  l_limit     NUMBER := NVL(TO_NUMBER(apex_application.g_x03), 50);
  l_json      CLOB;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  SELECT JSON_OBJECT(
    'messages' VALUE JSON_ARRAYAGG(
      JSON_OBJECT(
        'msg_id'          VALUE msg_id,
        'from_aus_id'     VALUE from_aus_id,
        'from_name'       VALUE from_name,
        'body'            VALUE body,
        'msg_type'        VALUE msg_type,
        'reply_to_msg_id' VALUE reply_to_msg_id,
        'reply_body'      VALUE reply_body,
        'reply_from_name' VALUE reply_from_name,
        'create_date'     VALUE create_date
        RETURNING CLOB
      )
      ORDER BY msg_id ASC
      RETURNING CLOB
    )
    RETURNING CLOB
  )
  INTO l_json
  FROM (
    SELECT
      m.msg_id,
      m.from_aus_id,
      NVL(e.full_name,'Unknown')           AS from_name,
      CASE WHEN m.delete_date IS NOT NULL
           THEN NULL ELSE m.body END       AS body,
      m.msg_type,
      m.reply_to_msg_id,
      m.create_date,
      CASE WHEN qm.delete_date IS NOT NULL
           THEN '[Tin nhắn đã bị xóa]'
           ELSE qm.body END               AS reply_body,
      NVL(qe.full_name,'Unknown')          AS reply_from_name
    FROM   CHAT_MESSENGERS m
    JOIN   APP_USERS    u   ON u.aus_id  = m.from_aus_id
    JOIN   EMPLOYEES    e   ON e.emp_id  = u.emp_id
    LEFT JOIN CHAT_MESSENGERS qm ON qm.msg_id  = m.reply_to_msg_id
    LEFT JOIN APP_USERS    qu ON qu.aus_id = qm.from_aus_id
    LEFT JOIN EMPLOYEES    qe ON qe.emp_id = qu.emp_id
    WHERE  m.conv_id = l_conv_id
      AND  (l_before_id IS NULL OR m.msg_id < l_before_id)
    ORDER  BY m.msg_id DESC
    FETCH FIRST l_limit ROWS ONLY
  );

  HTP.p(NVL(l_json, '{"messages":[]}'));
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('{"messages":[],"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;
```

### 5e. Code PL/SQL — `docChatMembers`

```sql
DECLARE
  l_conv_id NUMBER := TO_NUMBER(apex_application.g_x01);
  l_json    CLOB;
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');

  SELECT JSON_OBJECT(
    'members' VALUE JSON_ARRAYAGG(
      JSON_OBJECT(
        'aus_id'    VALUE p.aus_id,
        'full_name' VALUE NVL(e.full_name,'Unknown'),
        'user_name' VALUE u.user_name,
        'is_admin'  VALUE p.is_admin,
        'presence'  VALUE
          CASE WHEN o.last_seen >= SYSTIMESTAMP - INTERVAL '35' SECOND
               THEN 'online' ELSE 'offline' END
        RETURNING CLOB
      )
      ORDER BY p.is_admin DESC, e.full_name
      RETURNING CLOB
    )
    RETURNING CLOB
  )
  INTO l_json
  FROM   CHAT_PARTICIPANTS p
  JOIN   APP_USERS   u  ON u.aus_id = p.aus_id
  JOIN   EMPLOYEES   e  ON e.emp_id = u.emp_id
  LEFT JOIN CHAT_USER_ONLINE o ON o.aus_id = p.aus_id
  WHERE  p.conv_id = l_conv_id;

  HTP.p(NVL(l_json, '{"members":[]}'));
EXCEPTION
  WHEN OTHERS THEN
    HTP.p('{"members":[],"error":"' || REPLACE(SQLERRM,'"','') || '"}');
END;
```

### 5f. Callback `chatHeartbeat` (Page 0) — cập nhật

Bỏ UTL_HTTP, ghi thẳng vào `CHAT_USER_ONLINE`:

```sql
BEGIN
  OWA_UTIL.MIME_HEADER('application/json', TRUE, 'UTF-8');
  IF :G_AUS_ID IS NULL THEN
    HTP.p('{"status":"skip"}'); RETURN;
  END IF;

  MERGE INTO CHAT_USER_ONLINE o
  USING (SELECT :G_AUS_ID AS aus_id FROM DUAL) src
    ON  (o.aus_id = src.aus_id)
  WHEN MATCHED     THEN UPDATE SET last_seen = SYSTIMESTAMP
  WHEN NOT MATCHED THEN INSERT (aus_id, last_seen)
                        VALUES (src.aus_id, SYSTIMESTAMP);
  COMMIT;

  HTP.p('{"status":"ok"}');
END;
```

---

## 6. Frontend — File Structure

Upload lên APEX static files: `#APP_FILES#doc-chat/`

```
doc-chat/
  doc-chat.css            ← copy styles.css từ prototype
  icons.jsx               ← copy icons.jsx từ prototype
  conversation-list.jsx   ← adapt từ prototype
  chat-thread.jsx         ← adapt từ prototype
  info-panel.jsx          ← adapt: nhận doc_fields từ window.DOC_CHAT_CONTEXT
  empty-state.jsx         ← adapt: dùng doc_no, doc_label từ context
  doc-chat-app.jsx        ← entry point: expose window.openDocChat()
```

### Utility function gọi callbacks

```javascript
const MODAL_PAGE_ID = 10022710201;

function apexCall(processName, params = {}) {
  return new Promise((resolve, reject) => {
    apex.server.process(processName, {
      x01: params.x01 || '',
      x02: params.x02 || '',
      x03: params.x03 || '',
      x04: params.x04 || '',
      x05: params.x05 || '',
    }, {
      dataType: 'json',
      pageId:   MODAL_PAGE_ID,
      success:  resolve,
      error:    (_, err) => reject(new Error(err))
    });
  });
}
```

---

## 7. Tích hợp vào ERP Page

### JavaScript — Execute when Page Loads

```javascript
// 1. Context của chứng từ hiện tại
window.DOC_CHAT_CONTEXT = {
  doc_type:   'SO',
  doc_no:     '&P15_SO_NO.',
  doc_label:  'Đơn hàng bán',
  doc_status: '&P15_STATUS.',
  doc_total:  '&P15_TOTAL_AMOUNT.',
  doc_fields: [
    ['Đối tượng',    '&P15_CUSTOMER_NAME.'],
    ['Ngày đơn',     '&P15_ORDER_DATE.'],
    ['Ngày xuất',    '&P15_EXPECTED_DATE.'],
    ['Kho xuất',     '&P15_WAREHOUSE.'],
    ['Thanh toán',   '&P15_PAYMENT_TERMS.'],
    ['Số dòng hàng', '&P15_LINE_COUNT.'],
  ],
  doc_quick_actions: ['open', 'approve', 'print', 'pdf']
};

// 2. Lazy load modal khi cần
window.openDocChatLazy = function() {
  if (window.openDocChat) {
    window.openDocChat(window.DOC_CHAT_CONTEXT);
    return;
  }
  var base = '#APP_FILES#doc-chat/';
  var files = ['icons.jsx','conversation-list.jsx','chat-thread.jsx',
               'info-panel.jsx','empty-state.jsx','doc-chat-app.jsx'];

  var css = document.createElement('link');
  css.rel = 'stylesheet'; css.href = base + 'doc-chat.css';
  document.head.appendChild(css);

  var idx = 0;
  function loadNext() {
    if (idx >= files.length) {
      window.openDocChat(window.DOC_CHAT_CONTEXT);
      return;
    }
    fetch(base + files[idx]).then(r => r.text()).then(code => {
      var s = document.createElement('script');
      s.textContent = Babel.transform(code, {
        presets: ['react'],
        filename: files[idx]
      }).code;
      document.body.appendChild(s);
      idx++; loadNext();
    });
  }
  loadNext();
};
```

### Dynamic Action — nút mở modal

| Field | Giá trị |
|---|---|
| Event | Click |
| Selection Type | jQuery Selector |
| jQuery Selector | `#Btn_DocChat` (hoặc `.erp-sidebar-item.chat-trigger`) |
| Action | Execute JavaScript Code |
| Code | `window.openDocChatLazy();` |

---

## 8. Layout Modal (3 Panes)

```
┌─────────────────────────────────────────────────────────────────────┐
│ [Icon] Trao đổi chứng từ  [# SO-2601/010 · Đơn hàng bán]  [Filter][X] │
├───────────────────────┬─────────────────────────┬───────────────────┤
│  Danh sách hội thoại  │     Luồng chat          │   Info Panel      │
│  ~320px               │     (flex 1)            │   ~320px (toggle) │
│                       │                         │                   │
│  [Search]             │  [Header group/DM]      │  Chứng từ card    │
│  [Tất cả][Chưa đọc]  │  [Pinned message]       │  Thao tác nhanh   │
│  [@Tôi]               │                         │  Thành viên       │
│                       │  [Messages...]          │  Files đã share   │
│  NHÓM TRAO ĐỔI        │                         │  Chứng từ liên    │
│  ─ Duyệt giá...   3  │  [Typing indicator]     │  quan             │
│  ─ Kho K01MT...   1  │                         │                   │
│                       │  [Composer]             │                   │
│  TRAO ĐỔI CÁ NHÂN    │  [Attach][Img][@][#][😊]│                   │
│  ─ Nguyễn Văn Anh    │  [Gửi]                  │                   │
│                       │                         │                   │
│  [+ Tạo nhóm mới]    │                         │                   │
└───────────────────────┴─────────────────────────┴───────────────────┘
```

---

## 9. Việc còn lại (TODO)

- [ ] Chạy DDL trên Oracle DB (mục 3a)
- [ ] Deploy `chat.js` mới lên Server B → `pm2 restart chat-server`
- [ ] Tạo APEX Modal Dialog page → ghi lại số page
- [ ] Tạo 8 Ajax Callbacks trên modal page (mục 5b)
- [ ] Cập nhật `chatHeartbeat` trên Page 0 (mục 5f)
- [ ] Viết 6 file JSX + CSS cho doc-chat modal
- [ ] Upload lên APEX static files `#APP_FILES#doc-chat/`
- [ ] Thêm JS context + nút trigger vào từng ERP page cần thiết
- [ ] Test end-to-end

---

## 10. Thông tin kỹ thuật

| Thông tin | Giá trị |
|---|---|
| Server B (Node.js) | `172.25.10.38:3410` |
| Server A (APEX/ORDS) | `erp.greensys.vn:8211` |
| Oracle DB | `172.25.10.18:1521/pdbgc19c` |
| Schema | `DEV24` |
| ORDS URL pattern | `/ords/dev/` |
| Node.js process | `pm2 chat-server` |
| APEX version | `24.2` |
| Modal Page ID | `10022710201` |
