# Four public JR West conventional services: dated section extracts

Collected 2026-10-02 in the user's Toronto-local session. All train times and service dates are interpreted in **Asia/Tokyo**, not the collection timezone. Artifact: `jr-west-20261004-reviewed-sections.json`. No Swift, builder or bundled resource was changed during this collection gate.

The normalized overlay contains **four distinct published scheduled services**, represented by **five train-number sections** and **33 researched passenger calls**. It does not count the 3438M→3138M number change as a fifth independent departure. All dates are explicitly restricted to **2026-10-04**; no weekly calendar is inferred.

## Official source and calendar evidence

1. [JR West 3442A, new rapid 26](https://timetable.jr-odekake.net/train-timetable/238961?date=20261004): column explicitly says 新快速, train number 3442A and 土曜・休日運転. The requested date is Sunday 2026-10-04. Imported section is 大阪–京都 with four calls: 大阪 10:43/10:45, 新大阪 10:49/10:50, 高槻 11:00/11:01, 京都 11:14/11:15.
2. [JR West 752T](https://timetable.jr-odekake.net/train-timetable/101911?date=20261004): explicitly 快速, 752T, 土曜・休日運転. Source notes **西明石まで普通／高槻から普通**. Imported rapid section is 大阪–高槻: 大阪 11:22/11:23, 新大阪 11:27/11:28, 茨木 11:37/11:37, 高槻 arrival 11:43. No rapid service is asserted east of that boundary.
3. [JR West 744T, A rapid 744](https://timetable.jr-odekake.net/train-timetable/322251?date=20261004): explicitly 744T and 土曜・休日運転, with **西明石まで普通／高槻から普通**. The overlay imports the **ordinary** 高槻–京都 section from the published calls, not the advertised rapid class for the whole train. It includes departure 高槻 10:43 and the seven following passenger calls through 京都 11:05/11:07. This class comes from the explicit source note, not its T suffix or the fact that it stops frequently.
4. [JR West 3438M→3138M](https://timetable.jr-odekake.net/train-timetable/101572?date=20261004): both columns explicitly 新快速. The first is 土曜・休日運転; the second is 毎日運転. The source marks a **through** transition at 近江今津, arrival 11:34 as 3438M and departure 11:43 as 3138M. The overlay retains reciprocal previous/next trip IDs. It records the 湖西 section 山科–近江今津, followed by the full passenger-call continuation 近江今津–敦賀. The 3138M column's daily label is not expanded to unresearched dates.

Each page identifies its edition as **JR時刻表2026年10月号**. These are published timetable pages for the requested date, not advance timetable proposals in a press announcement. Calendar graphics cannot establish additional valid dates from extracted text, so only the requested date is included. They are schedules, not reports confirming that the trains actually ran.

## Physical and stopping scope

Every line ID and stop code was taken from `app/public/rail/jp-2025.json` and checked against the relevant line's station directory. Imported sections use JR West 東海道線、湖西線、北陸線 only. Source pass-through レ rows are omitted; omitted stations beyond the section boundaries remain unknown. The overlay is `partial` throughout, even where every published passenger call within an extracted section is present, because the complete train and national coverage are not imported.

Times are integer seconds from Japanese service-day midnight. The source's through change at 近江今津 does not create a guessed arrival or departure in the wrong column. At the 752T rapid→ordinary boundary only the rapid arrival is retained; the ordinary 744T section begins with its published departure at 高槻.

The public source carries timetable reproduction restrictions. This file preserves short manually reviewed factual extracts; it is not a whole source page copy, a bulk scraper or a complete reproduced train timetable.

## Deferred import

After the native compilation/performance gate clears, the parent can merge the overlay with:

```sh
python3 ios/tools/build-line-service-catalog.py \
  --reviewed-input app/data/conventional-timetable/overlays/jr-west-20261004-reviewed-sections.json
```

The collector intentionally did **not** run that command or alter bundled resources while compilation was active.

## Shikoku follow-up remains open

Public JR Shikoku local station PDFs and bus-connection tables expose useful times, but this collection did not establish a sufficiently explicit effective edition plus service-day calendar for a new dated local record. The Marine Liner 47 official train page appeared in search results but repeated direct fetches were unavailable. No Shikoku train or calendar was invented to fill this gap; public-source collection can continue when another verified dated page or provider PDF is available.
