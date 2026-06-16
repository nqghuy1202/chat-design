# Research Report: ERP Chat Module
**Ngay lap tuc:** 2026-06-15  
**Skill used:** UX Research 1.0.0 + design-taste-frontend + high-end-visual-design  
**Pham vi:** Feature gap analysis + UX audit + Prioritized roadmap  
**Context:** Chat module nhu 1 page trong he thong ERP da module (ke toan, quan tri, san xuat, nhan su). SaaS ban cho doanh nghiep, nguoi dung mixed.

---

## 1. DESIGN READ & DIALS

```
Reading this as: B2B SaaS product UI (embedded ERP chat) for mixed enterprise users
(accountants, HR, production, management), with a professional/modern/clean language,
leaning toward high-density elegant product UI -- closer to Linear or Notion than Slack.

DESIGN_VARIANCE:   6   (professional, clean, not bland -- subtle asymmetry)
MOTION_INTENSITY:  5   (smooth micro-interactions, no cinematic effects)
VISUAL_DENSITY:    7   (ERP context = information-dense but not cockpit-packed)
```

---

## 2. PHAN TICH HIEN TAI (Audit Baseline)

### Diem manh hien co
| Component | Danh gia |
|---|---|
| 3-panel layout (left/center/right) | Vung chac, logic ro rang |
| Left panel slider (S1-S4) | UX tot, smooth animation |
| Reply voi quote block | Da lam dung, semi-transparent cho theme |
| Ngu hanh theme system | Differentiator tot cho ERP co brand rieng |
| Message grouping (consecutive sender) | Dung best practice cua Slack/Teams |
| Context menu tren conversation | Du chuc nang co ban |
| Right panel info (collapsible) | Gon, khong lan man |
| Typing indicator | Co, animation tot |

### Diem yeu / Chua co
| Van de | Severity (0-4) | Ghi chu |
|---|---|---|
| Khong co global search | 4 - Catastrophic | ERP co hang nghin tin nhan, phai search duoc |
| Khong co empty states | 3 - Major | Khi chua co conversation, man hinh trong |
| Khong co loading/skeleton states | 3 - Major | Cam giac ung dung chua hoan thien |
| Khong co unread message divider | 3 - Major | Nguoi dung khong biet doc den dau |
| Khong co date separator trong chat | 3 - Major | Khong the nhan biet tin nhan ngay nao |
| Khong co message status (sent/delivered/read) | 2 - Minor | Enterprise can biet tin da doc chua |
| Khong co emoji picker o input | 2 - Minor | Tat ca cac chat app deu co |
| Khong co drag & drop file upload | 3 - Major | Workflow rat pho bien trong ERP |
| Khong co jump-to-latest button | 3 - Major | Khi scroll len tren, mat dinh huong |
| Khong co custom presence/status | 2 - Minor | "Dang hop", "Nghi phep" -- quan trong ERP |
| Khong co notification center | 4 - Catastrophic | Nguoi dung ERP bi bom thong bao tu nhieu module |
| Khong co keyboard shortcuts | 2 - Minor | Power user cua ERP thuong dung phim tat |
| Accessibility thieu (ARIA, focus trap) | 3 - Major | Enterprise co tieu chuan accessibility |
| Khong co pinned messages UI | 3 - Major | Da co menu "Ghim" nhung chua co UI hien thi |
| Input khong co rich text day du | 2 - Minor | Bold, italic, code, list -- quan trong voi ERP user |

---

## 3. FEATURE GAP ANALYSIS

### 3.1 ERP INTEGRATION -- Differentiator lon nhat
Day la diem tao ra su khac biet giua 1 chat biet lap va 1 ERP-native chat.

#### Chua co -- Can lam
| Feature | Mo ta | Priority |
|---|---|---|
| **ERP Record Linking** | Trong hop thoai co the mention @invoice #INV-001, @order #PO-234, @employee. Click vao se mo record tuong ung trong ERP module | P0 |
| **Context Card Preview** | Khi share link ERP record, hien thi card inline: tieu de, trang thai, nguoi phu trach, nut hanh dong | P0 |
| **Inline Action Buttons** | Duyet / Tu choi / Chinh sua truc tiep tu tin nhan ma khong can chuyen tab | P0 |
| **ERP Event Bot Channel** | Channel tu dong nhan thong bao tu cac module: "Don hang #1234 da duoc CEO duyet", "Phieu luong thang 6 da xuat" | P1 |
| **Task Creation from Message** | Right-click / action button tren tin nhan -> "Tao nhiem vu" -> tu dong dien mo ta va nguoi duoc mention | P1 |
| **Workflow Trigger** | Nut trong tin nhan de trigger ERP workflow (VD: "Xac nhan nhan hang", "Phe duyet tang luong") | P1 |

---

### 3.2 MESSAGING CORE -- Must-have gap
| Feature | Mo ta | Priority |
|---|---|---|
| **Global Search** | Tim kiem xuyen conversation: text, file, nguoi gui, ngay thang. Filter multi-dimension | P0 |
| **Date Separators** | "Hom nay", "Hom qua", "12 thang 6" phan cach cac nhom tin nhan | P0 |
| **Unread Message Divider** | Duong ngang co nhan "X tin nhan chua doc" chia cao nhat o lan cuoi mo | P0 |
| **Jump to Latest** | Nut float khi scroll len tren, click xuong cuoi conversation | P0 |
| **Message Forwarding** | Chuyen tin nhan sang conversation khac kem trich dan nguon | P1 |
| **Scheduled Messages** | Dat lich gui tin nhan (quan trong cho ERP: nhac nho cuoi ky ke toan) | P2 |
| **Message Draft** | Tu dong luu nhap khi chuyen sang conversation khac | P1 |
| **Reminder on Message** | "Nhac toi ve tin nhan nay vao 9h sang mai" | P2 |
| **Polls / Voting** | Tao phieu tham khao trong nhom (VD: "Chon gio hop?") | P2 |
| **Thread Reply** | Tra loi thanh thread rieng de khong lam ngat mach chat chinh | P1 |

---

### 3.3 FILE & MEDIA
| Feature | Mo ta | Priority |
|---|---|---|
| **Drag & Drop Upload** | Keo file tu may tinh vao cua so chat | P0 |
| **Inline File Preview** | PDF, Excel, anh hien thi trong chat, khong can tai ve | P0 |
| **File Tab trong conversation** | Tab "Files" trong right panel de xem tat ca file da chia se trong cuoc tro chuyen | P1 |
| **Image Gallery** | Click vao anh mo lightbox, xem truoc/sau | P1 |
| **Paste from Clipboard** | Dan anh/file truc tiep vao o nhap lieu | P0 |

---

### 3.4 NOTIFICATION & FOCUS
| Feature | Mo ta | Priority |
|---|---|---|
| **Notification Center** | Panel rieng hien thi tat ca notification tu moi conversation + ERP modules. Co phan loai: @mention, reply, ERP events | P0 |
| **Do Not Disturb Mode** | Tat thong bao theo khung gio (VD: 22:00 - 08:00) | P1 |
| **Priority Notifications** | Chi nhan thong bao tu quan ly hoac khi duoc mention truc tiep | P1 |
| **Per-Conversation Settings** | Ghim, tat thong bao, uu tien -- rieng cho tung conversation (menu da co, can lam UI) | P1 |
| **Unread Badge tren module nav** | Badge so luong unread hien thi tren icon Chat o sidebar ERP chinh | P0 |

---

### 3.5 PRESENCE & AVAILABILITY
| Feature | Mo ta | Priority |
|---|---|---|
| **Custom Status** | "Dang hop", "Nghi phep", "Lam viec tap trung" voi emoji + het han tu dong | P1 |
| **Working Hours** | Cai dat gio lam viec, hien thi cho nguoi khac biet | P2 |
| **Out-of-Office Auto Reply** | Tu dong tra loi khi OOO, redirect sang nguoi khac | P2 |

---

### 3.6 ADMIN & GOVERNANCE (cho ERP enterprise)
| Feature | Mo ta | Priority |
|---|---|---|
| **User Roles trong Group** | Admin group, Moderator, Member -- phan quyen ghi / doc | P1 |
| **Announcement Mode** | Che do chi admin duoc gui tin nhan (danh cho thong bao cong ty) | P1 |
| **Message Retention Policy** | Tu dong xoa tin nhan sau X ngay (GDPR, bao mat noi bo) | P2 |
| **Audit Log** | Log tat ca hanh dong: ai gui gi, ai sua/xoa, khi nao | P2 |
| **Guest / External Access** | Moi doi tac/khach hang vao conversation co gioi han quyen | P2 |
| **Department Channels** | Kenh theo phong ban (Ke Toan, Nhan Su, San Xuat) -- tu dong them thanh vien theo bo phan ERP | P1 |

---

### 3.7 PRODUCTIVITY
| Feature | Mo ta | Priority |
|---|---|---|
| **Bookmarked Messages** | Luu tin nhan de xem lai sau (khac voi ghim conversation) | P2 |
| **Pinned Messages UI** | Hien thi pin banner o dau conversation, co the xem tat ca pinned | P1 |
| **Message Templates** | Mau tin nhan san cho cac quy trinh ERP pho bien (VD: "De nghi xac nhan don hang...") | P2 |
| **Keyboard Shortcuts** | Ctrl+K global search, Ctrl+/ shortcuts panel, E edit last, R reply, Esc cancel | P2 |

---

## 4. UX/UI IMPROVEMENT AUDIT

### 4.1 Navigation & Information Architecture
**Van de:** Hien tai khong co cach nhanh chuyen sang conversation can thiet. Khi co nhieu conversation, nguoi dung phai scroll tim.

**Giai phap de xuat:**
- Quick switcher (Ctrl+K): go ten nguoi / conversation / ERP record
- Section phan loai trong left panel: "Ghim", "Direct Messages", "Nhom", "Kenh"
- Unread-first sort option

---

### 4.2 Visual Hierarchy & Density
**Van de:** Message area khong phan biet ngay/thoi gian, khong co unread divider, cac tin nhan nhin nhu do khoi.

**Giai phap de xuat:**
- Date separator pills ("Hom nay") float giua cac nhom tin nhan
- Unread divider co mau accent nhe voi nhan dem
- Avatar size nhat quan (32px), ten nguoi gui font 13.5px semibold
- Timestamp format nganh: <1h hien "2 phut truoc", >1 ngay hien ngay

---

### 4.3 Input Experience
**Van de:** O nhap lieu co toolbar dinh dang nhung thieu emoji picker, khong co indicator khi dang go reply, khong co preview file truoc khi gui.

**Giai phap de xuat:**
- Emoji picker (click icon hoac go `:` de goi emoji autocomplete)
- File drop zone hien thi khi keo file vao cua so
- File preview thumbnail trong input truoc khi gui
- Character/line count hint cho tin nhan dai
- Mention autocomplete khi go `@` (danh sach thanh vien + ERP entities)

---

### 4.4 Micro-interactions & Feedback
**Van de:** Mot so hanh dong khong co visual feedback (GUI tin nhan: khong co sent/delivered/read ticks, khong co optimistic UI).

**Giai phap de xuat:**
- Sent tick (1 tick xam = da gui, 2 tick xam = da nhan, 2 tick mau = da doc) -- cho DM
- Optimistic message render (tin nhan hien ngay khi gui, khong cho server confirm)
- Error state khi gui that bai: "Gui lai" button inline
- Hover state tren tin nhan cho thay action bar ro rang hon (hien tai ok nhung co the cai thien)
- Reaction animation (emoji bounce nhe khi them reaction)

---

### 4.5 Empty & Loading States
**Chua co hoan toan -- can thiet ke:**
- Empty state S1 (chua co conversation): illustration + "Bat dau cuoc tro chuyen moi"
- Empty state center panel (chua chon conversation): welcome illustration + shortcut tips
- Loading skeleton cho conversation list, message list
- Error state khi mat ket noi (banner nhe o tren cung)

---

### 4.6 Accessibility
**Van de:** Hien tai thieu nhieu ARIA attribute, focus trap trong modal, keyboard navigation.

**Giai phap de xuat:**
- `role="dialog"` cho modal, `aria-label` cho tat ca button icon
- Focus trap khi mo context menu / emoji picker
- `role="log"` cho message list (screen reader doc duoc)
- Skip-to-content link
- Phan biet focus state ro rang (khong chi dua vao outline mac dinh)

---

## 5. BENCHMARK -- Best-in-class Reference

| Tinh nang | Slack | Teams | Linear | ERP chat nay |
|---|---|---|---|---|
| Global search | Tot | Tot | Xuat sac | Chua co |
| Thread reply | Tot | Tot | Khong ap dung | Chua co |
| ERP integration | Plugin | Native (MS365) | N/A | **Potentail differentiator** |
| File preview inline | Tot | Tot | N/A | Chua co |
| Notification center | Tot | Tot | Tot | Chua co |
| Custom status | Tot | Tot | Tot | Chua co |
| Date separators | Co | Co | Co | Chua co |
| Unread divider | Co | Co | Co | Chua co |
| Keyboard shortcuts | Xuat sac | Tot | Xuat sac | Chua co |
| Context card (record link) | Plugin | Native (adaptive cards) | Issue embeds | **Chua co -- loi the doc dao** |
| Empty states | Tot | Tot | Xuat sac | Chua co |

**Ket luan benchmark:** Van de cot loi khong phai tinh nang -- ma la ERP context awareness. Slack/Teams la cac app chat tong hop. He thong nay co the tro thanh **ERP-native chat tot nhat** neu focus vao: record linking, context cards, va workflow integration.

---

## 6. PRIORITIZED ROADMAP

### PHASE 1 -- Foundation (lam ngay, cao impact / thap effort)
*Nhan thay ngay, khong can thay doi architecture*

| # | Feature | Effort | Impact |
|---|---|---|---|
| 1.1 | Date separators trong message list | Thap | Cao |
| 1.2 | Unread message divider | Thap | Cao |
| 1.3 | Jump-to-latest floating button | Thap | Cao |
| 1.4 | Drag & drop file upload (drop zone) | Trung | Cao |
| 1.5 | Paste from clipboard (image) | Thap | Cao |
| 1.6 | Empty states (S1, center panel) | Trung | Cao |
| 1.7 | Loading skeleton states | Trung | Trung |
| 1.8 | Emoji picker | Trung | Trung |
| 1.9 | Pinned messages UI (banner + view all) | Trung | Cao |
| 1.10 | File tab trong right panel | Trung | Trung |
| 1.11 | Inline image preview / lightbox | Trung | Cao |

---

### PHASE 2 -- Power Features (tao differentiation)
*Doi hoi thiet ke UX sau hon, co the can API support*

| # | Feature | Effort | Impact |
|---|---|---|---|
| 2.1 | Global search panel (Ctrl+K) | Cao | Rat cao |
| 2.2 | Notification center panel | Cao | Rat cao |
| 2.3 | ERP Record Mention & Context Card | Rat cao | Rat cao |
| 2.4 | Custom presence / status | Trung | Cao |
| 2.5 | Department channels (auto-member) | Trung | Cao |
| 2.6 | Thread reply | Cao | Cao |
| 2.7 | Message forwarding | Trung | Trung |
| 2.8 | Task creation from message | Cao | Cao |
| 2.9 | Message draft (auto-save) | Trung | Trung |
| 2.10 | Inline action buttons (approve/reject) | Cao | Rat cao |

---

### PHASE 3 -- Enterprise & Polish
*Governance, automation, advanced UX*

| # | Feature | Effort | Impact |
|---|---|---|---|
| 3.1 | ERP Event Bot channel | Cao | Cao |
| 3.2 | Scheduled messages | Trung | Trung |
| 3.3 | Workflow trigger buttons | Cao | Cao |
| 3.4 | Audit log (admin) | Cao | Cao (compliance) |
| 3.5 | Message retention policy | Trung | Trung (compliance) |
| 3.6 | Guest / external access | Cao | Trung |
| 3.7 | Announcement mode | Thap | Trung |
| 3.8 | Keyboard shortcuts full set | Trung | Cao (power users) |
| 3.9 | Message templates | Trung | Trung |
| 3.10 | Polls / voting | Trung | Thap |

---

## 7. UX DESIGN RECOMMENDATIONS (cho phase thiet ke)

### Typography & Density
- **Body messages:** 13.5px Outfit Regular, line-height 1.5
- **System messages / timestamp:** 11px Outfit, color #94A3B8
- **Names:** 13.5px Outfit SemiBold (600)
- Khong them font moi -- Outfit da du tot, du lightweight cho ERP

### Color Usage (ERP context)
- Giu ngay `var(--c-main)` cho tat ca accent -- theme switcher da tot
- Them semantic colors khong doi theo theme: `--c-success: #16A34A`, `--c-warning: #D97706`, `--c-error: #DC2626` cho ERP status
- **ERP Context Cards:** nen `#F8FAFC`, border `#E2E8F0`, status badge mau semantic

### Spacing System
- Message group padding: `8px 16px` (compact nhung khong nghet)
- Section gap trong right panel: `16px`
- Input area min-height: `44px`, max-height: `200px` (auto-expand)

### Motion (MOTION_INTENSITY: 5)
- Slide animation giu nguyen cubic-bezier(0.16,1,0.3,1) -- rat tot
- New message appear: `translateY(8px) opacity(0)` -> `translateY(0) opacity(1)` 200ms
- Reaction toggle: scale 1 -> 1.2 -> 1 bounce nhe
- Emoji picker: scale(0.95) + opacity 0 -> 1, origin bottom-right
- Khong dung GSAP -- Motion CSS / vanilla JS la du

### Key Visual Improvements (uu tien cao)
1. **Unread divider:** Duong ngang `#E2E8F0` voi badge accent color co text "N tin nhan chua doc"
2. **Date separator:** Pill `#F1F5F9`, text `#64748B`, 11px uppercase, centered
3. **Jump to latest:** FAB tron 40px, shadow `0 4px 12px rgba(0,0,0,0.12)`, icon arrow-down
4. **Context Card (ERP):** Card inline trong message bubble, co icon module, title, status badge, nut hanh dong
5. **Empty state center:** Illustration nhe (SVG don gian), headline 16px SemiBold, sub 13px, CTA button

---

## 8. KET LUAN

He thong chat hien tai co **nen tang kien truc tot** -- layout 3 panel, slider navigation, theme system. Day la nhung quyet dinh dung.

**3 viec quan trong nhat can lam truoc:**
1. **Phase 1 quick wins** -- date separator, unread divider, jump-to-latest, drag-drop: tao cam giac "hoan thien" ngay lap tuc
2. **Global search** -- bat buoc doi voi ERP co du lieu lon
3. **ERP Record Linking + Context Cards** -- day la diem khac biet duy nhat giup product nay tro thanh "ERP chat tot nhat thi truong" thay vi chi la "mot app chat nua"

**Next step:** Confirm Phase 1 feature nao muon implement truoc, sau do se thiet ke tung component vao `index.html`.
