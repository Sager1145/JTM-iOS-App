#!/usr/bin/env python3
"""Index reviewed web discoveries and their restrictions; does not crawl sources."""
from train_timetable import DEFAULT_CANONICAL, load_manifest, load_dataset, write_json


def main():
    data,_=load_dataset(DEFAULT_CANONICAL,load_manifest(DEFAULT_CANONICAL))
    rows=[dict(sourceId=s['source_id'],publisher=s['publisher'],title=s['title'],
               locator=s['url_or_locator'],sourceType=s['source_type'],
               automatedExtractionAllowed=s['automated_extraction_allowed'],
               licenseStatus=s['license_status'],redistributionStatus=s['redistribution_status'])
          for s in data['source_documents']]
    output=DEFAULT_CANONICAL/'audits/source-inventory.json'
    write_json(output,dict(sourceCount=len(rows),inventoryComplete=False,
        method='Curated official web search and archive guide discoveries; no complete timetable inventory inferred.',sources=rows))
    print(f'Indexed {len(rows)} researched sources; all-service discovery remains incomplete')


if __name__=='__main__': main()
