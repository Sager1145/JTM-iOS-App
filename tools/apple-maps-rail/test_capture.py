import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image,ImageDraw
from capture import NativeMaps

class ScaleTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.native=NativeMaps.__new__(NativeMaps)
        self.native.out=Path(self.tmp.name);self.native.helper='unused-helper'
        self.im=Image.new('RGB',(2500,1300),(20,30,45))
        # Bar midpoint is x1250; first 125 m segment is 44 px wide.
        ImageDraw.Draw(self.im).rectangle((1206,66,1249,69),fill=(135,147,170))
    def test_measures_filled_bar_when_final_number_merged_with_unit(self):
        # OCR numeral center x1250, translated to the crop (left975,width550).
        result=[{'text':'125','words':[{'text':'125','box':[(1250-975-10)/550,25/70,20/550,12/70]}]}]
        with patch('capture.run',return_value=json.dumps(result)):
            scale=self.native.scale(self.im)
        self.assertAlmostEqual(scale['meters_per_pixel'],125/44)
        self.assertEqual(scale['method'],'OCR tick + measured scale segment')
    def test_fails_closed_on_missing_scale(self):
        with patch('capture.run',return_value='[]'):
            with self.assertRaisesRegex(RuntimeError,'Cannot read metric'):
                self.native.scale(self.im)
    def test_rejects_imperial_scale(self):
        with patch('capture.run',return_value=json.dumps([{'text':'250 ft','words':[]}])):
            with self.assertRaisesRegex(RuntimeError,'not in metres'):
                self.native.scale(self.im)

if __name__=='__main__':unittest.main()

class BatchRecoveryTests(unittest.TestCase):
    def setUp(self):
        import argparse
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.out=Path(self.tmp.name)
        self.tiles=[{'id':'a','city':'toronto','country':'CA','lat':43.7,'lon':-79.4,'rail_lines':[]}]
        config={'latitude':43.7,'zoom':16.3,'target_meters_per_pixel':2.87,'image_size':[400,300],'coordinate_alignment_verified':True,'coordinate_offset_pixels':[0,0]}
        (self.out/'plan.json').write_text(json.dumps({'calibration':config,'tiles':self.tiles}))
        self.args=argparse.Namespace(out=self.out,limit=None,retries=1,one_per_city=False)
    def valid_capture(self,*args,**kwargs):
        # A real decodable image is created just as the native snapshotter does.
        im=Image.new('RGB',(400,300),(20,45,65));im.save(args[-1])
        return 16.3,{'elements':[]},im,{'meters_per_pixel':2.87}
    def test_transient_tile_failure_retries_then_resumes_without_recapture(self):
        from capture import capture,TileCaptureError
        attempts=[]
        def attempt(*args,**kwargs):
            attempts.append(1)
            if len(attempts)==1:raise TileCaptureError('temporary loading failure')
            return self.valid_capture(*args)
        with patch('capture.NativeMaps') as native,patch('capture.calibrate',side_effect=attempt),patch('classify.classify_image',return_value={'label':'no_rail','needs_review':True}):
            native.return_value.session.return_value={'locked':False}
            capture(self.args)
            capture(self.args)
        self.assertEqual(len(attempts),2)
        self.assertEqual(len((self.out/'manifest.jsonl').read_text().splitlines()),1)
        self.assertEqual(json.loads((self.out/'status.json').read_text())['state'],'complete')
    def test_unvalidated_tile_is_not_sorted_or_marked_complete(self):
        from capture import capture,TileCaptureError
        with patch('capture.NativeMaps') as native,patch('capture.calibrate',side_effect=TileCaptureError('unreadable scale')),patch('classify.classify_image') as classify:
            native.return_value.session.return_value={'locked':False}
            with self.assertRaisesRegex(RuntimeError,'tiles failed validation'):capture(self.args)
        classify.assert_not_called()
        self.assertFalse((self.out/'manifest.jsonl').exists())
        failure=json.loads((self.out/'failures.jsonl').read_text())
        self.assertEqual(failure['attempts'],2)
        self.assertEqual(json.loads((self.out/'status.json').read_text())['state'],'failed')

    def test_preflight_checks_secondary_city_membership_near_each_city(self):
        from capture import capture
        plan=json.loads((self.out/'plan.json').read_text())
        plan['tiles']=[{**self.tiles[0],'lat':43.7,'lon':-79.4,'cities':['toronto','kitchener_waterloo']},
                       {**self.tiles[0],'lat':43.45,'lon':-80.49,'cities':['toronto','kitchener_waterloo']}]
        (self.out/'plan.json').write_text(json.dumps(plan))
        self.args.one_per_city=True
        def frame(*args,**kwargs):
            im=Image.new('RGB',(400,300),(int(args[1]*100)%255,45,65));im.save(args[-1])
            return 16.3,{'elements':[]},im,{'meters_per_pixel':2.87}
        with patch('capture.NativeMaps') as native,patch('capture.calibrate',side_effect=frame),patch('classify.classify_image',return_value={'label':'no_rail','needs_review':True}):
            native.return_value.session.return_value={'locked':False}
            capture(self.args)
        self.assertEqual(len((self.out/'manifest.jsonl').read_text().splitlines()),2)

class CameraAlignmentTests(unittest.TestCase):
    def test_corrects_native_sidebar_camera_offset_instead_of_shifting_coverage(self):
        import math
        from capture import camera_alignment,corrected_coordinate
        lat,lon,mpp=43.68,-79.39,2.87
        im=Image.new('RGB',(2500,1300))
        stations=[('A Station',43.69,-79.40),('B Station',43.67,-79.38),('St. C Station',43.68,-79.41)]
        elements=[]
        for name,slat,slon in stations:
            x=1250+(slon-lon)*111320*math.cos(math.radians(lat))/mpp+198
            y=650-(slat-lat)*111320/mpp-4
            elements.append({'id':'VKPointFeature','description':name.removesuffix(' Station').replace('.','')+', TTC 1','rect':[x+1500-15,y-290-15,30,30]})
        info={'window_bounds':{'X':1500,'Y':-290,'Width':2500,'Height':1300},'elements':elements}
        with patch('capture.rail_stations',return_value=stations):result=camera_alignment(info,im,lat,lon,mpp)
        self.assertAlmostEqual(result['residual_offset_pixels'][0],198)
        self.assertAlmostEqual(result['residual_offset_pixels'][1],-4)
        requested=corrected_coordinate(lat,lon,mpp,result['residual_offset_pixels'])
        self.assertAlmostEqual((requested[1]-lon)*111320*math.cos(math.radians(lat))/mpp,198)
        self.assertAlmostEqual((requested[0]-lat)*111320/mpp,4)
    def test_locked_mac_never_receives_map_navigation(self):
        from capture import ScreenLockedError
        native=NativeMaps.__new__(NativeMaps)
        with patch.object(native,'session',return_value={'locked':True}),patch('capture.run') as command:
            with self.assertRaises(ScreenLockedError):native.open(43.68,-79.39,16.28)
        command.assert_not_called()

    def test_temporarily_hidden_maps_window_is_reactivated(self):
        native=NativeMaps.__new__(NativeMaps);native.helper='native-helper'
        with patch.object(native,'session',return_value={'locked':False}),patch('capture.time.sleep'),patch('capture.run',side_effect=[RuntimeError('No visible Maps window'),'',json.dumps({'window_id':42})]) as command:
            self.assertEqual(native.info()['window_id'],42)
        self.assertEqual(command.call_args_list[1][0][0],'/usr/bin/osascript')

class FullWorkflowTests(unittest.TestCase):
    def test_preflight_failure_prevents_full_capture(self):
        import argparse
        from capture import all_cities
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)
            (out/'calibration.json').write_text(json.dumps({'version':2,'coordinate_alignment_verified':True}))
            with patch('capture.fetch'),patch('capture.NativeMaps') as native,patch('capture.plan'),patch('capture.audit_plan'),patch('capture.capture',side_effect=RuntimeError('preflight failed')) as capture:
                native.return_value.session.return_value={'locked':False}
                with self.assertRaisesRegex(RuntimeError,'preflight failed'):
                    all_cities(argparse.Namespace(out=out))
                self.assertEqual(capture.call_count,1)
                self.assertTrue(capture.call_args[0][0].one_per_city)
            self.assertEqual(json.loads((out/'workflow-status.json').read_text())['stage'],'failed')

    def test_locked_workflow_waits_before_probe(self):
        import argparse
        from capture import all_cities
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)
            events=[]
            with patch('capture.fetch'),patch('capture.NativeMaps') as native,patch('capture.time.sleep',side_effect=lambda seconds:events.append('wait')),patch('capture.probe',side_effect=lambda args:events.append('probe')),patch('capture.plan'),patch('capture.audit_plan'),patch('capture.capture'):
                native.return_value.session.side_effect=[{'locked':True},{'locked':False}]
                all_cities(argparse.Namespace(out=out))
            self.assertEqual(events,['wait','probe'])
            self.assertEqual(json.loads((out/'workflow-status.json').read_text())['stage'],'capture_complete')

class RenderingTests(unittest.TestCase):
    def test_sparse_rendered_land_waits_longer_than_detailed_map(self):
        native=NativeMaps.__new__(NativeMaps)
        im=Image.new('RGB',(640,400),(25,58,62))
        ImageDraw.Draw(im).rectangle((320,0,639,399),fill=(27,57,61))
        with patch.object(native,'snapshot',return_value=({},im)) as shot,patch('capture.time.sleep'),patch('capture.time.monotonic',side_effect=range(100)):
            info,_=native.settled('unused')
        self.assertGreaterEqual(shot.call_count,7)
        self.assertEqual(info['capture_validation']['stable_frames'],6)

    def test_uniform_loading_frame_is_never_accepted(self):
        from capture import TileCaptureError
        native=NativeMaps.__new__(NativeMaps)
        im=Image.new('RGB',(640,400),(25,58,62))
        with patch.object(native,'snapshot',return_value=({},im)),patch('capture.time.sleep'),patch('capture.time.monotonic',side_effect=range(100)):
            with self.assertRaises(TileCaptureError):native.settled('unused')
