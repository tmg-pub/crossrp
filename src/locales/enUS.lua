Locales.enUS = {
	-- The addon title.
	CROSS_RP = "Cross RP";
	-- The tooltip text for Cross RP in the game's addon selection menu.
	ADDON_NOTES = "Links friends for cross-faction roleplay!";
	
	-- Menu button in the main minimap menu to open the channel selection tab.
	RP_CHANNELS = "RP Channels";
	-- Tooltip for the menu button in the main minimap menu to open the channel selection tab.
	RP_CHANNELS_TOOLTIP = "Select which /rp channels to show in your chatboxes.";
	-- A notice that shows in the minimap menu when the RP channel is muted.
	RP_IS_MUTED = "RP Is Muted";
	-- Additional information about the mute function, tooltip for the RP IS MUTED label.
	RP_IS_MUTED_TOOLTIP = "When RP is muted, normal community members cannot post in /rp. They can still post in /rp2-9.";
	-- The button that opens the Cross RP Interface options in the minimap menu.
	SETTINGS = "Settings";
	-- Tooltip for the Settings button in the minimap button menu.
	SETTINGS_TIP = "Open Interface options panel.";
	-- Tooltip for when mousing over a server in the minimap menu server list.
	CONNECT_TO_SERVER_TOOLTIP = "Click to connect.";
	-- Name of the RP Warning channel (/rpw).
	RP_WARNING = "RP Warning";
	-- Tooltip for the RP Warning channel in the minimap menu and options.
	RP_WARNING_TOOLTIP = "Similar to raid warning, this is accessed by leaders only with /rpw.";
	-- Title of the global RP channel (/rp). Used in a number of places in the options.
	RP_CHANNEL = "RP Channel";
	-- Title for the secondary RP channels (/rp#), used in the options. {1} is a number 2-9.
	RP_CHANNEL_X = "RP Channel {1}";
	-- Tooltip for toggling the RP channel in the minimap menu. Also shows up in the options panel when mousing over the color option for it.
	RP_CHANNEL_1_TOOLTIP = "The main RP channel. Access through /rp.";
	-- Tooltip for toggling the secondary RP channels in the minimap menu. Also shows up in the options panel when mousing over the color option for them. {1} is a number 2-9.
	RP_CHANNEL_X_TOOLTIP = "Channels 2-9 are meant for smaller sub-groups. Access through /rp#.";
	VERSION_LABEL = "Version: {1}";
	-- The author tag in the options panel.
	BY_AUTHOR = "by Tammya-MoonGuard";
	-- Label for the option that toggles the minimap menu button visibility.
	OPTION_MINIMAP_BUTTON = "Show Minimap Button";
	-- Tooltiop for the option that toggles the minimap menu button visibility.
	OPTION_MINIMAP_BUTTON_TIP = "Show or hide the minimap button (if you're using something else like Titan Panel to access it).";
	-- Label for the option that toggles the chat bubble modifications.
	OPTION_TRANSLATE_CHAT_BUBBLES = "Translate Chat Bubbles";
	-- Tooltip for the option that toggles the chat bubble modifications.
	OPTION_TRANSLATE_CHAT_BUBBLES_TIP = "Try and translate chat bubbles alongside text.";
	-- Label for the option that toggles the "Whisper" button when right-clicking an enemy player.
	OPTION_WHISPER_BUTTON = "Whisper Button";
	-- Tooltip for the option that toggles the "Whisper" button when right-clicking an enemy player.
	OPTION_WHISPER_BUTTON_TIP = "Adds a \"Whisper\" button when right-clicking on players from opposing faction if they're Battle.net friends. This may or may not break some things in the Blizzard UI, and you don't need it to /w someone cross-faction.";
	-- Label for the chat colors section in the options panel.
	OPTION_CHAT_COLORS = "Chat Colors";
	
	-- A notice printed to chat when a user tries to use the /rpw command without permission.
	CANT_POST_RPW2 = "Only group leaders or assistants can post in RP Warning.";
	WHISPER = "Whisper";
	WHISPER_TIP = "Whisper opposing faction. (This is sent safely over a direct Battle.net whisper, privately, and doesn't use the community relay.)";
	-- The label for the traffic monitor in the minimap button tooltip while connected.
	TRAFFIC = "Traffic";
	-- For the traffic monitor, suffix for kilobytes per second.
	KBPS = "KB/s";
	-- Shown in the traffic monitor, for bytes per second. e.g. "Traffic: 520 B/s"
	BPS = "B/s";
	-- What's shown when a community's name cannot be resolved for some reason. Probably won't ever be used.
	UNKNOWN_SERVER = "(Unknown)";
	
	-- Help text in the minimap button tooltip.
	MINIMAP_TOOLTIP_CLICK_OPEN_MENU = "|cffddddddClick to open menu.";
	-- Help text in the minimap button tooltip.
	MINIMAP_TOOLTIP_RIGHTCLICK_OPEN_MENU = "|cffddddddRight-click to open menu.";
	
	-- How the client should localize height numbers. Can be "FEETINCHES" or "CM".
	HEIGHT_UNIT = "FEETINCHES";
	WEIGHT_UNIT = "POUNDS";
	-- Label for the toggle switch in the world map tracking list. This toggles showing Cross RP players on the map.
	MAP_TRACKING_CROSSRP_PLAYERS = "Cross RP Players";
	
	---------------------------------------------------------------------------------------
	-- The API can't fetch these for us for languages we don't know. These need
	--  to be filled in for each locale. In the future we might add more fake
	--            languages that can have their own IDs for extra RP languages.
	---------------------------------------------------------------------------------------

	-- This needs to match EXACTLY the ingame name for the language Orcish. Cross RP uses it to detect that language.
	LANGUAGE_1 = "Orcish";
	-- This needs to match EXACTLY the ingame name for the language Common. Cross RP uses it to detect that language.
	LANGUAGE_7 = "Common";
	LANGUAGES_NOT_SET = "Language names have not been set up for your locale. Cross RP may not function properly.";
	
	-- Unused. Used to be the label for showing how long the relay has been idle in the minimap button tooltip.
	IDLE_TIME = "Idle Time";
	UPTIME = "Uptime";
	
	VERSION_TOO_OLD = "A required update is available and your current version may not work properly. Please download the latest release of Cross RP at your nearest convenience.";
	-- A message that tells the user what the latest version is. {1} is replaced with a version string such as "2.0.0".
	LATEST_VERSION = "Latest release version is {1}.";
	
	-- Currently unused. Label for the Links button in the minimap menu (opens up a list of Cross RP community links).
	LINKS = "Links";
	-- (Unused) Tooltip for the Links button in the minimap menu.
	LINKS_TOOLTIP = "Easy access to Cross RP hosted communities.";
	-- Shown when the user is missing core files and needs to restart their game (or something else is wrong, which is unlikely).
	UPDATE_ERROR = "Cross RP is not installed correctly. If you recently updated, please close the game and restart it completely. If this error persists and you are using the latest version of Cross RP, please submit an issue report.";
	
	-- This is a notice that pops up when your Elixir of Tongues is running out. {1} is formatted as a time like "48 seconds" (seconds/minutes is localized elsewhere).
	ELIXIR_NOTICE = "Elixir of Tongues expires in {1}.";
	-- When the timer for the elixir notice reaches 0, this is shown instead.
	ELIXIR_NOTICE_EXPIRED = "Elixir of Tongues has expired.";
	
	-- This shows up in the minimap tooltip, when Cross RP is "active" (meaning you are actively engaging in cross-faction RP).
	CROSSRP_ACTIVE = "Active";
	-- This shows up in the minimap tooltip, when Cross RP is "idle", meaning it's in a low-power standby mode until you find some cross-faction RP.
	CROSSRP_INACTIVE = "Idle";
	
	-- Label for the "Translate Emotes" button in the minimap button menu.
	TRANSLATE_EMOTES = "Translate Emotes";
	-- Tooltip text for the Translate Emotes button.
	TRANSLATE_EMOTES_TIP = "Turn /emote text into /say text when near the opposite faction. The other side doesn't need Cross RP installed.\n\nThis doesn't have any effect if Cross RP is Idle (red icon).\n\nAvoid getting drunk.";
	
	-- Label for the network status in the minimap button tooltip.
	NETWORK_STATUS = "Network Status";
	-- Label for the network status display when you don't have any connections to other realms or factions.
	NO_CONNECTIONS = "No connections.";
	
	-- Error printed when you try to use /rp chat while not in a linked group.
	NOT_IN_LINKED_GROUP = "You're not in a linked group.";
	
	USER_CONNECTED_TO_YOUR_GROUP = "{1} has connected to your group.";
	-- Label for the button in the minimap menu to start a linked group.
	LINK_GROUP = "Link Group";
	-- Label for the button in the minimap button menu to stop the group from being linked. Only usable by party leaders.
	UNLINK_GROUP = "Unlink Group";
	-- A message printed to chat when the party leader starts a linked group.
	GROUP_LINKED = "You have joined a linked group.";
	-- This prints to chat when the party leader stops the group from being linked.
	GROUP_UNLINKED = "Your group is no longer linked.";
	-- This is shown in the tooltip for the Link Group button to let the user know they can't change this unless they're the party leader.
	NEEDS_GROUP_LEADER = "Only group leaders can change this.";
	-- Error message when the user presses the Link/Unlink Group button when they aren't the party leader. Similar to the previous translation, but English uses "that" instead of "this" because the chatbox is usually far away from the minimap menu. :)
	NEEDS_GROUP_LEADER2 = "Only group leaders can change that.";
	
	-- This shows up in the minimap tooltip; it's a status label that lets the user know they're in a linked group.
	GROUP_STATUS_LINKED = "Group Linked";
	
	-- Tooltip for the Link Group button in the minimap menu.
	LINK_GROUP_TOOLTIP = "You can link your group to other groups with this, and /rp chat is used to talk between them.";
	-- Tooltip text for the Unlink Group button in the minimap menu.
	UNLINK_GROUP_TOOLTIP = "Unlink your group from others, disabling /rp chat.";
	
	-- This is an error message that shows up in chat when you try to use a Cross RP feature, but you need to wait until Cross RP is done initializing.
	CROSSRP_NOT_DONE_INITIALIZING = "Cross RP hasn't finished starting up yet.";
	
	-- Help text for the dialog that pops up when the user clicks Link Group.
	LINK_GROUP_DIALOG = "Enter a password for your linked group. Groups using the same password will be linked.";
	-- Error printed to chat when your RP chat message fails due to network problems.
	RPCHAT_TIMED_OUT = "Message to {1} timed out.";
	-- Error that's printed to chat when your RP chat message failed due to having no bridge. A bridge is a player on your realm and faction that can deliver your message to another realm or faction (through their Battle.net friends).
	RPCHAT_NOBRIDGE = "Couldn't send message to {1}. No bridge available.";
	RELAY_RP_CHAT = "Relay RP Chat";
	RELAY_RP_CHAT_TOOLTIP = "For group leaders only: any RP chat received will be copied into /raid or /party for users without Cross RP to see.";
	
	RELAY_RP_ROLL = "[{1}] rolled {2} ({3}-{4})";
	
	-- Error message that's shown when you try to refresh your Elixir of Tongues, but don't have any.
	NO_MORE_ELIXIRS = "You're out of elixirs!";
	
	INVALID_FACTION = "Disabling due to not having a faction selected.";
};