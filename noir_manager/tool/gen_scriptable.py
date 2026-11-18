# สร้าง lib/sync/scriptable_script.dart จาก tool/NoirManager.js (รันใน noir_manager/)
js = open('tool/NoirManager.js', encoding='utf-8').read()
assert "'''" not in js
head = open('lib/sync/scriptable_script.dart', encoding='utf-8').read().split("const scriptableSource = r'''")[0]
open('lib/sync/scriptable_script.dart', 'w', encoding='utf-8').write(head + "const scriptableSource = r'''" + js + "''';\n")
