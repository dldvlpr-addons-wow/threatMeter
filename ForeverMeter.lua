-- ForeverMeter : compteur de dégâts, soins, dégâts subis et menace pour WoW Forever (client 1.60, moteur 12.x).
-- Un seul fichier, aucune dépendance (ni Details, ni Ace, ni LibStub).
--
-- Sur ce moteur, COMBAT_LOG_EVENT_UNFILTERED est interdit aux addons : les données viennent de C_DamageMeter,
-- le compteur serveur de Blizzard. En combat, noms, montants et GUID sont des « valeurs secrètes » : on peut les
-- afficher (SetText, SetValue, string.format) mais ni les comparer, ni les additionner, ni les renvoyer à l'API.
-- L'addon affiche donc les barres dans l'ordre fourni par l'API, et complète (%, détail par sort) hors combat.
--
-- Structure :
--   1. Logique pure (format, tri de la menace) : testable hors jeu.
--   2. Partie WoW : lecture C_DamageMeter, menace, fenêtres, commandes.

local ADDON, NS = ...
local L = NS and NS.L or {}
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

local DEFAULTS = {
	locked = false,
	scale = 1,
	rows = 10,
	width = 260,
	rowHeight = 16,
	mode = "damage",
	warnPct = 90,
	warnSound = true,
	showPets = true,
	point = { "CENTER", nil, "CENTER", 300, 0 },
}

------------------------------------------------------------------------
-- 1. Logique pure
------------------------------------------------------------------------

function FM.FormatValue(v)
	v = v or 0
	if v >= 1000000 then return string.format("%.2fM", v / 1000000) end
	if v >= 1000 then return string.format("%.1fk", v / 1000) end
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
		return string.format("%d (%d/s)", total, perSecond)
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
local UnitCanAttack, UnitIsDead, UnitIsUnit = UnitCanAttack, UnitIsDead, UnitIsUnit
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local GetTime, PlaySound = GetTime, PlaySound
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local WARN_SOUND = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
local issecretvalue = issecretvalue or function() return false end
local DamageMeter = C_DamageMeter

local db
local view = "current"                    -- "current" | "overall" | sessionID (number)
local threatSamples = {}
local warnedGuid = nil
local scrollOffset = 0
local selectedGuid = nil                  -- GUID ouvert dans la fenêtre de détail
local selectedName = nil

------------------------------------------------------------------------
-- Lecture de C_DamageMeter
------------------------------------------------------------------------
local function MeterType()
	return FM.MODE_INFO[db.mode].type
end

-- Session affichée selon la vue. nil si l'API est absente ou la session inconnue.
local function ReadSession()
	if not DamageMeter then return nil end
	local t = MeterType()
	if view == "overall" then return DamageMeter.GetCombatSessionFromType(FM.SESSION_OVERALL, t) end
	if view == "current" then return DamageMeter.GetCombatSessionFromType(FM.SESSION_CURRENT, t) end
	return DamageMeter.GetCombatSessionFromID(view, t)
end

-- Durée de la session affichée, en secondes, ou nil si le client ne la donne pas ou la garde secrète.
local function SessionDuration(session)
	local d = session and session.durationSeconds
	if d == nil and (view == "overall" or view == "current") and DamageMeter and DamageMeter.GetSessionDurationSeconds then
		d = DamageMeter.GetSessionDurationSeconds(view == "overall" and FM.SESSION_OVERALL or FM.SESSION_CURRENT)
	end
	if d == nil or issecretvalue(d) or d <= 0 then return nil end
	return d
end

-- Par seconde d'une source ou d'un sort : amountPerSecond de l'API (vérifié : c'est bien le débit,
-- le type Dps de l'enum ne rend que le total). Hors combat, si l'API rend 0 avec un total non nul,
-- repli total / durée de session.
local function PerSecond(entry, session, secret)
	local ps = entry.amountPerSecond or 0
	if secret then return ps end
	if ps == 0 and (entry.totalAmount or 0) > 0 then
		local d = SessionDuration(session)
		if d then ps = entry.totalAmount / d end
	end
	return ps
end

local function AvailableSessions()
	if not DamageMeter then return {} end
	return DamageMeter.GetAvailableCombatSessions() or {}
end

local function SessionLabel(session)
	if view == "overall" then return L.SESSION_OVERALL end
	if view == "current" then
		local d = session and session.durationSeconds
		return L.SESSION_CURRENT .. (d and not issecretvalue(d) and (" (" .. FM.FormatTime(d) .. ")") or "")
	end
	for _, s in ipairs(AvailableSessions()) do
		if s.sessionID == view then
			local d = s.durationSeconds
			return s.name .. (d and not issecretvalue(d) and (" (" .. FM.FormatTime(d) .. ")") or "")
		end
	end
	return string.format(L.SESSION_UNKNOWN, tostring(view))
end

local function CycleView(step)
	local order = { "current", "overall" }
	for _, s in ipairs(AvailableSessions()) do order[#order + 1] = s.sessionID end
	local idx = 1
	for i, v in ipairs(order) do if v == view then idx = i end end
	idx = ((idx - 1 + step) % #order) + 1
	view = order[idx]
	scrollOffset = 0
end

local function CycleMode(step)
	local idx = 1
	for i, m in ipairs(FM.MODES) do if m == db.mode then idx = i end end
	idx = ((idx - 1 + step) % #FM.MODES) + 1
	db.mode = FM.MODES[idx]
	scrollOffset = 0
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

------------------------------------------------------------------------
-- Menace (hors C_DamageMeter)
------------------------------------------------------------------------
local function GroupUnits()
	local units = { "player" }
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	elseif IsInGroup() then
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
	local c = class and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

local function MakeWindow(name, w, h)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(w, h)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
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
	f.header:SetScript("OnDragStart", function() if not db.locked then f:StartMoving() end end)
	f.header:SetScript("OnDragStop", function() f:StopMovingOrSizing(); if f.OnMoved then f.OnMoved() end end)
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

local function LayoutWindow(f, rows, width)
	f:SetScale(db.scale)
	f:SetWidth(width)
	f:SetHeight(18 + rows * (db.rowHeight + 1) + 3)
	for i = 1, math.max(rows, #f.bars) do
		local bar = f.bars[i] or MakeBar(f, i)
		bar:SetSize(width - 6, db.rowHeight)
		bar.icon:SetSize(db.rowHeight - 2, db.rowHeight - 2)
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", 3, -18 - (i - 1) * (db.rowHeight + 1))
		if i > rows then bar:Hide() end
	end
end

local main = MakeWindow("ForeverMeterFrame", DEFAULTS.width, 100)
local detail = MakeWindow("ForeverMeterDetailFrame", DEFAULTS.width, 100)
detail:Hide()
detail.close = CreateFrame("Button", nil, detail.header, "UIPanelCloseButton")
detail.close:SetPoint("RIGHT", 2, 0)
detail.close:SetSize(20, 20)
detail.close:SetScript("OnClick", function() selectedGuid = nil; detail:Hide() end)

main.OnMoved = function()
	local point, _, relPoint, x, y = main:GetPoint()
	db.point = { point, nil, relPoint, x, y }
end

local function Layout()
	LayoutWindow(main, db.rows, db.width)
	LayoutWindow(detail, db.rows, db.width)
	main:ClearAllPoints()
	main:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
	detail:ClearAllPoints()
	detail:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
end

local GetSpellTextureCompat = (C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
local GetSpellNameCompat = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
local function SpellIcon(spellID)
	local tex = spellID and GetSpellTextureCompat(spellID)
	return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local function SetClassIcon(bar, class)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		bar.icon:SetTexture(CLASS_ICONS)
		bar.icon:SetTexCoord(unpack(coords))
	else
		bar.icon:SetTexture(nil)
	end
end

-- Détail par sort d'une source. Le GUID d'un autre joueur est secret en combat : détail hors combat seulement.
local function RenderDetail()
	if not selectedGuid or db.mode == "threat" or not DamageMeter then detail:Hide(); return end
	local t = MeterType()
	local source
	if view == "overall" or view == "current" then
		source = DamageMeter.GetCombatSessionSourceFromType(view == "overall" and FM.SESSION_OVERALL or FM.SESSION_CURRENT, t, selectedGuid)
	else
		source = DamageMeter.GetCombatSessionSourceFromID(view, t, selectedGuid)
	end
	local spells = source and source.combatSpells or {}
	detail:Show()
	detail.title:SetText((selectedName or "?") .. " : " .. FM.MODE_INFO[db.mode].label)
	local secret = spells[1] and issecretvalue(spells[1].totalAmount)
	if not secret then
		table.sort(spells, function(a, b) return a.totalAmount > b.totalAmount end)
	end
	local sessionTotal = source and source.totalAmount
	local session = ReadSession()
	for i = 1, db.rows do
		local bar, s = detail.bars[i], spells[i]
		if s then
			bar:SetMinMaxValues(0, source.maxAmount or 1)
			bar:SetValue(s.totalAmount)
			bar:SetStatusBarColor(0.8, 0.6, 0.2)
			bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			bar.icon:SetTexture(SpellIcon(s.spellID))
			bar.left:SetText(GetSpellNameCompat(s.spellID) or ("#" .. tostring(s.spellID)))
			bar.right:SetText(FM.FormatRow(s.totalAmount, PerSecond(s, session, secret), sessionTotal, secret))
			bar:Show()
		else
			bar:Hide()
		end
	end
end

local function RenderMeter()
	local session = ReadSession()
	main.title:SetText(FM.MODE_INFO[db.mode].label .. " · " .. SessionLabel(session))
	if not DamageMeter or (DamageMeter.IsDamageMeterAvailable and not DamageMeter.IsDamageMeterAvailable()) then
		main.title:SetText(FM.MODE_INFO[db.mode].label .. " · " .. L.METER_UNAVAILABLE)
	end
	local list = Sources(session)
	local maxAmount = session and session.maxAmount or 1
	local sessionTotal = session and session.totalAmount
	local secret = list[1] and issecretvalue(list[1].totalAmount)
	if secret then scrollOffset = 0 end
	local maxOffset = math.max(0, #list - db.rows)
	if scrollOffset > maxOffset then scrollOffset = maxOffset end
	for i = 1, db.rows do
		local bar, src = main.bars[i], list[i + scrollOffset]
		if src then
			bar:SetMinMaxValues(0, maxAmount)
			bar:SetValue(src.totalAmount)
			bar:SetStatusBarColor(ClassColor(src.classFilename))
			SetClassIcon(bar, src.classFilename)
			bar.left:SetText(string.format("%d. %s", i + scrollOffset, src.name))
			bar.right:SetText(FM.FormatRow(src.totalAmount, PerSecond(src, session, secret), sessionTotal, secret))
			bar.glow:Hide()
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
			bar.sourceGuid = nil
			bar:Hide()
		end
	end
	RenderDetail()
end

local function RenderThreat()
	local enemy = ThreatTarget()
	main.title:SetText(L.MODE_THREAT .. " · " .. (enemy and (UnitName(enemy) or "?") or L.THREAT_NO_TARGET))
	detail:Hide()
	local ok, list = pcall(function() return enemy and CollectThreat(enemy) or {} end)
	if not ok then
		main.title:SetText(L.MODE_THREAT .. " · " .. L.THREAT_UNAVAILABLE)
		list = {}
	end
	for i = 1, db.rows do
		local bar, row = main.bars[i], list[i]
		if row then
			bar:SetMinMaxValues(0, 100)
			bar:SetValue(row.pct)
			if row.tanking then bar:SetStatusBarColor(0.9, 0.2, 0.2) else bar:SetStatusBarColor(ClassColor(row.class)) end
			SetClassIcon(bar, row.class)
			bar.left:SetText((row.isPlayer and "> " or "") .. row.name)
			bar.right:SetText(string.format("%s  %s/s  %d%%", FM.FormatValue(row.value), FM.FormatValue(row.tps), row.pct))
			local warn = row.isPlayer and FM.ShouldWarn(row, db.warnPct) or false
			bar.glow:SetShown(warn)
			bar.sourceGuid = nil
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
	if db.mode == "threat" then RenderThreat() else RenderMeter() end
end

------------------------------------------------------------------------
-- Boutons du titre : menu déroulant (mode + session) et remise à zéro
------------------------------------------------------------------------
local function ResetData()
	if DamageMeter and DamageMeter.ResetAllCombatSessions then DamageMeter.ResetAllCombatSessions() end
	view, selectedGuid, scrollOffset = "current", nil, 0
	wipe(threatSamples)
	Refresh()
end

local function SelectMode(m) db.mode = m; scrollOffset = 0; selectedGuid = nil; Refresh() end
local function SelectView(v) view = v; scrollOffset = 0; selectedGuid = nil; Refresh() end

-- Entrées du menu sous forme neutre : { text, checked(), func } ou { title } ou { divider }.
local function MenuEntries()
	local entries = { { title = L.MENU_DISPLAY } }
	for _, m in ipairs(FM.MODES) do
		entries[#entries + 1] = { text = FM.MODE_INFO[m].label, checked = function() return db.mode == m end, func = function() SelectMode(m) end }
	end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { title = L.MENU_SESSION }
	entries[#entries + 1] = { text = L.SESSION_CURRENT, checked = function() return view == "current" end, func = function() SelectView("current") end }
	entries[#entries + 1] = { text = L.SESSION_OVERALL, checked = function() return view == "overall" end, func = function() SelectView("overall") end }
	for _, s in ipairs(AvailableSessions()) do
		local id = s.sessionID
		entries[#entries + 1] = { text = s.name, checked = function() return view == id end, func = function() SelectView(id) end }
	end
	entries[#entries + 1] = { divider = true }
	entries[#entries + 1] = { text = L.MENU_RESET, func = ResetData }
	return entries
end

local legacyDropDown = EasyMenu and CreateFrame("Frame", "ForeverMeterDropDown", UIParent, "UIDropDownMenuTemplate")
if legacyDropDown then legacyDropDown:Hide() end

local function OpenMenu(owner)
	local entries = MenuEntries()
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, e in ipairs(entries) do
				if e.title then root:CreateTitle(e.title)
				elseif e.divider then root:CreateDivider()
				elseif e.checked then root:CreateRadio(e.text, e.checked, e.func)
				else root:CreateButton(e.text, e.func) end
			end
		end)
	elseif legacyDropDown then
		local list = {}
		for _, e in ipairs(entries) do
			if e.title then list[#list + 1] = { text = e.title, isTitle = true, notCheckable = true }
			elseif e.divider then list[#list + 1] = { text = "", disabled = true, notCheckable = true }
			else list[#list + 1] = { text = e.text, checked = e.checked, func = e.func, notCheckable = e.checked == nil } end
		end
		EasyMenu(list, legacyDropDown, owner, 0, 0, "MENU")
	else
		CycleMode(1)
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

main.resetButton = MakeHeaderButton(main.header, L.BTN_RESET, 38)
main.resetButton:SetPoint("RIGHT", -2, 0)
main.resetButton:SetScript("OnClick", ResetData)
main.menuButton = MakeHeaderButton(main.header, L.BTN_MENU, 44)
main.menuButton:SetPoint("RIGHT", main.resetButton, "LEFT", -2, 0)
main.menuButton:SetScript("OnClick", function(self) OpenMenu(self) end)
main.title:SetPoint("RIGHT", main.menuButton, "LEFT", -4, 0)

-- Titre : clic gauche = mode suivant, clic droit = menu.
main.header:SetScript("OnClick", function(self, button)
	if button == "RightButton" then OpenMenu(self) else CycleMode(1); Refresh() end
end)
main:EnableMouseWheel(true)
main:SetScript("OnMouseWheel", function(_, delta)
	scrollOffset = math.max(0, scrollOffset - delta)
	Refresh()
end)
-- Clic sur une barre : détail par sort.
for i = 1, 40 do
	local bar = main.bars[i] or MakeBar(main, i)
	bar:SetScript("OnMouseUp", function(self)
		if not self.sourceGuid then
			if db.mode ~= "threat" then DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverMeter|r : " .. L.DETAIL_OUT_OF_COMBAT) end
			return
		end
		if selectedGuid == self.sourceGuid then
			selectedGuid, selectedName = nil, nil
		else
			selectedGuid, selectedName = self.sourceGuid, self.sourceName
		end
		Refresh()
	end)
end

------------------------------------------------------------------------
-- Événements
------------------------------------------------------------------------
local elapsedSince = 0
main:SetScript("OnUpdate", function(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.5 or not db then return end
	elapsedSince = 0
	Refresh()
end)

local events = CreateFrame("Frame")
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
		ForeverMeterDB = ForeverMeterDB or {}
		db = ForeverMeterDB
		for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
		if not FM.MODE_INFO[db.mode] then db.mode = "damage" end
		db.forbidden = forbiddenLog
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
		if type(view) == "number" then view = "current" end
		selectedGuid = nil
		Refresh()
	else
		Refresh()
	end
end)

------------------------------------------------------------------------
-- Commandes : /fm
------------------------------------------------------------------------
local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverMeter|r : " .. msg)
end

local function Report(count)
	if db.mode == "threat" then Print(L.REPORT_NOTHING_THREAT); return end
	local session = ReadSession()
	local list = Sources(session)
	if not list[1] then Print(L.REPORT_NOTHING); return end
	if issecretvalue(list[1].totalAmount) then Print(L.REPORT_OUT_OF_COMBAT); return end
	-- SAY est interdit aux addons hors instance (ADDON_ACTION_FORBIDDEN) : seul, on affiche en local.
	local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or (IsInInstance() and "SAY" or nil))
	local function Send(msg)
		if channel then SendChatMessage(msg, channel) else Print(msg) end
	end
	Send(string.format(L.REPORT_HEADER, FM.MODE_INFO[db.mode].label, SessionLabel(session)))
	for i = 1, math.min(count, #list) do
		local s = list[i]
		Send(string.format("%d. %s  %s", i, s.name, FM.FormatRow(s.totalAmount, PerSecond(s, session, false), session.totalAmount, false)))
	end
end

SLASH_FOREVERMETER1 = "/fm"
SLASH_FOREVERMETER2 = "/forevermeter"
SlashCmdList.FOREVERMETER = function(input)
	local cmd, arg = input:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	local num = tonumber(arg)
	if cmd == "lock" then db.locked = true; Print(L.MSG_LOCKED)
	elseif cmd == "unlock" then db.locked = false; Print(L.MSG_UNLOCKED)
	elseif cmd == "toggle" then main:SetShown(not main:IsShown())
	elseif cmd == "scale" and num then db.scale = math.max(0.5, math.min(2, num))
	elseif cmd == "rows" and num then db.rows = math.max(1, math.min(40, math.floor(num)))
	elseif cmd == "width" and num then db.width = math.max(150, math.min(600, math.floor(num)))
	elseif cmd == "mode" and FM.MODE_INFO[arg] then db.mode = arg; scrollOffset = 0
	elseif cmd == "report" then Report(num or 5); return
	elseif cmd == "reset" then
		ResetData()
		Print(L.MSG_RESET)
	elseif cmd == "warn" and num then db.warnPct = math.max(1, math.min(130, math.floor(num))); Print(string.format(L.MSG_WARN, db.warnPct))
	elseif cmd == "sound" then db.warnSound = not db.warnSound; Print(string.format(L.MSG_SOUND, db.warnSound and L.WORD_ON or L.WORD_OFF))
	elseif cmd == "pets" then db.showPets = not db.showPets; Print(string.format(L.MSG_PETS, db.showPets and L.WORD_SHOWN or L.WORD_HIDDEN))
	elseif cmd == "defaults" then
		wipe(db)
		for k, v in pairs(DEFAULTS) do db[k] = v end
		Print(L.MSG_DEFAULTS)
	else
		Print(string.format(L.HELP_1, table.concat(FM.MODES, "|")))
		Print(L.HELP_2)
		return
	end
	Layout()
	Refresh()
end
