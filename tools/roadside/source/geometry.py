"""Single-surface, indexed glTF geometry. Author coordinates are X right, Y rear, Z up."""
import json, math, struct
from pathlib import Path
import numpy as np
from finishes import BASE,NAMES

TAU=math.tau
WHITE=(1,1,1)
def unit(v):
    v=np.asarray(v,float)
    return v/max(1e-12,np.linalg.norm(v))
def basis(axis):
    z=unit(axis)
    x=unit(np.cross((0,1,0) if abs(z[1])<.92 else (1,0,0),z))
    return x,np.cross(z,x),z
def linear(rgb):
    rgb=np.clip(rgb,0,1)
    return np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
def rgb_mul(rgb,k):
    return tuple(np.array(rgb)*k)
class Mesh:
    def __init__(self,name,near):
        self.name=name; self.near=near; self.verts=[]; self.lookup={}; self.indices=[]
    def face(self,points,finish,tint=WHITE,uv=None,normals=None,shades=None):
        pts=np.asarray(points,float)
        if uv is None:
            uv=[(0,1),(1,1),(1,0),(0,0)] if len(pts)==4 else [(0,1),(1,1),(.5,0)]
        normal=unit(np.cross(pts[1]-pts[0],pts[2]-pts[0]))
        if np.linalg.norm(normal)<.1:return
        colidx=NAMES.index(finish)
        row,col=divmod(colidx,4)
        color=np.array(tint) if self.near else np.array(tint)*np.array(BASE[colidx])/255
        idx=[]
        for j,(pos,tex) in enumerate(zip(pts,uv)):
            norm=normal if normals is None else normals[j]
            c=linear(color*(1 if shades is None else shades[j]))
            vertex=(*np.round(pos,5),*np.round(norm,5),*np.rint(c*255).astype(int),
                    *(((col+(16+np.clip(tex[0],0,1)*479)/512)/4,
                       (row+(16+np.clip(tex[1],0,1)*479)/512)/4) if self.near else ()))
            if vertex not in self.lookup:
                self.lookup[vertex]=len(self.verts); self.verts.append(vertex)
            idx.append(self.lookup[vertex])
        for k in range(1,len(idx)-1):
            self.indices.extend((idx[0],idx[k],idx[k+1]))
    def box(self,center,size,finish,tint=WHITE,angle=0,front=None):
        hx,hy,hz=np.array(size)/2
        pts=np.array([[-hx,-hy,-hz],[hx,-hy,-hz],[hx,hy,-hz],[-hx,hy,-hz],
                      [-hx,-hy,hz],[hx,-hy,hz],[hx,hy,hz],[-hx,hy,hz]])
        cs,sn=math.cos(angle),math.sin(angle)
        pts=pts@np.array([[cs,sn,0],[-sn,cs,0],[0,0,1]])+center
        for j,face in enumerate(((0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7),(3,2,1,0))):
            self.face(pts[list(face)],front if j==0 and front else finish,tint)
    def tube(self,a,b,r0,r1,finish,tint=WHITE,n=8,smooth=True):
        a,b=np.array(a),np.array(b)
        axis=b-a; h=np.linalg.norm(axis)
        if h<1e-5:return
        xx,yy,zz=basis(axis)
        radii=[xx*math.cos(j*TAU/n)+yy*math.sin(j*TAU/n) for j in range(n)]
        bot=[a+r*r0 for r in radii]; top=[b+r*r1 for r in radii]
        normals=[unit(r+zz*(r0-r1)/h) for r in radii]
        for j in range(n):
            k=(j+1)%n
            points=[bot[j],bot[k],top[k],top[j]] if r1 else [bot[j],bot[k],b]
            ns=[normals[j],normals[k],normals[k],normals[j]] if r1 else [normals[j],normals[k],unit(normals[j]+normals[k])]
            uv=[(j/n,1),((j+1)/n,1),((j+1)/n,0),(j/n,0)][:len(points)]
            self.face(points,finish,tint,uv=uv,normals=ns if smooth else None)
        for ring,reverse in ((bot,True),(top,False)):
            if ring is top and r1==0:continue
            # Fans avoid duplicate centre vertices in the cap.
            rr=ring[::-1] if reverse else ring
            for j in range(1,n-1):
                self.face([rr[0],rr[j],rr[j+1]],finish,tint)
    def rings(self,rings,finish,tint=WHITE,smooth=0,shading=None):
        # Ordered bottom to top, counterclockwise in plan. End caps are closed.
        rows=[np.asarray(r,float) for r in rings]
        n=len(rows[0])
        for i in range(len(rows)-1):
            for j in range(n):
                k=(j+1)%n
                ps=[rows[i][j],rows[i][k],rows[i+1][k],rows[i+1][j]]
                vs=[(i,j),(i,k),(i+1,k),(i+1,j)]
                ns=[]
                if smooth:
                    for l,m in vs:
                        around=rows[l][(m+1)%n]-rows[l][m-1]
                        up=rows[min(l+1,len(rows)-1)][m]-rows[max(0,l-1)][m]
                        ns.append(unit(np.cross(around,up)))
                sh=[shading(l,m) for l,m in vs] if shading else None
                v0=1-i/(len(rows)-1);v1=1-(i+1)/(len(rows)-1)
                uv=[(j/n,v0),((j+1)/n,v0),((j+1)/n,v1),(j/n,v1)]
                self.face(ps,finish,tint,uv=uv,normals=ns or None,shades=sh)
        for row in (rows[0][::-1],rows[-1]):
            # One continuous projection on a roof or apron, including fan diagonals.
            origin=row[:,:2].min(axis=0)
            span=np.maximum(1e-6,np.ptp(row[:,:2],axis=0))
            coords=(row[:,:2]-origin)/span
            for j in range(1,n-1):
                self.face([row[0],row[j],row[j+1]],finish,tint,
                          uv=[(coords[k,0],1-coords[k,1]) for k in (0,j,j+1)])
    def panel(self,x,y,z,width,height,finish,tint=WHITE):
        self.face([(x-width/2,y,z),(x+width/2,y,z),(x+width/2,y,z+height),
                   (x-width/2,y,z+height)],finish,tint)
    def bounds(self):
        positions=np.asarray(self.verts)[:,:3]
        return positions.min(axis=0),positions.max(axis=0)
    def fit_proxy(self,bounds):
        # Preserve the detailed silhouette's envelope and ground contact across tiers.
        low,high=self.bounds()
        scale=(bounds[1]-bounds[0])/(high-low)
        self.verts=[(*((np.array(v[:3])-low)*scale+bounds[0]),*unit(np.array(v[3:6])/scale),*v[6:])
                    for v in self.verts]
    def save(self,path):
        arr=np.array(self.verts)
        # Z-up to glTF Y-up, preserving handedness.
        pos=arr[:,[0,2,1]].copy();pos[:,2]*=-1
        normals=arr[:,[3,5,4]].copy();normals[:,2]*=-1
        data=bytearray();views=[];access=[]
        def add(vals,dtype,shape,component,target,limits=False,normalized=False):
            vals=np.ascontiguousarray(vals,dtype=dtype)
            while len(data)%4:data.append(0)
            views.append(dict(buffer=0,byteOffset=len(data),byteLength=vals.nbytes,target=target))
            data.extend(vals.tobytes())
            entry=dict(bufferView=len(views)-1,componentType=component,count=len(vals),type=shape)
            if limits: entry.update(min=vals.min(axis=0).tolist(),max=vals.max(axis=0).tolist())
            if normalized:entry['normalized']=True
            access.append(entry);return len(access)-1
        attrs={'POSITION':add(pos,'<f4','VEC3',5126,34962,True),
               'NORMAL':add(normals,'<f4','VEC3',5126,34962),
               'COLOR_0':add(np.column_stack((arr[:,6:9],np.full(len(arr),255))),
                             'u1','VEC4',5121,34962,normalized=True)}
        if self.near:attrs['TEXCOORD_0']=add(arr[:,9:11],'<f4','VEC2',5126,34962)
        assert len(arr)<65536
        indices=add(self.indices,'<u2','SCALAR',5123,34963)
        mat={'name':'Roadside finishes' if self.near else 'Distance paint',
             'pbrMetallicRoughness':{'metallicFactor':0,'roughnessFactor':.82}}
        primitive={'attributes':attrs,'indices':indices,'material':0}
        obj={'asset':{'version':'2.0','generator':'Phaethon roadside workshop'},'scene':0,
             'scenes':[{'nodes':[0]}],'nodes':[{'name':self.name,'mesh':0}],
             'meshes':[{'name':self.name,'primitives':[primitive]}],'materials':[mat],
             'bufferViews':views,'accessors':access}
        if self.near:
            obj['images']=[{'uri':'../../textures/'+f} for f in ('roadside_color.jpg','roadside_orm.png')]
            obj['samplers']=[{'minFilter':9987,'magFilter':9729,'wrapS':33071,'wrapT':33071}]
            obj['textures']=[{'sampler':0,'source':i} for i in range(2)]
            mat['pbrMetallicRoughness'].update(metallicFactor=1,roughnessFactor=1,
                baseColorTexture={'index':0},metallicRoughnessTexture={'index':1})
        obj['buffers']=[{'byteLength':len(data)}]
        meta=json.dumps(obj,separators=(',',':')).encode()
        meta+=b' '*((-len(meta))%4);data+=bytes((-len(data))%4)
        path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(meta)+len(data))+
            struct.pack('<I4s',len(meta),b'JSON')+meta+struct.pack('<I4s',len(data),b'BIN\0')+data)
        return {'triangles':len(self.indices)//3,'vertices':len(arr),
                'width_height_depth_m':np.round(np.ptp(pos,axis=0),1).tolist(),
                'footprint_radius_m':round(float(np.linalg.norm(pos[:,[0,2]],axis=1).max()),2)}
