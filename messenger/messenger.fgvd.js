// ============================================================
// MESSENGER FULLSCREEN — Function and Global Variable Declaration
// Paste vào Page → Function and Global Variable Declaration
// ============================================================

(function () {
  'use strict';

  var PAGE_ID         = $v('pFlowStepId');  // page ID hiện tại
  var activeConvId    = null;               // conv đang chọn
  var activeFilter    = 'ALL';              // filter chip đang active
  var replyTo         = null;              // { id, name, body } hoặc null
  var selectedMembers = [];                // mảng aus_id đã chọn ở màn soạn tin (S2)
  var _lpScreen       = 1;                 // màn hình hiện tại: 1=S1 (list), 2=S2 (soạn tin)
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

  // ── Helper: gọi AJAX callback ──────────────────────────────
  function apexCall(proc, params, dataType, onSuccess) {
    apex.server.process(proc, params, {
      pageId:   PAGE_ID,
      dataType: dataType || 'json',
      success: onSuccess,
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
    loadCurrentUser();
    loadConvList();
    bindEvents();
    startEventPoll();

    // Hiển thị empty state ban đầu
    showEmptyState();
  };

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
      x02: document.getElementById('ms-conv-search').value.trim()
    }, 'text', function (html) {
      listEl.innerHTML = html || '<div style="padding:32px 16px;text-align:center;color:#94A3B8;font-size:13px">Chưa có hội thoại nào</div>';
    });
  }

  // ── Chọn hội thoại (gọi từ PL/SQL onclick) ─────────────────
  window.msSelectConv = function (convId, convType) {
    if (!convId) return;
    activeConvId = convId;

    // Mark active item
    document.querySelectorAll('.ms-conv-item').forEach(function (el) {
      el.classList.toggle('active', el.dataset.convId == convId);
    });

    // Hiển thị các panel
    hideEmptyState();
    document.getElementById('ms-chat-header').style.display = 'flex';
    document.getElementById('ms-messages').style.display    = 'flex';
    document.getElementById('ms-input-area').style.display  = 'block';

    // Load dữ liệu
    loadConvHeader(convId, convType);
    loadThread(convId);
    if (_infoVisible) loadInfoPanel(convId);

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
      var hue    = (convId * 47) % 360;
      var initl  = (d.name || '?').replace(/.*\s/, '').charAt(0).toUpperCase();
      headerAv.style.background = 'hsl(' + hue + ',55%,52%)';
      headerAv.innerHTML = initl;
      if (d.type === 'CHANNEL') {
        headerAv.classList.add('group');
        headerAv.innerHTML = '<i class="fa fa-users" style="font-size:15px"></i>';
      } else if (d.img) {
        headerAv.innerHTML += '<img src="' + d.img + '" style="width:100%;height:100%;object-fit:cover;position:absolute;inset:0;border-radius:50%" onerror="this.remove()">';
      }
      headerName.textContent = d.name || 'Hội thoại';
      if (d.type === 'DM') {
        headerSub.textContent = d.online ? 'Đang hoạt động' : 'Không hoạt động';
      } else {
        headerSub.textContent = (d.member_count || 0) + ' thành viên';
      }
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

    var isDM      = convType === 'DM';
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

  // Nút chính: 1 người → tạo DM; ≥2 → tạo nhóm
  window.msComposeSubmit = function () {
    var n = selectedMembers.length;
    if (n === 0) return;
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
    var btn = document.getElementById('ms-compose-action');
    if (btn) { btn.disabled = true; btn.textContent = 'Đang tạo...'; }
    nodePost('/create', {
      conv_type:      'CHANNEL',
      name:           name,
      aus_id:         AUS_ID,
      member_aus_ids: selectedMembers
    }, function (d) {
      if (btn) { btn.disabled = false; btn.textContent = 'Tạo nhóm'; }
      if (d && d.conv_id) {
        lpSlideTo(1);
        loadConvList();
        setTimeout(function () { window.msSelectConv(d.conv_id, 'CHANNEL'); }, 300);
      } else if (d && d.error) {
        alert('Lỗi tạo nhóm: ' + d.error);
      }
    });
  };

  // Mở 1 DM (đã có hoặc vừa tạo) → về danh sách + chọn
  function openDM(convId) {
    lpSlideTo(1);
    loadConvList();
    setTimeout(function () { window.msSelectConv(convId, 'DM'); }, 300);
  }

  // Tạo DM (1 người). Chống trùng: hỏi APEX (msFindDM) xem DM đã tồn tại chưa.
  // - Có → mở lại conv cũ (đã tự bỏ ẩn / rejoin phía callback).
  // - Chưa → tạo mới qua Node /create (giữ real-time cho đối phương).
  function msCreateDM(ausId) {
    apexCall('msFindDM', { x01: ausId }, 'json', function (d) {
      if (d && d.found && d.conv_id) {
        openDM(d.conv_id);
        return;
      }
      nodePost('/create', {
        conv_type:      'DM',
        aus_id:         AUS_ID,
        member_aus_ids: [ausId]
      }, function (r) {
        if (r && r.conv_id) {
          openDM(r.conv_id);
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

    // Filter chips
    var filterRow = document.getElementById('ms-filter-row');
    if (filterRow) {
      filterRow.addEventListener('click', function (e) {
        var chip = e.target.closest('.ms-filter-chip');
        if (!chip) return;
        activeFilter = chip.dataset.filter;
        document.querySelectorAll('.ms-filter-chip').forEach(function (c) {
          c.classList.remove('active');
        });
        chip.classList.add('active');
        loadConvList();
      });
    }

    // Toggle info
    var infoBtn = document.getElementById('ms-toggle-info-btn');
    if (infoBtn) infoBtn.addEventListener('click', msToggleInfo);
  }

})();
