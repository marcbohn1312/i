# Baut docs/index.html aus quelle/head.html + quelle/app.html + quelle/tail.html
import os
d=os.path.dirname(os.path.abspath(__file__))
r=lambda n:open(os.path.join(d,n),encoding='utf8').read()
open(os.path.join(d,'..','docs','index.html'),'w',encoding='utf8').write(r('head.html')+r('app.html')+r('tail.html'))
print('gebaut')
