--[[
	Base commands shared.
]]

local Plugin = {}

function Plugin:SetupDataTable()
	self:AddDTVar( "integer (1 to 10)", "Gamestate", 1 )
	self:AddDTVar( "boolean", "AllTalk", false )
	self:AddDTVar( "boolean", "AllTalkPreGame", false )

	self:AddNetworkMessage( "RequestMapData", {}, "Server" )
	self:AddNetworkMessage( "MapData", { Name = "string (32)" }, "Client" )

	self:AddNetworkMessage( "RequestPluginData", {}, "Server" )
	self:AddNetworkMessage( "PluginData", { Name = "string (32)", Enabled = "boolean" }, "Client" )
	self:AddNetworkMessage( "PluginTabAuthed", {}, "Client" )

	local MessageTypes = {
		Empty = {},
		Enabled = {
			Enabled = "boolean"
		},
		Kick = {
			TargetName = self:GetNameNetworkField(),
			Reason = "string (64)"
		},
		FF = {
			Scale = "float (0 to 100 by 0.01)"
		},
		TeamChange = {
			TargetCount = "integer (0 to 127)",
			Team = "integer (0 to 3)"
		},
		RandomTeam = {
			TargetCount = "integer (0 to 127)"
		},
		TargetName = {
			TargetName = self:GetNameNetworkField()
		},
		Gagged = {
			TargetName = self:GetNameNetworkField(),
			Duration = "integer (0 to 1800)"
		},
		FloatRate = {
			Rate = "float (0 to 1000 by 0.01)"
		},
		IntegerRate = {
			Rate = "integer (0 to 1000)"
		}
	}

	self:AddNetworkMessages( "AddTranslatedMessage", {
		[ MessageTypes.Empty ] = {
			"RESET_GAME", "HIVE_TEAMS", "FORCE_START", "VOTE_STOPPED"
		},
		[ MessageTypes.Enabled ] = {
			"CHEATS_TOGGLED", "ALLTALK_TOGGLED", "ALLTALK_PREGAME_TOGGLED",
			"ALLTALK_LOCAL_TOGGLED"
		},
		[ MessageTypes.Kick ] = {
			"ClientKicked"
		},
		[ MessageTypes.FF ] = {
			"FRIENDLY_FIRE_SCALE"
		},
		[ MessageTypes.TeamChange ] = {
			"ChangeTeam"
		},
		[ MessageTypes.RandomTeam ] = {
			"RANDOM_TEAM"
		},
		[ table.Copy( MessageTypes.TargetName ) ] = {
			"PLAYER_EJECTED", "PLAYER_UNGAGGED"
		},
		[ MessageTypes.Gagged ] = {
			"PLAYER_GAGGED"
		}
	} )

	self:AddNetworkMessages( "AddTranslatedCommandError", {
		[ MessageTypes.TargetName ] = {
			"ERROR_NOT_COMMANDER", "ERROR_NOT_GAGGED"
		},
		[ MessageTypes.FloatRate ] = {
			"ERROR_INTERP_CONSTRAINT"
		},
		[ MessageTypes.IntegerRate ] = {
			"ERROR_TICKRATE_CONSTRAINT", "ERROR_SENDRATE_CONSTRAINT",
			"ERROR_SENDRATE_MOVE_CONSTRAINT", "ERROR_MOVERATE_CONSTRAINT",
			"ERROR_MOVERATE_SENDRATE_CONSTRAINT"
		}
	} )

	self:AddNetworkMessage( "EnableLocalAllTalk", { Enabled = "boolean" }, "Server" )
end

Shine:RegisterExtension( "basecommands", Plugin )

if Server then return end

Plugin.HasConfig = true
Plugin.ConfigName = "BaseCommands.json"
Plugin.DefaultConfig = {
	DisableLocalAllTalk = false
}
Plugin.CheckConfig = true
Plugin.CheckConfigTypes = true

Shine.Hook.Add( "PostLoadScript", "SetupCustomVote", function( Script )
	if Script ~= "lua/Voting.lua" then return end

	RegisterVoteType( "ShineCustomVote", { VoteQuestion = "string (64)" } )

	AddVoteSetupCallback( function( VoteMenu )
		AddVoteStartListener( "ShineCustomVote", function( Data )
			return Data.VoteQuestion
		end )
	end )
end )

local Shine = Shine
local Hook = Shine.Hook
local SGUI = Shine.GUI

local StringFormat = string.format
local StringTimeToString = string.TimeToString
local TableEmpty = table.Empty

function Plugin:Initialise()
	if self.dt.AllTalk or self.dt.AllTalkPreGame then
		self:UpdateAllTalk( self.dt.Gamestate )
	end

	self:SetupAdminMenuCommands()
	self:SetupClientConfig()

	self.Enabled = true

	return true
end

function Plugin:NetworkUpdate( Key, Old, New )
	if Key == "Gamestate" then
		if ( Old == kGameState.PreGame or Old == kGameState.WarmUp ) and New == kGameState.NotStarted then
			-- The game state changes back to NotStarted, then to Countdown to start. This is VERY annoying...
			self:SimpleTimer( 1, function()
				if self.dt.Gamestate == kGameState.NotStarted then
					self:UpdateAllTalk( self.dt.Gamestate )
				end
			end )

			return
		end

		self:UpdateAllTalk( New )
	elseif Key == "AllTalk" then
		if not New and not self.dt.AllTalkPreGame then
			self:RemoveAllTalkText()
		else
			self:UpdateAllTalk( self.dt.Gamestate )
		end
	elseif Key == "AllTalkPreGame" then
		if New or self.dt.AllTalk then
			self:UpdateAllTalk( self.dt.Gamestate )
		else
			self:RemoveAllTalkText()
		end
	end
end

function Plugin:ReceiveClientKicked( Data )
	local Key = Data.Reason ~= "" and "CLIENT_KICKED_REASON" or "CLIENT_KICKED"
	self:CommandNotify( Data.AdminName, Key, Data )
end

function Plugin:ReceiveChangeTeam( Data )
	local TeamKeys = {
		[ 0 ] = "CHANGE_TEAM_READY_ROOM",
		"CHANGE_TEAM_MARINE",
		"CHANGE_TEAM_ALIEN",
		"CHANGE_TEAM_SPECTATOR"
	}

	self:CommandNotify( Data.AdminName, TeamKeys[ Data.Team ], Data )
end

function Plugin:SetupClientConfig()
	Shine.AddStartupMessage( "You can choose to enable/disable local all talk for yourself by entering sh_alltalklocal_cl true/false." )

	if self.Config.DisableLocalAllTalk then
		self:SendNetworkMessage( "EnableLocalAllTalk", { Enabled = false }, true )
	end

	self:BindCommand( "sh_alltalklocal_cl", function( Enable )
		self.Config.DisableLocalAllTalk = not Enable
		self:SaveConfig( true )
		self:SendNetworkMessage( "EnableLocalAllTalk", { Enabled = Enable }, true )

		Print( "Local all talk is now %s.", Enable and "enabled" or "disabled" )
	end ):AddParam{ Type = "boolean", Optional = true, Default = function() return self.Config.DisableLocalAllTalk end }

	Shine:RegisterClientSetting( {
		Type = "Boolean",
		Command = "sh_alltalklocal_cl",
		ConfigOption = function() return not self.Config.DisableLocalAllTalk end,
		Description = "ALL_TALK_LOCAL_DESCRIPTION",
		TranslationSource = self.__Name
	} )
end

function Plugin:SetupAdminMenuCommands()
	local Category = self:GetPhrase( "CATEGORY" )

	self:AddAdminMenuCommand( Category, self:GetPhrase( "EJECT" ), "sh_eject", false, nil,
		self:GetPhrase( "EJECT_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "KICK" ), "sh_kick", false, {
		self:GetPhrase( "KICK_NO_REASON" ), "",
		self:GetPhrase( "KICK_TROLLING" ), "Trolling.",
		self:GetPhrase( "KICK_LANGUAGE" ), "Offensive language.",
		self:GetPhrase( "KICK_MIC_SPAM" ), "Mic spamming.",
		self:GetPhrase( "KICK_AFK" ), "AFK.",
		"Custom", {
			Setup = function( Menu, Command, Player, CleanupMenu )
				local Panel = SGUI:Create( "Panel", Menu )
				local TextEntry = SGUI:Create( "TextEntry", Panel )
				TextEntry:SetFill( true )
				TextEntry:SetPlaceholderText( self:GetPhrase( "KICK_CUSTOM" ) )
				TextEntry:SetFontScale( Fonts.kAgencyFB_Small, Vector2( 0.9, 0.9 ) )
				function TextEntry:OnEnter()
					local Text = self:GetText()
					if #Text == 0 then return end

					Shine.AdminMenu:RunCommand( Command, StringFormat( "%s %s", Player, Text ) )
					CleanupMenu()
				end

				local Layout = SGUI.Layout:CreateLayout( "Horizontal", {
					Padding = SGUI.Layout.Units.Spacing( 2, 2, 2, 2 )
				} )
				Layout:AddElement( TextEntry )
				Panel:SetLayout( Layout )

				Menu:AddPanel( Panel )
			end
		},
		Width = 192
	}, self:GetPhrase( "KICK_TIP" ) )

	local GagTimes = {
		5 * 60, 10 * 60, 15 * 60, 20 * 60, 30 * 60
	}
	local GagLabels = {}
	for i = 1, #GagTimes do
		local Time = GagTimes[ i ]
		local TimeString = StringTimeToString( Time )

		GagLabels[ i * 2 - 1 ] = TimeString
		GagLabels[ i * 2 ] = tostring( Time )
	end

	GagLabels[ #GagLabels + 1 ] = self:GetPhrase( "GAG_UNTIL_MAP_CHANGE" )
	GagLabels[ #GagLabels + 1 ] = ""
	GagLabels[ #GagLabels + 1 ] = self:GetPhrase( "PERMANENTLY" )
	GagLabels[ #GagLabels + 1 ] = function( Args )
		Shine.AdminMenu:RunCommand( "sh_gagid", Args )
	end

	self:AddAdminMenuCommand( Category, self:GetPhrase( "GAG" ), "sh_gag", false, GagLabels,
		self:GetPhrase( "GAG_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "UNGAG" ), "sh_ungag", false, nil,
		self:GetPhrase( "UNGAG_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "FORCE_RANDOM" ), "sh_forcerandom", true, nil,
		self:GetPhrase( "FORCE_RANDOM_TIP" ) )
	self:AddAdminMenuCommand( Category, self:GetPhrase( "READY_ROOM" ), "sh_rr", true, nil,
		self:GetPhrase( "READY_ROOM_TIP" ) )
	local Teams = {}
	for i = 0, 3 do
		local TeamName = Shine:GetTeamName( i, true )
		i = i + 1

		Teams[ i * 2 - 1 ] = TeamName
		Teams[ i * 2 ] = tostring( i - 1 )
	end
	self:AddAdminMenuCommand( Category, self:GetPhrase( "SET_TEAM" ), "sh_setteam", true, Teams,
		self:GetPhrase( "SET_TEAM_TIP" ) )

	local Units = SGUI.Layout.Units
	local HighResScaled = Units.HighResScaled
	local Percentage = Units.Percentage
	local Spacing = Units.Spacing
	local UnitVector = Units.UnitVector
	local Auto = Units.Auto

	self:AddAdminMenuTab( self:GetPhrase( "MAPS" ), {
		OnInit = function( Panel, Data )
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( HighResScaled( 16 ), HighResScaled( 28 ),
					HighResScaled( 16 ), HighResScaled( 16 ) )
			} )

			local List = SGUI:Create( "List", Panel )
			List:SetColumns( self:GetPhrase( "MAP" ) )
			List:SetSpacing( 1 )
			List:SetFill( true )

			Shine.AdminMenu.SetupListWithScaling( List )

			local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

			Layout:AddElement( List )

			self.MapList = List

			local ControlLayout = SGUI.Layout:CreateLayout( "Horizontal", {
				Margin = Spacing( 0, HighResScaled( 16 ), 0, 0 ),
				Fill = false
			} )

			local ChangeMap = SGUI:Create( "Button", Panel )
			ChangeMap:SetText( self:GetPhrase( "CHANGE_MAP" ) )
			ChangeMap:SetFontScale( Font, Scale )
			ChangeMap:SetStyleName( "DangerButton" )
			function ChangeMap.DoClick()
				local Selected = List:GetSelectedRow()
				if not Selected then return end

				local Map = Selected:GetColumnText( 1 )

				Shine.AdminMenu:RunCommand( "sh_changelevel", Map )
			end
			ChangeMap:SetTooltip( self:GetPhrase( "CHANGE_MAP_TIP" ) )
			ChangeMap:SetEnabled( List:HasSelectedRow() )

			ControlLayout:AddElement( ChangeMap )

			function List:OnRowSelected( Index, Row )
				ChangeMap:SetEnabled( true )
			end

			function List:OnRowDeselected( Index, Row )
				ChangeMap:SetEnabled( false )
			end

			local ButtonWidth = Units.Max(
				HighResScaled( 128 ),
				Auto( ChangeMap ) + HighResScaled( 16 )
			)

			ChangeMap:SetAutoSize( UnitVector( ButtonWidth, Percentage( 100 ) ) )

			if Shine:IsExtensionEnabled( "mapvote" ) then
				local CallVote = SGUI:Create( "Button", Panel )
				CallVote:SetText( self:GetPhrase( "CALL_VOTE" ) )
				CallVote:SetFontScale( Font, Scale )
				CallVote:SetAlignment( SGUI.LayoutAlignment.MAX )
				function CallVote.DoClick()
					Shine.AdminMenu:RunCommand( "sh_forcemapvote" )
				end
				CallVote:SetTooltip( self:GetPhrase( "CALL_VOTE_TIP" ) )
				CallVote:SetAutoSize( UnitVector( ButtonWidth, Percentage( 100 ) ) )

				ButtonWidth:AddValue( Auto( CallVote ) + HighResScaled( 16 ) )

				ControlLayout:AddElement( CallVote )
			end

			local ButtonHeight = Auto( ChangeMap ) + HighResScaled( 8 )
			ControlLayout:SetAutoSize( UnitVector( Percentage( 100 ), ButtonHeight ) )

			Layout:AddElement( ControlLayout )
			Panel:SetLayout( Layout )
			Panel:InvalidateLayout( true )

			if not self.MapData then
				self:RequestMapData()
			else
				for Map in pairs( self.MapData ) do
					List:AddRow( Map )
				end
			end

			if not Shine.AdminMenu.RestoreListState( List, Data ) then
				List:SortRows( 1 )
			end
		end,

		OnCleanup = function( Panel )
			local MapList = self.MapList
			self.MapList = nil

			return Shine.AdminMenu.GetListState( MapList )
		end
	} )

	self:AddAdminMenuTab( self:GetPhrase( "PLUGINS" ), {
		OnInit = function( Panel, Data )
			local Layout = SGUI.Layout:CreateLayout( "Vertical", {
				Padding = Spacing( HighResScaled( 16 ), HighResScaled( 28 ),
					HighResScaled( 16 ), HighResScaled( 16 ) )
			} )

			local List = SGUI:Create( "List", Panel )
			List:SetColumns( self:GetPhrase( "PLUGIN" ), self:GetPhrase( "STATE" ) )
			List:SetSpacing( 0.8, 0.2 )
			List:SetSecondarySortColumn( 2, 1 )
			List:SetFill( true )

			Shine.AdminMenu.SetupListWithScaling( List )

			local Font, Scale = SGUI.FontManager.GetHighResFont( "kAgencyFB", 27 )

			Layout:AddElement( List )

			self.PluginList = List
			self.PluginRows = self.PluginRows or {}

			-- We need information about the server side only plugins too.
			if not self.PluginData then
				self:RequestPluginData()
				self.PluginData = {}
			end

			local ControlLayout = SGUI.Layout:CreateLayout( "Horizontal", {
				Margin = Spacing( 0, HighResScaled( 16 ), 0, 0 ),
				Fill = false
			} )

			local function GetSelectedPlugin()
				local Selected = List:GetSelectedRow()
				if not Selected then return end

				return Selected:GetColumnText( 1 ), Selected.PluginEnabled
			end

			local UnloadPlugin = SGUI:Create( "Button", Panel )
			UnloadPlugin:SetText( self:GetPhrase( "UNLOAD_PLUGIN" ) )
			UnloadPlugin:SetFontScale( Font, Scale )
			UnloadPlugin:SetStyleName( "DangerButton" )
			UnloadPlugin:SetEnabled( List:HasSelectedRow() )
			function UnloadPlugin.DoClick( Button )
				local Plugin, Enabled = GetSelectedPlugin()
				if not Plugin then return false end
				if not Enabled then return false end

				local Menu = Button:AddMenu()

				Menu:AddButton( self:GetPhrase( "NOW" ), function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_unloadplugin", Plugin )
				end, self:GetPhrase( "UNLOAD_PLUGIN_TIP" ) ):SetStyleName( "DangerButton" )

				Menu:AddButton( self:GetPhrase( "PERMANENTLY" ), function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_unloadplugin", Plugin.." true" )
				end, self:GetPhrase( "UNLOAD_PLUGIN_SAVE_TIP" ) ):SetStyleName( "DangerButton" )
			end

			ControlLayout:AddElement( UnloadPlugin )

			local LoadPlugin = SGUI:Create( "Button", Panel )
			LoadPlugin:SetText( self:GetPhrase( "LOAD_PLUGIN" ) )
			LoadPlugin:SetFontScale( Font, Scale )
			LoadPlugin:SetStyleName( "SuccessButton" )
			LoadPlugin:SetEnabled( List:HasSelectedRow() )
			LoadPlugin:SetAlignment( SGUI.LayoutAlignment.MAX )
			local function NormalLoadDoClick( Button )
				local Plugin = GetSelectedPlugin()
				if not Plugin then return false end

				local Menu = Button:AddMenu()

				Menu:AddButton( self:GetPhrase( "NOW" ), function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin )
				end, self:GetPhrase( "LOAD_PLUGIN_TIP" ) ):SetStyleName( "SuccessButton" )

				Menu:AddButton( self:GetPhrase( "PERMANENTLY" ), function()
					Menu:Destroy()

					Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin.." true" )
				end, self:GetPhrase( "LOAD_PLUGIN_SAVE_TIP" ) ):SetStyleName( "SuccessButton" )
			end

			ControlLayout:AddElement( LoadPlugin )

			local function ReloadDoClick()
				local Plugin = GetSelectedPlugin()
				if not Plugin then return false end

				Shine.AdminMenu:RunCommand( "sh_loadplugin", Plugin )
			end

			LoadPlugin.DoClick = NormalLoadDoClick

			function List.OnRowSelected( List, Index, Row )
				local State = Row.PluginEnabled

				LoadPlugin:SetEnabled( true )
				UnloadPlugin:SetEnabled( true )

				if State then
					LoadPlugin:SetText( self:GetPhrase( "RELOAD_PLUGIN" ) )
					LoadPlugin.DoClick = ReloadDoClick
				else
					LoadPlugin:SetText( self:GetPhrase( "LOAD_PLUGIN" ) )
					LoadPlugin.DoClick = NormalLoadDoClick
				end
			end

			function List:OnRowDeselected( Index, Row )
				LoadPlugin:SetEnabled( false )
				UnloadPlugin:SetEnabled( false )
			end

			local function UpdateRow( Name, State )
				local Row = self.PluginRows[ Name ]

				if SGUI.IsValid( Row ) then
					self:SetPluginRowState( Row, State )

					if Row == List:GetSelectedRow() then
						List:OnRowSelected( nil, Row )
					end
				end
			end

			Hook.Add( "OnPluginLoad", "AdminMenu_OnPluginLoad", function( Name, Plugin, Shared )
				UpdateRow( Name, true )
			end )

			Hook.Add( "OnPluginUnload", "AdminMenu_OnPluginUnload", function( Name, Plugin, Shared )
				UpdateRow( Name, false )
			end )

			local ButtonWidth = Units.Max(
				HighResScaled( 128 ),
				Auto( LoadPlugin ) + HighResScaled( 16 ),
				Auto( UnloadPlugin ) + HighResScaled( 16 )
			)
			UnloadPlugin:SetAutoSize( UnitVector( ButtonWidth, Percentage( 100 ) ) )
			LoadPlugin:SetAutoSize( UnitVector( ButtonWidth, Percentage( 100 ) ) )

			local ButtonHeight = Auto( LoadPlugin ) + HighResScaled( 8 )
			ControlLayout:SetAutoSize( UnitVector( Percentage( 100 ), ButtonHeight ) )

			Layout:AddElement( ControlLayout )
			Panel:SetLayout( Layout )
			Panel:InvalidateLayout( true )

			if self.PluginAuthed then
				self:PopulatePluginList()
			end

			if not Shine.AdminMenu.RestoreListState( List, Data ) then
				List:SortRows( 2, nil, true )
			end
		end,

		OnCleanup = function( Panel )
			TableEmpty( self.PluginRows )

			local PluginList = self.PluginList
			self.PluginList = nil

			Hook.Remove( "OnPluginLoad", "AdminMenu_OnPluginLoad" )
			Hook.Remove( "OnPluginUnload", "AdminMenu_OnPluginUnload" )

			return Shine.AdminMenu.GetListState( PluginList )
		end
	} )
end

function Plugin:RequestMapData()
	self:SendNetworkMessage( "RequestMapData", {}, true )
end

function Plugin:ReceiveMapData( Data )
	self.MapData = self.MapData or {}

	if self.MapData[ Data.Name ] then return end

	self.MapData[ Data.Name ] = true

	if SGUI.IsValid( self.MapList ) then
		self.MapList:AddRow( Data.Name )
	end
end

function Plugin:RequestPluginData()
	self:SendNetworkMessage( "RequestPluginData", {}, true )
end

function Plugin:ReceivePluginTabAuthed()
	self.PluginAuthed = true
	self:PopulatePluginList()
end

function Plugin:PopulatePluginList()
	local List = self.PluginList
	if not SGUI.IsValid( List ) then return end

	for Plugin in pairs( Shine.AllPlugins ) do
		local Enabled, PluginTable = Shine:IsExtensionEnabled( Plugin )
		local Skip
		-- Server side plugin.
		if not PluginTable then
			Enabled = self.PluginData and self.PluginData[ Plugin ]
		elseif PluginTable.IsClient and not PluginTable.IsShared then
			Skip = true
		end

		if not Skip then
			local Row = List:AddRow( Plugin, "" )
			self:SetPluginRowState( Row, Enabled )

			self.PluginRows[ Plugin ] = Row
		end
	end
end

function Plugin:SetPluginRowState( Row, Enabled )
	local Font, Scale = SGUI.FontManager.GetHighResFont( SGUI.FontFamilies.Ionicons, 27 )
	Row:SetColumnText( 2, SGUI.Icons.Ionicons[ Enabled and "CheckmarkCircled" or "MinusCircled" ] )
	Row:SetTextOverride( 2, {
		Font = Font,
		TextScale = Scale,
		Colour = Enabled and Colour( 0, 1, 0 ) or Colour( 1, 0.8, 0 )
	} )
	Row:SetData( 2, Enabled and "1" or "0" )
	Row.PluginEnabled = Enabled
end

function Plugin:ReceivePluginData( Data )
	self.PluginData = self.PluginData or {}
	self.PluginData[ Data.Name ] = Data.Enabled

	local Row = self.PluginRows[ Data.Name ]

	if Row then
		self:SetPluginRowState( Row, Data.Enabled )

		if Row == self.PluginList:GetSelectedRow() then
			self.PluginList:OnRowSelected( nil, Row )
		end
	end
end

local NOT_STARTED = kGameState and kGameState.WarmUp or 2
local COUNTDOWN = kGameState and kGameState.Countdown or 4

function Plugin:UpdateAllTalk( State )
	if not self.dt.AllTalk and not self.dt.AllTalkPreGame then return end

	if State >= COUNTDOWN and not self.dt.AllTalk then
		self:RemoveAllTalkText()
		return
	end

	local Phrase
	local AllTalkIsDisabled = State > NOT_STARTED and not self.dt.AllTalk
	if AllTalkIsDisabled then
		Phrase = self:GetPhrase( "ALLTALK_DISABLED" )
	else
		Phrase = self:GetPhrase( "ALLTALK_ENABLED" )
	end

	if not self.TextObj then
		local GB = AllTalkIsDisabled and 0 or 255

		self.TextObj = Shine.ScreenText.Add( "AllTalkState", {
			X = 0.5, Y = 0.95,
			Text = Phrase,
			R = 255, G = GB, B = GB,
			Alignment = 1,
			Size = 2,
			FadeIn = 1,
			IgnoreFormat = true,
			UpdateRate = 0.1
		} )

		function self.TextObj:UpdateForInventoryState( IsAlwaysVisible )
			if IsAlwaysVisible and not self.SetupForVisibleInventory then
				-- Inventory is always visible, so move text to the top of the screen
				-- (some configurations have a giant inventory that extends to the bottom
				-- of the screen, and the inventory position doesn't account for ammo text).
				self.SetupForVisibleInventory = true
				self:SetIsVisible( true )

				self:SetScaledPos( self.x, 0 )
				self:SetTextAlignmentY( GUIItem.Align_Min )
			elseif not IsAlwaysVisible and self.SetupForVisibleInventory then
				-- Inventory is only visible when in use, so we'll hide the text.
				self.SetupForVisibleInventory = false

				self:SetScaledPos( self.x, 0.95 )
				self:SetTextAlignmentY( GUIItem.Align_Center )
			end
		end

		-- Hide the text if the inventory HUD is visible (avoids the text overlapping it).
		-- There's no easy way to determine its visibility, so this awkward polling will have to do.
		function self.TextObj:Think()
			local HUD = ClientUI.GetScript( "Hud/Marine/GUIMarineHUD" ) or ClientUI.GetScript( "GUIAlienHUD" )
			local Inventory = HUD and HUD.inventoryDisplay
			local InventoryIsVisible = Inventory and Inventory.background and Inventory.background:GetIsVisible()

			if not ( InventoryIsVisible and Inventory.inventoryIcons ) then
				self:SetIsVisible( true )
				self:UpdateForInventoryState( false )
				return
			end

			if Inventory.forceAnimationReset then
				self:UpdateForInventoryState( true )

				return
			end

			self:UpdateForInventoryState( false )

			local Items = Inventory.inventoryIcons
			for i = 1, #Items do
				local Item = Items[ i ]
				if Item and Item.Graphic and Item.Graphic:GetColor().a > 0 then
					-- Inventory is temporarily visible, hide the text.
					self:SetIsVisible( false )
					return
				end
			end

			-- Inventory is not visible, show the text.
			self:SetIsVisible( true )
		end

		return
	end

	self.TextObj.Text = Phrase
	self.TextObj:UpdateText()

	local Col = AllTalkIsDisabled and Color( 255, 0, 0 ) or Color( 255, 255, 255 )

	self.TextObj:SetColour( Col )
end

function Plugin:RemoveAllTalkText()
	if not self.TextObj then return end

	self.TextObj:End()
	self.TextObj = nil
end

function Plugin:Cleanup()
	self:RemoveAllTalkText()

	self.BaseClass.Cleanup( self )
end
