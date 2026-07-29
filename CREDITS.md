# Credits & Attribution

SmartPVP is a **3.3.5a (Conquest of Azeroth / Ascension) port and fusion** of existing addons.
It would not exist without the work of the original authors.

## Original addons

### PvPStatsClassic — by Redridge Police
- Source: https://www.curseforge.com/wow/addons/pvpstatsclassic
- Provides: kill/death tracking, kill streaks, achievements, minimap button,
  the cross-player network/leaderboard, and the statistics engine.
- In SmartPVP this lives under `killboard/`.

### meebeegeeStats — by GamerLegend
- Provides: battleground & arena match tracking, per-map stats, healing/damage
  tracking, the Glory system, and seasons.
- In SmartPVP this lives under `matches/`.

## Bundled libraries
- **Ace3** (AceComm-3.0, ChatThrottleLib, CallbackHandler, LibStub, LibDataBroker,
  LibDBIcon) — https://www.wowace.com/projects/ace3 — used under their own licenses
  (see the license headers inside `killboard/Libs/`).

## What was added for this port (cccarv82)
- `killboard/Compat335.lua` — compatibility shim so the modern addons run on 3.3.5a
  (C_Timer, CombatLog reordering, C_Map, C_ChatInfo, widget method no-ops, etc.).
- `matches/embeds.xml` — 3.3.5a-compatible frame templates.
- `SmartPVP.lua`, `SmartPVP_Hub.lua`, `SmartPVP_HUD.lua`, `SmartPVP_Nemesis.lua`,
  `SmartPVP_WinRate.lua`, `SmartPVP_XP.lua`, `SmartPVP_Locale.lua`, `ClassInfo.lua`
  — the unified hub, session HUD, rivalries/win-rate/leveling views, EN/PT
  localization, and Conquest of Azeroth custom-class support.
- CoA-specific fixes: honorable-kill / scoreboard-based tracking, Death Recap
  nemesis capture, and more.

## A note on rights

All original code remains the property of its respective authors under their original
terms. This repository is a community effort to keep these tools playable on Conquest
of Azeroth. **Original authors:** if you would like attribution changes or removal,
please open an issue — it will be handled promptly and respectfully.
