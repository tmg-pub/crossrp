-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The Alliance Protocol.
-------------------------------------------------------------------------------
local _, Main = ...

-- terminology:
--  band: set of people by faction and their realm
--  bridge: a link between two players over battlenet
--  toon: a player's character
--  local: your band
--  global: all active bands
local Me = {
	channel_name = "crossrp";
	active_bands = {};
	
}
Main.Protocol = Me

local START_DELAY = 1.0 -- should be something more like 10

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
	
	Me.OpenBridges()
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
function Me.OpenBridges()

	local my_faction = UnitFactionGroup( "player" )
	
	for charname, faction, game_account in Me.FriendsGameAccounts() do
		
		local realm = charname:match( "%-(.+)" )
		if realm ~= Main.realm or faction ~= my_faction then
			BNSendGameData( game_account, "+RP", "HI" )
		end
	end
end

-------------------------------------------------------------------------------
function Me.CloseBridges()

	for charname, faction, game_account in Me.FriendsGameAccounts() do
		
		local realm = charname:match( "%-(.+)" )
		if realm ~= Main.realm or faction ~= my_faction then
			BNSendGameData( game_account, "+RP", "CLOSE" )
		end
	end
end

-------------------------------------------------------------------------------
function Me.BroadcastLocal( message )
	C_ChatInfo.SendAddonMessage( "+RP", message, "CHANNEL", 
	                                         GetChannelName( Me.channel_name ))
end


-------------------------------------------------------------------------------
function Me.OnBnChatMsgAddon( event, prefix, text, channel, sender )
	if prefix ~= "+RP" then return end
	
	Main.DebugLog2( "Protocol:", text, channel, sender )
	if text == "HI" then
		-- reply
		BNSendGameData( sender, "+RP", "HO" )
	end
end

-------------------------------------------------------------------------------
-- hooks
function Me.OnMouseoverUnit()
	
end

function Me.OnTargetUnit()
	
end

function Me.Test()
	for a,b,c,d in Me.FriendsGameAccounts() do
		print( a,b,c,d )
	end
end