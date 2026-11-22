"""Build UV-padded original surface finishes. No external artwork, fonts or samples."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

N = 480
PAD = 16
CELL = N + 2*PAD
NAMES = ['timber','bark','leaf','needle','metal','roof','concrete','asphalt',
         'glazing','shutter','pump','fascia','pv','stone','snow','enamel']
BASE = [(178,151,116),(115,96,72),(82,105,66),(57,85,70),
        (182,188,185),(152,151,144),(184,177,161),(94,91,84),
        (63,86,92),(150,156,153),(213,208,183),(198,86,41),
        (53,82,111),(150,143,126),(178,197,204),(214,217,205)]
# Original line-segment lettering for painted signs and instrument labels.
GLYPHS = {
 'F':'1111 1000 1110 1000 1000','U':'1001 1001 1001 1001 0110',
 'E':'1111 1000 1110 1000 1111','L':'1000 1000 1000 1000 1111',
 '0':'0110 1001 1001 1001 0110','1':'0100 1100 0100 0100 1110',
 '2':'1110 0001 0110 1000 1111','7':'1111 0001 0010 0100 0100',
 '8':'0110 1001 0110 1001 0110','9':'0110 1001 0111 0001 1110'}
def label(draw, x,y, text, width,height, ink):
    step = width/(5*len(text)-1)
    sy=height/5
    for j,ch in enumerate(text):
        for row,bits in enumerate(GLYPHS[ch].split()):
            for col,b in enumerate(bits):
                if b=='1':
                    a=x+(5*j+col)*step; t=y+row*sy
                    draw.rectangle((int(a),int(t),int(a+step),int(t+sy)),fill=ink)
def noise(rng, size):
    field=Image.fromarray(rng.uniform(0,255,(size,size)).astype('uint8'))
    return np.asarray(field.resize((N,N),Image.Resampling.BICUBIC),dtype=float)/127.5-1
def maps(out):
    atlas=np.zeros((CELL*4,CELL*4,3),np.uint8)
    orm=atlas.copy()
    y,x=np.mgrid[0:N,0:N]/N
    for i,key in enumerate(NAMES):
        rng=np.random.default_rng(1709+i)
        coarse,medium=noise(rng,9),noise(rng,40)
        fine=rng.normal(0,1,x.shape)
        texture=coarse*4+medium*3+fine*1.4
        rough=0.8; metallic=0.; groove=np.zeros_like(x)
        if key in ('timber','bark'):
            phase=x*(9 if key=='timber' else 23)+0.30*np.sin(y*7+x*8)+coarse*.66
            groove=np.exp(-(np.sin(np.pi*phase)/.19)**2)
            texture+=5*np.sin(phase*24+medium*2)-groove*26
            if key=='timber':
                groove=np.exp(-(np.sin(x*8*np.pi)/.078)**2)
                texture+=7*np.sin(np.floor(x*8)*7)-35*groove
        elif key in ('leaf','needle','snow'):
            texture+=coarse*9+medium*6
            canvas=Image.fromarray(np.uint8(np.clip(np.array(BASE[i])+texture[:,:,None],0,255)))
            draw=ImageDraw.Draw(canvas)
            for k in range(5600 if key!='snow' else 1600):
                a,b=rng.uniform(-8,N,2); h=rng.uniform(3,12); w=rng.uniform(2,4)
                value=rng.uniform(-21,16)+coarse[int(b)%N,int(a)%N]*12
                color=tuple(np.clip(np.array(BASE[i])+value,0,255).astype(int))
                slant=rng.uniform(-7,7)
                if key=='leaf':
                    draw.polygon([(a,b),(a+w,b-h*.4),(a+slant,b-h),(a-w,b-h*.5)],fill=color)
                else:
                    draw.line((a,b,a+slant,b+h),fill=color,width=2)
            if key=='leaf':
                # Large overlapping sprays leave legible shadows beneath smaller leaves.
                for j in range(145):
                    x0,y0=rng.uniform(-14,N+14,2)
                    a=rng.uniform(0,2*np.pi);ax=np.cos(a);ay=np.sin(a)
                    strength=rng.uniform(.67,1.12)
                    for k in range(5):
                        for side in (-1,1):
                            px=x0+ax*k*5;py=y0+ay*k*5
                            dx=ax*.6-ay*side*.8;dy=ay*.6+ax*side*.8
                            length=rng.uniform(8,16)*(1-k*.07);w=length*.30
                            mid=(px+dx*length*.53,py+dy*length*.53)
                            lobe=[(px,py),(mid[0]-dy*w,mid[1]+dx*w),(px+dx*length,py+dy*length),(mid[0]+dy*w,mid[1]-dx*w)]
                            ink=np.array(BASE[i])*strength*rng.uniform(.86,1.22)
                            draw.polygon(lobe,fill=tuple(np.clip(ink,0,255).astype(int)))
                            draw.polygon(lobe[:3],fill=tuple(np.clip(ink*1.08,0,255).astype(int)))
        elif key in ('roof','metal','shutter'):
            phase = (x*12 if key=='roof' else y*(20 if key=='shutter' else 5))
            groove=np.exp(-(np.sin(phase*np.pi)/.17)**2)
            texture += -groove*(42 if key!='metal' else 23)+6*np.sin(phase*2*np.pi)
            texture += 4*np.sin(110*x + medium) * np.maximum(0,1-y)
            studs=(np.sin(x*12*np.pi)**2+np.sin(y*2*np.pi+.17)**2)<.012
            texture+=studs*18; rough=.56; metallic=.45
        elif key=='concrete':
            row=np.floor(y*6); jj=np.mod(x*4+row*.5,1)
            seam=np.minimum(np.minimum(jj,1-jj)/4,np.minimum(np.mod(y*6,1),1-np.mod(y*6,1))/6)
            groove=np.exp(-(seam/.004)**2)
            texture+=coarse*6+fine*2-groove*34+np.sin(row*21+np.floor(x*4+row*.5)*5)*4
        elif key=='asphalt':
            texture+=fine*6+medium*5+4*np.sin(x*45+coarse*3)
        elif key=='glazing':
            column=np.floor(x*4)
            for phase in (x*4,y*3):
                groove=np.maximum(groove,np.exp(-(np.sin(np.pi*phase)/.145)**2))
            texture+=24*(1-y)+8*np.sin(column*7)+np.maximum(0,medium+coarse*.9)*14
            texture-=groove*54
            texture+=26*np.exp(-((np.mod(x*4,1)-.04)/.025)**2)
            rough=.29; metallic=.24
        elif key=='pv':
            groove=np.maximum(np.exp(-(np.sin(x*np.pi*8)/.16)**2),
                              np.exp(-(np.sin(y*np.pi*12)/.13)**2))
            texture+=groove*75+6*np.sin(x*230)+8*np.sin(np.floor(x*8)*3+np.floor(y*12)*2)
            rough=.29; metallic=.4
        elif key=='stone':
            phase=y*7+coarse*.9+.27*np.sin(x*8)
            groove=np.exp(-(np.sin(phase*np.pi)/.18)**2)
            texture+=coarse*13+medium*9+6*np.sin(phase*6.28)-22*groove
        elif key in ('enamel','pump','fascia'):
            rough=.47; metallic=.15; texture+=-4*(y**3)
        if key not in ('leaf','needle','snow'):
            canvas=Image.fromarray(np.uint8(np.clip(np.array(BASE[i])+texture[:,:,None],0,255)))
            draw=ImageDraw.Draw(canvas)
        if key=='pump':
            draw.rounded_rectangle((48,36,432,252),radius=9,fill=(45,58,59))
            draw.rectangle((78,67,392,139),fill=(128,153,129))
            label(draw,125,83,'098',184,36,(31,49,44))
            for j in range(3):
                draw.rectangle((79+j*110,175,157+j*110,211),fill=(189,160-j*12,94+j*12))
            draw.rectangle((0,305,N,384),fill=(178,76,43))
            label(draw,74,321,'FUEL',261,42,(239,226,183))
        if key=='fascia':
            draw.rectangle((0,60,N,75),fill=(235,202,140))
            draw.rectangle((0,400,N,417),fill=(109,51,41))
            label(draw,49,123,'FUEL',380,207,(251,236,193))
        tile=np.asarray(canvas)
        pixrough=np.clip(rough+medium*.035+groove*.10,0,1)
        data=np.stack((1-.16*groove,pixrough,np.ones_like(x)*metallic),axis=2)
        row,col=divmod(i,4)
        region=np.s_[row*CELL:(row+1)*CELL,col*CELL:(col+1)*CELL]
        atlas[region]=np.pad(tile,((PAD,PAD),(PAD,PAD),(0,0)),mode='edge')
        orm[region]=np.pad((data.clip(0,1)*255).astype('uint8'),((PAD,PAD),(PAD,PAD),(0,0)),mode='edge')
    out.mkdir(exist_ok=True)
    Image.fromarray(atlas).save(out/'roadside_color.jpg',quality=91,subsampling=0,optimize=True)
    Image.fromarray(orm).save(out/'roadside_orm.png',optimize=True)
