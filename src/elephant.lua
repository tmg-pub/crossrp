-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- Elephant (addon) support code.
-------------------------------------------------------------------------------

local _, Me = ...
local AceEvent      = LibStub("AceEvent-3.0")

-------------------------------------------------------------------------------
-- Entry for our Elephant Support. This is part one of two. Part two is in
--  SimulateChatMessage. All this does is hooks the event setup and then forces
--                a refresh; then we replace the event handlers with our hooks.
function Me.ButcherElephant()
	if not Elephant then return end
	if Me.block_elephant_support then return end
	hooksecurefunc( Elephant, "RegisterEventsRefresh", 
	                                         Me.OnElephantRegisterEvents )
	Elephant:RegisterEventsRefresh()
end

-------------------------------------------------------------------------------
-- I warn people that they need to make their code accessible from the outside,
--  otherwise it just makes things way more nastier when you want to add some
--  third party functionality to it. And no, I'm not going to make a pull
--  request for every little feature that I wanted implemented in everything
--                                                            that I'm abusing.
function Me.OnElephantRegisterEvents( self )
	-- Elephant has two types of ways to intercept chat messages, one is
	--  through Prat, which will already have our proper message filtering
	--  as well as translated messages, the other is through AceEvent, which
	--  is using LibCallbackHandler.
	-- Elephant's event handler is cached by the callback system, so we
	--  need to dig through there and then replace it. It's also accessed above
	--  in SimulateChatMessage when we add our translated messages to it.
	-- In here, we're just concerned with suppressing any orcish/common when
	--  we're connected, since Elephant doesn't respect chat filters.
	
	local ELEPHANT_EVENT_FILTERS = {
		CHAT_MSG_SAY               = Me.ChatFilter_Say;
		CHAT_MSG_YELL              = Me.ChatFilter_Say;
		CHAT_MSG_EMOTE             = Me.ChatFilter_Emote;
		CHAT_MSG_BN_WHISPER        = Me.ChatFilter_BNetWhisper;
		CHAT_MSG_BN_WHISPER_INFORM = Me.ChatFilter_BNetWhisper;
	}
	
	for chat_event, my_filter in pairs( ELEPHANT_EVENT_FILTERS ) do
		local prat = Prat and Elephant.db.profile.prat
		local elephant_event_info = Elephant.db.profile.events[chat_event]
		if elephant_event_info 
		          and (not prat or elephant_event_info.register_with_prat) then
				  
			local handler = AceEvent.events.events[chat_event][Elephant]
			if handler then
				AceEvent.events.events[chat_event][Elephant] = function( ... )
					-- This is a little bit dirty. Keep in mind that this is 
					--                    using our chat filter directly here.
					if not my_filter( nil, ... ) then
						return handler( ... )
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Adds a message to the elephant logs. This is called from 
--  SimulateChatMessage.
function Me.ElephantLog( event_type, msg, username, language, lineid, guid )
	
	if not Elephant or Me.block_elephant_support then 
		-- Elephant isn't installed, or the support for it is disabled. This is
		--  so that if Elephant updates to handle CrossRP messages directly,
		--  they can disable this for any users with that update.
		return
	end
	
	local is_rp_type = event_type:match( "^RP[1-9W]" )
	local event = "CHAT_MSG_" .. event_type
	local prat = Prat and Elephant.db.profile.prat
	local elephant_event_info = Elephant.db.profile.events[ event ]
	-- If the user has "Prat Formatting" enabled in Elephant, then we don't
	--  actually have to do anything for the normal public emotes. Elephant
	--  will capture those from a Prat handler, and Prat will capture those
	--                  directly from our calling the chat handler function.
	if elephant_event_info 
			  and (not prat or elephant_event_info.register_with_prat) then
				 
		
		local handler = AceEvent.events.events[event][Elephant]
		handler( event, msg, username, language, "", "", "", 0, 
												0, "", 0, lineid, guid, 0 )
	end
	
	-- For our RP types, which are custom chat types, we need to implement
	--  these completely manually. That is, create a group in Elephant and then
	--  add it to there.
	if is_rp_type then
		local channel_name = "Cross RP"
		local msg_prefix = _G["CHAT_"..event_type.."_GET"]:match( "^[^%]]+%]" )
		Elephant:InitCustomStructure( channel_name, channel_name )
		local elephant_msg = {
		  time = time();
		  arg1 = msg_prefix .. " " .. msg;
		  arg2 = username;
		  arg6 = nil;
		  arg9 = channel_name;
		}
		Elephant:CaptureNewMessage( elephant_msg, channel_name )
	end
end
