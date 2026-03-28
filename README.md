<div align="center">

# 💰 FS25 Tax Mod
### *Realistic Annual Farm Taxation*

[![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_TaxMod/total?style=for-the-badge&logo=github&color=4caf50&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_TaxMod/releases)
[![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_TaxMod?style=for-the-badge&logo=tag&color=76c442&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_TaxMod/releases/latest)
[![License](https://img.shields.io/badge/license-CC%20BY--NC--ND%204.0-lightgrey?style=for-the-badge&logo=creativecommons&logoColor=white)](https://creativecommons.org/licenses/by-nc-nd/4.0/)

<br>

**Running a farm means paying taxes — once a year, just like real life.**

Taxes accumulate silently throughout the year and are collected each March. In December you get an advance warning so you can plan your spending before year-end. Falls below your minimum balance? Tax is skipped.

`Singleplayer` • `Multiplayer` • `Persistent saves` • `Console commands`

</div>

---

## How It Works

Real farm businesses don't pay tax on every transaction — they settle up annually. This mod works the same way:

1. **Throughout the year** — income-based tax accumulates in the background. Nothing is deducted yet.
2. **December** — a notification shows your estimated tax bill, what percentage of your current balance it represents, and the total accumulated so far. Time to decide whether to spend more before year-end.
3. **March** — the full bill is collected. The amount is `accumulated × annual rate`.

Your minimum balance is always protected — if the tax payment would drop you below it, the payment is skipped for that year.

---

## Features

- **Annual tax cycle** — accumulates daily, paid once in March
- **December advisory** — estimated bill, % of balance, and accumulated total shown in advance
- **Configurable annual tax rate** — Low (2%), Medium (5%), or High (10%)
- **Transaction tax rate** — separate Low (1%), Medium (2%), or High (3%) rate on daily income that feeds the accumulator
- **Minimum balance protection** — payment is skipped if your balance is too low
- **HUD overlay** — always-visible panel showing current rate, annual accumulated, estimated March payment, and a countdown to the next tax event
- **In-game notifications** for payment and advisory events
- **Persistent statistics** — total taxes paid, returned, and running annual accumulation survive saves
- **Full console control** — adjust everything without leaving the game

---

## HUD

The Tax HUD shows at a glance:

| Row | Description |
|-----|-------------|
| TAX MOD | Status (ON / OFF) |
| Rate | Current transaction rate and annual rate |
| Min balance | Your protected floor |
| Annual accumulated | Tax built up so far this year |
| Est. March payment | Projected bill (accumulated × annual rate) in orange |
| Next tax event | Months until payment (red) or advisory (blue) |
| Total paid / returned | Running lifetime totals |
| Recent Activity | Last few tax events |

Toggle the HUD with **T**. Right-click to drag or resize it.

---

## Settings

Access via **ESC → Settings → General** (scroll to the Tax Mod section):

| Setting | Options | Default |
|---------|---------|---------|
| Enable Mod | Yes / No | Yes |
| Tax Rate | Low (1%) / Medium (2%) / High (3%) | Medium |
| Annual Tax Rate | Low (2%) / Medium (5%) / High (10%) | Medium |
| Notifications | Yes / No | Yes |
| Show HUD | Yes / No | Yes |

---

## Console Commands

Type `tax` in the developer console (`~` key) for the full list.

| Command | Description |
|---------|-------------|
| `tax` | Show all commands |
| `taxStatus` | Show current settings and statistics |
| `taxEnable` / `taxDisable` | Toggle tax system |
| `taxRate low\|medium\|high` | Set transaction tax rate |
| `taxAnnualRate low\|medium\|high\|[0.01-0.30]` | Set annual tax rate (e.g. `taxAnnualRate 0.08` for 8%) |
| `taxMinimum [amount]` | Set minimum balance threshold |
| `taxStatistics` | Show running tax statistics |
| `taxSimulate` | Simulate a tax cycle immediately |
| `taxDebug [0-3]` | Set debug verbosity |

---

## Installation

Drop the `FS25_TaxMod.zip` into your mods folder:
```
%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\
```

---

## License

[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/) — All rights reserved. No redistribution or modification without permission.
