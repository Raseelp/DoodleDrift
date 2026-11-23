# Doodle Drift: driftable track design (research report and plan)

Status: plan for approval. Nothing here is built yet. Scope: the track itself (its shape and width), not the paper around it.

## 1. What real drift tracks get right

**Flow comes first.** The trait drift sources agree on most is that a good drift circuit lets you link one drift seamlessly into the next ([Drift Enthusiast](https://www.driftenthusiast.com/magazine/drift-tracking), [low-offset on Ebisu](https://low-offset.com/guides/ebisu-circuit)). A drift track is a chain of corners, not corners separated by long straights.

**An initiation zone before the big corner.** Japanese courses such as Meihan C, Nikko and Ebisu open with a fast sweeping entry into the main corner, and that entry is the heart of the course ([Drift Bible tracks blog](https://rextremerc.blogspot.com/2016/10/drift-bible-tracks.html)). Competition rules make it formal: there is a window where you must start the drift, and starting too late costs points ([Drift Masters 2024 judging rules](https://dm.gp/media/pkmbve3r/dm2024-judging-rules.pdf)). So the driver always sees the corner coming and has room to set the car up.

**Long constant-radius corners.** The corners people love most are long ones that hold the same curve, like Ebisu Minami's long constant-radius turn ([low-offset](https://low-offset.com/guides/ebisu-circuit)). Once the car is balanced, the driver can hold the angle and enjoy it. Corners that keep changing tightness are hard to hold.

**Transitions.** A switchback where the drift changes direction (a "manji", or left-to-right flick) is a judged highlight in its own right. Rulebooks describe transition zones where the car must swap the direction of its drift, scored on how cleanly that's done ([GTPlanet summary of Formula D/D1 rules](https://www.gtplanet.net/forum/threads/formula-d-d1-rules-explained-for-gt6-drift-comps-drift-olr.306688/)).

**Clipping points and zones.** Judges define an ideal line with inner clipping points (get close to the inside) and outer clipping zones (swing wide to the outside), scored sector by sector ([Formula DRIFT judging regulations](https://www.formulad.com/storage/rulebooks/April2026/2026%20Formula%20Drift%20Judging%20Regulations%20V1.21.pdf), [classiccars.com on FD qualifying](https://journal.classiccars.com/2019/04/23/in-depth-look-at-how-formula-drift-qualifying-works/)). The same physical corner becomes a fresh challenge just by moving the clips.

**Variety in the mix.** Courses mix technical tight sections (Ebisu Kita, Touge) with wide fast ones for high-speed entries and manjis (Ebisu Higashi, Nishi) ([low-offset](https://low-offset.com/guides/ebisu-circuit)). A sweeping braking entry, a hairpin with an inside clip, a switchback transition and a power-on exit are named as the features that matter most ([Drift Bible tracks blog](https://rextremerc.blogspot.com/2016/10/drift-bible-tracks.html)).

## 2. What drift games teach

- **Absolute Drift** (top-down, the closest game to ours). Its tracks are packed with curves and obstacles made for drifting around, and the side objectives are drifting between two objects, spinning on the spot and jumps ([iMore review](https://www.imore.com/absolute-drift-review-absolutely-delightful-game-about-drifting), [Digitally Downloaded review](https://www.digitallydownloaded.net/?p=45512)). Reviewers single out its circuits as the least memorable part: circuits felt the least varied of its modes. Lesson: in top-down, set pieces and corner variety carry the fun, not lap length.
- **The zen feel.** No opponents, just you against the course (and your ghost). That fits an endless runner on paper.
- **Point-zone games** (CarX, Drift Hunters, from general knowledge): scoring rewards angle, speed, time sliding and proximity to marked zones. Doodle Drift already scores angle and closeness to the line. Zones that the generator places on purpose are the natural next step, covered in the gameplay plan.

## 3. Our car in numbers (from the code)

| Quantity | Value | Why it matters |
|---|---|---|
| Speed | 140 (drift minimum) to 290 (top, long straights only); about 220–250 typical | Sets how fast corners arrive |
| Full-drift turn rate | about 2.7 rad/s | Tightest drift circle ≈ speed ÷ 2.7: about **85 px at 230, 107 px at 290** |
| Road width | 150, narrowing to 100 over distance; squeeze ×0.6–0.7, pad ×1.5–1.8 | Inner edge = corner radius − half width |
| Camera look-ahead | about 560 px of road (70 points) | About 2 s of warning at 280 |
| Car | 76 px long, about 34 px wide | |

From these, the corner sizes (radius of the centre line) work out as:

- **Tightest fair drift corner:** about 120 px. The car's own drift circle (85–107 px) plus a margin so it doesn't need a perfect line.
- **Ideal drift corners:** 150–350 px. The car can hold a big, steady angle here.
- **Grip sweepers:** above about 500 px. Taken flat, little or no drift needed: these are breathers.

**What's wrong with the current generator.** The pieces themselves are fine, but:

1. **Corners start and stop abruptly.** Each piece is a perfect arc, so the road switches from straight to full curve in one step. Real roads (and the racing-line research) ease in with a transition curve whose tightness grows steadily ([clothoid background](https://pmc.ncbi.nlm.nih.gov/articles/PMC7184578/)). Without one, entries feel twitchy.
2. **Radii aren't tied to the car.** The only limit is "not tighter than the road is wide", so some corners are tighter than the car can drift (about 85 px) and many are dull in-between sizes.
3. **No initiation or exit space.** A corner can begin right where the last one ended, with no room to set up.
4. **Direction choice is random.** Linking isn't designed: the right left-right flick for a transition happens only by chance.
5. **Nothing marks the line.** There are no apexes or zones the scoring could use later.

## 4. Design principles for Doodle Drift's tracks

1. **Smooth tightness changes.** Every corner eases in and out with a transition curve; tightness never jumps. Entry eases are longer than exit eases, so the corner announces itself.
2. **Corner sizes come from the car.** Use the radius bands above: drift corners 150–350, the tightest 120, sweepers 500+. If the car's handling changes (garage cars), the bands move with it.
3. **Every drift corner gets a run-up and a run-out.** Before the corner, a straight or gentle bend long enough to see it (at least about 1 s of driving, longer for bigger corners). After it, a short power-on exit where the car pulls back up through the gears.
4. **Link corners into chains.** Prefer direction changes: L → R → L chains with short transitions (about 0.3–0.6 s), so a drift flows into the counter-drift. Same-direction pairs become a double apex or "esses". Never more than 2 same-direction corners in a row.
5. **A clear set of building blocks** (each with its own size and ease rules):
   - long constant-radius corner (the signature corner)
   - hairpin (the tightest, with a long run-up)
   - switchback / transition: two opposite corners, linked
   - esses: three or more linked opposite corners
   - double apex: two same-direction corners with a short ease between
   - fast sweeper: a breather
   - drift pad: a wide open area with one long turn
   - squeeze: a narrow section, to test control
   - kink: a slight bend on a straight, to keep straights alive
   - decreasing-radius corner: late-game only, the one deliberate trick
6. **Phrases and rhythm.** The road is built as short "phrases" of 3–6 blocks, each with an intensity: calm (sweepers, long corners) → build (chains) → peak (hairpin, esses, squeeze) → release (pad or straight where speed builds toward 290). The current calm/busy/calm/tense cycle stays, but each phase now shapes a phrase instead of one random piece. A memory of recent blocks prevents repeats, as now.
7. **Difficulty rises without speed.** The difficulty knobs:
   - corner radius (toward 120 px)
   - road width (toward 100 px)
   - transition length (shorter links)
   - chain length
   - how often peak blocks appear
   - run-up length (shorter, but never under the 1 s minimum)

   Speed stays the player's own choice: straights let you build to 290, corners take it away.
8. **Readable from above.** Every corner must be visible early enough. A corner's start must appear inside the camera's view at least about 1 s before the car reaches it. Width changes ease over at least about 200 px. A tight corner straight after a blind crest can't happen (there are no crests), but tight-after-hidden-by-the-HUD can, so check against the visible area.
9. **Track metadata for scoring.** For each corner the generator records its apex (inner clip), outer zone, direction and size class. The gameplay plan can then add clip points, zone bonuses and "link" bonuses without touching the shape code.
10. **Safety rules stay.** The road never crosses itself, keeps heading up the page within limits, and nothing impossible is generated: radius never below the minimum, total turning in one chain capped.

## 5. Proposed generator design (to build after approval)

- **Shape as a tightness profile.** Each block outputs a list of segments: (length, start tightness, end tightness). Straights have zero tightness, arcs hold a constant tightness, and the eases ramp between them. Points are laid every 8 px by integrating that profile, so the eases come for free. This replaces the current constant-turn pieces.
- **Phrase builder.** Picks a phrase template for the current phase, fills it with blocks, picks sizes from the difficulty-scaled bands, and alternates directions by rule (principle 4).
- **Checks before accepting a phrase:**
  - nothing tighter than the minimum radius
  - no self-overlap (existing check, kept)
  - stays within the up-the-page heading limit
  - visibility rule (principle 8)

  If a check fails, it tries smaller sizes, then a different phrase, then falls back to a gentle straight (as now).
- **Output per corner:** apex index, direction, radius class and outer side, kept with the road chunks and pruned with them.
- **Kept as is:** road chunk drawing, line styles per stretch, obstacle and coin placement. Placement can later use the corner metadata to put props at outer zones and coins along the ideal line.

**Effort:** about one focused session for the generator plus a short tuning pass, with measurement capped by your 5-minute rule.

## 6. How we'd judge it's better

- **Measured by a test bot (under 5 minutes):**
  - share of time drifting
  - number of linked drifts (drift into counter-drift with no grip gap)
  - share of time off the line
  - smallest radius generated
  - that no corner arrives without the minimum run-up
- **Felt on the phone (you):**
  - entries feel announced, not twitchy
  - chains flow
  - there are breathers
  - difficulty climbs over a run

## 7. Decisions for you

1. **Signature corner:** should long constant-radius corners be the most common drift corner, as on real courses? My recommendation: yes.
2. **Decreasing-radius "trick" corners:** include them late in a run, or never? My recommendation: late only, and rare.
3. **Hairpins:** currently 180° turns. Keep them full 180°, or cap at about 150° so they stay flowing? My recommendation: up to 160°.
4. **Corner metadata (apex and zones):** record it now, so the gameplay plan can use it later? My recommendation: yes. It costs little now and saves a rewrite.
