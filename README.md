# EquatePlus Extension for MoneyMoney

A MoneyMoney extension for tracking EquatePlus employee share plan portfolios and downloading account statements.

> **Based on the original work by [neatc0der](https://github.com/neatc0der/equateplus-moneymoney).
> This fork adds SMS OTP authentication support and several robustness improvements.**

---

## Features

- Portfolio synchronisation (positions, quantities, purchase prices, market prices)
- Statement download from the EquatePlus document library
- **EquateAccess App** (FIDO/QR code) authentication
- **SMS security code (OTP)** authentication — added in this fork
- Datacenter failover with host pinning (EMEA / NA / primary)
- Robust login detection across datacenter variants
- Cumulative position mode (aggregate positions per security)

## Requirements

- [MoneyMoney](https://moneymoney-app.com) for macOS
- An active EquatePlus participant account

## Installation

1. Download `EquatePlus.lua`
2. In MoneyMoney, open **Help → Show Database in Finder**
3. Place `EquatePlus.lua` in the **Extensions** folder
4. Restart MoneyMoney
5. Add a new account and search for **EquatePlus**

## Authentication

Two authentication methods are supported:

| Method | Description |
|---|---|
| EquateAccess App | Scan a QR code with the EquateAccess mobile app |
| SMS OTP | Enter the one-time code sent to your registered mobile number |

MoneyMoney will prompt for the appropriate method automatically based on your account configuration.

## Account types

The extension registers four bank codes to control display mode:

| Bank code | Description |
|---|---|
| `EquatePlus` | Individual positions |
| `EquatePlus SE` | Individual positions (SE plan) |
| `EquatePlus (cumulative)` | Positions aggregated per security |
| `EquatePlus SE (cumulative)` | Aggregated positions (SE plan) |

## Debugging

Prefix your username with `#` to enable debug output in MoneyMoney's log window:

```
#youruserid
```

Use `##` to also enable secrets in the log output (tokens, cookies). Use with care.

## Disclaimer

This extension is not affiliated with or endorsed by EquatePlus or its operator Equatex AG.
Use at your own risk. No warranty is provided.

## Credits

Original extension by [neatc0der](https://github.com/neatc0der/equateplus-moneymoney).
SMS OTP support, datacenter failover, and login robustness improvements by [DerSchiman](https://github.com/DerSchiman/equateplus-moneymoney).
