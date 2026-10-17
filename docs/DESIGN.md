# Approved design system
Reference: design/karmopath-home-v2.png. Preserve cream/coral/teal, illustrated hero, pastel categories, white job cards and friendly tone. Improve spacing and functionality without substituting a different visual direction.

Tokens: background #FFF8F0; coral #F4654A; teal #0F766E; text #1F2937; white surfaces. Coral is decorative; use contrast-tested dark text/buttons where needed. Card radius 16, spacing grid 4/8/12/16/24; subtle shadows. Captain centralizes tokens and bundles fonts/assets. Use Bengali-capable font with documented redistribution license and license file. No network fonts.

Home: Karmopath header + bell; search/filter; illustrated hero; category strip; latest opportunities + filter chips; list; bottom Home/Saved/Calendar/Profile. Compact banner on small devices so jobs remain visible. Profile means settings/about, not login. Header bell shows notification preferences, not fabricated unread counts.

Card: generic category icon, title, district/qualification, closing date/status, bookmark. Detail: structured eligibility/date/application sections, official source link, reviewed timestamp, independence disclaimer and report-correction action.

AI assets are decorative only. Real UI text must be widgets, not baked into assets. Do not ship entire mockup image as app UI. No state seals, police crests, Ashoka emblem, official badges or government logos. Existing mockup's crest-like badge must be replaced. Mockup jobs/counts are fictional and must not enter live feed.

Requirements: 320px width, large text scaling, screen readers, 48dp touch targets, reduced-motion preference, loading/empty/error/offline states, no clipped Bengali. Accessibility order follows visible layout.
