from PIL import Image, ImageDraw
import math
S=64
def new(): return Image.new("RGBA",(S,S),(0,0,0,0))
def px(im,x,y,v,a=255):
    if 0<=x<S and 0<=y<S: im.putpixel((x,y),(v,v,v,a))
def ring(im,inset,v,a=255,skip=0):
    lo,hi=inset,S-1-inset
    for i in range(lo+skip,hi+1-skip):
        px(im,i,lo,v,a); px(im,i,hi,v,a); px(im,lo,i,v,a); px(im,hi,i,v,a)
def mirror4(im):
    q=im.crop((0,0,S//2,S//2))
    im.paste(q.transpose(Image.FLIP_LEFT_RIGHT),(S//2,0))
    top=im.crop((0,0,S,S//2))
    im.paste(top.transpose(Image.FLIP_TOP_BOTTOM),(0,S//2))
    return im
# forged: thick hammered band, chunky L brackets with two studs
g=new()
ring(g,0,0,220); ring(g,1,170); ring(g,2,215); ring(g,3,150); ring(g,4,95); ring(g,5,0,170)
d=ImageDraw.Draw(g)
L=17; T=8
for box in ([0,0,L,T],[0,0,T,L]):
    d.rectangle(box,fill=(0,0,0,230))
for box in ([1,1,L-1,T-1],[1,1,T-1,L-1]):
    d.rectangle(box,fill=(135,135,135,255))
d.line([1,1,L-1,1],fill=(235,235,235,255)); d.line([1,1,1,L-1],fill=(235,235,235,255))
d.line([T,T-1,L-1,T-1],fill=(80,80,80,255)); d.line([T-1,T,T-1,L-1],fill=(80,80,80,255))
for (cx,cy) in [(3,3),(12,3),(3,12)]:
    d.rectangle([cx,cy,cx+2,cy+2],fill=(60,60,60,255)); d.rectangle([cx,cy,cx+1,cy+1],fill=(255,255,255,255))
# hammer nicks inside the corner zone only
for (x,y) in [(9,5),(6,9)]: px(g,x,y,95)
mirror4(g); g.save("theme-frame-forged.png")
# vine: twin thin twigs, leaf knot at each corner
v=new()
ring(v,2,200,255,skip=10); ring(v,4,120,200,skip=12)
def leaf(cx,cy,dx,dy,n=5):
    for i in range(n):
        w=[0,1,1,1,0][i] if n==5 else 0
        x=cx+dx*i; y=cy+dy*i
        px(v,x,y,245)
        for k in range(1,w+1):
            px(v,x-dy*k,y+dx*k,200); px(v,x+dy*k,y-dx*k,200)
leaf(6,6,1,1,5)      # diagonal leaf pointing inward
leaf(8,2,1,0,5)      # leaf along top
leaf(2,8,0,1,5)      # leaf along left
for dx,dy in [(0,0),(1,0),(0,1),(1,1)]: px(v,3+dx,3+dy,255)   # knot
px(v,5,4,160); px(v,4,5,160)
mirror4(v); v.save("theme-frame-vine.png")
# gilt: slim double line with a small fleur corner piece
t=new()
ring(t,1,240,255,skip=9); ring(t,4,170,255,skip=12)
d=ImageDraw.Draw(t)
# corner square joining lines
d.rectangle([1,1,9,9],outline=(240,240,240,255))
d.rectangle([3,3,7,7],fill=(200,200,200,255)); px(t,5,5,255); 
for (x,y) in [(4,4),(6,4),(4,6),(6,6)]: px(t,x,y,120)
# fleur petals reaching along each edge and the diagonal
for i in range(4):
    px(t,11+i,1+ (1 if i in (1,2) else 0)+1,230); px(t,2+(1 if i in (1,2) else 0),11+i,230)
for i in range(3): px(t,10+i,10+i,230 - 40*i)
px(t,13,13,255)
mirror4(t); t.save("theme-frame-gilt.png")
from gen import preview  # reuses tinted preview
