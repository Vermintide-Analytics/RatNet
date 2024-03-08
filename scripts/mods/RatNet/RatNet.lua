local mod = get_mod("RatNet")

Wwise.load_bank("wwise/mods/RatNet/DERP_SFX")

mod.version = "1.0.2"
mod:echo("RatNet version: " .. mod.version)

local BASE_ENDPOINT = "http://52.54.79.134:81/"
--local BASE_ENDPOINT = "http://localhost:5000/"
local HEARTBEAT_INTERVAL_SECONDS = 5

local initialize = true
local recovery_status = {}

local session_active = false
local do_heartbeat = false
local time_of_next_heartbeat = 0

-- Set setting defaults as specified
if mod:get("use_default_lobby_state") then
	mod:set("lobby_state", mod:get("default_lobby_state"))
end
if mod:get("use_default_use_desired_players") then
	mod:set("use_desired_players", mod:get("default_use_desired_players"))
	mod:set("desired_players", mod:get("default_desired_players"))
end

local lobby_state = mod:get("lobby_state")

-- ### <CACHED DATA> ###
local cached_lobby_id = nil
local cached_lobby_public = nil
local cached_lobby_max_players = nil

local cached_difficulty = nil

local player_careers_cache = {}
local remote_player_ids = {}

local cached_location = nil
local location_changed_time = os.time()

local cached_sub_location = nil

local last_sent_intent = nil
local intent_command_used = false

local last_sent_stream_links = {}
local last_sent_stream_link = nil

local num_bots = 0

local cached_mod_mutator_state = {}

local reset_cached_data = function()
	cached_lobby_id = nil
	cached_lobby_public = nil
	cached_lobby_max_players = nil

	cached_difficulty = nil

	player_careers_cache = {}
	remote_player_ids = {}

	cached_location = nil
	location_changed_time = os.time()

	cached_sub_location = nil

	last_sent_intent = nil
	
	last_sent_stream_links = {}
	last_sent_stream_link = nil
	
	num_bots = 0
	
	cached_mod_mutator_state = {}
end
-- ### </CACHED DATA> ###

local max_player_override = (mod:get("use_desired_players") and mod:get("desired_players")) or 9999

local our_heroes_party = function()
	return Managers.party and Managers.party:get_party_from_name("heroes")
end

local auto_approve_join_list = mod:get("auto_approve_join_list") or {}

local intent = mod:get("default_intent")
mod:set("intent", intent)
local stream_links = {
	[Steam.user_id()] = mod:get("stream_link")
}

local debug_mode = mod:get("debug_mode")
local debug_echo = function(to_print)
	if debug_mode then
		mod:echo(to_print)
	else
		print(to_print)
	end
end

local debug_echo_callback = function(callback_name, code, data)
	debug_echo("RATNET-CALLBACK: " .. callback_name .. " - " .. tostring(code))
	if code ~= 200 and data then
		debug_echo(tostring(data)) -- data should be a json string
	end
end

local attempt_play_sound = function(event_name)
	if not event_name then
		return
	end
	
	local world = Managers.world and (
		Managers.world:has_world("level_world") and Managers.world:world("level_world") or 
		Managers.world:has_world("loading_world") and Managers.world:world("loading_world") or
		Managers.world:has_world("top_ingame_view") and Managers.world:world("top_ingame_view"))
	if not world then
		return
	end
	local wwise_world = Wwise.wwise_world(world)
	if not wwise_world then
		return
	end
    WwiseWorld.trigger_event(wwise_world, event_name)
end
local get_join_request_sound_event = function()
	local setting = mod:get("join_request_sound")
	if setting == "pusfume" then
		return "Notify_Pusfume"
	elseif setting == "saltzpyre" then
		return "Notify_Saltzpyre"
	elseif setting == "bass" then
		return "Notify_Bass"
	elseif setting == "dings" then
		return "Notify_Dings"
	elseif setting == "strings" then
		return "Notify_StringsPizzi"
	elseif setting == "conga" then
		return "Notify_Conga"
	elseif setting == "orchestra" then
		return "Notify_Orchestra"
	elseif setting == "torgue" then
		return "Notify_Torgue"
	elseif setting == "darksouls" then
		return "Notify_DarkSouls"
	elseif setting == "hellothere" then
		return "Notify_HelloThere"
	elseif setting == "exalt" then
		return "Notify_Exalt"
	elseif setting == "vvvg" then
		return "Notify_VVVG"
	elseif setting == "startrek" then
		return "Notify_StarTrek"
	elseif setting == "terraria" then
		return "Notify_Terraria"
	elseif setting == "wololo" then
		return "Notify_Wololo"
	end
end
local join_request_sound_event_name = get_join_request_sound_event()

mod.validate_stream_link = function(link)
	local twitch_patterns = { "^https://twitch%.tv/[%w%p]+", "^https://www%.twitch%.tv/[%w%p]+" }
	--local youtube_patterns = { "^https://youtube%.com/live/[%w%p]+", "^https://www%.youtube%.com/live/[%w%p]+"}
	
	local is_twitch = false
	for _,pattern in ipairs(twitch_patterns) do
		if link:find(pattern) then
			is_twitch = true
		end
	end
	--local is_youtube = false
	--for _,pattern in ipairs(youtube_patterns) do
	--	if link:find(pattern) then
	--		is_youtube = true
	--	end
	--end
	
	return is_twitch --or is_youtube
end
mod.standardize_stream_link = function(link)
	if link == "" or not link then
		return link
	end

	local https_pattern = "^https://"
	
	if link:find(https_pattern) then
		return link
	end
	return "https://" .. link
end










-- ############################################################################
-- ## Mod state evaluation ####################################################
-- ############################################################################

local deathwish_mod_name = "catas"
local onslaught_mod_name = "Onslaught"
local onslaughtplus_mod_name = "OnslaughtPlus"
local spicyonslaught_mod_name = "SpicyOnslaught"
local dutchspice_mod_name = "DutchSpice"
local dutch_mod_name = "DutchSpiceTourney"
local dense_onslaught_name = "Dense Onslaught"

local cores_big_rebalance_name = "Weapon Balance"
local class_balance_name = "Class Balance"
local tourney_balance_name = "TourneyBalance"
local live_remastered_name = "LiveRemastered"

local function is_mod_mutator_enabled(mod_name, mutator_name)
  local other_mod = get_mod(mod_name)
  local mod_is_enabled = false
  local mutator_is_enabled = false
  if other_mod then
    local omutator = other_mod:persistent_table(mutator_name)
    mod_is_enabled = other_mod:is_enabled()
    mutator_is_enabled = omutator.active
  end
  return mod_is_enabled and mutator_is_enabled
end

local function is_deathwish_enabled()
	return is_mod_mutator_enabled(deathwish_mod_name, deathwish_mod_name)
end

local function is_onslaught_enabled()
	return is_mod_mutator_enabled(onslaught_mod_name, onslaught_mod_name)
end

local function is_onslaughtplus_enabled()
	return is_mod_mutator_enabled(onslaughtplus_mod_name, onslaughtplus_mod_name)
		
end

local function is_onslaughtsquared_enabled()
	return is_mod_mutator_enabled(onslaughtplus_mod_name, "OnslaughtSquared")
end

local function is_osplus_morespecials_enabled()
	return is_mod_mutator_enabled(onslaughtplus_mod_name, "MoreSpecials")
end

local function is_osplus_moreambients_enabled()
	return is_mod_mutator_enabled(onslaughtplus_mod_name, "MoreAmbients")
end

local function is_osplus_morehordes_enabled()
	return is_mod_mutator_enabled(onslaughtplus_mod_name, "MoreHordes")
end

local function is_makeitharder_enabled()
	return is_mod_mutator_enabled(onslaughtplus_mod_name, "EnhancedDifficulty")
end

local function is_beastmenrework_enabled()
	return is_mod_mutator_enabled(onslaughtplus_mod_name, "BeastmenRework")
end

local function is_spicyonslaught_enabled()
	return is_mod_mutator_enabled(spicyonslaught_mod_name, "SpicyOnslaught")
end

local function is_dutchspice_enabled()
	return is_mod_mutator_enabled(dutchspice_mod_name, "DutchSpice")
end

local function is_dutch_enabled()
	return is_mod_mutator_enabled(dutch_mod_name, "DutchSpiceTourney")
end

local function is_dense_enabled()
	return is_mod_mutator_enabled(dense_onslaught_name, "DenseOnslaught")
end

local function get_deathwish()
	if is_deathwish_enabled() then
		return "Deathwish"
	end
	return nil
end

local function get_os_plus_squared_modifiers()
		local more_specials = is_osplus_morespecials_enabled() and ", MoreSpecials" or ""
		local more_ambients = is_osplus_moreambients_enabled() and ", MoreAmbients" or ""
		local more_hordes = is_osplus_morehordes_enabled() and ", MoreHordes" or ""
		local makeitharder = is_makeitharder_enabled() and ", MakeItHarder" or ""
		local beastmen_rework = is_beastmenrework_enabled() and ", BeastmenRework" or ""
		
		return makeitharder .. beastmen_rework .. more_specials .. more_hordes .. more_ambients
end

local function get_onslaught()
	if is_onslaught_enabled() then
		return "Onslaught"
	elseif is_onslaughtplus_enabled() then
		local osplus_output = "Onslaught+"
		local modifiers = get_os_plus_squared_modifiers()
		if modifiers == "" then
			return osplus_output
		end
		modifiers = modifiers:gsub("^, ", "")
		
		return osplus_output .. " (" .. modifiers .. ")"
	elseif is_onslaughtsquared_enabled() then
		local ossquared_output = "Onslaught^2"
		local modifiers = get_os_plus_squared_modifiers()
		if modifiers == "" then
			return ossquared_output
		end
		modifiers = modifiers:gsub("^, ", "")
		
		return ossquared_output .. " (" .. modifiers .. ")"
	elseif is_spicyonslaught_enabled() then
		return "Spicy Onslaught"
	elseif is_dutchspice_enabled() then
		return "Dutch Spice"
	elseif is_dutch_enabled() then
		return "Dutch Spice Tourney"
	elseif is_dense_enabled() then
		return "Dense Onslaught"
	end
	return nil
end

local function get_peregrinaje()
	local peregrinaje = get_mod("Peregrinaje")
	if not peregrinaje or not peregrinaje:persistent_table("Peregrinaje") then
		return nil
	end
	if peregrinaje:persistent_table("Peregrinaje").active then
		return "Peregrinaje"
	end
	return nil
end

local function get_enigma()
	if get_mod("Enigma") then
		return "Enigma"
	end
	return nil
end

local function get_U5()
	if get_mod("UbersreikFive") then
		return "U5"
	end
	return nil
end

local function get_BTMP()
	if get_mod("MorePlayers2") then
		return "BTMP"
	end
	return nil
end

local function get_balance()
	if get_mod(cores_big_rebalance_name) then
		return "Core's Big Rebalance"
	elseif get_mod(class_balance_name) then
		return "Class Balance"
	elseif get_mod(tourney_balance_name) then
		return "Tourney Balance"
	elseif get_mod(live_remastered_name) then
		return "LiveRemastered"
	end
	return nil
end

local function get_any_weapon()
	if get_mod("AnyWeapon") then
		return "Any Weapon"
	end
	return nil
end

local function get_local_mod_mutator_state()
	return {
		["deathwish"] = get_deathwish(),
		["onslaught"] = get_onslaught(),
		["peregrinaje"] = get_peregrinaje(),
		["enigma"] = get_enigma(),
		["U5"] = get_U5(),
		["BTMP"] = get_BTMP(),
		["balance"] = get_balance(),
		["anyweapon"] = get_any_weapon()
	}
end


local function mod_mutator_state_changed(state)
	return state.deathwish ~= cached_mod_mutator_state.deathwish or
		state.onslaught ~= cached_mod_mutator_state.onslaught or
		state.peregrinaje ~= cached_mod_mutator_state.peregrinaje or
		state.enigma ~= cached_mod_mutator_state.enigma or
		state.U5 ~= cached_mod_mutator_state.U5 or
		state.BTMP ~= cached_mod_mutator_state.BTMP or
		state.balance ~= cached_mod_mutator_state.balance or
		state.anyweapon ~= cached_mod_mutator_state.anyweapon
end











-- ############################################################################
-- ## HTTP and callbacks ######################################################
-- ############################################################################

local get_level_key = function()
	local game_mode = Managers.state.game_mode
	local transition_handler = Managers.level_transition_handler
	local level_key = nil
	if game_mode then
		level_key = game_mode:level_key()
	elseif transition_handler then
		level_key = transition_handler:get_current_level_key()
	end
	if not level_key then
		return nil
	end

	if level_key == "arena_belakor" then
		return level_key
	end

	-- Remove Chaos Wastes name modifiers
	level_key = level_key:gsub("_wastes", "")
	level_key = level_key:gsub("_khorne", "")
	level_key = level_key:gsub("_nurgle", "")
	level_key = level_key:gsub("_slaanesh", "")
	level_key = level_key:gsub("_tzeentch", "")
	level_key = level_key:gsub("_belakor", "")
	level_key = level_key:gsub("_path(%d+)", "")
	level_key = level_key:gsub("_%a$", "")

	return level_key
end
local format_level_key = function(level_key)
	if not level_key then
		return nil
	end

	if level_key == "arena_belakor" then
		return level_key
	end

	-- Remove Chaos Wastes name modifiers
	level_key = level_key:gsub("_wastes", "")
	level_key = level_key:gsub("_khorne", "")
	level_key = level_key:gsub("_nurgle", "")
	level_key = level_key:gsub("_slaanesh", "")
	level_key = level_key:gsub("_tzeentch", "")
	level_key = level_key:gsub("_belakor", "")
	level_key = level_key:gsub("_path(%d+)", "")
	level_key = level_key:gsub("_%a$", "")

	return level_key
end

local HEARTBEAT_HEADERS = {
	"accept: */*"
}
local POST_HEADERS = {
	"accept: */*",
	"Content-Type: application/json"
}

local POST = function(url, body, callback)
	local body_json = cjson.encode(body)
	Managers.curl:post(url, body_json, POST_HEADERS, callback)
end

-- <utility>
local get_lobby_details = function()
	local lobby_id = ""
	local is_public = false
	
	local network_max_players = Managers.mechanism._lobby.max_members
	local max_players = math.min(max_player_override, network_max_players)
	
	local heroes_party = our_heroes_party()
	local num_players = heroes_party and (heroes_party.num_used_slots - heroes_party.num_bots)
	
	if not num_players then
		mod:echo("RatNet: Unable to determine current number of players in party when syncing lobby to server. Assuming 1 player for now. Please report this issue to Prismism")
		num_players = 1
	end
	
	if num_players < max_players and lobby_state ~= "closed" then
		lobby_id = Managers.state.network:lobby():id()
	end
	if lobby_state == "public" then
		is_public = true
	end
	
	return lobby_id, is_public, max_players
end

local lobby_details_have_changed = function(id, public, max_players)
	return id ~= cached_lobby_id or
		public ~= cached_lobby_public or
		max_players ~= cached_lobby_max_players
end
-- </utility>

local lobby_updated_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("lobby_updated", code, data)
end

local lobby_updated = function()
	if not Managers.player.is_server then
		return
	end
	
	local lobby_id, is_public, max_players = get_lobby_details()
	if not lobby_details_have_changed(lobby_id, is_public, max_players) then
		return
	end
	
	cached_lobby_id = lobby_id
	cached_lobby_public = is_public
	cached_lobby_max_players = max_players
	
	local body = {
		["hostSteamId"] = Steam.user_id()
	}
	
	body["lobbyId"] = lobby_id
	body["isPublic"] = is_public
	body["maxPlayers"] = max_players

	mod:dump(body, "RATNET-POSTBODY: LobbyUpdated", 1)
	
	-- TODO REMOVE EXTRA PRINTOUT
	local heroes_party = our_heroes_party()
	local num_players = heroes_party and (heroes_party.num_used_slots - heroes_party.num_bots)
	print("RATNET-POSTDEBUG: num_players=" .. tostring(num_players))
	
	POST(BASE_ENDPOINT .. "api/Session/LobbyUpdated", body, lobby_updated_callback)
end


local location_updated_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("location_updated", code, data)
end

local location_updated = function(location)	
	local body = {
		["hostSteamId"] = Steam.user_id(),
		["location"] = format_level_key(location)
	}

	mod:dump(body, "RATNET-POSTBODY: LocationUpdated", 1)
	POST(BASE_ENDPOINT .. "api/Session/LocationUpdated", body, location_updated_callback)
end


local sub_location_updated_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("sub_location_updated", code, data)
	if recovery_status.location then
		if code == 200 then
			recovery_status.location = nil
			debug_echo("RatNet: Recovery mode successfully synced current location.")
		else
			recovery_status.location = "failed"
			mod:echo("RatNet: Recovery mode could not sync current location. Discord may show incorrect values until location is next updated.")
		end
	end
end

local sub_location_updated = function(location)	
	local body = {
		["hostSteamId"] = Steam.user_id(),
		["subLocation"] = format_level_key(location)
	}
	
	if Managers.localizer and Managers.localizer._language_id == "en" then
		body["subLocationName"] = Localize(location)
	end

	mod:dump(body, "RATNET-POSTBODY: SubLocationUpdated", 1)
	POST(BASE_ENDPOINT .. "api/Session/SubLocationUpdated", body, sub_location_updated_callback)
end


local difficulty_updated_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("difficulty_updated", code, data)
	if recovery_status.difficulty then
		if code == 200 then
			recovery_status.difficulty = nil
			debug_echo("RatNet: Recovery mode successfully synced current difficulty.")
		else
			recovery_status.difficulty = "failed"
			mod:echo("RatNet: Recovery mode could not sync current difficulty. Discord may show incorrect values until difficulty is next updated.")
		end
	end
end

local difficulty_updated = function(difficulty)	
	local body = {
		["hostSteamId"] = Steam.user_id(),
		["difficulty"] = difficulty
	}

	mod:dump(body, "RATNET-POSTBODY: DifficultyUpdated", 1)
	POST(BASE_ENDPOINT .. "api/Session/DifficultyUpdated", body, difficulty_updated_callback)
end


local intent_updated_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("intent_updated", code, data)
	if code == 200 then
		if intent_command_used then
			if last_sent_intent == nil then
				mod:echo("LFG message has been cleared")
			else
				mod:echo("LFG message set to: \"" .. tostring(last_sent_intent) .. "\"")
			end
			intent_command_used = false
		end
	end
	
	if recovery_status.intent then
		if code == 200 then
			recovery_status.intent = nil
			debug_echo("RatNet: Recovery mode successfully synced current LFG message.")
		else
			recovery_status.intent = "failed"
			mod:echo("RatNet: Recovery mode could not sync current LFG message. Discord may show incorrect values until you run /lfg again.")
		end
	end
end

local intent_updated = function()
	local body = {
		["hostSteamId"] = Steam.user_id(),
		["intent"] = intent or "null"
	}

	last_sent_intent = intent
	mod:dump(body, "RATNET-POSTBODY: IntentUpdated", 1)
	POST(BASE_ENDPOINT .. "api/Session/IntentUpdated", body, intent_updated_callback)
end


local stream_link_updated_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("stream_link_updated", code, data)
	if code == 200 then
		if last_sent_stream_link == nil then
			debug_echo("Stream link has been cleared")
		else
			debug_echo("Stream link set to: \"" .. tostring(last_sent_stream_link) .. "\"")
		end
	end
	
	if recovery_status.stream_links then
		recovery_status.stream_links.expected = recovery_status.stream_links.expected - 1
		if code == 200 then
			recovery_status.stream_links.sycned = recovery_status.stream_links.synced + 1
		else
			recovery_status.stream_links.failed = recovery_status.stream_links.failed + 1
		end
		
		if recovery_status.stream_links.expected == 0 then
			if recovery_status.stream_links.failed > 0 then
			mod:echo("RatNet: Recovery mode could not sync current stream links. Discord may show incorrect values until you run /stream again.")
			else
			debug_echo("RatNet: Recovery mode successfully synced current stream links.")
			end
		end
	end
end

local stream_link_updated = function(player_id)
	local body = {
		["hostPlayerSteamId"] = Steam.user_id(),
		["playerSteamId"] = player_id,
		["streamLink"] = mod.standardize_stream_link(stream_links[player_id])
	}

	last_sent_stream_links[player_id] = stream_links[player_id]
	last_sent_stream_link = last_sent_stream_links[player_id]
	mod:dump(body, "RATNET-POSTBODY: PlayerChangedStreamLink", 1)
	POST(BASE_ENDPOINT .. "api/Session/PlayerChangedStreamLink", body, stream_link_updated_callback)
end


local player_changed_career_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("player_changed_career", code, data)
end

local player_changed_career = function(steam_id, career)
	if not Managers.player.is_server then
		return
	end

	if not steam_id then
		mod:echo("RatNet: Unknown player changed career. Please report this error to Prismism.")
		return
	end
	if not career then
		mod:echo("RatNet: Player switched to unknown career. Please report this error to Prismism.")
		return
	end

	local body = {
		["hostPlayerSteamId"] = Steam.user_id(),
		["playerSteamId"] = steam_id,
		["playerCareerName"] = career
	}
	
	mod:dump(body, "RATNET-POSTBODY: PlayerChangedCareer", 1)
	POST(BASE_ENDPOINT .. "api/Session/PlayerChangedCareer", body, player_changed_career_callback)
end


local mod_list_updated_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("mod_list_updated", code, data)
end

local mod_list_updated = function(mods)
	if not Managers.player.is_server then
		return
	end

	if not mods then
		mod:echo("RatNet: Could not determine active mods. Please report this error to Prismism.")
		return
	end

	local body = {
		["hostPlayerSteamId"] = Steam.user_id(),
		["modList"] = mods
	}
	
	mod:dump(body, "RATNET-POSTBODY: ModListUpdated", 1)
	POST(BASE_ENDPOINT .. "api/Session/ModListUpdated", body, mod_list_updated_callback)
end


local join_request_acknowledged_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("join_request_acknowledged", code, data)
end

local join_request_acknowledged = function(request, approved)
	local body = {
		["hostPlayerSteamId"] = Steam.user_id(),
		["requesterId"] = request.id,
		["approved"] = approved
	}
	
	mod:dump(body, "RATNET-POSTBODY: JoinRequestAcknowledged", 1)
	POST(BASE_ENDPOINT .. "api/Session/JoinRequestAcknowledged", body, join_request_acknowledged_callback)
end


local bots_changed_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("bots_changed", code, data)
end

local bots_changed = function()	
	local body = {
		["hostPlayerSteamId"] = Steam.user_id(),
		["numBots"] = num_bots
	}
	
	mod:dump(body, "RATNET-POSTBODY: BotsChanged", 1)
	POST(BASE_ENDPOINT .. "api/Session/BotsChanged", body, bots_changed_callback)
end


-- <utility>
local evaluate_mod_state = function()
	local mod_mutator_state = get_local_mod_mutator_state()
	if mod_mutator_state_changed(mod_mutator_state) then
		local list = ""
		if mod_mutator_state.onslaught then
			list = list .. mod_mutator_state.onslaught
		end
		if mod_mutator_state.deathwish then
			list = list .. "," .. mod_mutator_state.deathwish
		end
		if mod_mutator_state.peregrinaje then
			list = list .. "," .. mod_mutator_state.peregrinaje
		end
		if mod_mutator_state.enigma then
			list = list .. "," .. mod_mutator_state.enigma
		end
		if mod_mutator_state.U5 then
			list = list .. "," .. mod_mutator_state.U5
		end
		if mod_mutator_state.BTMP then
			list = list .. "," .. mod_mutator_state.BTMP
		end
		if mod_mutator_state.balance then
			list = list .. "," .. mod_mutator_state.balance
		end
		if mod_mutator_state.anyweapon then
			list = list .. "," .. mod_mutator_state.anyweapon
		end
		
		list = list:gsub("^,", "")
		mod_list_updated(list)
		cached_mod_mutator_state = mod_mutator_state
	end
end

local evaluate_number_of_bots = function()
	local new_bot_count = 0
	if Managers.player then
		new_bot_count = Managers.player:num_players() - Managers.player:num_human_players()
	end
	
	if new_bot_count ~= num_bots then
		num_bots = new_bot_count
		bots_changed()
	end
end

-- </utility>


local player_joined_session_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("player_joined_session", code, data)
	if recovery_status.players and recovery_status.players.expected > 0 then
		recovery_status.players.expected = recovery_status.players.expected - 1
		if code == 200 then
			recovery_status.players.synced = recovery_status.players.synced + 1
		else
			recovery_status.players.failed = recovery_status.players.failed + 1
		end
		
		if recovery_status.players.expected == 0 then
			if recovery_status.players.failed > 0 then
				mod:echo("RatNet: Recovery mode failed to sync " .. tostring(recovery_status.players.failed) .. " players in the session. Discord may show incorrect values until players leave and join again.")
			else
				debug_echo("RatNet: Recovery mode successfully synced current players.")
			end
			recovery_status.players = nil
		end
	end
end

local player_joined_session = function(steam_id, name, career)
	if not Managers.player.is_server then
		return
	end

	local body = {
		["hostPlayerSteamId"] = Steam.user_id(),
		["playerSteamId"] = steam_id,
		["playerName"] = name,
		["playerCareerName"] = career
	}
	
	mod:dump(body, "RATNET-POSTBODY: PlayerJoinedSession", 1)
	POST(BASE_ENDPOINT .. "api/Session/PlayerJoinedSession", body, player_joined_session_callback)
end


local player_left_session_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("player_left_session", code, data)
end

local player_left_session = function(steam_id)
	if not Managers.player.is_server then
		return
	end

	local body = {
		["hostPlayerSteamId"] = Steam.user_id(),
		["playerSteamId"] = steam_id
	}
	
	mod:dump(body, "RATNET-POSTBODY: PlayerLeftSession", 1)
	POST(BASE_ENDPOINT .. "api/Session/PlayerLeftSession", body, player_left_session_callback)
end


local end_session_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("end_session", code, data)
end

local end_session = function()
	if not session_active then
		return
	end
	
	session_active = false
	reset_cached_data()
	
	local body = {
		["hostSteamId"] = Steam.user_id()
	}

	mod:dump(body, "RATNET-POSTBODY: EndSession", 1)
	POST(BASE_ENDPOINT .. "api/Session/EndSession", body, end_session_callback)
end


local begin_session_callback = function(success, code, headers, data, userdata)
	debug_echo_callback("begin_session", code, data)
	if code == 200 then	
		session_active = true
		
		if recovery_status.begin then
			recovery_status.begin = nil
			
			-- Force re-sync of data
			cached_mod_mutator_state = {}
			evaluate_mod_state()
			num_bots = 0
			evaluate_number_of_bots()
			
			
			if Managers.player then
				debug_echo("RatNet: Beginning player recovery")
				recovery_status.players = {
					["expected"] = 0,
					["synced"] = 0,
					["failed"] = 0
				}
				for _,player in pairs(Managers.player:human_players()) do
					if not (player == Managers.player:local_human_player()) then
						recovery_status.players.expected = recovery_status.players.expected + 1
					end
				end
				if recovery_status.players.expected == 0 then
					debug_echo("RatNet: Skipping player recovery: no other players to sync")
				else
					for _,player in pairs(Managers.player:human_players()) do
						if not (player == Managers.player:local_human_player()) then
							player_joined_session(player.peer_id, player:name(), player:career_name())
						end
					end
				end
				
				if cached_sub_location then
					debug_echo("RatNet: Beginning location recovery")
					recovery_status.location = true
					sub_location_updated(cached_sub_location)
				else					
					debug_echo("RatNet: Skipping location recovery")
				end
					
			else
				debug_echo("RatNet: Skipping player recovery, could not determine players in current session")
				debug_echo("RatNet: Skipping location recovery")
			end
			
			if Managers.state and Managers.state.difficulty then
				debug_echo("RatNet: Beginning difficulty recovery")
				recovery_status.difficulty = true
				local difficulty, tweak = Managers.state.difficulty:get_difficulty()
				difficulty_updated(difficulty or "")
			else
				debug_echo("RatNet: Skipping difficulty recovery")
			end
			
			if intent then
				recovery_status.intent = true
				intent_updated()
			else
				debug_echo("RatNet: Skipping intent recovery, no intent to sync")
			end
			
			
			recovery_status.stream_links = {
				["expected"] = 0,
				["synced"] = 0,
				["failed"] = 0,
			}
			for player_id,link in pairs(stream_links) do
				if player_id ~= Steam.user_id() then
					recovery_status.stream_links.expected = recovery_status.stream_links.expected + 1
				end
			end
			if recovery_status.stream_links.expected > 0 then
				for player_id,link in pairs(stream_links) do
					if player_id ~= Steam.user_id() then
						stream_link_updated(player_id)
					end
				end
			else
				debug_echo("RatNet: Skipping stream link recovery, no links to sync")
			end
		elseif intent then
			intent_updated()
		end
	end
end

local begin_session = function()
	if not Managers.player.is_server then
		return
	end
	time_of_next_heartbeat = os.time() + HEARTBEAT_INTERVAL_SECONDS
	do_heartbeat = true
	if not Managers.player:local_human_player() then
		mod:echo("RatNet: Was not able to read player info when beginning session. Please report this to Prismism")
		return
	end
	if not Managers.player:local_human_player():name() then
		mod:echo("RatNet: Was not able to read player name when beginning session. Please report this to Prismism")
		return
	end
	if not Managers.player:local_human_player():career_name() then
		mod:echo("RatNet: Was not able to read player career when beginning session. Please report this to Prismism")
		return
	end
	
	local level_key = get_level_key()
	if not level_key then
		mod:echo("RatNet: Was not able to determine location when beginning session. Please report this to Prismism")
		return
	end

	if not recovery_status.begin then
		location_changed_time = os.time()
	end

	local body = {
		["hostSteamId"] = Steam.user_id(),
		["hostPlayerName"] = Managers.player:local_human_player():name(),
		["hostCareerName"] = Managers.player:local_human_player():career_name(),
		["location"] = format_level_key(level_key),
		["locationChangedTime"] = os.time() - location_changed_time,
		["streamLink"] = stream_links[Steam.user_id()]
	}
	
	if Managers.account and Managers.account:region() then
		body["region"] = Managers.account:region()
	end
	
	local lobby_id, is_public, max_players = get_lobby_details()
	cached_lobby_id = lobby_id
	cached_lobby_public = is_public
	cached_lobby_max_players = max_players
	
	body["lobbyId"] = lobby_id
	body["isPublic"] = is_public
	body["maxPlayers"] = max_players

	mod:dump(body, "RATNET-POSTBODY: BeginSession", 1)
	POST(BASE_ENDPOINT .. "api/Session/BeginSession", body, begin_session_callback)
end

local pending_join_requests = {}
local handle_join_requests = function(requests)
	for _,request in ipairs(requests) do
		if request.state == "Pending" then
			local approved_automatically = false
			for _,auto_approved in pairs(auto_approve_join_list) do
				if auto_approved.id == request.requesterId then
					approved_automatically = true
					break
				end
			end
			
			attempt_play_sound(join_request_sound_event_name)
			
			if approved_automatically then
				local approved_request = {
					["id"] = request.requesterId,
					["name"] = request.requesterName
				}
				join_request_acknowledged(approved_request, true)
				mod:echo(request.requesterName .. " has been automatically approved to join your game.")
			else		
				local loc_req_id = #pending_join_requests+1
				pending_join_requests[loc_req_id] = {
					["id"] = request.requesterId,
					["name"] = request.requesterName
				}
				local id_str = tostring(loc_req_id)
				mod:echo(request.requesterName .. " would like to join your game. Type:\n\"/approve " .. id_str .. "\" or\n\"/autoapprove " .. id_str .. "\" or\n\"/deny " .. id_str .. "\"\n")
			end
		elseif request.state == "TimedOut" then
			local timed_out = {}
			for key,value in pairs(pending_join_requests) do
				if value.id == request.requesterId then
					timed_out[#timed_out] = key
				end
			end
			for _,value in pairs(timed_out) do
				mod:echo("The request from " .. pending_join_requests[value].name .. " to join your game has expired.")
				pending_join_requests[value] = nil
			end
		end
	end
end

local heartbeat_callback = function(success, code, headers, data, userdata)
	if code == 205 then
		debug_echo("RatNet: Server reported that your session is not synced. Entering recovery mode...")
		session_active = false
		recovery_status.begin = true
	elseif code == 200 then
		if data then
			local decoded = cjson.decode(data)
			if decoded and decoded.joinRequests then
				handle_join_requests(decoded.joinRequests)
			end
		end
	end
end

local heartbeat = function()
	Managers.curl:get(BASE_ENDPOINT .. "api/Session/Heartbeat?steamId=" .. Steam.user_id(), HEARTBEAT_HEADERS, heartbeat_callback)
end






-- ############################################################################
-- ## RPCs ####################################################################
-- ############################################################################

mod:network_register("client_stream_link", function(sender, steam_id, stream_link)
	if Managers.player and Managers.player.is_server then
		stream_links[steam_id] = stream_link
		stream_link_updated(steam_id)
	end
end)









-- ############################################################################
-- ## Commands ################################################################
-- ############################################################################

mod:command("public", "Make your lobby available for Discord users to freely join.", function()
	mod:set("lobby_state", "public")
	lobby_state = mod:get("lobby_state")
	if session_active then
		lobby_updated()
	end
end)
mod:command("private", "Make your lobby available to Discord users to request to join.", function()
	mod:set("lobby_state", "private")
	lobby_state = mod:get("lobby_state")
	if session_active then
		lobby_updated()
	end
end)
mod:command("closed", "Make your lobby no-longer available to Discord users.", function()
	mod:set("lobby_state", "closed")
	lobby_state = mod:get("lobby_state")
	if session_active then
		lobby_updated()
	end
end)

mod:command("autoapprove", "Approve a Discord user's request to join, and add them to a local list of users which will automatically be able to join without approval in the future.", function(loc_id)
	local request = pending_join_requests[tonumber(loc_id)]
	if request then
		auto_approve_join_list[#auto_approve_join_list+1] = request
		mod:set("auto_approve_join_list", auto_approve_join_list)
		
		join_request_acknowledged(request, true)
		pending_join_requests[tonumber(loc_id)] = nil
	end
end)
mod:command("approve", "Approve a Discord user's request to join.", function(loc_id)
	local request = pending_join_requests[tonumber(loc_id)]
	if request then
		join_request_acknowledged(request, true)
		pending_join_requests[tonumber(loc_id)] = nil
	end
end)
mod:command("deny", "Deny a Discord user's request to join.", function(loc_id)
	local request = pending_join_requests[tonumber(loc_id)]
	if request then
		join_request_acknowledged(request, false)
		pending_join_requests[tonumber(loc_id)] = nil
	end
end)

mod:command("listautoapprovals", "Show a list of Discord usernames for which you have chosen to automatically approve join requests.", function()
	for _,request in pairs(auto_approve_join_list) do
		mod:echo(request.name)
	end
end)
mod:command("removeautoapproval", "Remove a username from your automatic approval list", function(name)
	for index,request in pairs(auto_approve_join_list) do
		if request.name == name then
			auto_approve_join_list[index] = nil
		end
	end
	mod:set("auto_approve_join_list", auto_approve_join_list)
end)

mod:command("lfg", "Set a custom LFG message on the RatNet.", function(...)
	local args = {...}
	if not args or args.n == 0 then
		mod:echo("Please provide a message")
		return
	end

	args.n = nil
	mod:set("intent", table.concat(args, " "), true)
	
	if session_active then
		intent_command_used = true
		intent_updated()
	end
end)
mod:command("clearlfg", "Clear your LFG message on the RatNet.", function()
	mod:set("intent", nil, true)
	
	if session_active then
		intent_command_used = true
		intent_updated()
	end
end)





-- ############################################################################
-- ## Hooks and events ########################################################
-- ############################################################################

mod:hook(MatchmakingManager, "rpc_matchmaking_request_join_lobby", function(func, self, channel_id, lobby_id, friend_join, client_dlc_unlocked_array)
	local is_friend = (lobby_state == "public") or (lobby_state == "private") or friend_join
	return func(self, channel_id, lobby_id, is_friend, client_dlc_unlocked_array)
end)

local client_stream_link_synced = false
mod:hook_safe(BulldozerPlayer, "spawn", function (self, optional_position, optional_rotation, is_initial_spawn, ammo_melee, ammo_ranged, healthkit, potion, grenade, ability_cooldown_percent_int, additional_items, initial_buff_names)
	if Managers.player.is_server then
		client_stream_link_synced = false
		if not session_active then
			begin_session()
		end
	else
		do_heartbeat = false
		if not client_stream_link_synced and stream_links[Steam.user_id()] then
			mod:network_send("client_stream_link", "others", Steam.user_id(), stream_links[Steam.user_id()])
			client_stream_link_synced = true
		end
	end
	if initialize then
		mod:hook(LobbyInternal, "leave_lobby", function(func, lobby)
			if session_active then
				end_session()
			end
			func(lobby)
		end)
		initialize = false
	else
		cached_location = nil -- This helps make sure if the player uses /restart that we will refresh the time in the level
	end
end)


mod:hook_safe(RemotePlayer, "set_player_unit", function(self, unit)
	if not self.is_server or remote_player_ids[self.peer_id] then
		return
	end
	
	remote_player_ids[self.peer_id] = true
	
	local steam_id = self.peer_id
	local name = self:name()
	local career = self:career_name()
	
	debug_echo("RatNet: Player joining " .. steam_id)
	player_joined_session(steam_id, name, career)
	lobby_updated()
end)

mod:hook_safe(GameNetworkManager, "remove_peer", function(self, peer_id)
	if not self.is_server then
		return
	end
	
	remote_player_ids[peer_id] = nil
	player_careers_cache[peer_id] = nil
	
	debug_echo("RatNet: Removing player " .. peer_id)
	player_left_session(peer_id)
	lobby_updated()
end)

mod:hook_safe(PartyManager, "set_selected_profile", function(self, peer_id, local_player_id, profile_index, career_index)
	if not Managers.player.is_server then
		return
	end

	local original_career = player_careers_cache[peer_id]
	local new_career = "invalid_career"
	local profile = SPProfiles[profile_index]
	local display_name = profile and profile.display_name
	if display_name then
		new_career = profile.careers[career_index].name
	end
	
	player_careers_cache[peer_id] = new_career
	debug_echo("RatNet: Set player_careers_cache value to " .. tostring(new_career))
	if new_career == original_career then
		return
	end
	
	debug_echo("RatNet: Raising player_changed_career for " .. tostring(new_career))
	player_changed_career(peer_id, new_career)
end)

mod:hook_safe(DifficultyManager, "set_difficulty", function(self, difficulty, tweak)
	if not self.is_server or not session_active or difficulty == cached_difficulty then
		return
	end
	
	if get_level_key() == "dlc_morris_map" then
		-- Difficulty gets set to recruit when returning to
		-- Holseher's Map. So we should ignore this
		return
	end
	
	cached_difficulty = difficulty
	difficulty_updated(difficulty)
end)

mod:hook_safe(PlayerHud, "set_current_location", function(self, location)
	if not session_active or location == cached_sub_location then
		return
	end
	cached_sub_location = location
	sub_location_updated(location)
end)

mod.on_game_state_changed = function(status, state_name)
	if state_name == "StateIngame" and status == "enter" then
		location_changed_time = os.time()
	end
	
	if not session_active then
		return
	end
	
	if state_name == "StateLoading" and status == "enter" then
		cached_sub_location = nil
	end
	
	local level_key = nil
	if state_name == "StateLoading" and status == "enter" and Managers.level_transition_handler then	
		level_key = Managers.level_transition_handler:get_current_level_key()
	elseif state_name == "StateIngame" and status == "enter" then
		level_key = get_level_key()
	end
	
	if level_key and level_key ~= cached_location then
		cached_location = level_key
		location_updated(level_key)
	end
end

mod.update = function(dt)
	if do_heartbeat then		
		local os_time = os.time()
		if os_time >= time_of_next_heartbeat then
			time_of_next_heartbeat = os_time + HEARTBEAT_INTERVAL_SECONDS
			if recovery_status.begin then
				begin_session()
			else
				heartbeat()
				
				evaluate_mod_state()
				evaluate_number_of_bots()
			end
		end
	end
end

mod.on_setting_changed = function(setting_id)
	if setting_id == "debug_mode" then
		debug_mode = mod:get("debug_mode")
	elseif setting_id == "use_desired_players" or setting_id == "desired_players" then
		max_player_override = (mod:get("use_desired_players") and mod:get("desired_players")) or 9999
		lobby_updated()
	elseif setting_id == "lobby_state" then
		lobby_state = mod:get("lobby_state")
		lobby_updated()
	elseif setting_id == "join_request_sound" then
		join_request_sound_event_name = get_join_request_sound_event()
		attempt_play_sound(join_request_sound_event_name)
	elseif setting_id == "intent" then
		intent = mod:get("intent")
		if session_active then
			intent_updated()
		end
	elseif setting_id == "stream_link" then
		stream_links[Steam.user_id()] = mod:get("stream_link")
		if Managers.player and Managers.player.is_server then
			if session_active then
				stream_link_updated(Steam.user_id())
			end
		else
			mod:network_send("client_stream_link", "others", Steam.user_id(), stream_links[Steam.user_id()])
		end
	end
end

