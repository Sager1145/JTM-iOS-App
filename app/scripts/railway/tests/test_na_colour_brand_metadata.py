import importlib.util
import json
import os
import unittest


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


class ColourBrandMetadataTests(unittest.TestCase):


    def test_houston_and_airport_mac_are_explicitly_audited_unbranded(self):
        with open(os.path.join(ROOT, 'na-operator-brands.json'),
                  encoding='utf-8') as source:
            unbranded = json.load(source)['unbranded']
        self.assertIn('houston-metro', unbranded)
        self.assertIn('metro-transit', unbranded)
        self.assertIn('METRO', unbranded['houston-metro']['operator'])
        self.assertIn('Airport', unbranded['metro-transit']['operator'])


if __name__ == '__main__':
    unittest.main()
