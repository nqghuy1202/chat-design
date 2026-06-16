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
  var selectedMembers = [];                // mảng aus_id đã chọn trong S3 (group)
  var _lpScreen       = 1;                 // màn hình hiện tại: 1=S1, 2=S2, 3=S3
  var _s2SearchTimer  = null;
  var _s3SearchTimer  = null;
  var _infoVisible    = false;             // right panel hiển thị hay không
  var _searchTimeout  = null;             // debounce conv search
  var _typingDebounce = null;             // debounce gửi typing event
  var _typingUsers    = {};               // aus_id → { name, timer }
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

  // ── Load thread tin nhắn ────────────────────────────────────
  function loadThread(convId) {
    var msgEl = document.getElementById('ms-messages');
    if (!msgEl) return;
    msgEl.innerHTML = skeletonHtml(4);

    apexCall('msMsgThreadHtml', { x01: convId }, 'text', function (html) {
      msgEl.innerHTML = html || '<div style="text-align:center;padding:40px;color:#94A3B8">Chưa có tin nhắn nào</div>';
      // Scroll xuống cuối
      setTimeout(function () { msgEl.scrollTop = msgEl.scrollHeight; }, 50);
      // Wire reply buttons
      msgEl.querySelectorAll('[data-reply-id]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          msStartReply(this.dataset.replyId, this.dataset.replyName, this.dataset.replyBody);
        });
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
        loadThread(activeConvId);
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

  // S1 → S2: mở contact picker (DM)
  window.msOpenNewConv = function () {
    document.getElementById('ms-s2-search').value = '';
    lpSlideTo(2);
    loadS2Contacts('');
    setTimeout(function () {
      var el = document.getElementById('ms-s2-search');
      if (el) el.focus();
    }, 320);
  };

  // S2 → S1: quay lại
  window.msNewConvBack = function () {
    lpSlideTo(1);
  };

  // S2 → S3: mở tạo nhóm
  window.msOpenNewGroup = function () {
    selectedMembers = [];
    document.getElementById('ms-s3-search').value = '';
    document.getElementById('ms-group-name').value = '';
    document.getElementById('ms-s3-chips').innerHTML = '';
    var createBtn = document.getElementById('ms-create-group-btn');
    if (createBtn) createBtn.disabled = true;
    lpSlideTo(3);
    loadS3Contacts('');
    setTimeout(function () {
      var el = document.getElementById('ms-group-name');
      if (el) el.focus();
    }, 320);
  };

  // S3 → S2: quay lại
  window.msGroupBack = function () {
    lpSlideTo(2);
  };

  // Load danh sách liên hệ vào S2 (DM picker — click để tạo DM ngay)
  function loadS2Contacts(search) {
    var el = document.getElementById('ms-s2-contacts');
    if (!el) return;
    el.innerHTML = '<div class="ms-loading-state">Đang tải...</div>';
    apexCall('msContactsHtml', { x01: search || '' }, 'text', function (html) {
      el.innerHTML = html;
      el.querySelectorAll('.ms-contact-item').forEach(function (item) {
        item.addEventListener('click', function () {
          var ausId = parseInt(this.dataset.ausId, 10);
          if (!ausId) return;
          msCreateDM(ausId);
        });
      });
    });
  }

  // Tạo DM trực tiếp khi click liên hệ ở S2
  function msCreateDM(ausId) {
    nodePost('/create', {
      conv_type:      'DM',
      aus_id:         AUS_ID,
      member_aus_ids: [ausId]
    }, function (d) {
      if (d && d.conv_id) {
        lpSlideTo(1);
        loadConvList();
        setTimeout(function () {
          window.msSelectConv(d.conv_id, 'DM');
        }, 300);
      } else if (d && d.error) {
        alert('Lỗi: ' + d.error);
      }
    });
  }

  // Debounce search S2
  window.msS2Search = function (val) {
    clearTimeout(_s2SearchTimer);
    _s2SearchTimer = setTimeout(function () { loadS2Contacts(val); }, 280);
  };

  // Load danh sách liên hệ vào S3 (multi-select cho group)
  function loadS3Contacts(search) {
    var el = document.getElementById('ms-s3-contacts');
    if (!el) return;
    el.innerHTML = '<div class="ms-loading-state">Đang tải...</div>';
    apexCall('msContactsHtml', { x01: search || '' }, 'text', function (html) {
      el.innerHTML = html;
      // Khôi phục trạng thái selected
      el.querySelectorAll('.ms-contact-item').forEach(function (item) {
        var ausId = parseInt(item.dataset.ausId, 10);
        if (selectedMembers.indexOf(ausId) !== -1) {
          item.classList.add('selected');
        }
        item.addEventListener('click', function () {
          toggleS3Contact(this);
        });
      });
    });
  }

  function toggleS3Contact(itemEl) {
    var ausId      = parseInt(itemEl.dataset.ausId, 10);
    var isSelected = itemEl.classList.contains('selected');
    if (isSelected) {
      itemEl.classList.remove('selected');
      selectedMembers = selectedMembers.filter(function (id) { return id !== ausId; });
    } else {
      itemEl.classList.add('selected');
      selectedMembers.push(ausId);
    }
    renderS3Chips();
    msUpdateGroupCreateBtn();
  }

  function renderS3Chips() {
    var container = document.getElementById('ms-s3-chips');
    if (!container) return;
    if (!selectedMembers.length) {
      container.innerHTML = '';
      return;
    }
    var html = '';
    document.querySelectorAll('#ms-s3-contacts .ms-contact-item.selected').forEach(function (item) {
      var name  = item.dataset.name || '?';
      var hue   = item.dataset.hue  || '0';
      var initl = name.replace(/.*\s/, '').charAt(0).toUpperCase();
      var ausId = item.dataset.ausId;
      html += '<div class="ms-chip">'
            + '<div class="ms-chip-av" style="background:hsl(' + hue + ',55%,52%)">' + initl + '</div>'
            + name.split(' ').pop()
            + '<button type="button" class="ms-chip-remove" data-aus-id="' + ausId + '">'
            + '<svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>'
            + '</button>'
            + '</div>';
    });
    container.innerHTML = html;
    container.querySelectorAll('.ms-chip-remove').forEach(function (btn) {
      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        var ausId  = parseInt(this.dataset.ausId, 10);
        selectedMembers = selectedMembers.filter(function (id) { return id !== ausId; });
        var itemEl = document.querySelector('#ms-s3-contacts .ms-contact-item[data-aus-id="' + ausId + '"]');
        if (itemEl) itemEl.classList.remove('selected');
        renderS3Chips();
        msUpdateGroupCreateBtn();
      });
    });
  }

  window.msUpdateGroupCreateBtn = function () {
    var btn  = document.getElementById('ms-create-group-btn');
    var name = (document.getElementById('ms-group-name') || {}).value || '';
    if (btn) btn.disabled = !(selectedMembers.length >= 2 && name.trim());
  };

  // Debounce search S3
  window.msS3Search = function (val) {
    clearTimeout(_s3SearchTimer);
    _s3SearchTimer = setTimeout(function () { loadS3Contacts(val); }, 280);
  };

  // Tạo nhóm
  window.msCreateGroup = function () {
    var name = (document.getElementById('ms-group-name') || {}).value || '';
    if (!name.trim() || selectedMembers.length < 2) return;
    var btn = document.getElementById('ms-create-group-btn');
    if (btn) { btn.disabled = true; btn.textContent = 'Đang tạo...'; }
    nodePost('/create', {
      conv_type:      'CHANNEL',
      name:           name.trim(),
      aus_id:         AUS_ID,
      member_aus_ids: selectedMembers
    }, function (d) {
      if (btn) { btn.disabled = false; btn.textContent = 'Tạo nhóm'; }
      if (d && d.conv_id) {
        lpSlideTo(1);
        loadConvList();
        setTimeout(function () {
          window.msSelectConv(d.conv_id, 'CHANNEL');
        }, 300);
      } else if (d && d.error) {
        alert('Lỗi tạo nhóm: ' + d.error);
      }
    });
  };

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
        loadThread(activeConvId);
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
