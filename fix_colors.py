import os
import re

dir_path = r'c:\Users\HomePC\Desktop\Vox App Antigravity\voxapplication\lib'
pattern = re.compile(r'(Color\(0xFF[A-Fa-f0-9]{6}\))([0-9]{2,3})\b')

def convert_to_hex(match):
    color_str = match.group(1) # e.g. Color(0xFF0A0E1A)
    alpha_pct = int(match.group(2)) # e.g. 54

    # Fix specific alpha percentage values commonly used by Colors.black54 etc.
    if alpha_pct == 54:
        alpha_hex = "8A"
    elif alpha_pct == 87:
        alpha_hex = "DD" # Dart uses DD for 87% usually (0xdd000000)
    elif alpha_pct == 38:
        alpha_hex = "61"
    elif alpha_pct == 26:
        alpha_hex = "42"
    elif alpha_pct == 12:
        alpha_hex = "1F"
    elif alpha_pct == 45:
        alpha_hex = "73"
    else:
        alpha_val = int(alpha_pct * 255 / 100)
        alpha_hex = f"{alpha_val:02X}"

    inner = re.search(r'0xFF([A-Fa-f0-9]{6})', color_str)
    if inner:
        base_hex = inner.group(1)
        return f"Color(0x{alpha_hex}{base_hex})"
    
    return f"{color_str}.withValues(alpha: 0.{alpha_pct})"

count = 0
for root, _, files in os.walk(dir_path):
    for f in files:
        if f.endswith('.dart'):
            file_path = os.path.join(root, f)
            with open(file_path, 'r', encoding='utf-8') as file:
                content = file.read()
            
            new_content = pattern.sub(convert_to_hex, content)
            
            if new_content != content:
                with open(file_path, 'w', encoding='utf-8') as file:
                    file.write(new_content)
                count += 1
                print(f"Fixed {file_path}")

print(f"Done! Modified {count} files.")
