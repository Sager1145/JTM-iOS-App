#!/usr/bin/env python3
"""Reviewed operator identity and historical boundary evidence, without trips."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'app/data/train-service-history'


def write(relative, rows):
    path=BASE / relative
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(''.join(json.dumps(r,ensure_ascii=False,sort_keys=True)+'\n' for r in rows))


def main():
    sources, operators, facts=[] ,[],[]
    for operator,legal,url in [
        ('jr-hokkaido','北海道旅客鉄道','https://www.jrhokkaido.co.jp/corporate/company/comtop.html'),
        ('jr-east','東日本旅客鉄道','https://www.jreast.co.jp/company/outline/'),
        ('jr-central','東海旅客鉄道','https://company.jr-central.co.jp/company/outline/'),
        ('jr-west','西日本旅客鉄道','https://www.westjr.co.jp/company/info/outline/'),
        ('jr-shikoku','四国旅客鉄道','https://www.jr-shikoku.co.jp/04_company/brochure/corporate_profile.pdf'),
        ('jr-kyushu','九州旅客鉄道','https://www.jrkyushu.co.jp/company/info/outline/')]:
        source_id=operator+'.corporate-identity'
        sources.append(dict(source_id=source_id,publisher=legal+'株式会社',title='会社概要',
            source_type='official_corporate_profile',url_or_locator=url,
            accessed_at='2026-09-27T19:36:14Z',license_status='unknown',redistribution_status='factual_metadata',
            automated_extraction_allowed=False,notes='Official legal name and establishment date; not timetable inventory evidence.'))
        operators.append(dict(operator_id=operator,legal_name=legal+'株式会社',display_name=legal,
            operator_type='jr_passenger',valid_from='1987-04-01',valid_until=None))
        for field in ['legal_name','valid_from']:
            facts.append(dict(entity_type='operator',entity_id=operator,field_name=field,source_id=source_id,
                page_or_locator='会社概要 設立 / 名称',confidence='high',verification_status='verified'))
    write('sources/source-registry-operators.jsonl',sources)
    write('normalized/operators-root.jsonl',operators)
    history=json.loads((BASE / 'sources/candidates/historical-limited-express-boundaries.json').read_text())
    service_id='ancestral-special-express-shinbashi-shimonoseki-1912'
    write('normalized/services-ancestral.jsonl',[dict(service_id=service_id,
        canonical_name='特別急行（新橋〜下関・1912年）',service_class='limited_express',historical_generation=1,
        first_verified_date=history['first_limited_express']['verified_date'],jr_scope='jr_ancestral')])
    facts.extend(dict(entity_type='service',entity_id=service_id,field_name=field,
        source_id='railway-museum-era-change-exhibit-20190227',page_or_locator='p1 時刻表 / 新橋下関間汽車時刻表',
        confidence='high',verification_status='verified') for field in ['first_verified_date','origin_destination'])
    zero=history['conservative_verified_zero_service_interval']
    write('normalized/verified-zero-service-intervals-root.jsonl',[dict(
        interval_id=zero['interval_id'],operator_scope=zero['operator_scope'],valid_from=zero['valid_from'],
        valid_until=zero['valid_until'],reason=zero['reason'],source_id=zero['source_ids'][0])])
    facts.extend(dict(entity_type='zero_service_interval',entity_id=zero['interval_id'],
        field_name='conservative_absence_bounds',source_id=sid,page_or_locator='Historical abolition/restoration explanation',
        confidence='medium',verification_status='verified') for sid in zero['source_ids'])
    write('normalized/fact-sources-operators-history.jsonl',facts)
    write('normalized/fact-completeness-ancestral.jsonl',[
        dict(entity_type='service',entity_id=service_id,dimension=d,status='partial' if d=='identity' else 'unknown',
             confidence='low',notes='Inventory-only evidence; source does not establish trip templates or all daily applicability.')
        for d in ['identity','train_number','operator','validity_calendar','stops','times','route_lines','station_refs']])
    queue=[
        dict(research_id=service_id+'.timetable',entity_type='service',entity_id=service_id,
             missing_dimension='timetable_issue',status='open',notes='Obtain original 1912-06-15 revised timetable; do not map historical Shinbashi to the modern station by name.'),
        dict(research_id='national-zero.exact-boundaries',entity_type='zero_service_interval',entity_id=zero['interval_id'],
             missing_dimension='source',status='open',notes='Conservative month bounds verified; original April 1944/September 1949 issues needed for exact abolition/restoration dates.')]
    queue.extend(dict(research_id=service_id+'.'+dimension,entity_type='service',entity_id=service_id,
        missing_dimension=dimension,status='open',notes='Original timetable and historical identity/topology evidence required.')
        for dimension in ['train_number','operator','validity_calendar','stops','times','route_lines','station_refs'])
    write('normalized/research-queue-ancestral.jsonl',queue)
    print('Six JR legal operator identities, one partial ancestral service and conservative zero interval normalized')


if __name__ == '__main__': main()
