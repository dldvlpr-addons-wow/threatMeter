-- luacheck . : vérifie l'addon (fichiers livrés). WoW Forever = Lua 5.1.
std = "lua51"
max_line_length = false
exclude_files = { "selfcheck.lua", "uicheck.lua", ".luarocks", "lua_modules" }

-- Globales écrites volontairement : réglages sauvegardés, raccourcis, commandes /fm.
globals = {
	"ForeverMeter",
	"ForeverMeterDB",
	"SlashCmdList",
	"SLASH_FOREVERMETER1",
	"SLASH_FOREVERMETER2",
	"BINDING_HEADER_FOREVERMETER",
	"BINDING_NAME_FOREVERMETER_TOGGLE",
	"BINDING_NAME_FOREVERMETER_RESET",
	"BINDING_NAME_FOREVERMETER_NEXT_MODE",
}

-- API du client (CreateFrame, C_*, UnitName…) : trop vaste pour une liste, lectures non signalées.
-- Une écriture de globale non listée ci-dessus reste signalée (local oublié).
ignore = { "113" }
