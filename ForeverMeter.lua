-- ForeverMeter : compteur de dégâts, soins, dégâts subis et menace pour WoW Forever (client 1.60, moteur 12.x).
-- Un seul fichier, aucune dépendance (ni Details, ni Ace, ni LibStub).
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

-- Modes : clé -> { label, type Enum.DamageMeterType }. La menace n'est pas dans C_DamageMeter.
FM.MODES = { "damage", "heal", "absorbs", "taken", "interrupts", "dispels", "deaths", "threat" }
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
FM.SESSION_OVERALL, FM.SESSION_CURRENT = 0, 1
FM.MAX_WINDOWS = 4
FM.RECAP_LINES = 6

local LABEL_KEYS = {
	damage = "MODE_DAMAGE", heal = "MODE_HEAL", absorbs = "MODE_ABSORBS", taken = "MODE_TAKEN",
	interrupts = "MODE_INTERRUPTS", dispels = "MODE_DISPELS", deaths = "MODE_DEATHS", threat = "MODE_THREAT",
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
	for mode, key in pairs(LABEL_KEYS) do FM.MODE_INFO[mode].label = L[key] end
	return code
end

FM.ApplyLocale(GetLocale and GetLocale() or "enUS")

local DEFAULTS = {
	scale = 1,
	rows = 10,
	width = 260,
	rowHeight = 16,
	warnPct = 90,
	refresh = 0.2,                        -- secondes entre deux rafraîchissements (les événements C_DamageMeter rafraîchissent aussi)
	warnSound = true,
	showPets = true,
	locale = nil,                         -- nil = langue du client (GetLocale)
	point = { "CENTER", nil, "CENTER", 300, 0 }, -- position de la première fenêtre
}

------------------------------------------------------------------------
-- 1. Logique pure
------------------------------------------------------------------------

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

-- Ligne de droite d'une barre. `secret` vrai en combat : pas de comparaison ni d'arithmétique possible,
-- string.format reste permis et le résultat s'affiche tel quel.
function FM.FormatRow(total, perSecond, sessionTotal, secret)
	if secret then
		-- Pas de test possible sur une valeur secrète : une décimale toujours, sinon %d tronque 0.8 en 0.
		return string.format("%d (%.1f/s)", total, perSecond)
	end
	local pct = sessionTotal and sessionTotal > 0 and (total / sessionTotal * 100) or 0
	return string.format("%s (%s/s, %.1f%%)", FM.FormatValue(total), FM.FormatValue(perSecond), pct)
end

function FM.SortThreat(list)
	table.sort(list, function(a, b)
		if a.tanking ~= b.tanking then return a.tanking end
		if a.pct ~= b.pct then return a.pct > b.pct end
		return a.name < b.name
	end)
	return list
end

function FM.ShouldWarn(row, warnPct)
	return row ~= nil and not row.tanking and (row.pct or 0) >= warnPct
end

function FM.ComputeTps(previous, value, now)
	if not previous or now <= previous.t then return 0 end
	local tps = (value - previous.v) / (now - previous.t)
	return tps > 0 and tps or 0
end

-- Derniers événements d'un recap de mort (C_DeathRecap.GetRecapEvents), du plus ancien au plus récent.
-- Chaque ligne : { left = "-2.3s  Sort (source)", right = "-1.2k  35%" }. `spellName(id)` résout un ID de sort.
function FM.RecapLines(events, spellName, maxLines)
	local lines = {}
	if not events or #events == 0 then return lines end
	maxLines = maxLines or FM.RECAP_LINES
	local last = events[#events].timestamp or 0
	for i = math.max(1, #events - maxLines + 1), #events do
		local e = events[i]
		local name = e.spellName or (e.spellId and spellName and spellName(e.spellId)) or e.environmentalType or "?"
		if e.sourceName and e.sourceName ~= "" then name = name .. " (" .. e.sourceName .. ")" end
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
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local GetTime, PlaySound = GetTime, PlaySound
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local WARN_SOUND = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
local issecretvalue = issecretvalue or function() return false end
local DamageMeter = C_DamageMeter
local DeathRecap = C_DeathRecap

local db
local windows = {}                        -- frames ; windows[i].cfg == db.windows[i] = { mode, view, point }
local threatSamples = {}
local warnedGuid = nil                    -- partagé : deux fenêtres en mode menace ne jouent le son qu'une fois

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverMeter|r : " .. msg)
end

local function WindowHeight(rows)
	return 18 + (rows or db.rows) * (db.rowHeight + 1) + 3
end

-- Taille d'une fenêtre : la sienne (poignée de redimensionnement) sinon la taille commune (/fm rows, /fm width).
local function Rows(win) return win.cfg.rows or db.rows end
local function Width(win) return win.cfg.width or db.width end

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
		local d = session and session.durationSeconds
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

local function SelectMode(win, m) win.cfg.mode = m; win.scrollOffset = 0; win.selectedGuid = nil end
local function SelectView(win, v) win.cfg.view = v; win.scrollOffset = 0; win.selectedGuid = nil end

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
local function GroupUnits()
	if IsInRaid() then
		local units = {}
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
		return units
	end
	local units = { "player" }
	if IsInGroup() then
		for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
	end
	return units
end

local function PetUnit(unit)
	if unit == "player" then return "pet" end
	return (unit:gsub("^(%a+)(%d+)$", "%1pet%2"))
end

local function ThreatTarget()
	if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
		return "target"
	end
	return nil
end

local function CollectThreat(enemy)
	local list, now = {}, GetTime()
	for _, unit in ipairs(GroupUnits()) do
		local candidates = { unit }
		if db.showPets then candidates[2] = PetUnit(unit) end
		for _, u in ipairs(candidates) do
			if UnitExists(u) then
				local isTanking, status, pct, rawPct, value = UnitDetailedThreatSituation(u, enemy)
				if status then
					local guid = UnitGUID(u)
					local _, class = UnitClass(u)
					local tps = FM.ComputeTps(threatSamples[guid], value or 0, now)
					threatSamples[guid] = { v = value or 0, t = now }
					list[#list + 1] = {
						name = UnitName(u) or u, class = class, guid = guid,
						tanking = isTanking and true or false,
						pct = isTanking and 100 or (rawPct or pct or 0), -- rawPct est faux pour le tank
						value = value or 0, tps = tps, isPlayer = UnitIsUnit(u, "player"),
					}
				end
			end
		end
	end
	return FM.SortThreat(list)
end

------------------------------------------------------------------------
-- Fenêtres
------------------------------------------------------------------------
local function ClassColor(class)
	local c = not issecretvalue(class) and class and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

local function MakeWindow(name, w, h)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(w, h)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	-- Frame nommée : StopMovingOrSizing la marque « placée par l'utilisateur » et le client restaure alors sa
	-- taille depuis layout-local.txt après ADDON_LOADED, sans passer par Layout() : le cadre et les barres divergent.
	f:SetUserPlaced(false)
	f:EnableMouse(true)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f:SetBackdropColor(0, 0, 0, 0.6)
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
	f.bars = {}
	return f
end

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

-- Place les barres pour `rows` lignes et `width` px sans toucher à la taille de la frame.
local function LayoutBars(f, rows, width)
	f.rows = rows
	for i = 1, math.max(rows, #f.bars) do
		local bar = f.bars[i] or MakeBar(f, i)
		bar:SetSize(width - 6, db.rowHeight)
		bar.icon:SetSize(db.rowHeight - 2, db.rowHeight - 2)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", 3, -18 - (i - 1) * (db.rowHeight + 1))
		if i > rows then bar:Hide() end
	end
end

local function LayoutWindow(f, rows, width)
	f:SetScale(db.scale)
	f:SetWidth(width)
	f:SetHeight(WindowHeight(rows))
	LayoutBars(f, rows, width)
end

-- Fenêtre de détail par sort, unique, ancrée à la fenêtre qui l'a ouverte (detail.owner).
local detail = MakeWindow("ForeverMeterDetailFrame", DEFAULTS.width, 100)
detail:Hide()
-- Collée à sa fenêtre propriétaire et déplacée avec elle : pas de déplacement propre (il serait perdu au prochain ancrage).
detail:SetMovable(false)
detail.header:SetScript("OnDragStart", nil)
detail.header:SetScript("OnDragStop", nil)
detail.close = CreateFrame("Button", nil, detail.header, "UIPanelCloseButton")
detail.close:SetPoint("RIGHT", 2, 0)
detail.close:SetSize(20, 20)
detail.close:SetScript("OnClick", function()
	if detail.owner then detail.owner.selectedGuid = nil end
	detail:Hide()
end)

local function AnchorDetail()
	local owner = detail.owner or windows[1]
	LayoutWindow(detail, Rows(owner), Width(owner))
	detail:ClearAllPoints()
	detail:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
end

local ANCHOR_GAP = 2
local ANCHOR_POINTS = {
	BOTTOM = { "TOPLEFT", "BOTTOMLEFT", 0, -ANCHOR_GAP },
	TOP    = { "BOTTOMLEFT", "TOPLEFT", 0, ANCHOR_GAP },
	RIGHT  = { "TOPLEFT", "TOPRIGHT", ANCHOR_GAP, 0 },
	LEFT   = { "TOPRIGHT", "TOPLEFT", -ANCHOR_GAP, 0 },
}

local function Layout()
	for i = 1, #db.windows do
		local f = windows[i]
		LayoutWindow(f, Rows(f), Width(f))
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

-- Nom d'un sort ; en dégâts subis, la créature qui l'a lancé (hors combat : le nom est secret en combat).
local function SpellLabel(win, s)
	local name = GetSpellNameCompat(s.spellID) or ("#" .. tostring(s.spellID))
	local creature = s.creatureName
	if win.cfg.mode == "taken" and creature and not issecretvalue(creature) and creature ~= "" then
		return name .. " · " .. creature
	end
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
	if not win or not win:IsShown() or not win.selectedGuid or win.cfg.mode == "threat" or not DamageMeter then
		detail:Hide()
		return
	end
	local source = ReadSource(win, win.selectedGuid)
	local spells, secret = SortedSpells(source)
	detail:Show()
	detail.title:SetText((win.selectedName or "?") .. " : " .. FM.MODE_INFO[win.cfg.mode].label)
	local sessionTotal = source and source.totalAmount
	local session = ReadSession(win)
	for i = 1, detail.rows do
		local bar, s = detail.bars[i], spells[i]
		if s then
			bar:SetMinMaxValues(0, source.maxAmount or 1)
			bar:SetValue(s.totalAmount)
			bar:SetStatusBarColor(0.8, 0.6, 0.2)
			bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			bar.icon:SetTexture(SpellIcon(s.spellID))
			bar.left:SetText(SpellLabel(win, s))
			bar.right:SetText(FM.FormatRow(s.totalAmount, PerSecond(win, s, session, secret), sessionTotal, secret))
			bar:Show()
		else
			bar:Hide()
		end
	end
end

local function RenderMeter(win)
	local session = ReadSession(win)
	local mode = win.cfg.mode
	win.title:SetText(FM.MODE_INFO[mode].label .. " · " .. SessionLabel(win, session))
	if not DamageMeter or (DamageMeter.IsDamageMeterAvailable and not DamageMeter.IsDamageMeterAvailable()) then
		win.title:SetText(FM.MODE_INFO[mode].label .. " · " .. L.METER_UNAVAILABLE)
	end
	local list = Sources(session)
	local maxAmount = session and session.maxAmount or 1
	local sessionTotal = session and session.totalAmount
	local secret = list[1] and issecretvalue(list[1].totalAmount)
	if secret then win.scrollOffset = 0 end
	local maxOffset = math.max(0, #list - win.rows)
	if win.scrollOffset > maxOffset then win.scrollOffset = maxOffset end
	for i = 1, win.rows do
		local bar, src = win.bars[i], list[i + win.scrollOffset]
		if src then
			bar:SetMinMaxValues(0, maxAmount)
			bar:SetValue(src.totalAmount)
			bar:SetStatusBarColor(ClassColor(src.classFilename))
			SetSourceIcon(bar, src)
			bar.left:SetText(string.format("%d. %s", i + win.scrollOffset, src.name))
			local deathTime = mode == "deaths" and src.deathTimeSeconds
			if not secret and not issecretvalue(deathTime) and deathTime then
				-- Morts : nombre, puis instant de la (dernière) mort dans le combat.
				bar.right:SetText(FM.FormatValue(src.totalAmount) .. " · " .. FM.FormatTime(deathTime))
			else
				bar.right:SetText(FM.FormatRow(src.totalAmount, PerSecond(win, src, session, secret), sessionTotal, secret))
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
	win.title:SetText(L.MODE_THREAT .. " · " .. (enemy and (UnitName(enemy) or "?") or L.THREAT_NO_TARGET))
	local ok, list = pcall(function() return enemy and CollectThreat(enemy) or {} end)
	if not ok then
		win.title:SetText(L.MODE_THREAT .. " · " .. L.THREAT_UNAVAILABLE)
		list = {}
	end
	for i = 1, win.rows do
		local bar, row = win.bars[i], list[i]
		if row then
			bar:SetMinMaxValues(0, 100)
			bar:SetValue(row.pct)
			if row.tanking then bar:SetStatusBarColor(0.9, 0.2, 0.2) else bar:SetStatusBarColor(ClassColor(row.class)) end
			SetClassIcon(bar, row.class)
			bar.left:SetText((row.isPlayer and "> " or "") .. row.name)
			bar.right:SetText(string.format("%s  %s/s  %d%%", FM.FormatValue(row.value), FM.FormatValue(row.tps), row.pct))
			local warn = row.isPlayer and FM.ShouldWarn(row, db.warnPct) or false
			bar.glow:SetShown(warn)
			bar.source, bar.sourceGuid = nil, nil
			bar:Show()
			if warn and warnedGuid ~= row.guid then
				warnedGuid = row.guid
				if db.warnSound then PlaySound(WARN_SOUND, "Master") end
			elseif row.isPlayer and not warn then
				warnedGuid = nil
			end
		else
			bar:Hide()
		end
	end
end

local function Refresh()
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
local function AddRecapLines(recapID)
	local ok, has = pcall(function()
		return DeathRecap and recapID and not issecretvalue(recapID) and recapID ~= -1 and DeathRecap.HasRecapEvents(recapID)
	end)
	local events = ok and has and DeathRecap.GetRecapEvents(recapID) or nil
	if not events or #events == 0 then
		GameTooltip:AddLine(L.TIP_NO_RECAP, 0.7, 0.7, 0.7)
		return
	end
	if issecretvalue(events[#events].amount) then
		GameTooltip:AddLine(L.DETAIL_OUT_OF_COMBAT, 0.7, 0.7, 0.7)
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
	elseif bar.sourceGuid then
		local source = ReadSource(win, bar.sourceGuid)
		local spells, secret = SortedSpells(source)
		local session = ReadSession(win)
		for i = 1, math.min(5, #spells) do
			local s = spells[i]
			GameTooltip:AddDoubleLine(SpellLabel(win, s), FM.FormatRow(s.totalAmount, PerSecond(win, s, session, secret), source.totalAmount, secret), 1, 1, 1, 1, 1, 1)
		end
		GameTooltip:AddLine(L.TIP_CLICK, 0.5, 0.5, 0.5)
	else
		GameTooltip:AddLine(L.DETAIL_OUT_OF_COMBAT, 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

-- Clic sur une barre : détail par sort, dans la fenêtre de détail unique.
local function BarClick(bar)
	local win = bar.win
	if not bar.sourceGuid then
		if win.cfg.mode ~= "threat" then Print(L.DETAIL_OUT_OF_COMBAT) end
		return
	end
	if detail.owner == win and win.selectedGuid == bar.sourceGuid then
		win.selectedGuid, win.selectedName = nil, nil
	else
		if detail.owner and detail.owner ~= win then detail.owner.selectedGuid = nil end
		detail.owner = win
		win.selectedGuid, win.selectedName = bar.sourceGuid, bar.sourceName
		AnchorDetail()
	end
	Refresh()
end

------------------------------------------------------------------------
-- Menu (mode, session, fenêtres, verrou, remise à zéro) et gestion des fenêtres
------------------------------------------------------------------------
local EnsureWindows -- défini plus bas, après NewWindow

local function ResetData()
	if DamageMeter and DamageMeter.ResetAllCombatSessions then DamageMeter.ResetAllCombatSessions() end
	for i = 1, #db.windows do SelectView(windows[i], "current") end
	wipe(threatSamples)
	Refresh()
end

local function AddWindow()
	if #db.windows >= FM.MAX_WINDOWS then return end
	db.windows[#db.windows + 1] = FM.NewWindowConfig(db.windows, WindowHeight(db.windows[#db.windows].rows))
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
local function MenuEntries(win)
	local entries = { { title = L.MENU_DISPLAY } }
	for _, m in ipairs(FM.MODES) do
		entries[#entries + 1] = { text = FM.MODE_INFO[m].label, checked = function() return win.cfg.mode == m end, func = function() SelectMode(win, m); Refresh() end }
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
	if #db.windows < FM.MAX_WINDOWS then entries[#entries + 1] = { text = L.MENU_NEW_WINDOW, func = AddWindow } end
	if #db.windows > 1 then entries[#entries + 1] = { text = L.MENU_CLOSE_WINDOW, func = function() CloseWindow(win) end } end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { text = L.MENU_RESET, func = ResetData }
	return entries
end

local legacyDropDown = EasyMenu and CreateFrame("Frame", "ForeverMeterDropDown", UIParent, "UIDropDownMenuTemplate")
if legacyDropDown then legacyDropDown:Hide() end

local function OpenMenu(win, owner)
	local entries = MenuEntries(win)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
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
		CycleMode(win, 1)
		Refresh()
	end
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
	f.menuButton:SetScript("OnClick", function(self) OpenMenu(f, self) end)
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
	f.title:SetPoint("RIGHT", f.lockButton, "LEFT", -4, 0)
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
		f:SetUserPlaced(false)
		f.OnMoved()
		TrySnap(f)
		Layout()
	end)
	f.header:SetScript("OnClick", function(self, button)
		if button == "RightButton" then OpenMenu(f, self) else CycleMode(f, 1); Refresh() end
	end)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		f.scrollOffset = math.max(0, f.scrollOffset - delta)
		Refresh()
	end)
	-- Poignée en bas à droite : glisser règle largeur et nombre de lignes de cette fenêtre seule.
	-- Redimensionnement à la main (OnUpdate + GetCursorPosition) entre OnDragStart et OnDragStop : sur ce client,
	-- StartSizing ne déclenche ni OnSizeChanged ni OnMouseUp, et IsMouseButtonDown répond « relâché » pendant le
	-- glissement ; seuls les événements de drag (ceux du titre) sont fiables.
	f.grip = CreateFrame("Button", nil, f)
	f.grip:SetSize(12, 12)
	f.grip:RegisterForDrag("LeftButton")
	f.grip:SetPoint("BOTTOMRIGHT", -1, 1)
	f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	-- Taille (largeur, hauteur en px) -> largeur et lignes de cette fenêtre.
	local function SizeToConfig(w, h)
		return math.max(150, math.min(600, math.floor(w + 0.5))),
			math.max(1, math.min(40, math.floor((h - 21) / (db.rowHeight + 1) + 0.5)))
	end
	-- Relâchement : la taille suivie pendant le glissement est arrondie à un nombre entier de lignes.
	f.OnResized = function()
		Layout()
		Refresh()
	end
	local function StopSizing()
		if not f.sizing then return end
		f.sizing = nil
		f.grip:SetScript("OnUpdate", nil)
		f.OnMoved()
		f.OnResized()
	end
	-- À chaque image pendant le glissement : coin bas-droit sous le curseur, coin haut-gauche fixe, barres replacées,
	-- taille enregistrée tout de suite (une déconnexion en plein glissement garde la dernière taille vue).
	local function FollowCursor()
		local x, y = GetCursorPosition()
		local scale = f:GetEffectiveScale()
		local w = math.max(150, math.min(600, x / scale - f:GetLeft()))
		local h = math.max(WindowHeight(1), math.min(WindowHeight(40), f:GetTop() - y / scale))
		f.cfg.width, f.cfg.rows = SizeToConfig(w, h)
		f:SetSize(w, h)
		LayoutBars(f, f.cfg.rows, w)
		Refresh()
	end
	f.grip:SetScript("OnDragStart", function()
		if f.cfg.locked then return end
		f.sizing = true
		-- Coin haut-gauche fixé en absolu : l'ancre CENTER enregistrée ferait bouger la fenêtre en grandissant.
		local left, top = f:GetLeft(), f:GetTop()
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		f.grip:SetScript("OnUpdate", FollowCursor)
	end)
	f.grip:SetScript("OnDragStop", StopSizing)
	for b = 1, 40 do
		local bar = MakeBar(f, b)
		bar.win = f
		bar:SetScript("OnMouseUp", BarClick)
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
_G.ForeverMeter_Toggle = ToggleWindows -- AddonCompartmentFunc (.toc)

-- Applique la langue choisie (db.locale, sinon celle du client) et met à jour les textes déjà posés.
local function ApplyLanguage()
	local code = FM.ApplyLocale(db.locale or GetLocale())
	for _, f in ipairs(windows) do
		f.resetButton:SetText(L.BTN_RESET)
		f.menuButton:SetText(L.BTN_MENU)
	end
	return code
end

-- Valeurs par défaut, migration de l'ancien format (db.mode, db.point) vers db.windows, nettoyage.
local function InitDb()
	for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
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
	if not db or elapsedSince < db.refresh then return end
	elapsedSince = 0
	Refresh()
end)

Register(events, "ADDON_LOADED")
Register(events, "PLAYER_ENTERING_WORLD")
Register(events, "GROUP_ROSTER_UPDATE")
Register(events, "PLAYER_REGEN_ENABLED")
Register(events, "DAMAGE_METER_CURRENT_SESSION_UPDATED")
Register(events, "DAMAGE_METER_COMBAT_SESSION_UPDATED")
Register(events, "DAMAGE_METER_RESET")
-- DAMAGE_METER_SESSION_EXPIRED n'existe pas sur WoW Forever 1.60 : non enregistré.
events:SetScript("OnEvent", function(_, event, arg1)
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
	elseif event == "GROUP_ROSTER_UPDATE" then
		wipe(threatSamples)
	elseif event == "PLAYER_REGEN_ENABLED" then
		warnedGuid = nil
		Refresh()
	elseif event == "DAMAGE_METER_RESET" then
		for i = 1, #db.windows do
			local win = windows[i]
			if type(win.cfg.view) == "number" then win.cfg.view = "current" end
			win.selectedGuid = nil
		end
		Refresh()
	else
		Refresh()
	end
end)

------------------------------------------------------------------------
-- Commandes : /fm (mode, report et debug agissent sur la première fenêtre)
------------------------------------------------------------------------
local function Report(win, count)
	if win.cfg.mode == "threat" then Print(L.REPORT_NOTHING_THREAT); return end
	local session = ReadSession(win)
	local list = Sources(session)
	if not list[1] then Print(L.REPORT_NOTHING); return end
	if issecretvalue(list[1].totalAmount) then Print(L.REPORT_OUT_OF_COMBAT); return end
	-- SAY est interdit aux addons hors instance (ADDON_ACTION_FORBIDDEN) : seul, on affiche en local.
	local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or (IsInInstance() and "SAY" or nil))
	local function Send(msg)
		if channel then SendChatMessage(msg, channel) else Print(msg) end
	end
	Send(string.format(L.REPORT_HEADER, FM.MODE_INFO[win.cfg.mode].label, SessionLabel(win, session)))
	for i = 1, math.min(count, #list) do
		local s = list[i]
		Send(string.format("%d. %s  %s", i, s.name, FM.FormatRow(s.totalAmount, PerSecond(win, s, session, false), session.totalAmount, false)))
	end
end

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

SLASH_FOREVERMETER1 = "/fm"
SLASH_FOREVERMETER2 = "/forevermeter"
SlashCmdList.FOREVERMETER = function(input)
	local cmd, arg = input:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	local num = tonumber(arg)
	local first = windows[1]
	if cmd == "lock" or cmd == "unlock" then
		for i = 1, #db.windows do windows[i].cfg.locked = cmd == "lock"; windows[i].UpdateLock() end
		Print(cmd == "lock" and L.MSG_LOCKED or L.MSG_UNLOCKED)
	elseif cmd == "toggle" then ToggleWindows()
	elseif cmd == "scale" and num then db.scale = math.max(0.5, math.min(2, num))
	elseif cmd == "rows" and num then
		db.rows = math.max(1, math.min(40, math.floor(num)))
		for _, c in ipairs(db.windows) do c.rows = nil end
	elseif cmd == "width" and num then
		db.width = math.max(150, math.min(600, math.floor(num)))
		for _, c in ipairs(db.windows) do c.width = nil end
	elseif cmd == "refresh" and num then db.refresh = math.max(0.05, math.min(2, num)); Print(string.format(L.MSG_REFRESH, db.refresh))
	elseif cmd == "windows" and num then
		num = math.max(1, math.min(FM.MAX_WINDOWS, math.floor(num)))
		while #db.windows < num do db.windows[#db.windows + 1] = FM.NewWindowConfig(db.windows, WindowHeight(db.windows[#db.windows].rows)) end
		while #db.windows > num do RemoveWindow(#db.windows) end
		EnsureWindows()
		Print(string.format(L.MSG_WINDOWS, #db.windows))
	elseif cmd == "mode" and FM.MODE_INFO[arg:lower()] then SelectMode(first, arg:lower())
	elseif cmd == "report" then Report(first, num or 5); return
	elseif cmd == "debug" then
		local ok, err = pcall(Debug, first)
		if not ok then Print("debug : erreur " .. tostring(err)) end
		return
	elseif cmd == "reset" then
		ResetData()
		Print(L.MSG_RESET)
	elseif cmd == "warn" and num then db.warnPct = math.max(1, math.min(130, math.floor(num))); Print(string.format(L.MSG_WARN, db.warnPct))
	elseif cmd == "sound" then db.warnSound = not db.warnSound; Print(string.format(L.MSG_SOUND, db.warnSound and L.WORD_ON or L.WORD_OFF))
	elseif cmd == "pets" then db.showPets = not db.showPets; Print(string.format(L.MSG_PETS, db.showPets and L.WORD_SHOWN or L.WORD_HIDDEN))
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
		wipe(db)
		InitDb()
		EnsureWindows()
		ApplyLanguage()
		Print(L.MSG_DEFAULTS)
	else
		-- Pas de "|" entre les modes : le chat lit "|h", "|a", "|t"... comme des codes d'échappement.
		Print(string.format(L.HELP_1, table.concat(FM.MODES, ", ")))
		Print(L.HELP_2)
		return
	end
	Layout()
	Refresh()
end
