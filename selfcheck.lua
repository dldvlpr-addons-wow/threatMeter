-- Auto-test hors jeu de la logique pure : lua selfcheck.lua
-- CreateFrame est absent hors client, la partie UI est ignorée par le module.
local NS = {}
for _, code in ipairs({ "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
	assert(loadfile("Locale/" .. code .. ".lua"))("ForeverMeter", NS)
end
assert(loadfile("ForeverMeter.lua"))("ForeverMeter", NS)
local FM = ForeverMeter

assert(FM.FormatValue(900) == "900" and FM.FormatValue(12345) == "12.3k" and FM.FormatValue(2500000) == "2.50M")
assert(FM.FormatTime(125) == "2:05")

assert(FM.FormatRow(12345, 1234, 24690, false) == "12.3k (1.2k/s, 50.0%)")
assert(FM.FormatRow(12345, 1234, 0, false) == "12.3k (1.2k/s, 0.0%)")
assert(FM.FormatRow(12345, 1234, nil, true) == "12345 (1234.0/s)", "en combat : format brut, sans comparaison")
-- Bas niveau : un débit sous 1/s ne doit pas s'afficher 0 (relevé en jeu : 72 en 88 s = 0.818/s).
assert(FM.FormatValue(0.818) == "0.8" and FM.FormatValue(7.26) == "7.3" and FM.FormatValue(72) == "72")
assert(FM.FormatRow(72, 0.818, 72, false) == "72 (0.8/s, 100.0%)")
assert(FM.FormatRow(72, 0.818, nil, true) == "72 (0.8/s)")

for _, m in ipairs(FM.MODES) do assert(FM.MODE_INFO[m], m) end
assert(FM.MODE_INFO.damage.type == 0 and FM.MODE_INFO.heal.type == 2 and FM.MODE_INFO.taken.type == 7)

local t = FM.SortThreat({
	{ name = "Bob", tanking = false, pct = 80 }, { name = "Tank", tanking = true, pct = 100 }, { name = "Alice", tanking = false, pct = 95 },
})
assert(t[1].name == "Tank" and t[2].name == "Alice" and t[3].name == "Bob")
assert(FM.ShouldWarn({ tanking = false, pct = 92 }, 90) and not FM.ShouldWarn({ tanking = true, pct = 100 }, 90))
assert(FM.ComputeTps({ v = 100, t = 10 }, 300, 12) == 100 and FM.ComputeTps({ v = 300, t = 10 }, 100, 12) == 0)

-- Langues : GetLocale absent hors client -> anglais ; changement sur place, clés complètes partout.
assert(NS.L.MODE_DAMAGE == "Damage" and FM.MODE_INFO.damage.label == "Damage")
assert(#FM.AvailableLocales() == 11 and FM.FindLocale("frfr") == "frFR" and FM.FindLocale("xx") == nil)
for _, code in ipairs(FM.AvailableLocales()) do
	for k in pairs(NS.Locales.enUS) do assert(NS.Locales[code][k], code .. " : " .. k .. " manquant") end
end
assert(FM.ApplyLocale("frFR") == "frFR" and NS.L.MODE_DAMAGE == "Dégâts" and FM.MODE_INFO.damage.label == "Dégâts")
assert(FM.ApplyLocale("xxXX") == "enUS" and NS.L.MODE_DAMAGE == "Damage" and FM.MODE_INFO.threat.label == "Threat")

print("selfcheck OK")
