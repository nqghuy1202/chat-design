---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 1
research_type: 'technical'
research_topic: 'Thêm cột fil_id vào CHAT_MESSENGERS để biểu diễn tin nhắn file/ảnh trong messenger/'
research_goals: 'Đánh giá tính đúng đắn dữ liệu (race condition, FK, 2 nguồn sự thật fil_id/owner_id), hiệu năng truy vấn JOIN, và checklist migration/rollout an toàn cho thiết kế cột fil_id song song với owner_id hiện có.'
user_name: 'Gia Huy'
date: '2026-06-18'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-06-18
**Author:** Gia Huy
**Research Type:** technical

---

## Research Overview

Nghiên cứu đánh giá đề xuất thêm cột `fil_id` (nullable, FK) vào `CHAT_MESSENGERS` để biểu diễn tin nhắn file/ảnh trong module `messenger/`, giữ song song với cơ chế `owner_id+owner_table_name` (polymorphic association) hiện có trên bảng file. Phạm vi tập trung vào 3 trục đã thống nhất với người yêu cầu: tính đúng đắn dữ liệu, hiệu năng truy vấn, và migration/rollout an toàn trên hệ thống Oracle/APEX production.

Kết luận chính: hướng đi `fil_id` là **đúng về lý thuyết thiết kế dữ liệu** (thay polymorphic association bằng direct FK), nhưng việc **giữ song song `owner_id`** tạo ra 2 nguồn sự thật có thể lệch nhau, và luồng 3 bước hiện tại (`/send` → upload callback → `/attach`) là một dạng **Dual Write Problem** kinh điển — có race condition thực sự khiến client khác có thể thấy tin nhắn "rỗng" tạm thời hoặc kẹt vĩnh viễn nếu một bước thất bại. Hiệu năng JOIN không phải là rủi ro đáng kể. Xem **Tổng hợp đánh giá thiết kế (ADR-style)** và **Research Synthesis** bên dưới để biết bảng rủi ro đầy đủ và khuyến nghị triển khai cụ thể.

---

<!-- Content will be appended sequentially through research workflow steps -->

## Technical Research Scope Confirmation

**Research Topic:** Thêm cột fil_id vào CHAT_MESSENGERS để biểu diễn tin nhắn file/ảnh trong messenger/
**Research Goals:** Đánh giá tính đúng đắn dữ liệu (race condition, FK, 2 nguồn sự thật fil_id/owner_id), hiệu năng truy vấn JOIN, và checklist migration/rollout an toàn cho thiết kế cột fil_id song song với owner_id hiện có.

**Technical Research Scope:**

- Phân tích kiến trúc dữ liệu - mô hình fil_id song song owner_id, race condition giữa các bước tạo msg → upload file → broadcast SSE
- Phương án triển khai - FK constraint, ON DELETE behavior, đồng bộ 2 chiều tham chiếu
- Hiệu năng - so sánh JOIN qua fil_id (PK lookup) với JOIN qua owner_id+owner_table_name
- Tích hợp hệ thống - ràng buộc đặc thù APEX/Oracle (MATERIALIZE hint, HTP.p escaping, thứ tự DDL/code khi deploy)
- Migration/rollout - checklist deploy an toàn theo đúng thứ tự DDL trước code

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-06-18

---

## Technology Stack Analysis

### Mô hình quan hệ dữ liệu: Direct FK vs Polymorphic Association

`owner_id + owner_table_name` trên bảng file hiện tại là dạng **Polymorphic Association** — một anti-pattern SQL được tài liệu hóa rộng rãi (chương "Polymorphic Associations" trong sách *SQL Antipatterns*, và GitLab database guidelines liệt nó vào danh sách cần tránh khi thiết kế schema mới).

_Vấn đề cốt lõi:_ không thể khai báo `FOREIGN KEY` thật trên `owner_id` vì cột này tham chiếu tới nhiều bảng khác nhau tùy giá trị `owner_table_name` — Oracle/mọi RDBMS đều không hỗ trợ "conditional FK". Hệ quả là toàn vẹn dữ liệu (referential integrity) phải tự đảm bảo ở tầng ứng dụng, không có DB-level guarantee.

_fil_id trên CHAT_MESSENGERS_ là hướng ngược lại — **Exclusive Arc / Direct Foreign Key** — đúng theo khuyến nghị thay thế polymorphic association: thay vì 1 cột đa hình, dùng FK trực tiếp trỏ đúng 1 bảng. Đây là hướng đi đúng về mặt lý thuyết thiết kế dữ liệu, NHƯNG vì giữ song song `owner_id` (không xóa), hệ thống sẽ có **cả hai mô hình cùng tồn tại** cho cùng một quan hệ message↔file — đây là điểm rủi ro chính sẽ phân tích sâu ở bước tiếp theo (tính đúng đắn dữ liệu).

_Khuyến nghị sơ bộ:_ nếu mục tiêu cuối là tận dụng FK thật, nên coi `fil_id` là **nguồn sự thật chính (source of truth)** cho quan hệ message↔file, và `owner_id` trên bảng file trở thành dữ liệu thứ cấp/lịch sử — không để cả hai cùng được ứng dụng ghi/đọc độc lập.

_Source: [GitLab Polymorphic Associations](https://docs.gitlab.com/development/database/polymorphic_associations/), [SQL Antipatterns Ch.7](https://www.oreilly.com/library/view/sql-antipatterns/9781680500073/f_0043.html)_

### FK Constraint và ON DELETE Behavior trên Oracle

Oracle cho phép `FOREIGN KEY ... ON DELETE SET NULL` chỉ khi cột FK **nullable** — đúng với thiết kế `fil_id` (NULL = tin nhắn text thường). Hai lựa chọn thực tế:

- **`ON DELETE SET NULL`**: nếu file bị xóa, `fil_id` tự về NULL → tin nhắn hiển thị lại như tin nhắn text rỗng (mất ngữ cảnh "đây từng là file"). Phù hợp nếu xóa file là thao tác hợp lệ và chấp nhận được trải nghiệm này.
- **`ON DELETE NO ACTION` (mặc định)** + xử lý xóa mềm (soft-delete) ở bảng file: an toàn hơn cho lịch sử chat — tin nhắn vẫn hiển thị "Tệp đã bị xóa" thay vì biến mất hoàn toàn. Đây là pattern phổ biến hơn cho hệ thống nhắn tin (Zalo/Messenger không cho xóa file đã gửi mà không để lại dấu vết).

_Khuyến nghị:_ dùng `NO ACTION` + cột `is_deleted`/`deleted_date` trên bảng file, KHÔNG dùng `SET NULL` — vì `SET NULL` sẽ làm tin nhắn "biến hình" ngầm từ file → text, có thể gây hiểu lầm trong lịch sử hội thoại và phá vỡ giả định "tin nhắn file luôn có `fil_id`" ở các nơi khác đã JOIN.

_Source: [Oracle FK SET NULL syntax](https://www.techonthenet.com/oracle/foreign_keys/foreign_null.php), [Oracle FK nullable requirement](http://www.techhoney.com/2012/10/30/foreign-key-with-on-delete-set-null-in-oracle-sql-plsql/)_

### SSE Delivery Ordering — cơ sở cho phân tích race condition

SSE (cơ chế chat-server đang dùng) **không đảm bảo ordering tuyệt đối qua proxy/multi-instance**, và là giao thức eventually-consistent theo thiết kế — chấp nhận được cho hầu hết ứng dụng chat/notification, nhưng có nghĩa là khoảng hở thời gian giữa 2 sự kiện liên tiếp (`message` rồi `attachment`) là **race condition thực sự có thể xảy ra**, không phải lý thuyết. Cụ thể: SSE event ID hỗ trợ resume sau khi mất kết nối, nhưng không đảm bảo client xử lý 2 event riêng biệt (`message` → `attachment`) một cách atomic — client hoàn toàn có thể render xong UI cho event `message` trước khi `attachment` tới (độ trễ vài trăm ms tới vài giây tùy mạng).

_Source: [MDN SSE Guide](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events), [SSE production readiness caveats](https://dev.to/miketalbot/server-sent-events-are-still-not-production-ready-after-a-decade-a-lesson-for-me-a-warning-for-you-2gie)_

### Migration Pattern: Expand-Contract / DDL-before-Code

Best practice ngành (Expand-Contract / Parallel Change pattern) khẳng định đúng nguyên tắc đã ghi trong `CLAUDE.md` của dự án: **migration phải backward-compatible với code đang chạy** — DDL chạy xong, code cũ vẫn hoạt động bình thường, chỉ sau đó mới deploy code mới phụ thuộc cột mới. Thêm cột nullable là thao tác metadata-only trên Oracle, không gây downtime hay khóa bảng lớn — an toàn để chạy độc lập trước.

_Source: [Zero-Downtime Schema Migrations](https://amrelsher07.medium.com/zero-downtime-schema-migrations-on-large-production-tables-0bdc27d3ad40), [Database Migrations Zero-Downtime Guide](https://dev.to/young_gao/database-migrations-in-production-zero-downtime-schema-changes-5fng)_

---

## Integration Patterns Analysis

### Đây chính là "Dual Write Problem" giữa 2 hệ thống ghi (Oracle ↔ Node SSE)

Luồng `msSendFileMessage()` 3 bước (tạo msg trong Oracle → upload file trong Oracle → broadcast SSE qua Node) là một biến thể kinh điển của **Dual Write Problem**: ghi vào 2 "đích" khác nhau (DB và message broker/SSE stream) mà không có transaction chung. Không thể đảm bảo atomic giữa "ghi DB" và "publish event" — nếu service crash giữa 2 bước, event bị mất vĩnh viễn dù DB đã ghi đúng.

Áp vào trường hợp cụ thể của `fil_id`:
- Bước 1 (`/send`) tạo row `CHAT_MESSENGERS` với `fil_id = NULL`, **DB transaction này COMMIT ngay** và Node phát SSE `message` event ngay sau đó — client khác nhận được tin nhắn "rỗng" trong UI.
- Bước 2 (`msUploadAttachment`) UPDATE `fil_id` — đây là **transaction Oracle thứ hai, độc lập** với bước 1. Giữa 2 transaction này không có gì đảm bảo bước 2 sẽ chạy (lỗi upload, mất kết nối, người dùng đóng tab).
- Bước 3 (`/attach`) chỉ broadcast SSE, KHÔNG ghi DB — nếu bước 3 thất bại (mất kết nối Node tạm thời) nhưng bước 2 đã UPDATE `fil_id` thành công, DB đã đúng nhưng client khác **không bao giờ biết** để refresh — chỉ người gửi tự `refreshThread()` ngay nên không nhận ra vấn đề khi tự test.

→ Đây CHÍNH XÁC là pattern **Transactional Outbox** giải quyết: ghi event cần publish vào CÙNG transaction/CÙNG DB với business data, rồi một tiến trình riêng đọc & publish — đảm bảo event không bao giờ mất ngay cả khi broadcast tạm thời lỗi. Áp dụng tối thiểu (không cần outbox đầy đủ): client tự chủ động `refreshThread()` định kỳ hoặc khi quay lại tab, không chỉ dựa vào SSE, để tự phục hồi nếu lỡ broadcast.

_Source: [Dual Writes - Unknown Cause of Data Inconsistencies](https://thorben-janssen.com/dual-writes/), [Confluent: Dual-Write Problem](https://www.confluent.io/blog/dual-write-problem/), [Transactional Outbox Pattern - AWS](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html)

### Optimistic UI cho trạng thái "đang tải file" — pattern ngành đã chuẩn hóa

Vấn đề "tin nhắn hiển thị rỗng trong lúc chờ `fil_id`" mà thiết kế hiện tại gặp phải đã có pattern chuẩn trong ngành chat app: gửi message với trạng thái **`pending`/`unpublished`** ngay lập tức ở client (hiển thị placeholder/spinner cho file), chỉ chuyển sang trạng thái `published`/hoàn chỉnh khi xác nhận attachment đã gắn xong; nếu thất bại → trạng thái `failed` kèm nút thử lại.

_Áp dụng cụ thể cho `messenger/`:_ thay vì để client khác thấy "tin nhắn rỗng" (vì `fil_id IS NULL` tạm thời), nên thêm 1 cờ trạng thái tạm thời ở tầng ứng dụng (không nhất thiết ở DB) — ví dụ payload SSE event `message` đầu tiên có thể đánh dấu `is_file: true, fil_id: null, status: 'uploading'` để client render skeleton/spinner thay vì coi đó là tin nhắn text rỗng hợp lệ. Đây là phân biệt quan trọng: **NULL có 2 nghĩa khác nhau** trong thiết kế hiện tại — "tin nhắn text thật" (NULL vĩnh viễn) vs "đang chờ upload" (NULL tạm thời) — mà schema không phân biệt được nếu chỉ dựa vào `fil_id IS NULL`.

_Source: [XMTP optimistic message sending](https://docs.xmtp.org/chat-apps/core-messaging/send-messages), [Remix Pending/Optimistic UI](https://remix.run/docs/en/main/discussion/pending-ui)

---

## Architectural Patterns and Design

### Data Architecture: Hiệu năng JOIN — fil_id (PK lookup) vs owner_id+owner_table_name (composite)

Oracle đọc index từ cột trái nhất (leftmost), và các cột dùng điều kiện bằng (`=`) — như JOIN — nên đặt trước trong composite index. `owner_id+owner_table_name` hiện tại đã có thể có composite index hỗ trợ JOIN nhanh nếu được tạo đúng thứ tự (`owner_table_name` cố định = `'CHAT_MESSENGERS'` luôn, `owner_id` biến thiên) — vấn đề hiệu năng JOIN thực ra **không lớn như lo ngại ban đầu** nếu composite index đã tồn tại đúng cách trên bảng file.

Khác biệt thực chất giữa `fil_id` trực tiếp và `owner_id` composite không nằm ở tốc độ JOIN đơn thuần (cả 2 đều dùng index, hiệu năng gần tương đương ở quy mô dữ liệu vừa phải), mà nằm ở:
- **`fil_id` JOIN single-column PK** → planner đơn giản hơn, không cần lọc thêm điều kiện `owner_table_name = 'CHAT_MESSENGERS'` (dù điều kiện này selective tốt vì hằng số).
- **`fil_id` cho phép FK constraint thật** → Oracle tự duy trì lock/validate khi INSERT/UPDATE/DELETE trên bảng cha-con, giảm rủi ro orphan record mà `owner_id` không có được.

_Khuyến nghị:_ lợi ích chính của `fil_id` là **toàn vẹn dữ liệu (FK)**, không phải hiệu năng — đừng dùng "hiệu năng" làm lý do chính để justify thiết kế song song; nếu hiệu năng là mối quan tâm thực sự, kiểm tra trước xem composite index trên `(owner_table_name, owner_id)` đã tồn tại trên bảng file hay chưa.

_Source: [Oracle Index Guidelines](https://docs.oracle.com/database/121/TGSQL/tgsql_indc.htm), [Oracle Composite Index Ordering](https://blogs.oracle.com/sql/how-to-create-and-use-indexes-in-oracle-database)_

### Data Architecture: Soft-delete cho file đính kèm trong lịch sử chat

Soft-delete (cờ `is_deleted`/`deleted_date` thay vì DELETE thật) là lựa chọn phù hợp cho dữ liệu có giá trị audit/lịch sử như tin nhắn — nhưng **không phải luật áp dụng mọi nơi** (xem cảnh báo "soft-delete như luật chung là anti-pattern" — chỉ nên dùng khi thực sự cần giữ lịch sử/audit, không phải mặc định cho mọi bảng). Với file đính kèm chat, lý do hợp lý để soft-delete:
- Giữ tính toàn vẹn của lịch sử hội thoại (người dùng khác đã đọc/forward tin nhắn đó không nên thấy nó "biến mất" đột ngột).
- Hỗ trợ trường hợp pháp lý/audit (đã có sẵn trong dự án qua `CHAT_PINNED_MSGS`, reaction, không có cơ chế xóa cứng tin nhắn).

_Khuyến nghị:_ nhất quán với cách `messenger/` đã xử lý xóa hội thoại (`msDeleteConv` = xóa participant row, KHÔNG xóa tin nhắn) — file đính kèm nên theo cùng triết lý: soft-delete, không hard-delete.

_Source: [Soft Delete vs Hard Delete](https://appmaster.io/blog/soft-delete-vs-hard-delete), [Soft-delete as anti-pattern caveat](https://news.ycombinator.com/item?id=40326815)_

### Tổng hợp đánh giá thiết kế (ADR-style)

| Khía cạnh | Đánh giá | Mức rủi ro |
|---|---|---|
| Hướng thiết kế `fil_id` thay vì polymorphic | Đúng về lý thuyết, cải thiện toàn vẹn dữ liệu | — (tích cực) |
| Giữ song song `owner_id` + `fil_id` | 2 nguồn sự thật cho cùng 1 quan hệ, có thể lệch nhau nếu code chỉ update 1 chiều | **Cao** |
| Race condition giữa `/send` (fil_id NULL) và update `fil_id` | Dual-write problem thực sự, client khác có thể thấy tin nhắn "rỗng" tạm thời hoặc kẹt vĩnh viễn nếu bước 2 lỗi | **Cao** |
| `fil_id IS NULL` mang 2 nghĩa (text thật vs đang upload) | Schema không phân biệt được, dễ gây bug hiển thị | **Trung bình-Cao** |
| `ON DELETE` behavior chưa xác định | Nếu chọn `SET NULL`, tin nhắn "biến hình" ngầm | **Trung bình** |
| Hiệu năng JOIN | Không phải vấn đề lớn nếu composite index đã có | **Thấp** |
| Thứ tự migration DDL/code | Đã có nguyên tắc đúng sẵn trong CLAUDE.md dự án | **Thấp** (nếu tuân thủ) |

---

## Implementation Approaches and Technology Adoption

### Idempotent recovery — giải pháp thực tế cho race condition (không cần outbox đầy đủ)

Pattern ngành cho lỗi giữa-chừng (mid-workflow) ở thao tác nhiều bước: **không cố "dọn dẹp" (rollback) bước đã xong, mà để bước tiếp theo tự chạy lại an toàn (idempotent) từ checkpoint cuối**. Áp dụng cụ thể vào `msSendFileMessage()`:

- Nếu bước 2 (`msUploadAttachment`) thất bại → msg đã tồn tại với `fil_id=NULL`, client nên cho phép người gửi **thử upload lại trên đúng msg_id đó** (không tạo msg mới) — tránh rác nhiều dòng `fil_id=NULL` mồ côi.
- Nếu bước 3 (`/attach`) thất bại nhưng bước 2 đã UPDATE `fil_id` thành công → không cần retry phức tạp, chỉ cần: (a) người gửi tự `refreshThread()` ngay (đã có sẵn trong code hiện tại) và (b) các client khác tự phục hồi nhờ **`loadThread()` định kỳ/khi focus lại tab** thay vì phụ thuộc 100% vào SSE — đây là biện pháp giảm rủi ro rẻ nhất, không cần xây transactional outbox đầy đủ.

_Source: [Idempotency Patterns: Retry-Safe Distributed Systems](https://backendbytes.com/articles/idempotency-patterns-distributed-systems/), [Idempotency Beyond Retry Safely](https://dev.to/aloknecessary/idempotency-in-distributed-systems-design-patterns-beyond-retry-safely-k66)_

### DDL đề xuất (thứ tự deploy bắt buộc: DDL → callback → JOIN render)

```sql
-- Bước A: chạy TRƯỚC tất cả code mới (nullable = metadata-only, không downtime)
ALTER TABLE CHAT_MESSENGERS ADD fil_id NUMBER;

ALTER TABLE CHAT_MESSENGERS
  ADD CONSTRAINT fk_chat_msg_fil
  FOREIGN KEY (fil_id) REFERENCES <bảng_file>(fil_id);
  -- KHÔNG dùng ON DELETE SET NULL — xem lý do ở mục FK Constraint phía trên
  -- Xóa file dùng soft-delete (is_deleted/deleted_date) ở <bảng_file>, không hard-delete

-- Bước B: nếu cần truy vấn nhanh tin nhắn có file (tùy chọn, tối ưu thêm)
CREATE INDEX ix_chat_msg_fil_id ON CHAT_MESSENGERS(fil_id);
```

### Checklist rollout (theo đúng thứ tự, không đảo)

1. **Chạy DDL** (Bước A/B ở trên) trên Oracle — verify bằng `DESC CHAT_MESSENGERS` trước khi đụng tới code.
2. **Đổi tên callback thật** thay cho `msUploadAttachment` (TODO đang treo trong `messenger.fgvd.js` dòng 633) — callback insert vào `<bảng_file>` VÀ `UPDATE CHAT_MESSENGERS SET fil_id = :fil_id WHERE msg_id = :msg_id` trong CÙNG 1 transaction PL/SQL (tận dụng atomic transaction của Oracle để giảm rủi ro race — đây là cải thiện so với thiết kế gốc, gộp việc ghi `owner_id` ở bảng file và update `fil_id` ở `CHAT_MESSENGERS` vào 1 lần COMMIT).
3. **Quyết định owner_id có còn cần ghi không**: nếu chỉ giữ `owner_id` cho mục đích lịch sử/không có chỗ nào đọc nữa, ghi rõ trong code comment + CLAUDE.md để tránh người sau tưởng đó vẫn là nguồn sự thật.
4. **Sửa `msMsgThreadHtml`** JOIN `CHAT_MESSENGERS.fil_id = <bảng_file>.fil_id` (PK lookup, đơn giản hơn JOIN cũ) — dùng `MATERIALIZE` hint nếu có `REGEXP_REPLACE`/`INTERVAL` trên cột remote theo đúng pitfall đã ghi trong CLAUDE.md gốc.
5. **Thêm trạng thái "đang tải"** ở tầng ứng dụng (không bắt buộc cột DB mới): event SSE `message` đầu tiên kèm `is_file:true` để client render skeleton, tránh hiểu nhầm `fil_id IS NULL` là tin nhắn text vĩnh viễn trong lúc đang chờ.
6. **Thêm cơ chế tự phục hồi**: `loadThread()`/`refreshThread()` định kỳ nhẹ hoặc khi tab focus lại, không chỉ dựa vào SSE `attachment` event — giảm thiểu hậu quả khi bước `/attach` lỡ broadcast thất bại.
7. **Deploy code** (callback mới + `msMsgThreadHtml` mới) sau khi DDL đã chạy ổn định — không gộp chung 1 lần deploy với DDL.
8. **Test thủ công**: gửi file → ngắt mạng giữa bước 2 và 3 (giả lập) → xác nhận client khác vẫn thấy file sau khi tự refresh, không bị kẹt vĩnh viễn ở trạng thái "tin nhắn rỗng".

---

## Research Synthesis

### Executive Summary

Đề xuất thêm `fil_id` (nullable, FK) vào `CHAT_MESSENGERS` để biểu diễn tin nhắn file/ảnh, render theo `fil_id IS NULL` (text) / `NOT NULL` (file), giữ song song với `owner_id+owner_table_name` hiện có trên bảng file.

Về mặt lý thuyết thiết kế dữ liệu, `fil_id` đi đúng hướng — `owner_id+owner_table_name` là **polymorphic association**, một anti-pattern đã được tài liệu hóa rộng rãi vì không thể có FK constraint thật. Thay bằng cột FK trực tiếp là cải thiện thật sự. Tuy nhiên, **2 rủi ro mức Cao** cần xử lý trước khi triển khai:

1. **Hai nguồn sự thật** — giữ song song `fil_id` và `owner_id` cho cùng một quan hệ message↔file, nếu code chỉ cập nhật một chiều sẽ lệch dữ liệu theo thời gian.
2. **Race condition (Dual Write Problem)** — luồng 3 bước hiện tại (`/send` → upload callback → `/attach`) ghi vào 2 hệ thống (Oracle + Node SSE) không có transaction chung; nếu một bước thất bại giữa chừng, client khác có thể thấy tin nhắn "rỗng" tạm thời hoặc kẹt vĩnh viễn.

Hiệu năng JOIN, vốn là mối quan tâm ban đầu, hóa ra **không phải vấn đề lớn** — composite index trên `owner_id+owner_table_name` (nếu đã có) cho hiệu năng gần tương đương `fil_id`. Lợi ích thật sự của `fil_id` nằm ở toàn vẹn dữ liệu (FK constraint), không phải tốc độ truy vấn.

**Khuyến nghị:**

- **Đi tiếp với `fil_id`**, nhưng coi nó là nguồn sự thật chính; làm rõ vai trò còn lại của `owner_id` (lịch sử/không dùng nữa) để tránh nhầm lẫn về sau.
- **Gộp bước 2 (insert file) và update `fil_id`** vào cùng 1 transaction PL/SQL trong callback upload — loại bỏ phần lớn race condition bằng atomic transaction sẵn có của Oracle, thay vì 2 thao tác rời rạc.
- Dùng `ON DELETE NO ACTION` + soft-delete cho file đính kèm, KHÔNG dùng `SET NULL` (tránh tin nhắn "biến hình" ngầm từ file thành text).
- Thêm cơ chế client tự phục hồi (`refreshThread`/`loadThread` định kỳ hoặc khi focus tab) thay vì phụ thuộc hoàn toàn vào SSE — giảm thiểu hậu quả khi broadcast `/attach` lỡ thất bại.
- Tuân thủ thứ tự deploy DDL trước code (đã đúng theo nguyên tắc sẵn có trong CLAUDE.md dự án).

### Bảng rủi ro tổng hợp

Xem mục **"Tổng hợp đánh giá thiết kế (ADR-style)"** ở phần Architectural Patterns Analysis phía trên — 2 rủi ro Cao (2 nguồn sự thật, race condition), 1 rủi ro Trung bình-Cao (`fil_id IS NULL` mang 2 nghĩa), 1 rủi ro Trung bình (`ON DELETE` behavior), 2 rủi ro Thấp (hiệu năng JOIN, thứ tự migration).

### Next Steps

1. Quyết định: `owner_id` còn được đọc ở nơi nào khác ngoài `messenger/` không? Nếu không, cân nhắc lộ trình loại bỏ dần thay vì giữ vĩnh viễn song song.
2. Lấy tên bảng file thật và tên cột chính xác để hoàn thiện DDL cụ thể (hiện dùng placeholder `<bảng_file>`).
3. Xác nhận với người phụ trách callback upload thật (thay `msUploadAttachment`) để gộp logic update `fil_id` vào đúng transaction.
4. Chạy checklist rollout 8 bước đã liệt kê ở mục Implementation Approaches khi sẵn sàng triển khai.

---

**Technical Research Completion Date:** 2026-06-18
**Source Verification:** Tất cả khẳng định kỹ thuật đối chiếu nguồn công khai (Oracle docs, GitLab/SQL Antipatterns, MDN, Confluent, AWS Prescriptive Guidance)
**Technical Confidence Level:** Cao đối với các pattern kiến trúc/dữ liệu tổng quát; Trung bình đối với chi tiết vận hành chat-server cụ thể (chưa kiểm chứng trực tiếp trên môi trường production)

---

## Addendum: Quyết định cuối — đảo thứ tự upload-trước-gửi-sau (2026-06-18)

Sau khi trình bày báo cáo, người yêu cầu đề xuất đơn giản hóa: **upload file TRƯỚC (lấy `fil_id`) rồi mới INSERT 1 lần duy nhất vào `CHAT_MESSENGERS` với `fil_id` đã có sẵn**, thay vì tạo msg rỗng trước rồi UPDATE `fil_id` sau. Đây là cách giải quyết tốt hơn dự kiến ban đầu trong báo cáo, vì:

- **Loại bỏ hoàn toàn race condition (Dual Write Problem)** đã nêu ở mục Integration Patterns — không còn 2 transaction Oracle rời rạc cho cùng 1 message, chỉ còn 1 INSERT atomic.
- **Loại bỏ luôn rủi ro "2 nguồn sự thật"** — vì xác nhận `owner_id`/`owner_table_name` trên bảng file KHÔNG có ràng buộc NOT NULL, nên với file đính kèm chat có thể để trống 2 cột này hoàn toàn, chỉ dùng `fil_id` trên `CHAT_MESSENGERS` làm nguồn sự thật duy nhất — không còn 2 cấu trúc song song.
- **Đánh đổi chấp nhận được:** tin nhắn (luồng "+") giờ chỉ xuất hiện sau khi upload xong, thay vì xuất hiện ngay với placeholder rồi cập nhật sau. Người yêu cầu đã xác nhận chấp nhận độ trễ này.

**Đã áp dụng vào code:**
- `chat-server/chat.js` (`C:\greensys\chat-server`) — route `POST /send` nhận thêm `fil_id/file_name/mime_type/file_size`, đưa `fil_id` vào câu INSERT `CHAT_MESSENGERS` (1 transaction). Route `/attach` đánh dấu deprecated, không xóa.
- `messenger/messenger.fgvd.js` — `msSendFileMessage()` viết lại theo thứ tự upload trước → `/send` sau, không còn gọi `/attach`.
- `messenger/docs/callbacks.sql` — thêm DDL cột `fil_id` (nullable, FK `NO ACTION`, không `SET NULL`) + index, ghi rõ `owner_id/owner_table_name` không set cho file chat.
- `messenger/CLAUDE.md` — cập nhật mục "Đính kèm file/ảnh" theo luồng mới.

**Còn lại (TODO chưa làm, cần thông tin từ người dùng):** đổi tên callback `msUploadAttachment` thành tên thật, và sửa `msMsgThreadHtml` JOIN bảng file theo `fil_id` để hiển thị lại file khi load thread.
