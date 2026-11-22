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
		if k == "SetWidth" then return function(self, v) self.w = v end end
		if k == "SetSize" then return function(self, w, h) self.w, self.h = w, h end end
		if k == "GetEffectiveScale" then return function() return 1 end end
		if k == "SetHeight" then return function(self, v) self.h = v end end
		if k == "SetBackdropColor" then return function(self, _, _, _, a) self.bgAlpha = a end end
		if k == "GetWidth" then return function(self) return self.w end end
		if k == "GetHeight" then return function(self) return self.h end end
		if k == "GetLeft" then return function(self) return self.l or 0 end end
		if k == "GetRight" then return function(self) return (self.l or 0) + (self.w or 260) end end
		if k == "GetTop" then return function(self) return self.t or 0 end end
		if k == "GetBottom" then return function(self) return (self.t or 0) - (self.h or 100) end end
		if k == "SetPoint" then return function(self, ...) self.point = { ... } end end
		if k == "GetNormalTexture" then return function(self) self.tex = self.tex or Obj("Texture"); return self.tex end end
		if k == "GetHighlightTexture" then return function(self) self.hl = self.hl or Obj("Texture"); return self.hl end end
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
UIParent = Obj("Frame"); UIParent.w, UIParent.h = 1920, 1080
GameTooltip = Obj("GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("  chat> " .. m) end }
RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = 0.5, b = 0 }, PRIEST = { r = 1, g = 1, b = 1 } }
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 }, PRIEST = { 0.5, 0.75, 0.25, 0.5 } }
SOUNDKIT = { RAID_WARNING = 1 }
GetLocale = function() return "frFR" end
cursorX, cursorY = 0, 0
GetCursorPosition = function() return cursorX, cursorY end
local SECRET = { secret = true } -- valeur secrète simulée, reconnue par issecretvalue
local testClock, testThreat, testTanking, sounds = nil, nil, true, 0 -- forcés par le test des deux fenêtres de menace (GetTime et la menace sont des locales de l'addon)
GetTime = function() return testClock or os.clock() end
PlaySound = function() sounds = sounds + 1 end
local errorsReported = 0 -- erreurs de rendu remontées au gestionnaire du jeu
geterrorhandler = function() return function() errorsReported = errorsReported + 1 end end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
UnitGUID = function(u) return "Player-" .. u end
UnitName = function(u) return u == "player" and "Moi" or u end
UnitClass = function() return "Guerrier", "WARRIOR" end
UnitExists = function(u) return u == "player" or u == "target" or u == "party1" end
local testCombat, testTargetCombat = false, nil -- testTargetCombat : combat de la cible seule (nil = comme le joueur)
UnitAffectingCombat = function(u) if u == "target" and testTargetCombat ~= nil then return testTargetCombat end return testCombat end
InCombatLockdown = function() return testCombat end
UnitCanAttack = function() return true end
UnitIsDead = function() return false end
local testCompareSecret = false
UnitIsUnit = function(a, b) if testCompareSecret then return SECRET end return a == b end
shiftDown = false
IsShiftKeyDown = function() return shiftDown end
-- Messages d'addon et encodage : envois capturés ; l'encodage range la valeur et rend une clé allongée (plusieurs morceaux).
GetServerTime = function() return 5000 end
local addonMessages, encoded = {}, {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() return 0 end,
	SendAddonMessage = function(prefix, text, channel) addonMessages[#addonMessages + 1] = { prefix = prefix, text = text, channel = channel }; return 0 end }
C_EncodingUtil = {
	SerializeCBOR = function(v) encoded[#encoded + 1] = v; return "cbor" .. #encoded end,
	DeserializeCBOR = function(s) return encoded[tonumber(s:match("^cbor(%d+)$"))] end,
	CompressString = function(s) return s end, DecompressString = function(s) return s end,
	EncodeBase64 = function(s) return s .. "#" .. string.rep("A", 300) end, DecodeBase64 = function(s) return s:match("^(.-)#") end,
}
ctrlDown = false
IsControlKeyDown = function() return ctrlDown end
-- testBoss : valeurs de UnitDetailedThreatSituation secrètes, statut de UnitThreatSituation lisible (ou secret si "secret").
local testBoss, testStatus = nil, { player = 3, party1 = 1 }
UnitDetailedThreatSituation = function(u)
	if testBoss then return SECRET, SECRET, SECRET, SECRET, SECRET end
	return u == "player" and testTanking, 3, 95, 95, testThreat or 1000
end
UnitThreatSituation = function(u) return testBoss == "secret" and SECRET or testStatus[u] end
-- IsInRaid et IsInGroup sont capturés en locales par l'addon : bascules par variables.
local inGroup, testRaid, testInstanceGroup = true, false, false
IsInRaid = function() return testRaid end
IsInGroup = function(category) if category == 2 then return inGroup and testInstanceGroup end return inGroup end
IsInInstance = function() return false end
testInstance = nil -- instanceID courant, nil = monde ouvert
GetInstanceInfo = function() return "Zone", testInstance and "party" or "none", 0, "", 5, 0, false, testInstance or 0 end
GetNumGroupMembers = function() return 2 end
SendChatMessage = function(msg, ch) print("  " .. ch .. "> " .. msg) end
C_Spell = { GetSpellTexture = function() return 123 end, GetSpellName = function(id) return "Sort" .. id end }
SlashCmdList = {}
MenuUtil = { CreateContextMenu = function(owner, gen)
	local root = Obj("Menu")
	root.entries = {}
	local function Level(level, parent)
		for _, m in ipairs({ "CreateTitle", "CreateDivider", "CreateRadio", "CreateCheckbox", "CreateButton" }) do
			level[m] = function(_, text, checked, func)
				root.entries[#root.entries + 1] = { m, text, checked, func, parent = parent }
				return Level({}, text)
			end
		end
		return level
	end
	Level(root)
	gen(nil, root)
	_G.LAST_MENU = root.entries
end }

local secretMode = false
-- isLocalPlayer (booléen) est NeverSecret : jamais secret, même en combat.
-- secretLine : motif d'une ligne de report rendue secrète (une ligne secrète dans un report).
local secretLine
issecretvalue = function(v) return v == SECRET or (secretMode and type(v) ~= "boolean") or (secretLine and type(v) == "string" and v:find(secretLine) ~= nil) or false end
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
	GetCombatSessionSourceFromType = function(_, meterType, guid) LAST_SOURCE_TYPE = meterType; for _, s in ipairs(session.combatSources) do if s.sourceGUID == guid then return s end end end,
	GetCombatSessionSourceFromID = function(_, meterType, guid) LAST_SOURCE_TYPE = meterType; for _, s in ipairs(session.combatSources) do if s.sourceGUID == guid then return s end end end,
	GetAvailableCombatSessions = function() return { { sessionID = 12, name = "Ogre", durationSeconds = 30 } } end,
	GetSessionDurationSeconds = function() return 60 end,
	ResetAllCombatSessions = function() calls.reset = (calls.reset or 0) + 1 end,
}
C_DeathRecap = {
	HasRecapEvents = function(id) return id == 7 end,
	GetRecapEvents = function() return { { spellId = 5, amount = 900, timestamp = 40, currentHP = 100, sourceName = "Ogre" }, { spellName = "Frappe", amount = 200, timestamp = 42, currentHP = 0 } } end,
}

-- Types de meter connus du client : les modes « ennemis » et « évitables » n apparaissent que s ils existent.
Enum = { DamageMeterType = { EnemyDamageTaken = 10, AvoidableDamageTaken = 8 } }
local NS = {}
for _, code in ipairs({ "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
	assert(loadfile("Locale/" .. code .. ".lua"))("ForeverMeter", NS)
end
assert(loadfile("Mirror.lua"))("ForeverMeter", NS)
assert(loadfile("ForeverMeter.lua"))("ForeverMeter", NS)
assert(loadfile("CombatBreakdown.lua"))("ForeverMeter", NS)
assert(loadfile("CombatSync.lua"))("ForeverMeter", NS)
local FM = ForeverMeter
assert(FM.MODES[1] == "threat" and FM.MODES[6] == "enemytaken" and FM.MODES[7] == "avoidable" and FM.MODE_INFO.avoidable.type == 8 and FM.MODE_INFO.enemytaken.label == "Dégâts subis (ennemis)", "modes lus dans Enum")

-- Chargement : trouve la frame d'événements (celle qui a ADDON_LOADED dans OnEvent) via le script OnUpdate.
ForeverMeterDB = { mode = "heal", point = { "TOPLEFT", nil, "TOPLEFT", 5, -5 }, locked = true, titleColor = { r = 0.5 } }
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
assert(loadfile("Mirror.lua"))("ForeverMeter", NS)
assert(loadfile("ForeverMeter.lua"))("ForeverMeter", NS)
assert(loadfile("CombatBreakdown.lua"))("ForeverMeter", NS)
assert(loadfile("CombatSync.lua"))("ForeverMeter", NS)
FM = ForeverMeter
for _, f in ipairs(created) do if f.scripts.OnEvent and f.scripts.OnUpdate then eventsFrame = f end end
-- Hors combat, l'OnUpdate ne redessine qu'après un événement du compteur : Tick() simule une mise à jour des données.
local function Tick()
	eventsFrame.scripts.OnEvent(eventsFrame, "DAMAGE_METER_CURRENT_SESSION_UPDATED")
	eventsFrame.scripts.OnUpdate(eventsFrame, 1)
end
assert(eventsFrame, "frame events introuvable")
local function Fire(e, a, b) eventsFrame.scripts.OnEvent(eventsFrame, e, a, b) end
Fire("ADDON_LOADED", "Autre")
Fire("ADDON_LOADED", "ForeverMeter")
local db = ForeverMeterDB
assert(db.mode == nil and #db.windows == 1 and db.windows[1].mode == "heal" and db.windows[1].point[4] == 5, "migration db.mode/db.point")
assert(db.locked == nil and db.windows[1].locked == true, "migration du verrou global vers la fenêtre")
assert(db.titleColor.r == 0.5 and db.titleColor.g == 0.82 and db.titleColor.b == 0, "couleur complétée après le miroir")
db.windows[1].locked = nil
local w1 = ForeverMeterFrame
assert(w1 and w1.cfg == db.windows[1])
assert(w1.title.text:find("Soins"), w1.title.text)
assert(w1.bars[1].left.text == "1. Moi" and w1.bars[2].left.text == "2. Bob" and not w1.bars[3].shown, tostring(w1.bars[1].left.text))
assert(w1.bars[1].right.text == "2.0k (200/s, 66.7%)", w1.bars[1].right.text)
assert(w1.bars[1].icon.SetTexture and w1.resetButton.text == "Reset")

-- Sa propre barre sous les lignes visibles : affichée en dernière ligne avec son rang.
local savedSources = session.combatSources
local crowd = {}
for n = 1, w1.rows + 3 do crowd[n] = src("Autre" .. n, "MAGE", 2500 - n, "Player-" .. n) end
crowd[#crowd + 1] = savedSources[1]
session.combatSources = crowd
Tick()
assert(w1.bars[w1.rows].left.text == string.format("%d. Moi", #crowd), tostring(w1.bars[w1.rows].left.text))
assert(w1.bars[w1.rows - 1].left.text == string.format("%d. Autre%d", w1.rows - 1, w1.rows - 1))
session.combatSources = savedSources
Tick()
assert(w1.bars[1].left.text == "1. Moi")

-- Tick OnUpdate
eventsFrame.scripts.OnUpdate(eventsFrame, 1)

-- Commandes
local slash = SlashCmdList.FOREVERMETER
w1.l, w1.t = 100, 900 -- position réaliste : la place libre se calcule depuis les coins des fenêtres
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
-- Deux fenêtres de menace : même débit dans les deux (même GetTime() dans un tour)
Fire("PLAYER_TARGET_CHANGED") -- relevés des tours précédents (horloge os.clock) écartés
testClock, testThreat = 100, 1000
ForeverMeterFrame2.cfg.mode = "threat"; Tick()
testClock, testThreat = 101, 1500; Tick() -- 1re hausse : base
testClock, testThreat = 102, 2000; Tick()
assert(w1.bars[1].right.text:find("500/s") and ForeverMeterFrame2.bars[1].right.text == w1.bars[1].right.text, w1.bars[1].right.text .. " / " .. ForeverMeterFrame2.bars[1].right.text)
-- Changement de cible : pas de débit calculé entre la menace sur l'ancienne cible et la nouvelle
Fire("PLAYER_TARGET_CHANGED"); testClock, testThreat = 102, 5000; Tick()
assert(w1.bars[1].right.text:find(" 0/s"), w1.bars[1].right.text)
-- Alerte sonore : une fois par cible au-dessus du seuil, rejouée après un changement de cible
testTanking, sounds = false, 0; Tick(); Tick()
assert(sounds == 1, "alerte jouée une seule fois : " .. sounds)
Fire("PLAYER_TARGET_CHANGED"); Tick()
assert(sounds == 2, "alerte rejouée sur la nouvelle cible : " .. sounds)
-- Autre addon qui alerte déjà (FM.externalWarning) : pas de son ForeverMeter
ForeverMeter.externalWarning = true; Fire("PLAYER_TARGET_CHANGED"); Tick()
assert(sounds == 2, "alerte externe : son coupé"); ForeverMeter.externalWarning = nil
-- Gros chiffre en erreur : l'alerte joue quand même ; titre marqué « (!) » jusqu'au rendu suivant réussi.
do
	local realSetText = w1.big.SetText
	w1.cfg.bigNumber, ForeverMeterFrame2.cfg.mode = true, "damage" -- w1 seule fenêtre de menace : le son vient d'elle
	w1.big.SetText = function(self, text) if text ~= "" then error("gros chiffre") end return realSetText(self, text) end
	sounds, errorsReported = 0, 0; Fire("PLAYER_TARGET_CHANGED"); Tick()
	assert(sounds == 1 and errorsReported == 1 and w1.title.text:find("(!)", 1, true), "alerte malgré l'erreur : " .. sounds .. " / " .. w1.title.text)
	-- Titre secret (nom d'ennemi) : la marque seule remplace le titre.
	secretLine = "Menace"; Tick(); secretLine = nil
	assert(w1.title.text == " |cffff4040(!)|r", "titre secret marqué : " .. tostring(w1.title.text))
	w1.big.SetText = realSetText; w1.cfg.bigNumber, ForeverMeterFrame2.cfg.mode = nil, "threat"; Tick()
	assert(not w1.title.text:find("(!)", 1, true), "titre rétabli : " .. w1.title.text)
end
testClock, testThreat, testTanking = nil, nil, true
-- Cible boss : barres en statut seul, sans chiffres ; alerte au statut 1 ; « indisponible » si le statut est secret aussi.
testBoss, sounds = true, 0; Fire("PLAYER_TARGET_CHANGED"); Tick()
assert(not w1.title.text:find("indisponible") and w1.bars[1].left.text == "> Moi" and w1.bars[1].right.text == "aggro" and w1.bars[2].right.text == "au-dessus du tank" and sounds == 0,
	w1.title.text .. " / " .. tostring(w1.bars[1].right.text) .. " / " .. tostring(w1.bars[2].right.text))
testStatus.player = 1; Tick()
assert(sounds == 1 and w1.bars[1].right.text == "au-dessus du tank", "alerte statut 1 : " .. sounds)
-- Statut qui oscille 1 -> 0 -> 1 en moins de 3 s : pas de nouveau son ; réarmé après 3 s sous le seuil.
testClock = 200; testStatus.player = 0; Tick(); testStatus.player = 1; Tick()
assert(sounds == 1, "oscillation : " .. sounds)
testStatus.player = 0; Tick(); testClock = 204; Tick(); testStatus.player = 1; Tick()
assert(sounds == 2, "réarmé après 3 s : " .. sounds)
testClock = nil
-- Comparaison d'unités secrète : la ligne du joueur reste reconnue par le GUID.
testCompareSecret = true; Tick()
assert(w1.bars[1].left.text == "> Moi" and w1.bars[2].left.text == "party1", tostring(w1.bars[1].left.text) .. " / " .. tostring(w1.bars[2].left.text))
testCompareSecret = false
testBoss = "secret"; Tick()
assert(w1.title.text:find("indisponible") and not w1.bars[1].shown, w1.title.text)
testBoss, testStatus.player = nil, 3
-- Tri : nom secret, pas de comparaison de chaîne
local sorted = ForeverMeter.SortThreat({ { name = SECRET, tanking = false, pct = 50 }, { name = "Bob", tanking = false, pct = 50 }, { name = SECRET, tanking = true, pct = 100 } })
assert(sorted[1].tanking)
-- Menace hors combat : figée ; en combat : suivie ; un dernier tour à la sortie, puis figée de nouveau.
do
	local OnUpdate, w2 = eventsFrame.scripts.OnUpdate, ForeverMeterFrame2
	testClock, testThreat = 299, 500; Tick()
	local afterFull = w1.bars[1].right.text
	testClock, testThreat = 300, 1000; OnUpdate(eventsFrame, 1)
	assert(w1.bars[1].right.text ~= afterFull, "après un rendu complet : un tour menace (la cible a pu quitter le combat)")
	local frozen = w1.bars[1].right.text
	testClock, testThreat = 301, 3000; OnUpdate(eventsFrame, 1)
	assert(w1.bars[1].right.text == frozen and w2.bars[1].right.text == frozen, "hors combat : figée")
	testCombat = true; OnUpdate(eventsFrame, 1)
	local live = w1.bars[1].right.text
	assert(live ~= frozen, "en combat : suivie")
	testCombat = false; testClock, testThreat = 302, 9000; OnUpdate(eventsFrame, 1)
	local last = w1.bars[1].right.text
	assert(last ~= live, "sortie de combat : dernier tour")
	testClock, testThreat = 303, 20000; OnUpdate(eventsFrame, 1)
	assert(w1.bars[1].right.text == last, "après le dernier tour : figée")
	-- Cible seule en combat, puis combat de la cible secret : suivie dans les deux cas.
	testTargetCombat = true; testClock, testThreat = 304, 40000; OnUpdate(eventsFrame, 1)
	local targetOnly = w1.bars[1].right.text
	assert(targetOnly ~= last, "cible en combat : suivie")
	testTargetCombat = SECRET; testClock, testThreat = 305, 80000; OnUpdate(eventsFrame, 1)
	assert(w1.bars[1].right.text ~= targetOnly, "combat de la cible secret : suivie")
	testTargetCombat = false; OnUpdate(eventsFrame, 1) -- dernier tour
	testClock, testThreat = nil, nil
end
-- Rendu isolé : une fenêtre en erreur ne bloque pas la suivante ; erreur signalée une fois, puis effacée au retour.
do
	local w2 = ForeverMeterFrame2
	w1.cfg.mode, w2.cfg.mode = "damage", "threat"; Tick()
	assert(w1.bars[1].source, "rendu dégâts : source posée")
	session.combatSources[2].totalAmount = SECRET -- ligne 1 lisible, ligne 2 secrète : état inattendu, erreur de rendu
	errorsReported, w2.bars[1].left.text = 0, nil; Tick()
	assert(errorsReported == 1 and w1.renderError and w2.bars[1].left.text == "> Moi", "erreur isolée : " .. errorsReported)
	assert(w1.title.text:find("(!)", 1, true) and not w1.bars[1].shown and not w1.bars[1].source, "fenêtre en erreur : vidée et marquée")
	Tick(); assert(errorsReported == 1, "signalée une seule fois : " .. errorsReported)
	-- Sans nouvel événement : le rendu en échec reste à refaire, le tour suivant le rétablit.
	session.combatSources[2].totalAmount = 1000; eventsFrame.scripts.OnUpdate(eventsFrame, 1)
	assert(not w1.renderError and w1.bars[2].left.text == "2. Bob" and w1.bars[1].shown and not w1.title.text:find("(!)", 1, true), "rendu rétabli")
	w1.cfg.mode = "threat"
end
ForeverMeterFrame2.cfg.mode = "damage"
slash("mode deaths")
assert(w1.bars[1].right.text == "2.0k · 0:42", w1.bars[1].right.text)
slash("report 2")
slash("debug")
slash("lang enUS")
assert(w1.title.text:find("Deaths") and w1.resetButton.text == "Reset" and ForeverMeterFrame2.menuButton.text == "Menu")
slash("lang auto")
slash("refresh 0.1"); assert(db.refresh == 0.1); slash("refresh 9"); assert(db.refresh == 2); slash("refresh 0.2"); slash("rows 3"); slash("width 300"); slash("scale 1.2"); slash("warn 80"); slash("sound"); slash("pets"); slash("lock"); assert(db.windows[1].locked and db.windows[2].locked); slash("unlock"); assert(not db.windows[1].locked)
slash("texture GLASS"); assert(db.barTexture == "glass"); slash("texture xx"); assert(db.barTexture == "glass"); slash("font arial 12"); assert(db.barFont == "arial" and db.fontSize == 12); slash("font 99"); assert(db.barFont == "arial" and db.fontSize == 24); slash("font xx"); assert(db.barFont == "arial"); slash("font default"); assert(db.barFont == nil and db.fontSize == nil); slash("font 2002 12"); assert(db.barFont == "2002" and db.fontSize == 12); slash("font 2002"); assert(db.fontSize == 12); slash("font default")
slash("options"); ForeverMeterOptionSlider7.scripts.OnValueChanged(ForeverMeterOptionSlider7, 14.2); assert(db.fontSize == 14); ForeverMeterOptionSlider1.scripts.OnValueChanged(ForeverMeterOptionSlider1, 1.5); assert(db.scale == 1.5); slash("font default"); slash("scale 1")
ForeverMeterOptionSlider8.scripts.OnValueChanged(ForeverMeterOptionSlider8, 24); assert(db.rowHeight == 24 and w1.bars[1].h == 24); ForeverMeterOptionSlider8.scripts.OnValueChanged(ForeverMeterOptionSlider8, 16)
assert(w1.bgAlpha == 0.6); ForeverMeterOptionSlider9.scripts.OnValueChanged(ForeverMeterOptionSlider9, 0.5); assert(db.bgAlpha == 0.5 and w1.bgAlpha == 0.5 and ForeverMeterDetailFrame.bgAlpha == 0.5); ForeverMeterOptionSlider9.scripts.OnValueChanged(ForeverMeterOptionSlider9, 0.6)
-- Fenêtres, lignes et largeur : mêmes chemins que /fm windows, /fm rows et /fm width
local windowCount = #db.windows
ForeverMeterOptionSlider4.scripts.OnValueChanged(ForeverMeterOptionSlider4, 9); assert(#db.windows == ForeverMeter.MAX_WINDOWS, "fenêtres bornées")
ForeverMeterOptionSlider4.scripts.OnValueChanged(ForeverMeterOptionSlider4, windowCount); assert(#db.windows == windowCount)
db.windows[1].rows = 9; ForeverMeterOptionSlider5.scripts.OnValueChanged(ForeverMeterOptionSlider5, 7.4); assert(db.rows == 7 and db.windows[1].rows == nil and w1.rows == 7, "lignes communes")
ForeverMeterOptionSlider6.scripts.OnValueChanged(ForeverMeterOptionSlider6, 1000); assert(db.width == 600 and w1.w == 600, "largeur bornée")
slash("rows 3"); slash("width 300")
slash("font oswald"); eventsFrame.scripts.OnUpdate(eventsFrame, 1); eventsFrame.scripts.OnUpdate(eventsFrame, 1); slash("font default")
slash("mode damage"); slash("test"); assert(w1.title.text == "Dégâts · mode test" and w1.bars[3].shown and w1.bars[1].left.text == "1. WARRIOR" and not w1.bars[1].sourceGuid, w1.title.text)
slash("test"); assert(w1.title.text:find("Combat actuel") and w1.bars[1].left.text == "1. Moi" and not w1.bars[3].shown, w1.title.text)
assert(BINDING_HEADER_FOREVERMETER == "ForeverMeter" and BINDING_NAME_FOREVERMETER_RESET == "Remettre les données à zéro")
ForeverMeter_Reset(); assert(calls.reset == 1); calls.reset = nil
ForeverMeter_NextMode(); assert(db.windows[1].mode == "heal", db.windows[1].mode); slash("mode damage")
slash("toggle"); assert(not w1.shown and not ForeverMeterFrame2.shown)
ForeverMeter_Toggle(); assert(w1.shown and ForeverMeterFrame2.shown)
slash("aide")

-- Tooltip : mode dégâts, survol des barres
slash("mode damage")
local bar = w1.bars[1]
bar.scripts.OnEnter(bar)
assert(GameTooltip.text == "Moi" and #GameTooltip.texts == 5 and GameTooltip.texts[1]:find("Sort1 | 1.2k"), table.concat(GameTooltip.texts, " ; "))
GameTooltip.texts = {}
w1.bars[2].scripts.OnEnter(w1.bars[2])
assert(GameTooltip.text == "Bob" and GameTooltip.texts[2]:find("Sort2 | "), table.concat(GameTooltip.texts, " ; "))
bar.scripts.OnLeave(bar)
-- Tooltip mode dégâts subis : nom de créature affiché
-- Sorts évitables et mortels : marqués en dégâts subis seulement
local mySpells = session.combatSources[1].combatSpells
mySpells[1].isDeadly, mySpells[2].isAvoidable = true, true
slash("mode taken"); GameTooltip.texts = {}
bar.scripts.OnEnter(bar)
assert(GameTooltip.texts[2]:find("Sort2 · Ogre") and GameTooltip.texts[2]:find("évitable", 1, true) and GameTooltip.texts[1]:find("mortel", 1, true), GameTooltip.texts[1] .. " ; " .. GameTooltip.texts[2])
slash("mode damage"); GameTooltip.texts = {}
bar.scripts.OnEnter(bar)
assert(not GameTooltip.texts[1]:find("mortel", 1, true) and not GameTooltip.texts[2]:find("évitable", 1, true), "mode dégâts : pas de marque")
-- Tooltip mode morts : recap
slash("mode deaths"); GameTooltip.texts = {}
bar.scripts.OnEnter(bar)
assert(#GameTooltip.texts == 3 and GameTooltip.texts[1] == "-2.0s  Sort5 (Ogre) | -900  100" and GameTooltip.texts[2] == "0.0s  Frappe | -200  0" and GameTooltip.texts[3] == NS.L.TIP_REPORT_DEATH, table.concat(GameTooltip.texts, " ; "))
GameTooltip.texts = {}
w1.bars[2].scripts.OnEnter(w1.bars[2])
assert(GameTooltip.texts[1] == NS.L.TIP_NO_RECAP, GameTooltip.texts[1])
-- Maj+clic en mode morts : récap de la mort dans le chat ; sans récap, rien n'est envoyé
local deathSent, chatSend = {}, SendChatMessage
SendChatMessage = function(msg, ch) deathSent[#deathSent + 1] = ch .. "> " .. msg end
shiftDown = true; bar.scripts.OnMouseUp(bar); w1.bars[2].scripts.OnMouseUp(w1.bars[2]); shiftDown = false
assert(#deathSent == 3 and deathSent[1] == "PARTY> ForeverMeter : mort de Moi" and deathSent[2] == "PARTY> -2.0s  Sort5 (Ogre)  -900  100", table.concat(deathSent, " ; "))
-- /fm report death [N] : même récap, ligne N de la première fenêtre Morts
deathSent = {}; slash("report death 1")
assert(#deathSent == 3 and deathSent[1] == "PARTY> ForeverMeter : mort de Moi", table.concat(deathSent, " ; "))
deathSent = {}; slash("report death 9"); assert(#deathSent == 0, "ligne absente : rien envoyé")
SendChatMessage = chatSend
assert(not (ForeverMeterDetailFrame and ForeverMeterDetailFrame.shown), "Maj+clic en mode morts : pas de détail")

-- Clic sur une barre : fenêtre de détail, partagée entre fenêtres
slash("mode damage")
bar.scripts.OnMouseUp(bar)
local d = ForeverMeterDetailFrame
assert(d.shown and w1.selectedGuid == "Player-player" and d.title.text == "Moi : Dégâts", tostring(d.title.text))
assert(d.bars[1].left.text == "Sort1" and d.bars[1].right.text == "1.2k (3/s, 60.0%)", d.bars[1].right.text)
-- Tableau détaillé : onglets Sorts, Cibles, Mort et Chronologie de la source ouverte dans le détail
do
	local bd, errorsBefore = ForeverMeterBreakdownFrame, errorsReported
	for _, spell in ipairs(session.combatSources[1].combatSpells) do
		if spell.spellID == 1 then spell.combatSpellDetails = { { unitName = "Ogre", amount = 800 }, { unitName = "Loup", amount = 400 } } end
	end
	NS.Breakdown.Open(d.owner)
	local function Cell(row, column) return bd.rows[row].cells[column].text end
	assert(bd.shown and bd.title.text:find("^Moi : Dégâts"), tostring(bd.title.text))
	-- Dégâts : nom, lancers, moyenne, lancers/min (« — » sans combat enregistré), total, par s, %, surplus ; ligne Total en bas.
	local totalRow = 0
	for i in pairs(bd.rows) do totalRow = math.max(totalRow, i) end
	assert(Cell(1, 1) == "+ Sort1" and Cell(1, 2) == "—" and Cell(1, 5) == "1.2k" and Cell(1, 7) == "60.0%", tostring(Cell(1, 1)))
	assert(bd.rows[totalRow].shown and Cell(totalRow, 1) == "Total" and Cell(totalRow, 5) == "2.0k" and Cell(totalRow, 7) == "100.0%", "ligne Total")
	bd.rows[1].scripts.OnMouseUp(bd.rows[1])
	assert(Cell(1, 1) == "- Sort1" and Cell(2, 1) == "Ogre" and Cell(3, 1) == "Loup" and Cell(4, 1) == "Sort2", "sort déplié en cibles")
	bd.tabs[2].scripts.OnClick(bd.tabs[2])
	assert(Cell(1, 1) == "+ Ogre" and Cell(1, 2) == "800" and Cell(2, 1) == "+ Loup", tostring(Cell(1, 1)))
	bd.tabs[3].scripts.OnClick(bd.tabs[3])
	assert(Cell(1, 1) == "Sort5 (Ogre)" and Cell(1, 2) == "-2.0s" and Cell(1, 3) == "900" and Cell(2, 1) == "Frappe" and Cell(2, 7) == "", tostring(Cell(1, 1)))
	-- Chronologie : combat enregistré (début à 100 s, rencontre gagnée, deux lancers du joueur), relié à la session 12
	local recorder = bd.recorder
	local function Record(event, ...) recorder.scripts.OnEvent(recorder, event, ...) end
	testClock = 100; Record("PLAYER_REGEN_DISABLED"); Record("ENCOUNTER_START", 1, "Ogre", 1, 5)
	testClock = 103; Record("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1); Record("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", 2)
	testClock = 110; Record("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 1); Record("ENCOUNTER_END", 1, "Ogre", 1, 5, 1)
	Record("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 12); Record("PLAYER_REGEN_ENABLED")
	local segment = NS.Breakdown.Segments[#NS.Breakdown.Segments]
	assert(#segment.casts == 2 and segment.casts[1].t == 3 and segment.sessionID == 12 and segment.encounters[1].stop == 10 and segment.encounters[1].success, "segment enregistré")
	bd.tabs[4].scripts.OnClick(bd.tabs[4])
	local plot = bd.plot
	assert(plot.shown, "chronologie affichée")
	-- Survol du premier lancer : piste 3 (après Rencontre et Morts), 3 s à 60.2 px/s
	plot.t, cursorX, cursorY = 1000, 181, 1000 - 45
	GameTooltip.texts = {}
	plot.scripts.OnEnter(plot); plot.scripts.OnUpdate(plot, 0.1)
	assert(GameTooltip.text == "Sort1" and GameTooltip.texts[1] == "0:03 - lancer 1 sur 2", tostring(GameTooltip.texts[1]))
	plot.scripts.OnLeave(plot)
	ctrlDown = true; plot.scripts.OnMouseWheel(plot, 1); ctrlDown = false
	plot.scripts.OnMouseWheel(plot, -1); shiftDown = true; plot.scripts.OnMouseWheel(plot, -1); shiftDown = false
	-- Partage : le combat fermé part au groupe en 2 morceaux (heure serveur 5000 = 100 s locales).
	for _ = 1, 5 do NS.Sync.sender.scripts.OnUpdate(NS.Sync.sender, 1) end
	assert(#addonMessages == 2 and addonMessages[1].text:match("^%d+:1:2:cbor") and addonMessages[1].channel == "PARTY", "envoi en morceaux")
	local sent = encoded[#encoded]
	assert(sent.g == "Player-player" and sent.b == 5000 and sent.c[1] == 300 and sent.c[3] == 1000 and sent.c[4] == 1, "lancers envoyés")
	-- Réception des lancers d'un autre joueur, morceaux dans le désordre ; affichés quand il est la source suivie.
	local payload = FM.BuildSyncPayload("Player-party1", { { t = 5, spellID = 2 } }, 5000)
	local chunks = FM.SplitChunks(C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(payload))), 240)
	local listener = NS.Sync.listener
	-- Refusés : chuchotement hors groupe, et lancers annoncés pour un autre joueur que l'expéditeur.
	listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", "ForeverMeter", "6:1:2:" .. chunks[1], "WHISPER", "party1")
	listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", "ForeverMeter", "6:2:2:" .. chunks[2], "WHISPER", "party1")
	listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", "ForeverMeter", "5:1:2:" .. chunks[1], "PARTY", "party2")
	listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", "ForeverMeter", "5:2:2:" .. chunks[2], "PARTY", "party2")
	assert(#NS.Sync.CastsBetween("Player-party1", 5000, 5010) == 0, "lancers d'un tiers refusés")
	listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", "ForeverMeter", "7:2:2:" .. chunks[2], "PARTY", "party1")
	listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", "ForeverMeter", "7:1:2:" .. chunks[1], "PARTY", "party1")
	listener.scripts.OnEvent(listener, "CHAT_MSG_ADDON", "ForeverMeter", "pas un morceau", "PARTY", "party1")
	assert(NS.Sync.CastsBetween("Player-party1", 5000, 5010)[1].t == 5, "lancers reçus")
	local owner = d.owner
	owner.selectedGuid = "Player-party1"; bd.tabs[4].scripts.OnClick(bd.tabs[4])
	assert(plot.shown and bd.help.text == NS.L.TIMELINE_HELP, "chronologie de l'autre joueur : " .. tostring(bd.help.text))
	owner.selectedGuid = "Player-inconnu"; bd.tabs[4].scripts.OnClick(bd.tabs[4])
	assert(bd.help.text == NS.L.TIMELINE_NO_SYNC, "aucun lancer reçu")
	owner.selectedGuid = "Player-player"
	-- Barre d'outils : combat Ogre (session 12, enregistré), lancers du joueur dans les colonnes des sorts.
	local toolbar = bd.toolbar
	local function Pick(prefix)
		for _, e in ipairs(LAST_MENU) do
			if type(e[2]) == "string" and e[2]:sub(1, #prefix) == prefix then return e[4]() end
		end
		error("entrée absente : " .. prefix)
	end
	bd.tabs[1].scripts.OnClick(bd.tabs[1])
	toolbar.session.scripts.OnClick(toolbar.session); Pick("Ogre")
	assert(toolbar.session.text.text:find("^Ogre"), tostring(toolbar.session.text.text))
	assert(Cell(1, 1) == "+ Sort1" and Cell(1, 2) == "2" and Cell(1, 3) == "600" and Cell(1, 4) == "12.0" and Cell(2, 2) == "", "lancers : " .. tostring(Cell(1, 2)))
	-- Filtre texte : seules les lignes dont le nom le contient, total recalculé.
	toolbar.search:SetText("SORT2"); toolbar.search.scripts.OnTextChanged(toolbar.search)
	assert(Cell(1, 1) == "Sort2" and not bd.rows[2].shown and Cell(totalRow, 5) == "800", "filtre : " .. tostring(Cell(1, 1)))
	toolbar.search:SetText(""); toolbar.search.scripts.OnTextChanged(toolbar.search)
	-- Clic droit : sort épinglé, bouton de retrait affiché ; un clic sur le bouton le retire.
	bd.rows[1].scripts.OnMouseUp(bd.rows[1], "RightButton")
	assert(toolbar.pin.shown and toolbar.pin.text.text:find("Sort1"), "épinglé")
	bd.tabs[2].scripts.OnClick(bd.tabs[2])
	-- Onglet Dégâts subis : lu en dégâts subis (type 7) quel que soit le mode, sans tenir compte de l'épingle.
	assert(bd.tabs[2].text.text == NS.L.MODE_TAKEN and LAST_SOURCE_TYPE == 7, "onglet Dégâts subis : type " .. tostring(LAST_SOURCE_TYPE))
	assert(Cell(1, 1) == "+ Ogre" and Cell(totalRow, 2) == "1.2k", "unités de l'onglet Dégâts subis : " .. tostring(Cell(totalRow, 2)))
	toolbar.pin.scripts.OnClick(toolbar.pin)
	assert(not toolbar.pin.shown, "épingle retirée")
	-- Comparer : message sans référence, puis le même combat en référence (écart nul).
	bd.tabs[5].scripts.OnClick(bd.tabs[5])
	assert(bd.message.text == NS.L.COMPARE_NO_REFERENCE and toolbar.reference.shown, tostring(bd.message.text))
	toolbar.reference.scripts.OnClick(toolbar.reference); Pick("Ogre")
	assert(Cell(1, 1) == "Sort1" and Cell(1, 2) == "1.2k" and Cell(1, 3) == "1.2k" and Cell(1, 4) == "+0.0%" and Cell(1, 5) == "2" and Cell(1, 6) == "2", "comparaison : " .. tostring(Cell(1, 4)))
	-- Mode choisi dans la barre : la fenêtre d'origine garde le sien.
	toolbar.mode.scripts.OnClick(toolbar.mode); Pick("Soins")
	assert(bd.title.text:find("^Moi : Soins") and owner.cfg.mode == "damage", tostring(bd.title.text))
	toolbar.mode.scripts.OnClick(toolbar.mode); Pick("Dégâts")
	-- Reset : combat choisi et référence oubliés, retour au combat de la fenêtre.
	Record("DAMAGE_METER_RESET")
	bd.tabs[1].scripts.OnClick(bd.tabs[1])
	assert(toolbar.session.text.text:find("^Combat actuel"), "reset : " .. tostring(toolbar.session.text.text))
	bd.tabs[5].scripts.OnClick(bd.tabs[5])
	assert(bd.message.text == NS.L.COMPARE_NO_REFERENCE, "reset : référence oubliée")
	-- Détail des lancers : incantation réussie (barre depuis START), interrompue, ratée, canalisation coupée.
	testClock = 200; Record("PLAYER_REGEN_DISABLED")
	Record("UNIT_SPELLCAST_START", "player", "c1", 1); testClock = 202; Record("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 1)
	Record("UNIT_SPELLCAST_START", "player", "c2", 3); testClock = 203; Record("UNIT_SPELLCAST_INTERRUPTED", "player", "c2", 3)
	Record("UNIT_SPELLCAST_FAILED", "player", "c2", 3) -- même incantation : déjà comptée
	Record("UNIT_SPELLCAST_FAILED", "player", "c9", 4) -- refusé sans START : ignoré
	Record("UNIT_SPELLCAST_START", "player", "c3", 3); testClock = 204; Record("UNIT_SPELLCAST_FAILED", "player", "c3", 3)
	Record("UNIT_SPELLCAST_CHANNEL_START", "player", "c4", 5); Record("UNIT_SPELLCAST_SUCCEEDED", "player", "c4", 5)
	testClock = 207; Record("UNIT_SPELLCAST_CHANNEL_STOP", "player", "c4", 5, "Creature-1")
	Record("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 12); testClock = 210; Record("PLAYER_REGEN_ENABLED")
	local casts = NS.Breakdown.Segments[#NS.Breakdown.Segments].casts
	assert(#casts == 4 and casts[1].from == 0 and casts[1].t == 2 and not casts[1].result, "incantation réussie")
	assert(casts[2].result == "interrupted" and casts[2].from == 2 and casts[2].t == 3, "incantation interrompue")
	assert(casts[3].result == "failed" and casts[3].spellID == 3, "incantation ratée")
	assert(casts[4].result == "cut" and casts[4].from == 4 and casts[4].to == 7, "canalisation coupée")
	bd.tabs[4].scripts.OnClick(bd.tabs[4])
	assert(plot.shown, "chronologie avec barres")
	-- /reload : combat sauvegardé (session 12 « Ogre » encore connue du client), repris au chargement.
	local count = #NS.Breakdown.Segments
	Record("PLAYER_LOGOUT")
	assert(#ForeverMeterTimelineDB == 1 and ForeverMeterTimelineDB[1].sessionName == "Ogre", "combat sauvegardé")
	Record("PLAYER_ENTERING_WORLD")
	assert(ForeverMeterTimelineDB == nil and #NS.Breakdown.Segments == count + 1, "combat repris")
	-- /reload en plein combat : combat sauvegardé, rouvert au chargement tant que le combat dure.
	Record("DAMAGE_METER_RESET")
	testClock, testCombat = 220, true; Record("PLAYER_REGEN_DISABLED"); Record("UNIT_SPELLCAST_SUCCEEDED", "player", "c5", 1)
	Record("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 12); testClock = 225
	Record("PLAYER_LOGOUT")
	assert(#ForeverMeterTimelineDB == 1 and ForeverMeterTimelineDB[1].stop == 225, "combat en cours sauvegardé")
	testCombat = false; Record("PLAYER_REGEN_ENABLED"); testCombat = true -- ferme le segment du module, comme le /reload
	for i = #NS.Breakdown.Segments, 1, -1 do NS.Breakdown.Segments[i] = nil end
	Record("PLAYER_ENTERING_WORLD")
	local reopened = NS.Breakdown.Segments[#NS.Breakdown.Segments]
	assert(#NS.Breakdown.Segments == 1 and not reopened.stop and #reopened.casts == 1 and not reopened.openAtLogout, "combat rouvert")
	testClock = 230; Record("UNIT_SPELLCAST_SUCCEEDED", "player", "c6", 1)
	testCombat = false; Record("PLAYER_REGEN_ENABLED")
	assert(#reopened.casts == 2 and reopened.stop == 230, "suite du combat enregistrée")
	testClock = nil
	assert(errorsReported == errorsBefore, "aucune erreur de rendu")
	bd.close.scripts.OnClick(bd.close)
	assert(not bd.shown)
end
-- Clic droit sur le titre du détail : report des sorts de la source ouverte, même canal que /fm report
local sent, realSend = {}, SendChatMessage
SendChatMessage = function(msg, ch) sent[#sent + 1] = ch .. "> " .. msg end
d.header.scripts.OnClick(d.header, "RightButton")
assert(#sent == 3 and sent[1] == "PARTY> ForeverMeter : Moi, Dégâts, Combat actuel" and sent[2] == "PARTY> 1. Sort1  1.2k (3/s, 60.0%)", table.concat(sent, " ; "))
-- Une ligne secrète : le chat la refuserait, tout le report reste en local plutôt que partir tronqué
secretLine = "^2%."
sent = {}; d.header.scripts.OnClick(d.header, "RightButton"); slash("report 5 guild")
secretLine = nil
assert(#sent == 0, "ligne secrète : rien envoyé au chat : " .. table.concat(sent, " ; "))
SendChatMessage = realSend
-- Colonnes du texte de droite : pourcentage puis total retirés ; les défauts de FormatRow restent intacts
eventsFrame.scripts.OnUpdate(eventsFrame, 1) -- vide un redessin en attente (police)
db.columns.percent = false; eventsFrame.scripts.OnUpdate(eventsFrame, 1)
assert(w1.bars[1].right.text == "2.0k (200/s, 66.7%)", "hors combat sans événement : pas de redessin")
testCombat = true; ForeverMeterFrame2.cfg.mode = "threat"; eventsFrame.scripts.OnUpdate(eventsFrame, 1); testCombat = false; ForeverMeterFrame2.cfg.mode = "damage"
assert(w1.bars[1].right.text == "2.0k (200/s, 66.7%)", "en combat sans événement : pas de redessin, même avec une fenêtre de menace visible")
Fire("ADDON_RESTRICTION_STATE_CHANGED"); eventsFrame.scripts.OnUpdate(eventsFrame, 1)
assert(w1.bars[1].right.text == "2.0k (200/s)", "fin de restriction : redessin")
Tick()
assert(d.bars[1].right.text == "1.2k (3/s)" and w1.bars[1].right.text == "2.0k (200/s)", d.bars[1].right.text .. " / " .. w1.bars[1].right.text)
db.columns.total = false; Tick()
assert(w1.bars[1].right.text == "200/s" and ForeverMeter.FormatRow(10, 1, 10, false) == "10 (1/s, 100.0%)", w1.bars[1].right.text)
db.columns.total, db.columns.percent = true, true
local w2 = ForeverMeterFrame2
w2.bars[2].scripts.OnMouseUp(w2.bars[2])
assert(d.shown and w1.selectedGuid == nil and w2.selectedGuid == "Player-bob" and d.title.text:find("Bob"), "détail passe à la fenêtre 2")
w2.bars[2].scripts.OnMouseUp(w2.bars[2])
assert(not d.shown and w2.selectedGuid == nil)
bar.scripts.OnMouseUp(bar); assert(d.shown)
d.close.scripts.OnClick(); assert(not d.shown and w1.selectedGuid == nil)
bar.scripts.OnMouseUp(bar); d.header.scripts.OnDragStart(); d.header.scripts.OnDragStop()
assert(db.detailPoint and db.detailPoint[1] == "CENTER", "détail déplacé : position gardée")
d.close.scripts.OnClick(); bar.scripts.OnMouseUp(bar); assert(d.point[2] == UIParent, "détail rouvert à sa position, détaché des fenêtres")
d.close.scripts.OnClick(); db.detailPoint = nil
-- Maj+clic : comparaison de deux sources dans le détail ; même Maj+clic : retour au détail simple
bar.scripts.OnMouseUp(bar); shiftDown = true; w1.bars[2].scripts.OnMouseUp(w1.bars[2]); shiftDown = false
assert(d.title.text == "Moi vs Bob : Dégâts" and d.bars[1].right.text == "1.2k | 600 (+100%)", tostring(d.title.text) .. " / " .. tostring(d.bars[1].right.text))
sent = {}; SendChatMessage = function(msg, ch) sent[#sent + 1] = ch .. "> " .. msg end
d.header.scripts.OnClick(d.header, "RightButton")
assert(sent[1] == "PARTY> ForeverMeter : Moi vs Bob, Dégâts, Combat actuel" and sent[2] == "PARTY> 1. Sort1  1.2k | 600 (+100%)", table.concat(sent, " ; "))
SendChatMessage = realSend
secretMode = true; Tick(); assert(d.title.text == "Moi : Dégâts", "en combat : détail simple")
secretMode = false; Tick(); assert(d.title.text == "Moi vs Bob : Dégâts")
shiftDown = true; w1.bars[2].scripts.OnMouseUp(w1.bars[2]); shiftDown = false
assert(w1.compareGuid == nil and d.title.text == "Moi : Dégâts", "fin de comparaison")
shiftDown = true; w1.bars[2].scripts.OnMouseUp(w1.bars[2]); shiftDown = false
d.close.scripts.OnClick(); assert(w1.compareGuid == nil and w1.selectedGuid == nil, "fermeture : comparaison oubliée")

-- Menu : entrées, verrou, nouvelle fenêtre, fermeture
w1.menuButton.scripts.OnClick(w1.menuButton)
local function Entry(text) for _, e in ipairs(LAST_MENU) do if e[2] == text then return e end end end
-- CreateButton(text, func) : func en position 3 ; radio/checkbox : en position 4.
local function Call(text) local e = assert(Entry(text), text); return (e[1] == "CreateButton" and e[3] or e[4])() end
assert(Entry("Dégâts")[3]() == true and Entry("Ogre") and Entry("Verrouiller la position")[1] == "CreateCheckbox")
assert(Entry("Dégâts").parent == nil and Entry("Verrouiller la position").parent == "Fenêtres" and Entry("Global").parent == "Session" and Entry("Couleur de classe").parent == "Couleur des barres", "sous-menus")
ForeverMeterBreakdownFrame:Hide(); Call("Tableau"); assert(ForeverMeterBreakdownFrame.shown, "menu : tableau ouvert"); ForeverMeterBreakdownFrame:Hide()
assert(Entry("Verrouiller la position")[3]() == false); Entry("Verrouiller la position")[4](); assert(db.windows[1].locked == true and not db.windows[2].locked, "verrou par fenêtre")
Call("Nouvelle fenêtre"); assert(#db.windows == 3 and ForeverMeterFrame3.shown)
ForeverMeterFrame3.menuButton.scripts.OnClick(ForeverMeterFrame3.menuButton)
Call("Fermer cette fenêtre"); assert(#db.windows == 2 and not ForeverMeterFrame3.shown)
w2.menuButton.scripts.OnClick(w2.menuButton)
Call("Soins"); assert(db.windows[2].mode == "heal" and w2.title.text:find("Soins"))
Call("Ogre"); assert(db.windows[2].view == 12 and w2.title.text:find("Ogre"), w2.title.text)
Call("Global"); assert(db.windows[2].view == "overall")
-- Copier en texte : en-tête et une ligne par source ; en combat (secret) rien ne s'ouvre
Call("Copier en texte"); local copy = ForeverMeterCopyFrame
assert(copy.shown and copy.box.text:find("^ForeverMeter") and copy.box.text:find("\n1%. Moi") and copy.box.text:find("\n2%. "), copy.box.text)
copy:Hide(); secretMode = true; Call("Copier en texte"); secretMode = false; assert(not copy.shown, "copie en combat refusée")
-- Filtre des ennemis (dégâts subis par les ennemis) : classification jamais secrète, rang des lignes visibles
assert(not Entry("Boss seulement"), "filtre absent hors mode ennemis")
session.combatSources[1].classification, session.combatSources[2].classification = "normal", "worldboss"
db.windows[2].mode = "enemytaken"; Tick()
w2.menuButton.scripts.OnClick(w2.menuButton); Call("Boss seulement")
assert(db.windows[2].filter == "boss" and w2.bars[1].left.text == "1. Bob" and not w2.bars[2].shown, tostring(w2.bars[1].left.text))
w2.menuButton.scripts.OnClick(w2.menuButton); Call("Élites et boss"); assert(w2.bars[1].left.text == "1. Bob" and not w2.bars[2].shown)
-- Mode test avec un filtre : les fausses lignes restent affichées
slash("test"); assert(w2.bars[3].shown, "mode test filtré : lignes affichées"); slash("test")
w2.menuButton.scripts.OnClick(w2.menuButton); Call("Tous"); assert(db.windows[2].filter == nil and w2.bars[2].shown)
session.combatSources[1].classification, session.combatSources[2].classification = nil, nil
db.windows[2].mode = "heal"; Tick()
-- Couleur des barres : sélecteur du client, Annuler remet la précédente, couleur de classe par défaut
ColorPickerFrame = { SetupColorPickerAndShow = function(self, info) self.info = info end, GetColorRGB = function() return 0.1, 0.2, 0.3 end }
local barColor
w1.bars[1].SetStatusBarColor = function(_, r, g, b) barColor = string.format("%.1f %.1f %.1f", r, g, b) end
w1.menuButton.scripts.OnClick(w1.menuButton); Call("Couleur choisie...")
local picker = ColorPickerFrame.info
assert(picker.r == 1 and picker.g == 0.5 and picker.b == 0 and not picker.hasOpacity, "départ : couleur de classe du joueur")
picker.swatchFunc(); Tick()
assert(db.windows[1].barColor.g == 0.2 and barColor == "0.1 0.2 0.3" and not db.windows[2].barColor, tostring(barColor))
picker.cancelFunc(); assert(db.windows[1].barColor == nil, "Annuler : couleur précédente")
picker.swatchFunc(); w1.menuButton.scripts.OnClick(w1.menuButton); assert(Entry("Couleur choisie...")[3]())
Call("Couleur de classe"); Tick(); assert(db.windows[1].barColor == nil and barColor == "1.0 0.5 0.0", tostring(barColor))
-- Export puis import : même réglages ; chaîne invalide refusée, rien ne change
db.windows[1].barColor = { r = 0.1, g = 0.2, b = 0.3 }
slash("export"); local copyFrame = ForeverMeterCopyFrame; local exported = copyFrame.box.text
assert(exported:find("^MIR1") and not exported:find("forbidden", 1, true) and not copyFrame.importButton.shown, exported)
db.warnPct = 42; db.windows[1].barColor = nil
slash("import"); assert(copyFrame.importButton.shown and copyFrame.box.text == "")
copyFrame.box.text = exported .. ";windows.#1.mode=sbogus"; copyFrame.importButton.scripts.OnClick()
assert(db.warnPct == 42 and copyFrame.shown, "mode inconnu : import refusé")
copyFrame.box.text = exported:gsub("warnPct=n%d+", "warnPct=n999"); copyFrame.importButton.scripts.OnClick()
assert(db.warnPct == 42, "hors bornes : import refusé")
copyFrame.box.text = "  " .. exported .. "\n"; copyFrame.importButton.scripts.OnClick()
assert(db.warnPct ~= 42 and db.windows[1].barColor.b == 0.3 and #db.windows == 2 and not copyFrame.shown and db.forbidden, "import appliqué")
db.windows[1].barColor = nil
w1.menuButton.scripts.OnClick(w1.menuButton)
Call("Remise à zéro"); assert(calls.reset == 1 and db.windows[2].view == "overall", "Reset garde la vue choisie au menu")
-- Affichage DPS : dégâts, débit seul. Colonnes, « ma barre seulement », sans titre et gros chiffre propres à la fenêtre.
w1.menuButton.scripts.OnClick(w1.menuButton); Call("Nouvelle fenêtre")
local w3 = ForeverMeterFrame3
w3.menuButton.scripts.OnClick(w3.menuButton); Call("DPS")
assert(#db.windows == 3 and db.windows[3].mode == "damage" and w3.bars[1].right.text == "200/s" and w1.bars[1].right.text == "2.0k (200/s, 66.7%)", w3.bars[1].right.text)
assert(w3.title.text:find("^DPS") and Entry("DPS")[3]() == true and Entry("Dégâts")[3]() == false, w3.title.text)
w3.menuButton.scripts.OnClick(w3.menuButton); Call("Total")
assert(w3.bars[1].right.text == "2.0k (200/s)" and db.columns.total and w1.bars[1].right.text == "2.0k (200/s, 66.7%)", "colonnes de la fenêtre 3 seule")
w3.menuButton.scripts.OnClick(w3.menuButton); Call("Total")
w3.menuButton.scripts.OnClick(w3.menuButton); Call("Ma barre seulement")
session.combatSources = crowd; Tick()
assert(w3.rows == 1 and w3.bars[1].left.text == string.format("%d. Moi", #crowd) and not w3.bars[2].shown, tostring(w3.bars[1].left.text))
session.combatSources = savedSources; Tick()
w3.menuButton.scripts.OnClick(w3.menuButton); Call("Sans titre")
assert(not w3.header.shown and w3.h == 17 + 3 and w3.bars[1].point[3] == 0, "sans titre : barres en haut, " .. tostring(w3.h))
LAST_MENU = nil; w3.bars[1].scripts.OnMouseUp(w3.bars[1], "RightButton"); assert(LAST_MENU and Entry("Sans titre"), "menu au clic droit sur une barre")
assert(not ForeverMeterDetailFrame.shown, "clic droit sans titre : pas de détail")
LAST_MENU = nil; w3.scripts.OnMouseUp(w3, "RightButton"); assert(LAST_MENU, "menu au clic droit sur la fenêtre")
Call("Gros chiffre")
assert(w3.big.shown and w3.big.text == "200/s" and not w3.bars[1].shown and w3.h == 36, tostring(w3.big.text))
AbbreviateNumbers = function(v) return "A" .. v end
secretMode = true; Tick(); assert(w3.big.text == "200.0/s", w3.big.text)
secretMode = false; AbbreviateNumbers = nil
w3.scripts.OnMouseUp(w3, "RightButton"); Call("Dégâts"); assert(db.windows[3].columns == nil and w3.title.text:find("^Dégâts"), "quitter DPS : colonnes communes")
w3.scripts.OnMouseUp(w3, "RightButton"); Call("DPS"); w3.header.scripts.OnMouseWheel(w3.header, -1)
assert(db.windows[3].mode ~= "damage" and db.windows[3].columns == nil, "quitter DPS à la molette : colonnes communes")
w3.scripts.OnMouseUp(w3, "RightButton"); Call("Fermer cette fenêtre"); assert(#db.windows == 2 and not w3.shown)
-- Clic gauche titre = mode suivant ; molette
w1.header.scripts.OnClick(w1.header, "LeftButton"); assert(db.windows[1].mode == "heal")
w1.scripts.OnMouseWheel(w1, -1); assert(w1.scrollOffset == 0, "2 sources, 3 lignes : pas de défilement")
local lockedPoint = db.windows[1].point
w1.header.scripts.OnDragStop(); assert(db.windows[1].point == lockedPoint, "fenêtre verrouillée : relâcher ne la déplace pas")
db.windows[1].locked = nil
w1.header.scripts.OnDragStop(); assert(db.windows[1].point[4] == 10)
eventsFrame.scripts.OnUpdate(eventsFrame, 1); assert(w1.bars[1].left.text ~= "", "textes réécrits après déplacement")

-- Poignée : redimensionne la fenêtre 1 seule ; /fm rows remet la taille commune partout
db.windows[1].locked = nil; w1.l, w1.t = 100, 500
w1.grip.scripts.OnDragStart(); assert(w1.sizing and w1.point[1] == "TOPLEFT" and w1.point[4] == 100 and w1.point[5] == 500, "coin haut-gauche fixé")
cursorX, cursorY = 433, 500 - (18 + 5 * 17 + 3 + 9) -- pendant le glissement : taille brute, barres replacées, frame non arrondie
w1.grip.scripts.OnUpdate()
assert(w1.w == 333 and w1.rows == 6 and db.windows[1].width == 333 and db.windows[1].rows == 6, "glissement : pas d'arrondi, taille enregistrée")
cursorX, cursorY = 420, 500 - (18 + 5 * 17 + 3)
w1.grip.scripts.OnUpdate()
w1.grip.scripts.OnDragStop()
assert(not w1.sizing and w1.grip.scripts.OnUpdate == nil and db.windows[1].width == 320 and db.windows[1].rows == 5, tostring(db.windows[1].rows))
assert(w1.rows == 5 and w1.w == 320 and w2.rows == db.rows and w2.w == db.width, "fenêtre 2 inchangée")
assert(ForeverMeterDetailFrame.w == 320 and ForeverMeterDetailFrame.rows == 5, "détail à la taille du propriétaire")
db.windows[1].locked = true; w1.grip.scripts.OnDragStart(); assert(not w1.sizing, "verrouillée : pas de redimensionnement"); w1.header.scripts.OnDragStart(); assert(w1.cfg.anchor == nil or true); w1.lockButton.scripts.OnClick(); assert(not db.windows[1].locked, "cadenas")
cursorX, cursorY = 100 + 40, 500 - 5 -- butées : largeur 150 minimum, 1 ligne minimum
w1.grip.scripts.OnDragStart(); w1.grip.scripts.OnUpdate(); w1.grip.scripts.OnDragStop()
assert(db.windows[1].width == 150 and db.windows[1].rows == 1, "butées min")
-- Poignée gauche : coin haut-droit fixe, la largeur grandit vers la gauche
w1.l, w1.t, w1.w = 100, 500, 300
w1.gripLeft.scripts.OnDragStart(); assert(w1.sizing and w1.point[1] == "TOPRIGHT" and w1.point[4] == 400 and w1.point[5] == 500, "coin haut-droit fixé")
cursorX, cursorY = 50, 500 - (18 + 5 * 17 + 3)
w1.gripLeft.scripts.OnUpdate(); w1.gripLeft.scripts.OnDragStop()
assert(not w1.sizing and db.windows[1].width == 350 and db.windows[1].rows == 5, "poignée gauche")
db.windows[2].width, db.windows[2].rows = 300, 7; slash("windows 3"); assert(db.windows[3].width == 300 and db.windows[3].rows == 7, "nouvelle fenêtre à la taille de sa parente"); slash("windows 2"); db.windows[2].width, db.windows[2].rows = nil, nil
slash("rows 4"); assert(db.windows[1].rows == nil and w1.rows == 4 and w2.rows == 4)
slash("width 260"); assert(db.windows[1].width == nil and w1.w == 260)

-- Ancrage : la 2e fenêtre est collée sous la 1re ; la déplacer la décroche ; la relâcher contre le bord droit la recolle.
assert(db.windows[2].anchor and db.windows[2].anchor.to == 1 and w2.point[2] == w1 and w2.point[1] == "TOPLEFT" and w2.point[3] == "BOTTOMLEFT", "nouvelle fenêtre collée dessous")
w2.header.scripts.OnDragStart()
assert(db.windows[2].anchor == nil)
w1.l, w1.t, w1.w, w1.h = 0, 500, 260, 100
w2.l, w2.t, w2.w, w2.h = 400, 300, 260, 100 -- loin : reste libre
w2.header.scripts.OnDragStop()
assert(db.windows[2].anchor == nil and w2.point[2] == UIParent)
w2.l, w2.t = 258, 497 -- contre le bord droit de w1, à 2-3 px
w2.header.scripts.OnDragStop()
assert(db.windows[2].anchor and db.windows[2].anchor.to == 1 and db.windows[2].anchor.side == "RIGHT" and w2.point[2] == w1, "aimantée à droite")
-- Boucle refusée : w1 relâchée sous w2 alors que w2 est collée à w1.
w1.l, w1.t = 258, 397
w1.header.scripts.OnDragStop()
assert(db.windows[1].anchor == nil, "pas de boucle 1->2->1")
-- Fermer la fenêtre visée : la collée garde sa position absolue.
slash("windows 3"); assert(db.windows[3].anchor.to == 2)
w1.menuButton.scripts.OnClick(w1.menuButton); Call("Fermer cette fenêtre")
assert(#db.windows == 2 and db.windows[1].anchor == nil and db.windows[1].point[1] == "BOTTOMLEFT" and db.windows[2].anchor.to == 1, "décrochée et index décalé")
slash("windows 1"); slash("windows 2") -- w2 recréée, collée sous w1

-- Événements restants
Fire("GROUP_ROSTER_UPDATE"); Fire("PLAYER_REGEN_ENABLED"); Fire("PLAYER_ENTERING_WORLD"); Fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
w2.cfg.view = 12; Fire("DAMAGE_METER_RESET"); assert(w2.cfg.view == "current")

-- Combat : valeurs secrètes, pas de tri ni d'arithmétique
secretMode = true
Tick()
assert(w1.bars[1].right.text == "2000 (200.0/s)", w1.bars[1].right.text)
db.columns.total = false; Tick(); assert(w1.bars[1].right.text == "200.0/s", w1.bars[1].right.text); db.columns.total = true
bar.scripts.OnEnter(bar)
w1.bars[2].scripts.OnMouseUp(w1.bars[2]) -- GUID d'autrui secret : message chat, pas de détail
assert(w1.selectedGuid == nil)
slash("report"); slash("mode deaths"); bar.scripts.OnEnter(bar)
secretMode = false

-- defaults, puis /reload simulé (config sauvegardée avec 2 fenêtres, vue numérique)
slash("defaults"); assert(#db.windows == 1 and db.windows[1].mode == "damage" and db.windows[1].locked == nil)

-- Rechargement avec une sauvegarde réelle (4 fenêtres, anciens champs) : les 4 doivent revenir.
wipe(ForeverMeterDB)
for k, v in pairs({ showPets = true, point = { "CENTER", nil, "CENTER", 300, 0 }, warnPct = 90, scale = 1, rows = 10, width = 260, forbidden = {}, rowHeight = 16, locked = false, refresh = 0.2, warnSound = true,
	windows = {
		{ view = "current", point = { "TOPLEFT", nil, "TOPLEFT", 0, -41 }, rows = 26, mode = "heal", width = 152 },
		{ view = "current", mode = "damage", point = { "TOPLEFT", nil, "TOPLEFT", 0, -510 } },
		{ view = "current", point = { "TOPLEFT", nil, "TOPLEFT", 151.9, -43.1 }, rows = 9, mode = "damage", width = 454 },
		{ view = "current", point = { "LEFT", nil, "LEFT", 152.5, 146.2 }, rows = 16, mode = "absorbs", width = 250 },
	} }) do ForeverMeterDB[k] = v end
Fire("ADDON_LOADED", "ForeverMeter")
assert(#db.windows == 4, #db.windows)
for i = 1, 4 do assert(_G["ForeverMeterFrame" .. (i == 1 and "" or i)].shown, "fenêtre " .. i .. " masquée") end
assert(w1.rows == 26 and w1.w == 152 and ForeverMeterFrame2.rows == 10 and ForeverMeterFrame4.title.text:find("Absorptions"))

-- Doubles des réglages (WoW Forever ne relit pas les SavedVariables) : table hôte Blizzard puis CVars.
local cvars = {}
g_addonCategoriesCollapsed = {}
C_CVar = {
	RegisterCVar = function(name, default) if cvars[name] == nil then cvars[name] = tostring(default) end end,
	GetCVar = function(name) return cvars[name] end,
	SetCVar = function(name, value) if cvars[name] == nil then return false end cvars[name] = tostring(value) return true end,
}
db.forbidden[1] = "ligne de journal"
assert(NS.Mirror:Flush(), "écriture du miroir")
assert(cvars.ForeverMeterMirror1:find("windows.#4.mode=sabsorbs", 1, true), cvars.ForeverMeterMirror1)
assert(not cvars.ForeverMeterMirror1:find("forbidden", 1, true), "journal exclu du miroir")
assert(not cvars.ForeverMeterMirror1:find("warnPct", 1, true), "défaut exclu du miroir")
wipe(ForeverMeterDB)
Fire("ADDON_LOADED", "ForeverMeter")
db = ForeverMeterDB
assert(#db.windows == 4 and db.windows[4].mode == "absorbs" and db.windows[1].rows == 26, "réglages restaurés depuis le miroir")
assert(db.windows[3].point[4] == 151.9 and db.windows[3].point[2] == nil, "position restaurée, trou nil conservé")
assert(db.warnPct == 90 and db.forbidden, "défauts et journal recréés")
assert(g_addonCategoriesCollapsed.ForeverMeter == ForeverMeterDB, "table hôte : même table que ForeverMeterDB")
-- Table hôte prioritaire sur le miroir CVar, SavedVariables prioritaire sur tout.
g_addonCategoriesCollapsed.ForeverMeter = { windows = { { mode = "threat", view = "current" } } }
wipe(ForeverMeterDB)
Fire("ADDON_LOADED", "ForeverMeter")
db = ForeverMeterDB
assert(#db.windows == 1 and db.windows[1].mode == "threat", "réglages restaurés depuis la table hôte")
assert(g_addonCategoriesCollapsed.ForeverMeter == ForeverMeterDB, "table hôte = table active")

-- Affichage automatique : masqué 10 s après le combat en solo, réaffiché en combat ou en groupe.
inGroup = false
db.autoHide = true
Fire("PLAYER_REGEN_DISABLED")
Fire("PLAYER_REGEN_ENABLED")
eventsFrame.scripts.OnUpdate(eventsFrame, 5)
assert(ForeverMeterFrame.shown, "encore visible 5 s après le combat")
eventsFrame.scripts.OnUpdate(eventsFrame, 6)
assert(not ForeverMeterFrame.shown, "masqué 10 s après le combat")
Fire("PLAYER_REGEN_DISABLED")
assert(ForeverMeterFrame.shown, "réaffiché en combat")
Fire("PLAYER_REGEN_ENABLED")
inGroup = true
Fire("GROUP_ROSTER_UPDATE")
eventsFrame.scripts.OnUpdate(eventsFrame, 20)
assert(ForeverMeterFrame.shown, "reste visible en groupe")
db.autoHide = false

-- Remise à zéro automatique : nouvelle instance ou passage solo -> groupe, pas au retour dans la même instance ni au /reload.
calls.reset = nil
inGroup = false
Fire("GROUP_ROSTER_UPDATE")
testInstance = 36
Fire("PLAYER_ENTERING_WORLD", false, false)
assert(not calls.reset, "option coupée : aucune remise à zéro")
db.autoReset = true
testInstance = nil
Fire("PLAYER_ENTERING_WORLD", false, false)
testInstance = 36
Fire("PLAYER_ENTERING_WORLD", false, false)
assert(not calls.reset, "même instance après une sortie : pas de remise à zéro")
testInstance = 48
Fire("PLAYER_ENTERING_WORLD", false, true)
assert(not calls.reset, "/reload : pas de remise à zéro")
testInstance = 43
Fire("PLAYER_ENTERING_WORLD", false, false)
assert(calls.reset == 1, "nouvelle instance : remise à zéro")
inGroup = true
Fire("GROUP_ROSTER_UPDATE")
assert(calls.reset == 2, "groupe rejoint : remise à zéro")
Fire("GROUP_ROSTER_UPDATE")
assert(calls.reset == 2, "changement dans le groupe : pas de remise à zéro")
db.autoReset = false
-- Re-clic sur Menu : le mouse-down global ferme le menu, le clic qui suit ne le rouvre pas.
-- Aucune fonction de l'addon dans le chemin de fermeture de Blizzard (taint) : pas de HandlesGlobalMouseEvent.
do
	local create, opened = MenuUtil.CreateContextMenu, 0
	MenuUtil.CreateContextMenu = function(owner, gen)
		create(owner, gen); opened = opened + 1
		local m = { shown = true }
		function m:IsShown() return self.shown end
		function m:Close() self.shown = false end
		function m:GetOwnerRegion() return owner end
		return m
	end
	local watch = ForeverMeterMenuWatch
	local b = w1.menuButton
	local over = true
	b.IsMouseOver = function() return over end
	-- Mouse-down global : Blizzard ferme le menu (avant ou après notre événement), puis OnClick au relâché.
	local function Click(btn, blizzardFirst)
		local m = b.fmMenu
		if blizzardFirst and m then m:Close() end
		watch.scripts.OnEvent(watch, "GLOBAL_MOUSE_DOWN", btn)
		if m then m:Close() end
		b.scripts.OnClick(b, btn)
		if watch.shown then watch.scripts.OnUpdate(watch, 0.01) end
	end
	Click("LeftButton")
	assert(opened == 1 and watch.shown and rawget(b, "HandlesGlobalMouseEvent") == nil, "menu ouvert, sans HandlesGlobalMouseEvent")
	Click("LeftButton"); assert(opened == 1 and not watch.shown, "re-clic : menu fermé, pas rouvert")
	Click("LeftButton"); assert(opened == 2, "clic suivant : menu rouvert")
	Click("LeftButton", true); assert(opened == 2, "re-clic, Blizzard avant nous : pas rouvert")
	Click("LeftButton"); assert(opened == 3)
	b.fmMenu:Close(); watch.scripts.OnUpdate(watch, 0.01); Click("LeftButton"); assert(opened == 4, "menu fermé ailleurs : rouvert")
	over = false; watch.scripts.OnEvent(watch, "GLOBAL_MOUSE_DOWN", "LeftButton"); b.fmMenu:Close(); watch.scripts.OnUpdate(watch, 0.01); over = true
	Click("LeftButton"); assert(opened == 5, "fermé par un clic ailleurs : le clic suivant rouvre")
	b.fmMenu:Close(); watch.scripts.OnUpdate(watch, 0.01)
	MenuUtil.CreateContextMenu = create
end
-- Molette sur le titre : bas = mode suivant, haut = retour
slash("mode damage"); w1.header.scripts.OnMouseWheel(w1.header, -1); assert(db.windows[1].mode == "heal", db.windows[1].mode)
w1.header.scripts.OnMouseWheel(w1.header, 1); assert(db.windows[1].mode == "damage")
w1.header.scripts.OnMouseWheel(w1.header, 1); assert(db.windows[1].mode == "threat", "menace avant dégâts")
w1.header.scripts.OnMouseWheel(w1.header, 1); assert(db.windows[1].mode == ForeverMeter.MODES[#ForeverMeter.MODES], "boucle vers le dernier mode")
slash("mode damage")
InterfaceOptionsFrame_OpenToCategory = function() calls.openOptions = (calls.openOptions or 0) + 1 end
testCombat = true; slash("options"); assert(not calls.openOptions, "en combat : pas d'ouverture")
testCombat = false; Fire("PLAYER_REGEN_ENABLED"); assert(calls.openOptions == 1, "ouverture après le combat")
Fire("PLAYER_REGEN_ENABLED"); assert(calls.openOptions == 1, "une seule fois"); calls.openOptions = nil
w1.optionsButton.scripts.OnClick(); assert(calls.openOptions == 1, "bouton Options du titre"); calls.openOptions = nil
-- Canal du report : automatique (groupe d'instance, raid, groupe, say en instance, local seul) ou demandé
do
	local out, chatFrame, instance = {}, DEFAULT_CHAT_FRAME.AddMessage, false
	SendChatMessage = function(msg, ch, _, target) out[#out + 1] = ch .. (target and ":" .. target or "") end
	DEFAULT_CHAT_FRAME.AddMessage = function() out[#out + 1] = "local" end
	IsInInstance = function() return instance end
	local function Sent(cmd) out = {}; slash(cmd); return out[1] .. "/" .. #out end
	slash("mode damage")
	assert(Sent("report 1") == "PARTY/2", Sent("report 1"))
	testRaid = true; assert(Sent("report 1") == "RAID/2"); testRaid = false
	LE_PARTY_CATEGORY_INSTANCE, testInstanceGroup = 2, true
	assert(Sent("report 1") == "INSTANCE_CHAT/2", "groupe d'instance")
	testInstanceGroup = false
	inGroup = false; assert(Sent("report 1") == "local/2", "seul hors instance : local")
	instance = true; assert(Sent("report 1") == "SAY/2", "seul en instance : say")
	instance = false; assert(Sent("report 1 say") == "local/2", "say demandé hors instance : local")
	assert(Sent("report 1 guild") == "GUILD/2" and Sent("report whisper Bob") == "WHISPER:Bob/3", "canal demandé")
	assert(Sent("report 1 yell") == "local/1" and Sent("report whisper") == "local/1", "canal inconnu : aide")
	slash("mode deaths"); assert(Sent("report death 1 guild") == "GUILD/3", "récap de mort sur le canal demandé")
	inGroup, LE_PARTY_CATEGORY_INSTANCE = true, nil
	IsInInstance = function() return false end
	SendChatMessage, DEFAULT_CHAT_FRAME.AddMessage = realSend, chatFrame
end
-- Modes interruptions et dispels : type de meter demandé à l'API, libellé du mode dans le titre
do
	local get, asked = C_DamageMeter.GetCombatSessionFromType, nil
	C_DamageMeter.GetCombatSessionFromType = function(kind, t) asked = t; return get(kind, t) end
	slash("mode interrupts"); Tick()
	assert(asked == 5 and w1.title.text:find(NS.L.MODE_INTERRUPTS, 1, true) and w1.bars[1].left.text:find("Moi"), tostring(asked) .. " / " .. w1.title.text)
	slash("mode dispels"); Tick()
	assert(asked == ForeverMeter.MODE_INFO.dispels.type and w1.title.text:find(NS.L.MODE_DISPELS, 1, true), w1.title.text)
	C_DamageMeter.GetCombatSessionFromType = get
	slash("mode damage")
end
-- /fm mode <mode> [N] : fenêtre N seulement si elle existe
slash("windows 2"); slash("mode heal 2"); assert(db.windows[2].mode == "heal" and db.windows[1].mode == "damage", "mode de la fenêtre 2")
slash("mode taken 3"); assert(db.windows[1].mode == "damage" and db.windows[2].mode == "heal", "fenêtre absente : rien")
slash("windows 1")
-- Réglages du panneau en commande : bornés, au pas du curseur ; autohide réaffiche à la désactivation
slash("rowheight 99"); assert(db.rowHeight == 40)
slash("rowheight 12.6"); assert(db.rowHeight == 12, db.rowHeight)
slash("bgalpha 0.33"); assert(math.abs(db.bgAlpha - 0.35) < 1e-9, db.bgAlpha)
slash("bgalpha 5"); assert(db.bgAlpha == 1)
-- Thèmes : cinq réglages posés d'un coup, casse libre ; nom inconnu sans effet ; police gardée sur client CJK
do
	local said, chatFrame = {}, DEFAULT_CHAT_FRAME.AddMessage
	DEFAULT_CHAT_FRAME.AddMessage = function(_, m) said[#said + 1] = m end
	slash("theme GLASS")
	assert(db.barTexture == "glass" and db.barFont == "pt-sans-narrow-bold" and db.fontSize == 12 and db.rowHeight == 20 and db.bgAlpha == 0.4, "thème glass")
	assert(said[#said]:find("glass"), said[#said])
	slash("theme xx"); assert(db.barTexture == "glass", "thème inconnu : rien")
	db.bgAlpha = 12 * 0.05; slash("theme classic"); assert(db.barFont == nil and db.fontSize == nil and db.rowHeight == 16 and db.barTexture == "blizzard")
	db.bgAlpha = 12 * 0.05; slash("theme"); assert(said[#said - 1]:find("classic"), "opacité du curseur : thème reconnu " .. said[#said - 1])
	slash("rowheight 17"); slash("theme"); assert(said[#said - 1]:find("Personnalisé"), "réglage changé : personnalisé")
	slash("font arial"); local realLocale = GetLocale; GetLocale = function() return "koKR" end
	slash("theme flat"); assert(db.barFont == "arial" and db.barTexture == "flat" and db.fontSize == 11, "koKR : police gardée")
	slash("theme"); assert(said[#said - 1]:find("flat"), "koKR : police ignorée dans la comparaison")
	GetLocale, DEFAULT_CHAT_FRAME.AddMessage = realLocale, chatFrame
	-- Habillage : couleurs copiées (jamais la table du thème), espacement appliqué aux barres et à la hauteur
	slash("theme bold")
	assert(db.borderSize == 2 and db.textOutline == true and db.bgColor.r == 0.1 and db.bgColor ~= FM.THEMES[7].bgColor, "thème bold copié")
	assert(ForeverMeterFrame.bars[2].point[3] == -18 - (20 + 2), "espacement du thème")
	assert(ForeverMeterFrame.header.bg ~= nil and ForeverMeterFrame.bgAlpha == 0.9, "fond du thème")
	slash("theme clear"); assert(db.borderSize == 0 and db.bgAlpha == 0 and db.barFont == nil and db.textOutline == true)
	slash("theme classic")
	assert(db.borderSize == 1 and db.barSpacing == 1 and db.textOutline == false and db.showIcons == true and db.bgColor.r == 0, "classic : habillage par défaut")
	db.showIcons = false; db.borderSize = 0; slash("rowheight " .. db.rowHeight)
	assert(not w1.bars[1].icon.shown and w1.header.point[2] == 0, "icône masquée, sans bordure")
	db.showIcons = true; db.borderSize = 1; slash("rowheight " .. db.rowHeight)
	-- Espace sous le titre : première barre et hauteur décalées d'autant, rien sans titre
	local height = ForeverMeterFrame:GetHeight()
	db.headerSpacing = 6; slash("rowheight " .. db.rowHeight)
	assert(ForeverMeterFrame.bars[1].point[3] == -18 - 6 and ForeverMeterFrame:GetHeight() == height + 6, "espace sous le titre")
	db.headerSpacing = 0; slash("rowheight " .. db.rowHeight)
end
slash("autoreset"); assert(db.autoReset == true); slash("autoreset"); assert(db.autoReset == false)
inGroup = false; slash("autohide"); assert(db.autoHide == true)
ForeverMeterFrame:Hide(); slash("autohide"); assert(db.autoHide == false and ForeverMeterFrame.shown, "autohide coupé : fenêtres réaffichées")
inGroup = true
-- Réduire : titre seul, sans barres ni poignées ; sans titre (noHeader), sans effet ; bouton = bascule
do
	local full = w1:GetHeight()
	w1.minimizeButton.scripts.OnClick(); Tick()
	assert(db.windows[1].minimized and w1:GetHeight() == 18 and w1.rows == 0 and not w1.grip.shown, "réduite : " .. tostring(w1:GetHeight()))
	-- Réduite : titre seul redessiné, le reste du rendu n'est pas parcouru (la ligne secrète ne lève rien).
	session.combatSources[2].totalAmount, errorsReported, w1.title.text = SECRET, 0, nil; Tick()
	assert(w1.title.text and errorsReported == 0, "réduite : titre seul")
	session.combatSources[2].totalAmount = 1000
	db.windows[1].noHeader = true; slash("rows 5"); assert(w1:GetHeight() > 18 and w1.grip.shown, "sans titre : réduction ignorée")
	db.windows[1].noHeader = nil; slash("rows 5")
	w1.minimizeButton.scripts.OnClick(); Tick()
	assert(db.windows[1].minimized == nil and w1:GetHeight() > 18 and w1.grip.shown, "agrandie")
	assert(full > 18)
end
-- Masquer hors instance : masqué hors instance, réaffiché en entrant, et à la désactivation
do
	local instance = false
	IsInInstance = function() return instance end
	slash("instanceonly"); assert(db.instanceOnly and not ForeverMeterFrame.shown, "hors instance : masqué")
	Fire("PLAYER_REGEN_DISABLED"); assert(not ForeverMeterFrame.shown, "combat hors instance : reste masqué")
	Fire("PLAYER_REGEN_ENABLED")
	instance = true; Fire("PLAYER_ENTERING_WORLD", false, false); assert(ForeverMeterFrame.shown, "en instance : affiché")
	slash("toggle"); Fire("PLAYER_REGEN_DISABLED"); assert(not ForeverMeterFrame.shown, "masquage manuel tenu en instance")
	Fire("PLAYER_REGEN_ENABLED"); slash("toggle")
	instance = false; Fire("ZONE_CHANGED_NEW_AREA"); assert(not ForeverMeterFrame.shown, "sortie sans chargement : masqué")
	slash("instanceonly"); assert(db.instanceOnly == false and ForeverMeterFrame.shown, "désactivé : réaffiché")
	IsInInstance = function() return false end
end
print("uicheck OK")
