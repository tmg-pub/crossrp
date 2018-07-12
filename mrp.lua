-------------------------------------------------------------------------------
-- Cross RP
-- by Tammya-MoonGuard (2018)
--
-- All Rights Reserved
-------------------------------------------------------------------------------
-- I can say with some certainty the TRP and XRP guys aren't gonna like what
--  I'm doing. :)
-- Time to get messy...
-------------------------------------------------------------------------------

local MSP_imp = {}

function MSP_imp.BuildVernum()
	
end

function MSP_imp.OnVernum()
	
end

function MSP_imp.GetExchangeData( section )
	
end

function MSP_imp.SaveProfileData( user, index, data )
	
end

function MSP_imp.IsPlayerKnown( username )
	
end

function MSP_imp.Init()
	
end

function Me.MRP_Init()
	if mrp or xrp then
		Me.TRP_imp = MSP_imp
	end
end