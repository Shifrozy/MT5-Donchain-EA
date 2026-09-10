# 📈 MetaTrader 5 Multi-Timeframe Donchian Channel Expert Advisor (EA)

[![MetaTrader 5](https://img.shields.io/badge/Platform-MetaTrader%205-007acc.svg)](https://www.metatrader5.com/)
[![MQL5](https://img.shields.io/badge/Language-MQL5-blue.svg)](https://www.mql5.com/)
[![Version](https://img.shields.io/badge/Version-1.20-brightgreen.svg)](https://github.com/Shifrozy/MT5-Donchain-EA)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

An institutional-grade **Multi-Timeframe Donchian Channel Expert Advisor** engineered in **MQL5** for MetaTrader 5. The EA executes trades based on strict, live simultaneous price touches across up to 4 configurable timeframes, backed by a cross-pair **Shared Basket Money Management** system with combined Floating and Realized Profit/Loss daily circuit breakers.

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Strategy Architecture & Logic](#-strategy-architecture--logic)
  - [PLOT_SHIFT = 1 Calculation](#1-plot_shift--1-calculation)
  - [Simultaneous Live Touch Confirmation](#2-simultaneous-live-touch-confirmation)
  - [Strategy Modes](#3-strategy-modes)
- [Shared Basket Money Management](#-shared-basket-money-management)
  - [Daily Floating + Realized P/L Tracking](#daily-floating--realized-pl-tracking)
  - [Automatic Daily Lock & Reset](#automatic-daily-lock--reset)
- [Visual System & On-Chart Dashboard](#-visual-system--on-chart-dashboard)
- [Input Parameters Reference](#-input-parameters-reference)
- [Installation & Setup](#-installation--setup)
- [Multi-Chart Portfolio Configuration](#-multi-chart-portfolio-configuration)
- [Disclaimer](#-disclaimer)

---

## 🌟 Overview

The **Donchian Channel EA** combines classic breakout/reversal channel principles with modern multi-timeframe synchronization and cross-asset portfolio risk controls. Unlike standard single-timeframe robots, this EA monitors 4 independent timeframes simultaneously in real time and only triggers trades when the current market price is actively reaching or exceeding Donchian boundaries across a user-defined threshold of timeframes.

---

## ⚡ Key Features

- **4-Timeframe Simultaneous Monitoring**: Monitor up to 4 arbitrary timeframes (e.g., M5, M15, M30, H1) regardless of which chart timeframe the EA is attached to.
- **Strict Real-Time Touch Verification**: Zero memory retention — touches must be active at the exact same moment on the live tick.
- **Exact PLOT_SHIFT = 1 Alignment**: Matches standard shifted Donchian Channel indicators precisely, avoiding lookahead bias.
- **Dual Execution Modes**:
  - `Same Direction`: Breakout trend following (Upper = BUY, Lower = SELL).
  - `Inverse Direction`: Mean-reversion bouncing (Upper = SELL, Lower = BUY).
- **Shared Basket Money Management**: Cross-chart portfolio manager using Global Variables and comment tags `[B{ID}]`.
- **Complete Daily Loss/Profit Circuit Breaker**: Evaluates combined **Floating P/L + Closed Realized Deals** for the current day.
- **Automated & Manual Lock Reset**: Automatically resets at 00:00 broker server time, with an instant manual reset toggle.
- **Seamless Visual Overlay**:
  - Automatically loads and attaches the Donchian indicator (`ChartIndicatorAdd`).
  - Embedded resource `#resource` for standalone operation.
  - Built-in stepped line fallback renderer with matching price labels.
  - Buy/Sell Wingdings signal arrows placed directly on entry bars.
- **Real-Time Comment Dashboard**: Comprehensive live HUD displaying timeframe levels, live touch markers (`<< HIT`), and basket P/L metrics.

---

## 🔬 Strategy Architecture & Logic

```
                    ┌─────────────────────────┐
                    │    Live Tick Received   │
                    └────────────┬────────────┘
                                 │
                 ┌───────────────┴───────────────┐
                 │  Check Basket Lock & Open Pos │
                 └───────────────┬───────────────┘
                                 │
           ┌─────────────────────┴─────────────────────┐
           ▼                                           ▼
┌──────────────────────┐                    ┌──────────────────────┐
│ Evaluate TF 1 (M5)   │                    │ Evaluate TF 3 (M30)  │
│ Upper / Lower Touch  │                    │ Upper / Lower Touch  │
└──────────┬───────────┘                    └──────────┬───────────┘
           │                                           │
           ▼                                           ▼
┌──────────────────────┐                    ┌──────────────────────┐
│ Evaluate TF 2 (M15)  │                    │ Evaluate TF 4 (H1)   │
│ Upper / Lower Touch  │                    │ Upper / Lower Touch  │
└──────────┬───────────┘                    └──────────┬───────────┘
           │                                           │
           └─────────────────────┬─────────────────────┘
                                 │
               ┌─────────────────┴─────────────────┐
               │ Simultaneous Confirmed TFs >= N?  │
               └─────────────────┬─────────────────┘
                                 │
                     ┌───────────┴───────────┐
                     ▼                       ▼
                  [ YES ]                 [ NO ]
                     │                       │
         ┌───────────┴───────────┐       [ Wait ]
         │ Execute Order (SL/TP) │
         │ Tag: [B{Basket_ID}]   │
         │ Draw Signal Arrow     │
         └───────────────────────┘
```

### 1. PLOT_SHIFT = 1 Calculation

The EA implements the exact shifted logic of the reference Donchian indicator:

$$\text{Upper Level} = \max(\text{High}_{1}, \dots, \text{High}_{N})$$
$$\text{Lower Level} = \min(\text{Low}_{1}, \dots, \text{Low}_{N})$$
$$\text{Middle Level} = \frac{\text{Upper Level} + \text{Lower Level}}{2}$$

By calculating historical extremes starting from bar index `1` for $N$ bars (`Period_of_Channel`), the level displayed at current forming bar `0` perfectly aligns with the standard 1-bar forward plot shift.

### 2. Simultaneous Live Touch Confirmation

- **No Touch Memory**: Old touches from previous bars that pulled back are strictly discarded.
- **No Distance Tolerance**: Current price must reach or penetrate the exact Donchian boundary at the tick moment.
- **Selectable Confluence (`Confirm_Directions`)**:
  - `1`: Any 1 of the 4 timeframes touching.
  - `2`: At least 2 timeframes touching simultaneously.
  - `3`: At least 3 timeframes touching simultaneously (Recommended).
  - `4`: All 4 timeframes touching simultaneously.

### 3. Strategy Modes

| Channel Boundary Hit | `SameDirection` Mode | `InverseDirection` Mode |
|:---|:---:|:---:|
| **Upper Donchian Level** | 🟢 **BUY** (Breakout) | 🔴 **SELL** (Reversal) |
| **Lower Donchian Level** | 🔴 **SELL** (Breakout) | 🟢 **BUY** (Reversal) |

---

## 💰 Shared Basket Money Management

Multiple EA instances sharing the same `Basket_ID` operate as a synchronized portfolio unit across different currency pairs.

```
┌─────────────────────────────────────────────────────────────────┐
│                      SHARED BASKET (ID: 1)                      │
├───────────────────┬───────────────────┬─────────────────────────┤
│ EURUSD (EA #1)    │ GBPUSD (EA #2)    │ USDJPY (EA #3)          │
│ Floating: -$200   │ Floating: -$150   │ Floating: -$250         │
├───────────────────┴───────────────────┴─────────────────────────┤
│ Closed Today Realized Loss: -$400                               │
├─────────────────────────────────────────────────────────────────┤
│ COMBINED BASKET TOTAL P/L = -$1,000                             │
│ 🚨 Threshold Reached -> Close All Positions -> Daily Lock Set    │
└─────────────────────────────────────────────────────────────────┘
```

### Daily Floating + Realized P/L Tracking

Standard EAs only measure floating loss of currently open trades. This EA tracks **Total Basket Risk**:

$$\text{Total Basket P/L} = \text{Floating P/L} + \text{Daily Realized P/L (Closed Deals)}$$

If three trades hit Stop Loss during the morning for $-\$600$, and active trades are currently at $-\$400$, the total basket loss is recognized as $-\$1,000$. If `Max_Basket_Loss_USD = 1000`, the circuit breaker immediately triggers.

### Automatic Daily Lock & Reset

1. **Close All**: When `Max_Basket_Loss_USD` or `Max_Basket_Profit_USD` is hit, all open trades with matching `[B{ID}]` are closed across all symbols.
2. **Lockout**: Trading is blocked for the rest of the day across all instances.
3. **Daily Reset**: At `00:00` server time, the lock automatically clears.
4. **Manual Override**: Setting `Reset_Daily_Lock = true` in input parameters instantly unlocks the basket anytime.

---

## 🖥 Visual System & On-Chart Dashboard

| Screenshot | Description |
|:---:|:---|
| ![Buy Signal](Buy%20Signal.jpg) | **Buy Signal Visualization**: Channel bands and simultaneous breakout alignment across timeframes. |
| ![Sell Signal](Sell%20Signal.jpg) | **Sell Signal Visualization**: Lower channel boundary confirmation with entry signals. |
| ![EA Inputs](EA%20Inputs.jpg) | **Intuitive Input Configuration**: Clean grouping of core and basket risk parameters. |

---

## ⚙️ Input Parameters Reference

### Core Strategy Settings

| Parameter | Type | Default | Description |
|:---|:---:|:---:|:---|
| `Strategy_Mode` | `ENUM_STRATEGY_MODE` | `SameDirection` | `SameDirection` (Trend) or `InverseDirection` (Reversal) |
| `Confirm_Directions` | `int` | `3` | Required number of confirming timeframes (1 to 4) |
| `Timeframe_1` | `ENUM_TIMEFRAMES` | `PERIOD_M5` | First monitored timeframe |
| `Timeframe_2` | `ENUM_TIMEFRAMES` | `PERIOD_M15` | Second monitored timeframe |
| `Timeframe_3` | `ENUM_TIMEFRAMES` | `PERIOD_M30` | Third monitored timeframe |
| `Timeframe_4` | `ENUM_TIMEFRAMES` | `PERIOD_H1` | Fourth monitored timeframe |
| `Period_of_Channel` | `int` | `50` | Lookback period for highest high / lowest low calculation |
| `Showprice_of_the_Level` | `bool` | `true` | Show on-chart price level labels and channel bands |
| `LotSize` | `double` | `1.25` | Fixed lot size per trade |
| `TP_Pips` | `int` | `40` | Take Profit distance in pips |
| `SL_Pips` | `int` | `40` | Stop Loss distance in pips |
| `Magic_Number` | `int` | `32134` | Unique EA identifier per chart/symbol |
| `Comment_Text` | `string` | `""` | Custom trade comment prefix |

### Basket Money Management Settings

| Parameter | Type | Default | Description |
|:---|:---:|:---:|:---|
| `Enable_Basket_Floating_PL` | `bool` | `true` | Enable/Disable shared basket risk management |
| `Basket_ID` | `int` | `1` | Shared group ID linking multiple chart instances |
| `Max_Basket_Loss_USD` | `double` | `1000.0` | Maximum allowable daily basket loss in USD (`0` = Disabled) |
| `Max_Basket_Profit_USD` | `double` | `2000.0` | Maximum target daily basket profit in USD (`0` = Disabled) |
| `Lock_Trading_After_Target` | `bool` | `true` | Lock trading until 00:00 server time once target/loss is hit |
| `Reset_Daily_Lock` | `bool` | `false` | Set to `true` to manually reset/unlock trading immediately |

---

## 📦 Installation & Setup

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/Shifrozy/MT5-Donchain-EA.git
   ```

2. **Copy Files to MetaTrader 5 Directory**:
   - Open MT5 $\rightarrow$ **File** $\rightarrow$ **Open Data Folder**.
   - Copy `Donchian_Channel_EA.mq5` into `MQL5/Experts/`.
   - Copy `Donchian Channel.mq5` and `Donchian Channel.ex5` into `MQL5/Indicators/`.

3. **Compile in MetaEditor**:
   - Open MetaEditor (`F4`).
   - Navigate to `Experts` $\rightarrow$ Open `Donchian_Channel_EA.mq5`.
   - Press **Compile** (`F7`).

4. **Attach to Chart**:
   - Drag the EA onto any symbol chart.
   - Ensure **"Allow Algo Trading"** is checked in MT5 and in the EA inputs.

---

## 🌐 Multi-Chart Portfolio Configuration

To trade multiple pairs under a unified basket:

1. Open separate charts for each symbol (e.g., EURUSD, GBPUSD, USDJPY, AUDUSD).
2. Attach `Donchian_Channel_EA` to each chart.
3. Configure settings:
   - Give each chart a **Unique `Magic_Number`** (e.g., `1001`, `1002`, `1003`).
   - Keep the **Same `Basket_ID`** (e.g., `1`) across all charts.
   - Keep the **Same `Max_Basket_Loss_USD` and `Max_Basket_Profit_USD`** values.
4. The EAs will coordinate atomically in real time to enforce your global portfolio limits.

---

## ⚠️ Disclaimer

*Trading foreign exchange and CFDs on margin carries a high level of risk and may not be suitable for all investors. Past performance is no guarantee of future results. Always backtest and demo-test thoroughly before deploying with real capital.*

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
