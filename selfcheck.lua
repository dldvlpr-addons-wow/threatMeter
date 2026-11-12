-- Auto-test hors jeu de la logique pure : lua selfcheck.lua
-- CreateFrame est absent hors client, la partie UI est ignorée par le module.
local NS = {}
-- Valeur secrète simulée, captée par le module au chargement.
local SECRET = {}
issecretvalue = function(v) return v == SECRET end
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
-- Colonnes choisies : total seul, sans total, sans débit, aucune ; en combat le pourcentage (calculé) est absent.
assert(FM.FormatRow(12345, 1234, 24690, false, { total = true }) == "12.3k")
assert(FM.FormatRow(12345, 1234, 24690, false, { perSecond = true, percent = true }) == "1.2k/s, 50.0%")
assert(FM.FormatRow(12345, 1234, 24690, false, { total = true, percent = true }) == "12.3k (50.0%)")
assert(FM.FormatRow(12345, 1234, 24690, false, {}) == "")
assert(FM.FormatRow(12345, 1234, nil, true, { perSecond = true, percent = true }) == "1234.0/s")
assert(FM.FormatRow(12345, 1234, nil, true, { total = true, percent = true }) == "12345")
assert(FM.FormatRow(12345, 1234, nil, true, { percent = true }) == "")
-- En combat, total abrégé par le client (AbbreviateNumbers) ; appel refusé : repli sur le format brut.
AbbreviateNumbers = function(v) return "A" .. math.floor(v) end
assert(FM.FormatRow(12345, 1234, nil, true) == "A12345 (1234.0/s)", "débit jamais abrégé : sous 1000 le client garde toutes les décimales")
assert(FM.FormatRow(12345, 1234, nil, true, { perSecond = true }) == "1234.0/s")
assert(FM.FormatRow(12345, 1234, 24690, false) == "12.3k (1.2k/s, 50.0%)", "hors combat : format de l'addon")
AbbreviateNumbers = function() error("refusé") end
assert(FM.FormatRow(12345, 1234, nil, true) == "12345 (1234.0/s)")
AbbreviateNumbers = nil

for _, m in ipairs(FM.MODES) do assert(FM.MODE_INFO[m], m) end
assert(FM.MODE_INFO.damage.type == 0 and FM.MODE_INFO.heal.type == 2 and FM.MODE_INFO.taken.type == 7)

local t = FM.SortThreat({
	{ name = "Bob", tanking = false, pct = 80 }, { name = "Tank", tanking = true, pct = 100 }, { name = "Alice", tanking = false, pct = 95 },
})
assert(t[1].name == "Tank" and t[2].name == "Alice" and t[3].name == "Bob")
assert(FM.ShouldWarn({ tanking = false, pct = 92 }, 90) and not FM.ShouldWarn({ tanking = true, pct = 100 }, 90))
-- Statut seul (boss) : alerte au statut 1 seulement, seuil ignoré.
assert(FM.ShouldWarn({ tanking = false, status = 1, pct = FM.STATUS_PCT[1] }, 90))
assert(not FM.ShouldWarn({ tanking = false, status = 0, pct = FM.STATUS_PCT[0] }, 10))
assert(not FM.ShouldWarn({ tanking = true, status = 2, pct = FM.STATUS_PCT[2] }, 10))
do -- débit de menace : stable entre deux mises à jour serveur, fenêtre glissante, base remise sur une baisse
	local s = { t = {}, v = {} }
	assert(FM.ThreatRate(s, 1000, 0) == 0)
	assert(FM.ThreatRate(s, 1000, 0.6) == 0)           -- pas encore de nouvelle valeur
	assert(FM.ThreatRate(s, 1100, 1) == 0)             -- 1re hausse : sert de base (1er relevé pris entre deux mises à jour)
	assert(FM.ThreatRate(s, 1200, 2) == 100)
	assert(FM.ThreatRate(s, 1200, 2.8) == 100)         -- rafraîchi sans nouvelle valeur : pas de chute
	assert(FM.ThreatRate(s, 1200, 2.8) == 100)         -- 2e fenêtre au même instant
	assert(FM.ThreatRate(s, 1200, 6) == 100 / 1.5)     -- plus rien depuis THREAT_STALE : le débit décroît
	assert(FM.ThreatRate(s, 1200, 13) == 0)            -- plus rien depuis THREAT_WINDOW : inactif
	for sec = 14, 29 do FM.ThreatRate(s, 1200 + (sec - 13) * 50, sec) end -- reprise : nouvelle base, pas de D/pause
	assert(FM.ThreatRate(s, 2050, 30) == 50 and #s.t <= 12) -- anciens relevés retirés
	assert(FM.ThreatRate(s, 500, 31) == 0 and #s.t == 1) -- menace réduite : nouvelle base
end

-- Recap de mort : derniers événements, du plus ancien au plus récent, temps relatif au dernier coup.
local recap = FM.RecapLines({
	{ spellId = 1, amount = 500, timestamp = 10, currentHP = 2000 },
	{ spellName = "Frappe", sourceName = "Ogre", amount = 1500, overkill = 200, timestamp = 12.5, currentHP = 0 },
}, function(id) return "Sort" .. id end)
assert(#recap == 2 and recap[1].left == "-2.5s  Sort1" and recap[1].right == "-500  2.0k", recap[1].left .. " | " .. recap[1].right)
assert(recap[2].left == "0.0s  Frappe (Ogre)" and recap[2].right == "-1.5k  0")
assert(#FM.RecapLines(nil) == 0 and #FM.RecapLines({}) == 0)
-- Nom de créature secret : pas de comparaison (elle lèverait en jeu), le nom est concaténé.
local secretConcat = getmetatable(SECRET)
setmetatable(SECRET, { __concat = function() return "secret" end })
assert(FM.RecapLines({ { spellName = "Frappe", sourceName = SECRET, amount = 1, timestamp = 1 } })[1].left:find("secret", 1, true))
assert(FM.RecapLines({ { spellName = "Frappe", sourceName = SECRET, amount = 1, timestamp = 1 } }, nil, nil, true)[1].left == "0.0s  Frappe")
setmetatable(SECRET, secretConcat)
local many = {}
for i = 1, 10 do many[i] = { spellName = "S" .. i, amount = i, timestamp = i } end
assert(#FM.RecapLines(many) == FM.RECAP_LINES and FM.RecapLines(many)[1].left == "-5.0s  S5")
local newestFirst = {}
for i = 10, 1, -1 do newestFirst[#newestFirst + 1] = many[i] end
local fromNewest = FM.RecapLines(newestFirst)
assert(fromNewest[1].left == "-5.0s  S5" and fromNewest[#fromNewest].left == "0.0s  S10")

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
assert(FM.CompareSpells({ { spellID = 1, totalAmount = 1, isAvoidable = true, isDeadly = false } }, {})[1].isAvoidable == true, "drapeaux du sort recopiés")

-- Bornes partagées : entier quand le pas est entier
assert(FM.Clamp("rows", 7.9) == 7 and FM.Clamp("rows", 99) == 40 and FM.Clamp("scale", 1.23) == 1.23 and FM.Clamp("windows", 0) == 1 and FM.Clamp("width", 1000) == 600)

-- Filtre des ennemis : ordre gardé, classification secrète gardée faute de pouvoir la comparer
local enemies = { { name = "a", classification = "normal" }, { name = "b", classification = "worldboss" }, { name = "c", classification = "elite" }, { name = "d", classification = SECRET }, { name = "e", classification = "rareelite" } }
local function Names(list) local t = {} for i, s in ipairs(list) do t[i] = s.name end return table.concat(t) end
assert(FM.FilterSources(enemies, nil) == enemies and Names(FM.FilterSources(enemies, "boss")) == "bd" and Names(FM.FilterSources(enemies, "elite")) == "bcde")

-- Import de réglages : copie propre si tout est valide, sinon nil et la clé fautive
local good = { scale = 1.2, warnSound = false, locale = "enUS", columns = { total = false }, point = { "CENTER", nil, "CENTER", 10, -20 },
	windows = { { mode = "damage", view = "current", barColor = { r = 0.1, g = 0.2, b = 0.3 }, filter = "boss" }, { mode = "threat", view = 12, rows = 5, anchor = { to = 1, side = "BOTTOM" } } } }
local clean = assert(FM.ValidateSettings(good))
assert(clean ~= good and clean.windows[2].anchor.to == 1 and clean.windows[1].barColor.b == 0.3 and clean.point[4] == 10 and clean.columns.total == false)
local function Bad(t, key)
	local out, bad = FM.ValidateSettings(t)
	assert(out == nil and bad == key, tostring(bad) .. " au lieu de " .. key)
end
Bad({ windows = { { mode = "damage" } }, bogus = 1 }, "bogus")
Bad({ windows = { { mode = "damage" } }, scale = "1" }, "scale")
Bad({ windows = { { mode = "damage" } }, warnPct = 999 }, "warnPct")
Bad({ windows = { { mode = "damage" } }, refresh = 0 / 0 }, "refresh")
Bad({ windows = { { mode = "damage" } }, locale = "xxXX" }, "locale")
Bad({ windows = { { mode = "damage" } }, point = { "CENTER", "UIParent", "CENTER", 0, 0 } }, "point")
Bad({ windows = {} }, "windows")
Bad({ windows = { { mode = "damage" }, { mode = "damage" }, { mode = "damage" }, { mode = "damage" }, { mode = "damage" } } }, "windows")
Bad({ windows = { [1] = { mode = "damage" }, [3] = { mode = "damage" } } }, "windows")
Bad({ windows = { [1] = { mode = "damage" }, [3] = { mode = "damage" }, [4] = { mode = "damage" }, x = true } }, "windows")
Bad({ windows = { [1] = { mode = "damage" }, [2] = { mode = "damage" }, [4] = { mode = "damage" }, ["2.5"] = { mode = "damage" } } }, "windows")
Bad({ windows = { { mode = "damage" } }, rows = 2.5 }, "rows")
Bad({ windows = { { mode = "damage", rows = 2.5 } } }, "windows.1.rows")
Bad({ windows = { { mode = "bogus" } } }, "windows.1.mode")
Bad({ windows = { { view = "current" } } }, "windows.1")
Bad({ windows = { { mode = "damage", anchor = { to = 1, side = "BOTTOM" } } } }, "windows.1.anchor")
Bad({ windows = { { mode = "damage" }, { mode = "damage", anchor = { to = 1, side = "BOTTOM", x = 1 } } } }, "windows.2.anchor")
Bad({ windows = { { mode = "damage", barColor = { r = 2, g = 0, b = 0 } } } }, "windows.1.barColor")
Bad({ windows = { { mode = "damage", filter = "rare" } } }, "windows.1.filter")
Bad("MIR1", "?")

-- Arguments de /fm report : nombre et canal optionnels, chuchotement avec nom obligatoire
local function Parsed(arg) local a, b, c = FM.ParseReport(arg); return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) end
assert(Parsed("") == "nil,nil,nil" and Parsed("8") == "8,nil,nil" and Parsed("GUILD") == "nil,GUILD,nil" and Parsed("3 instance") == "3,INSTANCE_CHAT,nil")
assert(Parsed("3 whisper Bob") == "3,WHISPER,Bob" and Parsed("whisper") == "false,nil,nil" and Parsed("say Bob") == "false,nil,nil" and Parsed("3 yell") == "false,nil,nil")
assert(Parsed("5guild") == "false,nil,nil" and Parsed("0") == "false,nil,nil" and Parsed("0 guild") == "false,nil,nil", "N collé au canal ou nul")

-- Miroir : aller-retour, rejet des chaînes illisibles, élagage des défauts (Prune, via Write)
local MNS = {}
assert(loadfile("Mirror.lua"))("ForeverMeter", MNS)
local Mirror = MNS.Mirror
local src = { a = { 1, 2.5, "x" }, s = 'p;q=r.s#t|u%v"w\\y\nz', b = false, t = true, e = {}, [3] = { k = -0.125 } }
local back = assert(Mirror.Deserialize(Mirror.Serialize(src)))
assert(back.a[1] == 1 and back.a[2] == 2.5 and back.a[3] == "x" and back.s == src.s and back.b == false and back.t == true)
assert(type(back.e) == "table" and next(back.e) == nil and back[3].k == -0.125 and back["3"] == nil, "clé numérique gardée numérique")
assert(Mirror.Serialize(back) == Mirror.Serialize(src), "sérialisation stable")
assert(Mirror.Deserialize("XX:a=b1") == nil and Mirror.Deserialize("MIR1:a") == nil and Mirror.Deserialize("MIR1:a=nzz") == nil)
assert(Mirror.Deserialize("MIR1:#=b1") == nil and Mirror.Deserialize(nil) == nil and next(Mirror.Deserialize("MIR1:")) == nil)
local cv = {}
C_CVar = { RegisterCVar = function() end, GetCVar = function(k) return cv[k] end, SetCVar = function(k, v) cv[k] = v end }
Mirror.IGNORE.log = true
assert(Mirror:Write({ x = 1, y = 2, flag = false, sub = { k = 1, j = 3 }, same = { k = 1 }, log = { 1 } }, { x = 1, flag = false, sub = { k = 1 }, same = { k = 1 } }))
local pruned = assert(Mirror:Read())
assert(pruned.x == nil and pruned.y == 2 and pruned.flag == nil and pruned.sub.k == nil and pruned.sub.j == 3, "défauts élagués, false compris")
assert(pruned.same == nil and pruned.log == nil, "table vide après élagage et clé ignorée absentes")
assert(not Mirror:Write({ y = 2, sub = { j = 3 } }, {}), "texte inchangé : pas de réécriture")
assert(not Mirror:Write({ big = string.rep("a", Mirror.SLOTS * Mirror.CHUNK) }, {}) and Mirror:Read().y == 2, "trop grand : miroir précédent gardé")
C_CVar = nil
print("selfcheck OK")
