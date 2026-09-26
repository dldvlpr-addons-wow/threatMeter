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

-- Recap de mort : derniers événements, du plus ancien au plus récent, temps relatif au dernier coup.
local recap = FM.RecapLines({
	{ spellId = 1, amount = 500, timestamp = 10, currentHP = 2000 },
	{ spellName = "Frappe", sourceName = "Ogre", amount = 1500, overkill = 200, timestamp = 12.5, currentHP = 0 },
}, function(id) return "Sort" .. id end)
assert(#recap == 2 and recap[1].left == "-2.5s  Sort1" and recap[1].right == "-500  2.0k", recap[1].left .. " | " .. recap[1].right)
assert(recap[2].left == "0.0s  Frappe (Ogre)" and recap[2].right == "-1.5k  0")
assert(#FM.RecapLines(nil) == 0 and #FM.RecapLines({}) == 0)
local many = {}
for i = 1, 10 do many[i] = { spellName = "S" .. i, amount = i, timestamp = i } end
assert(#FM.RecapLines(many) == FM.RECAP_LINES and FM.RecapLines(many)[1].left == "-5.0s  S5")

-- Fenêtres : la deuxième prend le mode opposé à la première et se pose sous la précédente.
local w1 = FM.NewWindowConfig({}, 100)
assert(w1.mode == "damage" and w1.view == "current" and w1.point[1] == "CENTER")
local list = { { mode = "damage", view = "overall", point = { "TOPLEFT", nil, "TOPLEFT", 20, -30 } } }
local w2 = FM.NewWindowConfig(list, 100)
assert(w2.mode == "heal" and w2.view == "current" and w2.point[3] == "TOPLEFT" and w2.point[4] == 20 and w2.point[5] == -136)
list[1].mode = "heal"
assert(FM.NewWindowConfig(list, 100).mode == "damage" and w2.anchor.to == 1 and w2.anchor.side == "BOTTOM")

-- Aimantation : rects { left, right, top, bottom }. Fenêtre A en 0..100 x 100..0.
local A = { 0, 100, 100, 0 }
assert(FM.SnapSide({ 3, 103, -4, -60 }, A, 15) == "BOTTOM")
assert(FM.SnapSide({ 0, 100, 150, 104 }, A, 15) == "TOP")
assert(FM.SnapSide({ 102, 200, 98, 40 }, A, 15) == "RIGHT")
assert(FM.SnapSide({ -110, -1, 100, 50 }, A, 15) == "LEFT")
assert(FM.SnapSide({ 30, 130, 300, 200 }, A, 15) == nil)

-- Chaîne d'ancrage : valide, cible absente, boucle.
local chain = { { anchor = nil }, { anchor = { to = 1 } }, { anchor = { to = 2 } } }
assert(not FM.AnchorValid(chain, 1) and FM.AnchorValid(chain, 2) and FM.AnchorValid(chain, 3))
chain[1].anchor = { to = 3 }
assert(not FM.AnchorValid(chain, 1) and not FM.AnchorValid(chain, 2) and not FM.AnchorValid(chain, 3), "boucle 1->3->2->1")
chain[1].anchor = { to = 9 }
assert(not FM.AnchorValid(chain, 1))
chain[1].anchor = { to = 1 }
assert(not FM.AnchorValid(chain, 1))

-- Retrait d'une fenêtre : ancrages vers elle décrochés, index au-dessus décalés.
local cfgs = { { n = 1 }, { n = 2, anchor = { to = 1 } }, { n = 3, anchor = { to = 2 } }, { n = 4, anchor = { to = 3 } } }
FM.RemoveWindowConfig(cfgs, 2)
assert(#cfgs == 3 and cfgs[2].n == 3 and cfgs[2].anchor == nil and cfgs[3].n == 4 and cfgs[3].anchor.to == 2)

-- Langues : GetLocale absent hors client -> anglais ; changement sur place, clés complètes partout.
assert(NS.L.MODE_DAMAGE == "Damage" and FM.MODE_INFO.damage.label == "Damage")
assert(#FM.AvailableLocales() == 11 and FM.FindLocale("frfr") == "frFR" and FM.FindLocale("xx") == nil)
for _, code in ipairs(FM.AvailableLocales()) do
	for k in pairs(NS.Locales.enUS) do assert(NS.Locales[code][k], code .. " : " .. k .. " manquant") end
end
assert(FM.ApplyLocale("frFR") == "frFR" and NS.L.MODE_DAMAGE == "Dégâts" and FM.MODE_INFO.damage.label == "Dégâts")
assert(FM.ApplyLocale("xxXX") == "enUS" and NS.L.MODE_DAMAGE == "Damage" and FM.MODE_INFO.threat.label == "Threat")

LibStub = function() return { HashTable = function() return { ["Zeta Bar"] = "x\\zeta", Flat = "Interface\\Buttons\\WHITE8X8" } end } end
local media = FM.MediaList("statusbar")
assert(#media == #FM.BAR_TEXTURES + 1 and media[#media][1] == "Zeta Bar" and FM.FindMedia(media, "zeta BAR") == "Zeta Bar")
LibStub = nil
assert(#FM.MediaList("font") == #FM.BAR_FONTS and FM.FindMedia(FM.MediaList("font"), "xx") == nil)

-- Nouvelle fenêtre : dessous si la place, sinon à droite, sinon cascade (nil)
local screen = { 1000, 800 }
assert(select(2, FM.FreeSide({ { 100, 360, 700, 500 } }, 260, 200, screen, 2)) == "BOTTOM")
local k, side = FM.FreeSide({ { 100, 360, 300, 50 } }, 260, 200, screen, 2)
assert(k == 1 and side == "RIGHT", "trop bas : à droite")
k, side = FM.FreeSide({ { 100, 360, 300, 50 }, { 362, 622, 300, 100 } }, 260, 200, screen, 2)
assert(k == 2 and side == "RIGHT", "à droite de la dernière")
assert(FM.FreeSide({ { 0, 1000, 800, 0 } }, 260, 200, screen, 2) == nil, "écran plein")
k, side = FM.FreeSide({ { 100, 360, 700, 500 }, { 362, 622, 700, 500 } }, 260, 200, screen, 2, 1)
assert(k == 1 and side == "BOTTOM", "parente d abord")

-- Comparaison : union des sorts, tri par le plus grand des deux totaux, côté absent = nil
local cmp = FM.CompareSpells({ { spellID = 1, totalAmount = 100 }, { spellID = 2, totalAmount = 50 } }, { { spellID = 2, totalAmount = 300 }, { spellID = 3, totalAmount = 10 } })
assert(#cmp == 3 and cmp[1].spellID == 2 and cmp[1].a == 50 and cmp[1].b == 300 and cmp[2].spellID == 1 and cmp[2].b == nil and cmp[3].a == nil)
assert(FM.FormatCompare(1200, 600) == "1.2k | 600 (+100%)" and FM.FormatCompare(50, 300) == "50 | 300 (-83%)" and FM.FormatCompare(nil, 10) == "- | 10" and FM.FormatCompare(5, 0) == "5 | 0")
print("selfcheck OK")
