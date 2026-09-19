-- Faux client WoW minimal : exécute la partie UI de ForeverMeter hors jeu pour attraper les erreurs d'exécution.
local calls = {}
local function Obj(kind)
	local o = { kind = kind, shown = true, texts = {}, scripts = {} }
	return setmetatable(o, { __index = function(t, k)
		if k == "SetScript" then return function(self, n, f) self.scripts[n] = f end end
		if k == "GetScript" then return function(self, n) return self.scripts[n] end end
		if k == "Show" then return function(self) self.shown = true end end
		if k == "Hide" then return function(self) self.shown = false end end
		if k == "SetShown" then return function(self, v) self.shown = v end end
		if k == "IsShown" then return function(self) return self.shown end end
		if k == "SetText" then return function(self, v) self.text = v end end
		if k == "GetText" then return function(self) return self.text end end
		if k == "GetPoint" then return function() return "CENTER", nil, "CENTER", 10, 20 end end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return Obj(k) end end
		if k == "RegisterEvent" then return function(self, e) if e == "BOGUS" then error("unknown event") end end end
		if k == "AddLine" then return function(self, l) self.texts[#self.texts + 1] = tostring(l) end end
		if k == "AddDoubleLine" then return function(self, l, r) self.texts[#self.texts + 1] = tostring(l) .. " | " .. tostring(r) end end
		if type(k) ~= "string" or not k:match("^[A-Z]") or k == "OnMoved" then return nil end
		return function() calls[k] = (calls[k] or 0) + 1 end
	end })
end
CreateFrame = function(kind, name) local f = Obj(kind); f.name = name; if name then _G[name] = f end; return f end
UIParent = Obj("Frame")
GameTooltip = Obj("GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("  chat> " .. m) end }
RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = 0.5, b = 0 }, PRIEST = { r = 1, g = 1, b = 1 } }
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, PRIEST = { 0.5, 0.75, 0.25, 0.5 } }
SOUNDKIT = { RAID_WARNING = 1 }
GetLocale = function() return "frFR" end
GetTime = function() return os.clock() end
PlaySound = function() end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
UnitGUID = function(u) return "Player-" .. u end
UnitName = function(u) return u == "player" and "Moi" or u end
UnitClass = function() return "Guerrier", "WARRIOR" end
UnitExists = function(u) return u == "player" or u == "target" or u == "party1" end
UnitAffectingCombat = function() return false end
UnitCanAttack = function() return true end
UnitIsDead = function() return false end
UnitIsUnit = function(a, b) return a == b end
UnitDetailedThreatSituation = function(u) return u == "player", 3, 95, 95, 1000 end
IsInRaid = function() return false end
IsInGroup = function() return true end
IsInInstance = function() return false end
GetNumGroupMembers = function() return 2 end
SendChatMessage = function(msg, ch) print("  " .. ch .. "> " .. msg) end
C_Spell = { GetSpellTexture = function() return 123 end, GetSpellName = function(id) return "Sort" .. id end }
SlashCmdList = {}
MenuUtil = { CreateContextMenu = function(owner, gen)
	local root = Obj("Menu")
	root.entries = {}
	for _, m in ipairs({ "CreateTitle", "CreateDivider", "CreateRadio", "CreateCheckbox", "CreateButton" }) do
		root[m] = function(_, text, checked, func) root.entries[#root.entries + 1] = { m, text, checked, func } end
	end
	gen(nil, root)
	_G.LAST_MENU = root.entries
end }

local secretMode = false
issecretvalue = function() return secretMode end
local function src(name, class, total, guid, extra)
	local s = { name = name, classFilename = class, totalAmount = total, amountPerSecond = total / 10, sourceGUID = guid, isLocalPlayer = guid == "Player-player",
		specIconID = 456, combatSpells = { { spellID = 1, totalAmount = total * 0.6, amountPerSecond = 3 }, { spellID = 2, totalAmount = total * 0.4, amountPerSecond = 2, creatureName = "Ogre" } }, maxAmount = total * 0.6 }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end
local session = { durationSeconds = 60, totalAmount = 3000, maxAmount = 2000, combatSources = {
	src("Moi", "WARRIOR", 2000, "Player-player", { deathRecapID = 7, deathTimeSeconds = 42 }),
	src("Bob", "PRIEST", 1000, "Player-bob", { deathRecapID = -1 }),
} }
C_DamageMeter = {
	GetCombatSessionFromType = function() return session end,
	GetCombatSessionFromID = function() return session end,
	GetCombatSessionSourceFromType = function(_, _, guid) for _, s in ipairs(session.combatSources) do if s.sourceGUID == guid then return s end end end,
	GetCombatSessionSourceFromID = function(_, _, guid) for _, s in ipairs(session.combatSources) do if s.sourceGUID == guid then return s end end end,
	GetAvailableCombatSessions = function() return { { sessionID = 12, name = "Ogre", durationSeconds = 30 } } end,
	GetSessionDurationSeconds = function() return 60 end,
	ResetAllCombatSessions = function() calls.reset = (calls.reset or 0) + 1 end,
}
C_DeathRecap = {
	HasRecapEvents = function(id) return id == 7 end,
	GetRecapEvents = function() return { { spellId = 5, amount = 900, timestamp = 40, currentHP = 100, sourceName = "Ogre" }, { spellName = "Frappe", amount = 200, timestamp = 42, currentHP = 0 } } end,
}

local NS = {}
for _, code in ipairs({ "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
	assert(loadfile("Locale/" .. code .. ".lua"))("ForeverMeter", NS)
end
assert(loadfile("ForeverMeter.lua"))("ForeverMeter", NS)
local FM = ForeverMeter

-- Chargement : trouve la frame d'événements (celle qui a ADDON_LOADED dans OnEvent) via le script OnUpdate.
ForeverMeterDB = { mode = "heal", point = { "TOPLEFT", nil, "TOPLEFT", 5, -5 }, locked = true }
local eventsFrame
-- Les frames sans nom : on retrouve celle avec OnEvent + OnUpdate en explorant les Obj créés par CreateFrame.
local created = {}
local realCreate = CreateFrame
CreateFrame = function(...) local f = realCreate(...); created[#created + 1] = f; return f end
-- ForeverMeter est déjà chargé : la frame events existe déjà. On la retrouve en injectant via le guard ADDON_ACTION ? Plus simple : rejouer le chargement.
NS = {}
for _, code in ipairs({ "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
	assert(loadfile("Locale/" .. code .. ".lua"))("ForeverMeter", NS)
end
assert(loadfile("ForeverMeter.lua"))("ForeverMeter", NS)
FM = ForeverMeter
for _, f in ipairs(created) do if f.scripts.OnEvent and f.scripts.OnUpdate then eventsFrame = f end end
assert(eventsFrame, "frame events introuvable")
local function Fire(e, a) eventsFrame.scripts.OnEvent(eventsFrame, e, a) end
Fire("ADDON_LOADED", "Autre")
Fire("ADDON_LOADED", "ForeverMeter")
local db = ForeverMeterDB
assert(db.mode == nil and #db.windows == 1 and db.windows[1].mode == "heal" and db.windows[1].point[4] == 5, "migration db.mode/db.point")
local w1 = ForeverMeterFrame
assert(w1 and w1.cfg == db.windows[1])
assert(w1.title.text:find("Soins"), w1.title.text)
assert(w1.bars[1].left.text == "1. Moi" and w1.bars[2].left.text == "2. Bob" and not w1.bars[3].shown, tostring(w1.bars[1].left.text))
assert(w1.bars[1].right.text == "2.0k (200/s, 66.7%)", w1.bars[1].right.text)
assert(w1.bars[1].icon.SetTexture and w1.resetButton.text == "Reset")

-- Tick OnUpdate
eventsFrame.scripts.OnUpdate(eventsFrame, 1)

-- Commandes
local slash = SlashCmdList.FOREVERMETER
slash("windows 3")
assert(#db.windows == 3 and ForeverMeterFrame2 and ForeverMeterFrame3 and ForeverMeterFrame3.shown)
assert(db.windows[2].mode == "damage" and db.windows[2].point[5] < db.windows[1].point[5], "2e fenêtre : mode opposé, posée dessous")
slash("windows 9")
assert(#db.windows == 4)
slash("windows 2")
assert(#db.windows == 2 and not ForeverMeterFrame3.shown and not ForeverMeterFrame4.shown)
slash("mode damage")
assert(db.windows[1].mode == "damage" and w1.title.text:find("Dégâts"), w1.title.text)
slash("mode threat")
assert(w1.title.text:find("Menace") and w1.bars[1].left.text == "> Moi", w1.title.text .. " / " .. tostring(w1.bars[1].left.text))
slash("mode deaths")
assert(w1.bars[1].right.text == "2.0k · 0:42", w1.bars[1].right.text)
slash("report 2")
slash("debug")
slash("lang enUS")
assert(w1.title.text:find("Deaths") and w1.resetButton.text == "Reset" and ForeverMeterFrame2.menuButton.text == "Menu")
slash("lang auto")
slash("rows 3"); slash("width 300"); slash("scale 1.2"); slash("warn 80"); slash("sound"); slash("pets"); slash("lock"); slash("unlock")
slash("toggle"); assert(not w1.shown and not ForeverMeterFrame2.shown)
ForeverMeter_Toggle(); assert(w1.shown and ForeverMeterFrame2.shown)
slash("aide")

-- Tooltip : mode dégâts, survol des barres
slash("mode damage")
local bar = w1.bars[1]
bar.scripts.OnEnter(bar)
assert(GameTooltip.text == "Moi" and #GameTooltip.texts == 3 and GameTooltip.texts[1]:find("Sort1 | 1.2k"), table.concat(GameTooltip.texts, " ; "))
GameTooltip.texts = {}
w1.bars[2].scripts.OnEnter(w1.bars[2])
assert(GameTooltip.text == "Bob" and GameTooltip.texts[2]:find("Sort2 | "), table.concat(GameTooltip.texts, " ; "))
bar.scripts.OnLeave(bar)
-- Tooltip mode dégâts subis : nom de créature affiché
slash("mode taken"); GameTooltip.texts = {}
bar.scripts.OnEnter(bar)
assert(GameTooltip.texts[2]:find("Sort2 · Ogre"), GameTooltip.texts[2])
-- Tooltip mode morts : recap
slash("mode deaths"); GameTooltip.texts = {}
bar.scripts.OnEnter(bar)
assert(#GameTooltip.texts == 2 and GameTooltip.texts[1] == "-2.0s  Sort5 (Ogre) | -900  100" and GameTooltip.texts[2] == "0.0s  Frappe | -200  0", table.concat(GameTooltip.texts, " ; "))
GameTooltip.texts = {}
w1.bars[2].scripts.OnEnter(w1.bars[2])
assert(GameTooltip.texts[1] == NS.L.TIP_NO_RECAP, GameTooltip.texts[1])

-- Clic sur une barre : fenêtre de détail, partagée entre fenêtres
slash("mode damage")
bar.scripts.OnMouseUp(bar)
local d = ForeverMeterDetailFrame
assert(d.shown and w1.selectedGuid == "Player-player" and d.title.text == "Moi : Dégâts", tostring(d.title.text))
assert(d.bars[1].left.text == "Sort1" and d.bars[1].right.text == "1.2k (3/s, 60.0%)", d.bars[1].right.text)
local w2 = ForeverMeterFrame2
w2.bars[2].scripts.OnMouseUp(w2.bars[2])
assert(d.shown and w1.selectedGuid == nil and w2.selectedGuid == "Player-bob" and d.title.text:find("Bob"), "détail passe à la fenêtre 2")
w2.bars[2].scripts.OnMouseUp(w2.bars[2])
assert(not d.shown and w2.selectedGuid == nil)
bar.scripts.OnMouseUp(bar); assert(d.shown)
d.close.scripts.OnClick(); assert(not d.shown and w1.selectedGuid == nil)

-- Menu : entrées, verrou, nouvelle fenêtre, fermeture
w1.menuButton.scripts.OnClick(w1.menuButton)
local function Entry(text) for _, e in ipairs(LAST_MENU) do if e[2] == text then return e end end end
-- CreateButton(text, func) : func en position 3 ; radio/checkbox : en position 4.
local function Call(text) local e = assert(Entry(text), text); return (e[1] == "CreateButton" and e[3] or e[4])() end
assert(Entry("Dégâts")[3]() == true and Entry("Ogre") and Entry("Verrouiller la position")[1] == "CreateCheckbox")
assert(Entry("Verrouiller la position")[3]() == false); Entry("Verrouiller la position")[4](); assert(db.locked == true)
Call("Nouvelle fenêtre"); assert(#db.windows == 3 and ForeverMeterFrame3.shown)
ForeverMeterFrame3.menuButton.scripts.OnClick(ForeverMeterFrame3.menuButton)
Call("Fermer cette fenêtre"); assert(#db.windows == 2 and not ForeverMeterFrame3.shown)
w2.menuButton.scripts.OnClick(w2.menuButton)
Call("Soins"); assert(db.windows[2].mode == "heal" and w2.title.text:find("Soins"))
Call("Ogre"); assert(db.windows[2].view == 12 and w2.title.text:find("Ogre"), w2.title.text)
Call("Global"); assert(db.windows[2].view == "overall")
w1.menuButton.scripts.OnClick(w1.menuButton)
Call("Remise à zéro"); assert(calls.reset == 1 and db.windows[2].view == "current")
-- Clic gauche titre = mode suivant ; molette
w1.header.scripts.OnClick(w1.header, "LeftButton"); assert(db.windows[1].mode == "heal")
w1.scripts.OnMouseWheel(w1, -1); assert(w1.scrollOffset == 0, "2 sources, 3 lignes : pas de défilement")
w1.header.scripts.OnDragStop(); assert(db.windows[1].point[4] == 10)

-- Événements restants
Fire("GROUP_ROSTER_UPDATE"); Fire("PLAYER_REGEN_ENABLED"); Fire("PLAYER_ENTERING_WORLD"); Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
w2.cfg.view = 12; Fire("DAMAGE_METER_RESET"); assert(w2.cfg.view == "current")

-- Combat : valeurs secrètes, pas de tri ni d'arithmétique
secretMode = true
eventsFrame.scripts.OnUpdate(eventsFrame, 1)
assert(w1.bars[1].right.text == "2000 (200.0/s)", w1.bars[1].right.text)
bar.scripts.OnEnter(bar)
w1.bars[2].scripts.OnMouseUp(w1.bars[2]) -- GUID d'autrui secret : message chat, pas de détail
assert(w1.selectedGuid == nil)
slash("report"); slash("mode deaths"); bar.scripts.OnEnter(bar)
secretMode = false

-- defaults, puis /reload simulé (config sauvegardée avec 2 fenêtres, vue numérique)
slash("defaults"); assert(#db.windows == 1 and db.windows[1].mode == "damage" and db.locked == false)
print("uicheck OK")
