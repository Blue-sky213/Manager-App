# embed the measuring font into the page so the viewer draws exactly the widths that were checked
import base64,re,sys
d='/tmp/claude-0/-home-claude/48d814e3-9116-5fa6-a0bd-d221a9af3c08/scratchpad/dg'
page=sys.argv[1]
css=open(f'{d}/node_modules/@fontsource/ibm-plex-sans-thai/400.css').read()
rng={sub: re.search(rf'{sub}-400-normal\.woff2.*?unicode-range:\s*([^;]+);', css, re.S).group(1) for sub in ['thai','latin']}
faces=''
for sub in ['thai','latin']:
  for w in [400,600]:
    b=base64.b64encode(open(f'{d}/node_modules/@fontsource/ibm-plex-sans-thai/files/ibm-plex-sans-thai-{sub}-{w}-normal.woff2','rb').read()).decode()
    faces+=f'@font-face{{font-family:"IBM Plex Sans Thai";font-weight:{w};font-display:block;src:url(data:font/woff2;base64,{b}) format("woff2");unicode-range:{rng[sub]}}}\n'
t=open(page).read()
t=t.replace('family=IBM+Plex+Sans+Thai:wght@400;600;700&','')
t=t.replace('<style>','<style>\n'+faces,1)
open(page,'w').write(t)
