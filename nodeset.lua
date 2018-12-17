
local _, Main = ...
local Protocol = Main.Protocol

local Methods = {
	Select = function()
		
	end);
	AddNode = function( name, load )
		
	end);
	RemoveNode = function( name, load )
		
	end);
}

function Protocol.CreateNodeSet()
	local object = {
		names = {};
		quota_sum = nil
	}
	for k, v in pairs(Methods) do
		object[k] = v
	end
end
