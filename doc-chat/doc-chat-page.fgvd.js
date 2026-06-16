/* Doc Chat — Function and Global Variable Declaration (FGVD)
 * Page 10022710201 — Paste TOÀN BỘ file này vào:
 *   Page → JavaScript → "Function and Global Variable Declaration".
 *
 * Mục tiêu: né giới hạn ký tự — toàn bộ hàm + state ở đây, mỗi tương tác do 1 Dynamic Action
 * kích hoạt (gọi window.dcOn*). Xem docs/doc-chat-da-setup.md.
 *
 * FGVD chạy TRƯỚC "Execute when Page Loads" nên CHAT_AUS_ID set ngay đây (IIFE đọc AUS_ID lúc init).
 * Items theo P${pageId}_ITEM_NAME → dùng $v('P'+pageId+'_CONV_ID').
 */
window.CHAT_AUS_ID = &G_AUS_ID.;
var pageId = $v('pFlowStepId');

(function($) {
  'use strict';

  var PAGE_ID         = 10022710201;
  var AUS_ID          = Number(window.CHAT_AUS_ID || 0);
  var activeConvId    = null;
  var activeFilter    = 'ALL';
  var showInfo        = true;
  var typingUsers     = {};   // aus_id → name
  var typingTimers    = {};   // aus_id → timer handle
  var selectedMembers = {};   // aus_id → { name, hue } — create dialog state
  var isSending       = false;
  var lastSentAt      = 0;    // ms — suppress duplicate reload from apex:chatEvent
  var typingDebounce;         // typing timer
  var convSearchTimer;        // sidebar search debounce
  var msgSearchTimer;         // message search debounce

  // Modal load trong iframe — global.js (TRANG CHA) fire apex:chatEvent trên parent document
  // bằng jQuery CỦA TRANG CHA. jQuery custom event KHÔNG vượt 2 instance jQuery → phải bind
  // bằng đúng jQuery của trang cha. Xem REVIEW-realtime-flow.
  var inIframe  = (window.parent && window.parent !== window);
  var eventWin  = inIframe ? window.parent : window;
  var $evt      = (eventWin.apex && eventWin.apex.jQuery) ? eventWin.apex.jQuery : $;
  var $eventDoc = $evt(eventWin.document);

  // ── APEX helpers ─────────────────────────────────────────────────────────────

  function dcHtml(proc, params, targetId, onDone) {
    apex.server.process(proc, params, {
      pageId:   PAGE_ID,
      dataType: 'text',
      success:  function(html) {
        var el = document.getElementById(targetId);
        if (el) el.innerHTML = html;
        if (onDone) onDone();
      },
      error: function(xhr) {
        console.error('[DocChat]', proc, xhr.responseText);
      }
    });
  }

  function dcJson(proc, params, onSuccess, onError) {
    apex.server.process(proc, params, {
      pageId:   PAGE_ID,
      dataType: 'json',
      success:  onSuccess || function() {},
      error:    onError || function(xhr) {
        console.error('[DocChat]', proc, xhr.responseText);
      }
    });
  }

  // ── Data loaders ──────────────────────────────────────────────────────────────

  function loadConvList(onDone) {
    dcHtml('dcConvListHtml', {
      x01: $v('P' + pageId + '_DOC_TYPE'),
      x02: $v('P' + pageId + '_DOC_NO'),
      x03: activeFilter,
      x04: $v('P' + pageId + '_SEARCH_QUERY') || ''
    }, 'dc-conv-list', onDone);
  }

  function loadThread() {
    if (!activeConvId) {
      var el = document.getElementById('dc-messages');
      if (el) el.innerHTML =
        '<div style="text-align:center;color:var(--text-3);margin-top:60px;font-size:13px">← Chọn hội thoại</div>';
      return;
    }
    var searchInput = document.getElementById('dc-msg-search-input');
    dcHtml('dcMsgThreadHtml', {
      x01: String(activeConvId),
      x02: searchInput ? searchInput.value : ''
    }, 'dc-messages', scrollToBottom);
  }

  function loadInfo() {
    if (!showInfo) return;
    dcHtml('dcInfoHtml', { x01: activeConvId ? String(activeConvId) : '' }, 'dc-info', injectDocFields);
  }

  function loadContacts(onDone) {
    dcHtml('dcContactsHtml', {}, 'dc-create-content', onDone);
  }

  // ── Scroll to bottom ──────────────────────────────────────────────────────────

  function scrollToBottom() {
    var el = document.getElementById('dc-messages');
    if (el) el.scrollTop = el.scrollHeight;
  }

  // ── Doc fields from sessionStorage ────────────────────────────────────────────

  function injectDocFields() {
    var ctx = {};
    try { ctx = JSON.parse(sessionStorage.getItem('docChatCtx') || '{}'); } catch(e) {}

    var elNo     = document.getElementById('dc-doc-no');
    var elStatus = document.getElementById('dc-doc-status');
    var elLabel  = document.getElementById('dc-doc-label');
    var elTotal  = document.getElementById('dc-doc-total');
    var elFields = document.getElementById('dc-doc-fields-placeholder');

    if (elNo     && ctx.doc_no)     elNo.textContent     = ctx.doc_no;
    if (elStatus && ctx.doc_status) elStatus.textContent = ctx.doc_status;
    if (elLabel  && ctx.doc_label)  elLabel.textContent  = ctx.doc_label;
    if (elTotal  && ctx.doc_total)  elTotal.textContent  = ctx.doc_total;

    if (elFields) {
      var fields = ctx.doc_fields || [];
      if (!fields.length) { elFields.innerHTML = ''; return; }
      var html = '';
      fields.forEach(function(f) {
        html += '<div class="doc-summary-row">'
              + '<span class="k">' + escHtml(f[0]) + '</span>'
              + '<span class="v">' + escHtml(f[1]) + '</span>'
              + '</div>';
      });
      elFields.innerHTML = html;
    }
  }

  function escHtml(s) {
    return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  // ── Select conversation ────────────────────────────────────────────────────────

  function selectConv(convId) {
    convId = Number(convId);
    if (convId === activeConvId) return;
    activeConvId = convId;
    $s('P' + pageId + '_CONV_ID', String(convId));
    $s('P' + pageId + '_REPLY_TO_MSG_ID', '');

    $('.convo-item').removeClass('active');
    $('.convo-item[data-conv-id="' + convId + '"]').addClass('active');

    document.getElementById('dc-compose-area').style.display = '';
    document.getElementById('dc-btn-search-toggle').style.display = '';
    document.getElementById('dc-btn-info').style.display = '';

    document.getElementById('dc-reply-banner').style.display = 'none';
    $('#dc-composer').removeClass('with-reply');

    var $item = $('.convo-item[data-conv-id="' + convId + '"]');
    var name  = $item.find('.convo-name').text();
    document.getElementById('dc-chat-head-title').textContent = name;

    var headEl = document.getElementById('dc-chat-head');
    if (headEl) {
      var $existingAv = $(headEl).find('.chat-head-avatar');
      if ($existingAv.length) $existingAv.remove();
      var $srcAv = $item.find('.convo-avatar').first();
      if ($srcAv.length) {
        var $av = $srcAv.clone().removeClass('convo-avatar');
        $av.addClass('chat-head-avatar').css({ width: 36, height: 36, fontSize: 13 });
        $(headEl).prepend($av);
      }
    }

    loadThread();
    loadInfo();
    dcJson('docChatRead', { x01: String(convId) });

    $('.convo-item[data-conv-id="' + convId + '"]').removeClass('unread').find('.convo-badge').remove();
  }

  // ── Send message ───────────────────────────────────────────────────────────────

  function sendMessage() {
    if (isSending) return;
    var input   = document.getElementById('dc-msg-input');
    var body    = (input.value || '').trim();
    var replyId = $v('P' + pageId + '_REPLY_TO_MSG_ID') || '';
    var partner = $('.convo-item[data-conv-id="' + activeConvId + '"]').data('partner-aus-id') || '';

    if (!body || !activeConvId) return;

    isSending  = true;
    lastSentAt = Date.now();
    input.value = '';
    $s('P' + pageId + '_REPLY_TO_MSG_ID', '');
    document.getElementById('dc-reply-banner').style.display = 'none';
    $('#dc-composer').removeClass('with-reply');

    dcJson('docChatSend', {
      x01: String(activeConvId),
      x02: body,
      x03: replyId,
      x04: String(partner)
    }, function(data) {
      isSending = false;
      if (data && data.error) {
        apex.message.showErrors([{ type: 'error', message: 'Gửi thất bại: ' + data.error }]);
        console.error('[DocChat] docChatSend error:', data.error);
        return;
      }
      loadThread();
      loadConvList();
    }, function(xhr) {
      isSending = false;
      var msg = xhr.responseText || 'Lỗi kết nối';
      apex.message.showErrors([{ type: 'error', message: 'Gửi thất bại: ' + msg }]);
      console.error('[DocChat] docChatSend xhr error:', msg);
    });
  }

  // ── Typing ─────────────────────────────────────────────────────────────────────

  function onMsgInput() {
    if (!activeConvId) return;
    clearTimeout(typingDebounce);
    typingDebounce = setTimeout(function() {
      dcJson('docChatTyping', { x01: String(activeConvId) });
    }, 600);
  }

  function showTyping(ausId, name) {
    typingUsers[ausId] = name || 'Ai đó';
    clearTimeout(typingTimers[ausId]);
    typingTimers[ausId] = setTimeout(function() { hideTyping(ausId); }, 5000);
    renderTyping();
  }

  function hideTyping(ausId) {
    delete typingUsers[ausId];
    clearTimeout(typingTimers[ausId]);
    renderTyping();
  }

  function renderTyping() {
    var names = Object.values(typingUsers);
    var el = document.getElementById('dc-typing');
    var elText = document.getElementById('dc-typing-text');
    if (!el) return;
    if (!names.length) { el.style.display = 'none'; return; }
    if (elText) elText.textContent = names.slice(0, 2).join(', ') + ' đang nhập...';
    el.style.display = 'flex';
  }

  // ── Real-time events from global.js ───────────────────────────────────────────
  // GIỮ BINDING Ở FGVD (không làm DA): custom event mang payload qua jQuery trigger;
  // và cleanup khi iframe unload. DA không lấy được payload của trigger, không gắn unload.

  function showSeen() {
    var box = document.getElementById('dc-messages');
    if (!box) return;
    var old = box.querySelector('.msg-seen');
    if (old) old.remove();
    var mine = box.querySelectorAll('.msg-row.mine');
    if (!mine.length) return;
    var col = mine[mine.length - 1].querySelector('.msg-col');
    if (!col) return;
    var tag = document.createElement('div');
    tag.className = 'msg-seen';
    tag.textContent = '✓ Đã xem';
    col.appendChild(tag);
  }

  function onChatEvent(_, ev) {
    if (ev.type === 'message') {
      loadConvList();
      if (String(ev.conv_id) === String(activeConvId)) {
        var justSentHere = (Date.now() - lastSentAt) < 3000;
        if (!justSentHere) loadThread();
        dcJson('docChatRead', { x01: String(activeConvId) });
      }
    } else if (ev.type === 'typing') {
      if (Number(ev.aus_id) !== AUS_ID && String(ev.conv_id) === String(activeConvId)) {
        showTyping(ev.aus_id, ev.name);
      }
    } else if (ev.type === 'typing_stop') {
      if (String(ev.conv_id) === String(activeConvId)) hideTyping(ev.aus_id);
    } else if (ev.type === 'read') {
      if (Number(ev.aus_id) !== AUS_ID && String(ev.conv_id) === String(activeConvId)) {
        showSeen();
      }
    }
  }

  $eventDoc.on('apex:chatEvent', onChatEvent);

  // Khi iframe unload (modal đóng), gỡ handler khỏi parent document
  $(window).on('unload', function() {
    $eventDoc.off('apex:chatEvent', onChatEvent);
  });

  // ── Create conversation dialog: helpers ───────────────────────────────────────

  function renderChips() {
    var $chips = $('#dc-selected-chips');
    var count  = Object.keys(selectedMembers).length;
    var $count = $('#dc-selected-count');
    if ($count.length) $count.text(count);
    if (!$chips.length) return;

    if (!count) {
      $chips.html('<span style="color:var(--text-4);font-size:13px;padding:4px">Chưa chọn thành viên nào</span>');
      return;
    }
    var html = '';
    Object.keys(selectedMembers).forEach(function(ausId) {
      var m     = selectedMembers[ausId];
      var initl = m.name.trim().split(/\s+/).slice(-1)[0][0].toUpperCase();
      html += '<span class="member-chip">'
            + '<span class="member-chip-avatar" style="background:hsl(' + m.hue + ',55%,52%)">'
            + (m.img ? '<img class="av-img" onerror="this.remove()" src="' + escHtml(m.img) + '">' : '') + initl + '</span>'
            + escHtml(m.name.split(/\s+/).slice(-1)[0])
            + '<span class="x" data-chip-id="' + ausId + '">×</span>'
            + '</span>';
    });
    $chips.html(html);
  }

  function toggleMember(item) {
    var $item    = $(item);
    var ausId    = String($item.data('aus-id'));
    var name     = String($item.data('name') || '');
    var hue      = String($item.data('hue')  || '0');
    var img      = String($item.data('img')  || '');
    var convType = $('input[name="dc-conv-type"]:checked').val() || 'DM';

    if ($item.hasClass('selected')) {
      $item.removeClass('selected');
      delete selectedMembers[ausId];
    } else {
      if (convType === 'DM') {
        $('#dc-member-suggest-list .member-suggest-item.selected').removeClass('selected');
        selectedMembers = {};
      }
      $item.addClass('selected');
      selectedMembers[ausId] = { name: name, hue: hue, img: img };
    }
    renderChips();
  }

  // Thân của handler "đổi loại hội thoại" — tách ra để openCompose gọi trực tiếp,
  // KHÔNG còn phụ thuộc .trigger('change') (DA không đảm bảo nhận trigger giả lập).
  function applyConvType(convType, radioEl) {
    var isChannel = convType === 'CHANNEL';
    $('.dc-type-tab').removeClass('active');
    if (radioEl) {
      $(radioEl).closest('.dc-type-tab').addClass('active');
    } else {
      $('input[name="dc-conv-type"][value="' + convType + '"]').closest('.dc-type-tab').addClass('active');
    }
    var wrap = document.getElementById('dc-create-name-wrap');
    if (wrap) wrap.style.display = isChannel ? 'flex' : 'none';
    if (!isChannel) {
      Object.keys(selectedMembers).slice(1).forEach(function(id) {
        delete selectedMembers[id];
        $('#dc-member-suggest-list .member-suggest-item[data-aus-id="' + id + '"]').removeClass('selected');
      });
      renderChips();
    }
  }

  // ── Inline compose: mở / đóng panel trong cột trái ──────────────────────────

  function openCompose(convType) {
    selectedMembers = {};
    document.getElementById('dc-list-screen').style.display    = 'none';
    document.getElementById('dc-compose-screen').style.display = 'flex';
    document.getElementById('dc-compose-title').textContent =
      convType === 'CHANNEL' ? 'Tạo nhóm mới' : 'Nhắn tin mới';

    loadContacts(function() {
      $('input[name=dc-conv-type][value="' + convType + '"]').prop('checked', true);
      applyConvType(convType);
      injectCreateContext();
    });
  }

  function closeCompose() {
    document.getElementById('dc-compose-screen').style.display = 'none';
    document.getElementById('dc-list-screen').style.display    = 'flex';
    selectedMembers = {};
  }

  function injectCreateContext() {
    var docType = $v('P' + pageId + '_DOC_TYPE');
    var docNo   = $v('P' + pageId + '_DOC_NO');
    var ref = document.getElementById('dc-create-doc-ref');
    if (ref) ref.textContent = (docType && docNo) ? (docType + ' — ' + docNo) : '—';
    var nameEl = document.getElementById('dc-create-name');
    if (nameEl && !nameEl.value && docType && docNo) {
      nameEl.value = docType + ' - ' + docNo;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  HANDLERS gọi từ Dynamic Action — nhận (el, ev) từ this.triggeringElement
  //  và this.browserEvent. Xem docs/doc-chat-da-setup.md.
  // ════════════════════════════════════════════════════════════════════════

  // DA1 — Click .convo-item[data-conv-id]  (chọn hội thoại)
  function dcOnConvClick(el, ev) { selectConv($(el).data('conv-id')); }

  // DA2 — Click .lp-filter-chip[data-filter], .convo-tab[data-filter]  (lọc theo loại)
  function dcOnFilter(el, ev) {
    var $t = $(el);
    activeFilter = $t.data('filter');
    if ($t.hasClass('convo-tab')) {
      $t.closest('.convo-tabs').find('.convo-tab').removeClass('active');
      $t.addClass('active');
    }
    loadConvList();
  }

  // DA3 — Custom input #dc-conv-search  (tìm kiếm hội thoại, debounce)
  function dcOnConvSearch(el, ev) {
    var q = el.value;
    clearTimeout(convSearchTimer);
    convSearchTimer = setTimeout(function() {
      $s('P' + pageId + '_SEARCH_QUERY', q);
      loadConvList();
    }, 350);
  }

  // DA4 — Click #dc-btn-search-toggle  (bật/tắt thanh tìm trong hội thoại)
  function dcOnSearchToggle(el, ev) {
    var bar = document.getElementById('dc-msg-search-bar');
    if (bar.style.display !== 'none') {
      bar.style.display = 'none';
      document.getElementById('dc-msg-search-input').value = '';
      loadThread();
    } else {
      bar.style.display = 'block';
      document.getElementById('dc-msg-search-input').focus();
    }
    $(el).toggleClass('active');
  }

  // DA5 — Custom input #dc-msg-search-input  (tìm trong hội thoại, debounce)
  function dcOnMsgSearch(el, ev) {
    clearTimeout(msgSearchTimer);
    msgSearchTimer = setTimeout(loadThread, 350);
  }

  // DA6 — Click #dc-btn-info  (bật/tắt panel thông tin)
  function dcOnToggleInfo(el, ev) {
    showInfo = !showInfo;
    $('#dc-body').toggleClass('with-info', showInfo);
    var pane = document.getElementById('dc-info-pane');
    if (pane) pane.style.display = showInfo ? '' : 'none';
    $(el).toggleClass('active', showInfo);
    if (showInfo) loadInfo();
  }

  // DA7 — Click .msg-hover-action[data-reply-id]  (bắt đầu trả lời)
  function dcOnReplyStart(el, ev) {
    if (ev) ev.stopPropagation();
    var $a = $(el);
    $s('P' + pageId + '_REPLY_TO_MSG_ID', String($a.data('reply-id')));
    document.getElementById('dc-reply-preview').textContent = ($a.data('reply-body') || '').substring(0, 80);
    document.getElementById('dc-reply-banner').style.display = 'flex';
    $('#dc-composer').addClass('with-reply');
    document.getElementById('dc-msg-input').focus();
  }

  // DA8 — Click #dc-reply-cancel  (hủy trả lời)
  function dcOnReplyCancel(el, ev) {
    $s('P' + pageId + '_REPLY_TO_MSG_ID', '');
    document.getElementById('dc-reply-banner').style.display = 'none';
    $('#dc-composer').removeClass('with-reply');
  }

  // DA9 — Click #dc-btn-send  (gửi tin)
  function dcOnSend(el, ev) { sendMessage(); }

  // DA10 — Key Down #dc-msg-input  (Ctrl+Enter gửi; phím khác → báo typing)
  function dcOnMsgKeydown(el, ev) {
    if (ev && ev.ctrlKey && ev.key === 'Enter') { ev.preventDefault(); sendMessage(); }
    else onMsgInput();
  }

  // DA11 — Custom input #dc-msg-input  (auto-resize textarea)
  function dcOnMsgAutosize(el, ev) {
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  }

  // DA12 — Click #dc-member-suggest-list .member-suggest-item  (chọn/bỏ thành viên)
  function dcOnMemberToggle(el, ev) { toggleMember(el); }

  // DA13 — Click .member-chip .x  (bỏ 1 chip thành viên)
  function dcOnChipRemove(el, ev) {
    if (ev) ev.stopPropagation();
    var ausId = String($(el).data('chip-id'));
    delete selectedMembers[ausId];
    $('#dc-member-suggest-list .member-suggest-item[data-aus-id="' + ausId + '"]').removeClass('selected');
    renderChips();
  }

  // DA14 — Custom input #dc-contact-search  (lọc danh bạ)
  function dcOnContactSearch(el, ev) {
    var q = el.value.toLowerCase().trim();
    $('#dc-member-suggest-list .member-suggest-item').each(function() {
      var name = ($(this).data('name') || '').toLowerCase();
      var dept = ($(this).data('dept') || '').toLowerCase();
      $(this).toggle(!q || name.indexOf(q) !== -1 || dept.indexOf(q) !== -1);
    });
    $('#dc-member-suggest-list [data-dept-header]').each(function() {
      var $h = $(this), any = false, $n = $h.next();
      while ($n.length && !$n.is('[data-dept-header]')) {
        if ($n.is(':visible')) { any = true; break; }
        $n = $n.next();
      }
      $h.toggle(any);
    });
  }

  // DA15 — Change input[name="dc-conv-type"]  (đổi loại hội thoại trong soạn)
  function dcOnTypeTab(el, ev) { applyConvType(el.value, el); }

  // DA16 — Click #dc-btn-dm  (mở soạn tin cá nhân)
  function dcOnOpenDM(el, ev) { openCompose('DM'); }

  // DA17 — Click #dc-btn-group, #dc-btn-create  (mở soạn nhóm)
  function dcOnOpenGroup(el, ev) { openCompose('CHANNEL'); }

  // DA18 — Click #dc-compose-back, #dc-compose-close, #dc-create-cancel  (đóng soạn)
  function dcOnCloseCompose(el, ev) { closeCompose(); }

  // DA19 — Click #dc-create-submit  (tạo hội thoại)
  function dcOnSubmitCreate(el, ev) {
    var $btn = $(el);
    if ($btn.data('submitting')) return;

    var convType = $('input[name="dc-conv-type"]:checked').val() || 'DM';
    var nameEl   = document.getElementById('dc-create-name');
    var name     = nameEl ? nameEl.value.trim() : '';
    var members  = Object.keys(selectedMembers).map(Number);

    if (!members.length) {
      apex.message.showErrors([{ type: 'error', message: 'Chọn ít nhất 1 thành viên' }]);
      return;
    }
    if (convType === 'CHANNEL' && !name) {
      var docType = $v('P' + pageId + '_DOC_TYPE');
      var docNo   = $v('P' + pageId + '_DOC_NO');
      name = (docType && docNo) ? docType + ' - ' + docNo : 'Nhóm mới';
      if (nameEl) nameEl.value = name;
    }

    $btn.data('submitting', true).prop('disabled', true);

    dcJson('docChatCreate', {
      x01: convType,
      x02: name,
      x03: JSON.stringify(members),
      x04: $v('P' + pageId + '_DOC_TYPE'),
      x05: $v('P' + pageId + '_DOC_NO')
    }, function(data) {
      $btn.removeData('submitting').prop('disabled', false);
      if (data && data.error) {
        apex.message.showErrors([{ type: 'error', message: 'Tạo thất bại: ' + data.error }]);
        console.error('[DocChat] docChatCreate error:', data.error);
        return;
      }
      closeCompose();
      if (data && data.conv_id) {
        loadConvList(function() { selectConv(data.conv_id); });
      }
    }, function(xhr) {
      $btn.removeData('submitting').prop('disabled', false);
      console.error('[DocChat] docChatCreate xhr error:', xhr.responseText);
      apex.message.showErrors([{ type: 'error', message: 'Tạo thất bại: ' + (xhr.responseText || 'Lỗi kết nối') }]);
    });
  }

  // ── Init (gọi 1 lần từ "Execute when Page Loads") ─────────────────────────────
  function dcInit() {
    var ctx = {};
    try { ctx = JSON.parse(sessionStorage.getItem('docChatCtx') || '{}'); } catch(e) {}

    if (ctx.doc_type)   $s('P' + pageId + '_DOC_TYPE',   ctx.doc_type);
    if (ctx.doc_no)     $s('P' + pageId + '_DOC_NO',     ctx.doc_no);
    if (ctx.doc_label)  $s('P' + pageId + '_DOC_LABEL',  ctx.doc_label);
    if (ctx.doc_status) $s('P' + pageId + '_DOC_STATUS', ctx.doc_status);
    if (ctx.doc_total)  $s('P' + pageId + '_DOC_TOTAL',  ctx.doc_total);

    if (ctx.doc_label && ctx.doc_no) {
      var $title = apex.jQuery('.ui-dialog-title');
      if ($title.length) $title.text('Trao đổi — ' + ctx.doc_label + ': ' + ctx.doc_no);
    }

    $('#dc-body').toggleClass('with-info', showInfo);

    loadConvList();
    loadInfo();
  }

  // ── Public API (cho Dynamic Actions + Execute-on-load gọi ngoài IIFE) ─────────
  window.dcInit           = dcInit;
  window.dcOnConvClick    = dcOnConvClick;
  window.dcOnFilter       = dcOnFilter;
  window.dcOnConvSearch   = dcOnConvSearch;
  window.dcOnSearchToggle = dcOnSearchToggle;
  window.dcOnMsgSearch    = dcOnMsgSearch;
  window.dcOnToggleInfo   = dcOnToggleInfo;
  window.dcOnReplyStart   = dcOnReplyStart;
  window.dcOnReplyCancel  = dcOnReplyCancel;
  window.dcOnSend         = dcOnSend;
  window.dcOnMsgKeydown   = dcOnMsgKeydown;
  window.dcOnMsgAutosize  = dcOnMsgAutosize;
  window.dcOnMemberToggle = dcOnMemberToggle;
  window.dcOnChipRemove   = dcOnChipRemove;
  window.dcOnContactSearch= dcOnContactSearch;
  window.dcOnTypeTab      = dcOnTypeTab;
  window.dcOnOpenDM       = dcOnOpenDM;
  window.dcOnOpenGroup    = dcOnOpenGroup;
  window.dcOnCloseCompose = dcOnCloseCompose;
  window.dcOnSubmitCreate = dcOnSubmitCreate;
  // Giữ tương thích tên cũ
  window.dcOpenCompose  = openCompose;
  window.dcCloseCompose = closeCompose;
  window.dcLoadConvList = loadConvList;
  window.dcSelectConv   = selectConv;
  window.dcLoadThread   = loadThread;
  window.dcSendMessage  = sendMessage;

})(apex.jQuery);
