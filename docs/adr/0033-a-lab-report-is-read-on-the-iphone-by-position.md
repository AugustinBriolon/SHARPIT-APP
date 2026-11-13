# 33. A lab report is read on the iPhone, by position

Date: 2026-11-13

## Status

Accepted. Client side of SHARPIT ADR-128.

## Context

Santé imports blood tests. A report prints the athlete's name, birth date, address and prescriber on every page, and the server accepts results only (SHARPIT ADR-128), so the reading has to happen here.

Two real reports from one lab chain (2021 and 2026, native PDFs) showed what a reader must survive:

- **Reading order lies.** The PDF text layer lists some values before their label and after the previous marker's method note. Read in order, ASAT took the alkaline phosphatase's neighbour.
- **Several figures per line.** A white-cell line carries a percentage, the count, the bounds and the previous test's value.
- **Two units.** The SI value sits on a second line under the conventional one.
- **Recognition is not text.** The same pages rendered as images and recognised by Vision came back with uneven boxes, « µg/L » read « Hg/L », and a few fragments read upside down.

## Decision

- **On the device only.** `BloodReportReader` uses the PDF's text layer when a page has one, Vision otherwise. The document is opened in place, never copied, cached or uploaded.
- **Position, not order.** Both sources give text with its box. `BloodReportParser` joins the pieces that share a printed line (within half the page's median line height), then reads each line.
- **A line is a result only if** it starts with a catalog alias (longest first) and holds a number followed by that marker's own unit. The unit picks the value among several and rejects a misread; the bounds are the parenthesis that follows; anything after is ignored.
- **Nothing is guessed.** A line that fails either test yields nothing. The athlete adds the marker by hand in the review.
- **The athlete confirms.** `BloodTestReviewView` shows every value, editable; a value outside the catalog's plausible range blocks the save; a report read by recognition says so.
- `BloodMarkerCatalog` mirrors the web catalog's keys, units and plausible ranges. Aliases are this app's.

## Consequences

- On the two reports, the text layer gave 32 of 32 and 4 of 4 results, bounds and sampling date included. Recognition of the same pages gave 30 of 32 and 4 of 4, with one bound missing and no wrong value.
- Only this lab chain's layout has been checked. Another lab needs its aliases, and may print one unit only.
- A real phone photo (skew, shadow, fold) has not been measured.
- Marker labels are French in both languages.
- Fixtures in tests are invented figures laid out like the real lines: no real report is committed.
