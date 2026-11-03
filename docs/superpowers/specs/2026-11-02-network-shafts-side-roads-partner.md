# The Network: shafts, side roads, interchange jumps, the driving partner

*2026-11-02. Changes to `2026-10-19-network-design.md`, from Luke's flight notes.*

## What Luke asked for

- Side roads, in different shapes, "that would reasonably cause the person to actually shift, while still
  staying at 'highway' speeds".
- The jumps in the interchanges. "The track starts with the player going the wrong way - all of the jumps
  are backwards and don't have indicators lit up on the signs", and "large arrow markings on these signs
  directing the player towards the jump".
- A main menu option for a driving partner, "that stays around your speed and just generally does what
  you do - i found it interesting to see a stable reference point at high speed - kind of trippy".
- "Some of the highways on the network completely straight from edge to edge."
- At the ends of all the highways, in place of the turnarounds, "a vertical shaft that turns over on
  itself and enters the same road it came from".

## What was wrong with the jumps

The jumps were one way only, and from Eridanus you drive west along E2 while E2's jump is taken east. You
met each one from behind: the deck coming down at you, the back of the board. The boards were lit, on the
side you never saw. Flipping the start wouldn't fix it (east out of Eridanus, E2's jump is behind you), so
every jump now exists every way through its crossing.

## The calls I made

- **Which highways are straight:** E2, N2 and E3. You start on E2, so the first run is dead straight.
- **Five jump crossings, four jumps each:** the centre and the middle of each edge. The corner crossings
  have cities and no jumps.
- **A jump's shape:** the exit ramp on your right forks, 4.5 deg round its arc. The ramp curves off, the
  spur runs straight on and kicks to a lip 3 km short of the crossing; the deck flies you over the crossing
  and merges with the highway 44 km past it. The numbers that decide who lands are the old ones (8.5 deg, 2
  mi, 1,500 ft, 3,000 mph and up).
- **The shaft's shape:** R 3.5 km, V 5.6 km, 41,000 ft at the top. It turns over backwards (an Immelmann's
  half loop), then rolls half a turn on the way down so you come out the right way up. Without the roll
  you'd land on the road inverted, and turning the other way in the air would be a bunt. It's two-way: from
  the left half of the road you go up the rolled side and come out of the other.
- **The sims stay flat.** A real vertical road would mean a 3D sim, in both languages, at parity. The shade
  line already has the answer: a flat sim and a view that carries everything onto the shape. The road is a
  paperclip in plan whose bulb carries the craft round; to the craft that stretch is straight.
- **Side roads only off the straight highways:** a loop has to leave and rejoin tangent, and the S-bends
  have no room for that. Twelve, on E2, N2 and E3.
- **There was no main menu.** The game launched straight into a track ("Nothing is on a menu"). So I built
  a small one, on the button that already says menu: a tap opens it, the hold still steps the track. That
  moves the control scheme from the tap into the menu.
- **The partner is in the view, not the sims:** no collision, no parity, on every track.

## Limits, as built

- The minimap shows a shaft's plan (a bulb), not its shape: read it as a marker with your arrow going round.
- Hands off, the craft creeps sideways up to ~90 m on its way through a shaft (the tow bar's reaction to the
  plan's bulb). It's inside the road and a touch corrects it; a slow pass can scrape the wall's forcefield.
- Far off, the shaft's silhouette is a flat ribbon; the hoops and lights come in with the chunks at 20 km.
