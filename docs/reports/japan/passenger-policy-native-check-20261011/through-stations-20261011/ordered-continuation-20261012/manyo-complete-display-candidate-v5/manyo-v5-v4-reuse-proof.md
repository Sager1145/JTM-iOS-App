# Manyo V5 / V4 unchanged-scope reuse proof

This comparison is limited to whether already-reviewed V4 native receipts remain applicable outside the nine changed 高岡軌道線 intervals. It does not treat the changed whole-line dependency hash as equal.

## Exact candidate/source comparison

- `jp-万葉線-新湊港線`: all seven interval arrays are byte-for-byte JSON-equal between the V4 and V5 candidate inputs; all eight display-station aliases are equal. Rebuilding its sole native row produces the same 746 points, 4895.7 m and SHA-256 `db451d667dbe50d991d31dc2af7e87ab16531473ef4a01a10f4c63e38057f067` in both versions.
- `jp-万葉線-高岡軌道線`: candidate intervals `0,1,2,3,4,9,15,16` are exactly equal. The remaining nine (`5,6,7,8,10,11,12,13,14`) are the changed set. Of 18 station aliases, exactly five changed: `001826`, `001834`, `001845`, `001851`, `001861`; every other alias is equal.
- The reconstructed 高岡 native rows differ globally (V4: 1625 points, 8001.5 m, SHA-256 `ff853b835b1eb018d199561f6f27417d30e69b9e178310d258785528ea341f62`; V5: 1672 points, 8003.6 m, SHA-256 `885672ad499dc9f2a55bbb368e4180c392ce9c29acd5659c5357d91af76c1d71`). Slicing each row by the exact interval endpoint anchors shows identical geographic native samples for every unchanged interval: #0 132/132, #1 218/218, #2 191/191, #3 127/127, #4 267/267, #9 158/158, #15 71/71, #16 112/112. Thus native grooming did not change outside the nine changed interval supports.

## Actual V4 receipt inventory

- 新湊港線 V4: 23 views: `#0=3, #1=4, #2=3, #3=3, #4=4, #5=3, #6=3`; dependency `2bfbf65fb21d4912de484c6a6dc45ec4a84b50ae82aef72480560ffe51aade38`.
- 高岡軌道線 V4: 50 views: `#0=3, #1=4, #2=4, #3=3, #4=4, #5=3, #6=3, #7=3, #8=2, #9=3, #10=2, #11=3, #12=3, #13=3, #14=2, #15=2, #16=3`; dependency `984f76db9ce0aa3646ced7f35a2ce722b6f748ded5a803ff79b838053ad82568`.

The V4 receipts reusable for unchanged geometry total 49 views: all 23 新湊港線 views plus 26 高岡 views from intervals `0,1,2,3,4,9,15,16`. Replacing the V4 changed-set 24 views with the actual V5 changed-set 23 views yields a 72-view complete candidate scope.

The V4 and V5 native plans use the same fixed compare rendering contract and camera style (1024×768, scale 1, z17, heading 0, pitch 0, opacity 1, evidence opacity 1, evidence width 1.5). Their whole-plan filenames/hashes differ because the nine interval inputs changed; reuse rests on the exact local interval/alias/native-slice comparisons above, not on a claimed equal global dependency.
