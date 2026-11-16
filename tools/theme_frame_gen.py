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
    # build from top-left quadrant
    q=im.crop((0,0,S//2,S//2))
    im.paste(q.transpose(Image.FLIP_LEFT_RIGHT),(S//2,0))
    top=im.crop((0,0,S,S//2))
    im.paste(top.transpose(Image.FLIP_TOP_BOTTOM),(0,S//2))
    return im
# ---- metal: bevelled bar with riveted corner plates
m=new()
ring(m,0,0,200)          # outer shadow line
ring(m,1,255,255)        # highlight
ring(m,2,190,255)        # body
ring(m,3,110,255)        # lower bevel
ring(m,4,0,150)          # inner shadow
d=ImageDraw.Draw(m)
P=11
for (x0,y0) in [(0,0)]:
    d.rectangle([x0,y0,x0+P,y0+P],fill=(0,0,0,210))
    d.rectangle([x0+1,y0+1,x0+P-1,y0+P-1],fill=(150,150,150,255))
    d.line([x0+1,y0+1,x0+P-1,y0+1],fill=(255,255,255,255))
    d.line([x0+1,y0+1,x0+1,y0+P-1],fill=(255,255,255,255))
    d.line([x0+2,y0+P-1,x0+P-1,y0+P-1],fill=(90,90,90,255))
    d.line([x0+P-1,y0+2,x0+P-1,y0+P-1],fill=(90,90,90,255))
    # rivet
    cx,cy=x0+5,y0+5
    d.rectangle([cx,cy,cx+2,cy+2],fill=(70,70,70,255))
    d.rectangle([cx,cy,cx+1,cy+1],fill=(255,255,255,255))
mirror4(m)
m.save("theme-frame-metal.png")
# ---- flourish: hairline with scrolled corners
f=new()
A=3
ring(f,A,235,255,skip=12)       # main hairline, broken at the corners
ring(f,A+3,235,90,skip=17)      # faint inner echo
d=ImageDraw.Draw(f)
# corner: arc curling inward, with a diamond at the corner point
def arc(cx,cy,r,a0,a1,v=235,a=255):
    steps=int(r*8)
    for i in range(steps+1):
        t=math.radians(a0+(a1-a0)*i/steps)
        px(f,round(cx+r*math.cos(t)),round(cy+r*math.sin(t)),v,a)
# concave quarter arc joining the two hairline ends: centre at the frame corner
arc(A,A,12,0,90)
# small inner curl
arc(A+7,A+7,3,180,450,235,200)
# diamond at the outer corner
for dx,dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1)]:
    px(f,A+2+dx,A+2+dy,255,255)
# end beads where the line resumes
for (x,y) in [(A+12,A),(A,A+12)]:
    for dx,dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1)]:
        px(f,x+dx,y+dy,255,255)
mirror4(f)
f.save("theme-frame-flourish.png")
# preview on dark, tinted gold
def preview(im,tint):
    w,h=220,120; M=20
    out=Image.new("RGBA",(w,h),(21,24,28,255))
    t=Image.new("RGBA",im.size)
    for y in range(S):
        for x in range(S):
            r,g,b,a=im.getpixel((x,y))
            t.putpixel((x,y),(r*tint[0]//255,g*tint[1]//255,b*tint[2]//255,a))
    def blit(sx,sy,sw,sh,dx,dy,dw,dh):
        out.alpha_composite(t.crop((sx,sy,sx+sw,sy+sh)).resize((dw,dh),Image.NEAREST),(dx,dy))
    c=S-2*M
    xs=[(0,M,0,M),(M,c,M,w-2*M),(S-M,M,w-M,M)]; ys=[(0,M,0,M),(M,c,M,h-2*M),(S-M,M,h-M,M)]
    for i,(sx,sw,dx,dw) in enumerate(xs):
        for j,(sy,sh,dy,dh) in enumerate(ys):
            if i==1 and j==1: continue
            blit(sx,sy,sw,sh,dx,dy,dw,dh)
    return out
a=preview(m,(221,186,106)); b=preview(f,(216,210,194))
sheet=Image.new("RGBA",(460,120),(10,12,14,255)); sheet.paste(a,(0,0)); sheet.paste(b,(240,0))
sheet.resize((1380,360),Image.NEAREST).save("preview.png")
