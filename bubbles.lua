-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- This handles capturing chat bubbles from players and changing the text.
-------------------------------------------------------------------------------
local _, Me = ...
-------------------------------------------------------------------------------
-- Bubble translations are somewhat strict with the timers. 3 seconds
--  is still a long time, but there can be issues on the source-side where they
--  can't send a message for seconds at a time. Hopefully it still catches
local TRANSLATION_TIMEOUT = 5  -- them.
-- 7/24/18 Adjusted these due to some issues regarding
--  latency and such. It's a bit uglier visually sometimes, but the end result
--  is more robust.
-------------------------------------------------------------------------------
-- If we do get a bubble translated, we shorten the window to 'update' it to
--  something much more strict. This is to avoid changing the text of the
--  bubble while it's still active if we're 'pretty sure' that it's the right
--  text.
-- Here's a picture:
--  [TRANSLATION RECEIVED] --> BUBBLE CAPTURED AND SET -->
--    [ANOTHER TRANSLATION RECEIVED] --> if within TIMEOUT2, then we update
--    the bubble again with this translation. Otherwise, we assume this
--    translation is for the next incoming bubble.
-- Latency always makes things screwy, but we try to handle things as robust
local TRANSLATION_TIMEOUT2 = 3  -- as possible.
-------------------------------------------------------------------------------
-- Player data, indexed by username.
--   source: If this is "orcish", then the bubble hasn't been tracked yet. We 
--            search through the chat bubbles for a string that matches the 
--            orcish text given, and then capture it. Once captured, this
--            changes to "frame", and `fontstring` is set to the bubble's text
--            font string.
--   orcish: The foreign text we saw from the player in the game's chat event.
--   fontstring: The captured bubble's fontstring. Even though we capture this,
--                we still need to iterate through the bubbles if we want
--                to make changes, to make sure that this fontstring is still
--                on the screen and ours. We could do this a different way but
--                basically we want to avoid using these font strings if they
--                aren't visible.
--   dim: If true, this bubble is new, and we want to dim the text while
--         waiting for a translation to arrive.
--   capture_time: The time of the call to Bubbles_Add, to measure translation
--                  timeouts.
--   translated: True if this bubble's text was changed.
-- Note that the bubble's fontstring itself also has `crp_name` set to the
--                 username when we capture the bubble.
Me.bubbles = {}
-------------------------------------------------------------------------------
-- This is a table indexed by fontstring/userdata objects. We don't use this
--  right now as of writing, but I suspect that some cat bubbles in the pool 
--  will get 'locked' into a dimmed state by us, and this will be important to
--  reset those.
Me.dimmed_bubbles = {}

-------------------------------------------------------------------------------
-- Easy function to get or make a bubble for a username.
local function GetBubble( username )
	Me.bubbles[username] = Me.bubbles[username] or {}
	return Me.bubbles[username]
end

-------------------------------------------------------------------------------
-- Called when we receive a CHAT_MSG_SAY event from someone we want to
--  translate for. `username` is the sender's fullname, `text` is the orcish
--  text we saw.
function Me.Bubbles_Capture( username, orcish )
	local bubble = GetBubble( username )
	bubble.source       = "orcish"
	bubble.orcish       = orcish;
	bubble.fontstring   = nil
	bubble.dim          = true
	bubble.capture_time = GetTime()
	bubble.translated   = false

	-- Need to be careful here capturing `username` and leaving some room for
	--        some strange errors if things happen between now and next frame.
	-- Once the chat event fires, the bubbles for them are created on the next
	--  frame.
	Me.Timer_Start( "bubble_" .. username, "ignore", 0.01, 
	                                              Me.Bubbles_Update, username, "CAPTURE" )
end

-------------------------------------------------------------------------------
-- Called when we receive a translation from the player. When we get a
--  translation, we aren't actually sure if we've received the player chat
--  even for it yet, or if we have the bubble. If we have something set, then
--  we do some basic checks before updating it. Otherwise, the translation is
--                              saved and then used in the next Capture call.
function Me.Bubbles_Translate( username, text )
	local bubble = GetBubble( username )
	bubble.dim            = false
	bubble.translate_to   = text
	bubble.translate_time = GetTime()
	
	if bubble.fontstring 
	          and (GetTime() - bubble.capture_time) < TRANSLATION_TIMEOUT then
		Me.Bubbles_Update( username, "TRANSLATE" )
	end
end

-------------------------------------------------------------------------------
-- For updating bubbles.
function Me.Bubbles_Update( username,dbgarg )
	local bubble = Me.bubbles[username]
	if not bubble or not bubble.source then return end
	Me.DebugLog2( "BUBBLE UPDATE", dbgarg, GetTime(), username )
	local fontstring
	
	if bubble.source == "orcish" then
		-- This bubble is new, and we need to search for it with the orcish
		--  text. Technically this can go very wrong if two people say the
		--  same orcish phrase at the exact same time.
		fontstring = Me.Bubbles_FindFromOrcish( bubble.orcish )
		
		if fontstring then
			Me.DebugLog2( "found chat bubble." )
			bubble.source     = "frame"
			bubble.fontstring = fontstring
			fontstring.crp_name = username
		else
			-- Sometimes we might not get the bubble here. This is from some
			--  quirks with our code as well as line of sight. If the bubble
			--  comes in line of sight later we still want to capture it.
			-- Chat bubbles show up for 2 - 12 seconds, depending on how long
			--  they are.
			local timeout = 2 + (#bubble.orcish / 255) * 10
			-- ...We also have to take into account that we don't let
			--  translations linger forever, so our cutoff time is that.
			timeout = math.min( TRANSLATION_TIMEOUT, timeout )
			Me.DebugLog2( "didn't find chat bubble.", timeout )
			if GetTime() - bubble.capture_time < timeout then
				-- Retry next frame.
				Me.Timer_Start( "bubble_" .. username, "ignore", 0.01, 
				                                  Me.Bubbles_Update, username, "CAPTURE_RETRY" )
				return
			else
				-- If something otherwise goes wrong, we give up. This can
				--  happen under normal circumstances if the bubble is
				--  obscured by line of sight.
				Me.DebugLog2( "giving up finding chat bubble." )
				bubble.source = nil
				return
			end
			
		end
	elseif bubble.source == "frame" then
		-- Either we captured this bubble already, or we didn't find it.
		--  In the latter case, the below function dies easily.
		if Me.Bubbles_IsStillActive( username, bubble.fontstring ) then
			fontstring = bubble.fontstring
		else
			Me.DebugLog2( "couldn't find bubble again." )
		end
	else
		-- Shouldn't reach here.
		return
	end
	
	if not fontstring then
		Me.DebugLog2( "bubble popped." )
		-- This bubble popped!
		bubble.source = nil
		return
	end
	
	-- We have two translation timeouts. The first one is longer, and is for
	--  when the bubble isn't already translated. Second one is shorter to
	--  try and avoid retranslating the bubble if we already have. See more
	--                         about this in the TRANSLATION_TIMEOUT notes.
	local tx_timeout = TRANSLATION_TIMEOUT
	if bubble.translated then
		tx_timeout = TRANSLATION_TIMEOUT2
	end
	
	if bubble.translate_to 
	             and (GetTime() - bubble.translate_time) < tx_timeout then
		fontstring:SetText( bubble.translate_to )
		
		-- The way the chat bubbles are built are kind of weird. If you just
		--  set the text simply, sometimes, especially with short text of
		--  just one word, the end of it gets wrapped around to the bottom,
		--  from the font string not being wide enough for it. We do a simple
		--  fix here of just making them wider. I'm not really happy with
		--                        this, but it's not easy to figure out.
		fontstring:SetWidth( math.min( fontstring:GetStringWidth() + 10, 400 ))
		Me.DebugLog2( "bubble translated." )
		bubble.dim        = false
		bubble.translated = true
	end
	
	-- `bubble.dim` is when we want to dim the text when we don't have a
	--  translation. We also save these dimmed strings into a table, because
	--  I know for certain that the text color is not reset for these strings
	--  in the pool. In the future we might have to implement a way to reset
	--  the visibility of them. I imagine this will likely pop up as an early
	if bubble.dim then                        -- issue during live testing.
		fontstring:SetTextColor( 1,1,1, 0.25 )
		Me.dimmed_bubbles[fontstring] = true
	else
		fontstring:SetTextColor( 1,1,1, 1)
		Me.dimmed_bubbles[fontstring] = nil
	end
end

-------------------------------------------------------------------------------
-- An iterator function to scan the chat bubbles table and extract the
--  font string.
function Me.IterateChatBubbleStrings()
	local bubbles = C_ChatBubbles.GetAllChatBubbles()
	local key, bubble_frame
	-- TODO: I think we forgot to check IsProtected in here.
	return function()
		key, bubble_frame = next( bubbles, key )
		if not bubble_frame then return end
		for _, region in pairs( {bubble_frame:GetRegions()} ) do
			-- We just return the first font string we find. Seems to be safe
			--  enough, and I don't see why they would add any more.
			if region:GetObjectType() == "FontString" then
				return region
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Checks if a bubble for a username is still in the active chat bubbles table.
--                                     `bubble` is the fontstring we captured.
function Me.Bubbles_IsStillActive( username, bubble )
	if not bubble then return false end
	for fontstring in Me.IterateChatBubbleStrings() do
		-- Just go through them and then return true if we find a matching
		--  frame and name, or false if the frame was captured by another
		--  name.
		if bubble == fontstring or fontstring.crp_name == username then
			if bubble == fontstring and fontstring.crp_name == username then
				return true
			end
			Me.DebugLog2( "ISSTILLACTIVE", bubble == fontstring, fontstring.crp_name, username )
		end
	end
end

-------------------------------------------------------------------------------
-- Does a fresh search on the chat bubbles to find which one contains the text
--                                 given, which is ideally an orcish string.
function Me.Bubbles_FindFromOrcish( text )
	for fontstring in Me.IterateChatBubbleStrings() do
		if fontstring:GetText() == text then
			return fontstring
		end
	end
end
