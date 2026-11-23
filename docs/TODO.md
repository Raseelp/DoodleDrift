# Doodle Drift: to-do list

In the order to work through them. Items marked **plan** start with research and a written plan for Raseel to approve before anything is built.

## In progress

- **Real sounds: built, needs a listen on the phone.** Tyre squeal loop follows the slide, paper rips while tearing, coin clinks, bump and crash (sounds/CREDITS.txt). The pencil-writing recording is kept in sounds/ for later (it's writing, not rolling).
- **Rips continue off the track.** Built.
- **Engine sound:** generic engine is the default (Raseel liked it best). Dev "Engine sound" lists generic pitch variants, two phone-recorded cars and the performance-car options. Drifts now scrub speed (floor 140 px/s), so long drifts drop to 3rd and the exit shifts back up: needs a feel test. Start-up, turn-off and acceleration clips are kept in sounds/engine_more for later.

## Next

1. **Driftable track design (plan).** Make the procedurally generated track itself good for drifting.
   - Research real drift tracks (for example Ebisu, Meihan, Irwindale, D1/Formula Drift layouts) and drift games: corner types, entry and exit lengths, linking corners into a flowing chain, transitions (left to right), clipping points and zones, widths, how difficulty rises.
   - Write down the design principles, then rebuild the generator around them.
   - Only the track itself for now; the area outside the track comes later (item 8).
2. **UI design system: the UI lives on the paper (plan).** Go creative: draw the UI into the game world instead of as screens.
   - Tutorial drawn on the free space beside the track: two fingers on either side of the road with a short handwritten note next to them.
   - Play, dev settings, mode select, garage and the rest as objects or handwriting near the track.
   - Define the style: handwriting fonts, pen and pencil colours, doodles, how things animate on and off, and how it stays readable.
3. **Gameplay loop, modes and engagement (plan).** What makes a run fun, what pulls the player back (goals, progression, daily things, records), which modes to have, and how they fit the UI on the paper.
4. **Paper zones.** The sheet changes as you drive (white, sketch, kraft, recycled, maybe sticky notes or crumpled paper), with a visible seam or torn edge between zones.
5. **Garage and car collection.** Coins buy cars at fixed, visible prices, each car handles differently (grip, turn rate, slide), and paints are cosmetic colours. Needs low-poly cars from Raseel, plus the paper car once found.

## Later

6. Phone test: drift feel, smoothness, tilted 3D view spikes (decide: lower 3D resolution, smaller paper patch, or leave), compressed object pictures.
7. Package name: keep `dev.raseel.findinglight` or switch.
8. The area outside the track: what's on the paper around the road.
9. **In-game radio:** let the player pick or skip background tracks while driving (music is in the dev settings for now).
10. Release build: app bundle, low-poly cars, around 30–35 MB.
11. Store listing: new Doodle Drift screenshots and text (replace the old Finding Light ones).
12. **Ad rewards (last).** Opt-in only: continue once per run, double coins, daily bonus.
