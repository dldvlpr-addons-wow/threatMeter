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
assert(loadfile("CombatBreakdown.lua"))("ForeverMeter", NS)
assert(loadfile("CombatSync.lua"))("ForeverMeter", NS)
local FM = ForeverMeter

-- Partage des lancers (CombatSync.lua)
assert(#FM.SplitChunks("abcde", 2) == 3 and FM.SplitChunks("abcde", 2)[3] == "e" and #FM.SplitChunks("", 2) == 0, "découpage")
local payload = FM.BuildSyncPayload("G", { { t = 0, spellID = 7 }, { t = 1.234, spellID = 8 } }, 5000.5)
assert(payload.b == 5000 and payload.c[1] == 50 and payload.c[3] == 173 and payload.c[4] == 8, "données envoyées")
local guid, casts = FM.ReadSyncPayload(payload)
assert(guid == "G" and casts[2].time == 5001.73 and casts[2].spellID == 8, "données relues")
assert(not FM.ReadSyncPayload({ g = "G", b = 1, c = { 1 } }) and not FM.ReadSyncPayload({ g = "G", b = 1, c = { "x", 2 } }) and not FM.ReadSyncPayload("x"), "données invalides refusées")
for _, list in ipairs({ { 1, 0 / 0 }, { 1, 2.5 }, { 1, -3 }, { 0 / 0, 2 }, { -1, 2 }, { 1.5, 2 } }) do
	assert(not FM.ReadSyncPayload({ g = "G", b = 1, c = list }), "nombre hors forme refusé")
end
assert(not FM.ReadSyncPayload({ g = "G", b = 0 / 0, c = {} }) and not FM.ReadSyncPayload({ g = "G", b = 1.5, c = {} }), "base hors forme refusée")
local between = FM.CastsBetween(casts, 5000.6, 5002)
assert(#between == 1 and math.abs(between[1].t - 1.13) < 1e-9 and #FM.CastsBetween(nil, 0, 1) == 0, "lancers d'un combat")

-- Tableau détaillé et chronologie (CombatBreakdown.lua)
assert(#FM.SpellTargets({}) == 0 and FM.SpellTargets({ combatSpellDetails = { unitName = "A", amount = 5 } })[1].unitName == "A", "structure unique rendue en liste")
local spellsWithTargets = {
	{ spellID = 1, combatSpellDetails = { { unitName = "A", amount = 10 }, { unitName = "B", amount = 30 } } },
	{ spellID = 2, combatSpellDetails = { unitName = "A", unitClassFilename = "MAGE", amount = 25 } },
}
assert(#FM.SpellTargets({ combatSpellDetails = { unitName = "", amount = 0 } }) == 0, "structure vide du client écartée")
local targets = FM.TargetTotals(spellsWithTargets)
assert(targets[1].name == "A" and targets[1].amount == 35 and targets[1].spells[1].spell.spellID == 2 and targets[2].amount == 30, "cibles cumulées et triées")
local sortedRows = FM.SortRows({ { values = { v = 2 } }, { values = {} }, { values = { v = 5 } } }, "v")
assert(sortedRows[1].values.v == 5 and sortedRows[2].values.v == 2 and sortedRows[3].values.v == nil, "tri décroissant, valeur absente en dernier")
assert(FM.SortRows(sortedRows, "v", true)[1].values.v == 2, "tri croissant")
local tied = FM.SortRows({ { id = 1, values = { v = 1 } }, { id = 2, values = {} }, { id = 3, values = { v = 1 } }, { id = 4, values = {} }, { id = 5, values = { v = 1 } } }, "v")
assert(tied[1].id == 1 and tied[2].id == 3 and tied[3].id == 5 and tied[4].id == 2 and tied[5].id == 4, "tri stable à égalité")
local deathRows = FM.DeathRows({ { timestamp = 42, amount = 1 }, { timestamp = 40, amount = 2 } })
assert(deathRows[1].event.amount == 2 and deathRows[1].time == -2 and deathRows[2].time == 0, "récap remis dans l'ordre, temps avant la mort")
assert(FM.NiceStep(10, 50) == 5 and FM.NiceStep(1, 50) == 60 and FM.NiceStep(0.01, 50) == 600, "pas de l'axe")
local tracks = FM.CastTracks({ { t = 1, spellID = 9 }, { t = 2, spellID = 8 }, { t = 3, spellID = 8 } })
assert(tracks[1].spellID == 8 and #tracks[1].times == 2 and tracks[2].spellID == 9, "sort le plus lancé d'abord")
-- Incantations interrompues ou ratées : sur la piste, hors du compte ; canalisation coupée comptée.
tracks = FM.CastTracks({ { t = 1, spellID = 9, result = "interrupted" }, { t = 2, spellID = 9, result = "failed" }, { t = 3, spellID = 8, result = "cut" } })
assert(tracks[1].spellID == 8 and tracks[1].landed == 1 and tracks[2].landed == 0 and #tracks[2].times == 2, "lancers partis comptés")
payload = FM.BuildSyncPayload("G", { { t = 0, spellID = 7, result = "interrupted" }, { t = 1, spellID = 8 } }, 5000)
assert(#payload.c == 2 and payload.c[2] == 8, "partage : lancers partis seulement")
local long = {}
for i = 1, 1001 do long[i] = { t = i, spellID = 7 } end
local landed
payload, landed = FM.BuildSyncPayload("G", long, 5000)
assert(#payload.c == 2000 and landed == 1001, "partage tronqué : nombre de lancers partis rendu")
-- Sauvegarde au /reload : combat fermé lié à une session ; reprise si la session existe encore sous le même nom.
local sessions = { { sessionID = 3, name = "Ogre" }, { sessionID = SECRET, name = "X" } }
local saved = FM.SavableSegments({ { stop = 10, sessionID = 3, casts = {}, encounters = {} }, { sessionID = 3 }, { stop = 5, sessionID = 4 } }, sessions)
assert(#saved == 1 and saved[1].sessionName == "Ogre", "combats sauvegardés")
assert(#FM.RestorableSegments(saved, sessions, 20) == 1, "combat repris")
assert(#FM.RestorableSegments(saved, { { sessionID = 3, name = "Loup" } }, 20) == 0, "session remplacée : écarté")
assert(#FM.RestorableSegments(saved, sessions, 5) == 0, "horloge repartie de zéro : écarté")
assert(#FM.RestorableSegments({ "x", { stop = 1 } }, sessions, 20) == 0 and #FM.RestorableSegments(nil, sessions, 20) == 0, "données abîmées écartées")
assert(FM.NearestTime({ 1, 5, 9 }, 5.4, 1) == 2 and FM.NearestTime({ 1, 5 }, 3, 1) == nil, "instant le plus proche")
assert(FM.MatchesFilter("Fireball", "") and FM.MatchesFilter("Fireball", "BALL") and not FM.MatchesFilter("Fireball", "frost"), "filtre sans casse")
assert(not FM.MatchesFilter(SECRET, "a") and FM.MatchesFilter(SECRET, nil) and not FM.MatchesFilter(nil, "a"), "filtre : nom secret ou absent écarté")
assert(FM.MatchesFilter("a.b", "."), "filtre littéral, pas un motif")

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
-- Habillage : couleurs, épaisseur et espacement bornés, cases booléennes
assert(FM.ValidateSettings({ windows = { { mode = "damage" } }, bgColor = { r = 0, g = 0.5, b = 1 }, borderSize = 0, barSpacing = 6, textOutline = true, showIcons = false }))
Bad({ windows = { { mode = "damage" } }, headerColor = { r = 0, g = 0 } }, "headerColor")
Bad({ windows = { { mode = "damage" } }, borderSize = 4 }, "borderSize")
Bad({ windows = { { mode = "damage" } }, showIcons = 1 }, "showIcons")
assert(FM.ValidateSettings({ windows = { { mode = "damage" } }, headerSpacing = 20, shortNames = true }))
Bad({ windows = { { mode = "damage" } }, headerSpacing = 21 }, "headerSpacing")
Bad({ windows = { { mode = "damage" } }, shortNames = 1 }, "shortNames")
-- Prénom seul : coupé à l'espace ou au tiret, nom simple et nom secret rendus tels quels
assert(FM.ShortName("Thrall-Forever") == "Thrall" and FM.ShortName("Jaina Proudmoore") == "Jaina" and FM.ShortName("Thrall") == "Thrall")
assert(FM.ShortName(SECRET) == SECRET, "nom secret jamais découpé")
-- Thème reconnu : clé absente du thème = défaut, couleurs comparées champ par champ avec tolérance
do
	local s = {}
	for _, k in ipairs(FM.THEME_KEYS) do s[k] = FM.ThemeValue(FM.THEMES[1], k) end
	assert(FM.CurrentTheme(s) == "classic", "classic avec les défauts")
	local bold = FM.THEMES[7]
	for _, k in ipairs(FM.THEME_KEYS) do s[k] = FM.ThemeValue(bold, k) end
	s.bgColor = { r = bold.bgColor.r + 1e-9, g = bold.bgColor.g, b = bold.bgColor.b }
	assert(FM.CurrentTheme(s) == "bold", "couleur à 1e-9 près : même thème")
	s.bgColor = { r = 0.5, g = 0, b = 0 }
	assert(FM.CurrentTheme(s) == nil, "couleur changée : personnalisé")
end
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
