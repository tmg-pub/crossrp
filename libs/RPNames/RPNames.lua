-------------------------------------------------------------------------------
-- RPNames
-- by Tammya-MoonGuard (Copyright 2018)
-------------------------------------------------------------------------------
-- This is a simple API to fetch roleplay names from RP addons such as
--  Total RP 3, XRP Roleplay Profiles, or MyRolePlay, and it falls back to 
--  their toon name.
-------------------------------------------------------------------------------
-- Redistribution and use in source and binary forms, with or without 
-- modification, are permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice, 
-- this list of conditions and the following disclaimer.
--
-- 2. Redistributions in binary form must reproduce the above copyright 
-- notice, this list of conditions and the following disclaimer in the 
-- documentation and/or other materials provided with the distribution.
--
-- 3. Neither the name of the copyright holder nor the names of its 
-- contributors may be used to endorse or promote products derived from this
-- software without specific prior written permission.
-----------------------------------------------------------------------------^-

local VERSION = 1

-------------------------------------------------------------------------------
-- LibRPNames is the public API. Internal is our "private" namespace to work 
--  in (Me).
if not LibRPNames then
	LibRPNames = {}
	LibRPNames.Internal = {}
end
-------------------------------------------------------------------------------
local Me     = LibRPNames.Internal
local Public = LibRPNames
-------------------------------------------------------------------------------
if Me.version and Me.version >= VERSION then
	-- Already have a newer or existing version loaded; cancel.
	Me.load = false
	return
else
	-- Save old version so any sub files can reference it and make upgrades.
	Me.old_version = Me.version
	-- Me.load is a simple switch for sub files to continue loading or not. If
	--  it's false then it means we're up-to-date and any sub files should exit
	--  out immediately.
	Me.load = true
end

-------------------------------------------------------------------------------
Me.version = VERSION
--
-- << Do upgrades here for anything that needs it. >>
--
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Cache keys are <ambiguated name>_<subkey>. Subkeys are "name", "short",
--  "icon", and "color", and those entries contiain the full name, the
--  shortened name, the icon, and the color code, respectively. Icon and color
--  may be missing if the RP addon being used doesn't support those values or
--                           if those values aren't present in their profile.
Me.cache = {}
-------------------------------------------------------------------------------
-- The time when the cache was last cleared. The entire cache is dumped every
--  `CACHE_RESET_TIME` seconds. Each entry does not have time attached. It's
--  a global reset.
Me.cache_time = 0
local CACHE_RESET_TIME = 5
-------------------------------------------------------------------------------
-- This is a table (built below) that contains common titles, used for
-- filtering out player titles.
--
-- The MSP doesn't have different slots for title, first name and last name,
-- so this is necessary to cut out titles if someone is using a non TRP addon.
--
Me.titles = {}

do
	local titles = {
		
		-- Military
		"private", "pvt", "pfc", "corporal", "cpl";
		"sergeant", "sgt"; "lieutenant", "lt";
		"captain", "cpt", "commander", "major", "admiral";
		"ensign", "officer", "cadet", "guard";
		
		-- Nobility
		"dame", "sir", "knight";
		"lady", "lord", "mister";
		"mistress", "master", "miss";
		"king", "queen", "prince", "princess";
		"archduke", "archduchess", "duke", "duchess";
		"marquess", "marquis", "marchioness", "margrave", "landgrave";
		"count", "countess", "viscount", "viscountess";
		"baron", "baroness", "baronet", "baronetess";
		
		-- Civility
		"mr", "mrs";
		
		-- Religion
		"bishop", "father", "mother";
	}
	
	for _,v in pairs( titles ) do
		Me.titles[v] = true
		
		-- Duplicate each entry with a trailing period, for a lot of the 
		--  abbreviated titles. So "mr" also includes "mr.".
		Me.titles[v .. "."] = true
	end
end

-------------------------------------------------------------------------------
-- Takes a full name like "Duke Maxen Montclair" and returns "Maxen Montclair".
--
function Me.StripTitle( name )
	local a = name:match( "^%s*%S+" )
	if a and Me.titles[a:lower()] then
		-- Note that this pattern should not destroy the word if it is the only
		--  word. Sure, execution should not reach here if that's the case, but
		--  future proofing?
		name = name:gsub( "^%s*%S+%s+", "" )
	end
	return name
end

-------------------------------------------------------------------------------
-- Takes a full name without titles such as "Maxen Montclair" and returns the
--  first term or first few terms if the first name is too short.
-- Examples:
--  Maxen Montclair -> Maxen
--  Kim Sweete -> Kim Sweete (Uses full name since first name is only 3
--                             characters)
-- If first term is less than 4 characters, the full name will be used.
--
function Me.GetShortName( name )
	if not name or name == "" then return name end
	
	local short = name:match( "%S+" )
	if #short < 4 then
		short = name
	end
	
	return short
end

-------------------------------------------------------------------------------
-- Reset the name cache.
function Me.ClearCache()
	Me.cache_time = GetTime()
	wipe( Me.cache )
end

-------------------------------------------------------------------------------
-- This is the main query function.
--
-- `toon` is the person you're querying, a toon name with optional dash and
--  realm. It should also have proper capitalization, or the underlying
--  RP addon API might not recognize it. `guid` is an optional parameter, and
--  only used if there is no data on the player, in which the color will be
--  filled in with their class color.
-- 
-- Returns `name, shortname, icon, color`
--
-- If the person doesn't have an icon or if we aren't using an RP addon that
--  uses icons, then that will be `nil`. If the person isn't using a name
--  color, then this returns the game's class color for them. Color will
--  always have "ff" at the start for the alpha channel, and is suitable to
--  pair with a "|c" escape sequence.
--
-- Example return values:
--  "Richard Baronsteen", "Richard", "spell_mage_supernova", "ff112233"
--  "Caroline Watson", "Caroline", nil, nil
--
function Me.Get( toon, guid )
	-- Every so often, we just dump the entire cache. This might have some
	--  caveats if the user is looking up a LOT of names, but under normal use
	--  this seems like a good way to go about it.
	if GetTime() > Me.cache_time + CACHE_RESET_TIME then
		Me.ClearCache()
	end
	
	toon = Ambiguate( toon, "all" )
	
	-- If we have a cached entry (not erased above) then we use that instantly.
	local cached = Me.cache[ toon ]
	if cached then
		local color = cached[4]		
		-- Color is kind of a weird thing. If the name doesn't have a color
		--  code attached to it from their RP profile, then we default to the
		--  class color, but we might not always have a valid guid. If the 
		--  guid isn't given, then the color should default to nil rather than
		--  whatever last value we got. Essentially, the class color is -not-
		--  cached.
		if not color then
			color = Me.GetClassColor( guid )
		end
		return cached[1], cached[2], cached[3], color
	end
	
	local name, shortname, icon, color
	
	if TRP3_API then
		-- TRP3 is the preferred method, since the title field is a separate
		--  entity (so long as a profile is received from TRP as well).
		name, shortname, icon, color = Me.GetTRP3Name( toon )
	
	elseif msp then
		-- XRP and MRP names are handled here. XRP populates the MSP cache so
		--  it works seamlessly with its own internal profile cache.
		
		name, shortname, icon, color = Me.GetMSPName( toon )
	end
	
	if not name then
		name  = Me.GetNormalName( toon )
		shortname = name
	end
	
	
	Me.cache[ toon ] = { name, shortname, icon, color }
	
	if not color then
		color = Me.GetClassColor( guid )
	end
	
	return name, shortname, icon, color
end

-------------------------------------------------------------------------------
-- Returns a character's class color from a guid. Handles `nil` as an input
--  where it just returns `nil` too.
--
function Me.GetClassColor( guid )
	if not guid then
		return nil
	end
	
	local _, cls = GetPlayerInfoByGUID( guid )
	if cls and RAID_CLASS_COLORS[cls] then
		local c = RAID_CLASS_COLORS[cls]
		return ("ff%.2x%.2x%.2x"):format(c.r*255, c.g*255, c.b*255)
	end
end

-------------------------------------------------------------------------------
-- Cuts a realm tag off of a name.
function Me.GetNormalName( toon )
	return toon:match( "[^-]*" )
end

-------------------------------------------------------------------------------
-- Fetches data from TRP3. `toon` is toon name and optional realm.
-- Returns `fullname, shortname, icon, color`
-- Disregards the "title" field from RP names.
--
function Me.GetTRP3Name( toon )
	-- A lot of this code "just works", but it's reasonably sensed. This
	--  basically checks if TRP3 is finished setting up its registry and 
	--  ready to go with queries.
	if not TRP3_API.register.getCharacterList() then 
		return
	end
	
	-- "unit id" in this case is a fully qualified toon name. TRP3 calls them
	--  that, so we're using the same term name here. If the realm is missing
	--  we can fetch it from TRP3's globals. Getting the player's realm name
	--  natively seems to be a bit of a pain in the ass otherwise.
	local unit_id = toon
	if not unit_id:find( "-" ) then
		unit_id = unit_id .. "-" .. TRP3_API.globals.player_realm_id
	end
	
	-- There's two profile sources, and that's the player's own, and other
	--  people they have seen. If the character name isn't known, then we
	--  just break out. Note that we're just returning nil when we fail. The
	--  fallback values are done in the upper layer of code.
	local profile
	if unit_id == TRP3_API.globals.player_id then
		profile = TRP3_API.profile.getData( "player" )
	elseif TRP3_API.register.isUnitIDKnown( unit_id ) then
		profile = TRP3_API.register.getUnitIDCurrentProfile( unit_id )
	else
		return
	end
	
	local ch = profile and profile.characteristics
	
	-- I'm not sure what cases would have this structure not present, but
	--  this sort of check is also there in the official TRP code. Simple
	--  prudence, maybe.
	if not ch then
		return
	end
	
	-- To build our fullname, we concatenate the first name and last name,
	--  discarding the title field. If the first name isn't present, we default
	--  to the stripped name.
	local fullname = ch.FN or Me.GetNormalName( toon )
	if ch.LN then
		fullname = fullname .. " " .. ch.LN
	end
	
	-- If this profile was received from the MSP side, the FN field is the
	--  entire name, including titles, so we need to manually strip them out.
	--  Of course this isn't ideal, but it's the best we can do.
	fullname = Me.StripTitle( fullname )
	
	local color, icon
	if ch.CH and ch.CH ~= "" then
		-- The color field is a 6 digit hex code, and we prepend "ff" to be
		--  a valid color code to use in the color escape sequence.
		color = "ff" .. ch.CH
	end
	-- In some cases I believe some fields can be "" as well as nil, so check
	--  for that too. At least with the MSP, "" is an empty field.
	if ch.IC and ch.IC ~= "" then
		icon = ch.IC
	end
	
	return fullname, Me.GetShortName( fullname ), icon, color
end

-------------------------------------------------------------------------------
-- Try and get a result from a certain name.
-- 
-- We try with fullname (name-realm) and then normal name.
--
local function TryGetMSP( name )
	if msp.char[name] and msp.char[name].supported then
		
		-- With the MSP, names are stored in a single field. Less optimal,
		--  since sometimes we don't know what is a player's title, but we
		--  try to filter it out still.
		-- Also with MSP, the name might have a color code prefixed to it,
		--  which we need to parse and save as the color field.
		local fullname = msp.char[name].field.NA
		local color  = fullname:match( "^|c(%x%x%x%x%x%x%x%x)" )
		fullname = fullname:gsub( "|c(%x%x%x%x%x%x%x%x)", "" )
		fullname = fullname:gsub( "|r", "" )
		if fullname == "" then return end
		
		-- MSP always returns empty strings rather than nil for unfilled
		--  entries.
		local icon = msp.char[name].IC
		if icon == "" then icon = nil end
		
		fullname = Me.StripTitle( fullname )
		
		return fullname, Me.GetShortName( fullname ), icon, color
	end
end

-------------------------------------------------------------------------------
-- Fetches data from LibMSP. `name` is a toon name and optional realm.
-- Returns `fullname, shortname, icon, color`
-- Tries to strip titles from names.
--
function Me.GetMSPName( toon )
	local firstname, color
	
	local toonrealm = toon
	toon = Ambiguate( toon, "all" )
	if not toonrealm:find( "-" ) then
		local realm = GetNormalizedRealmName()
		if not realm then return end
		toonrealm = toonrealm .. "-" .. realm
	end
	
	-- I'm not actually sure how LibMSP stores names for local-realm players,
	--  so we check both the ambiguated name and the full name. It might only
	--  be one or the other, but that might also change in the future.
	local name, short, icon, color = TryGetMSP( toonrealm )
	if name then
		return name, short, icon, color
	end
	
	if toonrealm ~= toon then
		local name, short, icon, color = TryGetMSP( toon )
		if name then
			return name, short, icon, color
		end
	end
	
	return
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
-- name, shortname, icon, color = LibRPNames.Get( toon, [guid] )
--
-- Fetches a person's RP name and some other information linked to them, such
--  as their TRP icon (although I believe MRP supports icons now), and their
--  name color. The GUID is only used as a fallback to get a toon's class color
--  from the game functions. `name` and `shortname` will always be strings, 
--  falling back to the toon name itself; `icon` may be a texture path or nil, 
--                               and `color` may be a 8-digit hexcode or nil.
LibRPNames.Get = Me.Get
-------------------------------------------------------------------------------
-- LibRPNames.ClearCache()
--
-- Clears the name cache, in case you want to get an instantly updated name
--  when you know that it's changed. Without calling this, it may take up to
--  five seconds for a name to update. The cache is meant for optimizing the
--  case when you're querying a name hundreds of times in a single frame (e.g.
--  populating chatboxes).
LibRPNames.ClearCache = Me.ClearCache
