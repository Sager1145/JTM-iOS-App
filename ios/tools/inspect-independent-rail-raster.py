#!/usr/bin/env python3
"""Inspect original 3x iPhone raster-probe screenshots against the native rail.

Only near-vertical red spans with both native green flanks yield a center.
These limited snapshot sections do not establish motion latency, globe behavior,
or whole-scene acceptance. The frame code is read from displayed pixels.
Requires one or more unmodified screenshots from testNativePolylineRasterFrameProbe.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

swift_source = r'''
import CoreGraphics
import Foundation
import ImageIO
for file in CommandLine.arguments.dropFirst() {
 let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath:file) as CFURL, nil)!,0,nil)!
 let w=image.width,h=image.height
 let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
 c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
 let p=c.data!.assumingMemoryBound(to:UInt8.self)
 func color(_ x:Int,_ y:Int)->(Int,Int,Int){let a=(y*w+x)*4;return(Int(p[a]),Int(p[a+1]),Int(p[a+2]))}
 var tag:(Int,Int)?
 outer:for y in 0..<min(500,h){for x in 0..<min(300,w){let a=color(x,y);if a.0>245&&a.1<10&&a.2>245{tag=(x,y);break outer}}}
 var frame = -1
 if let (x,y)=tag {frame=0;for bit in 0..<16{let a=color(x+15+bit*12+6,y+6);if a.0>200&&a.1>200&&a.2>200{frame |= 1<<bit}}}
 var offsets:[Double]=[];var oneSided=0;var inspected=0
 for y in stride(from:350,to:min(h-400,1900),by:4){
  var spans:[(Int,Int)]=[];var first:Int?
  for x in 0..<w {let a=color(x,y);let red=a.0>245&&a.1<10&&a.2<10
   if red&&first==nil{first=x};if !red,let begin=first{spans.append((begin,x-1));first=nil}
  }
  for (a,b) in spans where (10...23).contains(b-a+1) {
   var left:[Int]=[],right:[Int]=[]
   for x in max(0,a-40)..<min(w,b+41){let pixel=color(x,y);if pixel.0<10&&pixel.1>210&&pixel.2<10{if x<a{left.append(x)};if x>b{right.append(x)}}}
   guard !left.isEmpty || !right.isEmpty else{continue};inspected+=1
   if let l=left.min(),let r=right.max(),r-l<50 {offsets.append(Double(a+b-l-r)/2)}else{oneSided+=1}
  }
 }
 let sorted=offsets.map(abs).sorted();let p95=sorted.isEmpty ? -1:sorted[Int(Double(sorted.count-1)*0.95)]
 print(URL(fileURLWithPath:file).lastPathComponent,"decoded displayed frame",frame,"inspected row sections",inspected,"two-flank centers",offsets.count,"one-sided",oneSided,"red/native center p95 device pixels",p95,"max",sorted.last ?? -1)
}
'''

if len(sys.argv) < 2:
    raise SystemExit("usage: inspect-independent-rail-raster.py original-screenshot.png [...]")
with tempfile.TemporaryDirectory(prefix="jtm-raster-inspection-") as temporary:
    folder = Path(temporary)
    source = folder / "Inspect.swift"
    source.write_text(swift_source)
    executable = folder / "inspect"
    subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(folder / "modules"),
                    str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable), *sys.argv[1:]], check=True)
