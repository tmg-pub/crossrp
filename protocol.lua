-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The Alliance Protocol.
-------------------------------------------------------------------------------
local _, Main = ...

-- terminology:
--  band: set of people by faction and their realm
--  link: a link between two players over battlenet
--  bridge: an available player to carry data
--  toon: a player's character
--  local: your band
--  global: all active bands
local Me = {
	channel_name = "crossrp";
	
	-- bands that have been touched
	active_bands = {};
	
	-- links to bnet friends on other bands
	links   = {};
	hosting = false;
	
	-- list of bands we can access, indexed by band
	-- bridges[band] = {
	--   players[username] = { bridge info }
	--   bands[band] = { bridge list }
	--   bandmap[band] = { [player] = link to `players` }
	-- }
	bridges = {};
	
	next_status_broadcast = 0;
	
	VERSION = 1;
}
Main.Protocol = Me

local START_DELAY = 1.0 -- should be something more like 10

-------------------------------------------------------------------------------
function Me.Init()
	Main.Timer_Start( "join_broadcast_channel", "push", START_DELAY, 
		                                          Me.JoinBroadcastChannel, 10 )
end

-------------------------------------------------------------------------------
-- try to join the broadcast channel
function Me.JoinBroadcastChannel( retries )
	if GetChannelName( "crossrp" ) == 0 then
		if retries <= 0 then
			print( "Couldn't join broadcast channel." )
			return
		end
		JoinTemporaryChannel( "crossrp" )
		Main.Timer_Start( "join_broadcast_channel", "push", 1.0, 
		                                 Me.JoinBroadcastChannel, retries - 1 )
	else
		-- move to bottom
		local crossrp_channel = GetChannelName( "crossrp" )
		for i = crossrp_channel+1, MAX_WOW_CHAT_CHANNELS do
			if GetChannelName(i) ~= 0 then
				C_ChatInfo.SwapChatChannelsByChannelIndex( i, i-1 )
			else
				break
			end
		end
		
		Me.Start()
	end
end

-------------------------------------------------------------------------------
function Me.Start()
	C_ChatInfo.RegisterAddonMessagePrefix( "+RP" )
	
	Me.OpenLinks()
	
	Me.Update()
end

function Me.Update()
	Main.Timer_Start( "protocol_update", "push", 1.0, Me.Update )
	
	if GetTime() > Me.next_status_broadcast then
		Me.next_status_broadcast = Me.next_status_broadcast + 120
		Me.BroadcastStatus()
	end
end

-------------------------------------------------------------------------------
function Me.GameAccounts( bnet_account_id )
	local account = 1
	local friend_index = BNGetFriendIndex( bnet_account_id )
	local num_accounts = BNGetNumFriendGameAccounts( friend_index )
	return function()
		while account <= num_accounts do
			local _, char_name, client, realm,_, faction, 
					_,_,_,_,_,_,_,_,_, game_account_id 
				       = BNGetFriendGameAccountInfo( friend_index, account )
			account = account + 1
			
			if client == BNET_CLIENT_WOW then
				realm = realm:gsub( "%s*%-*", "" )
				return char_name .. "-" .. realm, faction, game_account_id
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.FriendsGameAccounts()
	
	local friend = 1
	local friends_online = select( 2, BNGetNumFriends() )
	local account_iterator = nil
		
	return function()
		while friend <= friends_online do
			if not account_iterator then
				local id, _,_,_,_,_,_, is_online = BNGetFriendInfo( friend )
				if is_online then
					account_iterator = Me.GameAccounts( id )
				end
			end
			
			if account_iterator then
				local name, faction, id = account_iterator()
				if not name then
					account_iterator = nil
					friend = friend + 1
				else
					return name, faction, id
				end
			else
				friend = friend + 1
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.OpenLinks()

	local my_faction = UnitFactionGroup( "player" )
	Me.hosting = true
	Me.next_status_broadcast = GetTime() + 5
	
	for charname, faction, game_account in Me.FriendsGameAccounts() do
		
		local realm = charname:match( "%-(.+)" )
		if realm ~= Main.realm or faction ~= my_faction then
			BNSendGameData( game_account, "+RP", "HI" )
		end
	end
end

-------------------------------------------------------------------------------
function Me.CloseLinks()
	if not Me.hosting then return end
	Me.hosting = false
	Me.Send( "local", "ST -" )
	
	for k, v in pairs( Me.links ) do 
		BNSendGameData( v.gameid, "+RP", "BYE" )
	end
	wipe( Me.links )
end

-------------------------------------------------------------------------------
function Me.BroadcastStatus()
	if not Me.hosting then return end
	local bands = {}
	local deststring = ""
	for k, v in pairs( Me.links ) do
		local b = bands[v.band]
		if not b then
			b = {
				load  = 0;
				count = 0;
			}
			bands[v.band] = b
		end
		b.load  = b.load + v.load
		b.count = b.count + 1
	end
	-- status message prints our list of accessible bands and an average of
	-- the links' loads
	for k, v in pairs( bands ) do
		local load = math.floor(v.load / v.count)
		deststring = deststring .. " " .. k .. load
	end
	
	-- ST <band list>
	Me.Send( "local", "ST" .. deststring )
end

-------------------------------------------------------------------------------
function Me.Send( destination, message )
	if destination == "all" then
		-- todo
		return
	elseif destination == "active" then
		-- todo
		return
	elseif destination == "local" then
		-- add header
		message = Me.VERSION .. " " .. message
		C_ChatInfo.SendAddonMessage( "+RP", message, "CHANNEL",
	                                         GetChannelName( Me.channel_name ))
		return
	end
	
	-- find a bridge
	local dest_band = destination:match( "%d[AH]$" )
	if not dest_band then
		error( "Invalid Band." )
	end
	
	if not Me.bridges[destination] then
		-- No available route.
		return
	end
	
	local t = GetTime()
	local bridges = {}
	
	for k, v in pairs( Me.bridges[destination] ) do
		if t < v + 150 then
			table.insert( bridges, k )
			table.insert( bridges, k )
		else
			-- remove inactive bridge
			Me.bridges[destination][k] = nil
		end
	end
	
	if #bridges == 0 then
		-- No available route.
		return
	end
	
	local bridge = bridges[ math.random( 1, #bridges ) ]
	
	-- todo, bypass this for self (but it should work both ways)
	local packet = "R1 " .. destination .. " " .. message
	C_ChatInfo.SendAddonMessage( "+RP", packet, "WHISPER", bridge )
end

function Me.SendBnetPacket( gameid, command, ... )
	
end

-------------------------------------------------------------------------------
function Me.FindLinkByGameAccount( gameid )
	for k, v in pairs( Me.links ) do
		if v.gameid == gameid then
			return v, k
		end
	end
end

-------------------------------------------------------------------------------
function Me.AddLink( gameid, load )
	load = load or 99
	local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
	realm = realm:gsub( "%s*%-*", "" )
	charname = charname .. "-" .. realm
	local band = Main.GetBandFromRealmFaction( realm, faction )
	if band == Me.band then return end -- Same band as us.
	
	local link = Me.FindLinkByGameAccount( gameid )
	
	if link then
		link.time = GetTime()
		link.band = band
		link.load = load
	else
		table.insert( Me.links, {
			gameid = gameid;
			time = GetTime();
			load = load;
		})
	end
end

function Me.RemoveLink( gameid )
	local link, key = Me.FindLinkByGameAccount( gameid )
	if link then
		table.remove( Me.links, key )
	end
end

function Me.GetBridgeByName( username )
	local b = Me.bridges.players[username]
	if not b then
		b = {
			name  = username;
			bands = {};
		}
		Me.bridges.players[username] = b
	end
	return b
end

function Me.UpdateBridge( sender, bands )
	local bands = strsplit( " ", bands )
	local 
	local bridge = Me.GetBridgeDataByName( sender )
	
end

Me.BroadcastPacketHandlers = {
	ST = function( command, message, sender )
		-- register or update a bridge.
		
		Me.UpdateBridge( sender, message )
		for k, v in pairs( bands ) do
			bridges[v] = bridges[v] or {}
			bridges[v][sender] = GetTime()
		end
	end;
}

Me.BnetPacketHandlers = {
	HI = function( command, message, sender )
		Me.AddLink( sender )
		-- reply
		local load = math.max( #Me.links, 1 )
		BNSendGameData( sender, "+RP", "HO " .. load  )
	end;
	
	HO = function( command, message, sender )
		local load = message:match( "%d+" )
		Me.AddLink( sender, load )
	end;
	
	BYE = function( command, message, sender )
		Me.RemoveLink( sender )
	end;
}

Me.WhisperPacketHandlers = {
	R1 = function( command, message, sender )
		local destination, message = message:match( "([A-Za-z]*%d+[AH]) (.+)" )
		if not destination then
			Main.DebugLog( "Bad R1 message." )
			return
		end
		
		-- find a suitable band host
		-- forward as R2
		-- if none found, do nothing?
		Me.HandleR1Packet( sender, destination, message )
	end
}

-------------------------------------------------------------------------------
function Me.OnBnChatMsgAddon( event, prefix, text, channel, sender )
	if prefix ~= "+RP" then return end
	
	local version, command, rest = text:match( "([0-9]+) (%S+)%s*(.*)" )
	if version ~= Me.VERSION then
		return
	end
	Main.DebugLog2( "Protocol:", text, channel, sender )
	
	local handler = Me.BnetPacketHandlers[command]
	if handler then handler( command, rest, sender ) end
end

function Me.OnChatMsgAddon( event, prefix, message, dist, sender )
	if prefix ~= "+RP" then return end
	
	local version, command, rest = message:match( "([0-9]+) (%S+)%s*(.*)" )
	if dist == "CHANNEL" then
		local handler = Me.BroadcastPacketHandlers[command]
		if handler then
			handler( command, message, sender )
		end
	elseif dist == "WHISPER" then
		local handler = Me.WhisperPacketHandlers[command]
		if handler then
			handler( command, message, sender )
		end
	end
end

function Me.HandleR1Packet( sender, destination, message )
	
end

-- todo: on logout, let everyone know.

function Me.TouchUnitBand( unit )
	local band = Main.BandFromUnit( unit )
	if band ~= Main.band then
		Me.active_bands[band] = GetTime()
	end
end

-------------------------------------------------------------------------------
-- hooks
function Me.OnMouseoverUnit()
	Me.TouchUnitBand( "mouseover" )
end

function Me.OnTargetUnit()
	Me.TouchUnitBand( "target" )
end

function Me.Test()
	Me.OpenLinks()
	
	
end
