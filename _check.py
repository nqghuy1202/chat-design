import re
content = open(r'C:\chat-design\nexus-pure-v2.html', encoding='utf-8').read()

# Check Tailwind CDN removed
print("tailwindcss.com present:", 'tailwindcss.com' in content)

# Check remaining class= with Tailwind patterns
patterns = ['flex-1', 'items-center', 'rounded-full', 'text-white', 'font-semibold',
            'bg-white', 'w-9 ', 'h-9 ', 'gap-', 'px-', 'py-', 'mt-', 'mb-',
            'min-h-screen', 'fixed inset', 'z-50', 'z-40']
for p in patterns:
    matches = re.findall(r'class="[^"]*' + re.escape(p) + r'[^"]*"', content)
    if matches:
        print(f"FOUND '{p}':", matches[:2])

print("\nFile size:", len(content), "chars")
print("Done checking.")
