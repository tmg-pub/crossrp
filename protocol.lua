-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The Alliance Protocol.
-------------------------------------------------------------------------------
local _, Me        = ...
local LibRealmInfo = LibStub("LibRealmInfo")

-- terminology:
--  band: set of people by faction and their realm
--  link: a link between two players over battlenet
--  bridge: an available player to carry data
--  toon: a player's character
--  local: your band
--  global: all active bands
local Proto = {
	channel_name = "crossrp";
	
	-- bands that have been touched
	active_bands = {};
	
	hosting = false;
	hosting_time = 0;
	
	-- these are indexed by band
	links   = {};
	bridges = {};
	
	link_ids = {};
	secure_links   = {};
	secure_code    = nil;
	secure_channel = nil;
	secure_hash    = nil;
	secure_myhash  = nil;
	
	next_status_broadcast = 0;
	status_broadcast_urgent = false;
	
	registered_addon_prefixes = {};
	
	my_dest    = nil;
	my_band    = nil;
	my_realmid = nil;
	
	message_handlers = {};
}
Me.Proto = Proto

-------------------------------------------------------------------------------
-- These servers get a special single digit realm identifier because they're
--  very popular. This may change if we decide to support non RP servers
--                                     (these IDs are overwriting PvE servers).
Proto.PRIMO_RP_SERVERS = {
	[1] = 1365; -- Moon Guard US
	[2] = 536;  -- Argent Dawn EU
	[3] = 1369; -- Wyrmrest Accord US
}
Proto.PRIMO_RP_SERVERS_R = {}
for k,v in pairs( Proto.PRIMO_RP_SERVERS ) do
	Proto.PRIMO_RP_SERVERS_R[v] = k
end

local START_DELAY          = 1.0 -- should be something more like 10
local HOSTING_GRACE_PERIOD = 60 * 5
local BAND_TOUCH_ACTIVE    = 60 * 15

-------------------------------------------------------------------------------
-- Destination utility functions.
-------------------------------------------------------------------------------
function Proto.GetBandFromUnit( unit )
	if not UnitIsPlayer( unit ) then return end
	local guid = UnitGUID( unit )
	if not guid then return end
	local realm = LibRealmInfo:GetRealmInfoByGUID( guid )
	local faction = UnitFactionGroup( unit )
	if realm <= 3 then
		realm = "0" .. realm
	else
		realm = Proto.PRIMO_RP_SERVERS_R[realm] or realm
	end
	return realm .. faction:sub(1,1)
end

function Proto.GetBandFromDest( destination )
	return destination:match( "%d+[AH]" )
end

function Proto.IsDestLocal( dest )
	return Proto.IsDestLinked( Proto.my_dest, dest )
end

function Proto.DestFromFullname( fullname, faction )
	local realm = LibRealmInfo:GetRealmInfo( fullname:match("%-(.+)") or Me.realm )
	if realm <= 3 then
		realm = "0" .. realm
	else
		realm = Proto.PRIMO_RP_SERVERS_R[realm] or realm
	end
	return fullname:match( "^[^-]*" ) .. realm .. faction
end

function Proto.DestToFullname( dest )
	local name, realm = dest:match( "([A-Za-z]+)(%d+)" )
	name = name:lower()
	name = name:gsub( "^[%z\1-\127\194-\244][\128-\191]*", string.upper )
	local primo = realm.byte(1) ~= 48
	realm = tonumber(realm)
	realm = primo and Proto.PRIMO_RP_SERVERS[realm] or realm
	local _, _, realm_apiname = LibRealmInfo:GetRealmInfoByID( realm )
	return name .. "-" .. realm_apiname
end

function Proto.IsDestLinked( dest1, dest2 )
	if dest1:byte(#dest1) ~= dest2:byte(#dest2) then
		-- factions not same
		return false
	end
	local band1, band2 = dest1:match( "(%d+)[AH]" ), dest2:match( "(%d+)[AH]" )
	if not band1 or not band2 then return end
	if band1 == band2 then return true end
	
	if Proto.linked_realm[tonumber(band1)] == Proto.linked_realm[tonumber(band2)] then
		
	end
end

function Proto.GetLinkedBand( dest1 )
	local realm, faction = dest1:match( "(%d+)([AH])" )
	local primo = realm.byte(1) == 48
	realm = tonumber(realm)
	realm = primo and Proto.PRIMO_RP_SERVERS[realm] or realm
	if primo then
		-- primo servers aren't linked.
		return realm .. faction
	end
	local realmid, _,_,_,_,_,_,_,connections = LibRealmInfo:GetRealmInfoByID( realm )
	for _, v in pairs( connections ) do
		realm = math.min( realm, v )
	end
	return realm .. faction
end

-------------------------------------------------------------------------------
function Proto.Init()
	Proto.my_dest = Proto.DestFromFullname( Me.fullname, Me.faction )
	Proto.my_band = Proto.GetBandFromDest( Proto.my_dest )
	
	Me.Timer_Start( "proto_start", "push", START_DELAY, function()
		Proto.JoinGameChannel( "crossrp", Proto.Start )
	end)
end

function Proto.GameChannelExists( name )
	return GetChannelName( name ) ~= 0
end

function Proto.MoveGameChannelToBottom( name )
	local index = GetChannelName( name )
	if index == 0 then return end
	
	while index < MAX_WOW_CHAT_CHANNELS do
		if GetChannelName( index + 1 ) ~= 0 then
			C_ChatInfo.SwapChatChannelsByChannelIndex( index, index + 1 )
			index = index + 1
		else
			break
		end
	end
end

function Proto.JoinGameChannel( name, onjoin, retries )
	if Proto.GameChannelExists( name ) then
		Proto.MoveGameChannelToBottom( name )
		if onjoin then
			onjoin( name )
		end
	else
		if retries and retries <= 0 then
			if name == "crossrp" then
				Me.Print( "Error: couldn't join broadcast channel." )
			else
				Me.Print( "Error: couldn't join channel '%s'.", name )
			end
			return
		end
		JoinTemporaryChannel( name )
		Me.Timer_Start( "joinchannel_" .. name, "push", 1.0, Proto.JoinGameChannel, name, onjoin or false, (retries or 10) - 1 )
	end
end

function Proto.LeaveGameChannel( name )
	Me.Timer_Cancel( "joinchannel_" .. name )
	if Proto.GameChannelExists( name ) then
		LeaveChannelByName( name )
	end
end

-------------------------------------------------------------------------------
function Proto.Start()
	C_ChatInfo.RegisterAddonMessagePrefix( "+RP" )
	Proto.SetSecure( 'henlo' ) -- debug
	Proto.StartHosting()
	
	Proto.Update()
end

-------------------------------------------------------------------------------
function Proto.IsHosting( include_grace_period )
	if Proto.hosting then
		return true
	else
		if include_grace_period and (GetTime() < Proto.hosting_time + HOSTING_GRACE_PERIOD) then
			return true
		end
	end
end

-------------------------------------------------------------------------------
function Proto.Update()
	Me.Timer_Start( "protocol_update", "push", 1.0, Proto.Update )
	
	if Proto.hosting and IsInInstance() then
		Proto.StopHosting()
	elseif not Proto.hosting and not IsInInstance() then
		Proto.StartHosting()
	end
	
	if Proto.hosting then
		Proto.hosting_time = GetTime()
	end
	
	-- check link health
	for k, v in pairs( Proto.links ) do
		if v:RemoveExpiredNodes() then
			-- we lost a link completely.
			Proto.next_status_broadcast = 0
			Proto.status_broadcast_urgent = true
		end
	end
	
	Proto.PurgeOfflineLinks( false )
	
	if GetTime() > Proto.next_status_broadcast and Proto.hosting then
		Proto.next_status_broadcast = GetTime() + 60 -- debug value
		Proto.BroadcastStatus()
		Proto.PingLinks()
	end
end

-------------------------------------------------------------------------------
function Proto.PurgeOfflineLinks( run_update )
	for gameid,_ in pairs( Proto.link_ids ) do
		local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
		if not charname or charname == "" then
			Proto.RemoveLink( gameid )
		end
	end
	
	if Proto.next_status_broadcast == 0 then
		Proto.status_broadcast_urgent = true
		if run_update then
			Proto.Update()
		end
	end
end

-------------------------------------------------------------------------------
function Proto.OnBnFriendInfoChanged()
	Me.Timer_Start( "purge_offline", "ignore", 0.01, Proto.PurgeOfflineLinks, true )
end

-------------------------------------------------------------------------------
function Proto.SetSecure( code )
	Proto.ResetSecureState()
	Proto.secure_code = code
	if code then
		Proto.secure_channel = Proto.GetSecureChannel()
		Proto.secure_hash    = Me.Sha256( Proto.secure_code )
		Proto.secure_myhash  = Me.Sha256( Me.fullname .. Proto.secure_code )
		if not Proto.registered_addon_prefixes[Proto.secure_channel] then
			Proto.registered_addon_prefixes[Proto.secure_channel] = true
			C_ChatInfo.RegisterAddonMessagePrefix( Proto.secure_channel .. "+RP" )
		end
	else
		Proto.secure_channel = nil
		Proto.secure_hash    = nil
		Proto.secure_myhash  = nil
	end
	Proto.next_status_broadcast = 0
end

-------------------------------------------------------------------------------
function Proto.ResetSecureState()
	wipe( Proto.secure_links )
	for k,v in pairs( Proto.links ) do
		v:EraseSubset( "secure" )
	end
end

-------------------------------------------------------------------------------
function Proto.GetSecureChannel()
	local sha1, sha2 = Me.Sha256Data( "channel" .. Proto.secure_code )
	local channel = tostring( sha1 % 1073741824, 32 ) .. tostring( sha2 % 1073741824, 32 )
	return channel:sub( 1,10 )
end

-------------------------------------------------------------------------------
function Proto.GameAccounts( bnet_account_id )
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
function Proto.FriendsGameAccounts()
	
	local friend = 1
	local friends_online = select( 2, BNGetNumFriends() )
	local account_iterator = nil
		
	return function()
		while friend <= friends_online do
			if not account_iterator then
				local id, _,_,_,_,_,_, is_online = BNGetFriendInfo( friend )
				if is_online then
					account_iterator = Proto.GameAccounts( id )
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
function Proto.StartHosting()
	if Proto.hosting then return end
	
	if BNGetNumFriends() == 0 then
		-- Battle.net is bugged during this session.
		return
	end
	
	local my_faction = UnitFactionGroup( "player" )
	
	Proto.hosting = true
	Proto.hosting_time = GetTime()
	--Proto.next_status_broadcast = GetTime() + 5
	Proto.next_status_broadcast = GetTime() + 1 -- debug bypass
	
	local send_to = {}
	for charname, faction, game_account in Proto.FriendsGameAccounts() do
		local realm = charname:match( "%-(.+)" )
		if realm ~= Me.realm or faction ~= my_faction then
			send_to[game_account] = true
		end
	end
	
	Proto.SendHI( send_to, true, 5 )
end

-------------------------------------------------------------------------------
function Proto.PingLinks()
	local send_to = {}
	for k, v in pairs( Proto.links ) do
		for gameid, _ in pairs( v.nodes ) do
			if not send_to[gameid] then
				send_to[gameid] = true
			end
		end
	end
	Proto.SendHI( send_to, false )
end

-------------------------------------------------------------------------------
function Proto.SendHI( gameids, request, load_override )
	if type(gameids) == "number" then
		gameids = {[gameids] = true}
	end
	local load = math.min( math.max( load_override or #Proto.links, 1 ), 99 )
	local short_passhash = (Proto.secure_hash or "-"):sub(1,8)
	local passhash       = (Proto.secure_myhash or "-"):sub(1,32)
	
	local request_mode = request and "?" or "-"
	
	for id, _ in pairs( gameids ) do
		local job = Proto.SendBnetMessage( id, 
		     {"HI", Me.version, request_mode, load, short_passhash, passhash}, false, "LOW" )
		job.tags = {"hi"}
	end
end

-------------------------------------------------------------------------------
function Proto.StopHosting()
	if not Proto.hosting then return end
	Proto.hosting = false
	Proto.BroadcastStatus()
	
	local sent_to = {}
	for k, v in pairs( Proto.links ) do
		for gameid, _ in pairs( v.nodes ) do
			if not sent_to[gameid] then
				send_to[gameid] = true
			end
		end
	end
	
	Me.Comm.CancelSendByTag( "hi" )
	
	for id, _ in pairs( send_to ) do
		Proto.SendBnetMessage( id, "BYE", false, "LOW" )
	end
end

-------------------------------------------------------------------------------
function Proto.BroadcastStatus()
	if not Proto.hosting then 
		Me.Comm.CancelSendByTag( "st" )
		local job = Proto.SendAddonMessage( "*", "ST -", false, "LOW" )
		job.tags = {"st"}
		return
	end
	
	local args = {}
	
	local secure_hash
	
	if Proto.secure_code then
		secure_hash = Proto.secure_hash:sub(1,32)
	else
		secure_hash = "-"
	end
	
	local bands = {}
	local deststring = ""
	for band, set in pairs( Proto.links ) do
		local avg = set:GetLoadAverage()
		if avg then
			local secure_mark = ""
			if Proto.secure_code then
				if set:SubsetCount( "secure" ) > 0 then
					secure_mark = "#"
				end
			end
			table.insert( bands, secure_mark .. band .. avg )
		end
	end
	
	-- ST <version> <secure code> <band list>
	
	Me.Comm.CancelSendByTag( "st" )
	
	bands = table.concat( bands, " " )
	if bands == "" then bands = "-" end
	
	local job = Proto.SendAddonMessage( "*", {"ST", Me.version, secure_hash, bands}, false, Proto.status_broadcast_urgent and "URGENT" or "LOW" )
	job.tags = {"st"}
	Proto.status_broadcast_urgent = false
end

-------------------------------------------------------------------------------
-- destinations can be
-- local: to local crossrp channel
-- all: to all crossrp channels we can reach
-- active: to all "touched" crossrpchannels we can reach
-- <band>: to the crossrp channel for this band
-- <user><band>: to this specific user
-- <user><myband>: local addon message (not implemented/used)
function Proto.Send( dest, msg, secure, priority )
	if secure and not Proto.secure_code then return end
	
	if type(msg) == "table" then
		msg = table.concat( msg, " " )
	end
	
	if dest == "local" then dest = Proto.my_band end
	
	if dest == "all" or dest == "active" then
		-- todo
		local send_to = { "local" }
		local time = GetTime()
		for k, v in pairs( Proto.bridges ) do
			if not v:Empty( secure and "secure" ) then
				local active = time < (Proto.active_bands[k] or 0) + BAND_TOUCH_ACTIVE
				if dest == "all" or (dest == "active" and active) then
					table.insert( send_to, k )
				end
			end
		end
		
		for k, v in ipairs( send_to ) do
			Proto.Send( v, msg, secure, priority )
		end
		return
	elseif Proto.IsDestLocal(dest) then
		-- this should be an r0, because this function is for forwarded messages that end up in a different handler.
		
		local localplayer = dest:match( "(.*)%d+[AH]" )
		local target
		if localplayer ~= "" then
			target = Proto.DestToFullname( dest )
		else
			target = "*"
		end
		
		Proto.SendAddonMessage( target, {"R0", msg}, secure, priority )
		return
	end
	
	-- Find a bridge.
	local bridge = Proto.SelectBridge( dest )
	if not bridge then
		-- No available route.
		return
	end
	
	if bridge == Me.fullname then
		local link = Proto.SelectLink( dest )
		if not link then
			-- No link.
			-- in the future we might reply to the user to remove us as a bridge?
			return
		end
		Proto.SendBnetMessage( link, {"R2", Proto.my_dest, dest, msg}, secure, priority )
	else
		-- todo, bypass this for self (but it should work both ways)
		-- VV R1 F DEST MESSAGE
		Proto.SendAddonMessage( bridge, {"R1", Me.faction, dest, msg}, secure, priority )
	end
end

-------------------------------------------------------------------------------
function Proto.SelectBridge( destination )
	local band = destination:match( "[A-Za-z]*(%d+[AH])" )
	if not band then error( "Invalid destination." ) end
	band = Proto.GetLinkedBand( band )
	local bridge = Proto.bridges[band]
	if not bridge then return end
	return bridge:Select()
end

-------------------------------------------------------------------------------
function Proto.SelectLink( destination )
	local user, band = destination:match( "([A-Za-z]*)(%d+[AH])" )
	if not band then error( "Invalid destination." ) end
	band = Proto.GetLinkedBand( band )
	local link = Proto.links[band]
	if not link then return end
	
	if user ~= "" then
		-- if user is set, try to get a direct link to that user.
		local direct = link:HasBnetLink( destination )
		if direct then return direct end
	end
	
	return link:Select()
end

-------------------------------------------------------------------------------
local function SpaceConcat( data )
	if type(data) == "table" then
		data = table.concat( data, " " )
	end
	return data
end

-------------------------------------------------------------------------------
function Proto.SendBnetMessage( gameid, msg, secure, priority )
	if secure and not Proto.secure_code then return end
	return Me.Comm.SendBnetPacket( gameid, nil, true, SpaceConcat(msg), secure and Proto.secure_channel, priority )
end

-------------------------------------------------------------------------------
function Proto.SendAddonMessage( target, msg, secure, priority )
	if secure and not Proto.secure_code then return end
	return Me.Comm.SendAddonPacket( target, nil, true, SpaceConcat(msg), secure and Proto.secure_channel, priority )
end

-------------------------------------------------------------------------------
function Proto.AddLink( gameid, load, secure )
	load = load or 99
	local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
	Me.DebugLog2( "Adding link.", charname, realm, gameid, "secure?", secure )
	realm = realm:gsub( "%s*%-*", "" )
	charname = charname .. "-" .. realm
	local band = Proto.DestFromFullname( "-" .. realm, faction )
	if Proto.IsDestLinked( band, Proto.my_band ) then
		-- same band as us
		return
	end
	
	band = Proto.GetLinkedBand( band )
	
	if not Proto.links[band] then
		Proto.links[band] = Me.NodeSet.Create( { "secure" } )
	end
	
	local subset
	if secure then subset = "secure" end
	Proto.link_ids[gameid] = true
	
	Proto.links[band]:Add( gameid, load, subset )
end

-------------------------------------------------------------------------------
function Proto.RemoveLink( gameid )
	Me.DebugLog2( "Removing link.", gameid )
	for k, v in pairs( Proto.links ) do
		if v:Remove( gameid ) then
			Proto.next_status_broadcast = 0
			Proto.status_broadcast_urgent = true
		end
	end
	Proto.link_ids[gameid] = nil
end

-------------------------------------------------------------------------------
function Proto.UpdateBridge( sender, secure_code, bands )
	-- all of the bands in here should be LINKED bands
	-- if not then the user may have received a bad message.
	local loads = {}
	local secure_bands = {}
	for secure, band, load in bands:gmatch( "(#?)(%d+[AH])([0-9]+)" ) do
		load = tonumber(load)
		
		if load < 1 or load > 99 then
			-- invalid input. cancel this user.
			loads = {}
			break
		end
		
		loads[band] = tonumber(load)
		if secure ~= "" then
			secure_bands[band] = "secure"
		end
	end
	
	-- create any nonexistant bridges.
	for band, load in pairs( loads ) do
		if not Proto.bridges[band] then
			Proto.bridges[band] = Me.NodeSet.Create( {"secure"} )
		end
	end
	
	for band, bridge in pairs( Proto.bridges ) do
		local load = loads[band]
		if load then
			bridge:Add( sender, load, secure_bands[band] )
		else
			bridge:Remove( sender )
		end
	end
end

function Proto.RemoveBridge( sender )
	for band, bridge in pairs( Proto.bridges ) do
		bridge:Remove( sender )
	end
end

-------------------------------------------------------------------------------
function Proto.GetFullnameFromGameID( gameid )
	local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
	realm = realm:gsub( "%s*%-*", "" )
	charname = charname .. "-" .. realm
	return charname, faction
end

-------------------------------------------------------------------------------
Proto.BroadcastPacketHandlers = {
	ST = function( job, sender )
		if not job.complete then return end
		
		if job.text == "ST -" then
			Proto.RemoveBridge( sender )
			return
		end
		
		-- register or update a bridge.
		local version, secure_code, bands = job.text:match( "ST (%S+) (%S+) (.+)" )
		if not version then return end
		
		if bands == "-" then
			Proto.RemoveBridge( sender )
			return
		end
		
		Proto.UpdateBridge( sender, secure_code, bands )
	end;
}

-------------------------------------------------------------------------------
Proto.BnetPacketHandlers = {
	---------------------------------------------------------------------------
	HI = function( job, sender )
		if not job.complete then return end
		-- HI <version> <request> <load> <secure short hash> <personal hash>
		local version, request, load, short_hash, personal_hash = job.text:match( 
		                                     "^HI (%S+) (.) ([0-9]+) (%S+) (%S+)" )
		if not load then return false end
		load = tonumber(load)
		if load < 1 or load > 99 then return false end
		
		local secure = false
		if Proto.secure_hash and short_hash == Proto.secure_hash:sub(1,8) then
			if not Proto.secure_links[sender] then
				local name = Proto.GetFullnameFromGameID( sender )
				local hash = Me.Sha256( name .. Proto.secure_code )
				if hash:sub(1,32) == personal_hash then
					Proto.secure_links[sender] = true
					secure = true
				end
			else
				secure = true
			end
		end
		
		Proto.AddLink( sender, load, secure )
		
		if Proto.hosting then
			if request == "?" then
				Proto.SendHI( sender, false )
			end
		end
	end;
	
	---------------------------------------------------------------------------
	BYE = function( job, sender )
		if not job.complete then return end
		Proto.RemoveLink( sender )
	end;
	
	---------------------------------------------------------------------------
	R2 = function( job, sender )
		
		if not job.skip_r3_for_self then
			if not job.forwarder then
				local source, dest_name, dest_band, message_data = job.text:match( "^R2 ([A-Za-z]+%d+[AH]) ([A-Za-z]*)(%d+[AH]) (.+)" )
				if not dest_name then return false end
				
				local destination = dest_name .. dest_band
				
				if destination:lower() == Proto.my_dest:lower() then
					-- we are the destination. Don't need R3 message.
					job.skip_r3_for_self = true
				else
					-- don't forward if we aren't hosting.
					if not Proto.IsHosting( true ) then
						-- likely a logical error
						Me.DebugLog( "Ignored R2 message because we aren't hosting." )
						return
					end
					
					local send_to
					if dest_name ~= "" then
						send_to = Proto.DestToFullname( destination )
					else
						send_to = "*"
					end
					
					job.forwarder = Me.Comm.SendAddonPacket( send_to )
					job.forwarder:SetPrefix( job.prefix )
					job.forwarder:SetPriority( "LOW" )
					job.forwarder:AddText( job.complete, "R3 " .. source .. " " .. message_data )
					job.text = ""
				end
			else
				job.forwarder:AddText( job.complete, job.text )
				job.text = ""
			end
		end
		
		if job.skip_r3_for_self then
			local source, message_data = job.text:match( "^R2 ([A-Za-z]+%d+[AH]) [A-Za-z]*%d+[AH] (.+)" )
			-- handle message.
			Proto.OnMessageReceived( source, message_data, job.complete )
		end
	end;
}

-------------------------------------------------------------------------------
Proto.WhisperPacketHandlers = {
	---------------------------------------------------------------------------
	R0 = function( job, sender )
		-- R0 <message>
		local message = job.text:sub(4)
		Proto.OnMessageReceived( Proto.DestFromFullname(sender, Me.faction), message, job.complete )
	end;
	---------------------------------------------------------------------------
	R1 = function( job, sender )
		if not Proto.IsHosting( true ) then
			-- likely a logical error
			Me.DebugLog( "Ignored R1 message because we aren't hosting." )
			return
		end
		
		if not job.forwarder then
			local faction, destination, message_data = job.text:match( "^R1 ([AH]) ([A-Za-z]*%d+[AH]) (.+)" )
			if not destination then
				Me.DebugLog( "Bad R1 message." )
				return false
			end
			
			local link = Proto.SelectLink( destination )
			if not link then
				-- No link.
				-- in the future we might reply to the user to remove us as a bridge?
				return false
			end
			
			job.forwarder = Me.Comm.SendBnetPacket( link )
			job.forwarder:SetPrefix( job.prefix )
			job.forwarder:SetPriority( "LOW" )
			local source = Proto.DestFromFullname( sender, faction )
			job.forwarder:AddText( job.complete, "R2 " .. source .. " " .. destination .. " " .. message_data )
			job.text = ""
		else
			job.forwarder:AddText( job.complete, job.text )
			job.text = ""
		end
	end;
	---------------------------------------------------------------------------
	R3 = function( job, sender )
		
		local source, message = job.text:match( "^R3 ([A-Za-z]+%d+[AH]) (.+)" )
		if not source then return false end
		Proto.OnMessageReceived( source, message, job.complete )
	end;
}

-------------------------------------------------------------------------------
Proto.BroadcastPacketHandlers.R3 = Proto.WhisperPacketHandlers.R3
Proto.BroadcastPacketHandlers.R0 = Proto.WhisperPacketHandlers.R0

-------------------------------------------------------------------------------
-- todo: on logout, let everyone know.

function Proto.TouchUnitBand( unit )
	local band = Proto.GetBandFromUnit( unit )
	if not band then return end
	
	if not Proto.IsDestLocal( band ) then
		band = Proto.GetLinkedBand( band )
		Proto.active_bands[band] = GetTime()
	end
end

-------------------------------------------------------------------------------
-- hooks
function Proto.OnMouseoverUnit()
	Proto.TouchUnitBand( "mouseover" )
end

function Proto.OnTargetUnit()
	Proto.TouchUnitBand( "target" )
end

function Proto.OnMessageReceived( source, text, complete )
	Me.DebugLog2( "Proto Msg", complete, source, text )
	local command = text:match( "^%S+" )
	if not command then return end
	
	local handler = Proto.message_handlers[command]
	if handler then
		handler( source, text, complete )
	end
end

function Proto.SetMessageHandler( command, handler )
	Proto.message_handlers[command] = handler
end

-------------------------------------------------------------------------------
function Proto.OnDataReceived( job, dist, sender )
	if job.proto_abort then return end
	Me.DebugLog2( "DATA RECEIVED", job.prefix, job.type, job.complete and "COMPLETE" or "PROGRESS", sender, job.text )
	
	if job.firstpage then
		local command = job.text:match( "^(%S+)" )
		if not command then
			job.proto_abort = true
			return
		end
		job.command = command
	end
	
	local handler_result
	if job.type == "BNET" then
		local handler = Proto.BnetPacketHandlers[ job.command ]
		if handler then handler_result = handler( job, sender ) end
	elseif job.type == "ADDON" then
		if dist == "CHANNEL" then
			local handler = Proto.BroadcastPacketHandlers[ job.command ]
			if handler then handler_result = handler( job, sender ) end
		elseif dist == "WHISPER" then
			local handler = Proto.WhisperPacketHandlers[ job.command ]
			if handler then handler_result = handler( job, sender ) end
		end
	end
	
	if handler_result == false then
		job.proto_abort = true
	end
end

function Proto.Test()
	--Proto.BnetPacketHandlers.HO( "HO", "1", 1443 )
	--Proto.Send( "Catnia1H", "to catnia." )
	--Proto.Send( "1H", "to all( baon)." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Shankle pig pork loin, ham salami landjaeger sirloin rump turducken. Beef ribs pork belly ground round, filet mignon pork kielbasa boudin corned beef picanha kevin. Tail ribeye swine venison. Short ribs leberkas flank, jerky ribeye drumstick cow sirloin sausage.Shankle pig pork loin, ham salami landjaeger sirloin rump turducken. Beef ribs pork belly ground round, filet mignon pork kielbasa boudin corned beef picanha kevin. Tail ribeye swine venison. Short ribs leberkas flank, jerky ribeye drumstick cow sirloin sausage." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Jerky tail cow jowl burgdoggen, short loin kevin sirloin porchetta. Meatloaf strip steak salami cupim leberkas, andouille hamburger landjaeger tongue swine beef filet mignon meatball. Chuck pork belly tenderloin strip steak sausage flank, pork turducken jowl tri-tip. Jerky tail cow jowl burgdoggen, short loin kevin sirloin porchetta. Meatloaf strip steak salami cupim leberkas, andouille hamburger landjaeger tongue swine beef filet mignon meatball. Chuck pork belly tenderloin strip steak sausage flank, pork turducken jowl tri-tip. " )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Pork loin chicken cow sirloin, ham pancetta andouille. Fatback biltong jerky ground round turducken. Pancetta jowl capicola picanha spare ribs shankle bresaola.Pork loin chicken cow sirloin, ham pancetta andouille. Fatback biltong jerky ground round turducken. Pancetta jowl capicola picanha spare ribs shankle bresaola." )
	--Proto.SetSecure( "henlo" )
	
	--Proto.Send( "all", "hitest", true )
	
	--C_ChatInfo.RegisterAddonMessagePrefix( "+TEN" )
	---C_ChatInfo.SendAddonMessage( "asdf", "hi", "CHANNEL", GetChannelName( "crossrp" ))
	C_ChatInfo.SendAddonMessage( "asdf", "hi", "WHISPER", "Tammya-MoonGuard" )
end
