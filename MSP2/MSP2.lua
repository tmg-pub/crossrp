
local VERSION = 1

if IsLoggedIn() then
	error( "MSP2 can't be loaded on demand!" )
end

local Me

if LibMSP2 then
	Me = LibMSP2.Internal
	if Me.VERSION >= VERSION then
		Me.load = false
		-- Already loaded.
		return
	end
	
	---------------------------------------------------------------------------
else
	LibMSP2 = {
		Internal = {}
	}
	
	Me = LibMSP2.Internal
end

-------------------------------------------------------------------------------
Me.VERSION = VERSION
Me.load    = true

