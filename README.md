# Kanto Life for Gen2Recomped

Ambient NPC life for the Gen2Recomped Pokémon engine: wandering humans and
Pokémon, daily routines, agendas, sleep, lifelike behaviors, conversations,
companions, and fly/teleport/surf travel departures — with a 5th-interaction
event system — across Generations 1-4.

This is the Kanto Life port for Gen2Recomped (mod api 2). Gen 1
(Red/Blue/Yellow) and Gen 2 (Gold/Silver/Crystal) reuse the proven
gen1recomp-era modules through the G2RCompat compatibility facade; Gen 3
(FireRed/LeafGreen/Emerald) and Gen 4 (Platinum) run the new AmbientCore
engine directly on the Gen2Recomped world API.

> **Gen 4 experimental:** Gen2Recomped's Gen 4 (Platinum) support is itself
> experimental, and Kanto Life's NPC features on Gen 4 have not been verified
> in-game. Expect rough edges.

## Features

- **Ambient humans and Pokémon** — NPCs spawn around the world and go about
  their day instead of standing frozen.
- **Routines and agendas** — NPCs follow daily routines and personal agendas:
  traveling between areas, visiting shops, resting.
- **Sleep** — NPCs sleep at night (and sometimes during the day), with
  sleep sprites and accessories where the engine provides them.
- **Lifelike behaviors** — idle behaviors, greetings, curiosity, mood-driven
  reactions, Pokémon adoration, and other small touches.
- **Conversations** — NPCs chat with each other and with the player.
- **Companions** — some NPCs (and their Pokémon) walk alongside you.
- **Travel departures** — NPCs leave areas on foot, by surf, by teleport, or
  by fly, each with its own departure animation.
- **5th interactions** — every NPC keeps a persistent interaction count.
  Talk to the same NPC five times and something happens: humans may give you
  an item, offer a trade, or challenge you to a battle; Pokémon may give you
  an item or trigger a wild encounter. Trade and item events have cooldowns.

## Installation

Install through the Gen2Recomped mod manager: drop the mod folder into the
mods directory (or install the packaged zip) and enable **Kanto Life for
Gen2Recomped** in the mod list. On first load the mod detects the active
game generation and installs the matching implementation automatically.

Requirements: Gen2Recomped engine `>=0.7.6 <2.0.0`, mod api 2.

## Options

The mod exposes options in the engine options menu (exact availability may
vary by generation):

- NPC density / spawn counts
- Sleep schedules and sleep bubbles
- Travel behavior (departure methods and frequencies)
- Conversation frequency
- Interaction event cooldowns

On install or update, the mod clears its own persisted data
(`InstallHygiene`) so new builds never drive on stale state from a previous
version.
