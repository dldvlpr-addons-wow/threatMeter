-- ForeverMeter : compteur de dégâts, soins, dégâts subis et menace pour WoW Forever (client 1.60, moteur 12.x).
-- Un seul fichier, aucune dépendance.
--
-- Sur ce moteur, COMBAT_LOG_EVENT_UNFILTERED est interdit aux addons : les données viennent de C_DamageMeter,
-- le compteur serveur de Blizzard. En combat, noms, montants et GUID sont des « valeurs secrètes » : on peut les
-- afficher (SetText, SetValue, string.format) mais ni les comparer, ni les additionner, ni les renvoyer à l'API.
-- L'addon affiche donc les barres dans l'ordre fourni par l'API, et complète (%, détail par sort) hors combat.
--
-- Structure :
--   1. Logique pure (format, tri de la menace, lignes du recap de mort) : testable hors jeu.
--   2. Partie WoW : lecture C_DamageMeter, menace, fenêtres (jusqu'à 4, chacune son mode et sa session), commandes.

local ADDON, NS = ...
NS = NS or {}
local LOCALES = NS.Locales or {}
-- Table unique, remplie sur place par FM.ApplyLocale : les références `L` restent valides après un changement.
local L = {}
NS.L = L
local FM = {}
_G.ForeverMeter = FM
local issecretvalue = issecretvalue or function() return false end

-- Modes : clé -> { label, type Enum.DamageMeterType }. La menace n'est pas dans C_DamageMeter.
-- Menace en tête : premier choix du menu Affichage.
FM.MODES = { "threat", "damage", "heal", "absorbs", "taken", "interrupts", "dispels", "deaths" }
FM.MODE_INFO = {
	damage     = { label = L.MODE_DAMAGE,     type = 0 },
	heal       = { label = L.MODE_HEAL,       type = 2 },
	absorbs    = { label = L.MODE_ABSORBS,    type = 4 },
	taken      = { label = L.MODE_TAKEN,      type = 7 },
	interrupts = { label = L.MODE_INTERRUPTS, type = 5 },
	dispels    = { label = L.MODE_DISPELS,    type = 6 },
	deaths     = { label = L.MODE_DEATHS,     type = 9 },
	threat     = { label = L.MODE_THREAT },
}
-- Modes lus dans l'énumération du client, placés après « taken » : absents si ce client ne les connaît pas.
local METER_TYPES = Enum and Enum.DamageMeterType or {}
for i, extra in ipairs({ { "enemytaken", "EnemyDamageTaken" }, { "avoidable", "AvoidableDamageTaken" } }) do
	if METER_TYPES[extra[2]] then
		FM.MODE_INFO[extra[1]] = { type = METER_TYPES[extra[2]] }
		table.insert(FM.MODES, 5 + i, extra[1])
	end
end
FM.SESSION_OVERALL, FM.SESSION_CURRENT = 0, 1
FM.MAX_WINDOWS = 4
FM.RECAP_LINES = 6

local LABEL_KEYS = {
	damage = "MODE_DAMAGE", heal = "MODE_HEAL", absorbs = "MODE_ABSORBS", taken = "MODE_TAKEN",
	interrupts = "MODE_INTERRUPTS", dispels = "MODE_DISPELS", deaths = "MODE_DEATHS", threat = "MODE_THREAT",
	enemytaken = "MODE_ENEMY_TAKEN", avoidable = "MODE_AVOIDABLE",
}

-- Langues chargées, triées : enUS, frFR, deDE...
function FM.AvailableLocales()
	local list = {}
	for code in pairs(LOCALES) do list[#list + 1] = code end
	table.sort(list)
	return list
end

-- Code de langue saisi (casse libre) -> code chargé, ou nil.
function FM.FindLocale(input)
	input = (input or ""):lower()
	for code in pairs(LOCALES) do
		if code:lower() == input then return code end
	end
	return nil
end

-- Remplit L : anglais, puis la langue demandée par-dessus (clés manquantes = anglais).
-- Renvoie le code réellement appliqué.
function FM.ApplyLocale(code)
	if not LOCALES[code] then code = "enUS" end
	for k in pairs(L) do L[k] = nil end
	for k, v in pairs(LOCALES.enUS or {}) do L[k] = v end
	for k, v in pairs(LOCALES[code] or {}) do L[k] = v end
	for mode, key in pairs(LABEL_KEYS) do
		if FM.MODE_INFO[mode] then FM.MODE_INFO[mode].label = L[key] end
	end
	return code
end

FM.ApplyLocale(GetLocale and GetLocale() or "enUS")

local DEFAULTS = {
	scale = 1,
	rows = 10,
	width = 260,
	rowHeight = 16,
	bgAlpha = 0.6,                        -- opacité du fond des fenêtres (0 = transparent)
	warnPct = 90,
	refresh = 0.2,                        -- secondes entre deux rafraîchissements au plus, après un changement de données
	warnSound = true,
	showPets = true,
	autoHide = false,                     -- fenêtres visibles seulement en combat ou en groupe
	instanceOnly = false,                 -- fenêtres masquées hors instance
	autoReset = false,                    -- remise à zéro à l'entrée dans une instance ou en rejoignant un groupe
	columns = { total = true, perSecond = true, percent = true }, -- texte de droite des barres
	locale = nil,                        -- nil = langue du client (GetLocale)
	barTexture = "blizzard",              -- nom dans FM.BAR_TEXTURES
	barFont = nil,                        -- nom dans FM.BAR_FONTS, nil = police du client (gère cyrillique et CJK)
	fontSize = nil,                       -- nil = taille de GameFontHighlightSmall
	point = { "CENTER", nil, "CENTER", 300, 0 }, -- position de la première fenêtre
}

-- Médias du client et de l'addon (Media/, textures faites pour ForeverMeter). Tableaux ordonnés pour la liste.
-- Les médias de LibSharedMedia s'ajoutent derrière quand un autre addon l'embarque (FM.MediaList).
local MEDIA = "Interface\\AddOns\\ForeverMeter\\Media\\"
FM.BAR_TEXTURES = {
	{ "blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
	{ "flat", "Interface\\Buttons\\WHITE8X8" },
	{ "gradient", MEDIA .. "Gradient" },
	{ "glass", MEDIA .. "Glass" },
	{ "striped", MEDIA .. "Striped" },
	{ "fade", MEDIA .. "Fade" },
}
-- Polices livrées avec l'addon (Media/Fonts, licence SIL OFL, voir OFL.txt), puis celles du client
-- (chemins de LibSharedMedia). Les polices du client n'ont pas l'alphabet coréen ni chinois : « default » pour ces langues.
local FONTS = MEDIA .. "Fonts\\"
FM.BAR_FONTS = {
	{ "oswald", FONTS .. "Oswald-Regular.ttf" },
	{ "pt-sans-narrow", FONTS .. "PTSansNarrow-Regular.ttf" },
	{ "pt-sans-narrow-bold", FONTS .. "PTSansNarrow-Bold.ttf" },
	{ "fira-sans", FONTS .. "FiraSans-Medium.ttf" },
	{ "fira-sans-condensed", FONTS .. "FiraSansCondensed-Medium.ttf" },
	{ "fira-mono", FONTS .. "FiraMono-Medium.ttf" },
	{ "friz", "Fonts\\FRIZQT__.TTF" },
	{ "arial", "Fonts\\ARIALN.TTF" },
	{ "morpheus", "Fonts\\MORPHEUS.TTF" },
	{ "skurri", "Fonts\\SKURRI.TTF" },
	{ "nimrod", "Fonts\\NIM_____.ttf" },
	{ "pagetext", "Fonts\\K_Pagetext.TTF" },
	{ "damage", "Fonts\\K_Damage.TTF" },
	{ "2002", "Fonts\\2002.TTF" },
	{ "2002bold", "Fonts\\2002B.TTF" },
	{ "friz-cyr", "Fonts\\FRIZQT___CYR.TTF" },
	{ "morpheus-cyr", "Fonts\\MORPHEUS_CYR.TTF" },
	{ "skurri-cyr", "Fonts\\SKURRI_CYR.TTF" },
}

-- Thèmes du panneau et de /fm theme : réglages d'apparence posés d'un coup. barFont ou fontSize absent = défaut du client.
FM.THEMES = {
	{ name = "classic", barTexture = "blizzard", rowHeight = 16, bgAlpha = 0.6 },
	{ name = "flat", barTexture = "flat", barFont = "fira-sans-condensed", fontSize = 11, rowHeight = 18, bgAlpha = 0.8 },
	{ name = "glass", barTexture = "glass", barFont = "pt-sans-narrow-bold", fontSize = 12, rowHeight = 20, bgAlpha = 0.4 },
	{ name = "compact", barTexture = "gradient", fontSize = 9, rowHeight = 12, bgAlpha = 0.5 },
}
FM.THEME_KEYS = { "barTexture", "barFont", "fontSize", "rowHeight", "bgAlpha" }
-- Les polices livrées n'ont pas l'alphabet coréen ni chinois : sur ces clients, un thème garde la police choisie.
FM.CJK_LOCALES = { koKR = true, zhCN = true, zhTW = true }

------------------------------------------------------------------------
-- 1. Logique pure
------------------------------------------------------------------------

-- Liste intégrée + médias LibSharedMedia (chemins déjà présents exclus), relue à chaque appel :
-- les addons qui enregistrent des médias peuvent se charger après ForeverMeter.
-- kind : "statusbar" ou "font".
function FM.MediaList(kind)
	local list = {}
	for i, m in ipairs(kind == "font" and FM.BAR_FONTS or FM.BAR_TEXTURES) do list[i] = m end
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not LSM then return list end
	local known, extra = {}, {}
	for _, m in ipairs(list) do known[m[2]:lower()] = true end
	for name, path in pairs(LSM:HashTable(kind)) do
		if type(path) == "string" and not known[path:lower()] then extra[#extra + 1] = { name, path } end
	end
	table.sort(extra, function(a, b) return a[1] < b[1] end)
	for _, m in ipairs(extra) do list[#list + 1] = m end
	return list
end

-- Nom saisi (casse libre) -> thème, ou nil.
function FM.FindTheme(input)
	input = (input or ""):lower()
	for _, t in ipairs(FM.THEMES) do
		if t.name == input then return t end
	end
end

-- Nom du thème dont tous les réglages valent ceux de `settings`, sinon nil. keepFont : police ignorée (client CJK).
-- Tolérance sur les nombres : le curseur d'opacité arrondit par multiples de 0.05 (12 * 0.05 ~= 0.6).
function FM.CurrentTheme(settings, keepFont)
	for _, t in ipairs(FM.THEMES) do
		local same = true
		for _, k in ipairs(FM.THEME_KEYS) do
			local a, b = settings[k], t[k]
			if not (keepFont and k == "barFont") and a ~= b
				and not (type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6) then same = false end
		end
		if same then return t.name end
	end
end

-- Nom saisi (casse libre) -> nom et chemin du média, ou nil.
function FM.FindMedia(list, input)
	input = (input or ""):lower()
	for _, m in ipairs(list) do
		if m[1]:lower() == input then return m[1], m[2] end
	end
	return nil
end

function FM.MediaNames(list)
	local names = {}
	for i, m in ipairs(list) do names[i] = m[1] end
	return table.concat(names, ", ")
end

function FM.FormatValue(v)
	v = v or 0
	if v >= 1000000 then return string.format("%.2fM", v / 1000000) end
	if v >= 1000 then return string.format("%.1fk", v / 1000) end
	-- Une décimale sous 10 : à bas niveau, un débit de 0.8/s ne doit pas s'afficher 0.
	if v < 10 and v ~= math.floor(v) then return string.format("%.1f", v) end
	return tostring(math.floor(v))
end

function FM.FormatTime(sec)
	sec = math.floor(sec or 0)
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Ligne de droite d'une barre, selon les colonnes choisies (`columns` : total, perSecond, percent ; toutes par défaut).
-- `secret` vrai en combat : pas de comparaison ni d'arithmétique possible, string.format reste permis et le
-- résultat s'affiche tel quel ; le pourcentage, calculé, n'existe pas.
-- Total secret abrégé (12K) par AbbreviateNumbers du client, qui accepte un secret sans arithmétique côté addon.
-- Sous 1000 il rend la valeur brute avec toutes ses décimales (vu en jeu : 0.818 -> "0.818") : réservé au total,
-- entier. Client sans la fonction ou appel refusé : nombre brut au format `fmt`.
local function SecretNumber(v, fmt)
	if AbbreviateNumbers then
		local ok, text = pcall(AbbreviateNumbers, v)
		if ok then return text end
	end
	return string.format(fmt, v)
end

function FM.FormatRow(total, perSecond, sessionTotal, secret, columns)
	columns = columns or DEFAULTS.columns
	if secret then
		-- Pas de test possible sur une valeur secrète : débit à une décimale toujours (0.8/s ne doit pas s'afficher 1).
		-- Total abrégé, repli %.0f (%d lève sur un secret, %.0f l'accepte). string.format accepte un texte secret.
		if columns.total and columns.perSecond then return string.format("%s (%.1f/s)", SecretNumber(total, "%.0f"), perSecond) end
		if columns.total then return SecretNumber(total, "%.0f") end
		if columns.perSecond then return string.format("%.1f/s", perSecond) end
		return ""
	end
	local parts = {}
	if columns.perSecond then parts[#parts + 1] = FM.FormatValue(perSecond) .. "/s" end
	if columns.percent then
		local pct = sessionTotal and sessionTotal > 0 and (total / sessionTotal * 100) or 0
		parts[#parts + 1] = string.format("%.1f%%", pct)
	end
	local rest = table.concat(parts, ", ")
	if not columns.total then return rest end
	if rest == "" then return FM.FormatValue(total) end
	return FM.FormatValue(total) .. " (" .. rest .. ")"
end

-- Comparaison de deux sources : union des sorts, { spellID, a, b, creatureName } triés par le plus grand
-- des deux totaux. a ou b vaut nil quand le sort manque d'un côté. Valeurs lisibles uniquement (hors combat).
function FM.CompareSpells(spellsA, spellsB)
	local rows, byID = {}, {}
	for side, spells in pairs({ a = spellsA, b = spellsB }) do
		for _, s in ipairs(spells) do
			local row = byID[s.spellID]
			if not row then
				row = { spellID = s.spellID, creatureName = s.creatureName, isAvoidable = s.isAvoidable, isDeadly = s.isDeadly }
				byID[s.spellID] = row
				rows[#rows + 1] = row
			end
			row[side] = (row[side] or 0) + s.totalAmount
		end
	end
	table.sort(rows, function(x, y)
		local mx, my = math.max(x.a or 0, x.b or 0), math.max(y.a or 0, y.b or 0)
		if mx ~= my then return mx > my end
		return x.spellID < y.spellID
	end)
	return rows
end

-- "12.3k | 9.8k (+26%)" ; "-" pour un côté absent, écart seulement quand les deux existent.
function FM.FormatCompare(a, b)
	local text = (a and FM.FormatValue(a) or "-") .. " | " .. (b and FM.FormatValue(b) or "-")
	if a and b and b > 0 then text = text .. string.format(" (%+d%%)", math.floor((a - b) / b * 100 + 0.5)) end
	return text
end

function FM.SortThreat(list)
	table.sort(list, function(a, b)
		if a.tanking ~= b.tanking then return a.tanking end
		if a.pct ~= b.pct then return a.pct > b.pct end
		local sa, sb = issecretvalue(a.name), issecretvalue(b.name)
		if sa or sb then return sb and not sa end -- noms secrets en dernier, égaux entre eux
		return a.name < b.name
	end)
	return list
end

-- Ligne en statut seul (row.status, valeurs secrètes contre un boss) : alerte au statut 1, menace au-dessus du tank.
function FM.ShouldWarn(row, warnPct)
	if row == nil or row.tanking then return false end
	if row.status then return row.status == 1 end
	return (row.pct or 0) >= warnPct
end

-- Statut UnitThreatSituation -> remplissage de barre, faute de pourcentage lisible.
FM.STATUS_PCT = { [0] = 25, 50, 75, 100 }

-- Débit de menace glissant. La menace serveur ne change qu'environ une fois par seconde, bien moins souvent que
-- le rafraîchissement : `samples` ({ t = {}, v = {} }) ne garde que les instants où la valeur a changé, et le débit
-- se mesure entre ces instants, sur THREAT_WINDOW secondes. Rappelé au même `now` (2e fenêtre) : même résultat.
FM.THREAT_WINDOW = 10
FM.THREAT_STALE = 3.5 -- sans nouvelle valeur depuis ce délai, le débit décroît (couvre une cadence de 3 s : tir auto, DoT)
function FM.ThreatRebase(samples, value, now, unaligned)
	local t, v = samples.t, samples.v
	for i = #t, 1, -1 do t[i], v[i] = nil, nil end
	t[1], v[1] = now, value
	samples.unaligned = unaligned
	return 0
end
function FM.ThreatRate(samples, value, now)
	local t, v = samples.t, samples.v
	local n = #t
	-- Premier relevé : pris entre deux mises à jour serveur, ce n'est pas un instant de changement (sinon faux pic).
	if n == 0 then return FM.ThreatRebase(samples, value, now, true) end
	-- Menace réduite (Disparition, effacement) ou reprise après une pause plus longue que la fenêtre : nouvelle base.
	if value < v[n] or (value > v[n] and (samples.unaligned or now - t[n] > FM.THREAT_WINDOW)) then
		return FM.ThreatRebase(samples, value, now, false)
	end
	if value > v[n] then n = n + 1; t[n], v[n] = now, value end
	if now - t[n] > FM.THREAT_WINDOW then return 0 end -- plus rien depuis la durée de la fenêtre : inactif
	-- Base : le dernier relevé à au moins THREAT_WINDOW secondes, les plus anciens sont retirés.
	while n > 2 and t[2] <= now - FM.THREAT_WINDOW do
		table.remove(t, 1); table.remove(v, 1); n = n - 1
	end
	local last = math.max(t[n], now - FM.THREAT_STALE)
	local span = last - t[1]
	if span <= 0 then return 0 end
	return (v[n] - v[1]) / span
end

-- Derniers événements d'un recap de mort (C_DeathRecap.GetRecapEvents), affichés du plus ancien au plus récent.
-- Blizzard les rend du coup mortel au plus ancien : liste remise dans l'ordre d'après les timestamps.
-- Chaque ligne : { left = "-2.3s  Sort (source)", right = "-1.2k  2.0k" }. `spellName(id)` résout un ID de sort.
function FM.RecapLines(events, spellName, maxLines, hideSecretNames)
	local lines = {}
	if not events or #events == 0 then return lines end
	if (events[1].timestamp or 0) > (events[#events].timestamp or 0) then
		local reversed = {}
		for i = #events, 1, -1 do reversed[#reversed + 1] = events[i] end
		events = reversed
	end
	maxLines = maxLines or FM.RECAP_LINES
	local last = events[#events].timestamp or 0
	for i = math.max(1, #events - maxLines + 1), #events do
		local e = events[i]
		local name = e.spellName or (e.spellId and spellName and spellName(e.spellId)) or e.environmentalType or "?"
		-- Nom de créature secret en instance : pas comparable, mais concaténable (ligne secrète, affichée en local).
		-- hideSecretNames (report en chat) : le nom secret est omis, la ligne reste envoyable.
		local who = e.sourceName
		if issecretvalue(who) then
			if not hideSecretNames then name = name .. " (" .. who .. ")" end
		elseif who and who ~= "" then
			name = name .. " (" .. who .. ")"
		end
		local right = "-" .. FM.FormatValue(e.amount or 0)
		if e.currentHP then right = right .. "  " .. FM.FormatValue(e.currentHP) end
		lines[#lines + 1] = { left = string.format("%.1fs  %s", (e.timestamp or last) - last, name), right = right }
	end
	return lines
end

-- Configuration d'une nouvelle fenêtre : mode opposé à celui de la première, collée sous la précédente
-- (anchor = { to = index, side }). `point` sert de repli si la fenêtre est décrochée.
function FM.NewWindowConfig(list, windowHeight)
	local prev = list[#list]
	if not prev then return { mode = "damage", view = "current", point = DEFAULTS.point } end
	local p = prev.point
	return {
		mode = list[1].mode == "damage" and "heal" or "damage",
		view = "current",
		point = { p[1], nil, p[3], p[4], p[5] - windowHeight - 6 },
		anchor = { to = #list, side = "BOTTOM" },
	}
end

-- Place libre pour une nouvelle fenêtre w x h : collée à une fenêtre existante (`first` d'abord, puis la dernière...),
-- côté dessous, droite, dessus puis gauche, sans sortir de l'écran ni recouvrir une autre fenêtre.
-- rects[i] = { left, right, top, bottom } et screen = { largeur, hauteur }, à la même échelle. Rend index, côté ou nil.
function FM.FreeSide(rects, w, h, screen, gap, first)
	local order = { first }
	for k = #rects, 1, -1 do if k ~= first then order[#order + 1] = k end end
	for _, k in ipairs(order) do
		local o = rects[k]
		local candidates = {
			BOTTOM = { o[1], o[1] + w, o[4] - gap, o[4] - gap - h },
			RIGHT  = { o[2] + gap, o[2] + gap + w, o[3], o[3] - h },
			TOP    = { o[1], o[1] + w, o[3] + gap + h, o[3] + gap },
			LEFT   = { o[1] - gap - w, o[1] - gap, o[3], o[3] - h },
		}
		for _, side in ipairs({ "BOTTOM", "RIGHT", "TOP", "LEFT" }) do
			local r = candidates[side]
			local fits = r[1] >= 0 and r[2] <= screen[1] and r[4] >= 0 and r[3] <= screen[2]
			for _, other in ipairs(rects) do
				if fits and r[1] < other[2] and r[2] > other[1] and r[4] < other[3] and r[3] > other[4] then fits = false end
			end
			if fits then return k, side end
		end
	end
	return nil
end

-- Aimantation : côté de `other` contre lequel `rect` a été relâché, ou nil. Rects = { left, right, top, bottom }.
-- BOTTOM/TOP : bords gauches alignés ; RIGHT/LEFT : bords hauts alignés.
function FM.SnapSide(rect, other, threshold)
	local near = function(a, b) return math.abs(a - b) <= threshold end
	if near(rect[1], other[1]) then
		if near(rect[3], other[4]) then return "BOTTOM" end
		if near(rect[4], other[3]) then return "TOP" end
	end
	if near(rect[3], other[3]) then
		if near(rect[1], other[2]) then return "RIGHT" end
		if near(rect[2], other[1]) then return "LEFT" end
	end
	return nil
end

-- L'ancrage de la fenêtre i est valide s'il vise une autre fenêtre existante et ne boucle pas sur i.
function FM.AnchorValid(list, i)
	local seen, k = {}, i
	while list[k] and list[k].anchor do
		local to = list[k].anchor.to
		if to == i or to == k or not list[to] or seen[to] then return false end
		seen[to] = true
		k = to
	end
	return list[i] and list[i].anchor ~= nil
end

-- Retire la fenêtre k : les ancrages qui la visaient sont décrochés, les index au-dessus décalés.
function FM.RemoveWindowConfig(list, k)
	table.remove(list, k)
	for _, c in ipairs(list) do
		local a = c.anchor
		if a then
			if a.to == k then c.anchor = nil elseif a.to > k then a.to = a.to - 1 end
		end
	end
end

-- Bornes des réglages numériques, partagées par les commandes /fm, les curseurs du panneau et l'import.
FM.BOUNDS = {
	scale = { min = 0.5, max = 2, step = 0.05 },
	rows = { min = 1, max = 40, step = 1 },
	width = { min = 150, max = 600, step = 10 },
	refresh = { min = 0.05, max = 2, step = 0.05 },
	warnPct = { min = 1, max = 130, step = 1 },
	fontSize = { min = 6, max = 24, step = 1 },
	rowHeight = { min = 10, max = 40, step = 1 },
	bgAlpha = { min = 0, max = 1, step = 0.05 },
	windows = { min = 1, max = FM.MAX_WINDOWS, step = 1 },
}

-- Valeur ramenée dans ses bornes ; entière quand le pas est entier.
function FM.Clamp(key, v)
	local b = FM.BOUNDS[key]
	if b.step >= 1 then v = math.floor(v) end
	return math.max(b.min, math.min(b.max, v))
end

-- Filtre des sources ennemies sur `classification` (jamais secrète d'après la doc Blizzard ;
-- une valeur secrète garde la ligne, faute de pouvoir la comparer). filter nil = tout.
local FILTER_CLASSIFICATIONS = {
	elite = { worldboss = true, elite = true, rareelite = true },
	boss = { worldboss = true },
}
function FM.FilterSources(list, filter)
	local keep = filter and FILTER_CLASSIFICATIONS[filter]
	if not keep then return list end
	local out = {}
	for _, s in ipairs(list) do
		local c = s.classification
		if issecretvalue(c) or keep[c] then out[#out + 1] = s end
	end
	return out
end

-- Validation d'un import de réglages (chaîne collée par n'importe qui) : copie propre, ou nil et la clé fautive.
-- Toute clé inconnue, tout type ou toute valeur hors bornes rejette l'ensemble.
local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local SIDES = { BOTTOM = true, RIGHT = true, TOP = true, LEFT = true }

local function Bounded(key)
	return function(v)
		local b = FM.BOUNDS[key]
		-- rows sert d'indice de liste : entier exigé ; width reste libre (anciennes largeurs non entières sauvegardées)
		return type(v) == "number" and v >= b.min and v <= b.max and (key ~= "rows" or v == math.floor(v)), v
	end
end
local function Boolean(v) return type(v) == "boolean", v end
local function Name(v) return type(v) == "string" and #v <= 100, v end
local function Finite(v) return type(v) == "number" and v == v and math.abs(v) < 100000 end

local function ValidPoint(p)
	if type(p) ~= "table" or not POINTS[p[1]] or p[2] ~= nil or not POINTS[p[3]] or not Finite(p[4]) or not Finite(p[5]) then return false end
	for k in pairs(p) do if k ~= 1 and k ~= 3 and k ~= 4 and k ~= 5 then return false end end
	return true, { p[1], nil, p[3], p[4], p[5] }
end

local function ValidColumns(c)
	if type(c) ~= "table" then return false end
	local out = {}
	for k, v in pairs(c) do
		if not DEFAULTS.columns[k] or type(v) ~= "boolean" then return false end
		out[k] = v
	end
	return true, out
end

local function ValidColor(c)
	if type(c) ~= "table" then return false end
	for k, v in pairs(c) do
		if (k ~= "r" and k ~= "g" and k ~= "b") or type(v) ~= "number" or not (v >= 0 and v <= 1) then return false end
	end
	if not (c.r and c.g and c.b) then return false end
	return true, { r = c.r, g = c.g, b = c.b }
end

local WINDOW_FIELDS = {
	mode = function(v) return type(v) == "string" and FM.MODE_INFO[v] ~= nil, v end,
	view = function(v) return v == "current" or v == "overall" or (type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge), v end, -- un sessionID repasse à current (InitDb)
	rows = Bounded("rows"),
	width = Bounded("width"),
	bigNumber = Boolean, locked = Boolean, noHeader = Boolean, onlyMe = Boolean, minimized = Boolean,
	columns = ValidColumns,
	point = ValidPoint,
	barColor = ValidColor,
	filter = function(v) return FILTER_CLASSIFICATIONS[v] ~= nil, v end,
}

local SETTINGS_FIELDS = {
	scale = Bounded("scale"), rows = Bounded("rows"), width = Bounded("width"), refresh = Bounded("refresh"),
	warnPct = Bounded("warnPct"), fontSize = Bounded("fontSize"), rowHeight = Bounded("rowHeight"), bgAlpha = Bounded("bgAlpha"),
	warnSound = Boolean, showPets = Boolean, autoHide = Boolean, autoReset = Boolean, instanceOnly = Boolean,
	columns = ValidColumns,
	locale = function(v) return type(v) == "string" and FM.FindLocale(v) == v, v end,
	barTexture = Name, barFont = Name,
	point = ValidPoint, detailPoint = ValidPoint,
}

-- Copie des champs de `t` validés par `fields`, `skip` mis à part ; nil et la clé fautive au premier écart.
local function CopyFields(t, fields, skip)
	local out = {}
	for k, v in pairs(t) do
		if k ~= skip then
			local check = type(k) == "string" and fields[k]
			if not check then return nil, tostring(k) end
			local ok, clean = check(v)
			if not ok then return nil, k end
			out[k] = clean
		end
	end
	return out
end

function FM.ValidateSettings(t)
	if type(t) ~= "table" then return nil, "?" end
	local list = t.windows
	local out, bad = CopyFields(t, SETTINGS_FIELDS, "windows")
	if not out then return nil, bad end
	if type(list) ~= "table" or #list < 1 or #list > FM.MAX_WINDOWS then return nil, "windows" end
	local count = 0
	for _ in pairs(list) do count = count + 1 end
	if count ~= #list then return nil, "windows" end
	-- # en Lua 5.1 peut rendre n'importe quelle bordure d'une liste à trous : clés 1..n exigées
	for i = 1, #list do if list[i] == nil then return nil, "windows" end end
	out.windows = {}
	for i, c in ipairs(list) do
		if type(c) ~= "table" or c.mode == nil then return nil, "windows." .. i end
		local anchor = c.anchor
		local w, wrong = CopyFields(c, WINDOW_FIELDS, "anchor")
		if not w then return nil, "windows." .. i .. "." .. wrong end
		if anchor ~= nil then
			local to = type(anchor) == "table" and anchor.to
			local valid = type(to) == "number" and to == math.floor(to) and to >= 1 and to <= #list and to ~= i and SIDES[anchor.side]
			for k in pairs(type(anchor) == "table" and anchor or {}) do if k ~= "to" and k ~= "side" then valid = false end end
			if not valid then return nil, "windows." .. i .. ".anchor" end
			w.anchor = { to = to, side = anchor.side }
		end
		out.windows[i] = w
	end
	return out
end

-- Arguments de /fm report : "[N] [say|guild|party|raid|instance|whisper <nom>]" -> N, canal, cible.
-- Canal absent : nil (choix automatique). Canal inconnu, chuchotement sans nom, N nul ou collé au canal : false.
local REPORT_CHANNELS = { say = "SAY", guild = "GUILD", party = "PARTY", raid = "RAID", instance = "INSTANCE_CHAT", whisper = "WHISPER" }
function FM.ParseReport(arg)
	local digits, space, word, target = arg:match("^(%d*)(%s*)(%S*)%s*(.-)$")
	local count = tonumber(digits)
	if count == 0 or (count and word ~= "" and space == "") then return false end
	if word == "" then return count end
	local channel = REPORT_CHANNELS[word:lower()]
	if not channel or (channel == "WHISPER") ~= (target ~= "") then return false end
	return count, channel, target ~= "" and target or nil
end

------------------------------------------------------------------------
-- 2. Partie WoW
------------------------------------------------------------------------
if not CreateFrame then return end

-- Diagnostic : enregistré avant tout le reste pour nommer une fonction refusée même au chargement.
-- Le nom est affiché dans le chat et conservé dans ForeverMeterDB.forbidden (lisible dans les SavedVariables).
local forbiddenLog = {}
local guard = CreateFrame("Frame")
guard:RegisterEvent("ADDON_ACTION_FORBIDDEN")
guard:RegisterEvent("ADDON_ACTION_BLOCKED")
guard:SetScript("OnEvent", function(_, event, addonName, func)
	if addonName ~= ADDON then return end
	local line = date("%H:%M:%S") .. " " .. event .. " " .. tostring(func) .. (guard.pending and (" [" .. guard.pending .. "]") or "")
	if #forbiddenLog >= 50 then table.remove(forbiddenLog, 1) end
	forbiddenLog[#forbiddenLog + 1] = line
	if ForeverMeterDB then ForeverMeterDB.forbidden = forbiddenLog end
	DEFAULT_CHAT_FRAME:AddMessage("|cffff3333ForeverMeter|r : " .. string.format(L.FORBIDDEN, line))
end)

-- Nomme l'événement en cours d'enregistrement si le client le refuse.
-- Un événement inconnu du client (liste C_DamageMeter variable selon la version) est ignoré sans bloquer le chargement.
local function Register(frame, event)
	guard.pending = event
	local ok = pcall(frame.RegisterEvent, frame, event)
	guard.pending = nil
	if not ok then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff9933ForeverMeter|r : " .. string.format(L.UNKNOWN_EVENT, event))
	end
end

local UnitGUID, UnitName, UnitClass, UnitExists = UnitGUID, UnitName, UnitClass, UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack, UnitIsDead, UnitIsUnit = UnitCanAttack, UnitIsDead, UnitIsUnit
local UnitDetailedThreatSituation, UnitThreatSituation = UnitDetailedThreatSituation, UnitThreatSituation
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local GetTime, PlaySound = GetTime, PlaySound
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local WARN_SOUND = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
local DamageMeter = C_DamageMeter
local DeathRecap = C_DeathRecap

local db
local windows = {}                        -- frames ; windows[i].cfg == db.windows[i] = { mode, view, point }
local threatSamples = {}
local needsRedraw = true                  -- données changées hors combat : l'OnUpdate redessine au prochain tour
local pollUntil = 0                       -- GetTime() jusqu'auquel l'OnUpdate redessine encore après le combat

-- Titre réécrit seulement s'il change. Un texte secret ne se compare pas : toujours posé.
local function SetTitle(fs, text)
	local current = fs:GetText()
	if issecretvalue(text) or issecretvalue(current) or current ~= text then fs:SetText(text) end
end
local warnedGuid = nil                    -- partagé : deux fenêtres en mode menace ne jouent le son qu'une fois
local warnRearmAt = nil                   -- GetTime() à partir duquel l'alerte se réarme, après être repassé sous le seuil
local WARN_REARM_DELAY = 3

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverMeter|r : " .. msg)
end

-- Hauteur d'une fenêtre : titre (absent si cfg.noHeader), puis les lignes ou le gros chiffre (cfg.bigNumber).
-- cfg nil : fenêtre de détail, avec titre.
local BIG_NUMBER_HEIGHT = 36
local function HeaderHeight(cfg) return cfg and cfg.noHeader and 0 or 18 end
-- Réduite : titre seul. Sans titre (noHeader), la réduction est ignorée : la fenêtre deviendrait invisible.
local function Minimized(cfg) return cfg and cfg.minimized and not cfg.noHeader end
local function WindowHeight(rows, cfg)
	if Minimized(cfg) then return HeaderHeight(cfg) end
	if cfg and cfg.bigNumber then return HeaderHeight(cfg) + BIG_NUMBER_HEIGHT end
	return HeaderHeight(cfg) + (rows or db.rows) * (db.rowHeight + 1) + 3
end

-- Taille d'une fenêtre : la sienne (poignée de redimensionnement) sinon la taille commune (/fm rows, /fm width).
local function Rows(win) return win.cfg.rows or db.rows end
local function Width(win) return win.cfg.width or db.width end
-- Lignes affichées : aucune barre sous le gros chiffre, une seule pour « ma barre seulement ».
local function ShownRows(win)
	if win.cfg.bigNumber or Minimized(win.cfg) then return 0 end
	if win.cfg.onlyMe then return 1 end
	return Rows(win)
end
-- Texte des barres : réglage de la fenêtre (menu), sinon le réglage commun (options).
local function Columns(win) return win.cfg.columns or db.columns end
-- Affichage DPS : mode dégâts avec le débit seul en colonne propre à la fenêtre.
local function IsDps(win)
	local c = win.cfg.columns
	return win.cfg.mode == "damage" and c ~= nil and c.perSecond and not c.total and not c.percent
end

------------------------------------------------------------------------
-- Lecture de C_DamageMeter (par fenêtre : win.cfg.mode, win.cfg.view)
------------------------------------------------------------------------
local function MeterType(win)
	return FM.MODE_INFO[win.cfg.mode].type
end

-- Session affichée selon la vue ("current" | "overall" | sessionID). nil si l'API est absente ou la session inconnue.
local function ReadSession(win)
	if not DamageMeter then return nil end
	local t, view = MeterType(win), win.cfg.view
	if view == "overall" then return DamageMeter.GetCombatSessionFromType(FM.SESSION_OVERALL, t) end
	if view == "current" then return DamageMeter.GetCombatSessionFromType(FM.SESSION_CURRENT, t) end
	return DamageMeter.GetCombatSessionFromID(view, t)
end

-- Sorts d'une source (GUID lisible) pour le mode et la session de la fenêtre.
local function ReadSource(win, guid)
	if not DamageMeter then return nil end
	local t, view = MeterType(win), win.cfg.view
	if view == "overall" or view == "current" then
		return DamageMeter.GetCombatSessionSourceFromType(view == "overall" and FM.SESSION_OVERALL or FM.SESSION_CURRENT, t, guid)
	end
	return DamageMeter.GetCombatSessionSourceFromID(view, t, guid)
end

-- Durée de la session affichée, en secondes, ou nil si le client ne la donne pas ou la garde secrète.
local function SessionDuration(win, session)
	local d, view = session and session.durationSeconds, win.cfg.view
	if d == nil and (view == "overall" or view == "current") and DamageMeter and DamageMeter.GetSessionDurationSeconds then
		d = DamageMeter.GetSessionDurationSeconds(view == "overall" and FM.SESSION_OVERALL or FM.SESSION_CURRENT)
	end
	if d == nil or issecretvalue(d) or d <= 0 then return nil end
	return d
end

-- Par seconde d'une source ou d'un sort : amountPerSecond de l'API (vérifié : c'est bien le débit,
-- le type Dps de l'enum ne rend que le total). Hors combat, si l'API rend 0 avec un total non nul,
-- repli total / durée de session.
local function PerSecond(win, entry, session, secret)
	local ps = entry.amountPerSecond or 0
	if secret then return ps end
	if ps == 0 and (entry.totalAmount or 0) > 0 then
		local d = SessionDuration(win, session)
		if d then ps = entry.totalAmount / d end
	end
	return ps
end

local function AvailableSessions()
	if not DamageMeter then return {} end
	return DamageMeter.GetAvailableCombatSessions() or {}
end

local function SessionLabel(win, session)
	local view = win.cfg.view
	if view == "overall" then return L.SESSION_OVERALL end
	if view == "current" then
		-- Hors combat, la session courante du client reste ouverte et sa durée continue de compter : pas de chrono.
		local d = UnitAffectingCombat("player") and session and session.durationSeconds
		return L.SESSION_CURRENT .. (d and not issecretvalue(d) and (" (" .. FM.FormatTime(d) .. ")") or "")
	end
	for _, s in ipairs(AvailableSessions()) do
		if s.sessionID == view then
			local d = s.durationSeconds
			-- string.format accepte un nom secret (créature, en combat), la concaténation non.
			return string.format("%s%s", s.name, not issecretvalue(d) and d and (" (" .. FM.FormatTime(d) .. ")") or "")
		end
	end
	return string.format(L.SESSION_UNKNOWN, tostring(view))
end

-- Quitter l'affichage DPS (menu, molette, /fm mode) rend à la fenêtre les colonnes communes.
local function SelectMode(win, m) if IsDps(win) then win.cfg.columns = nil end; win.cfg.mode = m; win.scrollOffset = 0; win.selectedGuid, win.compareGuid = nil, nil end
local function SelectView(win, v) win.cfg.view = v; win.scrollOffset = 0; win.selectedGuid, win.compareGuid = nil, nil end

local function CycleMode(win, step)
	local idx = 1
	for i, m in ipairs(FM.MODES) do if m == win.cfg.mode then idx = i end end
	SelectMode(win, FM.MODES[((idx - 1 + step) % #FM.MODES) + 1])
end

-- Sources de la session. Triées par l'API ; re-triées ici seulement quand les montants sont lisibles.
local function Sources(session)
	local list = session and session.combatSources or {}
	local first = list[1]
	if first and not issecretvalue(first.totalAmount) then
		table.sort(list, function(a, b) return a.totalAmount > b.totalAmount end)
	end
	return list
end

-- Sources affichées par une fenêtre : en dégâts subis par les ennemis, filtre boss / élites (cfg.filter).
local function VisibleSources(win, session)
	local list = Sources(session)
	if win.cfg.mode ~= "enemytaken" then return list end
	return FM.FilterSources(list, win.cfg.filter)
end

-- Sorts d'une source, triés quand lisibles. Renvoie la liste et le drapeau secret.
local function SortedSpells(source)
	local spells = source and source.combatSpells or {}
	local secret = spells[1] and issecretvalue(spells[1].totalAmount) or false
	if not secret then
		table.sort(spells, function(a, b) return a.totalAmount > b.totalAmount end)
	end
	return spells, secret
end

------------------------------------------------------------------------
-- Menace (hors C_DamageMeter)
------------------------------------------------------------------------
-- En raid, raid1..N contient déjà le joueur : "player" n'est ajouté qu'en solo ou en groupe.
local function PetUnit(unit)
	if unit == "player" then return "pet" end
	return (unit:gsub("^(%a+)(%d+)$", "%1pet%2"))
end

-- Unités du groupe et leurs familiers, en cache jusqu'au prochain GROUP_ROSTER_UPDATE.
local groupUnits, groupPets
local function GroupUnits()
	if groupUnits then return groupUnits, groupPets end
	groupUnits, groupPets = {}, {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do groupUnits[#groupUnits + 1] = "raid" .. i end
	else
		groupUnits[1] = "player"
		if IsInGroup() then
			for i = 1, GetNumGroupMembers() - 1 do groupUnits[#groupUnits + 1] = "party" .. i end
		end
	end
	for i, unit in ipairs(groupUnits) do groupPets[i] = PetUnit(unit) end
	return groupUnits, groupPets
end

local function ThreatTarget()
	if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
		return "target"
	end
	return nil
end

-- Liste et lignes réutilisées d'un tour à l'autre : la liste rendue n'est valable que jusqu'au prochain appel.
local threatList, threatRows = {}, {}

-- Renvoie true si l'unité est sur la table de menace mais illisible (statut secret).
local function AddThreatRow(u, enemy, now)
	if not UnitExists(u) then return end
	local isTanking, status, pct, rawPct, value = UnitDetailedThreatSituation(u, enemy)
	-- Cible boss : valeurs secrètes. Repli sur le statut 0-3, lisible dans plus de cas (SecretWhenUnitThreatStateRestricted).
	local statusOnly = issecretvalue(isTanking) or issecretvalue(status) or issecretvalue(pct) or issecretvalue(rawPct) or issecretvalue(value)
	if statusOnly then status = UnitThreatSituation(u, enemy) end
	if issecretvalue(status) then return true end
	if not status then return end
	local guid = UnitGUID(u)
	local isPlayer = UnitIsUnit(u, "player")
	if issecretvalue(isPlayer) then -- comparaison restreinte : repli sur le GUID, lisible pour un membre du groupe
		local myGuid = UnitGUID("player")
		isPlayer = u == "player" or (not issecretvalue(guid) and not issecretvalue(myGuid) and guid == myGuid)
	end
	if issecretvalue(guid) then guid = u end -- identité restreinte : le jeton sert de clé
	local _, class = UnitClass(u)
	local tps
	if statusOnly then
		value = nil
	else
		value = value or 0
		local samples = threatSamples[guid]
		if not samples then samples = { t = {}, v = {} }; threatSamples[guid] = samples end
		tps = FM.ThreatRate(samples, value, now)
	end
	local n = #threatList + 1
	local row = threatRows[n] or {}
	threatRows[n] = row
	row.name, row.class, row.guid = UnitName(u) or u, class, guid
	if statusOnly then
		row.status, row.tanking, row.pct = status, status >= 2, FM.STATUS_PCT[status] or 0
	else
		row.status = nil
		row.tanking = isTanking and true or false
		row.pct = isTanking and 100 or (rawPct or pct or 0) -- rawPct est faux pour le tank
	end
	row.value, row.tps, row.isPlayer = value, tps, isPlayer
	threatList[n] = row
end

-- Renvoie la liste triée, et true si au moins une unité était illisible.
local function CollectThreat(enemy)
	wipe(threatList)
	local now = GetTime()
	local units, pets = GroupUnits()
	local hidden = false
	for i, unit in ipairs(units) do
		if AddThreatRow(unit, enemy, now) then hidden = true end
		if db.showPets and AddThreatRow(pets[i], enemy, now) then hidden = true end
	end
	return FM.SortThreat(threatList), hidden
end

-- Texte d'une ligne en statut seul : libellé, vide au statut 0.
local function StatusLabel(row)
	return row.status == 1 and L.THREAT_STATUS_1 or row.status == 2 and L.THREAT_STATUS_2 or row.status == 3 and L.THREAT_STATUS_3 or ""
end

------------------------------------------------------------------------
-- Fenêtres
------------------------------------------------------------------------
local function ClassColor(class)
	local c = not issecretvalue(class) and class and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

-- Couleur choisie pour la fenêtre (cfg.barColor), sinon couleur de classe.
local function BarColor(win, class)
	local c = win.cfg.barColor
	if c then return c.r, c.g, c.b end
	return ClassColor(class)
end

local function MakeWindow(name, w, h)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(w, h)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	-- Frame nommée : StopMovingOrSizing la marque « placée par l'utilisateur » et le client restaure alors sa
	-- taille depuis layout-local.txt après ADDON_LOADED, sans passer par Layout() : le cadre et les barres divergent.
	f:SetUserPlaced(false)
	f:HookScript("OnShow", function() needsRedraw = true end)
	f:EnableMouse(true)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f:SetBackdropColor(0, 0, 0, DEFAULTS.bgAlpha)
	f:SetBackdropBorderColor(0, 0, 0, 1)
	f.header = CreateFrame("Button", nil, f)
	f.header:SetPoint("TOPLEFT")
	f.header:SetPoint("TOPRIGHT")
	f.header:SetHeight(18)
	f.header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f.header:RegisterForDrag("LeftButton")
	f.header.bg = f.header:CreateTexture(nil, "BACKGROUND")
	f.header.bg:SetAllPoints()
	f.header.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
	f.title = f.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.title:SetPoint("LEFT", 4, 0)
	f.title:SetPoint("RIGHT", -4, 0)
	f.title:SetJustifyH("LEFT")
	f.title:SetWordWrap(false)
	f.bars = {}
	return f
end

-- Remplissage animé des barres (comme Details) ; nil sur un client sans l'option : saut direct.
local SMOOTH_FILL = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local function MakeBar(parent, i)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetMinMaxValues(0, 100)
	bar:EnableMouse(true)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetPoint("LEFT", 1, 0)
	bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	bar.left = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.left:SetPoint("LEFT", bar.icon, "RIGHT", 3, 0)
	bar.left:SetJustifyH("LEFT")
	bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.right:SetPoint("RIGHT", -3, 0)
	bar.right:SetJustifyH("RIGHT")
	bar.left:SetPoint("RIGHT", bar.right, "LEFT", -4, 0)
	bar.glow = bar:CreateTexture(nil, "OVERLAY")
	bar.glow:SetAllPoints()
	bar.glow:SetColorTexture(1, 0, 0, 0.35)
	bar.glow:Hide()
	parent.bars[i] = bar
	return bar
end

-- Le client charge un fichier de police en différé : au premier SetFont, la police de repli s'affiche.
-- À chaque nouvelle police, la boucle OnUpdate relance Layout() une fois après ce délai.
local FONT_RETRY_DELAY = 0.5
local appliedFont, fontRetryIn

-- Place les barres pour `rows` lignes et `width` px sans toucher à la taille de la frame.
local function LayoutBars(f, rows, width)
	needsRedraw = true -- les textes sont vidés plus bas : l'OnUpdate les réécrit
	f.rows = rows
	-- Média introuvable (addon LibSharedMedia retiré) : défaut à l'affichage, le réglage reste pour son retour.
	local _, texture = FM.FindMedia(FM.MediaList("statusbar"), db.barTexture)
	local _, font = FM.FindMedia(FM.MediaList("font"), db.barFont)
	texture = texture or FM.BAR_TEXTURES[1][2]
	local fontKey = tostring(font) .. "/" .. tostring(db.fontSize)
	if fontKey ~= appliedFont then appliedFont, fontRetryIn = fontKey, FONT_RETRY_DELAY end
	for i = 1, math.max(rows, #f.bars) do
		local bar = f.bars[i] or MakeBar(f, i)
		bar:SetSize(width - 6, db.rowHeight)
		bar.icon:SetSize(db.rowHeight - 2, db.rowHeight - 2)
		bar:SetStatusBarTexture(texture)
		for _, text in ipairs({ bar.left, bar.right }) do
			text:SetFontObject(GameFontHighlightSmall)
			if font or db.fontSize then
				-- Comme Details : SetFont sans lire son retour (pas fiable d'un client à l'autre), ombre gardée.
				local defaultFont, defaultSize = text:GetFont()
				text:SetFont(font or defaultFont or STANDARD_TEXT_FONT, db.fontSize or defaultSize or 10, "")
			end
			-- Un FontString ne se redessine qu'à un texte différent : vidé ici, Refresh() le réécrit avec la police.
			text:SetText("")
		end
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", 3, -HeaderHeight(f.cfg) - (i - 1) * (db.rowHeight + 1))
		if i > rows then bar:Hide() end
	end
end

local function LayoutWindow(f, rows, width)
	f:SetScale(db.scale)
	f:SetBackdropColor(0, 0, 0, db.bgAlpha)
	f:SetWidth(width)
	f:SetHeight(WindowHeight(rows, f.cfg))
	if f.cfg then
		local minimized = Minimized(f.cfg)
		f.header:SetShown(not f.cfg.noHeader)
		f.big:SetShown(f.cfg.bigNumber == true and not minimized)
		f.grip:SetShown(not minimized)
		f.gripLeft:SetShown(not minimized)
		f.minimizeButton:SetNormalTexture(minimized and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
	end
	LayoutBars(f, rows, width)
end

-- Fenêtre de détail par sort, unique, pour la fenêtre qui l'a ouverte (detail.owner). Panneau à part : au-dessus
-- des compteurs (strate DIALOG), déplaçable par son titre, position gardée dans db.detailPoint.
local detail = MakeWindow("ForeverMeterDetailFrame", DEFAULTS.width, 100)
detail:Hide()
detail:SetFrameStrata("DIALOG")
detail:SetToplevel(true)
detail.header:SetScript("OnDragStart", function() detail:StartMoving() end)
detail.header:SetScript("OnDragStop", function()
	detail:StopMovingOrSizing()
	detail:SetUserPlaced(false)
	local point, _, relPoint, x, y = detail:GetPoint()
	db.detailPoint = { point, nil, relPoint, x, y }
end)
detail.close = CreateFrame("Button", nil, detail.header, "UIPanelCloseButton")
detail.close:SetPoint("RIGHT", 2, 0)
detail.close:SetSize(20, 20)
detail.close:SetScript("OnClick", function()
	if detail.owner then detail.owner.selectedGuid, detail.owner.compareGuid = nil, nil end
	detail:Hide()
end)

local ANCHOR_GAP = 2
local ANCHOR_POINTS = {
	BOTTOM = { "TOPLEFT", "BOTTOMLEFT", 0, -ANCHOR_GAP },
	TOP    = { "BOTTOMLEFT", "TOPLEFT", 0, ANCHOR_GAP },
	RIGHT  = { "TOPLEFT", "TOPRIGHT", ANCHOR_GAP, 0 },
	LEFT   = { "TOPRIGHT", "TOPLEFT", -ANCHOR_GAP, 0 },
}

-- Détail à la taille de sa fenêtre. Position : celle où l'utilisateur l'a posé, sinon un côté libre
-- de sa fenêtre (ou d'une autre) pour ne rien recouvrir, sinon le centre de l'écran.
local function AnchorDetail()
	local owner = detail.owner or windows[1]
	LayoutWindow(detail, Rows(owner), Width(owner))
	detail:ClearAllPoints()
	local p = db.detailPoint
	if p then
		detail:SetPoint(p[1], UIParent, p[3], p[4], p[5])
		return
	end
	local rects = {}
	for i = 1, #db.windows do
		local o = windows[i]
		rects[i] = { o:GetLeft() or 0, o:GetRight() or 0, o:GetTop() or 0, o:GetBottom() or 0 }
	end
	local screen = { (UIParent:GetWidth() or 0) / db.scale, (UIParent:GetHeight() or 0) / db.scale }
	local to, side = FM.FreeSide(rects, Width(owner), WindowHeight(Rows(owner)), screen, ANCHOR_GAP, owner.index)
	if to then
		local a = ANCHOR_POINTS[side]
		detail:SetPoint(a[1], windows[to], a[2], a[3], a[4])
	else
		detail:SetPoint("CENTER", UIParent, "CENTER")
	end
end

local function Layout()
	for i = 1, #db.windows do
		local f = windows[i]
		LayoutWindow(f, ShownRows(f), Width(f))
		f:ClearAllPoints()
		if f.cfg.anchor and FM.AnchorValid(db.windows, i) then
			-- Collée à une autre fenêtre : elle suit ses déplacements et sa taille.
			local a, p = f.cfg.anchor, ANCHOR_POINTS[f.cfg.anchor.side]
			f:SetPoint(p[1], windows[a.to], p[2], p[3], p[4])
		else
			f.cfg.anchor = nil
			f:SetPoint(f.cfg.point[1], UIParent, f.cfg.point[3], f.cfg.point[4], f.cfg.point[5])
		end
	end
	AnchorDetail()
end

-- Position absolue d'une fenêtre (pour la garder en place quand on la décroche).
local function AbsolutePoint(f)
	return { "BOTTOMLEFT", nil, "BOTTOMLEFT", f:GetLeft(), f:GetBottom() }
end

-- Relâchée près du bord d'une autre fenêtre : s'y colle.
local function TrySnap(f)
	local rect = { f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom() }
	for i = 1, #db.windows do
		local o = windows[i]
		if o ~= f and o:IsShown() then
			local side = FM.SnapSide(rect, { o:GetLeft(), o:GetRight(), o:GetTop(), o:GetBottom() }, 15)
			if side then
				f.cfg.anchor = { to = i, side = side }
				if FM.AnchorValid(db.windows, f.index) then return end
				f.cfg.anchor = nil
			end
		end
	end
end

local GetSpellTextureCompat = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
local GetSpellNameCompat = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
local function SpellIcon(spellID)
	local tex = spellID and GetSpellTextureCompat(spellID)
	return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Nom d'un sort ; en dégâts subis, la créature qui l'a lancé (hors combat : le nom est secret en combat),
-- puis les marques « évitable » et « mortel » (booléens jamais secrets d'après la doc, testés quand même).
-- `plain` : sans code couleur, pour le chat (SendChatMessage refuse les |c).
local function Flag(v) return not issecretvalue(v) and v == true end
local function SpellLabel(win, s, plain)
	local name = GetSpellNameCompat(s.spellID) or ("#" .. tostring(s.spellID))
	if win.cfg.mode ~= "taken" and win.cfg.mode ~= "avoidable" then return name end
	local creature = s.creatureName
	if creature and not issecretvalue(creature) and creature ~= "" then name = name .. " · " .. creature end
	if Flag(s.isAvoidable) then name = name .. (plain and " (" .. L.SPELL_AVOIDABLE .. ")" or " |cffffa500(" .. L.SPELL_AVOIDABLE .. ")|r") end
	if Flag(s.isDeadly) then name = name .. (plain and " (" .. L.SPELL_DEADLY .. ")" or " |cffff3333(" .. L.SPELL_DEADLY .. ")|r") end
	return name
end

local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local function SetClassIcon(bar, class)
	local coords = not issecretvalue(class) and class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		bar.icon:SetTexture(CLASS_ICONS)
		bar.icon:SetTexCoord(unpack(coords))
	else
		bar.icon:SetTexture(nil)
	end
end

-- Icône de spé fournie par l'API quand elle est lisible, sinon icône de classe.
local function SetSourceIcon(bar, src)
	local spec = src.specIconID
	if not issecretvalue(spec) and spec and spec > 0 then
		bar.icon:SetTexture(spec)
		bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	else
		SetClassIcon(bar, src.classFilename)
	end
end

-- Détail par sort de la source sélectionnée dans detail.owner. Le GUID d'un autre joueur est secret en combat.
local function RenderDetail()
	local win = detail.owner
	if not win or not win:IsShown() or Minimized(win.cfg) or not win.selectedGuid or win.cfg.mode == "threat" or not DamageMeter then
		detail:Hide()
		return
	end
	local source = ReadSource(win, win.selectedGuid)
	local spells, secret = SortedSpells(source)
	detail:Show()
	-- Comparaison (Maj+clic) : seulement si les deux listes sont lisibles, sinon détail simple de la source.
	local other, otherSecret
	if win.compareGuid and not secret then other, otherSecret = SortedSpells(ReadSource(win, win.compareGuid)) end
	if other and not otherSecret then
		detail.title:SetText(string.format("%s vs %s : %s", win.selectedName or "?", win.compareName or "?", FM.MODE_INFO[win.cfg.mode].label))
		local rows = FM.CompareSpells(spells, other)
		local top = rows[1] and math.max(rows[1].a or 0, rows[1].b or 0) or 1
		for i = 1, detail.rows do
			local bar, r = detail.bars[i], rows[i]
			if r then
				bar:SetMinMaxValues(0, top)
				bar:SetValue(r.a or 0, SMOOTH_FILL)
				bar:SetStatusBarColor(0.8, 0.6, 0.2)
				bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				bar.icon:SetTexture(SpellIcon(r.spellID))
				bar.left:SetText(SpellLabel(win, r))
				bar.right:SetText(FM.FormatCompare(r.a, r.b))
				bar:Show()
			else
				bar:Hide()
			end
		end
		return
	end
	detail.title:SetText((win.selectedName or "?") .. " : " .. FM.MODE_INFO[win.cfg.mode].label)
	local sessionTotal = source and source.totalAmount
	local session = ReadSession(win)
	for i = 1, detail.rows do
		local bar, s = detail.bars[i], spells[i]
		if s then
			bar:SetMinMaxValues(0, source.maxAmount or 1)
			bar:SetValue(s.totalAmount, SMOOTH_FILL)
			bar:SetStatusBarColor(0.8, 0.6, 0.2)
			bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			bar.icon:SetTexture(SpellIcon(s.spellID))
			bar.left:SetText(SpellLabel(win, s))
			bar.right:SetText(FM.FormatRow(s.totalAmount, PerSecond(win, s, session, secret), sessionTotal, secret, Columns(win)))
			bar:Show()
		else
			bar:Hide()
		end
	end
end

-- Mode test (/fm test) : fausses barres pour régler l'apparence sans combat. Ni rapport ni détail.
local testMode = false
local TEST_CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "DRUID", "PALADIN", "WARLOCK", "SHAMAN" }
local function TestSession()
	local list, total = {}, 0
	for i, class in ipairs(TEST_CLASSES) do
		local amount = 100000 - (i - 1) * 9000
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
		-- worldboss : les fausses lignes passent tous les filtres d'ennemis.
		list[i] = { name = name, classFilename = class, classification = "worldboss", totalAmount = amount, amountPerSecond = amount / 60 }
		total = total + amount
	end
	return { combatSources = list, maxAmount = list[1].totalAmount, totalAmount = total }
end

local function RenderMeter(win)
	local session = testMode and TestSession() or ReadSession(win)
	local mode = win.cfg.mode
	local label
	if testMode then
		label = L.SESSION_TEST
	elseif not DamageMeter or (DamageMeter.IsDamageMeterAvailable and not DamageMeter.IsDamageMeterAvailable()) then
		label = L.METER_UNAVAILABLE
	else
		label = SessionLabel(win, session)
	end
	SetTitle(win.title, (IsDps(win) and L.MENU_DPS or FM.MODE_INFO[mode].label) .. " · " .. label)
	local list = VisibleSources(win, session)
	local maxAmount = session and session.maxAmount or 1
	local sessionTotal = session and session.totalAmount
	local secret = list[1] and issecretvalue(list[1].totalAmount)
	-- Lignes filtrées : la plus grande visible remplit la barre (liste déjà triée par l'API ou par Sources).
	-- En combat, list[1].totalAmount est secret : SetMinMaxValues l'accepte, aucune comparaison ici.
	if list[1] and list ~= (session and session.combatSources) then maxAmount = list[1].totalAmount end
	if secret then win.scrollOffset = 0 end
	local maxOffset = math.max(0, #list - win.rows)
	if win.scrollOffset > maxOffset then win.scrollOffset = maxOffset end
	-- Sa propre barre prend la dernière ligne quand le joueur est sous les lignes visibles.
	-- isLocalPlayer n'est jamais secret : trouvé aussi en combat.
	local myIndex
	for index, src in ipairs(list) do
		if not issecretvalue(src.isLocalPlayer) and src.isLocalPlayer then myIndex = index; break end
	end
	if win.cfg.bigNumber then
		local me = myIndex and list[myIndex]
		win.big:SetText(me and FM.FormatRow(me.totalAmount, PerSecond(win, me, session, secret), sessionTotal, secret, Columns(win)) or "")
	end
	for i = 1, win.rows do
		local index = i + win.scrollOffset
		if i == win.rows and win.rows > 1 and myIndex and myIndex > index then index = myIndex end
		if win.cfg.onlyMe then index = myIndex or 0 end
		local bar, src = win.bars[i], list[index]
		if src then
			bar:SetMinMaxValues(0, maxAmount)
			bar:SetValue(src.totalAmount, SMOOTH_FILL)
			bar:SetStatusBarColor(BarColor(win, src.classFilename))
			SetSourceIcon(bar, src)
			bar.left:SetText(string.format("%d. %s", index, src.name))
			local deathTime = mode == "deaths" and src.deathTimeSeconds
			if not secret and not issecretvalue(deathTime) and deathTime then
				-- Morts : nombre, puis instant de la (dernière) mort dans le combat.
				bar.right:SetText(FM.FormatValue(src.totalAmount) .. " · " .. FM.FormatTime(deathTime))
			else
				bar.right:SetText(FM.FormatRow(src.totalAmount, PerSecond(win, src, session, secret), sessionTotal, secret, Columns(win)))
			end
			bar.glow:Hide()
			bar.source = src
			-- Son propre GUID reste lisible en combat ; celui des autres seulement hors combat.
			if src.isLocalPlayer then
				bar.sourceGuid, bar.sourceName = UnitGUID("player"), UnitName("player")
			elseif not issecretvalue(src.sourceGUID) then
				bar.sourceGuid, bar.sourceName = src.sourceGUID, src.name
			else
				bar.sourceGuid, bar.sourceName = nil, nil
			end
			bar:Show()
		else
			bar.source, bar.sourceGuid = nil, nil
			bar:Hide()
		end
	end
end

local function RenderThreat(win)
	local enemy = ThreatTarget()
	local ok, list, hidden = true, threatList, false
	if enemy then ok, list, hidden = pcall(CollectThreat, enemy) else wipe(threatList) end
	if ok and not (hidden and not list[1]) then
		SetTitle(win.title, L.MODE_THREAT .. " · " .. (enemy and (UnitName(enemy) or "?") or L.THREAT_NO_TARGET))
	else
		SetTitle(win.title, L.MODE_THREAT .. " · " .. L.THREAT_UNAVAILABLE)
		wipe(threatList)
		list = threatList
	end
	local mine
	for _, row in ipairs(list) do if row.isPlayer then mine = row; break end end
	if win.cfg.bigNumber then win.big:SetText(mine and (mine.status and StatusLabel(mine) or string.format("%d%%", mine.pct)) or "") end
	-- Alerte sur sa propre ligne, même sans barre affichée (gros chiffre).
	local warn = mine and FM.ShouldWarn(mine, db.warnPct) or false
	if warn then
		warnRearmAt = nil
		if warnedGuid ~= mine.guid then
			warnedGuid = mine.guid
			-- Un autre addon qui alerte déjà sur la menace (MuscaUI) pose FM.externalWarning : un seul son.
			if db.warnSound and not FM.externalWarning then PlaySound(WARN_SOUND, "Master") end
		end
	elseif mine then
		-- Réarmement après 3 s sous le seuil : une menace qui oscille autour (statut 0-1 contre un boss) ne rejoue pas le son.
		local now = GetTime()
		warnRearmAt = warnRearmAt or now + WARN_REARM_DELAY
		if now >= warnRearmAt then warnedGuid = nil end
	end
	for i = 1, win.rows do
		local bar, row = win.bars[i], list[i]
		if win.cfg.onlyMe then row = mine end
		if row then
			bar:SetMinMaxValues(0, 100)
			bar:SetValue(row.pct, SMOOTH_FILL)
			if row.tanking then bar:SetStatusBarColor(0.9, 0.2, 0.2) else bar:SetStatusBarColor(BarColor(win, row.class)) end
			SetClassIcon(bar, row.class)
			bar.left:SetText((row.isPlayer and "> " or "") .. row.name)
			bar.right:SetText(row.status and StatusLabel(row) or string.format("%s  %s/s  %d%%", FM.FormatValue(row.value), FM.FormatValue(row.tps), row.pct))
			bar.glow:SetShown(row == mine and warn)
			bar.source, bar.sourceGuid = nil, nil
			bar:Show()
		else
			bar:Hide()
		end
	end
end

local function Refresh()
	needsRedraw = false
	for i = 1, #db.windows do
		local win = windows[i]
		if win:IsShown() then
			if win.cfg.mode == "threat" then RenderThreat(win) else RenderMeter(win) end
		end
	end
	RenderDetail()
end

------------------------------------------------------------------------
-- Tooltip d'une barre : top sorts de la source, ou recap de mort en mode Morts
------------------------------------------------------------------------
-- Événements lisibles d'un recap de mort, ou nil et le message à afficher (tooltip et report en chat).
local function RecapEvents(recapID)
	local ok, has = pcall(function()
		return DeathRecap and recapID and not issecretvalue(recapID) and recapID ~= -1 and DeathRecap.HasRecapEvents(recapID)
	end)
	local events = ok and has and DeathRecap.GetRecapEvents(recapID) or nil
	if not events or #events == 0 then return nil, L.TIP_NO_RECAP end
	-- RecapLines compare et formate ces champs : un seul secret et le recap n'est pas lisible.
	for _, e in ipairs(events) do
		if issecretvalue(e.amount) or issecretvalue(e.currentHP) or issecretvalue(e.timestamp) then return nil, L.DETAIL_OUT_OF_COMBAT end
	end
	return events
end

local function AddRecapLines(recapID)
	local events, message = RecapEvents(recapID)
	if not events then
		GameTooltip:AddLine(message, 0.7, 0.7, 0.7)
		return
	end
	for _, line in ipairs(FM.RecapLines(events, GetSpellNameCompat)) do
		GameTooltip:AddDoubleLine(line.left, line.right, 1, 1, 1, 1, 0.5, 0.5)
	end
end

local function ShowTooltip(bar)
	local win, src = bar.win, bar.source
	if not src or win.cfg.mode == "threat" then return end
	GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
	GameTooltip:SetText(src.name, ClassColor(src.classFilename))
	if win.cfg.mode == "deaths" then
		AddRecapLines(src.deathRecapID)
		GameTooltip:AddLine(L.TIP_REPORT_DEATH, 0.5, 0.5, 0.5)
	elseif bar.sourceGuid then
		local source = ReadSource(win, bar.sourceGuid)
		local spells, secret = SortedSpells(source)
		local session = ReadSession(win)
		for i = 1, math.min(5, #spells) do
			local s = spells[i]
			GameTooltip:AddDoubleLine(SpellLabel(win, s), FM.FormatRow(s.totalAmount, PerSecond(win, s, session, secret), source.totalAmount, secret, Columns(win)), 1, 1, 1, 1, 1, 1)
		end
		GameTooltip:AddLine(L.TIP_CLICK, 0.5, 0.5, 0.5)
		GameTooltip:AddLine(L.TIP_COMPARE, 0.5, 0.5, 0.5)
		GameTooltip:AddLine(L.TIP_REPORT, 0.5, 0.5, 0.5)
	else
		GameTooltip:AddLine(L.DETAIL_OUT_OF_COMBAT, 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

local ReportDeath -- défini après ChatSend

-- Clic sur une barre : détail par sort, dans la fenêtre de détail unique.
-- Mode Morts : Maj+clic envoie le recap de cette mort dans le chat.
local function BarClick(bar)
	local win = bar.win
	if win.cfg.mode == "deaths" and IsShiftKeyDown() and bar.source then
		ReportDeath(bar.source)
		return
	end
	if not bar.sourceGuid then
		if win.cfg.mode ~= "threat" then Print(L.DETAIL_OUT_OF_COMBAT) end
		return
	end
	local detailHere = detail.owner == win and win.selectedGuid
	if detailHere and IsShiftKeyDown() and win.selectedGuid ~= bar.sourceGuid then
		-- Maj+clic : compare la source du détail avec celle-ci ; même Maj+clic : fin de la comparaison.
		if win.compareGuid == bar.sourceGuid then
			win.compareGuid, win.compareName = nil, nil
		else
			win.compareGuid, win.compareName = bar.sourceGuid, bar.sourceName
		end
	elseif detailHere and win.selectedGuid == bar.sourceGuid then
		win.selectedGuid, win.selectedName, win.compareGuid = nil, nil, nil
	else
		if detail.owner and detail.owner ~= win then detail.owner.selectedGuid, detail.owner.compareGuid = nil, nil end
		detail.owner = win
		win.selectedGuid, win.selectedName, win.compareGuid = bar.sourceGuid, bar.sourceName, nil
		AnchorDetail()
	end
	Refresh()
end

------------------------------------------------------------------------
-- Menu (mode, session, fenêtres, verrou, remise à zéro) et gestion des fenêtres
------------------------------------------------------------------------
local EnsureWindows -- défini plus bas, après NewWindow
local OpenOptions   -- défini avec le panneau d'options, en fin de fichier
local openOptionsAfterCombat = false

local function ResetData()
	if DamageMeter and DamageMeter.ResetAllCombatSessions then DamageMeter.ResetAllCombatSessions() end
	-- Seul un sessionID disparaît avec les données : « current » et « overall » choisis au menu restent.
	for i = 1, #db.windows do
		local win = windows[i]
		SelectView(win, type(win.cfg.view) == "number" and "current" or win.cfg.view)
	end
	wipe(threatSamples)
	Refresh()
end

-- parent : fenêtre d'où vient la demande (menu), sinon la dernière. La nouvelle reprend sa taille et son verrou.
local function AddWindow(parent)
	if #db.windows >= FM.MAX_WINDOWS then return end
	parent = parent or windows[#db.windows]
	local c = FM.NewWindowConfig(db.windows, WindowHeight(db.windows[#db.windows].rows))
	c.width, c.rows, c.locked = parent.cfg.width, parent.cfg.rows, parent.cfg.locked
	-- Collée à un côté libre ; sinon (écran plein) décalée en cascade depuis le centre, non collée.
	-- Coordonnées des fenêtres : échelle db.scale par rapport à UIParent.
	local rects = {}
	for i = 1, #db.windows do
		local o = windows[i]
		rects[i] = { o:GetLeft() or 0, o:GetRight() or 0, o:GetTop() or 0, o:GetBottom() or 0 }
	end
	local screen = { (UIParent:GetWidth() or 0) / db.scale, (UIParent:GetHeight() or 0) / db.scale }
	local to, side = FM.FreeSide(rects, Width(parent), WindowHeight(ShownRows({ cfg = c }), c), screen, ANCHOR_GAP, parent.index)
	if to then
		c.anchor = { to = to, side = side }
	else
		c.anchor = nil
		c.point = { "CENTER", nil, "CENTER", 30 * #db.windows, -30 * #db.windows }
	end
	db.windows[#db.windows + 1] = c
	EnsureWindows()
	Layout()
	Refresh()
end

-- Retire la fenêtre k ; celles qui y étaient collées gardent leur position à l'écran.
local function RemoveWindow(k)
	for i = 1, #db.windows do
		local c = db.windows[i]
		if c.anchor and c.anchor.to == k then c.point = AbsolutePoint(windows[i]) end
	end
	FM.RemoveWindowConfig(db.windows, k)
end

local function CloseWindow(win)
	if #db.windows <= 1 then return end
	RemoveWindow(win.index)
	EnsureWindows()
	Layout()
	Refresh()
end

-- Entrées du menu sous forme neutre : { text, checked(), func [, checkbox] } ou { title } ou { divider }.
-- Lignes du report d'une fenêtre (chat et copie en texte) ; nil et le message à afficher si rien n'est rapportable.
local function ReportLines(win, count)
	if win.cfg.mode == "threat" then return nil, L.REPORT_NOTHING_THREAT end
	local session = ReadSession(win)
	local list = VisibleSources(win, session)
	if not list[1] then return nil, L.REPORT_NOTHING end
	if issecretvalue(list[1].totalAmount) then return nil, L.REPORT_OUT_OF_COMBAT end
	local lines = { string.format(L.REPORT_HEADER, FM.MODE_INFO[win.cfg.mode].label, SessionLabel(win, session)) }
	for i = 1, math.min(count, #list) do
		local s = list[i]
		lines[#lines + 1] = string.format("%d. %s  %s", i, s.name, FM.FormatRow(s.totalAmount, PerSecond(win, s, session, false), session.totalAmount, false, Columns(win)))
	end
	return lines
end

-- Fenêtre de texte unique (copie, export, import), texte sélectionné pour un Ctrl+C.
-- `import` : bouton Importer, qui reçoit le texte de la zone de saisie.
local copyFrame
local function ShowTextWindow(text, hint, import)
	if not copyFrame then
		copyFrame = MakeWindow("ForeverMeterCopyFrame", 340, 220)
		copyFrame:SetFrameStrata("DIALOG")
		copyFrame:SetPoint("CENTER")
		copyFrame:SetBackdropColor(0, 0, 0, 0.9)
		copyFrame.header:SetScript("OnDragStart", function() copyFrame:StartMoving() end)
		copyFrame.header:SetScript("OnDragStop", function()
			copyFrame:StopMovingOrSizing()
			copyFrame:SetUserPlaced(false)
		end)
		local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 6, -24)
		scroll:SetPoint("BOTTOMRIGHT", -28, 6)
		local box = CreateFrame("EditBox", nil, scroll)
		box:SetMultiLine(true)
		box:SetAutoFocus(false)
		box:SetFontObject(ChatFontNormal)
		box:SetWidth(300)
		box:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
		scroll:SetScrollChild(box)
		copyFrame.box = box
		copyFrame.scroll = scroll
		local button = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
		button:SetSize(100, 22)
		button:SetPoint("BOTTOMRIGHT", -8, 6)
		button:SetScript("OnClick", function() if copyFrame.import then copyFrame.import(copyFrame.box:GetText()) end end)
		copyFrame.importButton = button
		if UISpecialFrames then table.insert(UISpecialFrames, "ForeverMeterCopyFrame") end
	end
	copyFrame.title:SetText(hint)
	copyFrame.import = import
	copyFrame.scroll:SetPoint("BOTTOMRIGHT", -28, import and 32 or 6)
	copyFrame.importButton:SetText(L.OPT_IMPORT)
	copyFrame.importButton:SetShown(import ~= nil)
	copyFrame:Show()
	copyFrame.box:SetText(text)
	copyFrame.box:SetFocus()
	copyFrame.box:HighlightText()
end

-- Copie en texte (menu de la fenêtre) : toutes les lignes du report, pour un Ctrl+C vers Discord.
-- Une ligne secrète (nom de créature en instance) ne peut pas aller dans la zone de saisie : elle est omise.
local function CopyWindow(win)
	local lines, err = ReportLines(win, math.huge)
	if not lines then Print(err); return end
	local plain, sources = {}, 0
	for i, line in ipairs(lines) do
		if not issecretvalue(line) then
			plain[#plain + 1] = line
			if i > 1 then sources = sources + 1 end
		end
	end
	if sources == 0 then Print(L.REPORT_NOTHING); return end
	ShowTextWindow(table.concat(plain, "\n"), L.COPY_HINT)
end

-- Couleur unique des barres de la fenêtre, choisie au sélecteur du client ; Annuler remet la précédente.
local function PickBarColor(win)
	local previous = win.cfg.barColor
	local r, g, b
	if previous then r, g, b = previous.r, previous.g, previous.b else r, g, b = ClassColor(select(2, UnitClass("player"))) end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b, hasOpacity = false,
		swatchFunc = function()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			win.cfg.barColor = { r = nr, g = ng, b = nb }
			Refresh()
		end,
		cancelFunc = function() win.cfg.barColor = previous; Refresh() end,
	})
end

local FILTER_CHOICES = { { label = "FILTER_ALL" }, { key = "elite", label = "FILTER_ELITE" }, { key = "boss", label = "FILTER_BOSS" } }

local WINDOW_FLAGS = {
	{ key = "onlyMe", label = "MENU_ONLY_ME" },
	{ key = "noHeader", label = "MENU_NO_HEADER" },
	{ key = "bigNumber", label = "MENU_BIG_NUMBER" },
	{ key = "minimized", label = "MENU_MINIMIZE" },
}
-- Bouton du titre et case du menu. Bord haut fixe, comme à la poignée : l'ancre CENTER ou BOTTOM* déplacerait le titre.
-- Une fenêtre collée à une autre garde son ancre.
local function ToggleMinimized(f)
	if not f.cfg.anchor and f:GetLeft() then f.cfg.point = { "TOPLEFT", nil, "BOTTOMLEFT", f:GetLeft(), f:GetTop() } end
	f.cfg.minimized = not f.cfg.minimized or nil
	Layout()
	Refresh()
end
local COLUMN_CHOICES = {
	{ key = "total", label = "OPT_COL_TOTAL" },
	{ key = "perSecond", label = "OPT_COL_PER_SECOND" },
	{ key = "percent", label = "OPT_COL_PERCENT" },
}

local function MenuEntries(win)
	local entries = { { title = L.MENU_DISPLAY } }
	for _, m in ipairs(FM.MODES) do
		entries[#entries + 1] = { text = FM.MODE_INFO[m].label, checked = function() return win.cfg.mode == m and not IsDps(win) end,
			func = function() SelectMode(win, m); Refresh() end }
		if m == "damage" then
			entries[#entries + 1] = { text = L.MENU_DPS, checked = function() return IsDps(win) end,
				func = function() SelectMode(win, "damage"); win.cfg.columns = { perSecond = true }; Refresh() end }
		end
	end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { title = L.MENU_SESSION }
	entries[#entries + 1] = { text = L.SESSION_CURRENT, checked = function() return win.cfg.view == "current" end, func = function() SelectView(win, "current"); Refresh() end }
	entries[#entries + 1] = { text = L.SESSION_OVERALL, checked = function() return win.cfg.view == "overall" end, func = function() SelectView(win, "overall"); Refresh() end }
	for _, s in ipairs(AvailableSessions()) do
		local id = s.sessionID
		entries[#entries + 1] = { text = s.name, checked = function() return win.cfg.view == id end, func = function() SelectView(win, id); Refresh() end }
	end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { title = L.MENU_WINDOWS }
	entries[#entries + 1] = { text = L.MENU_LOCK, checkbox = true, checked = function() return win.cfg.locked == true end, func = function() win.cfg.locked = not win.cfg.locked; win.UpdateLock() end }
	if #db.windows < FM.MAX_WINDOWS then
		entries[#entries + 1] = { text = L.MENU_NEW_WINDOW, func = function() AddWindow(win) end }
	end
	if #db.windows > 1 then entries[#entries + 1] = { text = L.MENU_CLOSE_WINDOW, func = function() CloseWindow(win) end } end
	-- Affichage de cette fenêtre seule : vrai ou nil (absent de la sauvegarde).
	-- Sans titre, Réduire n'aurait aucun effet visible (Minimized l'ignore) : la case est retirée.
	for _, o in ipairs(WINDOW_FLAGS) do if o.key ~= "minimized" or not win.cfg.noHeader then
		entries[#entries + 1] = { text = L[o.label], checkbox = true, checked = function() return win.cfg[o.key] == true end,
			func = function()
				if o.key == "minimized" then ToggleMinimized(win); return end
				win.cfg[o.key] = not win.cfg[o.key] or nil; Layout(); Refresh()
			end }
	end end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { title = L.OPT_COLUMNS }
	-- Première case cochée : la fenêtre prend sa propre copie du réglage commun.
	for _, o in ipairs(COLUMN_CHOICES) do
		entries[#entries + 1] = { text = L[o.label], checkbox = true, checked = function() return Columns(win)[o.key] == true end,
			func = function()
				if not win.cfg.columns then
					win.cfg.columns = {}
					for k, v in pairs(db.columns) do win.cfg.columns[k] = v end
				end
				win.cfg.columns[o.key] = not win.cfg.columns[o.key]
				Refresh()
			end }
	end
	if win.cfg.mode == "enemytaken" then
		entries[#entries + 1] = { divider = true }
		entries[#entries + 1] = { title = L.MENU_FILTER }
		for _, o in ipairs(FILTER_CHOICES) do
			entries[#entries + 1] = { text = L[o.label], checked = function() return win.cfg.filter == o.key end,
				func = function() win.cfg.filter = o.key; win.scrollOffset = 0; Refresh() end }
		end
	end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { title = L.MENU_BAR_COLOR }
	entries[#entries + 1] = { text = L.MENU_CLASS_COLOR, checked = function() return win.cfg.barColor == nil end,
		func = function() win.cfg.barColor = nil; Refresh() end }
	if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
		entries[#entries + 1] = { text = L.MENU_PICK_COLOR, checked = function() return win.cfg.barColor ~= nil end,
			func = function() PickBarColor(win) end }
	end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { text = L.MENU_COPY, func = function() CopyWindow(win) end }
	entries[#entries + 1] = { text = L.MENU_OPTIONS, func = function() OpenOptions() end }
	entries[#entries + 1] = { text = L.MENU_RESET, func = ResetData }
	return entries
end

local legacyDropDown = EasyMenu and CreateFrame("Frame", "ForeverMeterDropDown", UIParent, "UIDropDownMenuTemplate")
if legacyDropDown then legacyDropDown:Hide() end

-- Affiche des entrées neutres en menu déroulant sous `owner`. Faux si le client n'a aucune API de menu ;
-- sinon vrai et le menu ouvert (MenuUtil seulement, nil possible).
local function ShowEntries(entries, owner)
	if MenuUtil and MenuUtil.CreateContextMenu then
		return true, MenuUtil.CreateContextMenu(owner, function(_, root)
			-- Longues listes (médias LibSharedMedia) : défilement plutôt qu'un menu plus haut que l'écran.
			if #entries > 20 and root.SetScrollMode then root:SetScrollMode(400) end
			for _, e in ipairs(entries) do
				if e.title then root:CreateTitle(e.title)
				elseif e.divider then root:CreateDivider()
				elseif e.checkbox then root:CreateCheckbox(e.text, e.checked, e.func)
				elseif e.checked then root:CreateRadio(e.text, e.checked, e.func)
				else root:CreateButton(e.text, e.func) end
			end
		end)
	elseif legacyDropDown then
		local list = {}
		for _, e in ipairs(entries) do
			if e.title then list[#list + 1] = { text = e.title, isTitle = true, notCheckable = true }
			elseif e.divider then list[#list + 1] = { text = "", disabled = true, notCheckable = true }
			else list[#list + 1] = { text = e.text, checked = e.checked, func = e.func, notCheckable = e.checked == nil, isNotRadio = e.checkbox, keepShownOnClick = e.checkbox } end
		end
		EasyMenu(list, legacyDropDown, owner, 0, 0, "MENU")
	else
		return false
	end
	return true
end

-- Le menu se ferme au mouse-down global (Blizzard_Menu/Menu.lua:52-71), avant OnClick : sans garde, un re-clic
-- sur l'owner le rouvrait. Ni HandlesGlobalMouseEvent ni callback de fermeture : Blizzard les appelle sans
-- securecall, et la fermeture des menus tournerait teintée. L'état ouvert est relevé à chaque image ; le mouse-down
-- lit celui de l'image précédente, quel que soit l'ordre avec le gestionnaire de Blizzard.
-- Pool de frames : le proxy peut servir à un autre menu, d'où GetOwnerRegion.
local function MenuOpenFrom(owner)
	local menu = owner.fmMenu
	return menu ~= nil and menu:IsShown() and menu:GetOwnerRegion() == owner
end
local menuWatch = CreateFrame("Frame", "ForeverMeterMenuWatch")
menuWatch:Hide()
menuWatch:SetScript("OnUpdate", function(self)
	self.open = MenuOpenFrom(self.owner)
	if not self.open then self:Hide() end
end)
menuWatch:RegisterEvent("GLOBAL_MOUSE_DOWN")
menuWatch:SetScript("OnEvent", function(self, _, button)
	local owner = self.owner
	if owner then owner.fmSkipClick = self.open and button == owner.fmMenuButton and owner:IsMouseOver() end
end)

local function OpenMenu(win, owner, button)
	if owner.fmSkipClick then owner.fmSkipClick = nil; return end -- ce clic vient de fermer le menu
	local shown, menu = ShowEntries(MenuEntries(win), owner)
	if not shown then
		CycleMode(win, 1)
		Refresh()
		return
	end
	if menuWatch.owner then menuWatch.owner.fmSkipClick = nil end
	owner.fmMenu, owner.fmMenuButton = menu, button
	menuWatch.owner, menuWatch.open = owner, menu ~= nil
	menuWatch:SetShown(menu ~= nil)
end

local function MakeHeaderButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, 14)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	b:SetBackdropColor(0.25, 0.25, 0.25, 0.9)
	b:SetBackdropBorderColor(0, 0, 0, 1)
	b:SetNormalFontObject("GameFontHighlightSmall")
	b:SetHighlightFontObject("GameFontNormalSmall")
	b:SetText(text)
	return b
end

-- Fenêtre de compteur n° i : titre (clic gauche = mode suivant, clic droit = menu), boutons Menu et Reset,
-- molette = défilement, survol d'une barre = tooltip, clic = détail par sort.
local function NewWindow(i)
	local f = MakeWindow(i == 1 and "ForeverMeterFrame" or ("ForeverMeterFrame" .. i), DEFAULTS.width, 100)
	f.index = i
	f.scrollOffset = 0
	f.resetButton = MakeHeaderButton(f.header, L.BTN_RESET, 38)
	f.resetButton:SetPoint("RIGHT", -2, 0)
	f.resetButton:SetScript("OnClick", ResetData)
	f.menuButton = MakeHeaderButton(f.header, L.BTN_MENU, 44)
	f.menuButton:SetPoint("RIGHT", f.resetButton, "LEFT", -2, 0)
	f.menuButton:SetScript("OnClick", function(self, button) OpenMenu(f, self, button) end)
	-- Cadenas : verrou de position et de taille de cette fenêtre seule.
	f.lockButton = CreateFrame("Button", nil, f.header)
	f.lockButton:SetSize(14, 14)
	f.lockButton:SetPoint("RIGHT", f.menuButton, "LEFT", -2, 0)
	f.UpdateLock = function()
		local locked = f.cfg.locked == true
		f.lockButton:SetNormalTexture(locked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
		f.lockButton:GetNormalTexture():SetTexCoord(0.2, 0.8, 0.2, 0.8)
		f.lockButton:SetAlpha(locked and 1 or 0.5)
	end
	f.lockButton:SetScript("OnClick", function()
		f.cfg.locked = not f.cfg.locked
		f.UpdateLock()
	end)
	f.optionsButton = CreateFrame("Button", nil, f.header)
	f.optionsButton:SetSize(14, 14)
	f.optionsButton:SetPoint("RIGHT", f.lockButton, "LEFT", -2, 0)
	f.optionsButton:SetNormalTexture("Interface\\WorldMap\\GEAR_64GREY")
	f.optionsButton:SetHighlightTexture("Interface\\WorldMap\\GEAR_64GREY", "ADD")
	f.optionsButton:SetScript("OnClick", function() OpenOptions() end)
	f.optionsButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.MENU_OPTIONS)
		GameTooltip:Show()
	end)
	f.optionsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- Réduire / agrandir (cfg.minimized) : texture posée par LayoutWindow selon l'état.
	f.minimizeButton = CreateFrame("Button", nil, f.header)
	f.minimizeButton:SetSize(14, 14)
	f.minimizeButton:SetPoint("RIGHT", f.optionsButton, "LEFT", -2, 0)
	f.minimizeButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
	f.minimizeButton:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	f.minimizeButton:SetScript("OnClick", function() ToggleMinimized(f) end)
	f.minimizeButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.MENU_MINIMIZE)
		GameTooltip:Show()
	end)
	f.minimizeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.title:SetPoint("RIGHT", f.minimizeButton, "LEFT", -4, 0)
	-- Gros chiffre (cfg.bigNumber) : sa propre valeur, sans barres, en bas de la fenêtre.
	f.big = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.big:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")
	f.big:SetPoint("BOTTOMLEFT", 4, 0)
	f.big:SetPoint("BOTTOMRIGHT", -4, 0)
	f.big:SetHeight(BIG_NUMBER_HEIGHT)
	f.big:SetWordWrap(false)
	f.big:Hide()
	-- Sans titre (cfg.noHeader) : clic droit sur la fenêtre ou une barre pour le menu.
	f:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then OpenMenu(f, self, button) end
	end)
	f.OnMoved = function()
		local point, _, relPoint, x, y = f:GetPoint()
		f.cfg.point = { point, nil, relPoint, x, y }
	end
	-- Déplacer une fenêtre collée la décroche ; la relâcher contre une autre la colle.
	f.header:SetScript("OnDragStart", function()
		if f.cfg.locked then return end
		f.cfg.anchor = nil
		f:StartMoving()
	end)
	f.header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		if f.cfg.locked then return end
		f:SetUserPlaced(false)
		f.OnMoved()
		TrySnap(f)
		Layout()
	end)
	f.header:SetScript("OnClick", function(self, button)
		if button == "RightButton" then OpenMenu(f, self, button) else CycleMode(f, 1); Refresh() end
	end)
	-- Molette sur le titre : mode suivant vers le bas, précédent vers le haut.
	f.header:EnableMouseWheel(true)
	f.header:SetScript("OnMouseWheel", function(_, delta)
		CycleMode(f, delta < 0 and 1 or -1)
		Refresh()
	end)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		f.scrollOffset = math.max(0, f.scrollOffset - delta)
		Refresh()
	end)
	-- Poignées en bas à droite et en bas à gauche : glisser règle largeur et nombre de lignes de cette fenêtre seule.
	-- Redimensionnement à la main (OnUpdate + GetCursorPosition) entre OnDragStart et OnDragStop : sur ce client,
	-- StartSizing ne déclenche ni OnSizeChanged ni OnMouseUp, et IsMouseButtonDown répond « relâché » pendant le
	-- glissement ; seuls les événements de drag (ceux du titre) sont fiables.
	-- Taille (largeur, hauteur en px) -> largeur et lignes de cette fenêtre.
	local function SizeToConfig(w, h)
		return FM.Clamp("width", w + 0.5), FM.Clamp("rows", (h - HeaderHeight(f.cfg) - 3) / (db.rowHeight + 1) + 0.5)
	end
	-- Relâchement : la taille suivie pendant le glissement est arrondie à un nombre entier de lignes.
	f.OnResized = function()
		Layout()
		Refresh()
	end
	-- fromLeft : poignée en bas à gauche, le coin haut-droit reste fixe ; sinon le coin haut-gauche.
	local function MakeGrip(fromLeft)
		local grip = CreateFrame("Button", nil, f)
		grip:SetSize(12, 12)
		grip:RegisterForDrag("LeftButton")
		grip:SetPoint(fromLeft and "BOTTOMLEFT" or "BOTTOMRIGHT", fromLeft and 1 or -1, 1)
		grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		if fromLeft then -- icône retournée : les stries pointent vers le coin bas-gauche
			grip:GetNormalTexture():SetTexCoord(1, 0, 0, 1)
			grip:GetHighlightTexture():SetTexCoord(1, 0, 0, 1)
		end
		local function StopSizing()
			if not f.sizing then return end
			f.sizing = nil
			grip:SetScript("OnUpdate", nil)
			f.OnMoved()
			f.OnResized()
		end
		-- À chaque image pendant le glissement : coin du bas sous le curseur, coin haut opposé fixe, barres replacées,
		-- taille enregistrée tout de suite (une déconnexion en plein glissement garde la dernière taille vue).
		local function FollowCursor()
			local x, y = GetCursorPosition()
			local scale = f:GetEffectiveScale()
			local w = fromLeft and f:GetRight() - x / scale or x / scale - f:GetLeft()
			w = math.max(FM.BOUNDS.width.min, math.min(FM.BOUNDS.width.max, w))
			-- Gros chiffre ou « ma barre seulement » : hauteur fixe, seule la largeur suit le curseur.
			local fixed = f.cfg.bigNumber or f.cfg.onlyMe
			local h = fixed and WindowHeight(ShownRows(f), f.cfg) or math.max(WindowHeight(1, f.cfg), math.min(WindowHeight(FM.BOUNDS.rows.max, f.cfg), f:GetTop() - y / scale))
			local rows
			f.cfg.width, rows = SizeToConfig(w, h)
			if not fixed then f.cfg.rows = rows end
			f:SetSize(w, h)
			LayoutBars(f, ShownRows(f), w)
			Refresh()
		end
		grip:SetScript("OnDragStart", function()
			if f.cfg.locked then return end
			f.sizing = true
			-- Coin haut fixé en absolu : l'ancre CENTER enregistrée ferait bouger la fenêtre en grandissant.
			local left, right, top = f:GetLeft(), f:GetRight(), f:GetTop()
			f:ClearAllPoints()
			if fromLeft then
				f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
			else
				f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			end
			grip:SetScript("OnUpdate", FollowCursor)
		end)
		grip:SetScript("OnDragStop", StopSizing)
		return grip
	end
	f.grip = MakeGrip(false)
	f.gripLeft = MakeGrip(true)
	for b = 1, 40 do
		local bar = MakeBar(f, b)
		bar.win = f
		bar:SetScript("OnMouseUp", function(self, button)
			if button == "RightButton" and f.cfg.noHeader then OpenMenu(f, self, button) else BarClick(self) end
		end)
		bar:SetScript("OnEnter", ShowTooltip)
		bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	windows[i] = f
	return f
end

-- Aligne les frames sur db.windows : crée les manquantes, ré-attache les configs, cache le surplus.
EnsureWindows = function()
	for i = 1, #db.windows do
		local f = windows[i] or NewWindow(i)
		f.cfg = db.windows[i]
		f.scrollOffset, f.selectedGuid, f.selectedName = 0, nil, nil
		f.UpdateLock()
		f:Show()
	end
	for i = #db.windows + 1, #windows do windows[i]:Hide() end
	detail.owner = nil
	detail:Hide()
end

local function ToggleWindows()
	local shown = windows[1]:IsShown()
	for i = 1, #db.windows do windows[i]:SetShown(not shown) end
	if shown then detail:Hide() end
end
_G.ForeverMeter_Toggle = ToggleWindows -- AddonCompartmentFunc (.toc) et Bindings.xml
-- Raccourcis clavier (Bindings.xml) : comme /fm reset et un clic sur le titre de la première fenêtre.
_G.ForeverMeter_Reset = function() ResetData(); Print(L.MSG_RESET) end
_G.ForeverMeter_NextMode = function() CycleMode(windows[1], 1); Refresh() end

-- Affichage automatique (db.autoHide) : visible en combat ou en groupe, masqué 10 s après la fin du combat en solo.
-- Hors instance (db.instanceOnly) : masquées tout de suite, quel que soit autoHide. Sans autoHide, réaffichées à
-- l'entrée seulement si cette règle les a masquées : un masquage par /fm toggle tient en instance. Mode test : rien.
local autoHideIn, hiddenOutside
local function AutoShow(inCombat)
	if testMode then autoHideIn = nil; return end
	if db.instanceOnly and not IsInInstance() then
		autoHideIn, hiddenOutside = nil, true
		for i = 1, #db.windows do windows[i]:Hide() end
		detail:Hide()
		return
	end
	if not db.autoHide then
		autoHideIn = nil
		if hiddenOutside then for i = 1, #db.windows do windows[i]:Show() end end
		hiddenOutside = nil
		return
	end
	hiddenOutside = nil
	if inCombat or IsInGroup() then
		autoHideIn = nil
		for i = 1, #db.windows do windows[i]:Show() end
	else
		autoHideIn = autoHideIn or 10
	end
end
-- Après un changement de réglage (panneau, commande, import) : sans masquage automatique, tout réapparaît.
local function ApplyVisibility()
	if db.autoHide or db.instanceOnly then AutoShow(UnitAffectingCombat("player")) else for i = 1, #db.windows do windows[i]:Show() end end
end

-- Remise à zéro automatique (db.autoReset) : entrée dans une autre instance que la dernière, ou passage de solo à groupe.
-- La dernière instance est gardée en sortant : revenir après une mort ne remet pas à zéro. Connexion et /reload ne
-- font que relever l'état.
local lastInstanceID, wasInGroup
local function AutoReset(onlyRecord)
	if wasInGroup == nil then onlyRecord = true end -- premier appel, quel que soit l'événement : relevé seul
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	local newInstance = instanceType ~= "none" and instanceID ~= lastInstanceID
	local joinedGroup = IsInGroup() and wasInGroup == false
	if instanceType ~= "none" then lastInstanceID = instanceID end
	wasInGroup = IsInGroup()
	if onlyRecord or not db.autoReset or not (newInstance or joinedGroup) then return end
	ResetData()
	Print(L.MSG_RESET)
end

-- Applique la langue choisie (db.locale, sinon celle du client) et met à jour les textes déjà posés.
local function ApplyLanguage()
	local code = FM.ApplyLocale(db.locale or GetLocale())
	for _, f in ipairs(windows) do
		f.resetButton:SetText(L.BTN_RESET)
		f.menuButton:SetText(L.BTN_MENU)
	end
	-- Libellés de l'écran des raccourcis, lus à son ouverture.
	BINDING_HEADER_FOREVERMETER = "ForeverMeter"
	BINDING_NAME_FOREVERMETER_TOGGLE = L.BINDING_TOGGLE
	BINDING_NAME_FOREVERMETER_RESET = L.BINDING_RESET
	BINDING_NAME_FOREVERMETER_NEXT_MODE = L.BINDING_NEXT_MODE
	return code
end

-- Valeurs par défaut, migration de l'ancien format (db.mode, db.point) vers db.windows, nettoyage.
local function InitDb()
	for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
	-- Colonnes : table propre à db (jamais celle de DEFAULTS, que les cases à cocher modifieraient), clés manquantes à vrai.
	if db.columns == DEFAULTS.columns then db.columns = {} end
	for k, v in pairs(DEFAULTS.columns) do if db.columns[k] == nil then db.columns[k] = v end end
	if not db.windows or not db.windows[1] then
		db.windows = { { mode = db.mode or "damage", view = "current", point = db.point } }
	end
	if db.locked ~= nil then
		for _, c in ipairs(db.windows) do c.locked = db.locked or nil end
		db.locked = nil
	end
	db.mode = nil
	for i = #db.windows, FM.MAX_WINDOWS + 1, -1 do db.windows[i] = nil end
	for _, c in ipairs(db.windows) do
		if not FM.MODE_INFO[c.mode] then c.mode = "damage" end
		if c.view ~= "overall" then c.view = "current" end -- un sessionID ne survit pas au rechargement
		c.point = c.point or DEFAULTS.point
	end
	if db.locale and not FM.FindLocale(db.locale) then db.locale = nil end
	db.forbidden = forbiddenLog
end

------------------------------------------------------------------------
-- Événements
------------------------------------------------------------------------
local events = CreateFrame("Frame")
local elapsedSince = 0
events:SetScript("OnUpdate", function(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if fontRetryIn then
		fontRetryIn = fontRetryIn - elapsed
		if fontRetryIn <= 0 then
			fontRetryIn = nil
			Layout()
			elapsedSince = db.refresh -- Refresh() juste en dessous réécrit les textes vidés par Layout()
			needsRedraw = true
		end
	end
	if autoHideIn then
		autoHideIn = autoHideIn - elapsed
		if autoHideIn <= 0 then
			autoHideIn = nil
			if db.autoHide then
				for i = 1, #db.windows do windows[i]:Hide() end
				detail:Hide()
			end
		end
	end
	if not db or elapsedSince < db.refresh then return end
	-- Compteur redessiné sur événement seulement, comme celui de Blizzard : relu en continu, le /s du client
	-- baisse après la mort de la cible (total divisé par une durée qui court jusqu'à la fin du combat).
	-- La menace suit la cible, elle est redessinée tant qu'une fenêtre de menace est visible.
	elapsedSince = 0
	if needsRedraw or GetTime() < pollUntil then
		Refresh()
		return
	end
	for i = 1, #db.windows do
		local win = windows[i]
		if win:IsShown() and win.cfg.mode == "threat" then RenderThreat(win) end
	end
end)

Register(events, "ADDON_LOADED")
Register(events, "PLAYER_ENTERING_WORLD")
Register(events, "ZONE_CHANGED_NEW_AREA")
Register(events, "GROUP_ROSTER_UPDATE")
Register(events, "PLAYER_REGEN_ENABLED")
Register(events, "PLAYER_REGEN_DISABLED")
Register(events, "DAMAGE_METER_CURRENT_SESSION_UPDATED")
Register(events, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
Register(events, "DAMAGE_METER_RESET")
Register(events, "ADDON_RESTRICTION_STATE_CHANGED") -- montants lisibles à nouveau : redessin
Register(events, "PLAYER_LEVEL_CHANGED")            -- disponibilité du compteur réévaluée
Register(events, "PLAYER_TARGET_CHANGED")
-- DAMAGE_METER_SESSION_EXPIRED n'existe pas sur WoW Forever 1.60 : non enregistré.
events:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		-- WoW Forever ne relit pas la SavedVariables de compte : Mirror.lua fournit les replis.
		ForeverMeterDB = NS.Mirror:Load(ForeverMeterDB) or {}
		db = ForeverMeterDB
		InitDb()
		NS.Mirror.IGNORE.forbidden = true   -- journal de diagnostic, recréé à chaque session
		NS.Mirror:Watch(db, DEFAULTS)
		EnsureWindows()
		ApplyLanguage()
		Layout()
		Refresh()
	elseif not db then
		return
	elseif event == "PLAYER_TARGET_CHANGED" then
		wipe(threatSamples) -- échantillons de l'ancienne cible : sinon faux débit au premier tour sur la nouvelle
		warnedGuid = nil    -- alerte sonore rejouée sur la nouvelle cible
		needsRedraw = true
	elseif event == "GROUP_ROSTER_UPDATE" then
		wipe(threatSamples)
		groupUnits = nil
		AutoReset()
		AutoShow(UnitAffectingCombat("player"))
	elseif event == "PLAYER_REGEN_DISABLED" then
		AutoShow(true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		warnedGuid = nil
		pollUntil = GetTime() + 3 -- les montants peuvent rester secrets un court instant après le combat
		AutoShow(false)
		Refresh()
		if openOptionsAfterCombat then
			openOptionsAfterCombat = false
			OpenOptions()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		groupUnits = nil
		AutoReset(arg1 or arg2) -- isInitialLogin, isReloadingUi
		AutoShow(UnitAffectingCombat("player"))
		Refresh()
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		AutoShow(UnitAffectingCombat("player")) -- changement de zone sans écran de chargement
	elseif event == "DAMAGE_METER_RESET" then
		for i = 1, #db.windows do
			local win = windows[i]
			if type(win.cfg.view) == "number" then win.cfg.view = "current" end
			win.selectedGuid, win.compareGuid = nil, nil
		end
		Refresh()
	else
		needsRedraw = true -- DAMAGE_METER_*_UPDATED : très fréquents en combat, redessinés par l'OnUpdate
	end
end)

------------------------------------------------------------------------
-- Commandes : /fm (mode, report et debug agissent sur la première fenêtre)
------------------------------------------------------------------------
-- Ligne de report : canal demandé (/fm report ... guild), sinon groupe d'instance, raid, groupe, ou say en
-- instance. SAY est interdit aux addons hors instance (ADDON_ACTION_FORBIDDEN) : on affiche alors en local.
-- Message secret (nom de session d'une créature en instance, joueur sous restriction de carte) : SendChatMessage
-- le refuse, la ligne est affichée en local.
local function ChatSend(msg, channel, target)
	if not channel then
		-- Groupe de recherche : PARTY et RAID visent le groupe d'origine, INSTANCE_CHAT le groupe d'instance.
		local instanceGroup = LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
		channel = instanceGroup and "INSTANCE_CHAT" or (IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or (IsInInstance() and "SAY" or nil)))
	elseif channel == "SAY" and not IsInInstance() then
		channel = nil
	end
	if channel and not issecretvalue(msg) then
		(C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage)(msg, channel, nil, target)
	else
		Print(msg)
	end
end

-- Un report entier : une seule ligne secrète et le chat la refuserait, le canal recevrait un report tronqué.
-- Tout reste alors en local.
local function SendLines(messages, channel, target)
	local send = ChatSend
	for _, msg in ipairs(messages) do if issecretvalue(msg) then send = Print end end
	for _, msg in ipairs(messages) do send(msg, channel, target) end
end

ReportDeath = function(src, channel, target)
	local events, message = RecapEvents(src.deathRecapID)
	if not events then Print(message); return end
	-- Lignes du chat sans les noms de créature secrets. Un message encore secret (nom du mort, sort) : le chat
	-- le refuserait et le groupe recevrait un récap tronqué, tout reste donc en local.
	local messages = { string.format(L.REPORT_DEATH_HEADER, src.name) }
	for _, line in ipairs(FM.RecapLines(events, GetSpellNameCompat, nil, true)) do messages[#messages + 1] = line.left .. "  " .. line.right end
	SendLines(messages, channel, target)
end

local function Report(win, count, channel, target)
	local lines, err = ReportLines(win, count)
	if not lines then Print(err); return end
	SendLines(lines, channel, target)
end

-- Report des sorts de la source ouverte dans le panneau de détail : clic droit sur son titre.
local function ReportDetail(count)
	local win = detail.owner
	if not win or not win.selectedGuid or not DamageMeter then return end
	local source = ReadSource(win, win.selectedGuid)
	local spells, secret = SortedSpells(source)
	if not spells[1] then Print(L.REPORT_NOTHING); return end
	if secret then Print(L.REPORT_OUT_OF_COMBAT); return end
	local session = ReadSession(win)
	local label, sessionLabel = FM.MODE_INFO[win.cfg.mode].label, SessionLabel(win, session)
	-- Comparaison ouverte : les mêmes lignes que le panneau, « 12.3k | 9.8k (+26%) ».
	local other, otherSecret
	if win.compareGuid then other, otherSecret = SortedSpells(ReadSource(win, win.compareGuid)) end
	if other and not otherSecret then
		local rows = FM.CompareSpells(spells, other)
		local lines = { string.format(L.REPORT_DETAIL_HEADER, (win.selectedName or "?") .. " vs " .. (win.compareName or "?"), label, sessionLabel) }
		for i = 1, math.min(count, #rows) do
			local r = rows[i]
			lines[#lines + 1] = string.format("%d. %s  %s", i, SpellLabel(win, r, true), FM.FormatCompare(r.a, r.b))
		end
		SendLines(lines)
		return
	end
	local lines = { string.format(L.REPORT_DETAIL_HEADER, win.selectedName or "?", label, sessionLabel) }
	for i = 1, math.min(count, #spells) do
		local s = spells[i]
		lines[#lines + 1] = string.format("%d. %s  %s", i, SpellLabel(win, s, true), FM.FormatRow(s.totalAmount, PerSecond(win, s, session, false), source.totalAmount, false, Columns(win)))
	end
	SendLines(lines)
end

detail.header:SetScript("OnClick", function(_, button)
	if button == "RightButton" then ReportDetail(5) end
end)

-- Diagnostic (/fm debug) : valeurs brutes de C_DamageMeter pour le mode et la session de la première fenêtre.
-- Texte technique, volontairement non traduit. %.3f garde les décimales ; string.format accepte les valeurs secrètes.
local function Raw(v)
	if v == nil then return "nil" end
	if type(v) ~= "number" then return tostring(v) end
	if issecretvalue(v) then return "(secret)" end
	return string.format("%.3f", v)
end

local function Keys(t)
	local list = {}
	for k in pairs(t or {}) do list[#list + 1] = tostring(k) end
	table.sort(list)
	return table.concat(list, ", ")
end

local function Debug(win)
	local session = ReadSession(win)
	local view = win.cfg.view
	Print(string.format("debug : mode=%s type=%s vue=%s combat=%s fenetres=%d", win.cfg.mode, tostring(MeterType(win)),
		tostring(view), tostring(UnitAffectingCombat("player") and true or false), #db.windows))
	if not session then Print("debug : session nil"); return end
	Print("debug : session.durationSeconds=" .. Raw(session.durationSeconds) .. " totalAmount=" .. Raw(session.totalAmount))
	if DamageMeter.GetSessionDurationSeconds and (view == "overall" or view == "current") then
		Print("debug : GetSessionDurationSeconds=" .. Raw(DamageMeter.GetSessionDurationSeconds(view == "overall" and FM.SESSION_OVERALL or FM.SESSION_CURRENT)))
	end
	Print("debug : champs session = " .. Keys(session))
	for _, src in ipairs(session.combatSources or {}) do
		if src.isLocalPlayer then
			Print("debug : joueur totalAmount=" .. Raw(src.totalAmount) .. " amountPerSecond=" .. Raw(src.amountPerSecond)
				.. " specIconID=" .. Raw(src.specIconID) .. " deathRecapID=" .. Raw(src.deathRecapID))
			Print("debug : champs source = " .. Keys(src))
			return
		end
	end
	Print("debug : joueur absent de la session")
end

local function ResetSettings()
	wipe(db)
	InitDb()
	EnsureWindows()
	ApplyLanguage()
end

-- Panneau d'options (construit plus bas) : relu à l'affichage et après un import.
local refreshers = {}   -- relisent db et L à chaque affichage du panneau (réglages changés par /fm, langue)
local refreshing = false

local function RefreshOptions()
	refreshing = true
	for _, r in ipairs(refreshers) do r() end
	refreshing = false
end

-- Export : réglages sérialisés (format du miroir), sans le journal de diagnostic.
local function ExportSettings()
	local copy = {}
	for k, v in pairs(db) do if k ~= "forbidden" then copy[k] = v end end
	ShowTextWindow(NS.Mirror.Serialize(copy), L.COPY_HINT, nil)
end

-- Import d'une chaîne collée par n'importe qui : taille bornée, aucune exécution, tout validé avant d'appliquer.
-- pcall : une clé numérique « nan » ferait lever l'affectation dans Deserialize.
local function ImportSettings(text)
	-- Trim par indices : un motif « ^%s*(.-)%s*$ » serait quadratique sur une longue chaîne d'espaces.
	text = text or ""
	local first = text:find("%S")
	text = first and text:sub(first, text:match(".*()%S")) or ""
	local ok, parsed = false, nil
	if #text <= NS.Mirror.SLOTS * NS.Mirror.CHUNK then ok, parsed = pcall(NS.Mirror.Deserialize, text) end
	local clean, bad = nil, "?"
	if ok and parsed then clean, bad = FM.ValidateSettings(parsed) end
	-- bad vient de la chaîne collée : codes « | » neutralisés et longueur bornée avant affichage.
	if not clean then Print(string.format(L.MSG_IMPORT_INVALID, (tostring(bad or "?"):gsub("|", "||"):sub(1, 60)))); return end
	wipe(db)
	for k, v in pairs(clean) do db[k] = v end
	InitDb()
	EnsureWindows()
	ApplyLanguage()
	Layout()
	Refresh()
	-- Même effet que la case « masquer hors combat » du panneau.
	ApplyVisibility()
	RefreshOptions()
	NS.Mirror:Flush()
	copyFrame:Hide()
	Print(L.MSG_IMPORTED)
end

local function OpenImport() ShowTextWindow("", L.IMPORT_HINT, ImportSettings) end

-- Nombre de fenêtres, borné ; retirées par la fin.
local function SetWindowCount(n)
	n = FM.Clamp("windows", n)
	while #db.windows < n do AddWindow() end
	while #db.windows > n do RemoveWindow(#db.windows) end
	EnsureWindows()
end

-- Lignes ou largeur communes : les tailles propres à chaque fenêtre s'effacent.
local function SetCommonSize(key, v)
	db[key] = FM.Clamp(key, v)
	for _, c in ipairs(db.windows) do c[key] = nil end
end

-- Liste du panneau et /fm theme. Le texte du bouton et de /fm theme suit CurrentTheme.
local function ApplyTheme(t)
	local keepFont = FM.CJK_LOCALES[GetLocale()]
	for _, k in ipairs(FM.THEME_KEYS) do
		if not (keepFont and k == "barFont") then db[k] = t[k] end
	end
end
local function CurrentTheme() return FM.CurrentTheme(db, FM.CJK_LOCALES[GetLocale()]) end

------------------------------------------------------------------------
-- Panneau d'options : Options > AddOns > ForeverMeter, /fm options, entrée du menu des fenêtres
------------------------------------------------------------------------
local optionsPanel, optionsCategory
local sliderCount = 0

local function ApplyOption()
	Layout()
	Refresh()
	RefreshOptions()
end

local function OptionLabel(parent, key, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	refreshers[#refreshers + 1] = function() fs:SetText(L[key]) end
end

-- Libellé + bouton qui ouvre la liste de choix. entries() construit la liste, current() le texte du bouton.
local function OptionChoice(parent, key, x, y, entries, current)
	OptionLabel(parent, key, x, y)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(200, 22)
	b:SetPoint("TOPLEFT", x, y - 16)
	b:SetScript("OnClick", function(self) ShowEntries(entries(), self) end)
	local function Paint() b:SetText(current()) end
	refreshers[#refreshers + 1] = Paint
	return Paint
end
local PaintThemeButton   -- repeint par les curseurs : taille de police, hauteur et opacité font passer à « Custom »

-- Cases du panneau, /fm autohide et /fm instanceonly : désactivé, les fenêtres masquées réapparaissent.
local function SetAutoHide(v)
	db.autoHide = v
	ApplyVisibility()
end
local function SetInstanceOnly(v)
	db.instanceOnly = v
	ApplyVisibility()
end

local function OptionSlider(parent, key, x, y, bound, get, set)
	local b = FM.BOUNDS[bound]
	local minValue, maxValue, step = b.min, b.max, b.step
	sliderCount = sliderCount + 1
	local name = "ForeverMeterOptionSlider" .. sliderCount
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", x + 4, y - 20)
	s:SetWidth(200)
	s:SetMinMaxValues(minValue, maxValue)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	if _G[name .. "Low"] then _G[name .. "Low"]:SetText(minValue) end
	if _G[name .. "High"] then _G[name .. "High"]:SetText(maxValue) end
	local text = _G[name .. "Text"]
	if not text then
		text = s:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		text:SetPoint("BOTTOM", s, "TOP", 0, 2)
	end
	local function Paint(v) text:SetText(string.format("%s : %g", L[key], v)) end
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		Paint(v)
		if not refreshing then set(v); Layout(); Refresh(); if PaintThemeButton then PaintThemeButton() end end
	end)
	-- SetValue ne déclenche rien si la valeur ne change pas : peindre explicitement.
	refreshers[#refreshers + 1] = function() s:SetValue(get()); Paint(get()) end
end

local function OptionCheck(parent, key, x, y, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x - 4, y)
	local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); ApplyOption() end)
	refreshers[#refreshers + 1] = function() text:SetText(L[key]); cb:SetChecked(get() and true or false) end
end

-- Entrées radio d'une liste de médias ; la police propose en tête celle du jeu (nil).
local function MediaEntries(kind, key)
	local entries = {}
	if kind == "font" then
		entries[1] = { text = L.OPT_DEFAULT, checked = function() return db[key] == nil end, func = function() db[key] = nil; ApplyOption() end }
	end
	for _, m in ipairs(FM.MediaList(kind)) do
		local name = m[1]
		entries[#entries + 1] = { text = name, checked = function() return db[key] == name end, func = function() db[key] = name; ApplyOption() end }
	end
	return entries
end

local function LanguageEntries()
	local entries = { { text = "auto (" .. GetLocale() .. ")", checked = function() return db.locale == nil end, func = function() db.locale = nil; ApplyLanguage(); ApplyOption() end } }
	for _, code in ipairs(FM.AvailableLocales()) do
		entries[#entries + 1] = { text = code, checked = function() return db.locale == code end, func = function() db.locale = code; ApplyLanguage(); ApplyOption() end }
	end
	return entries
end

local function ThemeEntries()
	local entries = {}
	for _, t in ipairs(FM.THEMES) do
		entries[#entries + 1] = { text = t.name, checked = function() return CurrentTheme() == t.name end, func = function() ApplyTheme(t); ApplyOption() end }
	end
	return entries
end

do
	local p = CreateFrame("Frame")
	p.name = "ForeverMeter"
	p:Hide()
	p:SetScript("OnShow", RefreshOptions)
	local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("ForeverMeter")
	local LEFT, RIGHT = 16, 300

	OptionChoice(p, "OPT_TEXTURE", LEFT, -56, function() return MediaEntries("statusbar", "barTexture") end, function() return db.barTexture end)
	OptionChoice(p, "OPT_FONT", LEFT, -106, function() return MediaEntries("font", "barFont") end, function() return db.barFont or L.OPT_DEFAULT end)
	OptionSlider(p, "OPT_FONT_SIZE", LEFT, -160, "fontSize", function() return db.fontSize or 10 end, function(v) db.fontSize = v end)
	OptionChoice(p, "OPT_LANG", LEFT, -226, LanguageEntries, function() return db.locale or ("auto (" .. GetLocale() .. ")") end)

	-- Au-dessus du curseur d'échelle, à hauteur du titre : seule place libre du panneau.
	PaintThemeButton = OptionChoice(p, "OPT_THEME", RIGHT, -12, ThemeEntries, function() return CurrentTheme() or L.OPT_THEME_CUSTOM end)
	OptionSlider(p, "OPT_SCALE", RIGHT, -56, "scale", function() return db.scale end, function(v) db.scale = v end)
	OptionSlider(p, "OPT_REFRESH", RIGHT, -116, "refresh", function() return db.refresh end, function(v) db.refresh = v end)
	OptionSlider(p, "OPT_WARN", RIGHT, -176, "warnPct", function() return db.warnPct end, function(v) db.warnPct = v end)
	OptionLabel(p, "OPT_COLUMNS", RIGHT, -236)
	OptionCheck(p, "OPT_COL_TOTAL", RIGHT, -256, function() return db.columns.total end, function(v) db.columns.total = v end)
	OptionCheck(p, "OPT_COL_PER_SECOND", RIGHT, -286, function() return db.columns.perSecond end, function(v) db.columns.perSecond = v end)
	OptionCheck(p, "OPT_COL_PERCENT", RIGHT, -316, function() return db.columns.percent end, function(v) db.columns.percent = v end)
	OptionSlider(p, "OPT_ROW_HEIGHT", RIGHT, -456, "rowHeight", function() return db.rowHeight end, function(v) db.rowHeight = v end)
	OptionSlider(p, "OPT_BG_ALPHA", RIGHT, -512, "bgAlpha", function() return db.bgAlpha end, function(v) db.bgAlpha = v end)
	OptionCheck(p, "OPT_INSTANCE_ONLY", RIGHT, -346, function() return db.instanceOnly end, SetInstanceOnly)
	-- Mêmes chemins que /fm windows, /fm rows et /fm width.
	OptionSlider(p, "OPT_WINDOWS", RIGHT, -400, "windows", function() return #db.windows end, SetWindowCount)
	OptionSlider(p, "OPT_ROWS", LEFT, -446, "rows", function() return db.rows end, function(v) SetCommonSize("rows", v) end)
	OptionSlider(p, "OPT_WIDTH", LEFT, -506, "width", function() return db.width end, function(v) SetCommonSize("width", v) end)

	-- Rangée de boutons du bas : le cadre des réglages (Blizzard_SettingsPanel.xml) offre environ 600 px de haut.
	local function PanelButton(key, x, y, onClick)
		local button = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		button:SetSize(200, 22)
		button:SetPoint("TOPLEFT", x, y)
		button:SetScript("OnClick", onClick)
		refreshers[#refreshers + 1] = function() button:SetText(L[key]) end
	end
	-- 200 px chacun : « Einstellungen exportieren » (deDE) déborde d'un bouton de 140. Bord droit à 636 sur ~665.
	PanelButton("OPT_DEFAULTS", LEFT, -566, function() ResetSettings(); ApplyOption() end)
	PanelButton("OPT_EXPORT", LEFT + 210, -566, ExportSettings)
	PanelButton("OPT_IMPORT", LEFT + 420, -566, OpenImport)

	OptionCheck(p, "OPT_SOUND", LEFT, -286, function() return db.warnSound end, function(v) db.warnSound = v end)
	OptionCheck(p, "OPT_PETS", LEFT, -316, function() return db.showPets end, function(v) db.showPets = v end)
	OptionCheck(p, "OPT_LOCK", LEFT, -346, function() return windows[1] and windows[1].cfg.locked end, function(v)
		for i = 1, #db.windows do windows[i].cfg.locked = v or nil; windows[i].UpdateLock() end
	end)
	OptionCheck(p, "OPT_AUTO_HIDE", LEFT, -376, function() return db.autoHide end, SetAutoHide)
	OptionCheck(p, "OPT_AUTO_RESET", LEFT, -406, function() return db.autoReset end, function(v) db.autoReset = v end)

	optionsPanel = p
	if Settings and Settings.RegisterCanvasLayoutCategory then
		optionsCategory = Settings.RegisterCanvasLayoutCategory(p, p.name)
		Settings.RegisterAddOnCategory(optionsCategory)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(p)
	end
end

-- C_SettingsUtil.OpenSettingsPanel est restreint : en combat, ouverture repoussée à PLAYER_REGEN_ENABLED.
OpenOptions = function()
	if InCombatLockdown() then
		openOptionsAfterCombat = true
		Print(L.OPTIONS_AFTER_COMBAT)
		return
	end
	if optionsCategory then
		Settings.OpenToCategory(optionsCategory:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(optionsPanel)
	end
end

SLASH_FOREVERMETER1 = "/fm"
SLASH_FOREVERMETER2 = "/forevermeter"
SlashCmdList.FOREVERMETER = function(input)
	local cmd, arg = input:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	local num = tonumber(arg)
	local first = windows[1]
	-- /fm mode <mode> [N] : fenêtre N, la première par défaut
	local modeName, modeWindow = arg:lower():match("^(%S+)%s*(%d*)$")
	modeWindow = tonumber(modeWindow) or 1
	if cmd == "lock" or cmd == "unlock" then
		for i = 1, #db.windows do windows[i].cfg.locked = cmd == "lock"; windows[i].UpdateLock() end
		Print(cmd == "lock" and L.MSG_LOCKED or L.MSG_UNLOCKED)
	elseif cmd == "toggle" then ToggleWindows()
	elseif cmd == "scale" and num then db.scale = FM.Clamp("scale", num)
	elseif cmd == "rows" and num then SetCommonSize("rows", num)
	elseif cmd == "width" and num then SetCommonSize("width", num)
	elseif cmd == "refresh" and num then db.refresh = FM.Clamp("refresh", num); Print(string.format(L.MSG_REFRESH, db.refresh))
	elseif cmd == "windows" and num then
		SetWindowCount(num)
		Print(string.format(L.MSG_WINDOWS, #db.windows))
	elseif cmd == "export" then ExportSettings(); return
	elseif cmd == "import" then OpenImport(); return
	elseif cmd == "mode" and modeName and FM.MODE_INFO[modeName] and windows[modeWindow] and modeWindow <= #db.windows then
		SelectMode(windows[modeWindow], modeName)
	elseif cmd == "report" and arg:lower():match("^death") then
		-- /fm report death [N] [canal] : recap de la mort affichée à la ligne N (1 par défaut) de la première fenêtre Morts.
		local count, channel, target = FM.ParseReport(arg:match("^%S+%s*(.-)$"))
		if count == false then Print(L.HELP_1:format(table.concat(FM.MODES, ", "))); return end
		local win
		for i = 1, #db.windows do if windows[i].cfg.mode == "deaths" then win = windows[i]; break end end
		local src = win and VisibleSources(win, ReadSession(win))[count or 1]
		if src then ReportDeath(src, channel, target) else Print(L.REPORT_NOTHING) end
		return
	elseif cmd == "report" then
		local count, channel, target = FM.ParseReport(arg)
		if count == false then Print(L.HELP_1:format(table.concat(FM.MODES, ", "))); return end
		Report(first, count or 5, channel, target)
		return
	elseif cmd == "rowheight" and num then db.rowHeight = FM.Clamp("rowHeight", num); Print(string.format("%s : %g", L.OPT_ROW_HEIGHT, db.rowHeight))
	elseif cmd == "bgalpha" and num then
		-- Même pas que le curseur du panneau
		db.bgAlpha = math.floor(FM.Clamp("bgAlpha", num) / FM.BOUNDS.bgAlpha.step + 0.5) * FM.BOUNDS.bgAlpha.step
		Print(string.format("%s : %g", L.OPT_BG_ALPHA, db.bgAlpha))
	elseif cmd == "autohide" then SetAutoHide(not db.autoHide); Print(L.OPT_AUTO_HIDE .. " : " .. (db.autoHide and L.WORD_ON or L.WORD_OFF))
	elseif cmd == "instanceonly" then SetInstanceOnly(not db.instanceOnly); Print(L.OPT_INSTANCE_ONLY .. " : " .. (db.instanceOnly and L.WORD_ON or L.WORD_OFF))
	elseif cmd == "autoreset" then db.autoReset = not db.autoReset; Print(L.OPT_AUTO_RESET .. " : " .. (db.autoReset and L.WORD_ON or L.WORD_OFF))
	elseif cmd == "debug" then
		local ok, err = pcall(Debug, first)
		if not ok then Print("debug : erreur " .. tostring(err)) end
		return
	elseif cmd == "reset" then
		ResetData()
		Print(L.MSG_RESET)
	elseif cmd == "warn" and num then db.warnPct = FM.Clamp("warnPct", num); Print(string.format(L.MSG_WARN, db.warnPct))
	elseif cmd == "sound" then db.warnSound = not db.warnSound; Print(string.format(L.MSG_SOUND, db.warnSound and L.WORD_ON or L.WORD_OFF))
	elseif cmd == "pets" then db.showPets = not db.showPets; Print(string.format(L.MSG_PETS, db.showPets and L.WORD_SHOWN or L.WORD_HIDDEN))
	elseif cmd == "test" then
		testMode = not testMode
		if testMode then for i = 1, #db.windows do windows[i]:Show() end else ApplyVisibility() end
		Print(string.format(L.MSG_TEST, testMode and L.WORD_ON or L.WORD_OFF))
	elseif cmd == "texture" then
		local list = FM.MediaList("statusbar")
		local name = FM.FindMedia(list, arg)
		if not name then
			Print(string.format(L.MSG_TEXTURE, db.barTexture))
			Print(string.format(L.MSG_TEXTURE_LIST, FM.MediaNames(list)))
			return
		end
		db.barTexture = name
		Print(string.format(L.MSG_TEXTURE, name))
	elseif cmd == "font" then
		-- /fm font <nom|default> [taille], ou /fm font <taille>. Les noms LibSharedMedia contiennent des espaces.
		local list = FM.MediaList("font")
		local word, size = arg, nil
		if not FM.FindMedia(list, arg) then
			word, size = arg:match("^(.-)%s*(%d+)$")
			if not word then word = arg end
		end
		local name = FM.FindMedia(list, word)
		size = tonumber(size)
		if (word ~= "" and word:lower() ~= "default" and not name) or (word == "" and not size) then
			Print(string.format(L.MSG_FONT, db.barFont or "default", db.fontSize or 10))
			Print(string.format(L.MSG_FONT_LIST, FM.MediaNames(list)))
			return
		end
		if word ~= "" then db.barFont = name end
		if size then db.fontSize = FM.Clamp("fontSize", size) end
		if word:lower() == "default" and not size then db.fontSize = nil end
		Print(string.format(L.MSG_FONT, db.barFont or "default", db.fontSize or 10))
	elseif cmd == "theme" then
		local t = FM.FindTheme(arg)
		if t then ApplyTheme(t) end
		Print(string.format(L.MSG_THEME, CurrentTheme() or L.OPT_THEME_CUSTOM))
		if not t then
			local names = {}
			for i, theme in ipairs(FM.THEMES) do names[i] = theme.name end
			Print(string.format(L.MSG_THEME_LIST, table.concat(names, ", ")))
			return
		end
	elseif cmd == "lang" then
		if arg == "" then
			Print(string.format(L.MSG_LANG, db.locale or ("auto (" .. GetLocale() .. ")")))
			Print(string.format(L.MSG_LANG_LIST, table.concat(FM.AvailableLocales(), ", ")))
			return
		end
		local code = FM.FindLocale(arg)
		if arg:lower() ~= "auto" and not code then
			Print(string.format(L.MSG_LANG_LIST, table.concat(FM.AvailableLocales(), ", ")))
			return
		end
		db.locale = code
		local applied = ApplyLanguage()
		Print(string.format(L.MSG_LANG, db.locale or ("auto (" .. applied .. ")")))
	elseif cmd == "defaults" then
		ResetSettings()
		Print(L.MSG_DEFAULTS)
	elseif cmd == "options" or cmd == "config" then OpenOptions(); return
	else
		-- Pas de "|" entre les modes : le chat lit "|h", "|a", "|t"... comme des codes d'échappement.
		Print(string.format(L.HELP_1, table.concat(FM.MODES, ", ")))
		Print(L.HELP_2)
		return
	end
	Layout()
	Refresh()
end
