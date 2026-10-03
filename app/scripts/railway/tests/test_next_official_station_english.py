#!/usr/bin/env python3
"""Boundary checks for the portable JP/KR source gate."""
from pathlib import Path
import copy, importlib.util, json, unittest
spec=importlib.util.spec_from_file_location('gate',Path(__file__).resolve().parents[1] / 'verify-next-official-station-english.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
class GateTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  # An existing but incomplete archive must still fail its original checks.
  if not g.BASE.exists():
      raise unittest.SkipTest("本地官方原始证据未提供: " + str(g.BASE))
  cls.result=g.regenerate();cls.packages={c:g.load(g.APP/f'public/rail/{c}-2025.json') for c in ('jp','kr')}
 def mutation(self,changes):
  rows=copy.deepcopy(self.result['byLineStation']);key=next(iter(rows));rows[key].update(changes)
  with self.assertRaises(ValueError):g.validate_rows(rows,self.packages)
 def test_exact_count(self):self.assertEqual(len(self.result['byLineStation']),1310);self.assertEqual(len(self.result['coverage']['byCohort']),13)
 def test_wrong_operator(self):self.mutation({'operator':'OTHER OPERATOR'})
 def test_wrong_native(self):self.mutation({'name':'WRONG NATIVE'})
 def test_wrong_membership(self):self.mutation({'stationCode':'unknown'})
 def test_unknown_country(self):self.mutation({'country':'us'})
 def test_duplicate_current_membership(self):
  packages=copy.deepcopy(self.packages);line=packages['jp']['lines'][0];line['stations'].append(line['stations'][0])
  with self.assertRaisesRegex(ValueError,'duplicate current'):g.validate_rows(self.result['byLineStation'],packages)
 def test_unknown_evidence(self):
  rows=copy.deepcopy(self.result['byLineStation']);rows['unknown:unknown']=copy.deepcopy(next(iter(rows.values())))
  with self.assertRaises(ValueError):g.validate_rows(rows,self.packages)
 def test_stale_raw_source(self):
  path=g.BASE/'keikyu/directory-ja.html';old=path.read_bytes()
  try:
   path.write_bytes(old+b'\nMUTATION')
   with self.assertRaisesRegex(ValueError,'hash mismatch'):g.retained()
  finally:path.write_bytes(old)
 def test_wrong_registration(self):
  path=g.BASE/'cohorts.json';manifest=g.BASE/'retained-input-manifest.json';old=path.read_bytes();oldm=manifest.read_bytes()
  try:
   rows=g.load(path);rows['us']='verify_us_tail.py';path.write_text(g.encode(rows));m=g.load(manifest);m['files']['cohorts.json']=g.digest(path);manifest.write_text(g.encode(m))
   with self.assertRaisesRegex(ValueError,'registration'):g.retained()
  finally:path.write_bytes(old);manifest.write_bytes(oldm)
 def test_unreviewed_future_membership_stays_pending(self):
  path=g.APP/'public/rail/jp-2025.json';old=path.read_bytes()
  try:
   pkg=g.load(path);pkg['lines'][0]['stations'].append(['future-unreviewed','Future Native',139.0,35.0]);path.write_text(g.encode(pkg))
   result=g.regenerate();self.assertEqual(result['byLineStation'],self.result['byLineStation'])
  finally:path.write_bytes(old)
 def test_every_raw_reference_is_durable(self):
  def walk(v):
   if isinstance(v,list):
    for a in v:walk(a)
   elif isinstance(v,dict):
    if 'rawFile' in v:
     p=g.APP/v['rawRoot']/v['rawFile'];self.assertTrue(p.is_file(),str(p))
     if 'sha256' in v:self.assertEqual(g.digest(p),v['sha256'])
    for a in v.values():walk(a)
  walk(self.result)
if __name__=='__main__':unittest.main(verbosity=2)
