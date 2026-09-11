import tempfile
from pathlib import Path
import unittest
from PIL import Image
import tifffile
from merge_rail import geotiff,frame,mercator

class MosaicTests(unittest.TestCase):
    def test_camera_offset_is_removed_from_recorded_requested_coordinate(self):
        row={'id':'x','file':'x.png','requested_coordinate':[0,0], 'tile':{'lat':0,'lon':0},'scale':{'meters_per_pixel':2}}
        node=frame(row,(400,300),(20,10))
        self.assertAlmostEqual((node['left']+node['right'])/2,-40)
        self.assertAlmostEqual((node['top']+node['bottom'])/2,20)

    def test_geotiff_stitches_crop_overlap_and_transparent_gaps(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for name,color in [('a.png','red'),('b.png','blue')]:
                Image.new('RGB',(8,8),color).save(root/name)
            def node(name,x):return {'file':name,'x':x,'y':0,'width':4,'height':4,'crop':{'left':2,'top':2,'width':4,'height':4}}
            dest=root/'out.tif'
            geotiff([node('a.png',0),node('b.png',2)],8,4,100,200,2,root,dest)
            with tifffile.TiffFile(dest) as tif:
                a=tif.asarray()
                self.assertEqual(tuple(a[1,0]),(255,0,0,255))
                self.assertEqual(tuple(a[1,3]),(0,0,255,255))
                self.assertEqual(tuple(a[1,7]),(0,0,0,0))
                self.assertEqual(tif.pages[0].tags[33550].value,(2,2,0))
                self.assertEqual(tif.pages[0].tags[33922].value,(0,0,0,100,200,0))

if __name__=='__main__':unittest.main()
