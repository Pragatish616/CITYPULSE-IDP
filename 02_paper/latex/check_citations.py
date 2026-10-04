import re,sys
tex=open(sys.argv[1]).read(); bib=open('refs.bib').read()+open('extra.bib').read()
body=tex.split('\\begin{document}')[1]
abs_=re.search(r'\\begin\{abstract\}(.*?)\\end\{abstract\}',body,re.S).group(1)
fails=[]
if '\\cite' in abs_: fails.append('citation in abstract')
keys=set(re.findall(r'^@\w+\{([^,]+),',bib,re.M))
cited=[k.strip() for m in re.finditer(r'\\cite\{([^}]*)\}',body) for k in m.group(1).split(',')]
for k in set(cited)-keys: fails.append('missing bib key '+k)
for m in re.finditer(r'et al\.\}?',body):
    nxt=body[m.end():m.end()+12]
    if not nxt.lstrip('~ ').startswith('\\cite'): fails.append('et al. without citation: ...'+body[max(0,m.start()-40):m.end()+12].replace('\n',' '))
bbl=open(sys.argv[1].replace('.tex','.bbl')).read()
order=re.findall(r'\\bibitem\{([^}]+)\}',bbl)
first=[]; [first.append(k) for k in cited if k not in first]
if order!=first: fails.append('bibliography order differs from first-citation order')
print(sys.argv[1],'cited unique:',len(set(cited)),'bibitems:',len(order),'FAIL' if fails else 'PASS'); [print(' -',f) for f in fails]
