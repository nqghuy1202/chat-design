// ============================================================
// MESSENGER FULLSCREEN — Function and Global Variable Declaration
// Paste vào Page → Function and Global Variable Declaration
// ============================================================

(function () {
  'use strict';

  var PAGE_ID         = $v('pFlowStepId');  // page ID hiện tại
  var activeConvId    = null;               // conv đang chọn
  var activeFilter    = 'ALL';              // dropdown loại hội thoại đang chọn (ALL/DM/GROUP/DOC)
  var unreadOnly      = false;              // toggle "Chưa đọc" đang bật hay không
  var replyTo         = null;              // { id, name, body } hoặc null
  var selectedMembers = [];                // mảng aus_id đã chọn ở màn soạn tin (S2)
  var _lpScreen       = 1;                 // màn hình hiện tại: 1=S1 (list), 2=S2 (soạn tin)
  var _composeMode    = 'new';             // 'new' = tạo hội thoại mới | 'add' = thêm TV vào nhóm sẵn có
  var _addTargetConv  = null;              // conv_id đích khi _composeMode === 'add'
  var _s2SearchTimer  = null;
  var _infoVisible    = false;             // right panel hiển thị hay không
  var _searchTimeout  = null;             // debounce conv search
  var _typingDebounce = null;             // debounce gửi typing event
  var _typingUsers    = {};               // aus_id → { name, timer }
  var _threadConvId   = null;             // conv đang render trong #ms-messages
  var _convMenuId     = null;             // conv_id đang mở dot-menu (null = đóng)
  var _reactBarOpen   = false;            // thanh quick-react đang mở?
  var _fwdMsgId       = null;             // tin đang chuyển tiếp
  var _fwdBody        = '';               // nội dung tin chuyển tiếp
  var _fwdTarget      = null;             // hội thoại đích đã chọn { id, name }
  var _fwdSearchTimer = null;             // debounce tìm hội thoại forward
  var _inIframe       = window.parent && window.parent !== window;
  var _parentWin      = _inIframe ? window.parent : window;
  var AUS_ID          = Number((_inIframe ? _parentWin.$v('P0_AUS_ID') : $v('P0_AUS_ID')) || 0);
  var NODE_URL        = (window.CHAT_NODE_URL || _parentWin.CHAT_NODE_URL || 'https://chattest.erp100.vn') + '/api/chat';

  // ── Unified modal: entry mode + scope + cross-doc awareness ──
  // entryDoc: null = mo tu icon header he thong (xem tat ca);
  //           {doc_type,doc_no,doc_label} = mo tu nut "Trao doi" o chung tu (sessionStorage 'msEntryDoc')
  var entryDoc        = null;
  var scopeMode       = 'ALL';            // 'ALL' | 'DOC'
  var crossDocQueue   = [];               // [{convId, docNo, name}] tin den ngoai scope hien tai

  // ── Helper: gọi AJAX callback ──────────────────────────────
  // pageItems (optional): selector/array các page item cần gửi kèm session
  // state (vd '#P10022710201_UPLOAD_FILE') — apex.server.process() KHÔNG tự
  // gửi page item nào nếu không khai báo, khác với Ajax Callback gắn trực
  // tiếp vào action của 1 item (tự động kèm giá trị item đó).
  function apexCall(proc, params, dataType, onSuccess, pageItems) {
    apex.server.process(proc, params, {
      pageId:    PAGE_ID,
      dataType:  dataType || 'json',
      pageItems: pageItems,
      success:   onSuccess,
      error: function (xhr) {
        console.error('[Messenger] ' + proc + ' error:', xhr.status, xhr.responseText);
      }
    });
  }

  // ── Helper: gọi thẳng Node.js (send/read/create) ──────────
  function nodePost(path, body, onSuccess, onError) {
    fetch(NODE_URL + path, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(body)
    })
    .then(function (res) { return res.json(); })
    .then(onSuccess || function () {})
    .catch(onError  || function (err) { console.error('[Messenger] nodePost', path, err); });
  }

  // ── Helper: gọi thẳng Node.js (GET — unread-summary) ──────
  function nodeGet(path, onSuccess, onError) {
    fetch(NODE_URL + path)
    .then(function (res) { return res.json(); })
    .then(onSuccess || function () {})
    .catch(onError  || function (err) { console.error('[Messenger] nodeGet', path, err); });
  }

  // ── Helper: skeleton HTML ──────────────────────────────────
  function skeletonHtml(count) {
    var html = '';
    for (var i = 0; i < count; i++) {
      html += '<div class="ms-sk-item">'
            + '<div class="ms-skeleton ms-sk-av"></div>'
            + '<div class="ms-sk-body">'
            + '<div class="ms-skeleton ms-sk-line" style="width:55%"></div>'
            + '<div class="ms-skeleton ms-sk-line" style="width:80%"></div>'
            + '</div></div>';
    }
    return html;
  }

  // ── Helper: tạo avatar element ─────────────────────────────
  function avatarHtml(name, ausId, imgUrl, isGroup, size) {
    var initl  = (name || '?').replace(/.*\s/, '').charAt(0).toUpperCase();
    var hue    = (ausId * 47) % 360;
    var radius = isGroup ? '10px' : '50%';
    var sz     = size || 40;
    var icon   = isGroup ? '<i class="fa fa-users" style="font-size:' + Math.round(sz * 0.4) + 'px"></i>' : initl;
    var img    = imgUrl ? '<img src="' + imgUrl + '" style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:inherit" onerror="this.remove()">' : '';
    return '<div style="width:' + sz + 'px;height:' + sz + 'px;border-radius:' + radius + ';'
         + 'background:hsl(' + hue + ',55%,52%);color:#fff;'
         + 'display:flex;align-items:center;justify-content:center;'
         + 'font-weight:600;font-size:' + Math.round(sz * 0.38) + 'px;'
         + 'position:relative;overflow:hidden;flex-shrink:0">'
         + img + icon + '</div>';
  }

  // ============================================================
  // INIT
  // ============================================================
  window.msInit = function () {
    initEntryDoc();
    loadCurrentUser();
    loadConvList();
    bindEvents();
    startEventPoll();
    refreshUnreadSummary();

    // Hiển thị empty state ban đầu
    showEmptyState();
  };

  // ── Đọc context chứng từ (nếu modal được mở từ nút "Trao đổi" ở 1 chứng từ) ──
  // sessionStorage key 'msEntryDoc' = { doc_type, doc_no, doc_label } do trang chứng từ set
  // trước khi gọi apex.navigation.dialog(). Trống/không có = mở từ icon header → xem tất cả.
  function initEntryDoc() {
    // sessionStorage là per-origin (không per-app) — app 1002/1503 cùng domain:port
    // nên đọc trực tiếp sessionStorage của trang hiện tại là đủ (giống pattern docChatCtx cũ).
    var raw = null;
    try { raw = sessionStorage.getItem('msEntryDoc'); } catch (e) {}
    if (!raw) { entryDoc = null; scopeMode = 'ALL'; updateScopeUI(); return; }
    try {
      var ctx = JSON.parse(raw);
      if (ctx && ctx.doc_type && ctx.doc_no) {
        entryDoc  = ctx;
        scopeMode = 'DOC';
      }
    } catch (e) { entryDoc = null; }
    updateScopeUI();
  }

  // ── Load thông tin user đang đăng nhập ──────────────────────
  function loadCurrentUser() {
    apexCall('msGetCurrentUser', {}, 'json', function (d) {
      if (!d || d.error) return;
      var avEl   = document.getElementById('ms-user-avatar');
      var nameEl = document.getElementById('ms-user-name');
      var hue    = (d.aus_id * 47) % 360;
      var initl  = (d.full_name || '?').replace(/.*\s/, '').charAt(0).toUpperCase();
      avEl.style.background = 'hsl(' + hue + ',55%,52%)';
      avEl.textContent = initl;
      if (d.img) {
        var img = document.createElement('img');
        img.src = d.img;
        img.style.cssText = 'width:100%;height:100%;object-fit:cover;border-radius:50%;position:absolute;inset:0';
        img.onerror = function () { this.remove(); };
        avEl.appendChild(img);
      }
      if (nameEl) nameEl.textContent = d.full_name || d.username || '';
      var statusEl = document.getElementById('ms-user-status-label');
      if (statusEl) statusEl.textContent = 'Đang hoạt động';
    });
  }

  // ============================================================
  // CONVERSATION LIST
  // ============================================================
  function loadConvList() {
    var listEl = document.getElementById('ms-conv-list');
    if (!listEl) return;
    listEl.innerHTML = skeletonHtml(5);

    apexCall('msConvListHtml', {
      x01: activeFilter,
      x02: document.getElementById('ms-conv-search').value.trim(),
      // x03=scope (DOC/ALL), x04=doc_type, x05=doc_no — chi co y nghia khi scope=DOC
      x03: scopeMode,
      x04: (scopeMode === 'DOC' && entryDoc) ? entryDoc.doc_type : '',
      x05: (scopeMode === 'DOC' && entryDoc) ? entryDoc.doc_no   : '',
      // x06="1" khi can ghim section "Dang xem" len dau (xem Tat ca nhung mo tu 1 chung tu)
      x06: (scopeMode === 'ALL' && entryDoc) ? '1' : '0',
      // x07="1" khi toggle "Chua doc" dang bat — ket hop AND voi x01 (loai), khong loai tru nhau
      x07: unreadOnly ? '1' : '0'
    }, 'text', function (html) {
      listEl.innerHTML = html || '<div style="padding:32px 16px;text-align:center;color:#94A3B8;font-size:13px">Chưa có hội thoại nào</div>';
    });
  }

  // ============================================================
  // UNIFIED MODAL: scope segmented + cross-doc awareness
  // ============================================================
  function updateScopeUI() {
    var box = document.getElementById('ms-scope-box');
    if (!box) return;
    if (entryDoc) {
      box.classList.add('on');
      document.getElementById('ms-scope-doc-text').textContent = entryDoc.doc_no + (entryDoc.doc_label ? ' · ' + entryDoc.doc_label : '');
      document.getElementById('ms-seg-doc').classList.toggle('active', scopeMode === 'DOC');
      document.getElementById('ms-seg-all').classList.toggle('active', scopeMode === 'ALL');
    } else {
      box.classList.remove('on');
    }
  }

  // Chuyen segmented "Chung tu nay" / "Tat ca" (goi tu onclick trong HTML)
  window.msSetScope = function (mode) {
    scopeMode = mode;
    updateScopeUI();
    loadConvList();
  };

  // ============================================================
  // FILTER: dropdown loai hoi thoai (chip 1) + toggle chua doc (chip 2)
  // ============================================================
  function closeTypeMenu() {
    var trigger = document.getElementById('ms-type-trigger');
    var menu = document.getElementById('ms-type-menu');
    if (trigger) trigger.classList.remove('open');
    if (menu) menu.classList.remove('open');
  }

  window.msToggleTypeMenu = function (e) {
    e.stopPropagation();
    document.getElementById('ms-type-trigger').classList.toggle('open');
    document.getElementById('ms-type-menu').classList.toggle('open');
  };

  window.msSelectTypeFilter = function (btn) {
    activeFilter = btn.dataset.filter;
    document.querySelectorAll('.ms-filter-menu-item').forEach(function (i) {
      i.classList.remove('selected');
    });
    btn.classList.add('selected');
    document.getElementById('ms-type-trigger-label').textContent = btn.querySelector('span').textContent;
    closeTypeMenu();
    loadConvList();
  };

  window.msToggleUnreadFilter = function () {
    unreadOnly = !unreadOnly;
    document.getElementById('ms-unread-toggle').classList.toggle('active', unreadOnly);
    loadConvList();
  };

  // ── Tong hop unread cho seg-count + reconcile banner luc init/reconnect ──
  function refreshUnreadSummary() {
    if (!AUS_ID) return;
    nodeGet('/unread-summary/' + AUS_ID, function (d) {
      if (!d) return;
      if (entryDoc) {
        var byDoc = d.by_doc || [];
        var n = 0;
        for (var i = 0; i < byDoc.length; i++) {
          if (byDoc[i].doc_no === entryDoc.doc_no) { n = byDoc[i].unread; break; }
        }
        var cEl = document.getElementById('ms-seg-doc-count');
        if (cEl) cEl.textContent = n > 0 ? n : '';
      }
    });
  }

  // ── Cross-doc banner: tin moi den o hoi thoai NGOAI scope hien tai ──
  function pushCrossDoc(convId, docNo, name) {
    crossDocQueue.push({ convId: convId, docNo: docNo || null, name: name });
    showCrossDocBanner();
  }
  function showCrossDocBanner() {
    var banner = document.getElementById('ms-crossdoc-banner');
    if (!banner) return;
    if (scopeMode !== 'DOC' || !crossDocQueue.length) { banner.classList.remove('on'); return; }
    var n = crossDocQueue.length;
    var last = crossDocQueue[crossDocQueue.length - 1];
    var where = last.docNo ? ('chứng từ <b>' + last.docNo + '</b>') : ('<b>' + (last.name || '') + '</b>');
    document.getElementById('ms-crossdoc-text').innerHTML =
      n === 1 ? ('Tin mới ở ' + where) : (n + ' tin mới ở hội thoại khác · mới nhất: ' + where);
    banner.classList.add('on');
  }
  window.msCloseCrossDocBanner = function () {
    var banner = document.getElementById('ms-crossdoc-banner');
    if (banner) banner.classList.remove('on');
  };
  window.msViewCrossDoc = function () {
    var last = crossDocQueue[crossDocQueue.length - 1];
    crossDocQueue = [];
    msCloseCrossDocBanner();
    scopeMode = 'ALL';
    updateScopeUI();
    loadConvList();
    if (last) setTimeout(function () { window.msSelectConv(last.convId, null); }, 200);
  };

  // ── Chọn hội thoại (gọi từ PL/SQL onclick) ─────────────────
  window.msSelectConv = function (convId, convType) {
    if (!convId) return;
    activeConvId = convId;
    if (window.msCloseConvSearch) window.msCloseConvSearch();   // đóng ô tìm khi đổi hội thoại

    // Bỏ khỏi hàng đợi cross-doc nếu vừa mở đúng hội thoại đó
    if (crossDocQueue.length) {
      crossDocQueue = crossDocQueue.filter(function (q) { return q.convId != convId; });
      showCrossDocBanner();
    }

    // Mark active item
    document.querySelectorAll('.ms-conv-item').forEach(function (el) {
      el.classList.toggle('active', el.dataset.convId == convId);
    });

    // Hiển thị các panel
    hideEmptyState();
    document.getElementById('ms-chat-header').style.display = 'flex';
    document.getElementById('ms-messages').style.display    = 'flex';
    document.getElementById('ms-input-area').style.display  = 'block';

    // Right panel LUÔN mở khi chọn hội thoại (mọi loại DM/nhóm/DOC).
    // Người dùng vẫn đóng được bằng nút thông tin / nút ✕.
    _infoVisible = true;
    var rightEl = document.getElementById('ms-right');
    if (rightEl) rightEl.style.display = 'flex';
    var infoBtn = document.getElementById('ms-toggle-info-btn');
    if (infoBtn) infoBtn.classList.add('active');

    // Load dữ liệu
    loadConvHeader(convId, convType);
    loadThread(convId);
    loadInfoPanel(convId);

    // Mark read (không reload lại toàn bộ list ngay, dùng delay)
    nodePost('/read/' + convId + '/' + AUS_ID, {}, function () {
      var activeItem = document.querySelector('.ms-conv-item.active');
      if (activeItem) {
        var badge = activeItem.querySelector('.ms-ci-badge');
        if (badge) badge.remove();
        activeItem.classList.remove('unread');
      }
    });
  };

  // ── Load header của conv đang chọn ─────────────────────────
  function loadConvHeader(convId, convType) {
    var headerAv   = document.getElementById('ms-chat-header-av');
    var headerName = document.getElementById('ms-chat-header-name');
    var headerSub  = document.getElementById('ms-chat-header-sub');

    // Placeholder ngay lập tức
    headerAv.className   = convType === 'CHANNEL' ? 'group' : '';
    headerName.textContent = '...';
    headerSub.textContent  = '';

    apexCall('msConvHeaderJson', { x01: convId }, 'json', function (d) {
      if (!d) return;
      var hue     = (convId * 47) % 360;
      var initl   = (d.name || '?').replace(/.*\s/, '').charAt(0).toUpperCase();
      var isGroup = d.type === 'CHANNEL' || (d.type === 'DOC' && (d.member_count || 0) > 2);
      headerAv.className = isGroup ? 'group' : '';
      headerAv.style.background = 'hsl(' + hue + ',55%,52%)';

      if (isGroup) {
        headerAv.innerHTML = '<i class="fa fa-users" style="font-size:15px"></i>';
        headerSub.textContent = (d.member_count || 0) + ' thành viên';
      } else {
        // Lớp avatar: ảnh (bo tròn theo container) + chữ cái fallback + chấm trạng thái NGOÀI
        var av = '';
        if (d.img) {
          av += '<img src="' + d.img + '" style="width:100%;height:100%;object-fit:cover;'
              + 'position:absolute;inset:0;border-radius:inherit" onerror="this.remove()">';
        }
        av += initl;
        av += '<span class="ms-presence ' + (d.online ? 'online' : 'offline') + '"></span>';
        headerAv.innerHTML = av;
        // Dòng trạng thái: chấm màu + chữ
        var on = !!d.online;
        headerSub.innerHTML =
            '<span style="width:6px;height:6px;border-radius:50%;display:inline-block;flex-shrink:0;'
          + 'background:' + (on ? '#22C55E' : '#CBD5E1') + '"></span>'
          + '<span style="color:' + (on ? '#16A34A' : '#94A3B8') + '">'
          + (on ? 'Đang hoạt động' : 'Không hoạt động') + '</span>';
      }
      headerName.textContent = d.name || 'Hội thoại';
    });
  }

  // ── Scroll helpers ──────────────────────────────────────────
  function isNearBottom(el, threshold) {
    return (el.scrollHeight - el.scrollTop - el.clientHeight) < (threshold || 140);
  }

  // Wire reply buttons trong 1 scope. `_wired` guard tránh gắn listener trùng
  // khi gọi lại trên cùng node (append-only refresh).
  function wireReplyButtons(scope) {
    scope.querySelectorAll('[data-reply-id]').forEach(function (btn) {
      if (btn._wired) return;
      btn._wired = true;
      btn.addEventListener('click', function () {
        msStartReply(this.dataset.replyId, this.dataset.replyName, this.dataset.replyBody);
      });
    });
  }

  // ── Load thread tin nhắn (FULL — dùng khi chuyển hội thoại) ──
  // Vẽ lại toàn bộ thread + scroll cứng xuống cuối (không animate bulk).
  function loadThread(convId) {
    var msgEl = document.getElementById('ms-messages');
    if (!msgEl) return;
    _threadConvId = convId;
    msgEl.innerHTML = skeletonHtml(4);

    apexCall('msMsgThreadHtml', { x01: convId }, 'text', function (html) {
      // Race guard: user đã chuyển sang conv khác khi request đang bay
      if (_threadConvId !== convId) return;
      msgEl.innerHTML = html || '<div style="text-align:center;padding:40px;color:#94A3B8">Chưa có tin nhắn nào</div>';
      wireReplyButtons(msgEl);
      msLoadPinBanner(convId);
      // Scroll cứng xuống cuối sau khi layout xong (rAF thay cho setTimeout 50ms)
      requestAnimationFrame(function () { msgEl.scrollTop = msgEl.scrollHeight; });
    });
  }

  // ── Refresh thread (INCREMENTAL — gửi / nhận real-time) ──────
  // Chỉ chèn các tin nhắn MỚI vào cuối + animate riêng, không vẽ lại
  // toàn bộ thread → hết flicker. Giữ vị trí scroll nếu user đang đọc lên trên.
  function refreshThread(convId) {
    var msgEl = document.getElementById('ms-messages');
    if (!msgEl) return;
    // Chưa render conv này (hoặc thread rỗng) → full load
    if (_threadConvId !== convId || !msgEl.querySelector('.ms-msg-row')) {
      loadThread(convId);
      return;
    }

    apexCall('msMsgThreadHtml', { x01: convId }, 'text', function (html) {
      if (_threadConvId !== convId) return;

      var stickToBottom = isNearBottom(msgEl, 140);

      var tmp = document.createElement('div');
      tmp.innerHTML = html || '';
      var newRows = tmp.querySelectorAll('.ms-msg-row');
      if (!newRows.length) return;

      // Tập msg_id đang có trong DOM
      var have = {};
      msgEl.querySelectorAll('.ms-msg-row').forEach(function (r) {
        have[r.getAttribute('data-msg-id')] = true;
      });

      // Append các tin chưa có. Giữ nguyên grouping avatar do server tính sẵn.
      var appended = [];
      newRows.forEach(function (row) {
        if (have[row.getAttribute('data-msg-id')]) return;
        var node = row.cloneNode(true);
        node.classList.add('ms-msg-enter');
        msgEl.appendChild(node);
        wireReplyButtons(node);
        appended.push(node);
      });
      if (!appended.length) return;

      // Kích hoạt animation enter ở frame kế tiếp
      requestAnimationFrame(function () {
        appended.forEach(function (n) {
          n.classList.add('ms-msg-enter-active');
          n.addEventListener('transitionend', function te() {
            n.classList.remove('ms-msg-enter', 'ms-msg-enter-active');
            n.removeEventListener('transitionend', te);
          });
        });
        // Chỉ auto-scroll nếu user đang ở cuối thread (không giật khi đang đọc lên)
        if (stickToBottom) {
          msgEl.scrollTo({ top: msgEl.scrollHeight, behavior: 'smooth' });
        }
      });
    });
  }

  // ── Empty / active state ────────────────────────────────────
  function showEmptyState() {
    var el = document.getElementById('ms-no-conv');
    if (el) el.style.display = 'flex';
    document.getElementById('ms-chat-header').style.display = 'none';
    document.getElementById('ms-messages').style.display    = 'none';
    document.getElementById('ms-input-area').style.display  = 'none';
    var pin = document.getElementById('ms-pin-banner');
    if (pin) pin.classList.remove('visible', 'expanded');
  }
  function hideEmptyState() {
    var el = document.getElementById('ms-no-conv');
    if (el) el.style.display = 'none';
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================
  window.msSendMessage = function () {
    if (!activeConvId) return;

    // Co file dang preview (tu paste) -> gui theo luong file+caption, khong gui text rieng
    var pendingDropzone = document.getElementById('P10022710201_UPLOAD_FILE_DROPZONE');
    if (pendingDropzone && pendingDropzone.classList.contains('has-files')) {
      msSendFileMessage();
      return;
    }

    var inputEl = document.getElementById('ms-chat-input');
    var body    = inputEl.innerText.trim();
    if (!body) return;

    // Clear input ngay lập tức
    inputEl.innerHTML = '';
    msCancelReply();

    nodePost('/send', {
      conv_id:         activeConvId,
      aus_id:          AUS_ID,
      body:            body,
      reply_to_msg_id: replyTo ? replyTo.id : null
    }, function (d) {
      if (d && (d.status === 'ok' || d.msg)) {
        refreshThread(activeConvId);
        loadConvList();
      } else if (d && d.error) {
        inputEl.innerText = body;
        console.error('[Messenger] Send error:', d.error);
      }
    });
  };

  // ============================================================
  // INPUT TOOLBAR
  // ============================================================
  // Nguon cua file dang chon trong P10022710201_UPLOAD_FILE:
  //  'plus'  = bam nut "+" -> gui ngay nhu Zalo, khong qua preview
  //  'paste' = paste vao o nhap -> hien preview, cho bam Gui
  var _pendingFileSource = null;

  // Nut "+" mo thang APEX File Browse item (1 nut duy nhat cho anh/video/tep tin -
  // khong con dropdown chia 2 option vi item nhan moi loai file). Cung page, khong
  // qua iframe. APEX render item thanh dropzone wrapper -> click vao dropzone chu
  // khong phai input an ben trong.
  window.msTriggerFileUpload = function () {
    _pendingFileSource = 'plus';
    var dropzone = document.getElementById('P10022710201_UPLOAD_FILE_DROPZONE');
    if (dropzone) dropzone.click();
  };

  // ============================================================
  // FILE PREVIEW BAR
  // Doc truc tiep thong tin APEX da tu render trong DROPZONE (ten file,
  // dung luong, mime-type) thay vi tu quan ly File object - dam bao luon
  // dong bo voi trang thai that cua item, khong can bang DB nao.
  // ============================================================
  // Map duoi file -> mau + nhan chu (kieu Zalo/Messenger, khong dung logo brand that)
  var FILE_TYPE_STYLES = {
    doc:  { bg: '#EFF6FF', color: '#2563EB', label: 'DOC' },
    docx: { bg: '#EFF6FF', color: '#2563EB', label: 'DOC' },
    xls:  { bg: '#ECFDF5', color: '#15803D', label: 'XLS' },
    xlsx: { bg: '#ECFDF5', color: '#15803D', label: 'XLS' },
    csv:  { bg: '#ECFDF5', color: '#15803D', label: 'CSV' },
    ppt:  { bg: '#FFF7ED', color: '#C2410C', label: 'PPT' },
    pptx: { bg: '#FFF7ED', color: '#C2410C', label: 'PPT' },
    pdf:  { bg: '#FEF2F2', color: '#DC2626', label: 'PDF' },
    zip:  { bg: '#FFFBEB', color: '#B45309', label: 'ZIP' },
    rar:  { bg: '#FFFBEB', color: '#B45309', label: 'RAR' },
    '7z': { bg: '#FFFBEB', color: '#B45309', label: '7Z' }
  };
  var FILE_TYPE_DEFAULT = { bg: '#F1F5F9', color: '#475569', label: null };

  function getFileTypeStyle(fileName) {
    var ext = (fileName.split('.').pop() || '').toLowerCase();
    return FILE_TYPE_STYLES[ext] || FILE_TYPE_DEFAULT;
  }

  // Build 1 chip preview cho 1 dropzone APEX (file hoac image). Tra ve null neu chua co file.
  function buildFileChip(dropzoneId, inputId, forceImage) {
    var dropzone = document.getElementById(dropzoneId);
    if (!dropzone || !dropzone.classList.contains('has-files')) return null;

    var nameEl = dropzone.querySelector('.a-FileDrop-heading');
    var sizeEl = dropzone.querySelector('.a-FileDrop-description');
    var iconEl = dropzone.querySelector('.a-FileDrop-icon');
    var mimeType = iconEl ? (iconEl.getAttribute('data-mime-type') || '') : '';

    var inputEl = document.getElementById(inputId);
    var rawFile = inputEl && inputEl.files && inputEl.files[0];
    var fileName = (nameEl && nameEl.textContent) || (rawFile && rawFile.name) || '';
    var fileSize = sizeEl ? sizeEl.textContent : '';
    var isImage = forceImage || (mimeType.indexOf('image/') === 0 && !!rawFile);

    var chip = document.createElement('div');
    chip.className = 'ms-file-chip' + (isImage && rawFile ? ' ms-file-chip--image' : '');

    if (isImage && rawFile) {
      var img = document.createElement('img');
      img.className = 'ms-file-chip-thumb';
      img.src = URL.createObjectURL(rawFile);
      chip.appendChild(img);
    } else {
      var typeStyle = getFileTypeStyle(fileName);
      var iconWrap = document.createElement('div');
      iconWrap.className = 'ms-file-chip-icon';
      iconWrap.style.background = typeStyle.bg;
      iconWrap.style.color = typeStyle.color;
      if (typeStyle.label) {
        iconWrap.classList.add('ms-file-chip-icon--label');
        iconWrap.textContent = typeStyle.label;
      } else {
        iconWrap.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>';
      }
      chip.appendChild(iconWrap);
    }

    if (!(isImage && rawFile)) {
      var textWrap = document.createElement('div');
      textWrap.className = 'ms-file-chip-text';
      var nameSpan = document.createElement('span');
      nameSpan.className = 'ms-file-chip-name';
      nameSpan.textContent = fileName;
      var sizeSpan = document.createElement('span');
      sizeSpan.className = 'ms-file-chip-size';
      sizeSpan.textContent = fileSize;
      textWrap.appendChild(nameSpan);
      textWrap.appendChild(sizeSpan);
      chip.appendChild(textWrap);
    }

    var removeBtn = document.createElement('button');
    removeBtn.type = 'button';
    removeBtn.className = 'ms-file-chip-remove';
    removeBtn.title = 'Bỏ file này';
    removeBtn.innerHTML = '<svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
    removeBtn.onclick = function () {
      // Bam ho nut Remove that cua APEX item -> tu dong cap nhat lai DOM, observer se sync lai bar
      var apexRemoveBtn = dropzone.querySelector('.a-FileDrop-remove');
      if (apexRemoveBtn) apexRemoveBtn.click();
    };
    chip.appendChild(removeBtn);

    return chip;
  }

  // Chi dung cho luong PASTE - luong "+" gui ngay, khong qua preview bar
  function syncFilePreviewFromDropzone() {
    var bar = document.getElementById('ms-file-preview-bar');
    if (!bar) return;
    bar.innerHTML = '';

    var chip = buildFileChip('P10022710201_UPLOAD_FILE_DROPZONE', 'P10022710201_UPLOAD_FILE_input', false);
    if (chip) bar.appendChild(chip);

    bar.classList.toggle('has-files', !!chip);
  }

  // ============================================================
  // GUI FILE - upload TRUC TIEP qua callback APEX msUploadFile.
  // Vi sao KHONG goi Node: pkg_upload_file nam trong DB cua APEX, KHONG nam
  // trong DB ma Node chat-server ket noi -> goi tu Node se PLS-00201. Callback
  // APEX chay ngay trong DB co package nen goi dung cho.
  // Item File Browse + apex_application_temp_files RONG trong AJAX (chi submit
  // form that moi gui bytes) nen KHONG dung duoc -> client tu doc File object,
  // ma hoa base64, cat chunk vao f01 array gui kem apex.server.process.
  // Callback ghep base64 -> BLOB -> UploadFileChat -> INSERT CHAT_MESSENGERS
  // -> COMMIT -> tra response co cac field enrich.
  // Real-time: callback KHONG tu UTL_HTTP sang Node (may DB khong route toi Node
  // -> ORA-12535 timeout). Thay vao do BROWSER nhan response roi tu goi Node
  // /broadcast-message (browser toi duoc Node, dung duong /send text dang chay).
  // ============================================================
  var FILE_B64_CHUNK = 30000;   // <= 32767 (gioi han phan tu g_f01)
  function msSendFileMessage() {
    if (!activeConvId) return;
    var dropzone = document.getElementById('P10022710201_UPLOAD_FILE_DROPZONE');
    if (!dropzone || !dropzone.classList.contains('has-files')) return;

    var input = document.getElementById('P10022710201_UPLOAD_FILE_input');
    var files = (input && input.files) ? Array.prototype.slice.call(input.files) : [];
    if (!files.length) return;

    var inputEl = document.getElementById('ms-chat-input');
    var caption = inputEl ? inputEl.innerText.trim() : '';
    if (inputEl) inputEl.innerHTML = '';
    var replyId = replyTo ? replyTo.id : null;
    if (replyTo) window.msCancelReply();

    // Don dep item APEX ngay (da giu tham chieu File object trong `files`)
    var apexRemoveBtn = dropzone.querySelector('.a-FileDrop-remove');
    if (apexRemoveBtn) apexRemoveBtn.click();

    // Gui tuan tu tung file -> moi file 1 tin nhan. Caption + reply gan file dau.
    (function sendNext(i) {
      if (i >= files.length) return;
      uploadOneFile(files[i], i === 0 ? caption : '', i === 0 ? replyId : null,
                    function () { sendNext(i + 1); });
    })(0);
  }

  function uploadOneFile(file, caption, replyId, onDone) {
    var convId = activeConvId;   // giu lai phong khi user doi conv giua chung
    var reader = new FileReader();
    reader.onload = function () {
      // result = "data:<mime>;base64,<payload>" -> bo prefix, lay base64 thuan
      var dataUrl = reader.result || '';
      var comma   = dataUrl.indexOf(',');
      var b64     = comma >= 0 ? dataUrl.substring(comma + 1) : '';
      if (!b64) {
        console.error('[Messenger] Khong doc duoc file:', file.name);
        if (onDone) onDone();
        return;
      }

      // Cat base64 thanh chunk <= 30000 ky tu -> mang f01
      var chunks = [];
      for (var p = 0; p < b64.length; p += FILE_B64_CHUNK) {
        chunks.push(b64.substring(p, p + FILE_B64_CHUNK));
      }

      // Goi thang apex.server.process (khong qua apexCall) de onDone luon chay
      // ke ca khi loi transport -> khong ket vong gui tuan tu nhieu file.
      apex.server.process('msUploadFile', {
        f01: chunks,
        x01: convId,
        x02: file.name,
        x03: caption || '',
        x04: replyId || ''
      }, {
        pageId:   PAGE_ID,
        dataType: 'json',
        success: function (r) {
          if (!r || r.error || r.state !== 'success') {
            console.error('[Messenger] Upload file that bai:',
              r && (r.error || r.message || JSON.stringify(r)));
          } else {
            refreshThread(convId);
            loadConvList();
            // DB khong route toi Node duoc (ORA-12535) -> browser tu goi Node
            // phat SSE cho cac thanh vien khac. Node /broadcast-message CHI fan-out
            // (khong dung DB) va da loai tru nguoi gui qua aus_id.
            nodePost('/broadcast-message', {
              conv_id:         r.conv_id,
              msg_id:          r.msg_id,
              aus_id:          r.aus_id,
              from_name:       r.from_name,
              body:            r.body,
              fil_id:          r.fil_id,
              file_name:       r.file_name,
              file_disp_name:  r.file_disp_name,
              reply_to_msg_id: r.reply_to_msg_id,
              doc_type:        r.doc_type,
              doc_no:          r.doc_no,
              conv_type:       r.conv_type,
              conv_name:       r.conv_name
            });
          }
          if (onDone) onDone();
        },
        error: function (xhr) {
          console.error('[Messenger] msUploadFile error:', xhr.status, xhr.responseText);
          if (onDone) onDone();
        }
      });
    };
    reader.onerror = function () {
      console.error('[Messenger] Loi doc file:', file.name);
      if (onDone) onDone();
    };
    reader.readAsDataURL(file);
  }

  var MS_EMOJI_DATA = {
    'Thuong dung': ['😀','😂','🥹','😊','😍','🤔','😅','🤗','😎','🥳','😭','😤','🙄','😴','🤩','🫠'],
    'Phan ung':    ['❤️','👍','👎','👏','🙏','🔥','✅','❌','⚠️','💯','✨','🎉','🎊','💪','🫡','👀'],
    'Cong viec':   ['📎','📌','🔗','📋','💡','🔔','📢','📣','📝','📊','📈','🗓️','⏰','🏆','💼','🔑'],
  };
  var _emojiPickerOpen = false;
  window.msToggleEmojiPicker = function (e) {
    e.stopPropagation();
    _emojiPickerOpen = !_emojiPickerOpen;
    var picker = document.getElementById('ms-emoji-picker');
    if (picker) picker.classList.toggle('open', _emojiPickerOpen);
    if (_emojiPickerOpen) {
      msRenderEmojiGrid();
      setTimeout(function () {
        var inp = document.getElementById('ms-emoji-search-inp');
        if (inp) inp.focus();
      }, 50);
    }
  };
  window.msFilterEmoji = function (q) { msRenderEmojiGrid(q); };
  function msRenderEmojiGrid(q) {
    var wrap = document.getElementById('ms-emoji-grid-wrap');
    if (!wrap) return;
    var query = (q || '').toLowerCase();
    var html = '';
    for (var cat in MS_EMOJI_DATA) {
      var emojis = MS_EMOJI_DATA[cat].filter(function (em) { return !query || em.includes(query); });
      if (!emojis.length) continue;
      html += '<div class="ms-emoji-cat-label">' + cat + '</div><div class="ms-emoji-grid">';
      emojis.forEach(function (em) {
        html += '<button type="button" class="ms-emoji-btn" onclick="msInsertEmoji(\'' + em + '\')">' + em + '</button>';
      });
      html += '</div>';
    }
    wrap.innerHTML = html || '<div style="padding:16px;text-align:center;color:#94A3B8;font-size:12px;">Khong tim thay emoji</div>';
  }
  window.msInsertEmoji = function (em) {
    var input = document.getElementById('ms-chat-input');
    if (!input) return;
    input.focus();
    var sel = window.getSelection();
    if (sel && sel.rangeCount) {
      var range = sel.getRangeAt(0);
      range.deleteContents();
      range.insertNode(document.createTextNode(em));
      range.collapse(false);
    } else {
      input.textContent += em;
    }
  };

  var _fmtToolbarTimer = null;
  function setFmtToolbarVisible(visible) {
    clearTimeout(_fmtToolbarTimer);
    var toolbar = document.getElementById('ms-fmt-toolbar');
    if (!toolbar) return;
    if (visible) {
      toolbar.classList.add('visible');
    } else {
      _fmtToolbarTimer = setTimeout(function () { toolbar.classList.remove('visible'); }, 150);
    }
  }

  // ============================================================
  // REPLY
  // ============================================================
  window.msStartReply = function (id, name, body) {
    replyTo = { id: id, name: name, body: body };
    document.getElementById('ms-reply-name').textContent = name || '';
    document.getElementById('ms-reply-body').textContent = (body || '').substring(0, 80);
    document.getElementById('ms-reply-preview').style.display = 'block';
    document.getElementById('ms-chat-input').focus();
  };

  window.msCancelReply = function () {
    replyTo = null;
    document.getElementById('ms-reply-preview').style.display = 'none';
  };

  // ============================================================
  // DOT-MENU HỘI THOẠI (context menu trên từng dòng)
  // ============================================================
  window.msOpenConvMenu = function (convId, convType, e) {
    e.stopPropagation();          // không kích hoạt msSelectConv của conv item
    var btn  = e.currentTarget;
    var item = btn.closest('.ms-conv-item');

    if (_convMenuId == convId) { msCloseConvMenu(); return; }
    msCloseConvMenu();
    _convMenuId = convId;
    if (item) item.classList.add('menu-open');

    // DOC 1-1 cũng có partnerId (server chỉ trả khi <=2 thành viên) → coi như DM cho menu này
    var isDM      = convType === 'DM' || convType === 'DOC';
    var partnerId = item ? item.dataset.partnerId : '';
    var menu      = document.getElementById('ms-conv-menu');

    var pinSVG   = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 17v5"/><path d="M5 8.5A5.5 5.5 0 0 1 10.5 3h3A5.5 5.5 0 0 1 19 8.5v.5l1.5 3.5H3.5L5 9z"/></svg>';
    var hideSVG  = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94"/><path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';
    var groupSVG = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><line x1="23" y1="11" x2="17" y2="11"/><line x1="20" y1="8" x2="20" y2="14"/></svg>';
    var trashSVG = '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>';

    var html =
      '<button type="button" class="ms-conv-menu-item" onclick="msConvPin(' + convId + ')">' + pinSVG + '<span>Ghim hội thoại</span></button>' +
      '<button type="button" class="ms-conv-menu-item" onclick="msConvHide(' + convId + ')">' + hideSVG + '<span>Ẩn cuộc trò chuyện</span></button>';
    if (isDM && partnerId) {
      html += '<div class="ms-conv-menu-sep"></div>' +
              '<button type="button" class="ms-conv-menu-item" onclick="msConvAddToGroup(' + partnerId + ')">' + groupSVG + '<span>Thêm vào nhóm</span></button>';
    }
    html += '<div class="ms-conv-menu-sep"></div>' +
            '<button type="button" class="ms-conv-menu-item danger" onclick="msConvDelete(' + convId + ')">' + trashSVG + '<span>Xóa hội thoại</span></button>';
    menu.innerHTML = html;

    var rect = btn.getBoundingClientRect();
    menu.style.top  = (rect.bottom + 4) + 'px';
    menu.style.left = Math.max(8, rect.right - 184) + 'px';
    requestAnimationFrame(function () { menu.classList.add('open'); });
  };

  window.msCloseConvMenu = function () {
    if (_convMenuId == null) return;
    var menu = document.getElementById('ms-conv-menu');
    if (menu) menu.classList.remove('open');
    document.querySelectorAll('.ms-conv-item.menu-open').forEach(function (el) {
      el.classList.remove('menu-open');
    });
    _convMenuId = null;
  };

  // ── Actions: gọi APEX callback (PL/SQL ghi DB) rồi refresh list ──
  window.msConvPin = function (convId) {
    msCloseConvMenu();
    apexCall('msPinConv', { x01: convId }, 'text', function () { loadConvList(); });
  };
  window.msConvHide = function (convId) {
    msCloseConvMenu();
    apexCall('msHideConv', { x01: convId }, 'text', function () {
      if (activeConvId == convId) showEmptyState();
      activeConvId = (activeConvId == convId) ? null : activeConvId;
      loadConvList();
    });
  };
  window.msConvDelete = function (convId) {
    msCloseConvMenu();
    if (!window.confirm('Xóa hội thoại này khỏi danh sách của bạn?')) return;
    apexCall('msDeleteConv', { x01: convId }, 'text', function () {
      if (activeConvId == convId) { showEmptyState(); activeConvId = null; }
      loadConvList();
    });
  };

  // Thêm vào nhóm: mở màn soạn tin, preselect đối phương
  window.msConvAddToGroup = function (partnerId) {
    msCloseConvMenu();
    msOpenNewConv();
    if (partnerId) {
      selectedMembers = [Number(partnerId)];
      msUpdateComposeBtn();
      loadS2Contacts('');
    }
  };

  // ============================================================
  // REACTIONS (quick-react 6 emoji)
  // ============================================================
  var REACT_EMOJIS = ['👍', '❤️', '😆', '😮', '😢', '🙏'];

  window.msOpenReactBar = function (msgId, e) {
    e.stopPropagation();
    var bar = document.getElementById('ms-react-bar');
    if (!bar) return;
    bar.innerHTML = REACT_EMOJIS.map(function (em) {
      return '<button type="button" class="ms-react-emoji" onclick="msToggleReaction(' +
             msgId + ',\'' + em + '\')">' + em + '</button>';
    }).join('');
    var rect = e.currentTarget.getBoundingClientRect();
    bar.style.left = Math.max(8, rect.left + rect.width / 2 - 108) + 'px';
    bar.style.top  = (rect.top - 46) + 'px';
    requestAnimationFrame(function () { bar.classList.add('open'); });
    _reactBarOpen = true;
  };

  function msCloseReactBar() {
    var bar = document.getElementById('ms-react-bar');
    if (bar) bar.classList.remove('open');
    _reactBarOpen = false;
  }

  // Toggle reaction của mình trên 1 tin (gọi từ chip lẫn thanh quick-react)
  window.msToggleReaction = function (msgId, emoji) {
    msCloseReactBar();
    var row = document.querySelector('.ms-msg-row[data-msg-id="' + msgId + '"]');
    if (!row) return;
    var chip = row.querySelector('.ms-reaction-chip[data-emoji="' + emoji + '"]');
    var mine = chip ? chip.classList.contains('mine') : false;
    applyReactionDom(row, emoji, !mine);     // optimistic
    apexCall('msToggleReaction', { x01: msgId, x02: emoji }, 'json', function (d) {
      if (!d || typeof d.reacted === 'undefined') return;
      var now  = row.querySelector('.ms-reaction-chip[data-emoji="' + emoji + '"]');
      var nowM = now ? now.classList.contains('mine') : false;
      if ((d.reacted === 1) !== nowM) applyReactionDom(row, emoji, d.reacted === 1);  // reconcile
    });
  };

  function applyReactionDom(row, emoji, reacted) {
    var msgId = row.getAttribute('data-msg-id');
    var box   = row.querySelector('.ms-msg-reactions');
    if (!box) {
      if (!reacted) return;
      box = document.createElement('div');
      box.className = 'ms-msg-reactions';
      box.setAttribute('data-msg-id', msgId);
      var col   = row.querySelector('.ms-msg-col');
      var hover = col.querySelector('.ms-msg-hover-actions');
      col.insertBefore(box, hover || null);
    }
    var chip = box.querySelector('.ms-reaction-chip[data-emoji="' + emoji + '"]');
    var cnt  = chip ? (parseInt(chip.querySelector('.ms-reaction-count').textContent, 10) || 0) : 0;
    if (reacted) {
      if (chip) {
        chip.classList.add('mine');
        chip.querySelector('.ms-reaction-count').textContent = cnt + 1;
      } else {
        chip = document.createElement('button');
        chip.type = 'button';
        chip.className = 'ms-reaction-chip mine ms-reaction-pop';
        chip.setAttribute('data-emoji', emoji);
        chip.setAttribute('onclick', 'msToggleReaction(' + msgId + ',this.dataset.emoji)');
        chip.innerHTML = '<span>' + emoji + '</span><span class="ms-reaction-count">1</span>';
        box.appendChild(chip);
      }
    } else if (chip) {
      chip.classList.remove('mine');
      var n = cnt - 1;
      if (n <= 0) {
        chip.remove();
        if (!box.querySelector('.ms-reaction-chip')) box.remove();
      } else {
        chip.querySelector('.ms-reaction-count').textContent = n;
      }
    }
  }

  // ============================================================
  // FORWARD (chuyển tiếp tin nhắn)
  // ============================================================
  window.msOpenForward = function (msgId, btn) {
    _fwdMsgId = msgId;
    _fwdBody  = (btn && btn.getAttribute('data-fwd-body')) || '';
    _fwdTarget = null;
    document.getElementById('ms-fwd-quote').textContent = _fwdBody.slice(0, 120) || '(không có nội dung)';
    document.getElementById('ms-fwd-send').classList.remove('enabled');
    document.getElementById('ms-fwd-search').value = '';
    msLoadForwardList('');
    document.getElementById('ms-forward-modal').classList.add('open');
    setTimeout(function () {
      var s = document.getElementById('ms-fwd-search');
      if (s) s.focus();
    }, 80);
  };

  function msLoadForwardList(q) {
    var list = document.getElementById('ms-fwd-list');
    list.innerHTML = '<div style="padding:20px;text-align:center;color:#94A3B8;font-size:13px">Đang tải...</div>';
    apexCall('msForwardListHtml', { x01: q }, 'text', function (html) {
      list.innerHTML = html || '<div style="padding:20px;text-align:center;color:#94A3B8;font-size:13px">Không có hội thoại</div>';
    });
  }

  window.msForwardSearch = function (q) {
    clearTimeout(_fwdSearchTimer);
    _fwdSearchTimer = setTimeout(function () { msLoadForwardList(q); }, 250);
  };

  window.msSelectForward = function (el) {
    _fwdTarget = { id: el.getAttribute('data-conv-id'), name: el.getAttribute('data-conv-name') };
    document.querySelectorAll('.ms-fwd-item').forEach(function (x) { x.classList.remove('selected'); });
    el.classList.add('selected');
    document.getElementById('ms-fwd-send').classList.add('enabled');
  };

  window.msSendForward = function () {
    if (!_fwdTarget) return;
    var target = _fwdTarget;
    msCloseForward();
    nodePost('/send', {
      conv_id: target.id,
      aus_id:  AUS_ID,
      body:    _fwdBody,
      reply_to_msg_id: null
    }, function (d) {
      if (d && (d.status === 'ok' || d.msg)) {
        loadConvList();
        if (target.id == activeConvId) refreshThread(activeConvId);
      }
    });
  };

  window.msCloseForward = function (e) {
    if (e && e.target !== document.getElementById('ms-forward-modal')) return;
    document.getElementById('ms-forward-modal').classList.remove('open');
  };

  // ============================================================
  // PIN MESSAGE (ghim tin trong hội thoại)
  // ============================================================
  window.msTogglePinMsg = function (msgId) {
    if (!activeConvId) return;
    apexCall('msTogglePinMsg', { x01: activeConvId, x02: msgId }, 'json', function (d) {
      if (d && typeof d.pinned !== 'undefined') applyPinMarkDom(msgId, d.pinned === 1);
      msLoadPinBanner(activeConvId);
    });
  };

  function applyPinMarkDom(msgId, pinned) {
    var row = document.querySelector('.ms-msg-row[data-msg-id="' + msgId + '"]');
    if (!row) return;
    var col  = row.querySelector('.ms-msg-col');
    var mark = col.querySelector('.ms-msg-pinned-mark');
    if (pinned && !mark) {
      mark = document.createElement('div');
      mark.className = 'ms-msg-pinned-mark';
      mark.innerHTML = '<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 17v5"/><path d="M5 8.5A5.5 5.5 0 0 1 10.5 3h3A5.5 5.5 0 0 1 19 8.5v.5l1.5 3.5H3.5L5 9z"/></svg>Đã ghim';
      col.insertBefore(mark, col.firstChild);
    } else if (!pinned && mark) {
      mark.remove();
    }
  }

  function msLoadPinBanner(convId) {
    var banner = document.getElementById('ms-pin-banner');
    if (!banner) return;
    apexCall('msPinnedListHtml', { x01: convId }, 'text', function (html) {
      var listEl = document.getElementById('ms-pin-list');
      listEl.innerHTML = html || '';
      var items = listEl.querySelectorAll('.ms-pin-item');
      if (!items.length) { banner.classList.remove('visible', 'expanded'); return; }
      var countEl = document.getElementById('ms-pin-banner-count');
      countEl.textContent = items.length > 1 ? items.length : '';
      countEl.style.display = items.length > 1 ? '' : 'none';
      var body = items[0].querySelector('.ms-pin-item-body');
      document.getElementById('ms-pin-banner-text').textContent = body ? body.textContent : '';
      banner.classList.add('visible');
    });
  }

  window.msTogglePinList = function () {
    document.getElementById('ms-pin-banner').classList.toggle('expanded');
  };

  window.msJumpToMsg = function (msgId) {
    document.getElementById('ms-pin-banner').classList.remove('expanded');
    var row = document.querySelector('.ms-msg-row[data-msg-id="' + msgId + '"]');
    if (!row) return;     // tin nằm ngoài 50 tin gần nhất — không cuộn được
    row.scrollIntoView({ behavior: 'smooth', block: 'center' });
    row.classList.remove('ms-msg-highlight');
    void row.offsetWidth;                       // reflow để re-trigger animation
    row.classList.add('ms-msg-highlight');
    setTimeout(function () { row.classList.remove('ms-msg-highlight'); }, 1700);
  };

  // ============================================================
  // TÌM KIẾM TIN NHẮN TRONG HỘI THOẠI (#ms-msgsearch)
  // ============================================================
  var _csConvId = null;
  var _csTimer  = null;

  window.msOpenConvSearch = function (convId) {
    _csConvId = convId || activeConvId;
    if (!_csConvId) return;
    var box = document.getElementById('ms-msgsearch');
    if (box) box.style.display = 'block';
    var sbtn = document.getElementById('ms-header-search-btn');
    if (sbtn) sbtn.classList.add('active');
    var res = document.getElementById('ms-cs-results'); if (res) res.innerHTML = '';
    var inp = document.getElementById('ms-cs-input');
    if (inp) { inp.value = ''; setTimeout(function () { inp.focus(); }, 60); }
  };

  window.msCloseConvSearch = function () {
    clearTimeout(_csTimer);
    var box = document.getElementById('ms-msgsearch');
    if (box) box.style.display = 'none';
    var sbtn = document.getElementById('ms-header-search-btn');
    if (sbtn) sbtn.classList.remove('active');
    var res = document.getElementById('ms-cs-results'); if (res) res.innerHTML = '';
  };

  // Toggle từ icon tìm kiếm trên header: đang mở thì đóng, chưa thì mở.
  window.msToggleConvSearch = function () {
    if (!activeConvId) return;
    var box = document.getElementById('ms-msgsearch');
    var isOpen = box && box.style.display !== 'none' && box.style.display !== '';
    if (isOpen) window.msCloseConvSearch();
    else        window.msOpenConvSearch(activeConvId);
  };

  window.msConvSearchInput = function (val) {
    clearTimeout(_csTimer);
    var q   = (val || '').trim();
    var res = document.getElementById('ms-cs-results');
    if (!res) return;
    if (q.length < 1) { res.innerHTML = ''; return; }
    _csTimer = setTimeout(function () {
      apexCall('msSearchMsgsHtml', { x01: _csConvId, x02: q }, 'text', function (html) {
        res.innerHTML = (html && html.trim())
          ? html
          : '<div class="ms-cs-empty">Không tìm thấy tin nhắn nào</div>';
      });
    }, 280);
  };

  // Click 1 kết quả: đóng ô tìm + cuộn tới tin (nếu tin nằm trong thread đã tải).
  window.msJumpFromSearch = function (msgId) {
    msCloseConvSearch();
    msJumpToMsg(msgId);
  };

  // ============================================================
  // RIGHT PANEL (Info)
  // ============================================================
  window.msToggleInfo = function () {
    _infoVisible = !_infoVisible;
    var rightEl = document.getElementById('ms-right');
    var btn     = document.getElementById('ms-toggle-info-btn');
    rightEl.style.display = _infoVisible ? 'flex' : 'none';
    if (btn) btn.classList.toggle('active', _infoVisible);
    if (_infoVisible && activeConvId) loadInfoPanel(activeConvId);
  };

  function loadInfoPanel(convId) {
    var el = document.getElementById('ms-info-content');
    if (!el) return;
    el.innerHTML = skeletonHtml(3);
    apexCall('msInfoHtml', { x01: convId }, 'text', function (html) {
      el.innerHTML = html;
    });
  }

  // ============================================================
  // LEFT PANEL SLIDER — New Conversation Flow
  // ============================================================

  function lpSlideTo(screen) {
    _lpScreen = screen;
    var track = document.getElementById('ms-lp-track');
    if (track) track.style.transform = 'translateX(-' + ((screen - 1) * 272) + 'px)';
  }

  // Meta (tên + hue) cho từng aus_id đã chọn — để render chip kể cả khi
  // liên hệ bị lọc khỏi danh sách bởi từ khóa tìm kiếm.
  var _memberMeta = {};

  // S1 → S2: mở màn soạn tin hợp nhất (recipient: DM + nhóm)
  window.msOpenNewConv = function () {
    _composeMode = 'new';
    _addTargetConv = null;
    selectedMembers = [];
    _memberMeta = {};
    var s = document.getElementById('ms-s2-search'); if (s) s.value = '';
    var n = document.getElementById('ms-group-name'); if (n) n.value = '';
    renderComposeChips();
    msUpdateComposeBtn();
    lpSlideTo(2);
    loadS2Contacts('');
    setTimeout(function () {
      var el = document.getElementById('ms-s2-search');
      if (el) el.focus();
    }, 320);
  };

  // Mở màn soạn tin ở chế độ "thêm thành viên vào nhóm sẵn có" (nút Thêm TV ở right panel).
  // Dùng lại S2 nhưng submit gọi callback msAddMembers thay vì /create.
  window.msOpenAddMembers = function (convId) {
    msOpenNewConv();                 // reset sạch màn soạn + slide S2
    _composeMode = 'add';
    _addTargetConv = convId || activeConvId;
    msUpdateComposeBtn();            // đổi nhãn nút + ẩn ô tên nhóm
  };

  // S2 → S1: đóng về danh sách (1 thao tác — nút ✕ hoặc Esc)
  window.msComposeClose = function () {
    lpSlideTo(1);
  };

  // Load danh sách liên hệ vào màn soạn (multi-select toggle)
  function loadS2Contacts(search) {
    var el = document.getElementById('ms-s2-contacts');
    if (!el) return;
    el.innerHTML = '<div class="ms-loading-state">Đang tải...</div>';
    apexCall('msContactsHtml', { x01: search || '' }, 'text', function (html) {
      el.innerHTML = html;
      el.querySelectorAll('.ms-contact-item').forEach(function (item) {
        var ausId = parseInt(item.dataset.ausId, 10);
        // cache meta để chip giữ tên khi bị lọc
        _memberMeta[ausId] = { name: item.dataset.name || '?', hue: item.dataset.hue || '0' };
        if (selectedMembers.indexOf(ausId) !== -1) item.classList.add('selected');
        item.addEventListener('click', function () { toggleComposeContact(this); });
      });
      renderComposeChips();
    });
  }

  function toggleComposeContact(itemEl) {
    var ausId = parseInt(itemEl.dataset.ausId, 10);
    if (itemEl.classList.contains('selected')) {
      itemEl.classList.remove('selected');
      selectedMembers = selectedMembers.filter(function (id) { return id !== ausId; });
    } else {
      itemEl.classList.add('selected');
      selectedMembers.push(ausId);
      _memberMeta[ausId] = { name: itemEl.dataset.name || '?', hue: itemEl.dataset.hue || '0' };
    }
    renderComposeChips();
    msUpdateComposeBtn();
  }

  function renderComposeChips() {
    var container = document.getElementById('ms-s2-chips');
    if (!container) return;
    var html = '';
    selectedMembers.forEach(function (ausId) {
      var meta  = _memberMeta[ausId] || { name: '?', hue: '0' };
      var name  = meta.name;
      var initl = name.replace(/.*\s/, '').charAt(0).toUpperCase();
      html += '<span class="ms-chip">'
            + '<span class="ms-chip-av" style="background:hsl(' + meta.hue + ',55%,52%)">' + initl + '</span>'
            + name.split(' ').pop()
            + '<button type="button" class="ms-chip-remove" data-aus-id="' + ausId + '">'
            + '<svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>'
            + '</button>'
            + '</span>';
    });
    container.innerHTML = html;
    container.querySelectorAll('.ms-chip-remove').forEach(function (btn) {
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        var ausId = parseInt(this.dataset.ausId, 10);
        selectedMembers = selectedMembers.filter(function (id) { return id !== ausId; });
        var itemEl = document.querySelector('#ms-s2-contacts .ms-contact-item[data-aus-id="' + ausId + '"]');
        if (itemEl) itemEl.classList.remove('selected');
        renderComposeChips();
        msUpdateComposeBtn();
      });
    });
  }

  // Nút chính động: 0 người → disabled; 1 → "Nhắn tin" (DM);
  // ≥2 → "Tạo nhóm" + hiện ô tên nhóm (tùy chọn)
  window.msUpdateComposeBtn = function () {
    var n        = selectedMembers.length;
    var btn      = document.getElementById('ms-compose-action');
    var nameWrap = document.getElementById('ms-compose-name-wrap');
    // Chế độ "thêm TV vào nhóm": không có ô tên nhóm, nút bật khi chọn ≥1 người.
    if (_composeMode === 'add') {
      if (nameWrap) nameWrap.classList.remove('visible');
      if (!btn) return;
      btn.disabled = (n === 0);
      btn.textContent = 'Thêm vào nhóm';
      return;
    }
    if (nameWrap) nameWrap.classList.toggle('visible', n >= 2);
    if (!btn) return;
    if (n >= 2)      { btn.disabled = false; btn.textContent = 'Tạo nhóm'; }
    else if (n === 1) { btn.disabled = false; btn.textContent = 'Nhắn tin'; }
    else             { btn.disabled = true;  btn.textContent = 'Nhắn tin'; }
  };

  // Debounce search màn soạn
  window.msS2Search = function (val) {
    clearTimeout(_s2SearchTimer);
    _s2SearchTimer = setTimeout(function () { loadS2Contacts(val); }, 280);
  };

  // Nút chính: 1 người → tạo DM/DOC; ≥2 → tạo nhóm (CHANNEL/DOC).
  // entryDoc đang set (modal mở từ "Trao đổi" ở trang chứng từ) → mọi hội thoại
  // mới tạo trong phiên này đều conv_type='DOC', kèm doc_type/doc_no — bất kể
  // scopeMode đang là DOC hay ALL (entryDoc = phiên modal này gắn với 1 chứng từ).
  window.msComposeSubmit = function () {
    var n = selectedMembers.length;
    if (n === 0) return;

    // Chế độ thêm thành viên vào nhóm sẵn có
    if (_composeMode === 'add') {
      var target = _addTargetConv;
      var btnA = document.getElementById('ms-compose-action');
      if (btnA) { btnA.disabled = true; btnA.textContent = 'Đang thêm...'; }
      apexCall('msAddMembers',
        { x01: target, x02: JSON.stringify(selectedMembers) }, 'json',
        function (d) {
          if (d && d.state === 'success') {
            _composeMode = 'new'; _addTargetConv = null;
            lpSlideTo(1);
            loadConvList();
            if (activeConvId == target) {
              loadThread(target);
              if (_infoVisible) loadInfoPanel(target);
            }
          } else {
            if (btnA) { btnA.disabled = false; btnA.textContent = 'Thêm vào nhóm'; }
            alert('Lỗi thêm thành viên: ' + ((d && d.error) || 'không rõ'));
          }
        });
      return;
    }

    if (n === 1) { msCreateDM(selectedMembers[0]); return; }

    // ≥2 người → nhóm. Tên tùy chọn; để trống thì auto-sinh từ tên thành viên.
    var nameEl = document.getElementById('ms-group-name');
    var name   = ((nameEl && nameEl.value) || '').trim();
    if (!name) {
      name = selectedMembers.map(function (id) {
        var m = _memberMeta[id];
        return m ? m.name.split(' ').pop() : '';
      }).filter(Boolean).join(', ');
    }
    var convType = entryDoc ? 'DOC' : 'CHANNEL';
    var payload  = {
      conv_type:      convType,
      name:           name,
      aus_id:         AUS_ID,
      member_aus_ids: selectedMembers
    };
    if (entryDoc) { payload.doc_type = entryDoc.doc_type; payload.doc_no = entryDoc.doc_no; }

    var btn = document.getElementById('ms-compose-action');
    if (btn) { btn.disabled = true; btn.textContent = 'Đang tạo...'; }
    nodePost('/create', payload, function (d) {
      if (btn) { btn.disabled = false; btn.textContent = 'Tạo nhóm'; }
      if (d && d.conv_id) {
        lpSlideTo(1);
        loadConvList();
        setTimeout(function () { window.msSelectConv(d.conv_id, convType); }, 300);
      } else if (d && d.error) {
        alert('Lỗi tạo nhóm: ' + d.error);
      }
    });
  };

  // Mở 1 hội thoại 1-1 (DM hoặc DOC, đã có hoặc vừa tạo) → về danh sách + chọn
  function openConv(convId, convType) {
    lpSlideTo(1);
    loadConvList();
    setTimeout(function () { window.msSelectConv(convId, convType); }, 300);
  }

  // Tạo DM/DOC (1 người). Chống trùng: hỏi APEX (msFindDM) xem hội thoại đã tồn tại chưa.
  // - Có → mở lại conv cũ (đã tự bỏ ẩn / rejoin phía callback).
  // - Chưa → tạo mới qua Node /create (giữ real-time cho đối phương).
  // entryDoc set → tạo conv_type='DOC' kèm doc_type/doc_no (dedup riêng theo đúng chứng từ).
  function msCreateDM(ausId) {
    var findParams = { x01: ausId };
    var convType   = entryDoc ? 'DOC' : 'DM';
    if (entryDoc) { findParams.x02 = entryDoc.doc_type; findParams.x03 = entryDoc.doc_no; }

    apexCall('msFindDM', findParams, 'json', function (d) {
      if (d && d.found && d.conv_id) {
        openConv(d.conv_id, convType);
        return;
      }
      var payload = {
        conv_type:      convType,
        aus_id:         AUS_ID,
        member_aus_ids: [ausId]
      };
      if (entryDoc) { payload.doc_type = entryDoc.doc_type; payload.doc_no = entryDoc.doc_no; }

      nodePost('/create', payload, function (r) {
        if (r && r.conv_id) {
          openConv(r.conv_id, convType);
        } else if (r && r.error) {
          alert('Lỗi: ' + r.error);
        }
      });
    });
  }

  // ============================================================
  // TYPING — gửi + hiển thị
  // ============================================================
  function sendTyping() {
    if (!activeConvId) return;
    nodePost('/typing/' + activeConvId + '/' + AUS_ID, {});
  }

  var _avatarCache = {};  // aus_id → img URL hoặc '' (nếu không có)

  function showTypingIndicator(ausId, name) {
    _typingUsers[ausId] = { name: name || 'Ai đó' };
    if (_avatarCache[ausId] === undefined) {
      _avatarCache[ausId] = '';  // đánh dấu đang fetch, tránh gọi nhiều lần
      apexCall('msGetAvatar', { x01: ausId }, 'json', function (d) {
        _avatarCache[ausId] = (d && d.img) || '';
        renderTypingIndicator();
      });
    }
    clearTimeout(_typingUsers[ausId + '_t']);
    _typingUsers[ausId + '_t'] = setTimeout(function () {
      delete _typingUsers[ausId];
      delete _typingUsers[ausId + '_t'];
      renderTypingIndicator();
    }, 5000);
    renderTypingIndicator();
  }

  function hideTypingIndicator(ausId) {
    delete _typingUsers[ausId];
    delete _typingUsers[ausId + '_t'];
    renderTypingIndicator();
  }

  function renderTypingIndicator() {
    var el = document.getElementById('ms-typing-indicator');
    if (!el) return;
    var keys = Object.keys(_typingUsers).filter(function (k) { return !isNaN(k); });
    if (!keys.length) { el.style.display = 'none'; return; }
    var u = _typingUsers[keys[0]];
    var extraNames = keys.slice(1).map(function (k) { return _typingUsers[k].name; });
    var label = u.name + (extraNames.length ? ', ' + extraNames.join(', ') : '') + ' đang nhập...';
    var ausId0 = Number(keys[0]);
    var imgUrl = _avatarCache[ausId0] || '';
    el.innerHTML =
      avatarHtml(u.name, ausId0, imgUrl, false, 36) +
      '<div class="ms-typing-body">' +
        '<div class="ms-typing-dots"><span></span><span></span><span></span></div>' +
        '<span class="ms-typing-label">' + label + '</span>' +
      '</div>';
    el.style.display = 'flex';
  }

  // ============================================================
  // REAL-TIME — SSE (nhận qua apex:chatEvent từ global.js)
  // ============================================================
  function onChatEvent(_, ev) {
    if (!ev) return;
    if (ev.type === 'message') {
      loadConvList();
      if (ev.conv_id == activeConvId) {
        refreshThread(activeConvId);
        hideTypingIndicator(ev.msg && ev.msg.from_aus_id);
      } else {
        // Tin tới hội thoại KHÁC hội thoại đang mở.
        // ev.doc_type/doc_no/conv_name do server enrich (chat.js POST /send) — không cần lookup thêm.
        if (scopeMode === 'DOC' && entryDoc && ev.doc_no !== entryDoc.doc_no) {
          pushCrossDoc(ev.conv_id, ev.doc_no, ev.conv_name);
        }
        refreshUnreadSummary();
      }
    } else if (ev.type === 'typing') {
      if (ev.conv_id == activeConvId && ev.aus_id != AUS_ID) {
        showTypingIndicator(ev.aus_id, ev.name);
      }
    } else if (ev.type === 'typing_stop') {
      if (ev.conv_id == activeConvId) {
        hideTypingIndicator(ev.aus_id);
      }
    } else if (ev.type === 'read') {
      // read receipt: thêm xử lý nếu cần
    } else if (ev.type === 'reaction') {
      // Forward-looking: cần Node broadcast {type:'reaction',conv_id,msg_id}
      if (ev.conv_id == activeConvId) loadThread(activeConvId);
    } else if (ev.type === 'pin') {
      // Forward-looking: cần Node broadcast {type:'pin',conv_id,msg_id}
      if (ev.conv_id == activeConvId) { msLoadPinBanner(activeConvId); loadThread(activeConvId); }
    } else if (ev.type === 'attachment') {
      // File vừa upload xong sau khi tin nhắn (rỗng) đã được tạo - load lại thread
      // để msMsgThreadHtml (đã JOIN bảng file) render file vào đúng bong bóng đó.
      if (ev.conv_id == activeConvId) loadThread(activeConvId);
      else loadConvList();
    }
  }

  function startEventPoll() {
    // global.js trigger apex:chatEvent bằng jQuery của app cha (1503).
    // Phải dùng đúng jQuery instance của parent để bind — không dùng $ của iframe.
    var parentJQ  = _parentWin.apex ? _parentWin.apex.jQuery : _parentWin.$;
    var $eventDoc = parentJQ(_parentWin.document);
    $eventDoc.on('apex:chatEvent', onChatEvent);
  }

  // ============================================================
  // BIND EVENTS
  // ============================================================
  function bindEvents() {
    // Gửi bằng Enter (Shift+Enter = xuống dòng)
    var inputEl = document.getElementById('ms-chat-input');
    if (inputEl) {
      inputEl.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          msSendMessage();
        }
      });
      inputEl.addEventListener('input', function () {
        clearTimeout(_typingDebounce);
        _typingDebounce = setTimeout(sendTyping, 600);
      });
      inputEl.addEventListener('focus', function () { setFmtToolbarVisible(true); });
      inputEl.addEventListener('blur', function () { setFmtToolbarVisible(false); });
    }

    // Theo doi DROPZONE cua APEX File Browse item. Tuy nguon (_pendingFileSource)
    // ma route: 'plus' -> gui ngay (msSendFileMessage), 'paste'/null -> hien preview bar
    var attachDropzoneEl = document.getElementById('P10022710201_UPLOAD_FILE_DROPZONE');
    if (attachDropzoneEl && window.MutationObserver) {
      var attachObserver = new MutationObserver(function () {
        var hasFiles = attachDropzoneEl.classList.contains('has-files');
        if (hasFiles && _pendingFileSource === 'plus') {
          _pendingFileSource = null;
          msSendFileMessage();
        } else {
          syncFilePreviewFromDropzone();
        }
      });
      attachObserver.observe(attachDropzoneEl, { attributes: true, attributeFilter: ['class', 'style'], childList: true, subtree: true });
    }

    // Paste anh/file vao o nhap -> gan vao item APEX qua DataTransfer, kich hoat 'change'
    // that de component cua APEX tu cap nhat DOM (ten/size/mime) -> observer o tren se hien preview
    if (inputEl) {
      inputEl.addEventListener('paste', function (e) {
        var cd = e.clipboardData || window.clipboardData;
        if (!cd || !cd.items) return;
        for (var i = 0; i < cd.items.length; i++) {
          if (cd.items[i].kind !== 'file') continue;
          var pastedFile = cd.items[i].getAsFile();
          if (!pastedFile) continue;
          e.preventDefault();
          _pendingFileSource = 'paste';
          var dt = new DataTransfer();
          dt.items.add(pastedFile);
          var nativeFileInput = document.getElementById('P10022710201_UPLOAD_FILE_input');
          if (nativeFileInput) {
            nativeFileInput.files = dt.files;
            nativeFileInput.dispatchEvent(new Event('change', { bubbles: true }));
          }
          break; // chi xu ly 1 file moi lan paste
        }
      });
    }

    // Debounce search conv list
    var searchEl = document.getElementById('ms-conv-search');
    if (searchEl) {
      searchEl.addEventListener('input', function () {
        clearTimeout(_searchTimeout);
        _searchTimeout = setTimeout(loadConvList, 280);
      });
    }

    // Đóng dot-menu / react-bar: click ngoài / Esc / scroll
    document.addEventListener('click', function (e) {
      var menu = document.getElementById('ms-conv-menu');
      if (_convMenuId != null && menu && !menu.contains(e.target)) msCloseConvMenu();
      var bar = document.getElementById('ms-react-bar');
      if (_reactBarOpen && bar && !bar.contains(e.target) &&
          !e.target.closest('[onclick^="msOpenReactBar"]')) msCloseReactBar();
      if (_emojiPickerOpen && !e.target.closest('.ms-emoji-picker-wrap')) {
        _emojiPickerOpen = false;
        var ep = document.getElementById('ms-emoji-picker');
        if (ep) ep.classList.remove('open');
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      if (_convMenuId != null) msCloseConvMenu();
      if (_reactBarOpen) msCloseReactBar();
      var fwd = document.getElementById('ms-forward-modal');
      if (fwd && fwd.classList.contains('open')) fwd.classList.remove('open');
      else if (_lpScreen === 2) msComposeClose();
    });
    var listEl = document.getElementById('ms-conv-list');
    if (listEl) listEl.addEventListener('scroll', msCloseConvMenu);
    var msgsEl = document.getElementById('ms-messages');
    if (msgsEl) msgsEl.addEventListener('scroll', msCloseReactBar);

    // Filter: dong menu dropdown khi click ra ngoai
    document.addEventListener('click', function (e) {
      if (e.target.closest('#ms-type-select')) return;
      closeTypeMenu();
    });

    // Toggle info
    var infoBtn = document.getElementById('ms-toggle-info-btn');
    if (infoBtn) infoBtn.addEventListener('click', msToggleInfo);
  }

})();
