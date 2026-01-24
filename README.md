# FS25 Tax Mod

Daily tax deductions with monthly returns for **Farming Simulator 25**.  
Converted and adapted from the FS22 Tax Mod.

---

## 📌 Overview

The **FS25 Tax Mod** adds a realistic taxation system to Farming Simulator 25.  
Your farm is taxed daily based on its balance, and at the end of each month, a configurable percentage of those taxes is returned.

This mod is fully configurable via **console commands** and automatically saves settings per savegame.

---

## 🧾 Features

- 💸 **Daily tax deduction** based on farm balance
- 🔁 **Monthly tax return**
- ⚙️ Configurable **tax rates** (low / medium / high)
- 🧮 **Minimum balance protection**
- 🔔 Optional **in-game notifications**
- 📊 Detailed **tax statistics**
- 🐞 Multi-level **debug logging**
- 💾 Automatic **savegame-based settings**
- 🌐 Works in **singleplayer & multiplayer** (server-side)

---

## ⚙️ Default Settings

| Setting | Default | Description |
|------|---------|------------|
| enabled | `true` | Enable / disable the tax system |
| taxRate | `medium` | Tax rate level |
| returnPercentage | `20` | Monthly tax return percentage |
| minimumBalance | `1000` | Minimum balance before tax applies |
| showNotification | `true` | Show in-game notifications |
| showStatistics | `true` | Show statistics in console |
| debugLevel | `1` | Debug output level |

---

## 🚀 Installation

1. Download the mod `.zip`
2. Place it in: Documents/My Games/FarmingSimulator2025/mods
---

## 🔄 How It Works

- Every in-game day, the mod checks your farm balance
- If balance ≥ minimum balance → tax is deducted
- At the start of a new month → tax return is paid
- All values are tracked and saved automatically

---

## 🧠 Console Commands

| Command | Description |
|------|-------------|
| `tax` | Show command list |
| `taxStatus` | Show current settings & stats |

### ⚙️ Configuration

| Command | Example | Description |
|------|--------|------------|
| `taxEnable` | — | Enable tax system |
| `taxDisable` | — | Disable tax system |
| `taxRate [low|medium|high]` | `taxRate high` | Set tax rate |
| `taxReturn [0-100]` | `taxReturn 30` | Set return percentage |
| `taxMinimum [amount]` | `taxMinimum 2000` | Set minimum balance |

### 📊 Statistics & Debug

| Command | Description |
|------|-------------|
| `taxStatistics` | Show tax statistics |
| `taxSimulate` | Simulate tax cycle |
| `taxDebug [0-3]` | Set debug level |

---

## 📊 Tracked Statistics

- Total taxes paid
- Total tax returns
- Taxes paid this month
- Days taxed
- Months returned
- Average daily tax
- Net taxes paid

---
## ⚖️ License

All rights reserved. Unauthorized redistribution, copying, or claiming this mod as your own is **strictly prohibited**.  
Original author: **TisonK** 

---

## 📬 Support

Report bugs or request help in the comments section of the original mod page.

---

*Enjoy your farming experience!* 🌾
