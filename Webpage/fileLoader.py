import os
files = os.listdir("hornsamples")
i = 0
for x in files:
    print("samples[" + str(i) + "] = loadSound('hornsamples/" + x + "', progress);")
    print("horntimes1[" + str(i) + "] = " + str(int(filter(str.isdigit, x))) + ";")
    i = i+1