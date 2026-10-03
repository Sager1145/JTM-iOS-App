"""Small synthetic identity/calendar fixtures; these are not imported railway facts."""
import copy
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent

def load(filename, name):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

IMPORT = load('import-odpt-line-services.py', 'odpt_import')
BUILD = load('build-line-service-catalog.py', 'catalog_build')

class ImportODPTTests(unittest.TestCase):
    def setUp(self):
        self.package = {'version': 'test', 'lines': [dict(id='test-line', operator='Test operator', name='Test line', stations=[['s1','One'],['s2','Two']])]}
        self.mapping = dict(railways={'rail':dict(lineIDs=['test-line'],operatorName='Test operator',scope='One–Two')},
            operators={'operator':dict(operatorName='Test operator')},
            stations={'one':dict(stationCode='s1',stationName='One'), 'two':dict(stationCode='s2',stationName='Two')},
            trainTypes={'kind':dict(displayName='普通',trainType='普通')},
            calendars={'holiday':dict(serviceDates=['2026-10-04'])})
        self.provenance = dict(validFrom='2026-10-03',validUntil='2026-10-05',observedOn='2026-10-02',sourceURL='https://example.org/licensed-export')
        self.row = {'@type':'odpt:TrainTimetable','owl:sameAs':'trip-1','odpt:railway':'rail','odpt:operator':'operator',
            'odpt:trainType':'kind','odpt:calendar':'holiday','odpt:trainNumber':'1M',
            'odpt:previousTrain':['other-operator-trip'], 'odpt:nextTrain':'trip-2',
            'odpt:trainTimetableObject':[{'odpt:departureStation':'one','odpt:departureTime':'23:58'},
                {'odpt:arrivalStation':'two','odpt:arrivalTime':'00:04','odpt:departureStation':'two','odpt:departureTime':'00:05'}]}

    def normalize(self):
        return IMPORT.normalize([self.row],self.mapping,self.provenance,self.package)

    def test_midnight_explicit_dates_and_cross_operator_links(self):
        artifact=self.normalize(); trip=artifact['trips'][0]
        self.assertEqual(trip['stops'][1]['arrivalSeconds'],86400+240)
        self.assertEqual(trip['stops'][1]['departureSeconds'],86400+300)
        self.assertEqual(trip['serviceDates'],['2026-10-04'])
        self.assertEqual(trip['previousTrainIDs'],['other-operator-trip'])
        self.assertEqual(trip['nextTrainIDs'],['trip-2'])
        self.assertEqual(trip['sourceOperatorID'],'operator')
        self.assertEqual(artifact['lines'][0]['coverage'],'partial')

    def test_no_train_number_suffix_inference(self):
        del self.row['odpt:trainType']
        with self.assertRaises(ValueError): self.normalize()

    def test_ambiguous_or_unmapped_station_rejected(self):
        self.mapping['stations']['two']=[self.mapping['stations']['two']]
        with self.assertRaises(ValueError): self.normalize()

    def test_wrong_physical_line_operator_rejected(self):
        self.package['lines'][0]['operator']='Other operator'
        with self.assertRaises(ValueError): self.normalize()

    def test_out_of_interval_calendar_rejected(self):
        self.mapping['calendars']['holiday']['serviceDates']=['2026-10-05']
        with self.assertRaises(ValueError): self.normalize()

    def test_invalid_time_rejected(self):
        self.row['odpt:trainTimetableObject'][0]['odpt:departureTime']='23:62'
        with self.assertRaises(ValueError): self.normalize()

    def test_daytime_regression_is_not_an_invented_overnight_wait(self):
        calls = self.row['odpt:trainTimetableObject']
        calls[0]['odpt:departureTime'] = '10:05'
        calls[1]['odpt:arrivalTime'] = '09:55'
        calls[1]['odpt:departureTime'] = '09:56'
        with self.assertRaises(ValueError): self.normalize()

    def test_import_rejects_duplicate_trip(self):
        with self.assertRaises(ValueError):
            IMPORT.normalize([self.row,self.row],self.mapping,self.provenance,self.package)

    def test_reviewed_overlay_merges_without_fabricating_other_lines(self):
        base=dict(schemaVersion=1,inventoryVersion='test',observedOn='2026-10-02',trips=[],lines=[
            dict(lineID='test-line',operatorName='Test operator',lineName='Test line',kinds=[],coverage='unknown',note=''),
            dict(lineID='unresearched-line',operatorName='Test operator',lineName='Unknown',kinds=[],coverage='unknown',note='')])
        result=BUILD.merge_reviewed(base,self.normalize())
        self.assertEqual(len(result['trips']),1)
        self.assertEqual(result['lines'][0]['coverage'],'partial')
        self.assertEqual(result['lines'][1]['coverage'],'unknown')
        with self.assertRaises(ValueError): BUILD.merge_reviewed(result,self.normalize())

    def test_overlay_rejects_backwards_normalized_times(self):
        overlay=self.normalize(); overlay['trips'][0]['stops'][1]['arrivalSeconds']=1
        base=dict(schemaVersion=1,inventoryVersion='test',trips=[],lines=[dict(lineID='test-line',operatorName='Test operator',kinds=[],coverage='unknown')])
        with self.assertRaises(ValueError): BUILD.merge_reviewed(base,overlay)

if __name__=='__main__': unittest.main()
