# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2026-10-16

### Added
- Initial port of Kanto Life to the Gen2Recomped mod API (mod api 2).
- Support for Generations 1-4: Gen 1 (Red/Blue/Yellow) and Gen 2
  (Gold/Silver/Crystal) reuse the proven gen1recomp-era modules through the
  G2RCompat compatibility facade; Gen 3 (FireRed/LeafGreen/Emerald) and Gen 4
  (Platinum) run the new AmbientCore engine directly on the Gen2Recomped
  world API.
- Ambient humans and Pokémon NPCs with daily routines, agendas, wandering,
  sleep schedules, lifelike behaviors, NPC-to-NPC conversations, walking
  companions, and fly/teleport/surf travel departures.
- 5th-interaction events in every supported generation: persistent per-NPC
  interaction counts with item gifts, trade offers, or battles for humans and
  item gifts or wild encounters for Pokémon, with cooldowns.
- Per-generation movement adapters (lib/GenMoveAdapter.lua): Gen 1/2
  movement/range string protocol, Gen 3 native movementType support with
  string fallback, Gen 4 direction + movementRangeX/Z wander box.
- Install hygiene: clears stale mod save data on fresh install, update, and
  reinstall so new builds never drive on old state.

### Notes
- Gen 4 (Platinum) support is experimental: Gen2Recomped's Gen 4 support is
  itself experimental, and NPC features there have not been verified in-game.
