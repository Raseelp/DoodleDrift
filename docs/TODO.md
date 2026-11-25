# Doodle Drift: to-do list

In the order to work through them. Items marked **plan** start with research and a written plan for Raseel to approve before anything is built.

## Built, needs a test on the phone

- **Skids:** dark, unbroken marks from all four tyres (rears darker); old marks cleared once off screen.
- **Sound:** tyre squeal follows the slide, paper rips, coins, bump and crash; radio-style music that shuffles and crossfades across runs; engine (Generic 6) with a 5-gear automatic, drift speed scrub (floor 140) and launch from standstill. Spare clips kept in sounds/ for later.
- **Track:** drift-focused generator (docs/track-design-report.md), top speed 330 on long straights.
- **Drawing, phases 1-3:** pencil-stroke road edges; notebook page (coffee rings, creases, torn binding edges with punched holes the car drops into, page numbers, staples, show-through); the narrator's notes, doodles, drawings, memes, ghost roads, oops corrections and sticky notes (scripts/scribbles.gd), varied by the mixer and saved decks.
- **Handling:** flow mode (always drifting, pendulum switches, wider road) is the default; classic hold-to-drift is in dev settings.
- **Camera:** single top-down camera that eases its zoom to fit notes beside the road.
- **Tyre particles:** smoke and rubber bits on any skid, graphite smudge and eraser crumbs added when the paper tears (scripts/tyre_fx.gd).
- **UI phase 1 (2026-11-26): home is a hand-drawn page at the start, with a night car meet** (scripts/start_page.gd). From the top: a pencilled gear (top right of the page, only tappable on the start page); the road with "hold" handwritten either side (written, rubbed out, rewritten) and the best run in the margin; the start line; the car's stats (placeholder values until the garage plan); a night car meet taking over the lot (11 show cars at angles with popped hoods, open doors, a boot speaker and headlight beams; 53 people from above at true size who turn to watch; coffee van, chairs and cooler, a camera on a tripod, a marshal with a torch, lamp posts, cones, old donut marks and a burnout strip, a drone following the car, night shading lifted where the lights fall); the title at the bottom. The chosen car never stops: a figure of eight with donut laps and a 360 spin through the middle (more tricks were tried and taken out: too busy), braking for the loops, its tail swinging like a pendulum (driven in 1/120 s slices so a slow frame never jolts it), fresh marks wearing away behind it. Hold a side 0.25 s: it breaks off wherever it is and sweeps up through the stats to the start line, sliding through the turn instead of braking, and the player takes over as soon as it has turned out of the donuts towards the road (about 0.5-0.8 s after the hold, at 200-250); the meet below the start line is open ground (no slow-down, no lost-the-road there); the hold that started the run is ignored until let go. The drone flies back to hover over the pit once the run starts. On short screens the road moves up so the meet always fits. The still drawing is baked into one image (frames ~10 ms on PC). The gear pans to the settings written beside it on the right (the paper behind them is rubbed clean on the start page so the road never crosses the writing; the run brings it back); any other tap pans back. Only the two cones in the middle of the loops (above the marks). Trick marks use the run's own skid look (4 tyres, graphite, no fading except the very oldest). People are careless pencil doodles of many types (stick, blob, hoodie, cap, filming, cheering, hands on hips, coffee, kid, chairs, a dog), turning like paper cut-outs to watch.
- **Off the road:** the paper only drags the car once both rear tyres are past the edge (red lines and losing the road still go by the car itself).
- **Back button (2026-11-26):** in a run it pauses ("PAUSED, hold to start"; the hold that restarts it doesn't steer); on the start page it closes the settings, else asks "Do you want to quit?" (Quit / Stay). Placeholder screens until the UI phases design them.

## The theme (found 2026-11-26)

**Doodle street drift.** The whole game is a pencil-drawn street scene on a notebook page, the way the start page's night car meet is drawn: hand-drawn cars, careless doodle people, street furniture, buildings, all in pencil, with the track running through it. Every item below is designed in this style.

## Next

1. **UI on the paper, phases 2-4 (do these completely first, 2026-11-26)** (plan approved 2026-11-25: one sheet, the camera never cuts, UI made of the game's own pencil, "hold a side" is the only gesture; now in the street style).
   - **Phase 2: crash summary on the paper.** Written by hand beside the crash (score underlined, NEW BEST circled in red pen, distance, combo, confetti); hold a side to drive again (ignore holds for the first second after the crash) with a page-turn to a fresh start line; a small doodled "home" arrow. Street touch: the crowd at the crash reacts.
   - **Phase 3: run HUD and pause.** Score handwritten in the top margin, distance as a margin note, confetti as tally marks or the handful doodle; pause as a paper clip on the top edge (48 dp or more) with a "paused" note ("resume", "home"); replaces today's placeholder pause and back-button screens.
   - **Phase 4: garage and modes at the meet.** The meet on the start page becomes the garage: your cars are the show cars parked there, tap one to swap, locked ones as sketches with price tags; the stats bars get real values per car. Mode choice also lives at the meet (after the gameplay-loop plan).
2. **Track and surroundings: the doodle street world (plan, after the UI phases).** The road stops being a lone pencil road and becomes a street, drawn like the meet:
   - the street itself: kerbs and pavements, painted lines, crossings, drains and manholes, tyre marks left by other drivers;
   - what lines it: buildings from above (rooftops, AC units, water tanks), shopfronts, a petrol station, car parks, parked cars, lamp posts with pools of light, trees, fences, barriers, cones, graffiti, signs;
   - people: doodled spectators gathered at corners and along the best drift spots, phones up, turning to watch as you pass (like the meet);
   - districts that change as you drive (downtown, docks and containers, industrial yards, a mountain pass, a highway), taking over from the old "paper zones" idea and "the area outside the track";
   - meets and gatherings along the route as set pieces;
   - performance rule from the start page: everything still is drawn once into images per stretch of road (as the start page's baked image), only people, smoke and the car move.
3. **Phase 4: ink rules - built 2026-11-25 (scripts/inks.gd), needs a phone test.** On: pen-colour chapters at page edges, red ink = out if the car goes completely past it, clipping cones in marked chapters, travelling notes that teach each rule once. Off until Raseel asks (code kept): highlighter bonus zones, crayon (slick), ink puddles. The narrator is off too (NARRATOR in scribbles.gd). To review against the street theme: red ink could become barriers or walls, clipping cones become street cones or spectators to drift past.
4. **Gameplay loop, modes and engagement (plan).** What makes a run fun, what brings players back, which modes to have; street ideas to weigh: touge runs, a gymkhana lot, tandem with a ghost car, crowd points for drifting close to spectators, police-free "takeover" events.
5. **Garage and car collection.** Fixed visible prices, different handling per car, cosmetic paints. Needs low-poly cars from Raseel, plus the paper car once found. Shown at the meet (UI phase 4).

## Later

6. ~~Package name~~ done 2026-11-25: `dev.raseel.doodledrift`, its own repo (Raseelp/DoodleDrift, split from FindingLight `drift`).
7. ~~The area outside the track~~ folded into item 1 (the doodle street world).
8. **In-game radio controls:** let the player pick or skip tracks while driving (music is in the dev settings for now).
9. More narrator templates when the jokes start feeling familiar (about 138 now).
10. Release build: app bundle, low-poly cars, around 30-35 MB.
11. Store listing: new Doodle Drift screenshots and text (replace the old Finding Light ones).
12. **Ad rewards (last).** Opt-in only: continue once per run, double coins, daily bonus.
