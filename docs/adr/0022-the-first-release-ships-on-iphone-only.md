# 22. The first release ships on iPhone only

Date: 2026-10-23

## Status

Accepted

## Context

The app target declared `TARGETED_DEVICE_FAMILY = 1,2`, so version 1.0 would be listed for iPad
too. App Store Connect then requires a 13" iPad screenshot set next to the iPhone one, and App Review
checks the app on iPad. No screen was designed or tested for the iPad: the layouts, sheets and the
widget assume an iPhone width, and the iPad orientations listed every rotation without any screen
handling it.

## Decision

We will ship version 1.0 on iPhone only: `TARGETED_DEVICE_FAMILY = 1` for the app, the widget
extension and the tests, and the unused iPad orientation list is removed.

## Options considered

### Option A — iPhone only (chosen)
Pros: one screenshot set; App Review sees only the device the app was built for.
Cons: iPad owners cannot download it, even scaled.

### Option B — Keep iPad
Pros: a larger audience from the first day.
Cons: a second screenshot set, and an iPad review of layouts never checked on it, a common
rejection cause (guideline 2.1 / 4.0).

## Consequences

### Positive
- The first submission needs iPhone 6.9" screenshots only.

### Negative
- Adding iPad later needs its own design pass, screenshots and review.

### Neutral
- iPhone apps still run on Apple silicon Macs and on iPad in compatibility mode only if allowed in
  App Store Connect › Pricing and Availability; that setting is unchanged.
