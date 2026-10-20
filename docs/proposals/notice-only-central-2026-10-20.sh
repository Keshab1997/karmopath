#!/usr/bin/env bash
# Opens one issue per proposal, then confirms the notice-review
# label actually landed. Reviewing and labelling stays a human
# act: this never applies 'approve-notice' and never edits
# feed/jobs.json.
#
# The check is not ceremony. publish-notice.yml only runs for an
# issue carrying BOTH notice-review and approve-notice, and a
# token that may create issues cannot always edit labels - so a
# silently unlabelled issue looks approved in the tracker and can
# never be published.
set -uo pipefail
MISSING=()

created=$(gh issue create --title "[notice] Notification for Common Recruitment Process for CRP- PO/MTs-XVI" --body-file /dev/stdin <<'KARMOPATH_ISSUE_BODY'
Notification for Common Recruitment Process for CRP- PO/MTs-XVI

- Source listing: IBPS (Institute of Banking Personnel Selection)
- Notice link: https://www.ibps.in/wp-content/uploads/Detailed-Notification_CRP-PO-XVI_Final_V1_30.06.2026.pdf

Human steps before any feed change:
1. Open the notice and confirm it is on an official site.
2. Record last date, vacancy, eligibility and apply link from the notice itself.
3. Only then add or update the job in the feed draft (docs/REAL_DATA_RUNBOOK.md).

This proposal was generated offline by scripts/notice_proposals.py from a listing page captured on 2026-10-20. It is not a verification. The card preview says eligibility, vacancies and dates were not checked.
KARMOPATH_ISSUE_BODY
    ) || exit 1
number=${created##*/}
if ! gh issue edit "$number" --add-label notice-review >/dev/null 2>&1; then
  MISSING+=("$number")
fi
created=$(gh issue create --title "[notice] Notification for Common Recruitment Process for CRP- SPL-XVI" --body-file /dev/stdin <<'KARMOPATH_ISSUE_BODY'
Notification for Common Recruitment Process for CRP- SPL-XVI

- Source listing: IBPS (Institute of Banking Personnel Selection)
- Notice link: https://www.ibps.in/wp-content/uploads/Detailed-Notification-CRP-SPL-XVI_Final_V1_30.06.2026.pdf

Human steps before any feed change:
1. Open the notice and confirm it is on an official site.
2. Record last date, vacancy, eligibility and apply link from the notice itself.
3. Only then add or update the job in the feed draft (docs/REAL_DATA_RUNBOOK.md).

This proposal was generated offline by scripts/notice_proposals.py from a listing page captured on 2026-10-20. It is not a verification. The card preview says eligibility, vacancies and dates were not checked.
KARMOPATH_ISSUE_BODY
    ) || exit 1
number=${created##*/}
if ! gh issue edit "$number" --add-label notice-review >/dev/null 2>&1; then
  MISSING+=("$number")
fi
created=$(gh issue create --title "[notice] Window Notification for CRP-PO/MTs -XVI and SPL-XVI" --body-file /dev/stdin <<'KARMOPATH_ISSUE_BODY'
Window Notification for CRP-PO/MTs -XVI and SPL-XVI

- Source listing: IBPS (Institute of Banking Personnel Selection)
- Notice link: https://www.ibps.in/wp-content/uploads/PO_SPL_Combined_Window_CRP-XVI.pdf

Human steps before any feed change:
1. Open the notice and confirm it is on an official site.
2. Record last date, vacancy, eligibility and apply link from the notice itself.
3. Only then add or update the job in the feed draft (docs/REAL_DATA_RUNBOOK.md).

This proposal was generated offline by scripts/notice_proposals.py from a listing page captured on 2026-10-20. It is not a verification. The card preview says eligibility, vacancies and dates were not checked.
KARMOPATH_ISSUE_BODY
    ) || exit 1
number=${created##*/}
if ! gh issue edit "$number" --add-label notice-review >/dev/null 2>&1; then
  MISSING+=("$number")
fi
created=$(gh issue create --title "[notice] Addendum dated 06.10.2026 in respect of Recruitment of Banker Faculty, Banker Faculty (Technical) And Executive Secretary to Director On Fixed Term Contract Basis" --body-file /dev/stdin <<'KARMOPATH_ISSUE_BODY'
Addendum dated 06.10.2026 in respect of Recruitment of Banker Faculty, Banker Faculty (Technical) And Executive Secretary to Director On Fixed Term Contract Basis

- Source listing: IBPS (Institute of Banking Personnel Selection)
- Notice link: https://www.ibps.in/wp-content/uploads/Addendum-06.10.pdf

Human steps before any feed change:
1. Open the notice and confirm it is on an official site.
2. Record last date, vacancy, eligibility and apply link from the notice itself.
3. Only then add or update the job in the feed draft (docs/REAL_DATA_RUNBOOK.md).

This proposal was generated offline by scripts/notice_proposals.py from a listing page captured on 2026-10-20. It is not a verification. The card preview says eligibility, vacancies and dates were not checked.
KARMOPATH_ISSUE_BODY
    ) || exit 1
number=${created##*/}
if ! gh issue edit "$number" --add-label notice-review >/dev/null 2>&1; then
  MISSING+=("$number")
fi
created=$(gh issue create --title "[notice] Recruitment of Various Posts in IBPS" --body-file /dev/stdin <<'KARMOPATH_ISSUE_BODY'
Recruitment of Various Posts in IBPS

- Source listing: IBPS (Institute of Banking Personnel Selection)
- Notice link: https://www.ibps.in/index.php/careers/

Human steps before any feed change:
1. Open the notice and confirm it is on an official site.
2. Record last date, vacancy, eligibility and apply link from the notice itself.
3. Only then add or update the job in the feed draft (docs/REAL_DATA_RUNBOOK.md).

This proposal was generated offline by scripts/notice_proposals.py from a listing page captured on 2026-10-20. It is not a verification. The card preview says eligibility, vacancies and dates were not checked.
KARMOPATH_ISSUE_BODY
    ) || exit 1
number=${created##*/}
if ! gh issue edit "$number" --add-label notice-review >/dev/null 2>&1; then
  MISSING+=("$number")
fi
created=$(gh issue create --title "[notice] Tentative Calendar of CRP (PSBs & RRBs) Online Examinations" --body-file /dev/stdin <<'KARMOPATH_ISSUE_BODY'
Tentative Calendar of CRP (PSBs & RRBs) Online Examinations

- Source listing: IBPS (Institute of Banking Personnel Selection)
- Notice link: https://www.ibps.in/wp-content/uploads/IBPS_CALENDAR_2026-27_final.pdf

Human steps before any feed change:
1. Open the notice and confirm it is on an official site.
2. Record last date, vacancy, eligibility and apply link from the notice itself.
3. Only then add or update the job in the feed draft (docs/REAL_DATA_RUNBOOK.md).

This proposal was generated offline by scripts/notice_proposals.py from a listing page captured on 2026-10-20. It is not a verification. The card preview says eligibility, vacancies and dates were not checked.
KARMOPATH_ISSUE_BODY
    ) || exit 1
number=${created##*/}
if ! gh issue edit "$number" --add-label notice-review >/dev/null 2>&1; then
  MISSING+=("$number")
fi
created=$(gh issue create --title "[notice] Corrigendum dated 14.11.2025 in connection with CRP-CSA-XV" --body-file /dev/stdin <<'KARMOPATH_ISSUE_BODY'
Corrigendum dated 14.11.2025 in connection with CRP-CSA-XV

- Source listing: IBPS (Institute of Banking Personnel Selection)
- Notice link: https://www.ibps.in/wp-content/uploads/Corrigendum-CRP-CSA-XV_Vacancy_update2_14.11.25.pdf

Human steps before any feed change:
1. Open the notice and confirm it is on an official site.
2. Record last date, vacancy, eligibility and apply link from the notice itself.
3. Only then add or update the job in the feed draft (docs/REAL_DATA_RUNBOOK.md).

This proposal was generated offline by scripts/notice_proposals.py from a listing page captured on 2026-10-20. It is not a verification. The card preview says eligibility, vacancies and dates were not checked.
KARMOPATH_ISSUE_BODY
    ) || exit 1
number=${created##*/}
if ! gh issue edit "$number" --add-label notice-review >/dev/null 2>&1; then
  MISSING+=("$number")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Issues created without the notice-review label: ${MISSING[*]}" >&2
  echo "With a token that can write labels, run:" >&2
  echo "  gh issue edit ${MISSING[*]} --add-label notice-review" >&2
  exit 1
fi
echo "All issues created and labelled notice-review."
