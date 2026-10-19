# Shiku actual extraction adjudication

Root observed the actual z19 extraction. One 120m connected pale-fill candidate is unresolved, with no independently supported rail at its midpoint. It must not be a station alias.

A bounded Swift regression reproduced the misleading merged extent. Eroding/dilating connected fill by1,2,5pixels was tried in a preserved prototype. The2/5pixel variants split at the Ina text as well as roof/stair necks and lost the whole middle passenger frame; rejected. Existing3platform tests passed at2pixels, but the actual Shiku regression failed. This is evidence that synthetic passing tests cannot establish the real frame.

The prototype and failing regression remain in this report directory; both runtime source files were restored exactly to their pre-experiment contents. No candidate was installed or production line data changed. Next correction should analyze outer transverse envelopes with explicit text gaps, rather than erase fill around all text holes. Regional aerial establishes the south passenger roof but cannot independently establish both cartographic caps at Omiya/Uchijuku.

A second outer-envelope width-profile prototype also split at the rotated Ina label. Actual Shiku regression remained failing while the3existing platform tests passed. Preserved as rejected-outer-envelope-prototype.swift; removed only these rejected experiment changes from runtime source/tests. No runtime algorithm repair is claimed.
