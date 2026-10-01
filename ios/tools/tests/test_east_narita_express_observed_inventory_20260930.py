"""Close the observed NEX set without asserting unseen entrances are exhaustive."""
import json,sys,unittest
from pathlib import Path
TOOLS=Path(__file__).resolve().parents[1];sys.path.insert(0,str(TOOLS))
import train_timetable as timetable
BASE=Path(__file__).resolve().parents[3]/'app/data/train-service-history'
class ObservedInventoryTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.inventory=json.loads((BASE/'audits/jr-east-narita-express-observed-20260930-inventory.json').read_text())
  cls.data,_=timetable.load_dataset(BASE,timetable.load_manifest(BASE))
 def test_all_observed_numbers_columns_and_source_urls(self):
  proven={r['public_number']:r for r in self.inventory['trains'] if r['scheduled_on_date']}
  self.assertEqual(len(proven),54)
  day=[r for r in timetable.materialize(self.data,'2026-09-30') if r['service_id']=='narita-express']
  self.assertEqual({r['public_number'] for r in day},set(proven))
  sources={r['source_id']:r['url_or_locator'] for r in self.data['source_documents']}
  for n,e in proven.items():
   self.assertEqual(e['date_evidence'],{'month':'2026年9月','day':30,'cell_class':'ok'})
   trips=[r for r in day if r['public_number']==n]
   tids={r['trip_id'] for r in trips}
   columns={r['train_number'] for r in trips}
   columns.update(r['train_number'] for r in self.data['trip_number_segments'] if r['trip_id'] in tids)
   self.assertEqual(columns,set(e['printed_train_numbers']))
   self.assertEqual(len(trips),2 if e['column_relationship']=='coupled_branches' else 1)
   for t in trips:
    self.assertTrue(t['stop_times'])
    self.assertTrue(all(sources[s['source_id']]==e['source_url'] for s in t['stop_times']))
   candidate=json.loads((BASE/f'candidates/jr-east-narita-express{n}-20260930.json').read_text())
   self.assertEqual(candidate['source_url'],e['source_url'])
 def test_nonrunning_variants_not_promoted(self):
  rejected=[r for r in self.inventory['trains'] if not r['scheduled_on_date']]
  self.assertEqual(len(rejected),5)
  self.assertEqual({r['public_number'] for r in rejected},{'46','48','50','52','54'})
  for r in rejected:self.assertEqual(r['date_evidence']['cell_class'],'none')
  rejected_urls={r['source_url'] for r in rejected}
  source_urls={r['url_or_locator'] for r in self.data['source_documents'] if r['source_id'].startswith('jr-east-narita-express')}
  self.assertFalse(source_urls & rejected_urls)
if __name__=='__main__':unittest.main()
