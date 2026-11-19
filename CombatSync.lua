-- Partage des lancers avec le groupe, pour la chronologie des autres joueurs.
-- Le jeu donne le détail des dégâts de chaque joueur, pas ses lancers : chaque ForeverMeter envoie les siens
-- au groupe en fin de combat (hors combat), par messages d'addon. Instants en heure du serveur, commune à tous.
local _, NS = ...
local FM = ForeverMeter
local L = NS.L
local issecretvalue = issecretvalue or function() return false end

local CHUNK_SIZE = 240          -- message d'addon : 255 caractères au plus, en-tête « id:n:total: » compris
local MAX_CHUNKS = 64
local MAX_SENT_CASTS = 1000     -- derniers lancers d'un combat envoyés : environ 30 morceaux
local MAX_KEPT_CASTS = 3000     -- lancers reçus gardés par joueur
local MAX_PLAYERS = 40          -- joueurs dont les lancers sont gardés, le plus ancien part au-delà
local MAX_OFFSET = 360000       -- une heure en centièmes : un combat plus long est hors forme

------------------------------------------------------------------------
-- Logique pure (testée hors jeu : selfcheck.lua)
------------------------------------------------------------------------
function FM.SplitChunks(text, size)
	local chunks = {}
	for i = 1, #text, size do chunks[#chunks + 1] = text:sub(i, i + size - 1) end
	return chunks
end

-- Données envoyées : { g = GUID, b = seconde serveur de base, c = { centièmes depuis b, spellID, ... } }.
-- serverStart : heure serveur de segment.start ; casts : { { t, spellID, result } }, t en secondes depuis segment.start.
-- Seuls les lancers partis sont envoyés (FM.CastLanded), sans durée d'incantation : le format reste le même.
-- Second retour : nombre de lancers partis, plus grand que ceux envoyés au-delà de MAX_SENT_CASTS.
function FM.BuildSyncPayload(guid, casts, serverStart)
	local base = math.floor(serverStart)
	local landed = {}
	for _, cast in ipairs(casts) do
		if FM.CastLanded(cast) then landed[#landed + 1] = cast end
	end
	local list = {}
	for i = math.max(1, #landed - MAX_SENT_CASTS + 1), #landed do
		list[#list + 1] = math.floor((serverStart + landed[i].t - base) * 100 + 0.5)
		list[#list + 1] = landed[i].spellID
	end
	return { g = guid, b = base, c = list }, #landed
end

-- Données reçues d'un autre joueur, non fiables : rend (guid, { { time, spellID } }) ou nil si la forme est fausse.
function FM.ReadSyncPayload(value)
	if type(value) ~= "table" or type(value.g) ~= "string" or type(value.c) ~= "table" then return nil end
	local base = value.b
	-- Entiers bornés seulement : un NaN ou un flottant servirait de clé de table (FM.CastTracks) et ferait échouer le rendu.
	if type(base) ~= "number" or base ~= math.floor(base) or base <= 0 or base >= 2 ^ 32 then return nil end
	local list = value.c
	if #list % 2 ~= 0 or #list > 2 * MAX_SENT_CASTS then return nil end
	local casts = {}
	for i = 1, #list, 2 do
		local offset, spellID = list[i], list[i + 1]
		if type(offset) ~= "number" or offset ~= math.floor(offset) or offset < 0 or offset > MAX_OFFSET
			or type(spellID) ~= "number" or spellID ~= math.floor(spellID) or spellID <= 0 or spellID >= 2 ^ 31 then
			return nil
		end
		casts[#casts + 1] = { time = base + offset / 100, spellID = spellID }
	end
	return value.g, casts
end

-- Lancers reçus entre deux heures serveur, en { t, spellID } relatifs à `from`.
function FM.CastsBetween(received, from, to)
	local casts = {}
	for _, cast in ipairs(received or {}) do
		if cast.time >= from and cast.time <= to then casts[#casts + 1] = { t = cast.time - from, spellID = cast.spellID } end
	end
	return casts
end

if not CreateFrame then return end

local PREFIX = "ForeverMeter"
local SEND_INTERVAL = 0.2
local MAX_RETRIES = 50          -- 10 s de limite de débit sur un même morceau, puis abandon signalé
local MAX_QUEUE = 2 * MAX_CHUNKS
-- Enum.SendAddonMessageResult : AddonMessageThrottle et ChannelThrottle, le morceau repart au tour suivant.
local THROTTLED = { [3] = true, [8] = true }
local LOCKDOWN = 11             -- AddOnMessageLockdown : messages bloqués pour un temps, le morceau attend sans limite
local NOT_IN_GROUP = 5          -- groupe quitté pendant l'envoi : plus personne à qui envoyer, abandon sans message
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local MAX_DECOMPRESSED = 65536  -- 1000 lancers font environ 10 Ko : au-delà, message refusé avant de construire la table

-- Raison de l'indisponibilité du partage sur ce client, nil quand tout est là.
local unavailable
if not (C_EncodingUtil and C_EncodingUtil.SerializeCBOR and C_EncodingUtil.DeserializeCBOR and C_ChatInfo and C_ChatInfo.SendAddonMessage) then
	unavailable = "API"
else
	-- Enum.RegisterAddonMessagePrefixResult : 0 Success, 1 DuplicatePrefix (déjà enregistré, utilisable).
	local result = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	if not (result == 0 or result == 1 or result == true) then unavailable = "prefix " .. tostring(result) end
end

local queue = {}
local failureShown = false
local sender = CreateFrame("Frame")
sender:Hide()

-- Échec d'envoi : le reste de la file est abandonné, le joueur prévenu une fois jusqu'au prochain envoi réussi.
local function Fail(reason)
	wipe(queue)
	sender:Hide()
	if failureShown then return end
	failureShown = true
	-- Code du client traduit en nom de Enum.SendAddonMessageResult quand il existe.
	for name, value in pairs(Enum and Enum.SendAddonMessageResult or {}) do
		if value == reason then reason = name; break end
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cffff9933ForeverMeter|r : " .. string.format(L.SYNC_SEND_FAILED, tostring(reason)))
end

-- Heure serveur au centième : GetServerTime() ne change qu'à la seconde, on relève l'instant où elle change.
-- Le relevé arrive une image après le changement, donc sous-estime l'écart : le plus grand de 5 relevés
-- écarte une image lente (écran de chargement). Avant le premier relevé, l'écart est juste à une seconde près.
local CLOCK_SAMPLES = 5
local clockOffset
local lastSecond
local samples = 0
local clock = CreateFrame("Frame")
clock:SetScript("OnUpdate", function(self)
	local second = GetServerTime()
	if lastSecond and second ~= lastSecond then
		clockOffset = math.max(clockOffset or -math.huge, second - GetTime())
		samples = samples + 1
		if samples >= CLOCK_SAMPLES then self:SetScript("OnUpdate", nil) end
	end
	lastSecond = second
end)

-- Heure serveur = GetTime() + ClockOffset().
local function ClockOffset() return clockOffset or (GetServerTime() - GetTime()) end

------------------------------------------------------------------------
-- Envoi : une file, un morceau toutes les 0,2 s
------------------------------------------------------------------------
-- Identifiant de départ tiré au hasard : après un /reload de l'expéditeur, ses nouveaux morceaux
-- ne se mêlent pas à un message resté incomplet chez les autres.
local messageID = math.random(999)
local retries = 0
local elapsed = 0
sender:SetScript("OnUpdate", function(self, delta)
	elapsed = elapsed + delta
	if elapsed < SEND_INTERVAL then return end
	elapsed = 0
	local message = queue[1]
	if not message then self:Hide(); return end
	local result = C_ChatInfo.SendAddonMessage(PREFIX, message.text, message.channel)
	if result == 0 or result == true then
		table.remove(queue, 1)
		retries, failureShown = 0, false
	elseif result == LOCKDOWN then
		return
	elseif THROTTLED[result] then
		retries = retries + 1
		if retries > MAX_RETRIES then Fail(result) end
	elseif result == NOT_IN_GROUP then
		wipe(queue)
		self:Hide()
	else
		-- Envoi refusé (messages bloqués sur le royaume ou en instance) : le reste du combat est abandonné.
		Fail(result)
	end
end)

-- Groupe de recherche : INSTANCE_CHAT vise le groupe d'instance, PARTY et RAID le groupe d'origine.
local function GroupChannel()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

-- Envoie au groupe les lancers d'un segment fermé (CombatBreakdown.lua).
local function Send(segment)
	local channel = GroupChannel()
	local guid = UnitGUID("player")
	if not channel or not guid or issecretvalue(guid) then return end
	local payload, landed = FM.BuildSyncPayload(guid, segment.casts, segment.start + segment.clockOffset)
	if #payload.c == 0 then return end -- aucun lancer parti
	if unavailable then Fail(unavailable); return end
	local sent = #payload.c / 2
	if sent < landed then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff9933ForeverMeter|r : " .. string.format(L.SYNC_TRUNCATED, sent, landed))
	end
	local compressed = C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(payload))
	local chunks = compressed and FM.SplitChunks(C_EncodingUtil.EncodeBase64(compressed), CHUNK_SIZE) or {}
	if #chunks == 0 or #chunks > MAX_CHUNKS then Fail("encode"); return end
	-- File encore pleine (messages bloqués depuis plusieurs combats) : les combats en attente cèdent la place au dernier.
	if #queue + #chunks > MAX_QUEUE then wipe(queue) end
	messageID = messageID % 999 + 1
	for i, chunk in ipairs(chunks) do
		queue[#queue + 1] = { channel = channel, text = messageID .. ":" .. i .. ":" .. #chunks .. ":" .. chunk }
	end
	sender:Show()
end

------------------------------------------------------------------------
-- Réception : morceaux réassemblés par expéditeur, lancers rangés par GUID
------------------------------------------------------------------------
local partial = {}   -- [expéditeur] = { id, count, parts, got } : un message en cours par joueur
local received = {}  -- [GUID] = { { time, spellID } }, heure serveur, dans l'ordre de réception
local receivedOrder = {}  -- GUID dans l'ordre de première réception, pour retirer le plus ancien

local function Store(text, from)
	-- Message corrompu, tronqué ou d'une autre version : ignoré, la chronologie de ce joueur reste vide.
	local ok, value = pcall(function()
		local raw = C_EncodingUtil.DecompressString(C_EncodingUtil.DecodeBase64(text))
		if type(raw) ~= "string" or #raw > MAX_DECOMPRESSED then return nil end
		return C_EncodingUtil.DeserializeCBOR(raw)
	end)
	if not ok then return end
	local guid, casts = FM.ReadSyncPayload(value)
	local me, senderGuid = UnitGUID("player"), UnitGUID(from)
	if not guid or issecretvalue(me) or guid == me then return end
	-- Un joueur n'écrit que ses propres lancers, quand son GUID est lisible.
	if senderGuid and not issecretvalue(senderGuid) and senderGuid ~= guid then return end
	if not received[guid] then
		receivedOrder[#receivedOrder + 1] = guid
		if #receivedOrder > MAX_PLAYERS then received[table.remove(receivedOrder, 1)] = nil end
	end
	local list = received[guid] or {}
	for _, cast in ipairs(casts) do list[#list + 1] = cast end
	if #list > MAX_KEPT_CASTS then
		local kept = {}
		for i = #list - MAX_KEPT_CASTS + 1, #list do kept[#kept + 1] = list[i] end
		list = kept
	end
	received[guid] = list
end

local listener = CreateFrame("Frame")
if not unavailable then NS.Meter.Register(listener, "CHAT_MSG_ADDON") end
listener:SetScript("OnEvent", function(_, _, prefix, text, channel, from)
	if issecretvalue(prefix) or issecretvalue(text) or issecretvalue(channel) or issecretvalue(from) or prefix ~= PREFIX then return end
	-- Groupe seulement : un chuchotement d'un inconnu n'écrit pas dans la chronologie.
	if not GROUP_CHANNELS[channel] then return end
	local id, index, count, chunk = text:match("^(%d+):(%d+):(%d+):(.+)$")
	index, count = tonumber(index), tonumber(count)
	if not id or count < 1 or count > MAX_CHUNKS or index < 1 or index > count then return end
	local entry = partial[from]
	if not entry or entry.id ~= id or entry.count ~= count then
		entry = { id = id, count = count, parts = {}, got = 0 }
		partial[from] = entry
	end
	if not entry.parts[index] then
		entry.parts[index], entry.got = chunk, entry.got + 1
	end
	if entry.got < count then return end
	partial[from] = nil
	Store(table.concat(entry.parts), from)
end)

NS.Sync = {
	ClockOffset = ClockOffset,
	Send = Send,
	CastsBetween = function(guid, from, to) return FM.CastsBetween(received[guid], from, to) end,
	-- Accès des tests hors jeu (uicheck.lua).
	sender = sender, listener = listener,
}
