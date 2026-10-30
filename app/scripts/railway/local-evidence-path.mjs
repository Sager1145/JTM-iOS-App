import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const EXTERNAL_VOLUME = '/Volumes/JTM Evidence';
const EXTERNAL_ROOT = path.join(EXTERNAL_VOLUME, '99 Compatibility/Workspace/JTM-iOS-App/railway-evidence/local');
const SCRATCH_ROOT = '/private/tmp';
// Checkout paths are compatibility aliases only; their resolved outputs must
// reach the mounted external archive, never a new file in the mixed checkout.
const ROOTS = [SCRATCH_ROOT, EXTERNAL_ROOT];
const LEGACY_ROOT = path.join(REPO, 'railway-evidence/local');
function externalDevice() {
  try {
    const device = fs.statSync(EXTERNAL_VOLUME).dev;
    return device !== fs.statSync(path.dirname(EXTERNAL_VOLUME)).dev ? device : null;
  } catch { return null; }
}
const inside = (root, target) => {
  const relative = path.relative(root, target);
  return relative !== '' && relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
};

// Resolve existing ancestors: outputs may not exist, and migrated scratch aliases
// may resolve into the mounted external evidence archive. Dangling links are never missing outputs.
function allowed(candidate, directory) {
  if (typeof candidate !== 'string' || !path.isAbsolute(candidate)) return false;
  const target = path.resolve(candidate);
  if (![...ROOTS, LEGACY_ROOT, '/tmp'].some(root => inside(root, target))) return false;
  let ancestor = target;
  const missing = [];
  try {
    while (true) {
      try {
        const entry = fs.lstatSync(ancestor);
        if (!directory && !missing.length && entry.isSymbolicLink()) return false;
        break;
      } catch (error) {
        if (error.code !== 'ENOENT') return false;
        missing.unshift(path.basename(ancestor));
        const parent = path.dirname(ancestor);
        if (parent === ancestor) return false;
        ancestor = parent;
      }
    }
    const resolved = fs.realpathSync(ancestor);
    const stat = fs.statSync(ancestor);
    if ((missing.length || directory) && !stat.isDirectory()) return false;
    if (!directory && !missing.length && !stat.isFile()) return false;
    const actual = path.join(resolved, ...missing);
    if (inside(SCRATCH_ROOT, actual)) return true;
    const device = externalDevice();
    return inside(EXTERNAL_ROOT, actual) && device !== null && stat.dev === device;
  } catch {
    return false;
  }
}

export const isAllowedCandidateDirectory = candidate => allowed(candidate, true);
export const assertAllowedCandidateDirectory = candidate => assert(
  isAllowedCandidateDirectory(candidate), 'Candidate directory must remain inside mounted external evidence or private scratch');
export const assertAllowedCandidateFile = candidate => assert(
  allowed(candidate, false), 'Candidate file must remain inside mounted external evidence or private scratch');
