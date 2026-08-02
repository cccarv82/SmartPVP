# SmartPVP

**A complete PvP suite for Conquest of Azeroth (Ascension / WoW 3.3.5a).**
Kill tracking, battleground & arena match history, a live cross-player leaderboard, per-session HUD, rivalries, win-rate and leveling-efficiency analytics — all in one window.

<!-- Replace the placeholder below with a hero screenshot of the main hub -->
![SmartPVP hub](docs/images/hero.png)

> ⚠️ **Built for Conquest of Azeroth (Ascension), client 3.3.5a (Interface 30300).**
> SmartPVP is a 3.3.5a port + fusion of two great Retail/Classic addons. See [Credits](#-credits--attribution).

> 🧪 **Early release — expect bugs.** SmartPVP is a young community project running on a heavily customized server, so rough edges and occasional bugs are normal. If something breaks or looks wrong, **please [open an issue](https://github.com/cccarv82/SmartPVP/issues)** — that's the only supported way to report problems, and detailed reports (what you did, what happened, any Lua error text) genuinely help it improve.

---

## ✨ Features

| Tab | What it does |
|-----|--------------|
| **Matches** | Full BG/Arena history — wins/losses, KB, honor, healing, per-map stats, Glory summary, seasons. |
| **Kills** | Searchable list of every enemy player you've killed (name, class, level, race, zone, last seen). |
| **Leaderboard** | Live ranking of everyone nearby running SmartPVP (auto-synced — see [Sync](#-cross-player-sync)). |
| **Statistics** | Deep breakdowns: kills by class/race/gender/zone/hour/weekday/month, K/D, streaks, and more — with the server's **custom classes**. |
| **Rivalries** | *Your Preys* (who you killed most) and *Your Nemeses* (who killed you most). |
| **Win Rate** | Per-battleground win %, wins/losses/forfeits. |
| **Leveling** | XP/hour and honor/hour by activity (BG / arena / dungeon / open world) — find the fastest way to level. |
| **Config** | Everything is configurable in-game. No commands required. |
| **Session HUD** | Movable mini-panel with live **Kills / Deaths / K-D / Streak** + current BG name. Auto-resets on entering a battleground. |

<!-- Add screenshots per feature -->
| HUD | Statistics | Leaderboard |
|-----|-----------|-------------|
| ![HUD](docs/images/hud.png) | ![Statistics](docs/images/statistics.png) | ![Leaderboard](docs/images/leaderboard.png) |

| Matches | Rivalries | Win Rate |
|---------|-----------|----------|
| ![Matches](docs/images/matches.png) | ![Rivalries](docs/images/rivalries.png) | ![Win Rate](docs/images/winrate.png) |

---

## 📦 Installation

1. Download the latest **`SmartPVP-vX.Y.Z.zip`** from the [Releases](https://github.com/cccarv82/SmartPVP/releases) page.
2. Extract it into your WoW `Interface/AddOns` folder. You should end up with:
   ```
   Interface/AddOns/SmartPVP/SmartPVP.toc
   ```
3. Restart the game (or `/reload` if already running) and make sure **SmartPVP** is enabled on the character-select AddOns list.

**Via git:**
```bash
cd "Interface/AddOns"
git clone https://github.com/cccarv82/SmartPVP.git
```

---

## 🎮 Usage

- **Minimap button** or `/spvp` — open the hub.
- `/spvp help` — list commands.

| Command | Action |
|---------|--------|
| `/spvp` | Open/close the hub |
| `/spvp hud` | Toggle the session HUD |
| `/spvp reset` | Reset the HUD session counters |
| `/spvp kills` / `board` / `stats` / `winrate` / `leveling` / `config` | Jump to a tab |
| `/spvp wipe` | Wipe **all** stored data (asks for confirmation) |

Everything is also available through the **Config** tab — you never *need* a command.

---

## 🔄 Cross-player sync

SmartPVP shares your **aggregate stats** (kills, deaths, streaks, class/zone breakdowns, achievements…) with other players running the addon, over addon-message channels (**Battleground / Raid / Party / Guild**). This powers the **Leaderboard** and the "view another player's stats" feature.

- Fully automatic — broadcasts on login, on kills, and on request from other clients.
- Cross-realm aware, de-duplicated, throttled to respect the client's message limits.
- **Private data stays local:** your kill list, rivalries, and match history are **never** broadcast — only the summary that feeds the leaderboard.

---

## 🌐 Localization

English (default) and **Português (BR)**. Switch in **Config → Language** (reload to apply).

---

## ⚠️ Known limitations (Conquest of Azeroth specifics)

CoA is a heavily modernized 3.3.5a client, but a few things differ from Retail:

- **"Your Nemeses" (who killed you)** — the client doesn't expose the killer via the combat log. SmartPVP reads it from the **Death Recap**: when you die you'll get a reminder, and **opening the Death Recap** records who killed you into Rivalries. Deaths where you don't open the recap aren't recorded.
- **Sounds** are disabled (the client doesn't play custom addon sounds).

---

## 🙏 Credits & Attribution

SmartPVP is **not original work** — it's a 3.3.5a port and fusion of two excellent addons, with a compatibility layer and CoA-specific features added on top. Huge thanks to the original authors:

- **[PvPStatsClassic](https://www.curseforge.com/wow/addons/pvpstatsclassic)** by **Redridge Police** — the kill tracking, achievements, leaderboard, and stats engine.
- **meebeegeeStats** by **GamerLegend** — the battleground/arena match tracking and Glory system.

All original rights belong to their respective authors. This repository exists to keep these tools alive and playable on Conquest of Azeroth. **If you are an original author and would like changes or removal, please open an issue and it will be addressed promptly.**

Also bundles [Ace3](https://www.wowace.com/projects/ace3) libraries (AceComm-3.0, etc.), used under their own licenses.

---

## 📄 License

This project is a **derivative/community port**. The original addons' code remains under their authors' terms. New code added for the port (compatibility shim, HUD, hub, localization, CoA features) is released to the community for use on Conquest of Azeroth. See [CREDITS.md](CREDITS.md) for details.

---

## 🐛 Bugs & contributions

**Bugs are expected** on a project this young running on a custom server — and reporting them is the best way to help.

- **Report a bug:** [open an issue](https://github.com/cccarv82/SmartPVP/issues/new). Include what you were doing, what happened, and any red Lua error text (`/console scriptErrors 1` shows errors in-game).
- **Request a feature:** issues are welcome for those too.
- **Contribute:** PRs are welcome.

Please **do not** report bugs on the original addons' pages — those authors aren't responsible for this port.

---

<sub>SmartPVP is a community project and is not affiliated with Blizzard Entertainment, the Ascension team, or the original addon authors.</sub>
