-- Auto-test hors jeu de la logique pure : lua selfcheck.lua
-- CreateFrame est absent hors client, la partie UI est ignorée par le module.
local NS = {}
assert(loadfile("Locale/enUS.lua"))("ForeverMeter", NS)
assert(loadfile("ForeverMeter.lua"))("ForeverMeter", NS)
local FM = ForeverMeter

assert(FM.FormatValue(900) == "900" and FM.FormatValue(12345) == "12.3k" and FM.FormatValue(2500000) == "2.50M")
assert(FM.FormatTime(125) == "2:05")

assert(FM.FormatRow(12345, 1234, 24690, false) == "12.3k (1.2k/s, 50.0%)")
assert(FM.FormatRow(12345, 1234, 0, false) == "12.3k (1.2k/s, 0.0%)")
assert(FM.FormatRow(12345, 1234, nil, true) == "12345 (1234/s)", "en combat : format brut, sans comparaison")

for _, m in ipairs(FM.MODES) do assert(FM.MODE_INFO[m], m) end
assert(FM.MODE_INFO.damage.type == 0 and FM.MODE_INFO.heal.type == 2 and FM.MODE_INFO.taken.type == 7)

local t = FM.SortThreat({
	{ name = "Bob", tanking = false, pct = 80 }, { name = "Tank", tanking = true, pct = 100 }, { name = "Alice", tanking = false, pct = 95 },
})
assert(t[1].name == "Tank" and t[2].name == "Alice" and t[3].name == "Bob")
assert(FM.ShouldWarn({ tanking = false, pct = 92 }, 90) and not FM.ShouldWarn({ tanking = true, pct = 100 }, 90))
assert(FM.ComputeTps({ v = 100, t = 10 }, 300, 12) == 100 and FM.ComputeTps({ v = 300, t = 10 }, 100, 12) == 0)

print("selfcheck OK")
