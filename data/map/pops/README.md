# Who lives where in 1453

Every state lists its default mix of people. Provinces that differ (cities,
ports, frontier towns) override it. Shares are percentages and are
normalised, so they don't have to add up to exactly 100.

```
@ State Name                       <- default for every province in the state
culture religion share
culture religion.sect share        <- sect is optional (e.g. sunni.hanafi)
> Province Name                    <- this province uses its own mix instead
culture religion share
& Province Name | order strength   <- a Sufi order present there, strength 0–1
```

Cultures are listed in `../cultures.txt`. Religions and sects are listed in
`Packages/GezCore/Sources/GezCore/Faith/Religion.swift`.

Social classes (nobles, clergy, burghers, peasants, slaves) are not written
here; the game splits each group by class from the province's development
and its region's customs.

All numbers are educated estimates; there are no censuses for 1453.
