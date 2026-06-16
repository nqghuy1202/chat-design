import re

with open(r'C:\chat-design\nexus-pure-v2.html', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. message-group spacing classes (px-2 py-X -mx-2) - these are functional/layout classes
# The message-group already has custom CSS for border-radius etc.
# These padding/margin classes need to be converted too.
# px-2 py-2 -mx-2 -> padding:8px; margin-left:-8px;margin-right:-8px;
content = re.sub(
    r'class="message-group px-2 py-2 -mx-2"',
    'class="message-group" style="padding:8px;margin-left:-8px;margin-right:-8px;"',
    content
)
content = re.sub(
    r'class="message-group px-2 py-1 -mx-2"',
    'class="message-group" style="padding:4px 8px;margin-left:-8px;margin-right:-8px;"',
    content
)
content = re.sub(
    r'class="message-group px-2 py-1\.5 -mx-2"',
    'class="message-group" style="padding:6px 8px;margin-left:-8px;margin-right:-8px;"',
    content
)
content = re.sub(
    r'class="message-group msg-me-wrap px-2 py-2 -mx-2"',
    'class="message-group msg-me-wrap" style="padding:8px;margin-left:-8px;margin-right:-8px;"',
    content
)
content = re.sub(
    r'class="message-group msg-me-wrap px-2 py-1\.5 -mx-2"',
    'class="message-group msg-me-wrap" style="padding:6px 8px;margin-left:-8px;margin-right:-8px;"',
    content
)
content = re.sub(
    r'class="message-group msg-me-wrap px-2 py-1 -mx-2"',
    'class="message-group msg-me-wrap" style="padding:4px 8px;margin-left:-8px;margin-right:-8px;"',
    content
)

# 2. flex items-center gap-3 in member rows
content = re.sub(
    r'class="flex items-center gap-3"',
    'style="display:flex;align-items:center;gap:12px;"',
    content
)

# 3. Status dot in group member rows: absolute -bottom-0 -right-0 w-2 h-2 rounded-full status-online
content = re.sub(
    r'class="absolute -bottom-0 -right-0 w-2 h-2 rounded-full status-online"',
    'class="status-online" style="position:absolute;bottom:0;right:0;width:8px;height:8px;border-radius:50%;"',
    content
)

# 4. w-2.5 h-2.5 rounded-full (onlineDot in renderRPDM)
content = re.sub(
    r'class="w-2\.5 h-2\.5 rounded-full"',
    'style="width:10px;height:10px;border-radius:50%;"',
    content
)

# 5. class="mt-2" remaining
content = re.sub(r'\bclass="mt-2"\b', 'style="margin-top:8px;"', content)
# voucher-amount mt-2
content = re.sub(r'class="voucher-amount mt-2"', 'class="voucher-amount" style="margin-top:8px;"', content)
# vt-tag ${tagClass} mb-3  (in JS template literal)
content = content.replace(
    'class="vt-tag ${tagClass} mb-3"',
    'class="vt-tag ${tagClass}" style="margin-bottom:12px;"'
)

# Also fix in renderRPVoucher static: vt-tag hoadon mb-3 or similar
content = re.sub(
    r'class="vt-tag (\w+) mb-3"',
    r'class="vt-tag \1" style="margin-bottom:12px;"',
    content
)

# 6. Fix sendMessage JS: class="message-group msg-me-wrap px-2 py-2 -mx-2"
content = content.replace(
    "msgEl.className = 'message-group msg-me-wrap px-2 py-2 -mx-2';",
    "msgEl.className = 'message-group msg-me-wrap';\n      msgEl.style.cssText += ';padding:8px;margin-left:-8px;margin-right:-8px;';"
)

print("Fix 2 done.")
with open(r'C:\chat-design\nexus-pure-v2.html', 'w', encoding='utf-8') as f:
    f.write(content)
print("Written.")
