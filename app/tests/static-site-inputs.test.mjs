import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

test('retained static builder assembles registered inputs without the retired backend',async()=>{
  const {buildStaticSite,DATASET_NAMES}=await import('../scripts/build/build-static-site.mjs');
  const {PART_DATASETS}=await import('../shared/artifact-inputs.js');
  const scratch=await fs.mkdtemp(path.join(os.tmpdir(),'jtm-static-inputs-'));
  try{
    const appDir=path.join(scratch,'app'),outputDir=path.join(scratch,'site');
    await fs.mkdir(path.join(appDir,'public'),{recursive:true});await fs.mkdir(path.join(appDir,'shared'),{recursive:true});await fs.mkdir(path.join(appDir,'data'),{recursive:true});
    await fs.writeFile(path.join(appDir,'public','index.html'),'<script src="runtime-config.js"></script>');
    await fs.writeFile(path.join(appDir,'shared','app-core.js'),'window.AppCore={};');
    for(const name of DATASET_NAMES)await fs.writeFile(path.join(appDir,'data',name+'.json'),JSON.stringify({input:name}));
    for(const dataset of PART_DATASETS){const dir=path.join(appDir,'data',dataset.dir);await fs.mkdir(dir,{recursive:true});await fs.writeFile(path.join(dir,'manifest.json'),JSON.stringify({parts:['part-000']}));await fs.writeFile(path.join(dir,'part-000.json'),'{"train":{"id":"fixture"}}');}
    await buildStaticSite({appDir,outputDir,logger:{log(){}}});
    assert.deepEqual(JSON.parse(await fs.readFile(path.join(outputDir,'api','physical-rail-junctions.json'),'utf8')),{input:'physical-rail-junctions'});
    assert.equal(JSON.parse(await fs.readFile(path.join(outputDir,'api','sample-data-kr','part-000.json'),'utf8')).train.id,'fixture');
    assert.match(await fs.readFile(path.join(outputDir,'runtime-config.js'),'utf8'),/hasBackend: false/);
    assert.deepEqual(JSON.parse(await fs.readFile(path.join(outputDir,'api','stations-cn.json'),'utf8')),{input:'stations-cn'});
    assert.ok(!PART_DATASETS.some(dataset=>dataset.dir==='sample-data-cn'));
    assert.ok(!DATASET_NAMES.some(name=>/(?:^|-)(us|ca)(?:-|$)/.test(name)));
  }finally{await fs.rm(scratch,{recursive:true,force:true})}
});
