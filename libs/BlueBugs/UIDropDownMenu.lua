--[[
	© Justin Snelgrove

	Permission to use, copy, modify, and distribute this software for any
	purpose with or without fee is hereby granted, provided that the above
	copyright notice and this permission notice appear in all copies.

	THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
	WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
	MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
	SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
	WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
	OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
	CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

	--

	UIDropDownMenu_Refresh() taint

	This fixes one of the most infamous taint issues in WoW. This taint usually
	manifests as UIDROPDOWNMENU_MENU_LEVEL taint, but the root cause is insecure
	variables being left in the dropdown buttons. These insecure variables can
	be read when UIDropDownMenu_Refresh() is called.

	Specifically, when iterating through the buttons of a dropdown, the refresh
	function compares the value key with the selected value of the menu being
	refreshed... And the value key, if the new menu doesn't use values or
	doesn't have as many buttons as the previous menu, then taints the
	execution. Since this isn't wrapped in securecall() anywhere, it spreads
	taint horridly -- specifically, the next global variable to usually get
	tainted is UIDROPDOWNMENU_MENU_LEVEL.

	This taint is fixed by, while a menu is being initialized, clearing out any
	insecure keys leftover from previous menus.

	Possible fix locations:
	Interface\FrameXML\UIDropDownMenu.lua:35-59
	Interface\FrameXML\UIDropDownMenu.lua:608-623

	The communites frame is a special case, as it doesn't bother initializing
	even a single menu before starting to muck around with them, so the
	absolutely hideous workaround is to show and hide a frame that will
	initialize a secure menu in OnShow. The AddonList is a very good target, as
	it also prevents the community frame from opening if it's open.
]]

local UIDDMR_VERSION = 2
if (BLUEBUGS_UIDDMR_VERSION or 0) < UIDDMR_VERSION then

	local ADDONLIST_WORKAROUND_FUNCTIONS = { "Communities_LoadUI" }

	hooksecurefunc("UIDropDownMenu_InitializeHelper", function(frame)
		if UIDDMR_VERSION < BLUEBUGS_UIDDMR_VERSION then return end

		-- If level > 1, we've already cleaned it when the base menu was
		-- initialized.
		if UIDROPDOWNMENU_MENU_LEVEL > 1 then return end

		for i = 1, UIDROPDOWNMENU_MAXLEVELS do
			for j = 1, UIDROPDOWNMENU_MAXBUTTONS do
				local button = _G[("DropDownList%dButton%d"):format(i, j)]
				for k, v in pairs(button) do
					-- 0 and invisibleButton are default elements, never remove
					-- them or secure elements.
					if k ~= 0 and k ~= "invisibleButton"
						and not issecurevariable(button, k)
					then
						button[k] = nil
					end
				end
			end
		end
	end)

	local function FlashAddonList()
		if UIDDMR_VERSION < BLUEBUGS_UIDDMR_VERSION then return end

		-- This is a really sick (read: twisted, horrible) way of resetting
		-- to a secured UIDROPDOWNMENU_MENU_LEVEL, but it works.
		if not AddonList:IsShown() then
			AddonList:Show()
			AddonList:Hide()
		end
	end

	for i, funcName in ipairs(ADDONLIST_WORKAROUND_FUNCTIONS) do
		if _G[funcName] then
			hooksecurefunc(funcName, FlashAddonList)
		end
	end

	BLUEBUGS_UIDDMR_VERSION = UIDDMR_VERSION
end
