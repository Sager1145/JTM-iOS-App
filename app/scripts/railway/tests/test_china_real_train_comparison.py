import importlib.util
from pathlib import Path
import unittest


SPEC=importlib.util.spec_from_file_location('real_train_comparison',
    Path(__file__).resolve().parents[1]/'summarize-china-real-train-comparison.py')
METRICS=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(METRICS)


class RealTrainMetricTests(unittest.TestCase):
    def test_separate_parts_never_create_an_imaginary_bridge_for_stop_screening(self):
        parts=[[[110,30],[110.1,30]],[[110.9,30],[111,30]]]
        self.assertGreater(METRICS.station_distance([110.5,30],parts),38000)
        self.assertLess(METRICS.station_distance([110.05,30],parts),0.001)

    def test_geodesic_lengths_use_same_units_and_are_direction_independent(self):
        part=[[110,0],[111,0]]
        self.assertAlmostEqual(METRICS.length([part]),111.19508,places=4)
        self.assertEqual(METRICS.length([part]),METRICS.length([part[::-1]]))

    def test_unperformed_stop_screen_is_blank_in_csv(self):
        measured={'stopScreen':{'fartherThan2Km':[],'checked':2,'unreferenced':[{}]}}
        self.assertEqual(METRICS.csv_screen_counts({},measured),[None,0,None,2,None,1])

    def test_missing_geometry_is_not_zero_distance_to_a_real_stop(self):
        self.assertEqual(METRICS.station_distance([110,30],[]),float('inf'))

    def comparison(self,forced_changes=None):
        coordinates=[[110,30],[110.1,30]]
        case={'id':'real','trainNumber':'G1','trainNo':'internal','completeness':'full',
              'sourceURLs':['https://example.test/retained-official-response'],
              'observedStops':[{'name':name,'code':None} for name in ['A','B','C']]}
        original={'cases':[{'id':'real','modes':{
            mode:{'allLegsOk':True,'legs':[{'ok':True,'geometry':{'coordinates':coordinates}}
                                         for _ in range(expected)]}
            for mode,expected in [('endpoint-only',1),('forced-known-stops',2)]}}]}
        native={'phase':'completed','rows':[]}
        for mode,expected in [('endpoint-only',1),('forced-known-stops',2)]:
            row={'id':'real-'+mode,'expectedSectionCount':expected,'resolvedSectionCount':expected,
                 'indicesAreAuthoritative':True,'physicalGaps':[],'unresolvedSections':[],
                 'status':'fixture','parts':[{'sectionIndex':index,'sourceCoordinates':coordinates}
                                           for index in range(expected)]}
            if mode=='forced-known-stops':
                row['parts'].insert(1,{'sectionIndex':0,'sourceCoordinates':coordinates})
                row.update(forced_changes or {})
            native['rows'].append(row)
        return METRICS.summarize([case],original,native,{'lines':[]},{'byLine':{}})

    def test_multipart_geometry_counts_once_and_physical_gaps_do_not_subtract_geometry(self):
        for entry_count in [1,2]:
            with self.subTest(entry_count=entry_count):
                result=self.comparison({'resolvedSectionCount':1,
                    'physicalGaps':[{'segmentIndex':1,'isBoundary':True} for _ in range(entry_count)]})
                row=result['rows'][1]['railmap']
                self.assertEqual(row['returnedGeometrySections'],2)
                self.assertEqual(row['resolvedSections'],1)
                self.assertEqual(row['physicalGapEntries'],entry_count)
                self.assertEqual(row['unassignedGeometryParts'],0)
                self.assertFalse(row['complete'])
                summary=result['summary']['forced-known-stops']
                self.assertEqual(summary['railmap']['returnedGeometrySections'],2)
                self.assertEqual(summary['railmap']['physicalGapEntries'],entry_count)
                self.assertIsNone(summary['original']['physicalGapEntries'])
                self.assertIsNone(summary['original']['physicalGapEntriesKnownSubtotal'])

    def test_nonauthoritative_parts_leave_section_coverage_unknown(self):
        result=self.comparison({'indicesAreAuthoritative':False,'resolvedSectionCount':None})
        row=result['rows'][1]['railmap']
        self.assertIsNone(row['returnedGeometrySections'])
        self.assertEqual(row['unassignedGeometryParts'],3)
        self.assertFalse(row['complete'])
        summary=result['summary']['forced-known-stops']['railmap']
        self.assertIsNone(summary['returnedGeometrySections'])
        self.assertIsNone(summary['returnedGeometrySectionsKnownSubtotal'])
        self.assertEqual(summary['returnedGeometrySectionsUnknownCases'],1)
        self.assertIsNone(summary['resolvedSections'])

    def test_reported_resolution_cannot_replace_authoritative_geometry_coverage(self):
        coordinates=[[110,30],[110.1,30]]
        for invalid_index in [None,-1,2,True,'1']:
            with self.subTest(invalid_index=invalid_index):
                result=self.comparison({'parts':[
                    {'sectionIndex':0,'sourceCoordinates':coordinates},
                    {'sectionIndex':0,'sourceCoordinates':coordinates},
                    {'sectionIndex':invalid_index,'sourceCoordinates':coordinates}]})
                row=result['rows'][1]['railmap']
                self.assertEqual(row['resolvedSections'],2)
                self.assertEqual(row['returnedGeometrySections'],1)
                self.assertEqual(row['unassignedGeometryParts'],1)
                self.assertFalse(row['complete'])


if __name__=='__main__':unittest.main()
