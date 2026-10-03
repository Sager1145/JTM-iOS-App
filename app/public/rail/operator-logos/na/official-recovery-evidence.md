# Official North America operator logo recovery

Reviewed 2026-09-30 America/Toronto; asset retrieval timestamps below are UTC
(2026-10-01 UTC corresponds to the same local review date). Scope: 15 currently
audited-unbranded US lines from five operators. No runtime manifest, operator
registry, or package was changed by this recovery. These assets are **staged**,
not a declaration that their reuse conditions are satisfied. Every operator's
machine-readable source, publisher, status, and usage conditions are in
`app/scripts/railway/na-official-logo-catalog.json`.

## New Orleans Regional Transit Authority — 7 lines

Package operator `NORTA`, line prefix `new-orleans-rta-`: 12, 12-b1, 12-b2,
12-b3, 47, 48, 49. Publisher: New Orleans Regional Transit Authority.
[Official website](https://www.norta.com/) publishes an actual operator mark
at `/Content/Images/new-footer-logo.svg`.
[Terms of Service §12](https://www.norta.com/app-terms-and-conditions) reserves
the logo and gives no right to copy, distribute, or display it. **Permission
required: no asset downloaded or activated.** This replaces the outdated
explanation that no official artwork exists; the obstacle is now documented
usage rights, not Wikidata availability.

## Houston METRO — 5 lines

Package operator `Metropolitan Transit Authority of Harris County`; line IDs
`houston-metro-700`, `houston-metro-800`, `houston-metro-900`,
`houston-metro-800-b1`, `houston-metro-900-b1`.
Publisher: Metropolitan Transit Authority of Harris County, Texas.
[Official source page](https://www.ridemetro.org/about/news-media) displays
[current METRO SVG artwork](https://www.ridemetro.org/ResourcePackages/Main/dist/assets/images/METRO-Logo.svg).
Staged PNG: `houston-metro-official.png`, 512 × 87.
Retrieved `2026-10-01T02:41:40.113Z`.
SVG SHA256: `0134424078d9ae802f8c8a1bcd9add783bbe6e3c7d1c6c6984bf1538d193de0a`.
PNG SHA256: `87cacc59070f73b19d734c28cb1b1d13737275ec4bcc4df5381bc84c39ce73c1`.

Usage remains conditional. The page's Transit Data Files agreement §1(B)(v)
permits the METRO mark to identify METRO service associated with its data,
but requires `METRO*` and the nearby notice: “The METRO logo is the registered
trademark of the Metropolitan Transit Authority of Harris County, Texas.
All rights reserved.” The separate Marks/Downloadable Assets agreement §2 limits its media
license to news/current events/community partnerships and requires prior
written approval outside that scope. **Do not activate as an unrestricted
operator mark.** Manifest synchronization must record the conditions and the
product must implement the applicable required notice or obtain permission.

## Hillsborough HART — 1 line

Package operator `Hillsborough Area Regional Transit`, line
`hillsborough-area-regional-t-800`. Publisher: Hillsborough Area Regional
Transit Authority. The current [official homepage](https://www.gohart.org/Pages/GoHart-Home.aspx)
labels [this PNG](https://www.gohart.org/Style%20Library/GoHart/Images/hart-logo.png)
“GoHart Logo”; it is the actual operator artwork, not a bus photograph or
TECO streetcar route badge. `hillsborough-hart-official.png`, 266 × 80,
is the downloaded PNG without alteration.
Retrieved `2026-10-01T02:41:40.256Z`.
Source and PNG SHA256:
`c40af4c002027b2e5fccf3d9388fc9bd4227d93157cd706ceb6918e0ed506629`.

No open redistribution license was found. [Published marketing guidance](https://www.gohart.org/Style%20Library/goHART/pdfs/SOPS/marketing.pdf)
documents preferred/secondary variants and Marketing authorization for certain
variants. That older guidance does not itself establish redistribution rights
for the current website mark. **Rights review and manifest synchronization
pending.** No permission request was sent.

## Tampa International Airport SkyConnect — 1 line

Package operator `Tampa International Airport`, line
`hillsborough-area-regional-t-sky`. Publisher/rights owner: Hillsborough County
Aviation Authority. The airport would be this service's own operator, not a
borrowed municipal mark. Its [official trademark policy](https://www.tampaairport.com/legal/intellectual-property-and-trademarks)
requires prior written permission for business use and prohibits using the
authority's intellectual property with an unauthorized product/service.
**Permission required: no asset downloaded or activated.**

## Seattle Center Monorail — 1 line

Package operator `Seattle Center Monorail`, line
`metro-transit-intercity-tran-monorail`. Publisher: Seattle Monorail Services /
Seattle Center Monorail. The [official current page](https://www.seattlemonorail.com/about-the-monorail/)
uses [Primary Blue SVG artwork](https://www.seattlemonorail.com/wp-content/uploads/2022/06/Logo_Seattle-Center-Monorail_rgb_Primary-Blue.svg)
as its logo. It is the current circular train mark, not the older Wikipedia
file, a tourism substitute, or a photograph. Staged PNG:
`seattle-center-monorail-official.png`, 512 × 512.
Retrieved `2026-10-01T02:41:40.400Z`.
SVG SHA256: `06c97bc0d2ce943accd56ef5f8e0a84e4ebafcc4fef69657e902fecdc598a46e`.
PNG SHA256: `7b44818496bcaf56498d7e46e2b2a7be288fbc696b925641c8f1ff60f0f47c67`.
The official page reserves copyright; no open redistribution license found.
**Rights review and manifest synchronization pending.**

## Reproduce and verify

Run from `app/`, with a Node installation containing `sharp`:

```sh
node scripts/railway/recover-official-na-operator-logos.mjs --download
node scripts/railway/recover-official-na-operator-logos.mjs
```

Set `SHARP_MODULE` to an installed module directory if necessary. The script
never overwrites an asset or updates a runtime manifest. It downloads only
catalog entries explicitly staged for review, rejects changed source hashes,
converts SVG to PNG at 512 px without editing the artwork, and verifies PNG
format/dimensions/hashes and current line mapping. Existing PNGs are checked
offline. The three PNGs were visually inspected against the actual official
artwork on this review. No logo was invented or generated.
