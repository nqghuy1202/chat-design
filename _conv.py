import re

with open(r'C:\chat-design\index.html', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove Tailwind CDN
content = content.replace('  <script src="https://cdn.tailwindcss.com"></script>\n', '')

# 2. Fix body tag
content = content.replace(
    '<body class="min-h-screen flex items-center justify-center" style="background: linear-gradient(135deg, #CBD5E1, #94A3B8);">',
    '<body style="min-height:100vh;display:flex;align-items:center;justify-content:center;background: linear-gradient(135deg, #CBD5E1, #94A3B8);">'
)

# 3. Background hint div
content = content.replace(
    '  <div class="fixed inset-0 flex items-center justify-center select-none opacity-30 pointer-events-none">\n    <div class="text-white text-xl font-semibold tracking-tight">Nexus Studio</div>\n  </div>',
    '  <div style="position:fixed;top:0;left:0;right:0;bottom:0;display:flex;align-items:center;justify-content:center;user-select:none;opacity:0.3;pointer-events:none;">\n    <div style="color:white;font-size:20px;font-weight:600;letter-spacing:-0.025em;">Nexus Studio</div>\n  </div>'
)

# 4. Reopen button
content = content.replace(
    '  <button id="reopen-btn" onclick="openModal()" style="display:none;"\n    class="fixed bottom-8 right-8 z-40 flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-medium px-4 py-2.5 rounded-xl shadow-lg transition-colors">',
    '  <button id="reopen-btn" onclick="openModal()"\n    style="display:none;position:fixed;bottom:32px;right:32px;z-index:40;align-items:center;gap:8px;background:#2563EB;color:white;font-size:14px;font-weight:500;padding:10px 16px;border-radius:12px;box-shadow:0 10px 15px -3px rgba(0,0,0,0.1),0 4px 6px -2px rgba(0,0,0,0.05);border:none;cursor:pointer;">'
)

# 5. Backdrop
content = content.replace(
    '  <div id="backdrop" class="fixed inset-0 z-40" style="background: rgba(15,23,42,0.4); backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px);">',
    '  <div id="backdrop" style="position:fixed;top:0;left:0;right:0;bottom:0;z-index:40;background: rgba(15,23,42,0.4); backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px);">'
)

# 6. Chat modal
content = content.replace(
    '  <div id="chat-modal" class="fixed z-50 modal-animate"\n    style="inset: 16px; max-width: 1360px; max-height: 860px; margin: auto;">',
    '  <div id="chat-modal" class="modal-animate"\n    style="position:fixed;z-index:50;top:16px;left:16px;right:16px;bottom:16px;max-width: 1360px; max-height: 860px; margin: auto;">'
)

# 7. Inner modal container
content = content.replace(
    '    <div class="w-full h-full bg-white rounded-2xl shadow-2xl flex overflow-hidden"\n      style="border: 1px solid rgba(226,232,240,0.8); position:relative;">',
    '    <div style="width:100%;height:100%;background:white;border-radius:16px;box-shadow:0 25px 50px -12px rgba(0,0,0,0.25);display:flex;overflow:hidden;border: 1px solid rgba(226,232,240,0.8); position:relative;">'
)

# 8. Left panel
content = content.replace(
    '      <div class="flex flex-col flex-shrink-0" style="width: 268px; border-right: 1px solid #E2E8F0; background: #F8FAFC; overflow: hidden;">',
    '      <div style="display:flex;flex-direction:column;flex-shrink:0;width: 268px; border-right: 1px solid #E2E8F0; background: #F8FAFC; overflow: hidden;">'
)

# 9. App header row
content = content.replace(
    '        <div class="px-4 pt-4 pb-3 flex items-center justify-between" style="border-bottom: 1px solid #F1F5F9;">',
    '        <div style="padding:16px 16px 12px;display:flex;align-items:center;justify-content:space-between;border-bottom: 1px solid #F1F5F9;">'
)

# 10. Logo area
content = content.replace(
    '          <div class="flex items-center gap-2.5">\n            <div class="app-logo-icon w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0"\n              style="background: linear-gradient(135deg, #2563EB, #1D4ED8);">',
    '          <div style="display:flex;align-items:center;gap:10px;">\n            <div class="app-logo-icon"\n              style="width:28px;height:28px;border-radius:8px;display:flex;align-items:center;justify-content:center;flex-shrink:0;background: linear-gradient(135deg, #2563EB, #1D4ED8);">'
)
content = content.replace(
    '            <span class="font-semibold text-slate-900" style="font-size: 14px;">Messages</span>',
    '            <span style="font-weight:600;color:#0F172A;font-size: 14px;">Messages</span>'
)

# 12. LP search row
content = content.replace(
    '        <div class="px-3 pt-3 pb-2">\n          <div class="search-wrap" onclick="openGlobalSearch()" style="cursor:pointer;">',
    '        <div style="padding:12px 12px 8px;">\n          <div class="search-wrap" onclick="openGlobalSearch()" style="cursor:pointer;">'
)

# 13. Filter tabs row
content = content.replace(
    '        <div class="flex items-center gap-1 px-3 pb-2">',
    '        <div style="display:flex;align-items:center;gap:4px;padding:0 12px 8px;">'
)

# 14. Conv list
content = content.replace(
    '        <div id="lp-conv-list" class="flex-1 overflow-y-auto thin-scroll px-2 pb-2 space-y-0.5"></div>',
    '        <div id="lp-conv-list" class="thin-scroll" style="flex:1;overflow-y:auto;padding:0 8px 8px;"></div>'
)

# 15. User profile row
content = content.replace(
    '        <div class="px-3 py-3 flex items-center gap-2.5" style="border-top: 1px solid #E2E8F0; position:relative;">',
    '        <div style="padding:12px;display:flex;align-items:center;gap:10px;border-top: 1px solid #E2E8F0; position:relative;">'
)
content = content.replace(
    '          <div class="relative flex-shrink-0 cursor-pointer" onclick="toggleStatusPicker(event)" title="Doi trang thai">',
    '          <div style="position:relative;flex-shrink:0;cursor:pointer;" onclick="toggleStatusPicker(event)" title="Doi trang thai">'
)
content = content.replace(
    '            <div id="user-avatar" class="w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-semibold" style="background: #2563EB;">MH</div>',
    '            <div id="user-avatar" style="width:32px;height:32px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:white;font-size:12px;font-weight:600;background: #2563EB;">MH</div>'
)
content = content.replace(
    '            <div id="user-status-dot" class="absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full status-online" style="border: 2px solid white;"></div>',
    '            <div id="user-status-dot" class="status-online" style="position:absolute;bottom:-2px;right:-2px;width:10px;height:10px;border-radius:50%;border: 2px solid white;"></div>'
)
content = content.replace(
    '          <div class="flex-1 min-w-0 cursor-pointer" onclick="toggleStatusPicker(event)">',
    '          <div style="flex:1;min-width:0;cursor:pointer;" onclick="toggleStatusPicker(event)">'
)
content = content.replace(
    '            <div class="text-slate-800 font-semibold truncate" style="font-size: 13px;">Minh Hoang</div>',
    '            <div style="color:#1E293B;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size: 13px;">Minh Hoang</div>'
)
content = content.replace(
    '            <div id="user-status-label" class="text-slate-400" style="font-size: 10.5px;">Dang hoat dong</div>',
    '            <div id="user-status-label" style="color:#94A3B8;font-size: 10.5px;">Dang hoat dong</div>'
)

# 16. S2 Header
content = content.replace(
    '          <div class="flex items-center gap-2 px-3 pt-3.5 pb-3" style="border-bottom: 1px solid #F1F5F9; flex-shrink: 0;">\n            <button onclick="lpBack()" class="tb-btn flex-shrink-0" style="width:30px;height:30px;" title="Back">',
    '          <div style="display:flex;align-items:center;gap:8px;padding:14px 12px 12px;border-bottom: 1px solid #F1F5F9; flex-shrink: 0;">\n            <button onclick="lpBack()" class="tb-btn flex-shrink-0" style="width:30px;height:30px;" title="Back">'
)
content = content.replace(
    '          <div class="px-3 pt-3 pb-2" style="flex-shrink: 0;">\n            <div class="search-wrap">\n              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#94A3B8" stroke-width="2.5" stroke-linecap="round">\n                <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>\n              </svg>\n              <input type="text" id="lp-s2-search" placeholder="Search by name..." oninput="lpSearchContacts(this.value)" autocomplete="off">\n            </div>\n          </div>',
    '          <div style="padding:12px 12px 8px;flex-shrink: 0;">\n            <div class="search-wrap">\n              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#94A3B8" stroke-width="2.5" stroke-linecap="round">\n                <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>\n              </svg>\n              <input type="text" id="lp-s2-search" placeholder="Search by name..." oninput="lpSearchContacts(this.value)" autocomplete="off">\n            </div>\n          </div>'
)
content = content.replace(
    '          <div id="lp-online-strip" class="px-4 pb-2.5" style="flex-shrink: 0;">',
    '          <div id="lp-online-strip" style="padding:0 16px 10px;flex-shrink: 0;">'
)
content = content.replace(
    '          <div id="lp-s2-list" class="flex-1 overflow-y-auto thin-scroll px-2 pb-2"></div>',
    '          <div id="lp-s2-list" class="thin-scroll" style="flex:1;overflow-y:auto;padding:0 8px 8px;"></div>'
)
content = content.replace(
    '          <div class="px-3 py-3" style="border-top: 1px solid #E2E8F0; flex-shrink: 0;">',
    '          <div style="padding:12px;border-top: 1px solid #E2E8F0; flex-shrink: 0;">'
)

# S3
content = content.replace(
    '          <div class="flex items-center gap-2 px-3 pt-3.5 pb-3" style="border-bottom: 1px solid #F1F5F9; flex-shrink: 0;">\n            <button onclick="lpGroupBack()" class="tb-btn flex-shrink-0" style="width:30px;height:30px;" title="Back">',
    '          <div style="display:flex;align-items:center;gap:8px;padding:14px 12px 12px;border-bottom: 1px solid #F1F5F9; flex-shrink: 0;">\n            <button onclick="lpGroupBack()" class="tb-btn flex-shrink-0" style="width:30px;height:30px;" title="Back">'
)
content = content.replace(
    '          <div class="px-3 pt-2.5 pb-2" style="flex-shrink: 0;">\n            <div class="search-wrap">',
    '          <div style="padding:10px 12px 8px;flex-shrink: 0;">\n            <div class="search-wrap">'
)
content = content.replace(
    '          <div id="lp-s3-list" class="flex-1 overflow-y-auto thin-scroll px-2 pb-2"></div>',
    '          <div id="lp-s3-list" class="thin-scroll" style="flex:1;overflow-y:auto;padding:0 8px 8px;"></div>'
)

# S4 header
content = content.replace(
    '          <div class="flex items-center gap-2 px-3 pt-3.5 pb-3" style="border-bottom: 1px solid #F1F5F9; flex-shrink: 0; position: sticky; top: 0; background: #F8FAFC; z-index: 1;">',
    '          <div style="display:flex;align-items:center;gap:8px;padding:14px 12px 12px;border-bottom: 1px solid #F1F5F9; flex-shrink: 0; position: sticky; top: 0; background: #F8FAFC; z-index: 1;">'
)

# Center panel
content = content.replace(
    '      <div id="center-panel" class="flex-1 flex flex-col min-w-0 bg-white" style="position:relative;">',
    '      <div id="center-panel" style="flex:1;display:flex;flex-direction:column;min-width:0;background:white;position:relative;">'
)

# Chat header
content = content.replace(
    '        <div class="flex-shrink-0 px-5 flex items-center justify-between" style="height: 64px; border-bottom: 1px solid #E2E8F0;">',
    '        <div style="flex-shrink:0;padding:0 20px;display:flex;align-items:center;justify-content:space-between;height: 64px; border-bottom: 1px solid #E2E8F0;">'
)
content = content.replace(
    '          <div class="flex items-center gap-3">\n            <div class="relative" id="ch-av-wrap">',
    '          <div style="display:flex;align-items:center;gap:12px;">\n            <div style="position:relative;" id="ch-av-wrap">'
)
content = content.replace(
    '              <div id="ch-avatar" class="w-9 h-9 rounded-full flex items-center justify-center text-white text-sm font-semibold"\n                style="background: #059669;">LT</div>',
    '              <div id="ch-avatar" style="width:36px;height:36px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:white;font-size:14px;font-weight:600;background: #059669;">LT</div>'
)
content = content.replace(
    '              <div id="ch-status-dot" class="absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full status-online" style="border: 2px solid white;"></div>',
    '              <div id="ch-status-dot" class="status-online" style="position:absolute;bottom:-2px;right:-2px;width:10px;height:10px;border-radius:50%;border: 2px solid white;"></div>'
)
content = content.replace(
    '              <div id="ch-name" class="text-slate-900 font-semibold" style="font-size: 14px;">Linh Tran</div>',
    '              <div id="ch-name" style="color:#0F172A;font-weight:600;font-size: 14px;">Linh Tran</div>'
)
content = content.replace(
    '              <div id="ch-sub" class="flex items-center gap-1.5 text-slate-400" style="font-size: 11.5px;">\n                <span class="w-1.5 h-1.5 rounded-full bg-green-400 inline-block"></span>\n                Active now\n              </div>',
    '              <div id="ch-sub" style="display:flex;align-items:center;gap:6px;color:#94A3B8;font-size: 11.5px;">\n                <span style="width:6px;height:6px;border-radius:50%;background:#4ADE80;display:inline-block;"></span>\n                Active now\n              </div>'
)

# Header right buttons in chat header
content = content.replace(
    '          <div class="flex items-center gap-0.5">\n            <button class="tb-btn" style="width:32px;height:32px;" title="Search">',
    '          <div style="display:flex;align-items:center;gap:2px;">\n            <button class="tb-btn" style="width:32px;height:32px;" title="Search">'
)

# Separator
content = content.replace(
    '            <div class="w-px h-5 bg-slate-200 mx-1.5"></div>',
    '            <div style="width:1px;height:20px;background:#E2E8F0;margin-left:6px;margin-right:6px;"></div>'
)

# Close button
content = content.replace(
    '            <button onclick="closeModal()" title="Close"\n              class="flex items-center justify-center rounded-lg text-slate-400 hover:text-slate-700 hover:bg-slate-100 transition-colors"\n              style="width:32px;height:32px;">',
    '            <button onclick="closeModal()" title="Close"\n              style="width:32px;height:32px;display:flex;align-items:center;justify-content:center;border-radius:8px;color:#94A3B8;border:none;cursor:pointer;background:transparent;">'
)

# Messages wrapper
content = content.replace(
    '        <div class="flex-1 relative" style="overflow:hidden;">',
    '        <div style="flex:1;position:relative;overflow:hidden;">'
)

# Messages div
content = content.replace(
    '          <div id="messages" class="absolute inset-0 overflow-y-auto thin-scroll px-5 py-4" style="scroll-behavior:smooth;">',
    '          <div id="messages" class="thin-scroll" style="position:absolute;top:0;left:0;right:0;bottom:0;overflow-y:auto;padding:16px 20px;scroll-behavior:smooth;">'
)

# Input area wrapper
content = content.replace(
    '        <div class="flex-shrink-0 px-4 py-3" style="border-top: 1px solid #F1F5F9;">',
    '        <div style="flex-shrink:0;padding:12px 16px;border-top: 1px solid #F1F5F9;">'
)

# Formatting toolbar
content = content.replace(
    '            <div class="flex items-center gap-0.5 px-3 pt-2.5 pb-2" style="border-bottom: 1px solid #F8FAFC;">',
    '            <div style="display:flex;align-items:center;gap:2px;padding:10px 12px 8px;border-bottom: 1px solid #F8FAFC;">'
)
content = content.replace(
    '              <div class="w-px h-4 bg-slate-200 mx-1"></div>',
    '              <div style="width:1px;height:16px;background:#E2E8F0;margin-left:4px;margin-right:4px;"></div>'
)
content = content.replace(
    '            <div class="flex items-center justify-between px-3 pb-2.5 pt-1">',
    '            <div style="display:flex;align-items:center;justify-content:space-between;padding:4px 12px 10px;">'
)
content = content.replace(
    '              <div class="flex items-center gap-0.5">',
    '              <div style="display:flex;align-items:center;gap:2px;">'
)
content = content.replace(
    '          <div class="flex items-center gap-1 mt-1.5 px-1" style="font-size:11px;color:#CBD5E1;">',
    '          <div style="display:flex;align-items:center;gap:4px;margin-top:6px;padding:0 4px;font-size:11px;color:#CBD5E1;">'
)

# Right panel
content = content.replace(
    '      <div id="right-panel" class="right-panel flex flex-col" style="border-left: 1px solid #E2E8F0; background: #FAFAFA; overflow-y: auto;" class="thin-scroll">',
    '      <div id="right-panel" class="right-panel thin-scroll" style="display:flex;flex-direction:column;border-left: 1px solid #E2E8F0; background: #FAFAFA; overflow-y: auto;">'
)

# File card download button
content = content.replace(
    '                  <button class="text-blue-600 hover:text-blue-700 font-medium flex-shrink-0 transition-colors" style="font-size: 12px;">Download</button>',
    '                  <button style="color:#2563EB;font-weight:500;flex-shrink:0;font-size: 12px;border:none;background:transparent;cursor:pointer;">Download</button>'
)
content = content.replace(
    '                  <div class="flex-1 min-w-0">\n                    <div class="text-slate-800 font-medium truncate" style="font-size: 13px;">design-tokens-v2.pdf</div>\n                    <div class="text-slate-400" style="font-size: 11px;">2.4 MB · PDF Document</div>\n                  </div>',
    '                  <div style="flex:1;min-width:0;">\n                    <div style="color:#1E293B;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size: 13px;">design-tokens-v2.pdf</div>\n                    <div style="color:#94A3B8;font-size: 11px;">2.4 MB · PDF Document</div>\n                  </div>'
)

# ===== GLOBAL REPLACEMENTS =====
# flex gap-3
content = content.replace('class="flex gap-3"', 'style="display:flex;gap:12px;"')

# Avatar patterns
content = re.sub(
    r'class="w-9 h-9 rounded-full flex items-center justify-center text-white text-xs font-semibold flex-shrink-0 mt-0\.5"',
    'style="width:36px;height:36px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:white;font-size:12px;font-weight:600;flex-shrink:0;margin-top:2px;"',
    content
)
content = re.sub(
    r'class="w-9 h-9 rounded-full flex items-center justify-center text-white text-xs font-semibold flex-shrink-0"',
    'style="width:36px;height:36px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:white;font-size:12px;font-weight:600;flex-shrink:0;"',
    content
)
content = content.replace('class="flex-1 min-w-0"', 'style="flex:1;min-width:0;"')
content = content.replace('class="flex items-baseline gap-2 mb-1"', 'style="display:flex;align-items:baseline;gap:8px;margin-bottom:4px;"')
content = content.replace('class="font-semibold text-slate-900"', 'style="font-weight:600;color:#0F172A;"')
content = content.replace('class="text-slate-400"', 'style="color:#94A3B8;"')
content = content.replace('class="text-slate-700 leading-relaxed flex-1"', 'style="color:#334155;line-height:1.625;flex:1;"')
content = content.replace('class="text-slate-700 leading-relaxed"', 'style="color:#334155;line-height:1.625;"')
content = re.sub(r'class="flex items-center gap-1\.5 mt-2"', 'style="display:flex;align-items:center;gap:6px;margin-top:8px;"', content)

# typing indicator in JS strings
content = content.replace(
    'class="flex items-center gap-3 px-2 py-2 -mx-2"',
    'style="display:flex;align-items:center;gap:12px;padding:8px;margin-left:-8px;margin-right:-8px;"'
)
content = content.replace('class="flex items-center gap-2.5"', 'style="display:flex;align-items:center;gap:10px;"')
content = re.sub(
    r'class="flex items-center gap-1 rounded-xl px-3 py-2\.5"',
    'style="display:flex;align-items:center;gap:4px;border-radius:12px;padding:10px 12px;"',
    content
)
content = content.replace(
    'class="typing-dot w-1.5 h-1.5 rounded-full bg-slate-400"',
    'class="typing-dot" style="width:6px;height:6px;border-radius:50%;background:#94A3B8;"'
)
content = content.replace('class="w-9 flex-shrink-0"', 'style="width:36px;flex-shrink:0;"')
content = re.sub(
    r'class="w-9 h-9 flex items-center justify-center text-white text-xs font-bold flex-shrink-0"',
    'style="width:36px;height:36px;display:flex;align-items:center;justify-content:center;color:white;font-size:12px;font-weight:700;flex-shrink:0;"',
    content
)

# RP sections
content = content.replace('class="flex flex-col items-center pt-8 pb-5 px-4"', 'style="display:flex;flex-direction:column;align-items:center;padding:32px 16px 20px;"')
content = content.replace('class="flex flex-col items-center pt-7 pb-5 px-4"', 'style="display:flex;flex-direction:column;align-items:center;padding:28px 16px 20px;"')
content = re.sub(r'class="w-16 h-16 rounded-2xl flex items-center justify-center text-white text-2xl font-bold mb-3"', 'style="width:64px;height:64px;border-radius:16px;display:flex;align-items:center;justify-content:center;color:white;font-size:24px;font-weight:700;margin-bottom:12px;"', content)
content = re.sub(r'class="w-16 h-16 rounded-full flex items-center justify-center text-white text-xl font-semibold"', 'style="width:64px;height:64px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:white;font-size:20px;font-weight:600;"', content)
content = re.sub(r'class="w-16 h-16 rounded-2xl flex items-center justify-center text-white text-lg font-bold mb-3"', 'style="width:64px;height:64px;border-radius:16px;display:flex;align-items:center;justify-content:center;color:white;font-size:18px;font-weight:700;margin-bottom:12px;"', content)
content = content.replace('class="font-semibold text-slate-900 text-center"', 'style="font-weight:600;color:#0F172A;text-align:center;"')
content = re.sub(r'class="text-slate-400 text-center mt-0\.5 px-4"', 'style="color:#94A3B8;text-align:center;margin-top:2px;padding:0 16px;"', content)
content = re.sub(r'class="text-slate-400 text-center mt-0\.5"', 'style="color:#94A3B8;text-align:center;margin-top:2px;"', content)
content = re.sub(r'class="flex items-center gap-1\.5 mt-1\.5"', 'style="display:flex;align-items:center;gap:6px;margin-top:6px;"', content)
content = re.sub(r'class="flex items-center gap-1\.5 mt-1"', 'style="display:flex;align-items:center;gap:6px;margin-top:4px;"', content)
content = re.sub(r'class="w-1\.5 h-1\.5 rounded-full bg-green-400 inline-block"', 'style="width:6px;height:6px;border-radius:50%;background:#4ADE80;display:inline-block;"', content)
content = re.sub(r'class="w-1\.5 h-1\.5 rounded-full bg-slate-300 inline-block"', 'style="width:6px;height:6px;border-radius:50%;background:#CBD5E1;display:inline-block;"', content)
content = content.replace('class="text-green-600 font-medium"', 'style="color:#16A34A;font-weight:500;"')
content = re.sub(r'class="flex items-center gap-1 mt-5 w-full"', 'style="display:flex;align-items:center;gap:4px;margin-top:20px;width:100%;"', content)
content = re.sub(r'class="flex items-center gap-2 mt-5 w-full"', 'style="display:flex;align-items:center;gap:8px;margin-top:20px;width:100%;"', content)
content = content.replace('class="text-slate-500"', 'style="color:#64748B;"')
content = content.replace('class="relative mb-3"', 'style="position:relative;margin-bottom:12px;"')
content = re.sub(r'class="absolute -bottom-0\.5 -right-0\.5 w-3\.5 h-3\.5 rounded-full status-online"', 'class="status-online" style="position:absolute;bottom:-2px;right:-2px;width:14px;height:14px;border-radius:50%;"', content)
content = re.sub(r'class="absolute -bottom-0\.5 -right-0\.5 w-2\.5 h-2\.5 rounded-full status-online"', 'class="status-online" style="position:absolute;bottom:-2px;right:-2px;width:10px;height:10px;border-radius:50%;"', content)

# JS string updates
content = content.replace(
    '<span class=\\"w-1.5 h-1.5 rounded-full bg-green-400 inline-block\\"></span> Active now',
    '<span style=\\"width:6px;height:6px;border-radius:50%;background:#4ADE80;display:inline-block;\\"></span> Active now'
)
content = content.replace(
    '<span class=\\"w-1.5 h-1.5 rounded-full bg-slate-300 inline-block\\"></span> Offline',
    '<span style=\\"width:6px;height:6px;border-radius:50%;background:#CBD5E1;display:inline-block;\\"></span> Offline'
)
content = content.replace(
    '<span class=\\"w-1.5 h-1.5 rounded-full bg-green-400 inline-block\\"></span><span class=\\"text-green-600 font-medium\\" style=\\"font-size:11.5px;\\">Active now</span>',
    '<span style=\\"width:6px;height:6px;border-radius:50%;background:#4ADE80;display:inline-block;\\"></span><span style=\\"color:#16A34A;font-weight:500;font-size:11.5px;">Active now</span>'
)

# statusDot JS
content = content.replace(
    "statusDot.className = `absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full ${conv.online ? 'status-online' : 'status-offline'}`;",
    "statusDot.className = conv.online ? 'status-online' : 'status-offline';\n        statusDot.style.cssText = 'position:absolute;bottom:-2px;right:-2px;width:10px;height:10px;border-radius:50%;border:2px solid white;';"
)

content = content.replace('class="font-semibold text-slate-700"', 'style="font-weight:600;color:#334155;"')
content = re.sub(r'class="w-8 h-8 rounded-full flex items-center justify-center text-white font-semibold"', 'style="width:32px;height:32px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:white;font-weight:600;"', content)
content = re.sub(r'class="relative flex-shrink-0"', 'style="position:relative;flex-shrink:0;"', content)
content = re.sub(r'class="font-medium text-slate-800 truncate"', 'style="font-weight:500;color:#1E293B;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;"', content)
content = re.sub(r'class="flex items-center gap-3 px-4 py-2\.5 hover:bg-slate-50 transition-colors cursor-pointer"', 'style="display:flex;align-items:center;gap:12px;padding:10px 16px;cursor:pointer;transition:background 0.1s;"', content)
content = re.sub(r'class="flex items-center gap-3 px-4 py-2\.5 hover:bg-red-50 transition-colors cursor-pointer"', 'style="display:flex;align-items:center;gap:12px;padding:10px 16px;cursor:pointer;transition:background 0.1s;"', content)
content = re.sub(r'class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0"', 'style="width:32px;height:32px;border-radius:8px;display:flex;align-items:center;justify-content:center;flex-shrink:0;"', content)
content = re.sub(r'class="w-8 h-8 rounded-lg flex items-center justify-center"', 'style="width:32px;height:32px;border-radius:8px;display:flex;align-items:center;justify-content:center;"', content)
content = re.sub(r'class="text-slate-700 font-medium truncate"', 'style="color:#334155;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;"', content)
content = re.sub(r'class="text-slate-800 font-medium truncate"', 'style="color:#1E293B;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;"', content)
content = re.sub(r'class="flex items-center justify-between px-4 py-2\.5 hover:bg-slate-50 transition-colors cursor-pointer"', 'style="display:flex;align-items:center;justify-content:space-between;padding:10px 16px;cursor:pointer;transition:background 0.1s;"', content)
content = re.sub(r'class="w-9 h-5 rounded-full cursor-pointer transition-colors flex items-center px-0\.5"', 'style="width:36px;height:20px;border-radius:100px;cursor:pointer;display:flex;align-items:center;padding:0 2px;transition:background 0.15s;"', content)
content = re.sub(r'class="w-4 h-4 bg-white rounded-full shadow-sm transition-transform"', 'style="width:16px;height:16px;background:white;border-radius:50%;box-shadow:0 1px 3px rgba(0,0,0,0.1);transition:transform 0.15s;"', content)
content = content.replace('class="text-slate-700"', 'style="color:#334155;"')
content = content.replace('class="text-red-500 font-medium"', 'style="color:#EF4444;font-weight:500;"')
content = re.sub(r'class="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0"', 'style="width:36px;height:36px;border-radius:8px;display:flex;align-items:center;justify-content:center;flex-shrink:0;"', content)
content = re.sub(r'class="tb-btn flex-shrink-0"', 'class="tb-btn" style="flex-shrink:0;"', content)
content = re.sub(r'class="px-4 py-3"', 'style="padding:12px 16px;"', content)
content = re.sub(r'\bclass="mt-2"\b', 'style="margin-top:8px;"', content)
content = re.sub(r'class="w-3 h-3 bg-white rounded-full"', 'style="width:12px;height:12px;background:white;border-radius:50%;"', content)
content = re.sub(r'class="ml-auto w-8 h-4 rounded-full"', 'style="margin-left:auto;width:32px;height:16px;border-radius:100px;"', content)
content = re.sub(r'class="text-blue-600 font-medium"', 'style="color:#2563EB;font-weight:500;"', content)
content = re.sub(r'class="flex items-center gap-2"', 'style="display:flex;align-items:center;gap:8px;"', content)
content = re.sub(r'class="text-slate-400 ml-1\.5"', 'style="color:#94A3B8;margin-left:6px;"', content)
content = re.sub(r'class="flex items-center gap-3 px-4 py-2\.5 hover:bg-slate-50 transition-colors"', 'style="display:flex;align-items:center;gap:12px;padding:10px 16px;transition:background 0.1s;"', content)
content = re.sub(r'class="w-full flex items-center gap-3 px-2\.5 py-2\.5 dm-item text-left([^"]*)"', lambda m: f'class="dm-item{m.group(1)}" style="width:100%;display:flex;align-items:center;gap:12px;padding:10px;text-align:left;"', content)
content = re.sub(r'class="w-10 h-10 rounded-full flex items-center justify-center text-white font-semibold"', 'style="width:40px;height:40px;border-radius:50%;display:flex;align-items:center;justify-content:center;color:white;font-weight:600;"', content)
content = re.sub(r'class="w-10 h-10 flex items-center justify-center text-white font-semibold"', 'style="width:40px;height:40px;display:flex;align-items:center;justify-content:center;color:white;font-weight:600;"', content)
content = re.sub(r'class="flex items-center justify-between mb-0\.5"', 'style="display:flex;align-items:center;justify-content:space-between;margin-bottom:2px;"', content)
content = re.sub(r'class="font-semibold truncate"', 'style="font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;"', content)
content = re.sub(r'class="flex items-center gap-2 overflow-hidden"', 'style="display:flex;align-items:center;gap:8px;overflow:hidden;"', content)
content = re.sub(r'class="truncate flex-1 min-w-0"', 'style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;min-width:0;"', content)
content = re.sub(r'class="flex items-center gap-1\.5 mt-2 justify-end"', 'style="display:flex;align-items:center;gap:6px;margin-top:8px;justify-content:flex-end;"', content)
content = content.replace('class="flex items-center gap-0.5"', 'style="display:flex;align-items:center;gap:2px;"')

print("All replacements done.")
with open(r'C:\chat-design\nexus-pure-v2.html', 'w', encoding='utf-8') as f:
    f.write(content)
print("File written successfully.")
