import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.boundsPen import BoundsPen
FONT='fonts/node_modules/@expo-google-fonts/readex-pro/600SemiBold/ReadexPro_600SemiBold.ttf'
tt=TTFont(FONT); gs=tt.getGlyphSet()
font=hb.Font(hb.Face(hb.Blob.from_file_path(FONT)))
AR_SCALE=0.94; GAP=250
class DartPen(BasePen):
    def __init__(self, gs, tx, ty, s):
        super().__init__(gs); self.ops=[]; self.t=(tx,ty,s)
    def P(self,p):
        tx,ty,s=self.t; return [round(tx+p[0]*s,1), round(-(ty+p[1]*s),1)]
    def _moveTo(self,p): self.ops+= [0]+self.P(p)
    def _lineTo(self,p): self.ops+= [1]+self.P(p)
    def _qCurveToOne(self,a,b): self.ops+= [2]+self.P(a)+self.P(b)
    def _curveToOne(self,a,b,c): self.ops+= [3]+self.P(a)+self.P(b)+self.P(c)
    def _closePath(self): self.ops+= [4]
def shape(text):
    buf=hb.Buffer(); buf.add_str(text); buf.guess_segment_properties(); hb.shape(font,buf,{})
    x=0; out=[]
    for i,p in zip(buf.glyph_infos,buf.glyph_positions):
        out.append((tt.getGlyphName(i.codepoint),x+p.x_offset,p.y_offset)); x+=p.x_advance
    return out,x
def parts(text, ox, s):
    gl,adv=shape(text); body=[]; dots=[]
    for name,x,y in gl:
        rp=DecomposingRecordingPen(gs); gs[name].draw(rp)
        cur=[]
        for op,args in rp.value:
            cur.append((op,args))
            if op in ('closePath','endPath'):
                bp=BoundsPen(gs)
                for o,a in cur: getattr(bp,o)(*a)
                x0,y0,x1,y1=bp.bounds; w,h=x1-x0,y1-y0
                pen=DartPen(gs, ox+x*s, y*s, s)
                # glyph-local coordinates: shift by glyph origin first
                pen.t=(ox+x*s, y*s, s)
                for o,a in cur: getattr(pen,o)(*a)
                isdot = 140<=w<=230 and 140<=h<=230
                (dots if isdot else body).append((pen.ops, ox+(x+(x0+x1)/2)*s))
                cur=[]
    return body,dots,adv
en_body,en_dots,en_adv=parts('Shahri',0,1)
div_x=en_adv+GAP; ar_x=div_x+GAP+40
ar_body,ar_dots,ar_adv=parts('شهري',ar_x,AR_SCALE)
total=ar_x+ar_adv*AR_SCALE
ar_dots.sort(key=lambda d:-d[1])
fmt=lambda ops: ','.join(str(int(v)) if float(v).is_integer() else str(v) for v in ops)
flat=lambda ps: [v for ops,_ in ps for v in ops]
out=f'''// Generated from Readex Pro SemiBold (SIL Open Font License) by tool/gen_wordmark.py.
// The "Shahri | شهري" wordmark as vector shapes, in font units (y grows downwards, baseline at 0).
// Dots are kept apart so they can be coloured gold and animated one by one.

const double wmLeft = -40, wmTop = -820, wmWidth = {total+80:.0f}, wmHeight = 1380;
const double wmDividerX = {div_x}, wmDividerTop = -640, wmDividerHeight = 760, wmDividerWidth = 44;
const double wmEnRight = {en_adv}, wmArLeft = {ar_x};

/// 0 moveTo(x,y) · 1 lineTo(x,y) · 2 quadTo(x1,y1,x,y) · 3 cubicTo(x1,y1,x2,y2,x,y) · 4 close
const List<double> wmEnglish = [{fmt(flat(en_body))}];
const List<double> wmArabic = [{fmt(flat(ar_body))}];
/// Drop order: the i, the three dots of ش (right to left), the two dots of ي.
const List<List<double>> wmDots = [
{''.join('  ['+fmt(ops)+'],\n' for ops,_ in en_dots+ar_dots)}];
'''
open('/home/claude/household_ledger/lib/brand_paths.dart','w').write(out)
print(len(out), len(en_dots+ar_dots))
