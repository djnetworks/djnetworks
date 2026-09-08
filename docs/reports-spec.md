# Reports screen — spec and decisions

Written 8 September 2026, in answer to Claude Code's three blockers and its ROI finding.
The layout reference is `reference/design/reports-mockup.html`, now in the repo.

Read the mockup as a **layout and honesty spec, not as code**. It was written outside the repo
against EKUM v6 token names, and those will not all match `web/tokens.css`. Map every colour to
the app's real token. If a token it needs does not exist, say so rather than inventing one.
Every figure in it is illustrative — AMP-2K, the ₹2,800, the day counts. Nothing hard-coded
survives into the build.

---

## Answers to the three blockers

**Dark mode — do not build one.** The app is light-only and stays light-only. Ignore every
dark-theme block in the mockup.

**dataviz — it does not exist in that session, and saying so was right.** Use the WCAG checker
built during the tokens pass (the one that produced 4.60 / 4.84 / 4.80) and label the output as
that. Check every bar colour against `--surface` **and** against `--bg`, since bars sit on both.

**The mockup was missing** because it was a chat attachment, not a file. It is now at
`reference/design/reports-mockup.html`.

---

## ROI — three states, not two

The finding was correct. Two states are not enough, and the three must be visually distinct.

| condition | render |
|---|---|
| `roi_pct` null **and** `units_missing_cost > 0` | "Cost not recorded", muted grey, flat grey bar, "3 of 3 pieces" beside it |
| tracking_mode `pool` / `consumable` | "Not tracked for counted stock", same muted treatment, **suppress `units_missing_cost` entirely** |
| `roi_pct = 0` with cost recorded | a real bar at zero, "0.0%" printed |

Suppressing the zero in the pooled case is the important one. "0 pieces missing cost" reads as
*fully costed* when the truth is that the view cannot see the cost at all — a structural absence
rendered as a confident number, which is rule 14 in miniature.

The third state matters for the opposite reason: a product with a known cost that has earned
nothing back is genuinely underperforming, and must not hide among the unpriced ones.

**One thing "not tracked" understates.** Chachu *has* typed ₹450 for the cables. The cost exists;
`v_product_roi` cannot see it because it sums over `unit` rows and counted stock has none. Pooled
ROI is computable as `default_purchase_cost × quantity on hand`. Do **not** build that now — it is
a view change and therefore a migration. Add it to the backlog as *"pooled ROI is computable and
currently isn't"*, so it does not come to be believed impossible.

---

## Not moving — client-side is fine

Numbered pieces from `v_unit_utilisation`; counted stock in its own group with
days-since-last-movement computed from `v_movement_effective`. Nothing is stored, so rule 10 is
untouched. No migration this pass.

---

## analysis.html — fold and delete, but rename the section

Folding is right. The heading is not: *"how hard it works"* and *"how often it goes out"* are
answers about products that **are** working, and filing them under **Not moving** buries them.

Call the section **"How each product is working"**, with columns for days idle, times hired and
% of time out, sorted worst-first so dead stock still lands at the top.

Then delete `analysis.html`, drop it from the service-worker shell, and grep for anything still
linking to it before committing — a dead link left in the nav is how this returns as a bug report.

---

## The four rules that survive from the mockup

1. **Billed and Received are two separate numbers**, side by side, never one figure. Revenue posts
   on order *confirmation*, so billed includes gear that has not left the godown. Keep the one line
   that says so — it is the one place a sentence earns its place after the text cut.
2. **Deposits held sits apart from still-to-collect.** Rule 6. Never blended, never summed into a
   single "outstanding".
3. **Never render a missing cost as 0%.** With an empty catalogue the unpriced case is the
   *majority* case on day one, not an edge case. Design for that.
4. **One raised card — the money block.** Everything else is flat hairline rows, per the elevation
   law. Do not build a grid of cards; that is what produced the border problem just fixed.

Layout: single column, phone width. Money block first. Thin bars in the teal token on a pale teal
trough. At most one tangerine use on the whole screen.

---

## Sections and their views

| section | source |
|---|---|
| Money | billed vs received, still to collect, deposits held |
| Earning best | `v_product_roi` |
| How each product is working | `v_unit_utilisation` + `v_movement_effective` for counted stock |
| Best customers | with a status tag — pays on time / owed / settled / returned late |
| What breaks | `repair_job` against hire count, as repairs per 10 jobs |

Repoint the Reports nav slot from `analysis.html` once `reports.html` exists.

---

## Standing decisions from this pass, recorded so they are not re-litigated

- **Keep `.eq('user_id', uid)` in `loadPermissions()`.** It is the one place this pass broke
  "presentation only", and it stays. Shipping the staff view without it means shipping a feature
  whose first successful use strips the owner of every permission. **Check the Team screen still
  reads all rows** — it must not have inherited the filter.
- **Do not build repairs or locations screens.** Repair is a new form, not a UI pass; locations are
  four seeded rows nobody edits. The Gear strip is Equipment · Products · Load the van.
- **Overdue is the loudest state on Equipment** — louder than *out* and louder than *at repair*.
  Out is the normal state of a working rental business. A piece out past its return date is the bug
  rule 2 exists for.
- **The Aadhaar/PAN warning goes in the field label**, not back as a paragraph: label "ID document
  link", placeholder "photo link, never the number". The real enforcement is that no column exists.
- **"Back doesn't close a sheet" is not a nicety.** On Android the back gesture is how people
  dismiss things; if it navigates away instead, a return sheet with six units ticked is lost. Same
  class as the primary button under the nav. Needs a `popstate` handler on the five screens with
  sheets — its own prompt, not an indefinite deferral.
- **The orders.html gate** — a full new-order form for an account RLS will refuse at save — is
  real and is scope. Queue it separately.
