-- CombatBreakdown : tableau détaillé et chronologie d'un combat, dans une grande fenêtre séparée.
-- Ouverte par le bouton « Tableau » du panneau de détail, pour la source et la session de la fenêtre d'origine.
--
-- Onglets :
--   Sorts       : sorts de la source (total, par seconde, %, overkill), chacun dépliable en cibles.
--   Cibles      : cibles touchées, chacune dépliable en sorts.
--   Mort        : récap de la dernière mort de la source, coup par coup.
--   Chronologie : sorts lancés par le joueur, rencontres et morts du groupe sur un axe du temps.
--
-- Les trois premiers onglets lisent C_DamageMeter, secret en combat : ils se remplissent hors combat.
-- La chronologie est enregistrée en mémoire depuis le dernier chargement de l'interface : sur ce moteur, le client
-- ne donne ni horodatage des dégâts ni sorts des autres joueurs, seulement les sorts lancés par le joueur.
-- Chargé après ForeverMeter.lua, qui lui expose ses lectures dans NS.Meter.

local _, NS = ...
local FM = ForeverMeter
local L = NS.L
local issecretvalue = issecretvalue or function() return false end

------------------------------------------------------------------------
-- 1. Logique pure (testée par selfcheck.lua)
------------------------------------------------------------------------

-- Cibles d'un sort (combatSpellDetails) : le client rend une structure unique ou une liste, toujours rendu en liste.
function FM.SpellTargets(spell)
	local details = spell and spell.combatSpellDetails
	if issecretvalue(details) or type(details) ~= "table" then return {} end
	-- Forme testée sans lire les champs : unitName peut être secret, et comparer un secret lève une erreur.
	if details[1] ~= nil or next(details) == nil then return details end
	return { details }
end

-- Cibles de tous les sorts : { name, class, amount, spells = { { spell, amount } } }, triées par montant décroissant.
function FM.TargetTotals(spells)
	local byName, list = {}, {}
	for _, spell in ipairs(spells) do
		for _, d in ipairs(FM.SpellTargets(spell)) do
			local name = d.unitName or "?"
			local target = byName[name]
			if not target then
				target = { name = name, class = d.unitClassFilename, amount = 0, spells = {} }
				byName[name] = target
				list[#list + 1] = target
			end
			target.amount = target.amount + (d.amount or 0)
			target.spells[#target.spells + 1] = { spell = spell, amount = d.amount or 0 }
		end
	end
	local function ByAmount(a, b) return a.amount > b.amount end
	table.sort(list, ByAmount)
	for _, target in ipairs(list) do table.sort(target.spells, ByAmount) end
	return list
end

-- Tri des lignes d'un tableau sur row.values[key] (nombre ou texte). Valeur absente en dernier.
-- table.sort n'est pas stable : à égalité, l'ordre d'entrée est gardé par l'index d'origine.
function FM.SortRows(rows, key, ascending)
	local order = {}
	for i, row in ipairs(rows) do order[row] = i end
	table.sort(rows, function(a, b)
		local x, y = a.values[key], b.values[key]
		if x == y or (x == nil and y == nil) then return order[a] < order[b] end
		if x == nil or y == nil then return x ~= nil end
		if ascending then return x < y end
		return x > y
	end)
	return rows
end

-- Événements d'un récap de mort, du plus ancien au coup mortel (Blizzard les rend dans l'autre sens),
-- chacun avec son temps avant la mort en secondes (0 au coup mortel, négatif avant).
function FM.DeathRows(events)
	local list = {}
	for i, e in ipairs(events or {}) do list[i] = e end
	if #list > 1 and (list[1].timestamp or 0) > (list[#list].timestamp or 0) then
		for i = 1, math.floor(#list / 2) do list[i], list[#list + 1 - i] = list[#list + 1 - i], list[i] end
	end
	local last = list[#list] and list[#list].timestamp or 0
	local rows = {}
	for i, e in ipairs(list) do rows[i] = { event = e, time = (e.timestamp or last) - last } end
	return rows
end

-- Pas des graduations de l'axe du temps : la plus petite valeur ronde qui laisse au moins `minPixels` entre deux traits.
local TIME_STEPS = { 1, 2, 5, 10, 15, 30, 60, 120, 300, 600 }
function FM.NiceStep(pixelsPerSecond, minPixels)
	for _, step in ipairs(TIME_STEPS) do
		if step * pixelsPerSecond >= minPixels then return step end
	end
	return TIME_STEPS[#TIME_STEPS]
end

-- Vrai si le sort est parti : réussi, ou canalisation coupée après son départ ("cut").
-- "interrupted" et "failed" : incantation commencée qui n'a rien lancé, hors des comptes et du partage.
function FM.CastLanded(cast)
	return not cast.result or cast.result == "cut"
end

-- Lancers { t, spellID, from, to, result } regroupés par sort : { spellID, times, casts, landed },
-- times et casts dans le même ordre, landed = lancers partis. Le sort le plus lancé d'abord.
function FM.CastTracks(casts)
	local bySpell, tracks = {}, {}
	for _, cast in ipairs(casts) do
		local track = bySpell[cast.spellID]
		if not track then
			track = { spellID = cast.spellID, times = {}, casts = {}, landed = 0 }
			bySpell[cast.spellID] = track
			tracks[#tracks + 1] = track
		end
		track.times[#track.times + 1] = cast.t
		track.casts[#track.casts + 1] = cast
		if FM.CastLanded(cast) then track.landed = track.landed + 1 end
	end
	table.sort(tracks, function(a, b)
		if a.landed ~= b.landed then return a.landed > b.landed end
		return a.times[1] < b.times[1]
	end)
	return tracks
end

-- Indice de l'instant de `times` le plus proche de `t`, à `tolerance` secondes au plus, ou nil.
function FM.NearestTime(times, t, tolerance)
	local best, bestGap
	for i, time in ipairs(times) do
		local gap = math.abs(time - t)
		if gap <= tolerance and (not bestGap or gap < bestGap) then best, bestGap = i, gap end
	end
	return best
end

-- Filtre texte des tableaux : vrai si `filter` est vide ou contenu dans `text` (sans casse).
-- Un texte secret (nom de créature en instance) ne peut être lu : écarté dès qu'un filtre est posé.
function FM.MatchesFilter(text, filter)
	if not filter or filter == "" then return true end
	if issecretvalue(text) or type(text) ~= "string" then return false end
	return text:lower():find(filter:lower(), 1, true) ~= nil
end

-- Nom de chaque session du client par sessionID ({ sessionID, name } de GetAvailableCombatSessions).
local function SessionNames(sessions)
	local names = {}
	for _, s in ipairs(sessions) do
		if not issecretvalue(s.sessionID) and not issecretvalue(s.name) and s.sessionID then names[s.sessionID] = s.name end
	end
	return names
end

-- Segments à sauvegarder au /reload : les combats fermés encore liés à une session du client,
-- avec le nom de cette session pour la reconnaître au rechargement.
function FM.SavableSegments(segments, sessions)
	local names, saved = SessionNames(sessions), {}
	for _, segment in ipairs(segments) do
		if segment.stop and segment.sessionID and names[segment.sessionID] then
			segment.sessionName = names[segment.sessionID]
			saved[#saved + 1] = segment
		end
	end
	return saved
end

-- Segments sauvegardés à reprendre : leur session existe encore sous le même ID et le même nom,
-- et l'horloge n'est pas repartie de zéro (redémarrage de la machine). Sinon les données seraient fausses.
function FM.RestorableSegments(saved, sessions, now)
	local names, kept = SessionNames(sessions), {}
	for _, segment in ipairs(type(saved) == "table" and saved or {}) do
		if type(segment) == "table" and type(segment.stop) == "number" and segment.stop <= now and type(segment.casts) == "table"
			and type(segment.encounters) == "table" and segment.sessionID and names[segment.sessionID] == segment.sessionName then
			kept[#kept + 1] = segment
		end
	end
	return kept
end

------------------------------------------------------------------------
-- 2. Partie WoW
------------------------------------------------------------------------
if not CreateFrame then return end

local Meter = NS.Meter
local GetTime = GetTime

------------------------------------------------------------------------
-- Enregistrement de la chronologie : un segment par combat, gardé au /reload (ForeverMeterTimelineDB)
------------------------------------------------------------------------
local MAX_SEGMENTS = 40 -- combats gardés, au /reload compris : borne la mémoire et la sauvegarde
-- Après la fin du combat, un sessionID reçu pendant ce délai est encore rattaché au segment.
local SESSION_LINK_DELAY = 5
-- segments[i] = { start, stop, sessionID, casts = { { t, spellID, from, to, result } }, encounters = { { t, stop, name, success } } }
-- Les instants sont en secondes depuis segment.start. from..to : barre d'incantation (to absent = t) ou de canalisation ;
-- result : nil (réussi), "interrupted" ou "failed" (incantation sans lancer), "cut" (canalisation coupée).
local segments = {}
local openSegment
local encounterActive = false
-- Lancers hors combat des dernières secondes : le sort qui engage (incantation, projectile) précède PLAYER_REGEN_DISABLED.
local PULL_CAST_DELAY = 3
local recentCasts = {}
-- Incantation en cours du joueur { guid, time, spellID } et canalisation en cours { time, spellID } (instants GetTime).
local pendingCast, pendingChannel

local function OpenSegment()
	if openSegment then return end
	local now = GetTime()
	-- combatStart : entrée en combat, origine des deathTimeSeconds ; start peut reculer au lancer d'engagement.
	-- clockOffset : heure serveur = GetTime() + clockOffset, pour aligner les lancers reçus des autres joueurs.
	openSegment = { start = now, combatStart = now, clockOffset = NS.Sync.ClockOffset(), casts = {}, encounters = {} }
	for _, cast in ipairs(recentCasts) do
		if now - cast.time <= PULL_CAST_DELAY then
			openSegment.start = math.min(openSegment.start, cast.time)
			openSegment.casts[#openSegment.casts + 1] = cast
		end
	end
	for _, cast in ipairs(openSegment.casts) do
		cast.t = cast.time - openSegment.start
		cast.from = cast.fromTime and cast.fromTime - openSegment.start
	end
	wipe(recentCasts)
	segments[#segments + 1] = openSegment
	if #segments > MAX_SEGMENTS then table.remove(segments, 1) end
end

local function CloseSegment()
	if not openSegment then return end
	local segment = openSegment
	segment.stop = GetTime()
	openSegment = nil
	-- Envoi protégé : une erreur du partage ne doit pas laisser le segment ouvert ni couper l'enregistrement.
	local ok, err = pcall(NS.Sync.Send, segment)
	if not ok then geterrorhandler()(err) end
end

local ForgetSessions -- défini avec l'état de la fenêtre : oublie les combats choisis, effacés par un reset
local recorder = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END",
	"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_RESET", "PLAYER_LOGOUT" }) do
	Meter.Register(recorder, event)
end
-- Lancers du joueur seulement : ni le trafic des autres unités, ni leur jeton d'unité à comparer.
for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
	if not pcall(recorder.RegisterUnitEvent, recorder, event, "player") then Meter.Register(recorder, event) end
end
recorder:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGOUT" then
		-- /reload en combat : le combat en cours est sauvegardé fermé, rouvert au chargement si le combat dure encore.
		if openSegment then openSegment.stop, openSegment.openAtLogout = GetTime(), true end
		-- Erreur signalée, sauvegarde précédente gardée : une panne ici ne doit pas effacer la chronologie.
		local ok, saved = pcall(FM.SavableSegments, segments, Meter.AvailableSessions())
		if ok then ForeverMeterTimelineDB = saved else geterrorhandler()(saved) end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Sortie d'instance en pleine rencontre : ENCOUNTER_END peut ne jamais arriver.
		encounterActive = false
		if not UnitAffectingCombat("player") then CloseSegment() end
		-- Reprise des combats d'avant le /reload, placés avant ceux enregistrés depuis. Liste des sessions
		-- encore vide (client pas prêt) : la sauvegarde est gardée pour le prochain chargement d'écran.
		local sessions = ForeverMeterTimelineDB and Meter.AvailableSessions()
		if sessions and #sessions > 0 then
			local restored = FM.RestorableSegments(ForeverMeterTimelineDB, sessions, GetTime())
			ForeverMeterTimelineDB = nil
			for _, segment in ipairs(segments) do restored[#restored + 1] = segment end
			wipe(segments)
			for i = math.max(1, #restored - MAX_SEGMENTS + 1), #restored do segments[#segments + 1] = restored[i] end
			-- Combat en cours au /reload et toujours en cours : il reprend là où il s'était arrêté.
			local last = restored[#restored]
			-- Rencontre laissée inactive : sa fin a pu arriver pendant le chargement, sans ENCOUNTER_END reçu.
			if last and last.openAtLogout and not openSegment and UnitAffectingCombat("player") then
				openSegment, last.stop = last, nil
			elseif last and last.openAtLogout then
				-- Combat fini pendant le chargement : partagé maintenant, comme à sa fermeture.
				local ok, err = pcall(NS.Sync.Send, last)
				if not ok then geterrorhandler()(err) end
			end
			for _, segment in ipairs(restored) do segment.openAtLogout = nil end
		end
		-- En combat sans segment (reprise impossible) : la suite du combat est enregistrée dans un nouveau segment.
		if UnitAffectingCombat("player") then OpenSegment() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		OpenSegment()
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Joueur mort pendant une rencontre : le segment reste ouvert jusqu'à ENCOUNTER_END.
		if not encounterActive then CloseSegment() end
	elseif event == "ENCOUNTER_START" then
		OpenSegment()
		encounterActive = true
		local _, name = ...
		openSegment.encounters[#openSegment.encounters + 1] = { t = GetTime() - openSegment.start, name = name }
	elseif event == "ENCOUNTER_END" then
		local success = select(5, ...)
		local segment = openSegment or segments[#segments]
		local encounter = segment and segment.encounters[#segment.encounters]
		if encounter and not encounter.stop then
			encounter.stop = GetTime() - segment.start
			if not issecretvalue(success) then encounter.success = success == 1 end -- secret : issue inconnue (nil)
		end
		encounterActive = false
		if not UnitAffectingCombat("player") then CloseSegment() end
	elseif event == "UNIT_SPELLCAST_START" then
		local unit, castGUID, spellID = ...
		if unit == "player" and castGUID and spellID and not issecretvalue(castGUID) and not issecretvalue(spellID) then
			pendingCast = { guid = castGUID, time = GetTime(), spellID = spellID }
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, castGUID, spellID = ...
		if unit == "player" and spellID and not issecretvalue(spellID) then
			local now = GetTime()
			-- Sort à incantation : la barre part du début de l'incantation (même castGUID).
			local fromTime
			if pendingCast and castGUID and not issecretvalue(castGUID) and pendingCast.guid == castGUID then
				fromTime, pendingCast = pendingCast.time, nil
			end
			if openSegment then
				openSegment.casts[#openSegment.casts + 1] = { t = now - openSegment.start, spellID = spellID,
					from = fromTime and fromTime - openSegment.start }
			else
				if #recentCasts >= 10 then table.remove(recentCasts, 1) end
				recentCasts[#recentCasts + 1] = { time = now, spellID = spellID, fromTime = fromTime }
			end
		end
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		-- Seule une incantation commencée compte : un sort refusé avant de partir (recharge, portée) n'a pas de START.
		local unit, castGUID = ...
		if unit == "player" and pendingCast and castGUID and not issecretvalue(castGUID) and pendingCast.guid == castGUID then
			if openSegment then
				local now = GetTime()
				openSegment.casts[#openSegment.casts + 1] = { t = now - openSegment.start, spellID = pendingCast.spellID,
					from = pendingCast.time - openSegment.start, result = event == "UNIT_SPELLCAST_INTERRUPTED" and "interrupted" or "failed" }
			end
			pendingCast = nil
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local unit, _, spellID = ...
		if unit == "player" and spellID and not issecretvalue(spellID) then pendingChannel = { time = GetTime(), spellID = spellID } end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		-- Fin de canalisation : la barre va du départ à l'arrêt, sur le lancer réussi du même sort (SUCCEEDED au départ).
		local unit, _, _, interruptedBy = ...
		if unit == "player" and pendingChannel and openSegment then
			local from = pendingChannel.time - openSegment.start
			for i = #openSegment.casts, 1, -1 do
				local cast = openSegment.casts[i]
				if cast.t < from - 1 then break end
				if cast.spellID == pendingChannel.spellID and not cast.result then
					cast.from, cast.to = math.min(from, cast.t), GetTime() - openSegment.start
					if interruptedBy then cast.result = "cut" end
					break
				end
			end
		end
		if unit == "player" then pendingChannel = nil end
	elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
		local _, sessionID = ...
		local segment = openSegment or segments[#segments]
		if segment and segment.stop and GetTime() - segment.stop > SESSION_LINK_DELAY then segment = nil end
		-- Mise à jour tardive du combat précédent reçue après l'ouverture du suivant : ID déjà pris, ignoré.
		local previous = segment and segments[#segments - (segment == segments[#segments] and 1 or 0)]
		local floor = math.max(segment and segment.sessionID or 0, previous and previous ~= segment and previous.sessionID or 0)
		-- Segment fermé déjà rattaché : la session suivante (pull enchaîné) n'est pas la sienne.
		if segment and not (segment.stop and segment.sessionID) and not issecretvalue(sessionID) and type(sessionID) == "number" and sessionID > floor then
			segment.sessionID = sessionID
		end
	elseif event == "DAMAGE_METER_RESET" then
		-- Les sessionID disparaissent avec les données : seul le combat en cours est gardé, sans lien.
		for i = #segments, 1, -1 do segments[i] = nil end
		ForgetSessions()
		if openSegment then
			openSegment.sessionID = nil
			segments[1] = openSegment
		end
	end
end)

-- Segment de la session affichée : « current » = dernier combat, sessionID = combat rattaché. nil sinon.
local function SegmentForView(view)
	if view == "current" then return segments[#segments] end
	for i = #segments, 1, -1 do
		if segments[i].sessionID == view then return segments[i] end
	end
	return nil
end

------------------------------------------------------------------------
-- Fenêtre
------------------------------------------------------------------------
local WIDTH, HEIGHT = 760, 440
local HEADER_HEIGHT, TAB_HEIGHT, TOOL_HEIGHT = 18, 20, 20
local TOOL_TOP = HEADER_HEIGHT + TAB_HEIGHT + 4
local CONTENT_TOP = TOOL_TOP + TOOL_HEIGHT + 4
local ROW_HEIGHT = 18
local TABLE_ROWS_TOP = CONTENT_TOP + ROW_HEIGHT + 2
-- Dernière ligne réservée au total, fixe sous les lignes qui défilent.
local TABLE_ROWS = math.floor((HEIGHT - TABLE_ROWS_TOP - 4) / (ROW_HEIGHT + 1)) - 1
local SPELL_COLOR = { 0.8, 0.6, 0.2 }
local DEATH_COLOR = { 0.8, 0.2, 0.2 }
local PINNED_COLOR = { 0.2, 0.55, 1 }
local TOTAL_COLOR = { 0.5, 0.5, 0.5 }

local frame = Meter.MakeWindow("ForeverMeterBreakdownFrame", WIDTH, HEIGHT)
frame:Hide()
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetPoint("CENTER")
frame.header:SetScript("OnDragStart", function() frame:StartMoving() end)
frame.header:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); frame:SetUserPlaced(false) end)
frame.close = CreateFrame("Button", nil, frame.header, "UIPanelCloseButton")
frame.close:SetPoint("RIGHT", 2, 0)
frame.close:SetSize(20, 20)
frame.close:SetScript("OnClick", function() frame:Hide() end)
frame.title:SetPoint("RIGHT", frame.close, "LEFT", -4, 0)
if UISpecialFrames then table.insert(UISpecialFrames, "ForeverMeterBreakdownFrame") end -- Échap ferme la fenêtre

-- État : fenêtre d'origine, source suivie, onglet, tri et lignes dépliées par onglet, défilement.
-- mode, view : mode et combat choisis dans la barre d'outils (nil : ceux de la fenêtre d'origine).
-- reference : combat de référence de l'onglet Comparer. pinned : sort épinglé. filter : texte du filtre.
local state = {
	tab = "spells",
	sort = { spells = { key = "total" }, targets = { key = "total" }, compare = { key = "current" } },
	expanded = {},
	scroll = 0,
}
local Render -- défini plus bas

function ForgetSessions()
	if type(state.view) == "number" then state.view = nil end
	state.reference = nil
end

-- Fenêtre vue par le tableau : pseudo-fenêtre, car les lectures de NS.Meter ne lisent que cfg.mode et cfg.view.
-- Le mode et le combat choisis ici ne changent pas la fenêtre d'origine.
local function ShownWindow()
	local cfg = state.win.cfg
	return { cfg = { mode = state.mode or cfg.mode, view = state.view or cfg.view } }
end

local message = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
message:SetPoint("TOPLEFT", 20, -(CONTENT_TOP + 40))
message:SetPoint("TOPRIGHT", -20, -(CONTENT_TOP + 40))
message:SetJustifyH("CENTER")

-- Onglets
local TABS = { { key = "spells", label = "TAB_SPELLS" }, { key = "targets", label = "TAB_TARGETS" },
	{ key = "death", label = "TAB_DEATH" }, { key = "timeline", label = "TAB_TIMELINE" }, { key = "compare", label = "TAB_COMPARE" } }
local tabButtons = {}
for i, tab in ipairs(TABS) do
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(110, TAB_HEIGHT)
	button:SetPoint("TOPLEFT", 4 + (i - 1) * 112, -(HEADER_HEIGHT + 2))
	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints()
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.text:SetPoint("CENTER")
	button.key = tab.key
	button.label = tab.label
	button:SetScript("OnClick", function()
		state.tab, state.scroll = tab.key, 0
		Render()
	end)
	tabButtons[i] = button
end

------------------------------------------------------------------------
-- Barre d'outils : mode, combat, combat de référence, sort épinglé, filtre texte
------------------------------------------------------------------------
local function ToolButton(width)
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(width, TOOL_HEIGHT)
	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints()
	button.bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 4, 0)
	button.text:SetPoint("RIGHT", -4, 0)
	button.text:SetWordWrap(false)
	return button
end

-- Choix d'un mode ou d'un combat : défilement et lignes dépliées remis à zéro.
local function Choose(field, value)
	state[field], state.scroll = value, 0
	wipe(state.expanded)
	Render()
end

-- Combats disponibles en entrées de menu ; `selected()` rend le combat coché.
local function SessionEntries(entries, selected, field)
	for _, s in ipairs(Meter.AvailableSessions()) do
		local id = s.sessionID
		entries[#entries + 1] = { text = Meter.SessionLabel({ cfg = { view = id } }), checked = function() return selected() == id end,
			func = function() Choose(field, id) end }
	end
	return entries
end

local modeButton = ToolButton(120)
modeButton:SetPoint("TOPLEFT", 4, -TOOL_TOP)
modeButton:SetScript("OnClick", function(self)
	local entries = {}
	for _, m in ipairs(FM.MODES) do
		-- Menace : hors C_DamageMeter. Morts : sans sorts ni cibles, l'onglet Mort les couvre déjà.
		if m ~= "threat" and m ~= "deaths" then
			entries[#entries + 1] = { text = FM.MODE_INFO[m].label, checked = function() return ShownWindow().cfg.mode == m end,
				func = function() Choose("mode", m) end }
		end
	end
	Meter.ShowEntries(entries, self)
end)

local sessionButton = ToolButton(160)
sessionButton:SetPoint("LEFT", modeButton, "RIGHT", 2, 0)
sessionButton:SetScript("OnClick", function(self)
	local function Selected() return ShownWindow().cfg.view end
	local entries = {
		{ text = L.SESSION_CURRENT, checked = function() return Selected() == "current" end, func = function() Choose("view", "current") end },
		{ text = L.SESSION_OVERALL, checked = function() return Selected() == "overall" end, func = function() Choose("view", "overall") end },
	}
	Meter.ShowEntries(SessionEntries(entries, Selected, "view"), self)
end)

local referenceButton = ToolButton(170)
referenceButton:SetPoint("LEFT", sessionButton, "RIGHT", 2, 0)
referenceButton:SetScript("OnClick", function(self)
	Meter.ShowEntries(SessionEntries({}, function() return state.reference end, "reference"), self)
end)

local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
search:SetSize(120, TOOL_HEIGHT)
search:SetPoint("TOPRIGHT", -8, -TOOL_TOP)
search:SetAutoFocus(false)
search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
search.hint:SetPoint("LEFT", 2, 0)
search.hint:SetText(L.BREAKDOWN_SEARCH)
search:SetScript("OnTextChanged", function(self)
	state.filter, state.scroll = self:GetText(), 0
	self.hint:SetShown(state.filter == "")
	Render()
end)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

-- Sort épinglé : un clic le retire.
local pinButton = ToolButton(140)
pinButton:SetPoint("RIGHT", search, "LEFT", -10, 0)
pinButton:SetScript("OnClick", function()
	state.pinned = nil
	Render()
end)

------------------------------------------------------------------------
-- Tableau : en-têtes de colonnes cliquables (tri) et lignes dépliables
------------------------------------------------------------------------
local tableArea = CreateFrame("Frame", nil, frame)
tableArea:SetPoint("TOPLEFT", 0, -CONTENT_TOP)
tableArea:SetPoint("BOTTOMRIGHT")
tableArea:EnableMouseWheel(true)
tableArea:SetScript("OnMouseWheel", function(_, delta)
	state.scroll = math.max(0, state.scroll - delta * 3)
	Render()
end)

local headers, rows = {}, {}

local function HeaderButton(i)
	local button = headers[i]
	if button then return button end
	button = CreateFrame("Button", nil, tableArea)
	button:SetHeight(ROW_HEIGHT)
	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints()
	button.bg:SetColorTexture(0.2, 0.2, 0.2, 0.9)
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.text:SetPoint("LEFT", 4, 0)
	button.text:SetPoint("RIGHT", -4, 0)
	button.text:SetWordWrap(false)
	button:SetScript("OnClick", function(self)
		local sort = state.sort[state.tab]
		if not sort or not self.key then return end
		if sort.key == self.key then
			sort.ascending = not sort.ascending
		else
			sort.key, sort.ascending = self.key, self.key == "name"
		end
		Render()
	end)
	headers[i] = button
	return button
end

local function RowEnter(row)
	if not row.spellID then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(row.spellID) end
	if state.tab ~= "death" then GameTooltip:AddLine(L.BREAKDOWN_PIN_HINT, 0.5, 0.8, 1) end
	GameTooltip:Show()
end

local function TableRow(i)
	local row = rows[i]
	if row then return row end
	row = CreateFrame("StatusBar", nil, tableArea)
	row:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	row:SetMinMaxValues(0, 1)
	row:SetSize(WIDTH - 8, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 4, -(ROW_HEIGHT + 2 + (i - 1) * (ROW_HEIGHT + 1)))
	row:EnableMouse(true)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.cells = {}
	-- Clic gauche : déplie la ligne. Clic droit sur un sort : l'épingle (Cibles et Chronologie n'affichent que lui),
	-- un second clic droit le retire.
	row:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			-- Onglet Mort : sorts ennemis, absents des lancers et des cibles de la source.
			if state.tab == "death" or not self.spellID or issecretvalue(self.spellID) then return end
			state.pinned = state.pinned ~= self.spellID and self.spellID or nil
		elseif self.expandKey then
			state.expanded[self.expandKey] = not state.expanded[self.expandKey] or nil
		else
			return
		end
		Render()
	end)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = row
	return row
end

local function Cell(row, i)
	local text = row.cells[i]
	if not text then
		text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetWordWrap(false)
		row.cells[i] = text
	end
	return text
end

-- Remplit une ligne du tableau ; les cellules de `line.cells` sont rangées par clé de colonne.
local function FillRow(row, line, columns, widths, shade)
	local pinned = line.spellID and not issecretvalue(line.spellID) and line.spellID == state.pinned
	local color = pinned and PINNED_COLOR or line.color
	row:SetStatusBarColor(color[1], color[2], color[3], line.depth > 0 and 0.35 or 0.6)
	row:SetValue(line.fill or 0)
	row.bg:SetColorTexture(0.12, 0.12, 0.12, shade)
	row.expandKey, row.spellID = line.expandKey, line.spellID
	local indent = 2 + line.depth * 16
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", indent, 0)
	row.icon:SetTexture(line.icon)
	row.icon:SetShown(line.icon ~= nil)
	local cx = 0
	for c, column in ipairs(columns) do
		local text = Cell(row, c)
		text:ClearAllPoints()
		local left = c == 1 and indent + (line.icon and ROW_HEIGHT + 2 or 0) or cx + 4
		text:SetPoint("LEFT", left, 0)
		text:SetWidth(cx + widths[c] - 4 - left)
		text:SetJustifyH(column.justify or "RIGHT")
		local value = line.cells[column.key] or ""
		if c == 1 and line.expandKey then value = (state.expanded[line.expandKey] and "- " or "+ ") .. value end
		text:SetText(value)
		text:Show()
		cx = cx + widths[c]
	end
	for c = #columns + 1, #row.cells do row.cells[c]:Hide() end
	row:Show()
end

-- columns : { { key, label, width, justify } }, la première prend la largeur restante.
-- lines : { { cells, values, icon, color, fill, children, expandKey, spellID } } ; les enfants suivent leur parent.
-- total : ligne fixe sous le tableau, ou nil.
local function ShowTable(columns, lines, sortable, total)
	local fixed = 0
	for i = 2, #columns do fixed = fixed + columns[i].width end
	local x, widths = 4, { WIDTH - 8 - fixed }
	for i = 2, #columns do widths[i] = columns[i].width end
	local sort = sortable and state.sort[state.tab]
	-- Colonne de tri absente de ce mode (lancers en vue Global, marques hors dégâts subis) : tri par défaut de l'onglet.
	if sort then
		local present
		for _, column in ipairs(columns) do present = present or column.key == sort.key end
		if not present then sort.key, sort.ascending = state.tab == "compare" and "current" or "total", nil end
	end
	if sort then FM.SortRows(lines, sort.key, sort.ascending) end
	for i, column in ipairs(columns) do
		local button = HeaderButton(i)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", x, 0)
		button:SetWidth(widths[i])
		button.key = sortable and column.key or nil
		local arrow = sort and sort.key == column.key and (sort.ascending and " ^" or " v") or ""
		button.text:SetText(L[column.label] .. arrow)
		button.text:SetJustifyH(column.justify or "RIGHT")
		button:Show()
		x = x + widths[i]
	end
	for i = #columns + 1, #headers do headers[i]:Hide() end

	local flat = {}
	for _, line in ipairs(lines) do
		flat[#flat + 1] = line
		line.depth = 0
		if line.expandKey and state.expanded[line.expandKey] then
			for _, child in ipairs(line.children or {}) do
				child.depth = 1
				flat[#flat + 1] = child
			end
		end
	end
	state.scroll = math.max(0, math.min(state.scroll, #flat - TABLE_ROWS))
	for i = 1, TABLE_ROWS do
		local line = flat[i + state.scroll]
		if line then
			FillRow(TableRow(i), line, columns, widths, i % 2 == 0 and 0.7 or 0.4)
		elseif rows[i] then
			rows[i]:Hide()
		end
	end
	if total then
		total.depth = 0
		FillRow(TableRow(TABLE_ROWS + 1), total, columns, widths, 0.95)
	elseif rows[TABLE_ROWS + 1] then
		rows[TABLE_ROWS + 1]:Hide()
	end
end

local function HideTable()
	for _, button in ipairs(headers) do button:Hide() end
	for _, row in ipairs(rows) do row:Hide() end
end

------------------------------------------------------------------------
-- Contenu des onglets du tableau : colonnes, lignes et total, ou nil et le message à afficher
------------------------------------------------------------------------
local function Percent(part, whole)
	if not whole or whole <= 0 then return "" end
	return string.format("%.1f%%", part / whole * 100)
end

-- Nombre d'un champ : un champ secret ne se formate pas, affiché « ? ».
local function Field(v)
	if issecretvalue(v) then return "?" end
	if not v or v == 0 then return "" end
	return FM.FormatValue(v)
end

-- Somme d'une valeur sur les lignes affichées, nil si aucune ligne ne l'a.
local function Sum(lines, key)
	local sum
	for _, line in ipairs(lines) do
		local v = line.values[key]
		if v then sum = (sum or 0) + v end
	end
	return sum
end

local function TotalLine(cells)
	cells.name = L.BREAKDOWN_TOTAL
	return { color = TOTAL_COLOR, fill = 0, values = {}, cells = cells }
end

local function ClassColorTable(class)
	local r, g, b = Meter.ClassColor(class)
	return { r, g, b }
end

-- Cibles d'un sort lisibles ? Montants seulement, ou noms aussi (`withNames`, nom secret en instance).
-- Un seul secret et la liste n'est ni comparable ni cumulable.
local function TargetsReadable(spell, withNames)
	if issecretvalue(spell.combatSpellDetails) then return false end
	for _, d in ipairs(FM.SpellTargets(spell)) do
		if issecretvalue(d.amount) or (withNames and issecretvalue(d.unitName)) then return false end
	end
	return true
end

-- Modes où les lancers du joueur expliquent les montants, et modes où le client marque les sorts évitables et mortels.
local CAST_MODES = { damage = true, heal = true, absorbs = true, interrupts = true, dispels = true }
local FLAG_MODES = { taken = true, avoidable = true }

-- Lancers d'un segment pour la source suivie : les siens enregistrés ici, ceux d'un autre joueur reçus de son
-- ForeverMeter (CombatSync.lua). Rend les lancers, la durée du segment et vrai pour un autre joueur.
local function SegmentCasts(segment)
	local duration = math.max((segment.stop or GetTime()) - segment.start, 1)
	local me = UnitGUID("player")
	if state.guid and (issecretvalue(me) or state.guid ~= me) then
		local from = segment.start + segment.clockOffset
		return NS.Sync.CastsBetween(state.guid, from, from + duration), duration, true
	end
	return segment.casts, duration, false
end

-- Lancers par sort de la source suivie dans le combat `view` : { [spellID] = nombre } et durée en minutes,
-- ou nil : vue Global, combat non enregistré depuis le chargement, aucun lancer reçu d'un autre joueur.
local function CastCounts(view)
	local segment = view ~= "overall" and SegmentForView(view)
	if not segment then return nil end
	local casts, duration, other = SegmentCasts(segment)
	if other and #casts == 0 then return nil end
	local counts = {}
	for _, track in ipairs(FM.CastTracks(casts)) do counts[track.spellID] = track.landed end
	return counts, duration / 60
end

-- Lancers d'un sort : « — » sans données de lancers, vide pour un sort jamais lancé (effet, proc, coup blanc).
local function CastText(counts, casts)
	if not counts then return "—" end
	return casts > 0 and tostring(casts) or ""
end

-- Nom du sort pour le tableau ; en dégâts subis, suivi de la créature lisible. Les marques ont leur colonne.
local function SpellText(win, s)
	local name = Meter.SpellName(s.spellID) or ("#" .. tostring(s.spellID))
	local creature = FLAG_MODES[win.cfg.mode] and s.creatureName
	if creature and not issecretvalue(creature) and creature ~= "" then name = name .. " · " .. creature end
	return name
end

-- Marques du client (booléens, testés quand même) : mortel = 2, évitable = 1, pour trier les plus dangereux d'abord.
local function Flag(v) return not issecretvalue(v) and v == true end
local function SpellFlags(s)
	local deadly, avoidable = Flag(s.isDeadly), Flag(s.isAvoidable)
	local text = (deadly and "|cffff3333" .. L.SPELL_DEADLY .. "|r " or "") .. (avoidable and "|cffffa500" .. L.SPELL_AVOIDABLE .. "|r" or "")
	return (deadly and 2 or 0) + (avoidable and 1 or 0), text
end

local function SpellColumns(mode)
	local columns = { { key = "name", label = "COL_SPELL", justify = "LEFT" } }
	if CAST_MODES[mode] then
		columns[#columns + 1] = { key = "casts", label = "COL_CASTS", width = 55 }
		columns[#columns + 1] = { key = "average", label = "COL_AVERAGE_CAST", width = 75 }
		columns[#columns + 1] = { key = "cpm", label = "COL_CPM", width = 50 }
	end
	columns[#columns + 1] = { key = "total", label = "COL_TOTAL", width = 80 }
	columns[#columns + 1] = { key = "perSecond", label = "COL_PER_SECOND", width = 70 }
	columns[#columns + 1] = { key = "percent", label = "COL_PERCENT", width = 55 }
	columns[#columns + 1] = { key = "overkill", label = "COL_OVERKILL", width = 75 }
	if FLAG_MODES[mode] then columns[#columns + 1] = { key = "flags", label = "COL_FLAGS", width = 130 } end
	return columns
end

local function SpellLines(win, source)
	local spells, secret = Meter.SortedSpells(source)
	if secret then return nil, L.DETAIL_OUT_OF_COMBAT end
	if #spells == 0 then return nil, L.BREAKDOWN_NO_DATA end
	local session = Meter.ReadSession(win)
	local counts, minutes
	if CAST_MODES[win.cfg.mode] then counts, minutes = CastCounts(win.cfg.view) end
	local total, top = source.totalAmount or 0, spells[1].totalAmount
	local lines = {}
	for i, s in ipairs(spells) do
		local perSecond = Meter.PerSecond(win, s, session, false)
		local casts = counts and (counts[s.spellID] or 0)
		local average = casts and casts > 0 and s.totalAmount / casts or nil
		local flags, flagText = SpellFlags(s)
		local text = SpellText(win, s) -- valeur de tri et du filtre aussi : le filtre trouve la créature
		local line = {
			spellID = s.spellID, icon = Meter.SpellIcon(s.spellID), color = SPELL_COLOR,
			fill = top > 0 and s.totalAmount / top or 0, expandKey = "spells:" .. i .. ":" .. tostring(s.spellID),
			values = { name = text, total = s.totalAmount, perSecond = perSecond,
				percent = total > 0 and s.totalAmount / total or 0, overkill = not issecretvalue(s.overkillAmount) and s.overkillAmount or nil,
				casts = casts, average = average, cpm = casts and casts / minutes, flags = flags },
			cells = { name = text, total = FM.FormatValue(s.totalAmount), perSecond = FM.FormatValue(perSecond),
				percent = Percent(s.totalAmount, total), overkill = Field(s.overkillAmount), casts = CastText(counts, casts),
				average = average and FM.FormatValue(average) or (counts and "" or "—"),
				cpm = casts and casts > 0 and string.format("%.1f", casts / minutes) or (counts and "" or "—"), flags = flagText },
			children = {},
		}
		-- Cibles affichées si leurs montants sont lisibles ; un nom secret s'affiche tel quel (SetText l'accepte).
		local targets = {}
		if TargetsReadable(s) then
			for k, d in ipairs(FM.SpellTargets(s)) do targets[k] = d end -- copie : la table du client n'est pas triée
		end
		table.sort(targets, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
		for _, d in ipairs(targets) do
			line.children[#line.children + 1] = {
				color = ClassColorTable(d.unitClassFilename), fill = s.totalAmount > 0 and (d.amount or 0) / s.totalAmount or 0,
				values = {}, cells = { name = d.unitName or "?", total = FM.FormatValue(d.amount), percent = Percent(d.amount or 0, s.totalAmount) },
			}
		end
		if #line.children == 0 then line.expandKey = nil end
		lines[#lines + 1] = line
	end
	-- Total des lignes affichées (après filtre).
	local function Total(shown)
		local casts = Sum(shown, "casts")
		return TotalLine({ total = FM.FormatValue(Sum(shown, "total") or 0), perSecond = FM.FormatValue(Sum(shown, "perSecond") or 0),
			percent = Percent(Sum(shown, "percent") or 0, 1), overkill = Field(Sum(shown, "overkill")),
			casts = counts and tostring(casts or 0) or "—", cpm = counts and string.format("%.1f", (casts or 0) / minutes) or "—" })
	end
	return SpellColumns(win.cfg.mode), lines, Total
end

local TARGET_COLUMNS = {
	{ key = "name", label = "COL_TARGET", justify = "LEFT" },
	{ key = "total", label = "COL_TOTAL", width = 90 },
	{ key = "percent", label = "COL_PERCENT", width = 70 },
}

local function TargetLines(win, source)
	local spells, secret = Meter.SortedSpells(source)
	if secret then return nil, L.DETAIL_OUT_OF_COMBAT end
	-- Sort épinglé : seules ses cibles.
	if state.pinned then
		local only = {}
		for _, s in ipairs(spells) do
			if not issecretvalue(s.spellID) and s.spellID == state.pinned then only[#only + 1] = s end
		end
		spells = only
	end
	-- Cumul par nom : un nom secret (instance) ne peut servir de clé.
	for _, spell in ipairs(spells) do
		if not TargetsReadable(spell, true) then return nil, L.BREAKDOWN_TARGETS_HIDDEN end
	end
	local targets = FM.TargetTotals(spells)
	if #targets == 0 then return nil, L.BREAKDOWN_NO_TARGETS end
	local total, top = source.totalAmount or 0, targets[1].amount
	local lines = {}
	for _, target in ipairs(targets) do
		local line = {
			color = ClassColorTable(target.class), fill = top > 0 and target.amount / top or 0,
			expandKey = "targets:" .. target.name,
			values = { name = target.name, total = target.amount, percent = total > 0 and target.amount / total or 0 },
			cells = { name = target.name, total = FM.FormatValue(target.amount), percent = Percent(target.amount, total) },
			children = {},
		}
		for _, entry in ipairs(target.spells) do
			line.children[#line.children + 1] = {
				spellID = entry.spell.spellID, icon = Meter.SpellIcon(entry.spell.spellID), color = SPELL_COLOR,
				fill = target.amount > 0 and entry.amount / target.amount or 0, values = {},
				cells = { name = Meter.SpellLabel(win, entry.spell), total = FM.FormatValue(entry.amount), percent = Percent(entry.amount, target.amount) },
			}
		end
		lines[#lines + 1] = line
	end
	local function Total(shown)
		return TotalLine({ total = FM.FormatValue(Sum(shown, "total") or 0), percent = Percent(Sum(shown, "percent") or 0, 1) })
	end
	return TARGET_COLUMNS, lines, Total
end

-- Écart en % : « nouveau » quand la référence ne l'avait pas.
local function DeltaText(delta, current)
	if delta then return string.format("%+.1f%%", delta) end
	return current > 0 and L.COMPARE_NEW or ""
end

-- Onglet Comparer : sorts de la source dans le combat affiché et dans le combat de référence.
local function CompareLines(win, source)
	if not state.reference then return nil, L.COMPARE_NO_REFERENCE end
	local spells, secret = Meter.SortedSpells(source)
	local reference = Meter.ReadSource({ cfg = { mode = win.cfg.mode, view = state.reference } }, state.guid)
	local referenceSpells, referenceSecret = Meter.SortedSpells(reference)
	if secret or referenceSecret then return nil, L.DETAIL_OUT_OF_COMBAT end
	local entries = FM.CompareSpells(spells, referenceSpells)
	if #entries == 0 then return nil, L.BREAKDOWN_NO_DATA end
	local counts, referenceCounts
	local columns = { { key = "name", label = "COL_SPELL", justify = "LEFT" },
		{ key = "current", label = "COL_CURRENT", width = 85 }, { key = "reference", label = "COL_REFERENCE", width = 85 },
		{ key = "delta", label = "COL_DELTA", width = 70 } }
	if CAST_MODES[win.cfg.mode] then
		counts, referenceCounts = CastCounts(win.cfg.view), CastCounts(state.reference)
		columns[#columns + 1] = { key = "casts", label = "COL_CASTS", width = 60 }
		columns[#columns + 1] = { key = "referenceCasts", label = "COL_REFERENCE_CASTS", width = 80 }
	end
	local top = 0
	for _, e in ipairs(entries) do top = math.max(top, e.a or 0, e.b or 0) end
	local lines = {}
	-- FM.CompareSpells : a = ce combat, b = référence, nil pour un sort absent d'un côté.
	for _, e in ipairs(entries) do
		e.current, e.reference = e.a or 0, e.b or 0
		if e.reference > 0 then e.delta = (e.current - e.reference) / e.reference * 100 end
		local casts = counts and (counts[e.spellID] or 0)
		local referenceCasts = referenceCounts and (referenceCounts[e.spellID] or 0)
		local text = SpellText(win, e) -- tri et filtre sur le texte affiché, créature comprise
		lines[#lines + 1] = {
			spellID = e.spellID, icon = Meter.SpellIcon(e.spellID), color = SPELL_COLOR, fill = top > 0 and e.current / top or 0,
			values = { name = text, current = e.current, reference = e.reference, delta = e.delta,
				casts = casts, referenceCasts = referenceCasts },
			cells = { name = text, current = FM.FormatValue(e.current), reference = FM.FormatValue(e.reference),
				delta = DeltaText(e.delta, e.current), casts = CastText(counts, casts), referenceCasts = CastText(referenceCounts, referenceCasts) },
		}
	end
	local function Total(shown)
		local current, ref = Sum(shown, "current") or 0, Sum(shown, "reference") or 0
		return TotalLine({ current = FM.FormatValue(current), reference = FM.FormatValue(ref),
			delta = DeltaText(ref > 0 and (current - ref) / ref * 100 or nil, current),
			casts = CastText(counts, Sum(shown, "casts") or 0), referenceCasts = CastText(referenceCounts, Sum(shown, "referenceCasts") or 0) })
	end
	return columns, lines, Total
end

local DEATH_COLUMNS = {
	{ key = "name", label = "COL_SPELL", justify = "LEFT" },
	{ key = "time", label = "COL_TIME", width = 50 },
	{ key = "amount", label = "COL_AMOUNT", width = 70 },
	{ key = "overkill", label = "COL_OVERKILL", width = 70 },
	{ key = "absorbed", label = "COL_ABSORBED", width = 70 },
	{ key = "blocked", label = "COL_BLOCKED", width = 70 },
	{ key = "health", label = "COL_HEALTH", width = 70 },
}

-- Récap de mort de la source, lu dans la session Morts de la même vue que la fenêtre d'origine.
local function DeathLines(win, guid)
	local session = Meter.ReadSession({ cfg = { mode = "deaths", view = win.cfg.view } })
	if not session then return nil, L.BREAKDOWN_NO_DATA end
	local recapID, hidden
	for _, src in ipairs(session.combatSources or {}) do
		if issecretvalue(src.sourceGUID) then
			hidden = true
		elseif src.sourceGUID == guid then
			recapID = src.deathRecapID
		end
	end
	if not recapID then return nil, hidden and L.DETAIL_OUT_OF_COMBAT or L.TIP_NO_RECAP end
	local events, why = Meter.RecapEvents(recapID)
	if not events then return nil, why end
	local deathRows = FM.DeathRows(events)
	local top = 1
	for _, r in ipairs(deathRows) do top = math.max(top, r.event.amount or 0) end
	local lines = {}
	for _, r in ipairs(deathRows) do
		local e = r.event
		local name = e.spellName or (e.spellId and Meter.SpellName(e.spellId)) or e.environmentalType or "?"
		local who = e.sourceName
		if issecretvalue(who) or (who and who ~= "") then name = string.format("%s (%s)", name, who) end
		lines[#lines + 1] = {
			spellID = e.spellId, icon = e.spellId and Meter.SpellIcon(e.spellId) or nil, color = DEATH_COLOR,
			fill = (e.amount or 0) / top, values = {},
			cells = { name = name, time = string.format("%.1fs", r.time), amount = Field(e.amount), overkill = Field(e.overkill),
				absorbed = Field(e.absorbed), blocked = Field(e.blocked), health = Field(e.currentHP) },
		}
	end
	return DEATH_COLUMNS, lines
end

------------------------------------------------------------------------
-- Chronologie
------------------------------------------------------------------------
local LABEL_WIDTH = 150
local AXIS_HEIGHT = 16
local TRACK_ROWS = 16
local PLOT_WIDTH = WIDTH - 8 - LABEL_WIDTH
local PLOT_HEIGHT = TRACK_ROWS * ROW_HEIGHT
local MARKER_SIZE = 14
local MAX_PIXELS_PER_SECOND = 200
local HOVER_PIXELS = 6
local DEATH_ICON = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"

-- view : segment affiché, pixels par seconde, début de la partie visible (s), première piste visible, zoom manuel.
local view = { pixelsPerSecond = 1, offset = 0, firstTrack = 0, hidden = {} }
local shownTracks = {}

local timeline = CreateFrame("Frame", nil, frame)
timeline:SetPoint("TOPLEFT", 4, -CONTENT_TOP)
timeline:SetPoint("BOTTOMRIGHT", -4, 4)
timeline:EnableMouseWheel(true)
timeline:SetScript("OnMouseWheel", function(_, delta)
	view.firstTrack = math.max(0, view.firstTrack - delta)
	Render()
end)

local plot = CreateFrame("Frame", nil, timeline)
plot:SetPoint("TOPLEFT", LABEL_WIDTH, -AXIS_HEIGHT)
plot:SetSize(PLOT_WIDTH, PLOT_HEIGHT)
plot:EnableMouse(true)
plot:EnableMouseWheel(true)
plot.bg = plot:CreateTexture(nil, "BACKGROUND")
plot.bg:SetAllPoints()
plot.bg:SetColorTexture(0.05, 0.05, 0.05, 0.6)

local help = timeline:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
help:SetPoint("BOTTOMLEFT", 2, 2)
help:SetPoint("BOTTOMRIGHT", -2, 2)
help:SetJustifyH("LEFT")

local cursorLine = plot:CreateTexture(nil, "OVERLAY")
cursorLine:SetColorTexture(1, 1, 1, 0.5)
cursorLine:SetSize(1, PLOT_HEIGHT)
cursorLine:Hide()
local cursorTime = timeline:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cursorTime:Hide()

-- Réserves de textures et de textes, cachées puis réutilisées à chaque rendu.
local function Pool(create)
	local pool = { used = 0 }
	function pool.Reset()
		for i = 1, pool.used do pool[i]:Hide() end
		pool.used = 0
	end
	function pool.Next()
		pool.used = pool.used + 1
		local item = pool[pool.used] or create()
		pool[pool.used] = item
		item:Show()
		return item
	end
	return pool
end
local markers = Pool(function() return plot:CreateTexture(nil, "ARTWORK") end)
local tickLabels = Pool(function() return timeline:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") end)

local trackLabels = {}
local function TrackLabel(i)
	local label = trackLabels[i]
	if label then return label end
	label = CreateFrame("Button", nil, timeline)
	label:SetSize(LABEL_WIDTH - 4, ROW_HEIGHT)
	label:SetPoint("TOPLEFT", 0, -(AXIS_HEIGHT + (i - 1) * ROW_HEIGHT))
	label.icon = label:CreateTexture(nil, "ARTWORK")
	label.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
	label.icon:SetPoint("LEFT", 2, 0)
	label.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	label.text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label.text:SetPoint("LEFT", label.icon, "RIGHT", 4, 0)
	label.text:SetPoint("RIGHT", -2, 0)
	label.text:SetJustifyH("LEFT")
	label.text:SetWordWrap(false)
	-- Clic sur un sort : ses lancers sont masqués (ligne grisée), un second clic les réaffiche.
	label:SetScript("OnClick", function(self)
		if not self.spellID then return end
		view.hidden[self.spellID] = not view.hidden[self.spellID] or nil
		Render()
	end)
	trackLabels[i] = label
	return label
end

-- Morts du groupe dans la session de la fenêtre d'origine : { t, name, class, recapID } (instants lisibles seulement).
local function SessionDeaths(win, segment)
	local session = Meter.ReadSession({ cfg = { mode = "deaths", view = win.cfg.view } })
	local deaths = {}
	for _, src in ipairs(session and session.combatSources or {}) do
		local t = src.deathTimeSeconds
		if t and not issecretvalue(t) and not issecretvalue(src.name) then
			deaths[#deaths + 1] = { t = t + (segment.combatStart or segment.start) - segment.start, name = src.name, class = src.classFilename, recapID = src.deathRecapID }
		end
	end
	return deaths
end

local function X(t) return (t - view.offset) * view.pixelsPerSecond end

-- Repère centré sur l'instant t, dans la piste `row`, s'il tombe dans la partie visible.
local function PlaceMarker(texture, t, row, r, g, b)
	local x = X(t) - MARKER_SIZE / 2
	if x < 0 or x > PLOT_WIDTH - MARKER_SIZE then return end
	local marker = markers.Next()
	marker:ClearAllPoints()
	marker:SetPoint("TOPLEFT", x, -((row - 1) * ROW_HEIGHT + (ROW_HEIGHT - MARKER_SIZE) / 2))
	marker:SetSize(MARKER_SIZE, MARKER_SIZE)
	marker:SetDrawLayer("ARTWORK", 1)
	marker:SetDesaturated(false)
	marker:SetVertexColor(1, 1, 1)
	if texture then
		marker:SetTexture(texture)
		marker:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	else
		marker:SetColorTexture(r, g, b, 0.9)
	end
	return marker
end

-- Bande de l'instant `from` à `to` dans la piste `row`, coupée à la partie visible, sous les icônes.
local function PlaceBand(from, to, row, inset, r, g, b, a)
	local left, right = math.max(X(from), 0), math.min(X(to), PLOT_WIDTH)
	if right - left < 1 then return end
	local band = markers.Next()
	band:ClearAllPoints()
	band:SetPoint("TOPLEFT", left, -((row - 1) * ROW_HEIGHT + inset))
	band:SetSize(right - left, ROW_HEIGHT - 2 * inset)
	band:SetDrawLayer("ARTWORK", 0)
	band:SetDesaturated(false)
	band:SetVertexColor(1, 1, 1)
	band:SetColorTexture(r, g, b, a)
end

-- Couleur d'un lancer : rouge si interrompu ou coupé, gris si raté, bleu sinon.
local CAST_COLORS = { interrupted = { 0.9, 0.2, 0.2 }, cut = { 0.9, 0.2, 0.2 }, failed = { 0.5, 0.5, 0.5 } }
local CAST_COLOR = { 0.3, 0.6, 1 }

local function RenderTimeline(win)
	markers.Reset()
	tickLabels.Reset()
	for _, label in ipairs(trackLabels) do label:Hide() end
	wipe(shownTracks)
	if win.cfg.view == "overall" then return L.TIMELINE_OVERALL end
	local segment = SegmentForView(win.cfg.view)
	if not segment then return L.TIMELINE_NO_FIGHT end
	if view.segment ~= segment then
		view.segment, view.offset, view.firstTrack, view.zoomed = segment, 0, 0, false
	end
	local duration = math.max((segment.stop or GetTime()) - segment.start, 1)
	local fit = PLOT_WIDTH / duration
	if not view.zoomed or view.pixelsPerSecond < fit then view.pixelsPerSecond, view.zoomed = fit, false end
	local span = PLOT_WIDTH / view.pixelsPerSecond
	view.offset = math.max(0, math.min(view.offset, duration - span))
	view.duration = duration

	-- Axe du temps : graduations rondes, au moins 50 px entre deux.
	local step = FM.NiceStep(view.pixelsPerSecond, 50)
	for t = math.ceil(view.offset / step) * step, view.offset + span, step do
		local x = X(t)
		local line = markers.Next()
		line:ClearAllPoints()
		line:SetColorTexture(1, 1, 1, 0.08)
		line:SetDrawLayer("ARTWORK", 0)
		line:SetDesaturated(false)
		line:SetVertexColor(1, 1, 1)
		line:SetSize(1, PLOT_HEIGHT)
		line:SetPoint("TOPLEFT", x, 0)
		local label = tickLabels.Next()
		label:ClearAllPoints()
		label:SetPoint("BOTTOM", plot, "TOPLEFT", x, 2)
		label:SetText(FM.FormatTime(t))
	end

	local tracks = {}
	if #segment.encounters > 0 then tracks[#tracks + 1] = { kind = "encounter", label = L.TIMELINE_ENCOUNTER } end
	local deaths = SessionDeaths(win, segment)
	if #deaths > 0 then
		local times = {}
		for i, death in ipairs(deaths) do times[i] = death.t end
		tracks[#tracks + 1] = { kind = "deaths", label = L.TIMELINE_DEATHS, times = times, deaths = deaths }
	end
	local casts, _, other = SegmentCasts(segment)
	local noCast = other and L.TIMELINE_NO_SYNC or L.TIMELINE_NO_CAST
	if other and #casts == 0 then help:SetText(L.TIMELINE_NO_SYNC) end
	-- Sort épinglé ou filtre texte : seules les pistes de sort qui y répondent.
	for _, track in ipairs(FM.CastTracks(casts)) do
		if (not state.pinned or track.spellID == state.pinned) and FM.MatchesFilter(Meter.SpellName(track.spellID), state.filter) then
			track.kind = "spell"
			tracks[#tracks + 1] = track
		end
	end
	if #tracks == 0 then return noCast end
	view.firstTrack = math.max(0, math.min(view.firstTrack, #tracks - TRACK_ROWS))

	for row = 1, TRACK_ROWS do
		local track = tracks[row + view.firstTrack]
		if not track then break end
		shownTracks[row] = track
		local label = TrackLabel(row)
		label.spellID = track.spellID
		local hidden = track.spellID and view.hidden[track.spellID]
		if track.kind == "spell" then
			label.icon:SetTexture(Meter.SpellIcon(track.spellID))
			label.text:SetText(string.format("%s (%d)", Meter.SpellName(track.spellID) or ("#" .. tostring(track.spellID)), track.landed))
			if not hidden then
				-- Barre d'incantation ou de canalisation derrière l'icône ; icône rougie si interrompue, grisée si ratée.
				for _, cast in ipairs(track.casts) do
					local color = CAST_COLORS[cast.result] or CAST_COLOR
					if cast.from then PlaceBand(cast.from, cast.to or cast.t, row, 5, color[1], color[2], color[3], 0.6) end
					local icon = PlaceMarker(Meter.SpellIcon(track.spellID), cast.t, row)
					if icon and cast.result == "failed" then icon:SetDesaturated(true) end
					if icon and cast.result == "interrupted" then icon:SetVertexColor(1, 0.35, 0.35) end
				end
			end
		elseif track.kind == "deaths" then
			label.icon:SetTexture(DEATH_ICON)
			label.text:SetText(track.label)
			for _, t in ipairs(track.times) do PlaceMarker(DEATH_ICON, t, row) end
		else
			label.icon:SetTexture(nil)
			label.text:SetText(track.label)
			-- Bande de la rencontre, de son début à sa fin (ou à la fin du segment), verte si victoire.
			for _, encounter in ipairs(segment.encounters) do
				if encounter.success then
					PlaceBand(encounter.t, encounter.stop or duration, row, 3, 0.2, 0.7, 0.2, 0.6)
				elseif encounter.success == false then
					PlaceBand(encounter.t, encounter.stop or duration, row, 3, 0.7, 0.4, 0.1, 0.6)
				else
					PlaceBand(encounter.t, encounter.stop or duration, row, 3, 0.5, 0.5, 0.5, 0.6)
				end
			end
		end
		label.text:SetTextColor(hidden and 0.4 or 1, hidden and 0.4 or 1, hidden and 0.4 or 1)
		label.icon:SetDesaturated(hidden and true or false)
		label:Show()
	end
	return nil
end

-- Molette : défilement horizontal ; Ctrl : zoom autour du curseur ; Maj : pistes.
local function CursorX()
	local scale = plot:GetEffectiveScale()
	local x = GetCursorPosition() / scale
	return x - (plot:GetLeft() or 0)
end

plot:SetScript("OnMouseWheel", function(_, delta)
	if not view.duration then return end
	if IsShiftKeyDown() then
		view.firstTrack = math.max(0, view.firstTrack - delta)
	elseif IsControlKeyDown() then
		local x = CursorX()
		local anchor = view.offset + x / view.pixelsPerSecond
		local fit = PLOT_WIDTH / view.duration
		view.pixelsPerSecond = math.max(fit, math.min(MAX_PIXELS_PER_SECOND, view.pixelsPerSecond * (delta > 0 and 1.25 or 0.8)))
		view.zoomed = view.pixelsPerSecond > fit
		view.offset = anchor - x / view.pixelsPerSecond
	else
		view.offset = view.offset - delta * 0.15 * PLOT_WIDTH / view.pixelsPerSecond
	end
	Render()
end)

-- Survol : trait vertical et instant sous le curseur, tooltip de l'événement le plus proche dans la piste survolée.
local function TrackTooltip(track, index)
	if track.kind == "spell" then
		GameTooltip:SetText(Meter.SpellName(track.spellID) or ("#" .. tostring(track.spellID)), 1, 0.82, 0)
		-- Rang parmi les lancers partis, comme le compte de la piste ; une incantation sans lancer n'a que son instant.
		local cast, rank = track.casts[index], 0
		for i = 1, index do
			if FM.CastLanded(track.casts[i]) then rank = rank + 1 end
		end
		if FM.CastLanded(cast) then
			GameTooltip:AddLine(string.format(L.TIMELINE_CAST_AT, FM.FormatTime(cast.t), rank, track.landed), 1, 1, 1)
		else
			GameTooltip:AddLine(FM.FormatTime(cast.t), 1, 1, 1)
		end
		-- Durée de l'incantation ou de la canalisation, et issue si le sort n'est pas parti en entier.
		if cast.from then
			GameTooltip:AddLine(string.format(cast.to and L.TIMELINE_CHANNEL_TIME or L.TIMELINE_CAST_TIME, (cast.to or cast.t) - cast.from), 1, 1, 1)
		end
		if cast.result == "interrupted" or cast.result == "cut" then
			GameTooltip:AddLine(L.TIMELINE_INTERRUPTED, 1, 0.3, 0.3)
		elseif cast.result == "failed" then
			GameTooltip:AddLine(L.TIMELINE_FAILED, 0.7, 0.7, 0.7)
		end
	elseif track.kind == "deaths" then
		local death = track.deaths[index]
		GameTooltip:SetText(death.name, Meter.ClassColor(death.class))
		GameTooltip:AddLine(FM.FormatTime(death.t), 1, 1, 1)
		local events, why = Meter.RecapEvents(death.recapID)
		if events then
			for _, line in ipairs(FM.RecapLines(events, Meter.SpellName)) do
				GameTooltip:AddDoubleLine(line.left, line.right, 1, 1, 1, 1, 0.5, 0.5)
			end
		else
			GameTooltip:AddLine(why, 0.7, 0.7, 0.7)
		end
	else
		local encounter = track.encounter
		GameTooltip:SetText(encounter.name or L.TIMELINE_ENCOUNTER, 1, 0.82, 0)
		GameTooltip:AddLine(string.format("%s - %s", FM.FormatTime(encounter.t), encounter.stop and FM.FormatTime(encounter.stop) or "..."), 1, 1, 1)
		if encounter.success ~= nil then
			GameTooltip:AddLine(encounter.success and L.TIMELINE_KILL or L.TIMELINE_WIPE, 1, 1, 1)
		end
	end
end

local hovered
local function PlotHover()
	if not view.duration then return end
	local scale = plot:GetEffectiveScale()
	local _, cy = GetCursorPosition()
	local x, y = CursorX(), (plot:GetTop() or 0) - cy / scale
	if x < 0 or x > PLOT_WIDTH or y < 0 or y > PLOT_HEIGHT then return end
	local t = view.offset + x / view.pixelsPerSecond
	cursorLine:ClearAllPoints()
	cursorLine:SetPoint("TOPLEFT", x, 0)
	cursorLine:Show()
	cursorTime:ClearAllPoints()
	cursorTime:SetPoint("TOP", plot, "BOTTOMLEFT", x, -1)
	cursorTime:SetText(FM.FormatTime(t))
	cursorTime:Show()

	local track = shownTracks[math.floor(y / ROW_HEIGHT) + 1]
	local index
	if track and track.kind == "encounter" then
		for i, encounter in ipairs(view.segment.encounters) do
			if t >= encounter.t and t <= (encounter.stop or view.duration) then index, track.encounter = i, encounter end
		end
	elseif track and not (track.spellID and view.hidden[track.spellID]) then
		index = FM.NearestTime(track.times, t, HOVER_PIXELS / view.pixelsPerSecond)
	end
	local key = index and (tostring(track) .. ":" .. index)
	if key == hovered then return end
	hovered = key
	if not key then GameTooltip:Hide(); return end
	GameTooltip:SetOwner(plot, "ANCHOR_CURSOR")
	TrackTooltip(track, index)
	GameTooltip:Show()
end

plot:SetScript("OnEnter", function() plot:SetScript("OnUpdate", PlotHover) end)
plot:SetScript("OnLeave", function()
	plot:SetScript("OnUpdate", nil)
	cursorLine:Hide()
	cursorTime:Hide()
	hovered = nil
	GameTooltip:Hide()
end)

------------------------------------------------------------------------
-- Rendu
------------------------------------------------------------------------
-- Suit la source cliquée dans la fenêtre d'origine ; garde la dernière quand le détail est fermé.
local function Follow()
	local win = state.win
	if win and win.selectedGuid and win.selectedGuid ~= state.guid then
		state.guid, state.name, state.scroll = win.selectedGuid, win.selectedName, 0
		wipe(state.expanded)
	end
end

-- Lignes dont le nom (valeur de tri) contient le filtre texte.
local function Filtered(lines)
	if not state.filter or state.filter == "" then return lines end
	local kept = {}
	for _, line in ipairs(lines) do
		if FM.MatchesFilter(line.values.name, state.filter) then kept[#kept + 1] = line end
	end
	return kept
end

local function RenderContent()
	Follow()
	local win = ShownWindow()
	for _, button in ipairs(tabButtons) do
		local selected = button.key == state.tab
		button.text:SetText(L[button.label])
		if selected then button.bg:SetColorTexture(0.35, 0.3, 0.1, 0.9) else button.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end
	end
	local label = FM.MODE_INFO[win.cfg.mode].label
	if win.cfg.mode ~= "threat" then label = label .. " · " .. Meter.SessionLabel(win, Meter.ReadSession(win)) end
	frame.title:SetText(string.format("%s : %s", state.name or "?", label))
	modeButton.text:SetText(FM.MODE_INFO[win.cfg.mode].label)
	sessionButton.text:SetText(win.cfg.mode == "threat" and "-" or Meter.SessionLabel(win))
	referenceButton.text:SetText(string.format(L.COMPARE_REFERENCE, state.reference and Meter.SessionLabel({ cfg = { view = state.reference } }) or "-"))
	referenceButton:SetShown(state.tab == "compare")
	pinButton.text:SetText(state.pinned and string.format(L.BREAKDOWN_PINNED, Meter.SpellName(state.pinned) or ("#" .. state.pinned)) or "")
	pinButton:SetShown(state.pinned ~= nil)

	local why
	tableArea:SetShown(state.tab ~= "timeline")
	if state.tab == "timeline" then
		HideTable()
		timeline:Show()
		help:SetText(L.TIMELINE_HELP)
		why = RenderTimeline(win)
		plot:SetShown(why == nil)
	else
		timeline:Hide()
		-- Chaque onglet rend (colonnes, lignes, total des lignes affichées) ou (nil, message).
		local columns, lines, totalOf
		if win.cfg.mode == "threat" then
			why = L.BREAKDOWN_NO_DATA
		elseif not state.guid then
			why = L.BREAKDOWN_NO_SOURCE
		elseif state.tab == "death" then
			columns, lines = DeathLines(win, state.guid)
		else
			local source = Meter.ReadSource(win, state.guid)
			if not source then
				why = L.BREAKDOWN_NO_DATA
			elseif state.tab == "targets" then
				columns, lines, totalOf = TargetLines(win, source)
			elseif state.tab == "compare" then
				columns, lines, totalOf = CompareLines(win, source)
			else
				columns, lines, totalOf = SpellLines(win, source)
			end
		end
		if columns then
			-- Le récap de mort garde l'ordre des coups : ni filtre ni tri.
			if state.tab ~= "death" then lines = Filtered(lines) end
			ShowTable(columns, lines, state.tab ~= "death", totalOf and totalOf(lines))
		else
			why = why or lines
			HideTable()
		end
	end
	message:SetText(why or "")
	message:SetShown(why ~= nil)
end

-- Une erreur de rendu vide la fenêtre et marque le titre, signalée une fois au gestionnaire d'erreurs du jeu.
local lastError
function Render()
	if not frame:IsShown() or not state.win then return end
	local ok, err = pcall(RenderContent)
	if ok then lastError = nil; return end
	HideTable()
	timeline:Hide()
	message:SetText("(!)")
	message:Show()
	if err ~= lastError then
		lastError = err
		geterrorhandler()(err)
	end
end

-- Rafraîchi chaque seconde tant qu'elle est ouverte : montants lisibles à la fin du combat, chronologie en direct.
local REFRESH_DELAY = 1
local sinceRender = 0
frame:SetScript("OnUpdate", function(_, elapsed)
	sinceRender = sinceRender + elapsed
	if sinceRender < REFRESH_DELAY then return end
	sinceRender = 0
	Render()
end)

local function Open(win)
	if not win then return end
	-- Autre fenêtre : source, mode, combats et sort épinglé repartent de ceux de la fenêtre.
	if state.win ~= win then state.guid, state.mode, state.view, state.reference, state.pinned = nil, nil, nil, nil, nil end
	state.win = win
	Follow()
	Meter.SkinFrame(frame, 0.9) -- habillage du thème, fond presque opaque pour la lecture du tableau
	frame:Show()
	sinceRender = 0
	Render()
end

-- Bouton « Tableau » dans le titre du panneau de détail.
local detail = ForeverMeterDetailFrame
local openButton = CreateFrame("Button", nil, detail.header)
openButton:SetSize(56, 16)
openButton:SetPoint("RIGHT", detail.close, "LEFT", -2, 0)
openButton.bg = openButton:CreateTexture(nil, "BACKGROUND")
openButton.bg:SetAllPoints()
openButton.bg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
openButton.text = openButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
openButton.text:SetPoint("CENTER")
openButton:SetScript("OnShow", function(self) self.text:SetText(L.BREAKDOWN_BUTTON) end)
openButton.text:SetText(L.BREAKDOWN_BUTTON)
openButton:SetScript("OnClick", function() Open(detail.owner) end)
detail.title:SetPoint("RIGHT", openButton, "LEFT", -4, 0)

NS.Breakdown = { Open = Open, Segments = segments }
-- Accès des tests hors jeu (uicheck.lua) aux éléments sans nom.
frame.tabs, frame.rows, frame.plot, frame.recorder, frame.help = tabButtons, rows, plot, recorder, help
frame.message, frame.toolbar = message, { mode = modeButton, session = sessionButton, reference = referenceButton, pin = pinButton, search = search }
