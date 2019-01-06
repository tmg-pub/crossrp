-------------------------------------------------------------------------------
-- Cross RP
-- by Tammya-MoonGuard (2018)
--
-- All Rights Reserved
-------------------------------------------------------------------------------
local _, Main = ...
local L = Main.Locale

Main.ElixirNotice = {}
Me = Main.ElixirNotice

Me.refresh_button = CreateFrame("Button", nil, UIParent, 
                     "StaticPopupButtonTemplate, InsecureActionButtonTemplate")
Me.refresh_button:SetAttribute( "type", "macro" )
Me.refresh_button:SetText( REFRESH )
Me.refresh_button:HookScript( "OnClick", function()
	Me.RefreshClicked()
end)

function Me.RefreshClicked() end

-------------------------------------------------------------------------------
StaticPopupDialogs["CROSSRP_ELIXIR_NOTICE"] = {
	text    = "";
	button1 = REFRESH;
	button2 = IGNORE;
	timeout = 0;
	---------------------------------------------------------------------------
	OnShow = function( self )
		Me.refresh_button:SetParent( self )
		Me.refresh_button:SetAllPoints( self.button1 )
		
		-- We're doing this setup here rather than outside of the function,
		--  because we might not have the item info ready beforehand.
		local elixir_name = GetItemInfo( 2460 )
		Me.refresh_button:SetAttribute( "macrotext", "/cast " .. elixir_name )
		   
		self.button1:Hide()
		Me.refresh_button:Show()
		Me.RefreshClicked = function()
			-- Show a UI error if they don't have any elixirs left in their
			--  bags.
			local has_elixirs = GetItemCount(2460) > 0
			if not has_elixirs then
				UIErrorsFrame:AddMessage( L.NO_MORE_ELIXIRS, 1,0,0 )
			end
			self:Hide()
		end
	end;
	---------------------------------------------------------------------------
	OnHide = function( self )
		Me.refresh_button:Hide()
		self.button1:Show()
	end;
	---------------------------------------------------------------------------
	OnAccept = function( self )
	
	end;
	---------------------------------------------------------------------------
	OnCancel = function( self )
	
	end;
	---------------------------------------------------------------------------
	OnUpdate = function(self)
		
		if InCombatLockdown() then
			Me.refresh_button:SetEnabled( false )
		else
			Me.refresh_button:SetEnabled( true )
		end
		
		local time = Main.UnitHasElixir( "player" )
		if time then
			if time > 30*60 then
				self:Hide()
				return
			end
			if time < 60 then
				time = math.ceil(time) .. " " .. SECONDS:lower()
			else
				time = math.ceil(time / 60) .. " " .. MINUTES:lower()
			end
			self.text:SetText( L( "ELIXIR_NOTICE", time ))
		else
			self.text:SetText( L.ELIXIR_NOTICE_EXPIRED )
		end
		StaticPopup_Resize( self, self.which )
	end;
}

-------------------------------------------------------------------------------
function Me.Show() 
	StaticPopup_Show( "CROSSRP_ELIXIR_NOTICE" )
end
