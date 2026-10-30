import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {isAllowedCandidateDirectory,assertAllowedCandidateDirectory,assertAllowedCandidateFile} from '../local-evidence-path.mjs';
const REPO=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../..');

const EXTERNAL_VOLUME='/Volumes/JTM Evidence';
const EXTERNAL_ROOT=path.join(EXTERNAL_VOLUME,'99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local');

test('candidate writes accept mounted external evidence and explicit scratch, never new mixed-checkout paths',()=>{
  assert.equal(isAllowedCandidateDirectory(path.join(EXTERNAL_ROOT,'candidates/new-candidate')),true);
  assert.equal(isAllowedCandidateDirectory(path.join(REPO,'railway-evidence/local/__new-unmigrated-routing-test')),false);
  assert.equal(isAllowedCandidateDirectory('/private/tmp/new-railway-candidate'),true);
  for(const candidate of ['/private/tmp-collision/candidate',path.join(REPO,'railway-evidence/local-other/candidate'),path.join(REPO,'app/public/rail/candidate')]){
    assert.equal(isAllowedCandidateDirectory(candidate),false);
    assert.throws(()=>assertAllowedCandidateDirectory(candidate),/Candidate directory/);
  }
});

test('candidate paths follow migrated legacy aliases but reject symlink escapes and files',()=>{
  const root=fs.mkdtempSync('/private/tmp/jtm-evidence-path-test-');
  try{
    fs.symlinkSync(EXTERNAL_ROOT,path.join(root,'migrated'),'dir');
    assert.equal(isAllowedCandidateDirectory(path.join(root,'migrated/candidate-new/child')),true);
    fs.symlinkSync(path.join(REPO,'app/public/rail'),path.join(root,'escape'),'dir');
    assert.equal(isAllowedCandidateDirectory(path.join(root,'escape/candidate-new/child')),false);
    fs.symlinkSync(path.join(root,'missing-target'),path.join(root,'dangling'),'dir');
    assert.equal(isAllowedCandidateDirectory(path.join(root,'dangling/child')),false);
    fs.writeFileSync(path.join(root,'file'),'fixture');
    assert.equal(isAllowedCandidateDirectory(path.join(root,'file')),false);
    assert.equal(isAllowedCandidateDirectory(path.join(root,'file/child')),false);
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});

test('JSON output paths support existing files and migrated aliases without allowing escaping file links',()=>{
  const root=fs.mkdtempSync('/private/tmp/jtm-evidence-path-test-');
  try{
    const file=path.join(root,'candidate.json');
    fs.writeFileSync(file,'fixture');
    assert.doesNotThrow(()=>assertAllowedCandidateFile(file));
    assert.doesNotThrow(()=>assertAllowedCandidateFile(path.join(root,'new/candidate.json')));
    assert.doesNotThrow(()=>assertAllowedCandidateFile(path.join(EXTERNAL_ROOT,'new/candidate.json')));
    fs.symlinkSync(file,path.join(root,'same-root-link.json'),'file');
    assert.throws(()=>assertAllowedCandidateFile(path.join(root,'same-root-link.json')),/Candidate file/);
    assert.doesNotThrow(()=>assertAllowedCandidateDirectory(root.replace('/private/tmp/','/tmp/')));
    fs.symlinkSync(path.join(REPO,'app/package.json'),path.join(root,'escape.json'),'file');
    assert.throws(()=>assertAllowedCandidateFile(path.join(root,'escape.json')),/Candidate file/);
    assert.throws(()=>assertAllowedCandidateFile(root),/Candidate file/);
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});

test('an unavailable external mount cannot turn into a local fallback',()=>{
  const original=fs.statSync;
  try{
    fs.statSync=function(target,...args){if(String(target)===EXTERNAL_VOLUME)throw Object.assign(new Error('unmounted'),{code:'ENOENT'});return original.call(this,target,...args);};
    assert.equal(isAllowedCandidateDirectory(path.join(EXTERNAL_ROOT,'new/candidate')),false);
    assert.equal(isAllowedCandidateDirectory('/private/tmp/explicit-routing-test'),true);
  }finally{fs.statSync=original;}
});
