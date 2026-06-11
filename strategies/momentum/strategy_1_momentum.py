import pandas as pd

df = pd.read_csv("OANDA_XAUUSD, 240.csv")
df["green"] = df["close"] > df["open"]
df["red"] = df["close"] < df["open"]

df = df.drop("Exit Arrows", axis=1)
df = df.drop("ParabolicSAR", axis=1)
df = df.drop("EMA", axis=1)
df = df.drop("Basis", axis=1)
df = df.drop("Upper", axis=1)
df = df.drop("Lower", axis=1)
df = df.drop("EMA.1", axis=1)
df = df.drop("VWAP", axis=1)
df = df.drop("RSI", axis=1)
df = df.drop("Centre line", axis=1)
df = df.drop("Volume strength", axis=1)
df = df.drop("Price strength", axis=1)
df = df.drop("ATR", axis=1)

trade = []
xbuying = 1   # how far below candle low to place SL for buys
xselling = 1  # how far above candle high to place SL for sells

ybuying = [1, 3, 1]
yselling = [1, 3, 1]

ivariable = 100   # maximum SL for this instrument
partitions = 10
steplen = ivariable / partitions
pointa = 4
pointb = 5

multiplier = 1
takeprofit = 0
stoploss = 0
buying = False
selling = False

for i in range(1, len(df) - 1):
    # Check TP/SL exits BEFORE checking for new entries so we don't open and
    # close on the same bar (fixes lookahead bias).
    if buying:
        if df["high"].iloc[i] >= takeprofit:
            lst = list(df.iloc[i])
            lst.append("Buying finished at Take profit")
            lst.append(multiplier)
            lst.append(0)
            lst.append(trade[-1][-2] * multiplier)
            trade.append(lst)
            buying = False
        elif df["low"].iloc[i] <= stoploss:
            lst = list(df.iloc[i])
            lst.append("Buying finished at Stop loss")
            lst.append(-1)
            lst.append(0)
            lst.append(trade[-1][-2] * -1)
            trade.append(lst)
            buying = False

    if selling:
        if df["low"].iloc[i] <= takeprofit:
            lst = list(df.iloc[i])
            lst.append("Selling finished at Take profit")
            lst.append(multiplier)
            lst.append(0)
            lst.append(trade[-1][-2] * multiplier)
            trade.append(lst)
            selling = False
        elif df["high"].iloc[i] >= stoploss:
            lst = list(df.iloc[i])
            lst.append("Selling finished at Stop loss")
            lst.append(-1)
            lst.append(0)
            lst.append(trade[-1][-2] * -1)
            trade.append(lst)
            selling = False

    # Buying entry conditions (only when flat)
    if (
        df["green"].iloc[i]
        and df["green"].iloc[i - 1]
        and not selling
        and not buying
    ):
        buying = True
        lst = list(df.iloc[i + 1])
        lst.append("Buying started")
        stoploss = df["low"].iloc[i] - xbuying
        stoplosslen = df["open"].iloc[i + 1] - stoploss

        if stoplosslen < pointa * steplen:
            takeprofit = df["open"].iloc[i + 1] + (df["open"].iloc[i + 1] - stoploss) * ybuying[0]
            multiplier = ybuying[0]
        elif stoplosslen < pointb * steplen:
            takeprofit = df["open"].iloc[i + 1] + (df["open"].iloc[i + 1] - stoploss) * ybuying[1]
            multiplier = ybuying[1]
        else:
            takeprofit = df["open"].iloc[i + 1] + (df["open"].iloc[i + 1] - stoploss) * ybuying[2]
            multiplier = ybuying[2]

        lst.append(0)
        lst.append(df["open"].iloc[i + 1] - stoploss)
        lst.append(0)
        trade.append(lst)

    # Selling entry conditions (only when flat)
    if (
        df["red"].iloc[i]
        and df["red"].iloc[i - 1]
        and not buying
        and not selling
    ):
        selling = True
        lst = list(df.iloc[i + 1])
        lst.append("Selling started")
        stoploss = df["high"].iloc[i] + xselling
        stoplosslen = stoploss - df["open"].iloc[i + 1]

        if stoplosslen < pointa * steplen:
            takeprofit = df["open"].iloc[i + 1] + (df["open"].iloc[i + 1] - stoploss) * yselling[0]
            multiplier = yselling[0]
        elif stoplosslen < pointb * steplen:
            takeprofit = df["open"].iloc[i + 1] + (df["open"].iloc[i + 1] - stoploss) * yselling[1]
            multiplier = yselling[1]
        else:
            takeprofit = df["open"].iloc[i + 1] + (df["open"].iloc[i + 1] - stoploss) * yselling[2]
            multiplier = yselling[2]

        lst.append(0)
        lst.append(stoploss - df["open"].iloc[i + 1])
        lst.append(0)
        trade.append(lst)

# Output the results
netpips = 0.0
netmultiplier = 0
for i in range(len(trade)):
    netpips += trade[i][-1]
    netmultiplier += trade[i][11]
    trade[i].append(netpips)
    trade[i].append(netmultiplier)

# O(n) maximum drawdown calculation
startdate = 0
finaldate = 0
maxloss = 0
peak_val = trade[0][-2]
peak_idx = 0
for j in range(1, len(trade)):
    drawdown = trade[j][-2] - peak_val
    if drawdown < maxloss:
        maxloss = drawdown
        startdate = peak_idx
        finaldate = j
    if trade[j][-2] > peak_val:
        peak_val = trade[j][-2]
        peak_idx = j

startmulti = 0
finalmulti = 0
minmulti = 0
peak_multi = trade[0][-1]
peak_multi_idx = 0
for j in range(1, len(trade)):
    dd = trade[j][-1] - peak_multi
    if dd < minmulti:
        minmulti = dd
        startmulti = peak_multi_idx
        finalmulti = j
    if trade[j][-1] > peak_multi:
        peak_multi = trade[j][-1]
        peak_multi_idx = j

output = pd.DataFrame(trade, columns=["time", "open", "high", "low", "close", "volume", "green", "red", "action", "y multiplier", "stop loss", "pips", "Net Pips", "Net multiplier"])
print("Minimum value of Net Pips is ", maxloss, " between the dates ", trade[startdate][0], " and ", trade[finaldate][0])
print("pips sum is ", output["pips"].sum())
