-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- Parsing player /rolls and forwarding them.
-------------------------------------------------------------------------------
local _, Me = ...
local Rolls = {}
Me.Rolls = Rolls

-------------------------------------------------------------------------------
-- The following is some serious mojo to convert localized strings into
-- matching patterns. A feeble attempt at providing message recognition that
-- works on any client.
--
-- For roll results... English is "%s rolls %d (%d-%d)"
local SYSTEM_ROLL_PATTERN = RANDOM_ROLL_RESULT

-- Convert to a pattern.
SYSTEM_ROLL_PATTERN = SYSTEM_ROLL_PATTERN:gsub( "%%%d?$?s", "(%%S+)" )
SYSTEM_ROLL_PATTERN = SYSTEM_ROLL_PATTERN:gsub( "%%%d?$?d", "(%%d+)" )
SYSTEM_ROLL_PATTERN = SYSTEM_ROLL_PATTERN:gsub( "%(%(%%%d?$?d%+%)%-%(%%%d?$?d%+%)%)", "%%((%%d+)%%-(%%d+)%%)" ) -- yikes HAHA

local ROLL_FORMAT = RANDOM_ROLL_RESULT:gsub( "%%%d%$", "%%" )
	
function Rolls.OnChatMsgSystem( event, message )
	local sender, roll, rmin, rmax = message:match( SYSTEM_ROLL_PATTERN )
	
	if sender == UnitName("player") then
		-- this is our roll message
		Me.RPChat.SendRoll( roll, rmin, rmax )
	end
end

function Rolls.SimulateChat( sender, result, range_from, range_to )
	
	-- Other addons can intercept this message.
	Me:SendMessage( "CROSSRP_ROLL", sender, result, range_from, range_to )
	
	local msg = Rolls.FormatChat( sender, result, range_from, range_to )
	
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame" .. i]
		if frame:IsEventRegistered( "CHAT_MSG_SYSTEM" ) then
			ChatFrame_MessageEventHandler( frame, "CHAT_MSG_SYSTEM", msg, "", nil, "",
									"", "", 0, 0, "", 0, 0, nil, 0 )
		end
	end
	
	if ListenerAddon and not Me.block_listener_roll_forwarding then
		ListenerAddon.AddChatHistory( sender, "ROLL", msg )
	end
end

function Rolls.FormatChat( sender, roll, rmin, rmax )
	return ROLL_FORMAT:format( sender, roll, rmin, rmax )
end