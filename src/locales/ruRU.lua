-- Translator ZamestoTV
Locales.ruRU = {
	-- The addon title.
	CROSS_RP = "Cross RP";
	-- The tooltip text for Cross RP in the game's addon selection menu.
	ADDON_NOTES = "Соединяет друзей для ролевой игры между фракциями!";
	
	-- Menu button in the main minimap menu to open the channel selection tab.
	RP_CHANNELS = "RP-каналы";
	-- Tooltip for the menu button in the main minimap menu to open the channel selection tab.
	RP_CHANNELS_TOOLTIP = "Выберите, какие каналы /rp показывать в ваших окнах чата.";
	-- A notice that shows in the minimap menu when the RP channel is muted.
	RP_IS_MUTED = "RP заглушён";
	-- Additional information about the mute function, tooltip for the RP IS MUTED label.
	RP_IS_MUTED_TOOLTIP = "Когда RP заглушён, обычные участники сообщества не могут писать в /rp. Они всё ещё могут писать в /rp2-9.";
	-- The button that opens the Cross RP Interface options in the minimap menu.
	SETTINGS = "Настройки";
	-- Tooltip for the Settings button in the minimap button menu.
	SETTINGS_TIP = "Открыть панель настроек интерфейса.";
	-- Tooltip for when mousing over a server in the minimap menu server list.
	CONNECT_TO_SERVER_TOOLTIP = "Кликните для подключения.";
	-- Name of the RP Warning channel (/rpw).
	RP_WARNING = "RP-предупреждение";
	-- Tooltip for the RP Warning channel in the minimap menu and options.
	RP_WARNING_TOOLTIP = "Аналог рейдового предупреждения, доступно только лидерам через /rpw.";
	-- Title of the global RP channel (/rp). Used in a number of places in the options.
	RP_CHANNEL = "RP-канал";
	-- Title for the secondary RP channels (/rp#), used in the options. {1} is a number 2-9.
	RP_CHANNEL_X = "RP-канал {1}";
	-- Tooltip for toggling the RP channel in the minimap menu. Also shows up in the options panel when mousing over the color option for it.
	RP_CHANNEL_1_TOOLTIP = "Основной RP-канал. Доступ через /rp.";
	-- Tooltip for toggling the secondary RP channels in the minimap menu. Also shows up in the options panel when mousing over the color option for them. {1} is a number 2-9.
	RP_CHANNEL_X_TOOLTIP = "Каналы 2–9 предназначены для небольших подгрупп. Доступ через /rp#.";
	VERSION_LABEL = "Версия: {1}";
	-- The author tag in the options panel.
	BY_AUTHOR = "от Tammya-MoonGuard";
	-- Label for the option that toggles the minimap menu button visibility.
	OPTION_MINIMAP_BUTTON = "Показывать кнопку у миникарты";
	-- Tooltiop for the option that toggles the minimap menu button visibility.
	OPTION_MINIMAP_BUTTON_TIP = "Показывать или скрывать кнопку у миникарты (если вы используете что-то другое, например Titan Panel, для доступа).";
	-- Label for the option that toggles the chat bubble modifications.
	OPTION_TRANSLATE_CHAT_BUBBLES = "Переводить облачка чата";
	-- Tooltip for the option that toggles the chat bubble modifications.
	OPTION_TRANSLATE_CHAT_BUBBLES_TIP = "Пытаться переводить облачка чата вместе с текстом.";
	-- Label for the option that toggles the "Whisper" button when right-clicking an enemy player.
	OPTION_WHISPER_BUTTON = "Кнопка шёпота";
	-- Tooltip for the option that toggles the "Whisper" button when right-clicking an enemy player.
	OPTION_WHISPER_BUTTON_TIP = "Добавляет кнопку «Шёпот» при клике ПКМ по игрокам противоположной фракции, если они друзья Battle.net. Это может сломать некоторые элементы интерфейса Blizzard, и она не нужна для /w игроку другой фракции.";
	-- Label for the chat colors section in the options panel.
	OPTION_CHAT_COLORS = "Цвета чата";

	-- A notice printed to chat when a user tries to use the /rpw command without permission.
	CANT_POST_RPW2 = "Только лидеры группы или помощники могут писать в RP-предупреждение.";
	WHISPER = "Шёпот";
	WHISPER_TIP = "Шёпот противоположной фракции. (Отправляется безопасно через прямой шёпот Battle.net, приватно, без использования ретрансляции сообщества.)";
	-- The label for the traffic monitor in the minimap button tooltip while connected.
	TRAFFIC = "Трафик";
	-- For the traffic monitor, suffix for kilobytes per second.
	KBPS = "КБ/с";
	-- Shown in the traffic monitor, for bytes per second. e.g. "Traffic: 520 B/s"
	BPS = "Б/с";
	-- What's shown when a community's name cannot be resolved for some reason. Probably won't ever be used.
	UNKNOWN_SERVER = "(Неизвестно)";
	
	-- Help text in the minimap button tooltip.
	MINIMAP_TOOLTIP_CLICK_OPEN_MENU = "|cffddddddКлик для открытия меню.";
	-- Help text in the minimap button tooltip.
	MINIMAP_TOOLTIP_RIGHTCLICK_OPEN_MENU = "|cffddddddПКМ для открытия меню.";
	
	-- How the client should localize height numbers. Can be "FEETINCHES" or "CM".
	HEIGHT_UNIT = "FEETINCHES";
	WEIGHT_UNIT = "POUNDS";
	-- Label for the toggle switch in the world map tracking list. This toggles showing Cross RP players on the map.
	MAP_TRACKING_CROSSRP_PLAYERS = "Игроки Cross RP";
	
	---------------------------------------------------------------------------------------
	-- The API can't fetch these for us for languages we don't know. These need
	-- to be filled in for each locale. In the future we might add more fake
	-- languages that can have their own IDs for extra RP languages.
	---------------------------------------------------------------------------------------
	
	-- This needs to match EXACTLY the ingame name for the language Orcish. Cross RP uses it to detect that language.
	LANGUAGE_1 = "Орочьий";
	-- This needs to match EXACTLY the ingame name for the language Common. Cross RP uses it to detect that language.
	LANGUAGE_7 = "Общий";
	LANGUAGES_NOT_SET = "Названия языков не настроены для вашей локали. Cross RP может работать некорректно.";
	
	-- Unused. Used to be the label for showing how long the relay has been idle in the minimap button tooltip.
	IDLE_TIME = "Время простоя";
	UPTIME = "Время работы";
	
	VERSION_TOO_OLD = "Доступно обязательное обновление, текущая версия может работать некорректно. Пожалуйста, скачайте последнюю версию Cross RP при первой возможности.";
	-- A message that tells the user what the latest version is. {1} is replaced with a version string such as "2.0.0".
	LATEST_VERSION = "Последняя версия: {1}.";
	
	-- Currently unused. Label for the Links button in the minimap menu (opens up a list of Cross RP community links).
	LINKS = "Ссылки";
	-- (Unused) Tooltip for the Links button in the minimap menu.
	LINKS_TOOLTIP = "Быстрый доступ к сообществам Cross RP.";
	-- Shown when the user is missing core files and needs to restart their game (or something else is wrong, which is unlikely).
	UPDATE_ERROR = "Cross RP установлен некорректно. Если вы недавно обновляли аддон, полностью закройте игру и перезапустите. Если ошибка сохраняется и вы используете последнюю версию Cross RP, отправьте отчёт об ошибке.";
	
	-- This is a notice that pops up when your Elixir of Tongues is running out. {1} is formatted as a time like "48 seconds" (seconds/minutes is localized elsewhere).
	ELIXIR_NOTICE = "Лингвистическое зелье истекает через {1}.";
	-- When the timer for the elixir notice reaches 0, this is shown instead.
	ELIXIR_NOTICE_EXPIRED = "Лингвистическое зелье истекло.";
	
	-- This shows up in the minimap tooltip, when Cross RP is "active" (meaning you are actively engaging in cross-faction RP).
	CROSSRP_ACTIVE = "Активен";
	-- This shows up in the minimap tooltip, when Cross RP is "idle", meaning it's in a low-power standby mode until you find some cross-faction RP.
	CROSSRP_INACTIVE = "Бездействует";
	
	-- Label for the "Translate Emotes" button in the minimap button menu.
	TRANSLATE_EMOTES = "Переводить эмоции";
	-- Tooltip text for the Translate Emotes button.
	TRANSLATE_EMOTES_TIP = "Превращать текст /emote в /say при нахождении рядом с противоположной фракцией. Другой стороне не нужен Cross RP.\n\nНе действует, если Cross RP бездействует (красная иконка).\n\nИзбегайте пьянства.";
	
	-- Label for the network status in the minimap button tooltip.
	NETWORK_STATUS = "Статус сети";
	-- Label for the network status display when you don't have any connections to other realms or factions.
	NO_CONNECTIONS = "Нет подключений.";
	
	-- Error printed when you try to use /rp chat while not in a linked group.
	NOT_IN_LINKED_GROUP = "Вы не в связанной группе.";
	
	USER_CONNECTED_TO_YOUR_GROUP = "{1} подключился к вашей группе.";
	-- Label for the button in the minimap menu to start a linked group.
	LINK_GROUP = "Связать группу";
	-- Label for the button in the minimap button menu to stop the group from being linked. Only usable by party leaders.
	UNLINK_GROUP = "Разорвать связь группы";
	-- A message printed to chat when the party leader starts a linked group.
	GROUP_LINKED = "Вы присоединились к связанной группе.";
	-- This prints to chat when the party leader stops the group from being linked.
	GROUP_UNLINKED = "Ваша группа больше не связана.";
	-- This is shown in the tooltip for the Link Group button to let the user know they can't change this unless they're the party leader.
	NEEDS_GROUP_LEADER = "Изменять может только лидер группы.";
	-- Error message when the user presses the Link/Unlink Group button when they aren't the party leader. Similar to the previous translation, but English uses "that" instead of "this" because the chatbox is usually far away from the minimap menu. :)
	NEEDS_GROUP_LEADER2 = "Изменять может только лидер группы.";
	
	-- This shows up in the minimap tooltip; it's a status label that lets the user know they're in a linked group.
	GROUP_STATUS_LINKED = "Группа связана";
	
	-- Tooltip for the Link Group button in the minimap menu.
	LINK_GROUP_TOOLTIP = "Свяжите вашу группу с другими группами, и чат /rp будет использоваться для общения между ними.";
	-- Tooltip text for the Unlink Group button in the minimap menu.
	UNLINK_GROUP_TOOLTIP = "Разорвите связь вашей группы с другими, отключив чат /rp.";
	
	-- This is an error message that shows up in chat when you try to use a Cross RP feature, but you need to wait until Cross RP is done initializing.
	CROSSRP_NOT_DONE_INITIALIZING = "Cross RP ещё не завершил запуск.";
	
	-- Help text for the dialog that pops up when the user clicks Link Group.
	LINK_GROUP_DIALOG = "Введите пароль для вашей связанной группы. Группы с одинаковым паролем будут связаны.";
	-- Error printed to chat when your RP chat message fails due to network problems.
	RPCHAT_TIMED_OUT = "Сообщение для {1} истекло.";
	-- Error that's printed to chat when your RP chat message failed due to having no bridge. A bridge is a player on your realm and faction that can deliver your message to another realm or faction (through their Battle.net friends).
	RPCHAT_NOBRIDGE = "Не удалось отправить сообщение для {1}. Нет доступного моста.";
	RELAY_RP_CHAT = "Ретранслировать RP-чат";
	RELAY_RP_CHAT_TOOLTIP = "Только для лидеров группы: любой полученный RP-чат будет копироваться в /raid или /party для игроков без Cross RP.";
	
	RELAY_RP_ROLL = "[{1}] выбросил {2} ({3}-{4})";
	
	-- Error message that's shown when you try to refresh your Elixir of Tongues, but don't have any.
	NO_MORE_ELIXIRS = "У вас закончились эликсиры!";
	
	INVALID_FACTION = "Отключение из-за отсутствия выбранной фракции.";
};	
