from tabulate import tabulate
import csv
import math

# ______________________________________-
rsival = 75
rsich = True  # To check RSI set it to True else False
startingstoplosslength = -0.5  # must be negative
five = 0.1
margin = 660
targetincrement = 3
trailloss = 4.5
rsicheck = True
lotlimit = 1
lot = 1  # default value of lot
lotcal = False  # to calculate lot set it to True else false
# _______________________________________


# volume - price strength
output = [["SNO", "Time", "Open", "High", "Low", "Close", "Status", "Target Profit", "Stop Loss", "Lot Size", "Profit/Loss", "Net Profit"]]
netprof = 0.0


def trade(opening, loss, target, data, lot, net, trailloss, targetincrement):
    lin = []
    lin.append(opening + 2)
    lin.append(data[opening][0])
    lin.append(data[opening][1])
    lin.append(data[opening][2])
    lin.append(data[opening][3])
    lin.append(data[opening][4])
    lin.append("Started(Buying)")
    lin.append(target)
    lin.append(loss)
    lin.append(lot)
    lin.append(0)
    lin.append(net)
    output.append(list(lin))
    lin.clear()
    extra = 0

    for counter in range(opening, len(data)):
        extra += 1
        line = data[counter]
        high = float(line[2])
        op = float(line[1])
        low = float(line[3])
        clos = float(line[4])

        if low <= loss:
            lin.append(counter + 2)
            lin.append(data[counter][0])
            lin.append(data[counter][1])
            lin.append(data[counter][2])
            lin.append(data[counter][3])
            lin.append(data[counter][4])
            lin.append("Stopped at Stop Loss(Buying)")
            lin.append(target)
            lin.append(loss)
            lin.append(lot)
            lost = (loss - float(data[opening][1])) * lot * margin
            lin.append(lost)
            net += lost
            lin.append(net)
            output.append(list(lin))
            return extra, net
        elif high >= target:
            lin.append(counter + 2)
            lin.append(data[counter][0])
            lin.append(data[counter][1])
            lin.append(data[counter][2])
            lin.append(data[counter][3])
            lin.append(data[counter][4])
            lin.append("Target Achieved(Buying)")
            lin.append(target)
            lin.append(loss)
            lin.append(lot)
            profit = (lot * targetincrement * margin)
            net += profit
            lin.append(profit)
            lin.append(net)
            output.append(list(lin))
            return extra, net

        # Trailing stop: only move the stop up, never down
        if clos - op >= five:
            new_loss = op - trailloss
            if new_loss > loss:
                loss = new_loss
        elif clos - op <= -five:
            new_loss = clos - trailloss
            if new_loss > loss:
                loss = new_loss

    return extra, net


with open("OANDA_USDJPY, 240.csv", mode="r") as csvfile:
    file = csv.reader(csvfile)
    data = []
    for lines in file:
        a0 = lines[0]   # time
        a1 = lines[1]   # open
        a2 = lines[2]   # high
        a3 = lines[3]   # low
        a4 = lines[4]   # close
        a5 = lines[5]   # exit arrows
        a6 = lines[6]   # parabolicsar
        a7 = lines[7]   # ema
        a8 = lines[8]   # basis
        a9 = lines[9]   # upper
        a10 = lines[10]  # lower
        a11 = lines[11]  # ema
        a12 = lines[12]  # vwap
        a13 = lines[13]  # volume
        a14 = lines[14]  # rsi
        a15 = lines[15]  # centre line
        a16 = lines[16]  # volume strength
        a17 = lines[17]  # price strength
        a18 = lines[18]  # ATR
        line = [a0, a1, a2, a3, a4, a13, a8, a9, a10, a12, a14, a15, a16, a17]
        data.append(line)

    del data[0]

    counter = 0
    while counter < len(data) - 1:
        i = data[counter]

        if rsich:
            rsicheck = float(i[10]) > rsival

        if float(i[12]) < float(i[13]) and float(i[4]) > float(i[6]) and float(i[4]) > float(i[9]) and rsicheck:
            start = counter
            op = 0.0
            loss = startingstoplosslength
            for cand in range(start, -1, -1):
                candle = data[cand]
                op = float(candle[1])
                clos = float(candle[4])
                if clos - op >= five and float(data[counter + 1][1]) - op > five:
                    loss = op - trailloss
                    break
            if math.isclose(loss, startingstoplosslength):
                loss += float(data[counter + 1][1])

            target = float(data[counter + 1][1]) + targetincrement

            if lotcal:
                lot = 4 / (float(data[counter + 1][1]) - loss)
                if lot > lotlimit:
                    lot = lotlimit
            ext, netnew = trade(counter + 1, loss, target, data, lot, netprof, trailloss, targetincrement)
            counter += ext
            netprof = netnew
        else:
            counter += 1

print(tabulate(output, tablefmt="grid"))
print("Net profit is ", output[-1][-1])
del output[0]

for i in range(0, len(output)):
    del output[i][11]
with open('output1.csv', mode='w', newline='') as file:
    writer = csv.writer(file)
    writer.writerows(output)
