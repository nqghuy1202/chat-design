const layout=document.getElementById('layout');
const side=document.getElementById('side');

/* ============================================================
   Real-time — dùng chung Node chat-server với messenger/ (cùng instance,
   xem CLAUDE.md mục "Chat Server"). Mọi đọc/ghi dữ liệu vẫn đi qua APEX
   Ajax Callback (apexCall/apexCallJson) — Node CHỈ relay SSE, không
   chạm DB. Sau khi 1 callback ghi DB thành công, BROWSER (không phải
   DB qua UTL_HTTP) tự gọi nodePost('/broadcast-message',...) để phát
   sự kiện cho các thành viên khác — tránh ORA-12535 vì máy DB Oracle
   thường không route được tới Node (đã xác nhận khi làm msUploadFile
   của messenger/, xem messenger/CLAUDE.md mục "Luồng gửi file thật").
   ============================================================ */
const NODE_URL = 'https://chattest.erp100.vn/api/chat';
function nodePost(path, body, onSuccess, onError){
  fetch(NODE_URL + path, {
    method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(body||{})
  }).then(r=>r.json()).then(onSuccess||function(){})
    .catch(onError || function(err){ console.error('[chat-erp] nodePost', path, err); });
}
function nodeGet(path, onSuccess, onError){
  fetch(NODE_URL + path).then(r=>r.json()).then(onSuccess||function(){})
    .catch(onError || function(err){ console.error('[chat-erp] nodeGet', path, err); });
}
/* Trang chứa modal có thể nhúng iframe (app 1503) hoặc chạy trực tiếp —
   tự dò parent giống pattern messenger/, không phá vỡ trường hợp đứng riêng. */
const _inIframe  = window.parent && window.parent !== window;
const _parentWin = _inIframe ? window.parent : window;

/* ============================================================
   APEX Ajax Callback helper — mọi đọc/ghi dữ liệu (gửi tin, đọc tin,
   tạo hội thoại...) đi thẳng qua page-level Ajax Callback
   (apex.server.process), đồng bộ với Oracle session APEX.
   ============================================================ */
function apexCall(proc, params, onSuccess, onError){
  params = params || {};
  const ajax = {pageItems: []};
  Object.keys(params).forEach(k=>{ ajax[k] = params[k]; });
  apex.server.process(proc, ajax, {
    dataType: 'text',
    success: function(data){ if(onSuccess) onSuccess(data); },
    error: function(xhr){ console.error('[chat-erp] '+proc+' lỗi', xhr); if(onError) onError(xhr); }
  });
}
function apexCallJson(proc, params, onSuccess, onError){
  apexCall(proc, params, function(data){
    let json; try{ json = JSON.parse(data); }catch(e){ json = {error:'parse_error'}; }
    if(json.error){ console.error('[chat-erp] '+proc+' trả lỗi:', json.error); if(onError) onError(json); return; }
    if(onSuccess) onSuccess(json);
  }, onError);
}

let currentUser = null;     // {aus_id, username, full_name, img}
let activeConvId = null;
let activeConvKind = 'nhom';  // chungtu | channel | nhom | canhan
let activeConvIsDoc = false;
let _sidePanelKind = null;  // 'info' | 'thread' | 'detail' | null — panel #side đang hiện gì

/* ============================================================
   Unified Entry — 2 cửa vào (icon header = tất cả; nút "Trao đổi" = scoped 1 chứng từ)
   + cross-doc awareness. Xem docs/unified-chat-architecture.md.
   entryDoc set TRƯỚC khi mở modal qua sessionStorage['msEntryDoc'].
   ============================================================ */
let entryDoc = null;        // {doc_type, doc_no, doc_label} hoặc null (cửa header)
let scopeMode = 'all';      // 'all' | 'doc'
let draftConv = null;       // Phòng ảo: hội thoại CHƯA ghi DB, chỉ tạo khi gửi tin đầu.
                            // {kind:'dm'|'doc'|'nhom'|'channel', title, ...metadata}
let unreadMap = {};         // convId -> số chưa đọc (nguồn cho badge tổng)
let crossDocQueue = [];     // [{conv_id, doc_no, conv_name}] tin tới ngoài scope chứng từ

function initEntryDoc(){
  entryDoc = null; scopeMode = 'all';
  try{
    const raw = sessionStorage.getItem('msEntryDoc');
    if(raw){
      const d = JSON.parse(raw);
      if(d && d.doc_type && d.doc_no){ entryDoc = d; scopeMode = 'doc'; }
    }
  }catch(e){ console.warn('[chat-erp] msEntryDoc hỏng, fallback all', e); entryDoc=null; scopeMode='all'; }
  // Segmented control chỉ hiện khi vào từ chứng từ
  const box = document.getElementById('scopeBox');
  if(box){
    box.classList.toggle('hidden', !entryDoc);
    if(entryDoc){
      const lbl = document.getElementById('scopeDocLabel');
      if(lbl) lbl.textContent = entryDoc.doc_label || (entryDoc.doc_type+'-'+entryDoc.doc_no);
      applyScopeButtons();
    }
  }
}
function applyScopeButtons(){
  document.querySelectorAll('#scopeBox .scope-tab').forEach(b=>
    b.classList.toggle('active', b.dataset.scope === scopeMode));
}
function setScope(mode){
  if(mode === scopeMode) return;
  scopeMode = mode;
  applyScopeButtons();
  if(mode === 'doc') hideCrossDocBanner();   // đã quay về chứng từ → ẩn banner
  loadConvList();
}

function paneComposer(){return document.querySelector('.pane .composer .input');}
function scrollMessages(){const m=document.getElementById('messages');m.scrollTop=m.scrollHeight;}
function nowHM(){const d=new Date();return String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');}

/* ============================================================
   Khởi tạo
   ============================================================ */
function msInit(){
  initEntryDoc();
  apexCallJson('msGetCurrentUser', {}, function(u){
    currentUser = u;
    loadConvList();
    initUnreadSummary();
  }, function(){
    document.getElementById('navScroll').innerHTML =
      '<div style="padding:16px;color:#DC2626">Không lấy được thông tin người dùng. Tải lại trang.</div>';
  });
  apexCall('msRoleOptionsHtml', {}, function(html){
    document.getElementById('roleMenu').insertAdjacentHTML('beforeend', html);
  });
  startEventPoll();
}

/* ============================================================
   Real-time — nhận sự kiện qua custom event 'apex:chatEvent' do
   global.js (app cha, nếu chạy trong iframe) trigger từ SSE của Node
   chat-server. Nếu chạy độc lập (không iframe) thì bind thẳng vào
   document hiện tại — _parentWin đã tự dò ở trên.
   ============================================================ */
function startEventPoll(){
  // CHẨN ĐOÁN real-time: in rõ đang ở kịch bản nào để khỏi đoán mò.
  console.info('[chat-erp][rt] _inIframe=%s (window.parent!==window: %s)', _inIframe, window.parent!==window);
  if(!_inIframe){
    console.warn('[chat-erp][rt] Đang chạy STANDALONE (không nhúng dưới app 1503). '+
      'Không có global.js để mở SSE → KHÔNG nhận real-time. Hãy mở chat-erp qua launcher của app 1503.');
  }
  const parentJQ = _parentWin.apex ? _parentWin.apex.jQuery : (_parentWin.jQuery || _parentWin.$);
  if(!parentJQ){
    console.warn('[chat-erp][rt] Không tìm thấy jQuery của parent — real-time KHÔNG hoạt động. '+
      '(parent không phải app APEX 1503, hoặc chưa load apex.jQuery)');
    return;
  }
  parentJQ(_parentWin.document).on('apex:chatEvent', onChatEvent);
  console.info('[chat-erp][rt] Đã bind apex:chatEvent vào parent.document qua %s.',
    _parentWin.apex ? 'parent.apex.jQuery' : 'parent jQuery/$');
  // Nếu parent KHÔNG có cầu nối SSE (global.js mở EventSource), sự kiện sẽ không bao
  // giờ tới — cảnh báo để phân biệt "không nhận" vs "không bind".
  try{
    if(!_parentWin.apex || !_parentWin.apex.jQuery){
      console.warn('[chat-erp][rt] parent.apex.jQuery thiếu — global.js của 1503 có thể chưa nạp.');
    }
  }catch(e){ console.warn('[chat-erp][rt] Không đọc được parent (cross-origin?)', e); }
}
function onChatEvent(_, ev){
  if(!ev) return;
  if(ev.type === 'message'){
    loadConvList();
    if(ev.conv_id == activeConvId){
      // Tin của hội thoại đang mở → append vào thread, đánh dấu đã đọc, KHÔNG báo cross-doc.
      apexCall('msMsgThreadHtml', {x01: activeConvId}, function(html){
        document.getElementById('messages').innerHTML = html; initMsgActions(); scrollMessages();
      });
      apexCallJson('msMarkRead', {x01: activeConvId});
    } else {
      // Tin ở hội thoại khác → tăng unread + badge tổng.
      unreadMap[ev.conv_id] = (unreadMap[ev.conv_id] || 0) + 1;
      updateGlobalBadge();
      // Đang scope chứng từ mà tin tới TỪ hội thoại NGOÀI chứng từ đang xem → banner cross-doc.
      if(scopeMode === 'doc' && entryDoc && String(ev.doc_no || '') !== String(entryDoc.doc_no)){
        if(!crossDocQueue.some(x => x.conv_id == ev.conv_id)){
          crossDocQueue.push({conv_id: ev.conv_id, doc_no: ev.doc_no || null, conv_name: ev.conv_name || 'Hội thoại'});
        }
        showCrossDocBanner();
      }
    }
  }
}

/* ===== Badge tổng + cross-doc banner ===== */
function initUnreadSummary(){
  if(!currentUser || !currentUser.aus_id) return;
  nodeGet('/unread-summary/' + currentUser.aus_id, function(res){
    unreadMap = {};
    if(res && Array.isArray(res.by_conv)){
      res.by_conv.forEach(c => { unreadMap[c.conv_id] = c.unread; });
    }
    updateGlobalBadge();
  });
}
function unreadTotal(){
  let t = 0; for(const k in unreadMap){ t += unreadMap[k] || 0; } return t;
}
function updateGlobalBadge(){
  const total = unreadTotal();
  const el = document.getElementById('msgTotalBadge');   // badge trong modal (nếu có)
  if(el){ el.textContent = total > 99 ? '99+' : total; el.classList.toggle('hidden', total <= 0); }
  // Hook tới icon tin nhắn ở header HỆ THỐNG (app cha, ngoài file chat-erp): nếu app
  // cha có hàm window.msSetChatBadge(total) thì gọi để cập nhật badge launcher.
  try{ if(_parentWin && typeof _parentWin.msSetChatBadge === 'function') _parentWin.msSetChatBadge(total); }catch(e){}
}
function showCrossDocBanner(){
  const b = document.getElementById('crossdocBanner'); if(!b) return;
  const n = crossDocQueue.length;
  const txt = document.getElementById('crossdocText');
  if(txt) txt.textContent = n + (n>1 ? ' hội thoại khác có tin mới' : ' tin mới ở hội thoại khác');
  b.classList.remove('hidden');
}
function hideCrossDocBanner(){
  const b = document.getElementById('crossdocBanner'); if(b) b.classList.add('hidden');
}
function viewCrossDoc(){
  // Bấm [Xem]: chuyển sang "Tất cả" + mở hội thoại mới nhất ngoài scope.
  const last = crossDocQueue[crossDocQueue.length - 1];
  crossDocQueue = [];
  hideCrossDocBanner();
  if(entryDoc){ scopeMode = 'all'; applyScopeButtons(); }
  loadConvList();
  if(last && last.conv_id) openConversation2(last.conv_id);
}

/* ============================================================
   Sidebar — danh sách hội thoại (4 nhóm + nhóm con + Đã ghim)
   ============================================================ */
function loadConvList(){
  const q = (document.getElementById('sbSearch').value || '').trim();
  apexCall('msConvListHtml', {
    x01: filterType, x02: q, x03: unreadOnly ? '1' : '0',
    x04: scopeMode,
    x05: entryDoc ? entryDoc.doc_type : '',
    x06: entryDoc ? entryDoc.doc_no : ''
  }, function(html){
    document.getElementById('navScroll').innerHTML = html;
    applyOverflow();
    const any = document.querySelectorAll('#navScroll .sb-section').length > 0;
    document.getElementById('navEmpty').classList.toggle('hidden', any);
    if(activeConvId){
      document.querySelectorAll('[data-conv="'+activeConvId+'"]').forEach(e=>e.classList.add('active'));
    }
    maybeOpenDocRoom();
  });
}
/* Vào từ nút "Trao đổi" chứng từ: lần đầu danh sách load xong, tự mở phòng chung
   của chứng từ — phòng THẬT nếu đã có, hoặc PHÒNG ẢO nếu chưa (gõ là tạo). Chỉ
   chạy 1 lần để không cướp ngữ cảnh khi user tự điều hướng sau đó. */
let _docRoomChecked = false;
function maybeOpenDocRoom(){
  if(_docRoomChecked || scopeMode !== 'doc' || !entryDoc) return;
  _docRoomChecked = true;
  const main = document.querySelector('#navScroll .sb-section[data-group="chungtu"] .doc-item:not(.subgroup)[data-conv]');
  if(main){
    openConversation2(Number(main.dataset.conv));
  } else {
    openVirtualRoom({kind:'doc', doc_type: entryDoc.doc_type, doc_no: entryDoc.doc_no,
      title: entryDoc.doc_label || (entryDoc.doc_type+'-'+entryDoc.doc_no)});
  }
}

/* ============================================================
   Mở 1 hội thoại — thay cho openConversation() cũ (dữ liệu tĩnh)
   ============================================================ */
function openConversation2(convId, keepCompose){
  if(!convId) return;
  if(!keepCompose) exitComposeBar();   // điều hướng thường → đóng thanh "Tới:"
  activeConvId = convId;
  draftConv = null;   // mở hội thoại thật → bỏ phòng ảo đang chờ (nếu có)
  document.querySelectorAll('.conv,.doc-item').forEach(e=>e.classList.remove('active'));
  document.querySelectorAll('[data-conv="'+convId+'"]').forEach(e=>{
    e.classList.add('active');
    const b=e.querySelector('.badge,.di-badge'); if(b) b.remove();
  });

  apexCall('msMsgThreadHtml', {x01: convId}, function(html){
    document.getElementById('messages').innerHTML = html;
    initMsgActions();
    scrollMessages();
  });

  apexCallJson('msMarkRead', {x01: convId});
  // Đã đọc hội thoại này → trừ khỏi badge tổng + gỡ khỏi hàng đợi cross-doc.
  if(unreadMap[convId]){ unreadMap[convId] = 0; updateGlobalBadge(); }
  crossDocQueue = crossDocQueue.filter(x => x.conv_id != convId);
  if(crossDocQueue.length === 0) hideCrossDocBanner(); else showCrossDocBanner();
  loadMentionMembers(convId);

  // Header: lấy trực tiếp từ item sidebar đã render (tránh round-trip JSON riêng)
  const item = document.querySelector('[data-conv="'+convId+'"]');
  const section = item ? item.closest('.sb-section') : null;
  const kind = section ? section.dataset.group : 'nhom';
  activeConvKind = kind === 'pinned' ? 'nhom' : kind;
  activeConvIsDoc = (activeConvKind === 'chungtu');

  const nameEl = item ? (item.querySelector('.name') || item.querySelector('.di-code')) : null;
  const title = nameEl ? nameEl.textContent.trim() : '';
  document.getElementById('hName').textContent = title;
  const subText = activeConvKind==='canhan' ? 'Tin nhắn trực tiếp'
    : activeConvKind==='chungtu' ? 'Hội thoại theo chứng từ' : 'Hội thoại nhóm';
  document.getElementById('hSub').textContent = subText;
  const iconMap = {chungtu:'<span class="fa fa-file-o"></span>', channel:'#', nhom:'<span class="fa fa-group"></span>', canhan:'<span class="fa fa-user"></span>'};
  document.getElementById('hHash').innerHTML = iconMap[activeConvKind] || '<span class="fa fa-comment-o"></span>';

  const crumb = document.getElementById('crumb');
  const srcEl = item ? item.querySelector('.conv-src') : null;
  if(srcEl){
    document.getElementById('crumbText').textContent = srcEl.textContent.replace(/^thuộc /,'').trim();
    crumb.classList.remove('hidden');
  } else crumb.classList.add('hidden');

  const ci = paneComposer();
  if(ci){ ci.dataset.ph = 'Nhắn tin…'; ci.innerText=''; }
  cancelReply();
  closeMentionPop();

  // Side panel đang mở vẫn còn dữ liệu của hội thoại CŨ nếu không refresh ở đây —
  // openConversation2() trước đây chỉ cập nhật center/messages, không đụng #side.
  // "Thông tin hội thoại" tự nạp lại theo conv mới; "Luồng trả lời"/"Chi tiết chứng
  // từ" gắn với 1 tin/1 chứng từ cụ thể nên KHÔNG còn hợp lệ → đóng panel.
  if(layout.classList.contains('panel-open')){
    if(_sidePanelKind === 'info') openInfo();
    else closePanel();
  }
}
/* Alias để tương thích các onclick cũ trong HTML demo còn sót lại */
function selectConv(el,type,id){ openConversation2(id); }
function switchDoc(el,id){ openConversation2(id); }
function selectSubgroup(el,icon,parent,id){ openConversation2(id); }

/* ============================================================
   Gửi tin nhắn
   ============================================================ */
let replyTo = null;  // {id, fromName} khi đang trả lời 1 tin trong panel "Luồng trả lời"
function sendMessage(){
  const ci=paneComposer(); if(!ci) return;
  const text=serializeComposer(ci).trim(); if(!text) return;
  // Phòng ảo: chưa có hội thoại thật trong DB → tạo (materialize) trước rồi mới gửi.
  if(!activeConvId){
    if(draftConv){ materializeDraftThenSend(text, ci); }
    else if(newConvMode){ alert('Chọn người nhận trước khi gửi.'); }
    return;
  }
  _doSend(text, ci);
}
function _doSend(text, ci){
  closeMentionPop();
  ci.contentEditable = 'false';
  apexCallJson('msSendMsg', {x01: activeConvId, x02: text, x03: replyTo ? replyTo.id : ''}, function(res){
    ci.innerText=''; ci.contentEditable='true'; ci.focus();
    exitComposeBar();   // gửi xong tin đầu của hội thoại mới → đóng thanh "Tới:"
    cancelReply();
    apexCall('msMsgThreadHtml', {x01: activeConvId}, function(html){
      document.getElementById('messages').innerHTML = html; initMsgActions(); scrollMessages();
    });
    loadConvList();
    broadcastMessage(res);
  }, function(){ ci.contentEditable='true'; alert('Gửi tin thất bại, thử lại.'); });
}

/* ============================================================
   Phòng ảo (virtual room) — mở hội thoại trống KHÔNG ghi DB; chỉ tạo thật
   (materialize) khi gửi tin đầu tiên. Bỏ đi mà không gửi → không sinh row.
   ============================================================ */
function openVirtualRoom(draft){
  draftConv = draft;
  activeConvId = null;
  closeCompose();
  document.querySelectorAll('.conv,.doc-item').forEach(e=>e.classList.remove('active'));
  const kind = draft.kind;
  activeConvKind = kind==='dm' ? 'canhan' : kind==='doc' ? 'chungtu' : kind==='channel' ? 'channel' : 'nhom';
  activeConvIsDoc = (kind==='doc');
  document.getElementById('hName').innerHTML = escapeHtml(draft.title||'Hội thoại mới')+' <span class="new-chip">Mới</span>';
  document.getElementById('hSub').textContent =
    kind==='dm' ? 'Tin nhắn trực tiếp' : kind==='doc' ? 'Hội thoại theo chứng từ' : 'Hội thoại nhóm';
  const iconMap = {chungtu:'<span class="fa fa-file-o"></span>', channel:'#', nhom:'<span class="fa fa-group"></span>', canhan:'<span class="fa fa-user"></span>'};
  document.getElementById('hHash').innerHTML = iconMap[activeConvKind] || '<span class="fa fa-comment-o"></span>';
  document.getElementById('crumb').classList.add('hidden');
  document.getElementById('messages').innerHTML =
    '<div class="ve-empty"><span class="ve-ic fa fa-paper-plane-o"></span>'+
    '<div class="ve-title">Bắt đầu trao đổi</div>'+
    '<div class="ve-sub">Gửi tin đầu tiên để tạo hội thoại này.</div></div>';
  const ci=paneComposer();
  if(ci){ ci.dataset.ph='Nhắn tin để bắt đầu…'; ci.innerText=''; ci.contentEditable='true'; setTimeout(()=>ci.focus(),60); }
  cancelReply(); closeMentionPop();
  if(layout.classList.contains('panel-open')) closePanel();
}
/* Gửi tin đầu: tạo hội thoại thật theo kind rồi gửi (tái dùng _doSend). */
function materializeDraftThenSend(text, ci){
  const d = draftConv; if(!d) return;
  ci.contentEditable = 'false';
  const onConv = function(res){
    if(!res || !res.conv_id){ ci.contentEditable='true'; alert('Tạo hội thoại thất bại, thử lại.'); return; }
    activeConvId = res.conv_id;
    draftConv = null;
    // Phòng đã thật → gỡ nhãn "Mới" ở header.
    document.getElementById('hName').textContent = d.title || '';
    loadMentionMembers(activeConvId);
    _doSend(text, ci);
  };
  const onErr = function(){ ci.contentEditable='true'; alert('Tạo hội thoại thất bại, thử lại.'); };
  if(d.kind==='dm'){
    apexCallJson('msCreateDM', {x01: d.partnerId}, onConv, onErr);
  } else if(d.kind==='doc'){
    apexCallJson('msEnsureDocConv', {x01: d.doc_type, x02: d.doc_no}, onConv, onErr);
  } else if(d.kind==='nhom'){
    apexCallJson('msCreateGroup', {x01: d.name, x02: (d.memberIds||[]).join(','),
      x03: d.attachedDoc?d.attachedDoc.doc_type:'', x04: d.attachedDoc?d.attachedDoc.doc_no:''}, onConv, onErr);
  } else if(d.kind==='channel'){
    apexCallJson('msCreateChannel', {x01: d.name, x02: d.desc||'', x03: (d.roleIds||[]).join(',')}, onConv, onErr);
  } else {
    ci.contentEditable='true';
  }
}
function composerKey(e){
  if(_mentionOpen){
    if(e.key==='ArrowDown'){ e.preventDefault(); e.stopPropagation(); moveMentionSel(1); return; }
    if(e.key==='ArrowUp'){ e.preventDefault(); e.stopPropagation(); moveMentionSel(-1); return; }
    if(e.key==='Enter' || e.key==='Tab'){ e.preventDefault(); e.stopPropagation(); if(_mentionSel>=0) pickMention(_mentionSel); return; }
    if(e.key==='Escape'){ e.preventDefault(); e.stopPropagation(); closeMentionPop(); return; }
  }
  if(e.key==='Enter' && !e.shiftKey){ e.preventDefault(); sendMessage(); }
}

/* ============================================================
   Reaction — bấm nút mở thanh chọn emoji rồi mới react
   ============================================================ */
function initMsgActions(){ /* hook mở rộng nếu cần re-bind sau khi render lại thread */ }

const REACT_EMOJIS = ['👍','❤️','😆','😮','😢','🙏'];
let _reactMsgId = null;
function openReactBar(btn){
  const row = btn.closest('.msg'); if(!row) return;
  const bar = document.getElementById('reactBar');
  _reactMsgId = row.dataset.msgId;
  if(!bar.dataset.built){
    bar.innerHTML = REACT_EMOJIS.map(em=>`<button type="button" onclick="pickReact('${em}')">${em}</button>`).join('');
    bar.dataset.built = '1';
  }
  bar.classList.remove('hidden');
  const r = btn.getBoundingClientRect();
  const bw = bar.offsetWidth, bh = bar.offsetHeight;
  let left = Math.max(8, Math.min(r.left + r.width/2 - bw/2, window.innerWidth - bw - 8));
  let top = r.top - bh - 6; if(top < 8) top = r.bottom + 6;
  bar.style.left = left+'px'; bar.style.top = top+'px';
}
function closeReactBar(){ document.getElementById('reactBar').classList.add('hidden'); _reactMsgId = null; }
function pickReact(emoji){ if(_reactMsgId) applyReaction(_reactMsgId, emoji); closeReactBar(); }

function applyReaction(msgId, emoji){
  apexCallJson('msToggleReaction', {x01: msgId, x02: emoji}, function(res){
    const row = document.querySelector('#messages .msg[data-msg-id="'+msgId+'"]'); if(!row) return;
    let rc = row.querySelector('.reactions');
    let pill = rc ? [...rc.querySelectorAll('.reaction')].find(r=>r.dataset.emoji===emoji) : null;
    if(res.count <= 0){ if(pill) pill.remove(); if(rc && !rc.querySelector('.reaction')) rc.remove(); return; }
    if(!rc){ rc=document.createElement('div'); rc.className='reactions';
      row.querySelector('.body').insertBefore(rc, row.querySelector('.hover-actions')); }
    if(!pill){ pill=document.createElement('span'); pill.className='reaction'; pill.dataset.msgId=msgId; pill.dataset.emoji=emoji;
      pill.setAttribute('onclick','toggleReaction(this)'); rc.appendChild(pill); }
    pill.classList.toggle('mine', res.mine);
    pill.innerHTML = emoji+' <span>'+res.count+'</span>';
  });
}
function toggleReaction(el){
  const msgId = el.dataset.msgId, emoji = el.dataset.emoji || '👍'; if(!msgId) return;
  applyReaction(msgId, emoji);
}

/* ============================================================
   Reply inline — preview bar trên composer (openThread vẫn giữ riêng)
   ============================================================ */
function startReply(btn){
  const row = btn.closest('.msg'); if(!row) return;
  const txtEl = row.querySelector('.text:last-of-type');
  replyTo = { id: row.dataset.msgId, fromName: row.dataset.fromName || '' };
  document.getElementById('rpTo').textContent = 'Đang trả lời ' + (replyTo.fromName || '');
  document.getElementById('rpText').textContent = txtEl ? txtEl.textContent.trim() : '[Tệp đính kèm]';
  document.getElementById('replyPreview').classList.add('active');
  const ci = paneComposer(); if(ci) ci.focus();
}
function cancelReply(){
  replyTo = null;
  const rp = document.getElementById('replyPreview'); if(rp) rp.classList.remove('active');
}

/* ============================================================
   Mention (@tên) — gợi ý thành viên hội thoại, chỉ highlight hiển thị
   ============================================================ */
let _mentionMembers = [];               // [{name, ini, hue}] thành viên conv hiện tại
let _mentionList = [];                   // kết quả lọc đang hiển thị
let _mentionOpen = false, _mentionSel = 0;
function loadMentionMembers(convId){
  _mentionMembers = [];
  apexCallJson('msMentionList', {x01: convId}, function(res){
    _mentionMembers = (res && res.members) || [];
  }, function(){ _mentionMembers = []; });
}
function composerInput(){
  const sel = window.getSelection();
  if(!sel || !sel.rangeCount){ closeMentionPop(); return; }
  const range = sel.getRangeAt(0), node = range.startContainer;
  if(node.nodeType !== 3){ closeMentionPop(); return; }
  const m = node.nodeValue.slice(0, range.startOffset).match(/@([^\s@]*)$/);
  if(!m){ closeMentionPop(); return; }
  openMentionPop(m[1]);
}
function openMentionPop(query){
  const pop = document.getElementById('mentionPop');
  const q = (query||'').toLowerCase();
  _mentionList = _mentionMembers.filter(mb=>(mb.name||'').toLowerCase().includes(q));
  if(!_mentionList.length){
    pop.innerHTML = '<div class="mp-empty">Không có thành viên phù hợp</div>';
    pop.classList.remove('hidden'); _mentionOpen = true; _mentionSel = -1; return;
  }
  _mentionSel = 0;
  pop.innerHTML = _mentionList.map((mb,i)=>
    `<div class="mention-item${i===0?' sel':''}" data-i="${i}" onmousedown="event.preventDefault();pickMention(${i})">`+
    `<span class="avatar" style="background:hsl(${mb.hue||200},55%,52%)">${escapeHtml(mb.ini||(mb.name||'?')[0])}</span>`+
    `<span>${escapeHtml(mb.name||'')}</span></div>`).join('');
  pop.classList.remove('hidden'); _mentionOpen = true;
}
function closeMentionPop(){ const pop = document.getElementById('mentionPop'); if(pop) pop.classList.add('hidden'); _mentionOpen = false; }
function moveMentionSel(d){
  if(!_mentionList.length) return;
  _mentionSel = (_mentionSel + d + _mentionList.length) % _mentionList.length;
  document.getElementById('mentionPop').querySelectorAll('.mention-item')
    .forEach(el=>el.classList.toggle('sel', +el.dataset.i===_mentionSel));
}
function pickMention(i){
  const mb = _mentionList[i]; if(!mb){ closeMentionPop(); return; }
  const ci = paneComposer(), sel = window.getSelection();
  if(sel && sel.rangeCount){
    const range = sel.getRangeAt(0), node = range.startContainer;
    if(node.nodeType === 3){
      const m = node.nodeValue.slice(0, range.startOffset).match(/@([^\s@]*)$/);
      if(m){
        const r2 = document.createRange();
        r2.setStart(node, range.startOffset - m[0].length); r2.setEnd(node, range.startOffset);
        r2.deleteContents();
        const chip = document.createElement('span');
        chip.className = 'mention-chip'; chip.contentEditable = 'false';
        chip.dataset.name = mb.name; chip.textContent = '@' + mb.name;
        const space = document.createTextNode(' ');
        r2.insertNode(space); r2.insertNode(chip);
        const r3 = document.createRange(); r3.setStartAfter(space); r3.collapse(true);
        sel.removeAllRanges(); sel.addRange(r3);
      }
    }
  }
  closeMentionPop(); if(ci) ci.focus();
}
function mentionFromButton(){
  const ci = paneComposer(); if(!ci) return;
  ci.focus(); document.execCommand('insertText', false, '@'); composerInput();
}
// Chuyển nội dung composer thành text gửi đi: chip @tên -> sentinel @[tên] để render highlight lại
function serializeComposer(ci){
  function walk(node){
    let s = '';
    node.childNodes.forEach(n=>{
      if(n.nodeType === 3) s += n.nodeValue;
      else if(n.nodeType === 1){
        if(n.classList.contains('mention-chip')) s += '@[' + (n.dataset.name || n.textContent.replace(/^@/,'')) + ']';
        else if(n.tagName === 'BR') s += '\n';
        else s += walk(n);
      }
    });
    return s;
  }
  return walk(ci);
}

// Đóng react bar / mention pop khi bấm ra ngoài
document.addEventListener('mousedown', e=>{
  const bar = document.getElementById('reactBar');
  if(bar && !bar.classList.contains('hidden') && !bar.contains(e.target) && !e.target.closest('.hover-actions')) closeReactBar();
  const mp = document.getElementById('mentionPop');
  if(mp && !mp.classList.contains('hidden') && !mp.contains(e.target) && !e.target.closest('.composer .input')) closeMentionPop();
});

/* ============================================================
   Luồng trả lời — lọc trực tiếp trên DOM đã render (data-reply-to),
   không cần round-trip riêng. Composer trong panel gửi reply thật.
   ============================================================ */
function openThread(msgId){
  const row = document.querySelector('#messages .msg[data-msg-id="'+msgId+'"]');
  const parentText = row ? row.querySelector('.text').textContent : '';
  const parentFrom = row ? (row.dataset.fromName || '') : '';
  const replies = [...document.querySelectorAll('#messages .msg[data-reply-to="'+msgId+'"]')];

  const repliesHtml = replies.map(r=>{
    const who = r.dataset.fromName || '';
    const txt = r.querySelector('.text:last-of-type') ? r.querySelector('.text:last-of-type').textContent : '';
    return '<div class="thread-msg"><span class="avatar" style="background:hsl('+(Math.abs(hashCode(who))%360)+',55%,52%)">'+
      (who[0]||'?').toUpperCase()+'</span><div><div class="meta"><span class="who">'+escapeHtml(who)+'</span></div>'+
      '<div class="text">'+escapeHtml(txt)+'</div></div></div>';
  }).join('') || '<div style="font-size:12.5px;color:var(--text-tertiary);padding:8px 0">Chưa có trả lời nào</div>';

  side.innerHTML = `
    <div class="side-head"><span class="st">Luồng trả lời</span><span style="flex:1"></span>
      <button class="icon-btn" type="button" onclick="closePanel()" title="Đóng"><span class="fa fa-close"></span></button></div>
    <div class="side-body">
      <div style="font-size:12.5px;color:var(--text-secondary)">${escapeHtml(parentFrom)}</div>
      <div class="thread-msg" style="margin-top:4px"><div class="text">${escapeHtml(parentText)}</div></div>
      <div class="thread-reply-count">${replies.length} trả lời</div>
      ${repliesHtml}
    </div>
    <div class="side-foot">
      <div class="composer" style="margin:0">
        <div class="input" id="threadReplyInput" contenteditable="true" data-ph="Trả lời trong luồng…" onkeydown="threadReplyKey(event,${msgId})"></div>
        <div class="tools"><div class="send"><span class="kbdhint">⌘↵</span><button class="btn primary" type="button" onclick="sendThreadReply(${msgId})">Gửi</button></div></div>
      </div>
    </div>`;
  layout.classList.add('panel-open'); side.setAttribute('aria-hidden','false');
  _sidePanelKind = 'thread';
}
function threadReplyKey(e,msgId){ if(e.key==='Enter' && !e.shiftKey){ e.preventDefault(); sendThreadReply(msgId); } }
function sendThreadReply(msgId){
  const ci=document.getElementById('threadReplyInput'); if(!ci || !activeConvId) return;
  const text=ci.innerText.trim(); if(!text) return;
  apexCallJson('msSendMsg', {x01: activeConvId, x02: text, x03: msgId}, function(res){
    apexCall('msMsgThreadHtml', {x01: activeConvId}, function(html){
      document.getElementById('messages').innerHTML = html; initMsgActions(); scrollMessages();
      openThread(msgId);  // re-render panel với reply mới
    });
    broadcastMessage(res);
  });
}
/* Phát SSE cho thành viên khác sau khi 1 callback ghi tin nhắn thành công.
   res = JSON trả về từ msSendMsg/msUploadFile, đã enrich đủ trường ở PL/SQL. */
function broadcastMessage(res){
  if(!res || !res.msg_id){
    console.warn('[chat-erp][rt] broadcastMessage bỏ qua: res thiếu msg_id', res);
    return;
  }
  nodePost('/broadcast-message', {
    conv_id: res.conv_id, msg_id: res.msg_id, aus_id: res.from_aus_id,
    from_name: res.from_name, body: res.body, fil_id: res.fil_id || null,
    file_name: res.file_name || null, file_disp_name: res.file_disp_name || null,
    reply_to_msg_id: res.reply_to_msg_id || null,
    doc_type: res.doc_type || null, doc_no: res.doc_no || null,
    conv_type: res.conv_type, conv_name: res.conv_name
  }, function(r){
    console.info('[chat-erp][rt] /broadcast-message OK conv=%s msg=%s →', res.conv_id, res.msg_id, r);
  }, function(err){
    console.error('[chat-erp][rt] /broadcast-message THẤT BẠI (CORS/mạng?) →', err);
  });
}
function hashCode(s){ let h=0; for(let i=0;i<s.length;i++){h=(h<<5)-h+s.charCodeAt(i);h|=0;} return h; }
function escapeHtml(s){return (s||'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));}

/* ============================================================
   Chi tiết chứng từ — ngoài phạm vi schema chat (thuộc module ERP gốc).
   Giữ placeholder điều hướng; nối API module thật khi tích hợp.
   ============================================================ */
function openDetail(docNo){
  side.innerHTML = `
    <div class="side-head"><span class="st">Chi tiết · ${escapeHtml(docNo||'')}</span><span style="flex:1"></span>
      <button class="icon-btn" type="button" onclick="closePanel()" title="Đóng"><span class="fa fa-close"></span></button></div>
    <div class="side-body"><div style="font-size:13px;color:var(--text-secondary)">
      Chi tiết chứng từ lấy từ module ERP gốc (Đơn hàng/Hóa đơn/Phiếu thu...), ngoài phạm vi schema CHAT_*.
      Nối API/region của module tương ứng tại đây theo doc_type/doc_no của hội thoại.</div></div>`;
  layout.classList.add('panel-open'); side.setAttribute('aria-hidden','false');
  _sidePanelKind = 'detail';
}
function closePanel(){layout.classList.remove('panel-open');side.setAttribute('aria-hidden','true');_sidePanelKind=null;setTimeout(()=>side.innerHTML='',180)}

/* ============================================================
   Panel "Thông tin hội thoại" — từ msInfoHtml
   ============================================================ */
function openInfo(){
  if(!activeConvId) return;
  apexCall('msInfoHtml', {x01: activeConvId}, function(html){
    side.innerHTML = html;
    layout.classList.add('panel-open'); side.setAttribute('aria-hidden','false');
    _sidePanelKind = 'info';
  });
}
function toggleInfoSection(btn){
  btn.classList.toggle('collapsed');
  btn.nextElementSibling.classList.toggle('collapsed');
}
function openDocFromMenu(){ toggleMoreMenu(); if(activeConvIsDoc) openDetail(document.getElementById('hName').textContent); }

/* ===== Toast realtime — nút demo giữ lại để test UI, sự kiện thật vào qua onChatEvent() ===== */
function simulateToast(){ document.getElementById('toast').classList.remove('hidden'); }
function hideToast(){document.getElementById('toast').classList.add('hidden');}
function viewToast(){ hideToast(); }

/* ===== Sidebar: collapse section ===== */
function toggleSection(btn){
  btn.classList.toggle('collapsed');
  btn.parentElement.querySelector('.sec-body').classList.toggle('collapsed');
}

/* Giới hạn tối đa 5 mục / section + nút Xem thêm */
const OV_MAX=5;
function applyOverflow(){
  document.querySelectorAll('#navScroll .sb-section').forEach(sec=>{
    if(sec.dataset.group==='pinned') return;
    const body=sec.querySelector('.sec-body'); if(!body) return;
    const items=[...body.querySelectorAll(':scope > .conv, :scope > .doc-item')];
    const expanded = body.dataset.expanded==='1';
    items.forEach((e,i)=> e.classList.toggle('ov-hidden', !expanded && i>=OV_MAX));
    let btn=body.querySelector('.show-more');
    if(items.length>OV_MAX){
      if(!btn){ btn=document.createElement('button'); btn.type='button'; btn.className='show-more';
        btn.addEventListener('click',()=>toggleSectionMore(body)); }
      body.appendChild(btn);
      btn.style.display='';
      btn.innerHTML = expanded
        ? '<span class="fa fa-chevron-up"></span> Thu gọn'
        : `<span class="fa fa-chevron-down"></span> Xem thêm ${items.length-OV_MAX}`;
    } else if(btn){ btn.style.display='none'; }
  });
}
function toggleSectionMore(body){
  body.dataset.expanded = body.dataset.expanded==='1' ? '0' : '1';
  applyOverflow();
}

/* ===== Filter loại + tìm kiếm + chưa đọc — giờ trigger loadConvList() (server-driven) ===== */
const TYPE_LABEL={all:'Tất cả',chungtu:'Chứng từ',channel:'Channel',nhom:'Nhóm',canhan:'Cá nhân'};
let filterType='all';
let unreadOnly=false;
let _sbSearchTimer=null;
function filterSidebar(){
  clearTimeout(_sbSearchTimer);
  _sbSearchTimer = setTimeout(loadConvList, 250);
}
function toggleTypeMenu(e){
  if(e) e.stopPropagation();
  const m=document.getElementById('typeMenu');
  const open=m.classList.toggle('hidden')===false;
  document.getElementById('typePill').setAttribute('aria-expanded', open?'true':'false');
}
function setType(item){
  filterType=item.dataset.type;
  item.parentElement.querySelectorAll('.type-item').forEach(i=>i.classList.toggle('sel',i===item));
  document.getElementById('typeLabel').textContent=TYPE_LABEL[filterType];
  const active=filterType!=='all';
  document.getElementById('typePill').classList.toggle('on',active);
  document.getElementById('typeCaret').style.display=active?'none':'';
  document.getElementById('typeClear').style.display=active?'':'none';
  document.getElementById('typeMenu').classList.add('hidden');
  loadConvList();
}
function clearType(e){
  if(e) e.stopPropagation();
  filterType='all';
  document.querySelectorAll('#typeMenu .type-item').forEach(i=>i.classList.toggle('sel',i.dataset.type==='all'));
  document.getElementById('typeLabel').textContent=TYPE_LABEL.all;
  document.getElementById('typePill').classList.remove('on');
  document.getElementById('typeCaret').style.display='';
  document.getElementById('typeClear').style.display='none';
  loadConvList();
}
function clearFilters(){
  document.getElementById('sbSearch').value='';
  unreadOnly=false;
  const up=document.getElementById('unreadPill'); up.classList.remove('on'); up.setAttribute('aria-pressed','false');
  clearType();
}
function toggleUnread(){
  unreadOnly=!unreadOnly;
  const p=document.getElementById('unreadPill');
  p.classList.toggle('on',unreadOnly);
  p.setAttribute('aria-pressed',unreadOnly?'true':'false');
  loadConvList();
}
document.addEventListener('click',e=>{
  const m=document.getElementById('typeMenu');
  if(!m.classList.contains('hidden') && !document.getElementById('typeSelect').contains(e.target)) toggleTypeMenu();
  const rm=document.getElementById('roleMenu');
  if(rm && !rm.classList.contains('hidden') && !document.getElementById('roleSelect').contains(e.target)) toggleRoleMenu();
});

/* ============================================================
   Soạn mới — people picker dùng msContactsHtml (server), lưu lựa chọn
   bằng Map(aus_id -> {name,hue}) đọc trực tiếp từ dataset DOM trả về,
   KHÔNG cần directory tĩnh / round-trip JSON riêng.
   ============================================================ */
let selected=[];          // mảng aus_id (number) đã chọn — dùng chung picker & group
let selectedMeta={};      // {aus_id: {name, hue}}
let inGroupCtx=false;
let attachedDoc=null;     // {doc_type, doc_no, label} — gắn chứng từ khi tạo Nhóm


function closeCompose(){
  document.getElementById('composePicker').classList.add('hidden');
  document.getElementById('composeGroup').classList.add('hidden');
  document.getElementById('composeChannel').classList.add('hidden');
  document.getElementById('composeSubgroup').classList.add('hidden');
}
function openPeoplePicker(){
  selected=[]; selectedMeta={}; inGroupCtx=false;
  renderChips(); renderPeople(''); updatePickFoot();
  document.getElementById('composeGroup').classList.add('hidden');
  document.getElementById('composePicker').classList.remove('hidden');
  setTimeout(()=>document.getElementById('toInput').focus(),50);
}
function openCreateGroup(){
  inGroupCtx=true; attachedDoc=null;
  document.getElementById('grpName').value=''; clearErr();
  renderChips(); renderPeople('',true);
  document.getElementById('grpDoc').textContent=''; renderPreview();
  document.getElementById('composePicker').classList.add('hidden');
  document.getElementById('composeGroup').classList.remove('hidden');
  setTimeout(()=>document.getElementById('grpName').focus(),50);
}
let _peopleTimer=null;
function renderPeople(q,grp){
  clearTimeout(_peopleTimer);
  _peopleTimer = setTimeout(function(){
    apexCall('msContactsHtml', {x01: q||''}, function(html){
      const list=grp?document.getElementById('grpPeopleList'):document.getElementById('peopleList');
      list.innerHTML = '<div class="picker-label">'+((q||'').trim()?'Kết quả':'Gợi ý')+'</div>' +
        (html || '<div class="person"><div class="pinfo"><div class="pn">Không tìm thấy</div></div></div>');
      list.querySelectorAll('.person[data-id]').forEach(p=>{
        const id=Number(p.dataset.id);
        selectedMeta[id] = {name: p.dataset.name, hue: p.dataset.hue,
                            dm: p.dataset.conv ? Number(p.dataset.conv) : null};
        p.classList.toggle('sel', selected.includes(id));
      });
    });
  }, 200);
}
function togglePerson(id,grp){
  id = Number(id);
  selected.includes(id) ? selected=selected.filter(x=>x!==id) : selected.push(id);
  document.querySelectorAll('.person[data-id="'+id+'"]').forEach(p=>p.classList.toggle('sel',selected.includes(id)));
  renderChips();
  grp ? renderPreview() : updatePickFoot();
}
function renderChips(){
  const html=selected.map(id=>{const m=selectedMeta[id]||{name:'?',hue:200};
    return `<span class="chip-person"><span class="ca" style="background:hsl(${m.hue},55%,52%)">${(m.name||'?')[0]}</span>${escapeHtml(m.name||'')}<span class="x" onclick="event.stopPropagation();togglePerson(${id},${inGroupCtx})"><span class="fa fa-close"></span></span></span>`;}).join('');
  document.getElementById(inGroupCtx?'grpChips':'toChips').innerHTML=html;
}
function updatePickFoot(){
  const n=selected.length, act=document.getElementById('pickAction');
  document.getElementById('pickCount').textContent = n===0?'Chưa chọn ai':`Đã chọn ${n} người`;
  act.textContent = n>=2?'Tạo nhóm':'Nhắn tin';
  act.disabled = n===0; act.style.opacity=n===0?.5:1;
}
function autoGroupName(ids){
  const names = ids.map(id=>(selectedMeta[id]||{}).name).filter(Boolean);
  if(names.length<=2) return names.join(', ');
  return names.slice(0,2).join(', ')+' và '+(names.length-2)+' người khác';
}
function pickerSubmit(){
  if(selected.length===0) return;
  if(selected.length>=2){
    // Nhóm kiểu Messenger: vào thẳng phòng ảo, tên tự sinh từ thành viên đã chọn —
    // đổi tên sau qua menu "Thêm" → "Đổi tên" (renameConvFromMenu).
    const ids = selected.slice();
    const name = autoGroupName(ids);
    closeCompose();
    openVirtualRoom({kind:'nhom', name: name, memberIds: ids, title: name});
    return;
  }
  // DM kiểu Messenger: đã có hội thoại với người này → LOAD hội thoại cũ;
  // chưa có → mở phòng ảo (chỉ tạo DM thật khi gửi tin đầu).
  const pid = selected[0];
  const m = selectedMeta[pid] || {};
  closeCompose();
  if(m.dm){ openConversation2(m.dm); }
  else { openVirtualRoom({kind:'dm', partnerId: pid, title: m.name || 'Hội thoại'}); }
}

/* ============================================================
   Soạn mới kiểu Messenger — thanh "Tới:" + dropdown nhân viên giàu thông tin
   (avatar · tên · mã · chức danh · chấm online). Bấm compose-btn → vào THẲNG
   phòng chat ảo trống + thanh chọn người. 1 người → DM (dedup), ≥2 → nhóm ảo.
   ============================================================ */
let newConvMode = false;   // đang ở phiên soạn hội thoại mới (thanh "Tới:" mở)
let ncDir = {};            // aus_id -> {name,hue,dm,code,pos,online} (thư mục đã tải)
let ncRows = [];           // aus_id theo thứ tự đang render trong dropdown (cho phím ↑↓)
let ncActive = -1;         // chỉ số dòng đang sáng (điều hướng bàn phím)
let _ncTimer = null;

function startNewConversation(){
  selected = []; newConvMode = true; draftConv = null; activeConvId = null;
  document.getElementById('newConvBar').classList.remove('hidden');
  document.getElementById('ncChips').innerHTML = '';
  document.getElementById('ncInput').value = '';
  document.querySelectorAll('.conv,.doc-item').forEach(e=>e.classList.remove('active'));
  applyDraftFromSelection();   // header "Tin nhắn mới" + empty state, composer sẵn sàng
  ncSearch('');                // nạp gợi ý ban đầu
  ncOpenList();
  setTimeout(()=>document.getElementById('ncInput').focus(), 60);
}
function cancelNewConv(){
  newConvMode = false; draftConv = null; activeConvId = null; selected = [];
  ncCloseList();
  document.getElementById('newConvBar').classList.add('hidden');
  document.getElementById('messages').innerHTML = '';
  document.getElementById('hName').textContent = 'Chọn 1 hội thoại';
  document.getElementById('hSub').textContent = '';
  document.getElementById('hHash').innerHTML = '<span class="fa fa-comment-o"></span>';
}
function exitComposeBar(){
  if(!newConvMode) return;
  newConvMode = false; ncCloseList();
  document.getElementById('newConvBar').classList.add('hidden');
}
function ncOpenList(){
  document.getElementById('ncList').classList.remove('hidden');
  document.getElementById('ncInput').setAttribute('aria-expanded','true');
}
function ncCloseList(){
  document.getElementById('ncList').classList.add('hidden');
  document.getElementById('ncInput').setAttribute('aria-expanded','false');
  ncActive = -1;
}
/* Gọi msContactsHtml → parse .person → dựng lại dòng giàu thông tin. */
function ncSearch(q){
  ncRenderSkeleton();
  apexCall('msContactsHtml', {x01: q||''}, function(html){
    const tmp = document.createElement('div'); tmp.innerHTML = html;
    const people = [...tmp.querySelectorAll('.person[data-id]')];
    people.forEach(p=>{
      const id = Number(p.dataset.id);
      const av = p.querySelector('.pa');
      ncDir[id] = {
        name: p.dataset.name || '', hue: p.dataset.hue,
        dm: p.dataset.conv ? Number(p.dataset.conv) : null,
        code: p.dataset.code || '', pos: p.dataset.pos || '',
        online: p.dataset.online === '1',
        avInner: av ? av.innerHTML : ''   // giữ <img> thật nếu có, fallback chữ cái
      };
      selectedMeta[id] = ncDir[id];       // dùng chung cho chip
    });
    ncRenderRows(people.map(p=>Number(p.dataset.id)).filter(id=>!selected.includes(id)), q);
  });
}
function ncRenderSkeleton(){
  let s = '';
  for(let i=0;i<5;i++) s += '<div class="nc-skel-row"><div class="nc-skel-av"></div>'+
    '<div class="nc-skel-lines"><div class="nc-skel-line w60"></div><div class="nc-skel-line w35"></div></div></div>';
  document.getElementById('ncList').innerHTML = s;
  ncRows = []; ncActive = -1;
}
function ncRenderRows(ids, q){
  const list = document.getElementById('ncList');
  ncRows = ids; ncActive = -1;
  if(ids.length === 0){
    list.innerHTML = '<div class="nc-empty">Không tìm thấy nhân viên'+
      (q && q.trim() ? ' khớp “'+escapeHtml(q.trim())+'”' : '')+'.</div>';
    return;
  }
  const cap = (q && q.trim()) ? 'Kết quả' : 'Gợi ý';
  let html = '<div class="nc-list-cap">'+cap+'</div>';
  html += ids.map((id, i)=>{
    const m = ncDir[id] || {};
    const sub = [m.code ? '<span class="nc-code">'+escapeHtml(m.code)+'</span>' : '',
                 m.pos ? escapeHtml(m.pos) : '']
                .filter(Boolean).join('<span class="nc-dot">·</span>');
    return '<div class="nc-person" role="option" data-i="'+i+'" onmouseenter="ncSetActive('+i+')" onclick="ncPick('+id+')">'+
      '<span class="nc-av" style="background:hsl('+m.hue+',55%,52%)">'+(m.avInner||'?')+
        '<span class="nc-presence '+(m.online?'online':'')+'"></span></span>'+
      '<span class="nc-info"><span class="nc-name">'+escapeHtml(m.name||'')+'</span>'+
        (sub ? '<span class="nc-sub">'+sub+'</span>' : '')+'</span>'+
      '<span class="nc-add fa fa-plus"></span></div>';
  }).join('');
  list.innerHTML = html;
}
function ncSetActive(i){
  ncActive = i;
  document.querySelectorAll('#ncList .nc-person').forEach(el=>
    el.classList.toggle('active', Number(el.dataset.i)===i));
}
function ncMoveActive(dir){
  if(ncRows.length===0) return;
  ncActive = (ncActive + dir + ncRows.length) % ncRows.length;
  ncSetActive(ncActive);
  const el = document.querySelector('#ncList .nc-person[data-i="'+ncActive+'"]');
  if(el) el.scrollIntoView({block:'nearest'});
}
function ncPick(id){
  addRecipient(id);
  const input = document.getElementById('ncInput');
  input.value = '';
  ncSearch('');                 // làm mới danh sách (bỏ người vừa chọn)
  setTimeout(()=>input.focus(), 30);
}
function ncInputChange(input){
  ncOpenList();
  clearTimeout(_ncTimer);
  _ncTimer = setTimeout(()=>ncSearch(input.value), 200);
}
function ncInputKey(e){
  const input = e.target;
  if(e.key==='ArrowDown'){ e.preventDefault(); ncOpenList(); ncMoveActive(1); return; }
  if(e.key==='ArrowUp'){ e.preventDefault(); ncMoveActive(-1); return; }
  if(e.key==='Enter'){
    if(ncActive>=0 && ncRows[ncActive]!=null){ e.preventDefault(); ncPick(ncRows[ncActive]); }
    return;
  }
  if(e.key==='Escape'){
    if(!document.getElementById('ncList').classList.contains('hidden')){ e.stopPropagation(); ncCloseList(); }
    return;
  }
  if(e.key==='Backspace' && input.value==='' && selected.length){ ncRemove(selected[selected.length-1]); }
}
function addRecipient(id){
  if(!selected.includes(id)) selected.push(id);
  renderNcChips(); applyDraftFromSelection();
}
function ncRemove(id){
  selected = selected.filter(x=>x!==id);
  renderNcChips(); ncSearch(document.getElementById('ncInput').value); applyDraftFromSelection();
}
/* Đóng dropdown khi bấm ra ngoài thanh "Tới:".
   Bỏ qua click trên compose-btn (chính nó vừa mở thanh — tránh đóng ngay). */
document.addEventListener('click', function(e){
  if(e.target.closest && e.target.closest('.compose-btn')) return;
  const bar = document.getElementById('newConvBar');
  if(bar && !bar.classList.contains('hidden') && !bar.contains(e.target)) ncCloseList();
});
function renderNcChips(){
  const html = selected.map(id=>{
    const m = selectedMeta[id] || {name:'?', hue:200};
    return `<span class="chip-person"><span class="ca" style="background:hsl(${m.hue},55%,52%)">${(m.name||'?')[0]}</span>${escapeHtml(m.name||'')}<span class="x" onclick="event.stopPropagation();ncRemove(${id})"><span class="fa fa-close"></span></span></span>`;
  }).join('');
  document.getElementById('ncChips').innerHTML = html;
}
/* Suy ra phòng ảo từ số người đã chọn — gọi lại mỗi khi thêm/bớt người. */
function applyDraftFromSelection(){
  if(selected.length === 0){
    draftConv = null; activeConvId = null;
    document.getElementById('hName').innerHTML = 'Tin nhắn mới';
    document.getElementById('hSub').textContent = 'Chọn người nhận để bắt đầu';
    document.getElementById('hHash').innerHTML = '<span class="fa fa-pencil-square-o"></span>';
    document.getElementById('crumb').classList.add('hidden');
    document.getElementById('messages').innerHTML =
      '<div class="ve-empty"><span class="ve-ic fa fa-paper-plane-o"></span>'+
      '<div class="ve-title">Hội thoại mới</div>'+
      '<div class="ve-sub">Chọn người nhận ở ô “Tới:” phía trên.</div></div>';
    const ci = paneComposer(); if(ci){ ci.innerText=''; ci.dataset.ph='Chọn người nhận trước…'; }
    return;
  }
  if(selected.length === 1){
    const pid = selected[0], m = selectedMeta[pid] || {};
    if(m.dm){ openConversation2(m.dm, true); }   // có DM cũ → load lịch sử, giữ thanh "Tới:"
    else { openVirtualRoom({kind:'dm', partnerId: pid, title: m.name || 'Hội thoại'}); }
    return;
  }
  const ids = selected.slice(), name = autoGroupName(ids);
  openVirtualRoom({kind:'nhom', name: name, memberIds: ids, title: name});
}

/* Create group (nhóm luôn riêng tư) */
function attachDoc(){
  const doc_no = prompt('Nhập mã chứng từ (vd: SO-2026-0148):'); if(!doc_no) return;
  const doc_type = prompt('Loại chứng từ (vd: SO/INV/PT/PC):','SO') || 'SO';
  attachedDoc={doc_type, doc_no};
  document.getElementById('grpDoc').innerHTML='<span class="fa fa-file-o"></span> '+escapeHtml(doc_no);
  renderPreview();
}
function clearErr(){document.getElementById('grpErr').classList.remove('show');}
function renderPreview(){
  const name=document.getElementById('grpName').value.trim();
  document.getElementById('pvAv').textContent=(name||'N')[0].toUpperCase();
  document.getElementById('pvName').textContent=name||'Nhóm chưa đặt tên';
  document.getElementById('pvMeta').innerHTML=`<span class="fa fa-lock"></span> Riêng tư · ${selected.length+1} thành viên`;
  document.getElementById('pvMembers').innerHTML='<div class="pv-row">◉ Bạn (Quản trị)</div>'+
    selected.map(id=>`<div class="pv-row">◉ ${escapeHtml((selectedMeta[id]||{}).name||'')}</div>`).join('');
  const dw=document.getElementById('pvDocWrap');
  if(attachedDoc){dw.style.display='';document.getElementById('pvDoc').innerHTML=`<div class="pv-row"><span class="fa fa-file-o"></span> ${escapeHtml(attachedDoc.doc_no)}</div>`;}
  else dw.style.display='none';
}
function createGroup(){
  const name=document.getElementById('grpName').value.trim();
  if(!name){document.getElementById('grpErr').classList.add('show');document.getElementById('grpName').focus();return;}
  if(selected.length===0){alert('Thêm ít nhất 1 thành viên');return;}
  // Nhóm: giữ bước nhập tên+thành viên, nhưng mở phòng ảo — chỉ INSERT (msCreateGroup)
  // khi gửi tin đầu. Snapshot lựa chọn vì `selected` dùng chung, sẽ bị reset.
  openVirtualRoom({kind:'nhom', name: name, memberIds: selected.slice(),
    attachedDoc: attachedDoc, title: name});
}

/* ===== Tạo Channel (công khai, theo nhóm quyền) =====
   data-role giờ là gus_id thật (số), không phải tên — cần map sẵn trong
   #roleMenu .role-item data-role="<gus_id>" data-role-name="<tên nhóm quyền>"
   khi paste vào APEX (render tĩnh từ GROUP_USERS, xem ghi chú cuối file). */
let chRoles=[];   // gus_id đã chọn (number[])
function slugify(s){
  return s.toLowerCase().trim()
    .normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/đ/g,'d')
    .replace(/[^a-z0-9\s-]/g,'').replace(/\s+/g,'-').replace(/-+/g,'-');
}
function openCreateChannel(){
  chRoles=[];
  document.getElementById('chName').value='';
  document.getElementById('chDesc').value='';
  document.getElementById('chErr').classList.remove('show');
  document.querySelectorAll('#roleMenu .role-item').forEach(o=>o.classList.remove('sel','dim'));
  document.getElementById('roleMenu').classList.add('hidden');
  renderRoleChips();
  renderChannelPreview();
  document.getElementById('composePicker').classList.add('hidden');
  document.getElementById('composeGroup').classList.add('hidden');
  document.getElementById('composeChannel').classList.remove('hidden');
  setTimeout(()=>document.getElementById('chName').focus(),50);
}
function toggleRoleMenu(e){
  if(e) e.stopPropagation();
  const m=document.getElementById('roleMenu');
  const open=m.classList.toggle('hidden')===false;
  m.previousElementSibling.setAttribute('aria-expanded', open?'true':'false');
}
function toggleRole(item){
  const role=item.dataset.role, name=item.dataset.roleName||item.textContent.trim(), on=!item.classList.contains('sel');
  item.classList.toggle('sel',on);
  if(on) chRoles.push(role); else chRoles=chRoles.filter(r=>r!==role);
  if(name==='Toàn công ty' && on) chRoles=[]; // "Toàn công ty" = không gán role nào (xem msCreateChannel)
  renderRoleChips();
  renderChannelPreview();
}
function removeRole(role,e){
  if(e) e.stopPropagation();
  chRoles=chRoles.filter(r=>r!==role);
  document.querySelectorAll('#roleMenu .role-item').forEach(o=>{ if(o.dataset.role===role) o.classList.remove('sel'); });
  renderRoleChips();renderChannelPreview();
}
function renderRoleChips(){
  const wrap=document.getElementById('roleChips');
  wrap.innerHTML=chRoles.map(r=>{
    const it=document.querySelector('#roleMenu .role-item[data-role="'+r+'"]');
    const name = it ? (it.dataset.roleName||it.textContent.trim()) : r;
    return `<span class="role-chip">${escapeHtml(name)}<span class="x" onclick="removeRole('${r}',event)"><span class="fa fa-close"></span></span></span>`;
  }).join('');
  document.getElementById('rolePh').style.display=chRoles.length?'none':'';
}
function renderChannelPreview(){
  const name=document.getElementById('chName').value.trim();
  const slug=slugify(name);
  document.getElementById('chErr').classList.remove('show');
  document.getElementById('chPvName').textContent=name?('#'+slug):'#kênh-chưa-đặt-tên';
  const desc=document.getElementById('chDesc').value.trim();
  document.getElementById('chPvMeta').textContent=desc||'Công khai theo nhóm quyền';
  if(chRoles.length){
    document.getElementById('chPvRoles').innerHTML=chRoles.map(r=>{
      const it=document.querySelector('#roleMenu .role-item[data-role="'+r+'"]');
      return '<div class="pv-row">• '+escapeHtml(it?(it.dataset.roleName||''):'')+'</div>';
    }).join('');
  } else {
    document.getElementById('chPvRoles').innerHTML='<div class="pv-row" style="color:var(--text-tertiary)">Toàn công ty</div>';
  }
  const ok=!!name;
  const btn=document.getElementById('chCreate');
  btn.disabled=!ok; btn.style.opacity=ok?1:.5;
}
function createChannel(){
  const name=document.getElementById('chName').value.trim();
  if(!name){document.getElementById('chErr').classList.add('show');document.getElementById('chName').focus();return;}
  const desc=document.getElementById('chDesc').value.trim();
  // Channel: giữ bước nhập tên+quyền, mở phòng ảo — chỉ INSERT (msCreateChannel)
  // khi gửi tin đầu. Snapshot roleIds vì chRoles dùng chung sẽ bị reset.
  openVirtualRoom({kind:'channel', name: name, desc: desc, roleIds: chRoles.slice(), title: '#'+slugify(name)});
}

/* ===== Tạo Nhóm con — nguồn = hội thoại đang mở ===== */
let sgSelected=[];
function openCreateSubgroup(){
  if(!document.getElementById('moreMenu').classList.contains('hidden')) toggleMoreMenu();
  if(!activeConvId){ alert('Mở 1 hội thoại trước khi tạo nhóm con'); return; }
  const srcName = (document.getElementById('hName').textContent||'Hội thoại').trim();
  document.getElementById('sgSrcChip').innerHTML = escapeHtml(srcName);
  document.getElementById('sgPvSrcRow').textContent = srcName;
  document.getElementById('sgName').value='';
  document.getElementById('sgErr').classList.remove('show');
  sgSelected=[];
  apexCall('msInfoHtml', {x01: activeConvId}, function(html){
    const tmp=document.createElement('div'); tmp.innerHTML=html;
    sgSelected = [...tmp.querySelectorAll('.mem-row')].map((row,i)=>i); // placeholder, xem ghi chú dưới
    renderSgMembers(); renderSubgroupPreview();
  });
  ['composePicker','composeGroup','composeChannel'].forEach(id=>document.getElementById(id).classList.add('hidden'));
  document.getElementById('composeSubgroup').classList.remove('hidden');
  setTimeout(()=>document.getElementById('sgName').focus(),50);
}
function renderSgMembers(){
  // Thành viên nhóm con chọn từ msContactsHtml (toàn hệ thống) — đơn giản hóa so với "mặc định
  // tích sẵn thành viên cha" trong bản demo tĩnh, vì cần JOIN thêm callback riêng để liệt kê
  // đúng participant của cha kèm role. Việc đó để lại như TODO khi cần khớp 100% bản thiết kế.
  apexCall('msContactsHtml', {x01:''}, function(html){
    const box=document.getElementById('sgMembers');
    box.innerHTML = html.replace(/class="person"/g,'class="mc-item"').replace(/onclick="togglePerson\((\d+)\)"/g,'onclick="sgToggleMember($1)"');
    updateMcHead();
  });
}
function updateMcHead(){
  const total=document.querySelectorAll('#sgMembers .mc-item').length;
  document.getElementById('sgCount').textContent=`(đã chọn ${sgSelected.length}/${total})`;
  document.getElementById('sgAll').textContent=sgSelected.length===total?'Bỏ chọn tất cả':'Chọn tất cả';
}
function sgToggleMember(id){
  id=Number(id);
  sgSelected.includes(id)?sgSelected=sgSelected.filter(x=>x!==id):sgSelected.push(id);
  const row=document.querySelector('#sgMembers .mc-item[data-id="'+id+'"]');
  if(row) row.classList.toggle('sel',sgSelected.includes(id));
  updateMcHead();
  renderSubgroupPreview();
}
function sgToggleAll(){
  const ids=[...document.querySelectorAll('#sgMembers .mc-item')].map(e=>Number(e.dataset.id));
  sgSelected = sgSelected.length===ids.length ? [] : ids;
  document.querySelectorAll('#sgMembers .mc-item').forEach(e=>e.classList.toggle('sel',sgSelected.includes(Number(e.dataset.id))));
  updateMcHead();
  renderSubgroupPreview();
}
function renderSubgroupPreview(){
  const name=document.getElementById('sgName').value.trim();
  document.getElementById('sgErr').classList.remove('show');
  document.getElementById('sgPvAv').textContent=(name||'N')[0].toUpperCase();
  document.getElementById('sgPvName').textContent=name||'Nhóm con chưa đặt tên';
  document.getElementById('sgPvMeta').innerHTML=`<span class="fa fa-lock"></span> Riêng tư · ${sgSelected.length+1} thành viên`;
  const ok=!!name && sgSelected.length>0;
  const btn=document.getElementById('sgCreate'); btn.disabled=!ok; btn.style.opacity=ok?1:.5;
}
function createSubgroup(){
  const name=document.getElementById('sgName').value.trim();
  if(!name){document.getElementById('sgErr').classList.add('show');document.getElementById('sgName').focus();return;}
  if(sgSelected.length===0){alert('Chọn ít nhất 1 thành viên');return;}
  apexCallJson('msCreateSubgroup', {x01:name, x02:activeConvId, x03:sgSelected.join(',')}, function(res){
    closeCompose(); loadConvList(); openConversation2(res.conv_id);
  });
}
function hideCrumb(){document.getElementById('crumb').classList.add('hidden');}
function openCrumbParent(){
  const item=[...document.querySelectorAll('#navScroll [data-name]')]
    .find(e=>e.querySelector('.name') && e.querySelector('.name').textContent.trim()===document.getElementById('crumbText').textContent.trim());
  if(item) openConversation2(item.dataset.conv);
}

/* ===== Tìm trong hội thoại (client-side, trên thread đã tải) ===== */
let csHits=[], csIdx=-1;
function escRe(s){return s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');}
function clearConvHighlight(){
  document.querySelectorAll('#messages mark.search-hit').forEach(m=>{
    const t=document.createTextNode(m.textContent); m.replaceWith(t);
  });
  document.querySelectorAll('#messages .text').forEach(el=>el.normalize());
  csHits=[]; csIdx=-1;
}
function openConvSearch(){
  document.getElementById('convSearch').classList.remove('hidden');
  setTimeout(()=>document.getElementById('convSearchInput').focus(),40);
}
function closeConvSearch(){
  document.getElementById('convSearch').classList.add('hidden');
  document.getElementById('convSearchInput').value='';
  document.getElementById('convSearchCount').textContent='';
  clearConvHighlight();
}
function runConvSearch(){
  clearConvHighlight();
  const q=document.getElementById('convSearchInput').value.trim();
  const cnt=document.getElementById('convSearchCount');
  const prev=document.getElementById('csPrev'),next=document.getElementById('csNext');
  if(!q){cnt.textContent='';prev.disabled=next.disabled=true;return;}
  const ql=q.toLowerCase();
  document.querySelectorAll('#messages .text').forEach(el=>{
    if(!el.textContent.toLowerCase().includes(ql))return;
    el.innerHTML=el.innerHTML.replace(new RegExp('('+escRe(q)+')(?![^<]*>)','gi'),'<mark class="search-hit">$1</mark>');
  });
  csHits=[...document.querySelectorAll('#messages mark.search-hit')];
  if(!csHits.length){cnt.textContent='Không có kết quả';prev.disabled=next.disabled=true;return;}
  prev.disabled=next.disabled=false;
  csIdx=0; markCurrent();
}
function markCurrent(){
  csHits.forEach((m,i)=>m.classList.toggle('current',i===csIdx));
  const cur=csHits[csIdx];
  if(cur){cur.scrollIntoView({block:'center',behavior:'smooth'});}
  document.getElementById('convSearchCount').textContent=`${csIdx+1}/${csHits.length}`;
}
function convSearchStep(d){
  if(!csHits.length)return;
  csIdx=(csIdx+d+csHits.length)%csHits.length; markCurrent();
}
function convSearchKey(e){
  if(e.key==='Enter'){e.preventDefault();convSearchStep(e.shiftKey?-1:1);}
  else if(e.key==='Escape'){e.preventDefault();closeConvSearch();}
}

/* ===== Menu Thêm (Ghim / Xóa) — msConvAction ===== */
function toggleMoreMenu(e){
  if(e) e.stopPropagation();
  const m=document.getElementById('moreMenu');
  document.getElementById('mmOpenDoc').style.display=activeConvIsDoc?'':'none';
  document.getElementById('mmOpenDocSep').style.display=activeConvIsDoc?'':'none';
  document.getElementById('mmRename').style.display=(activeConvKind!=='canhan')?'':'none';
  const open=m.classList.toggle('hidden')===false;
  document.getElementById('moreBtn').setAttribute('aria-expanded',open?'true':'false');
}
function renameConvFromMenu(){
  toggleMoreMenu();
  const current = (document.getElementById('hName').textContent||'').trim();
  const name = prompt('Tên mới:', current);
  if(!name || !name.trim()) return;
  const trimmed = name.trim();
  if(draftConv && !activeConvId){
    // Phòng ảo chưa ghi DB — chỉ cập nhật state cục bộ, materialize sẽ dùng tên này.
    draftConv.name = trimmed; draftConv.title = trimmed;
    document.getElementById('hName').innerHTML = escapeHtml(trimmed)+' <span class="new-chip">Mới</span>';
    return;
  }
  if(!activeConvId) return;
  apexCallJson('msRenameConv', {x01: activeConvId, x02: trimmed}, function(){
    document.getElementById('hName').textContent = trimmed;
    loadConvList();
  }, function(){ alert('Đổi tên thất bại, thử lại.'); });
}
function pinConv(){
  toggleMoreMenu();
  if(!activeConvId) return;
  apexCallJson('msConvAction', {x01: activeConvId, x02:'pin'}, loadConvList);
}
function deleteConv(){
  toggleMoreMenu();
  if(!activeConvId) return;
  if(!confirm('Xóa cuộc hội thoại này? Hành động không thể hoàn tác.')) return;
  apexCallJson('msConvAction', {x01: activeConvId, x02:'delete'}, function(){
    activeConvId=null;
    document.getElementById('messages').innerHTML='';
    document.getElementById('hName').textContent='Chọn 1 hội thoại';
    loadConvList();
  });
}
document.addEventListener('click',e=>{
  const m=document.getElementById('moreMenu');
  if(!m.classList.contains('hidden') && !m.contains(e.target) && e.target.id!=='moreBtn') toggleMoreMenu();
});

/* ===== Lightbox ===== */
function openLightbox(src){
  document.getElementById('lightboxImg').src=src;
  document.getElementById('lightbox').classList.remove('hidden');
}
function closeLightbox(e,force){
  if(force || e.target.id==='lightbox') document.getElementById('lightbox').classList.add('hidden');
}
function fileIcon(ext){return ({xlsx:'fa-bar-chart',xls:'fa-bar-chart',pdf:'fa-file-pdf-o',doc:'fa-file-word-o',docx:'fa-file-word-o',zip:'fa-file-zip-o'})[ext]||'fa-paperclip';}
function pickAttachment(){document.getElementById('attachInput').click();}

/* ===== Đính kèm file/ảnh — upload TRỰC TIẾP qua callback APEX msUploadFile
   (base64 qua apex.server.process), KHÔNG qua Node. Nguyên do giống hệt
   messenger/ (xem messenger/CLAUDE.md mục "Luồng gửi file thật"):
   pkg_upload_file nằm trong DB của APEX, gọi từ Node sẽ PLS-00201; và
   item File Browse rỗng bytes trong AJAX nên client phải tự đọc/mã hóa. */
const FILE_B64_CHUNK = 30000; // <= 32767 (giới hạn phần tử g_f01)
function onAttachPicked(input){
  const files=[...input.files];
  if(!files.length || !activeConvId){ input.value=''; return; }
  const convId = activeConvId;
  (function sendNext(i){
    if(i>=files.length){ input.value=''; return; }
    uploadOneFile(convId, files[i], function(){ sendNext(i+1); });
  })(0);
}
function uploadOneFile(convId, file, onDone){
  const reader = new FileReader();
  reader.onload = function(){
    const dataUrl = reader.result || '';
    const comma = dataUrl.indexOf(',');
    const b64 = comma>=0 ? dataUrl.substring(comma+1) : '';
    if(!b64){ console.error('[chat-erp] Không đọc được file:', file.name); if(onDone) onDone(); return; }
    const chunks=[];
    for(let p=0;p<b64.length;p+=FILE_B64_CHUNK) chunks.push(b64.substring(p,p+FILE_B64_CHUNK));
    apex.server.process('msUploadFile', {f01: chunks, x01: convId, x02: file.name}, {
      dataType: 'json',
      success: function(r){
        if(!r || r.error){ console.error('[chat-erp] Upload file thất bại:', r && r.error); }
        else {
          if(convId===activeConvId){
            apexCall('msMsgThreadHtml', {x01: activeConvId}, function(html){
              document.getElementById('messages').innerHTML = html; initMsgActions(); scrollMessages();
            });
          }
          loadConvList();
          broadcastMessage(r);
        }
        if(onDone) onDone();
      },
      error: function(xhr){ console.error('[chat-erp] msUploadFile lỗi', xhr); if(onDone) onDone(); }
    });
  };
  reader.onerror = function(){ console.error('[chat-erp] Lỗi đọc file:', file.name); if(onDone) onDone(); };
  reader.readAsDataURL(file);
}

/* ===== Emoji popover ===== */
const EMOJIS=['👍','🙏','✅','🔥','😊','😂','🎉','❤️','👏','🙌','💪','✨','📌','📎','💯','🤝','👀','🚀','⚡','✔️','❌','⭐','💡','📈','😅','😉','🤔','😍','🥳','😎','🙆','📝'];
function toggleEmoji(e){
  if(e) e.stopPropagation();
  const pop=document.getElementById('emojiPop');
  if(!pop.dataset.built){pop.innerHTML=EMOJIS.map(em=>`<button type="button" onclick="insertEmoji('${em}')">${em}</button>`).join('');pop.dataset.built='1';}
  const open=pop.classList.toggle('hidden')===false;
  document.getElementById('emojiBtn').setAttribute('aria-expanded',open?'true':'false');
}
function insertEmoji(em){
  const input=document.querySelector('.pane .composer .input');
  input.focus();
  const sel=window.getSelection();
  if(sel && sel.rangeCount && input.contains(sel.anchorNode)){
    const r=sel.getRangeAt(0); r.deleteContents();
    const node=document.createTextNode(em); r.insertNode(node);
    r.setStartAfter(node); r.collapse(true); sel.removeAllRanges(); sel.addRange(r);
  } else { input.innerText+=em; }
}
document.addEventListener('click',e=>{
  const pop=document.getElementById('emojiPop');
  if(!pop.classList.contains('hidden') && !pop.contains(e.target) && e.target.id!=='emojiBtn') toggleEmoji();
});

function toggleTheme(){
  const h=document.documentElement;
  h.dataset.theme = h.dataset.theme==='dark'?'light':'dark';
}
function setElement(key){
  document.documentElement.dataset.element = key;
  document.querySelectorAll('.elem-btn').forEach(b=>b.classList.toggle('active', b.dataset.el===key));
}

/* ===== Tìm toàn cục (⌘K) — msGlobalSearchHtml ===== */
let _gsTimer=null;
function openGlobalSearch(){
  const o=document.getElementById('gsOverlay'); o.classList.remove('hidden');
  document.getElementById('gsInput').value=''; document.getElementById('gsBody').innerHTML='';
  setTimeout(()=>document.getElementById('gsInput').focus(),40);
}
function closeGlobalSearch(){
  document.getElementById('gsOverlay').classList.add('hidden');
  const ms=document.querySelector('.m-search'); if(ms) ms.focus();
}
function gsBackdrop(e){ if(e.target.id==='gsOverlay') closeGlobalSearch(); }
function renderGlobalResults(q){
  clearTimeout(_gsTimer);
  q=(q||'').trim();
  if(!q){ document.getElementById('gsBody').innerHTML=''; return; }
  _gsTimer=setTimeout(function(){
    apexCall('msGlobalSearchHtml', {x01:q}, function(html){
      document.getElementById('gsBody').innerHTML = html || '<div class="gs-empty">Không tìm thấy kết quả</div>';
    });
  }, 200);
}
function gsPick(id){ closeGlobalSearch(); loadConvList(); setTimeout(()=>openConversation2(id), 200); }
function gsPickPerson(ausId, name, dmConv){
  closeGlobalSearch();
  // Nhất quán với pickerSubmit: đã có DM → load hội thoại cũ; chưa có → phòng ảo.
  if(dmConv && Number(dmConv)>0){ openConversation2(Number(dmConv)); }
  else { openVirtualRoom({kind:'dm', partnerId: ausId, title: name || 'Hội thoại'}); }
}
function gsKey(e){
  if(e.key==='Escape'){e.preventDefault();closeGlobalSearch();return;}
  if(e.key==='Enter'){const first=document.querySelector('#gsBody .gs-item'); if(first) first.click();}
}

document.addEventListener('keydown',e=>{
  if((e.metaKey||e.ctrlKey)&&(e.key==='k'||e.key==='K')){
    e.preventDefault();
    const o=document.getElementById('gsOverlay');
    o.classList.contains('hidden')?openGlobalSearch():closeGlobalSearch();
    return;
  }
  if((e.metaKey||e.ctrlKey)&&(e.key==='f'||e.key==='F')){
    e.preventDefault(); openConvSearch(); return;
  }
  if((e.metaKey||e.ctrlKey)&&(e.key==='n'||e.key==='N')){
    e.preventDefault(); startNewConversation(); return;
  }
  if(e.key==='Escape'){
    if(_mentionOpen){closeMentionPop();return;}
    if(!document.getElementById('reactBar').classList.contains('hidden')){closeReactBar();return;}
    if(!document.getElementById('gsOverlay').classList.contains('hidden')){closeGlobalSearch();return;}
    const cp=document.getElementById('composePicker'),cg=document.getElementById('composeGroup'),cc=document.getElementById('composeChannel'),csg=document.getElementById('composeSubgroup');
    if(!document.getElementById('lightbox').classList.contains('hidden')){closeLightbox(null,true);return;}
    if(!document.getElementById('emojiPop').classList.contains('hidden')){toggleEmoji();return;}
    if(!document.getElementById('moreMenu').classList.contains('hidden')){toggleMoreMenu();return;}
    if(!document.getElementById('convSearch').classList.contains('hidden')){closeConvSearch();return;}
    if(!document.getElementById('typeMenu').classList.contains('hidden')){toggleTypeMenu();return;}
    if(!document.getElementById('roleMenu').classList.contains('hidden')){toggleRoleMenu();return;}
    if(!cp.classList.contains('hidden')||!cg.classList.contains('hidden')||!cc.classList.contains('hidden')||!csg.classList.contains('hidden')){closeCompose();return;}
    if(!document.getElementById('newConvBar').classList.contains('hidden')){cancelNewConv();return;}
    if(!document.getElementById('toast').classList.contains('hidden')){hideToast();return;}
    if(layout.classList.contains('panel-open'))closePanel();
  }
});
