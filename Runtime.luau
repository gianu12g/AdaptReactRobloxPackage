--!strict
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Store = require(script.Parent.Store)

local Runtime = {}

-- internal singletons
local _store = Store.new()
local _React = nil
local _ReactRoblox = nil

local _serviceLocator = nil
local _player = nil
local _packages = nil

local _screenGui: ScreenGui? = nil
local _rootFrame: Frame? = nil
local _rootHandle = nil

local _inputConn: RBXScriptConnection? = nil

type KeyAction = "toggle" | "open" | "close"
type KeyBindingEntry = {
	screenId: string,
	action: KeyAction,
	key: Enum.KeyCode,
}

local _keyIndex: { [Enum.KeyCode]: { KeyBindingEntry } } = {}

local function assertMounted()
	if not _store:getState().mounted then
		error("[ui_runtime] Not mounted. Call UIRuntime.mount(...) first.")
	end
end

local function waitFrames(n: number)
	for _ = 1, n do
		RunService.Heartbeat:Wait()
	end
end

local function getScreenDef(id: string)
	local def = _store:getState().screens[id]
	if not def then
		error(("[ui_runtime] Unknown screen '%s'. Did you register it?"):format(id))
	end
	return def
end

local function _clearKeyIndex()
	_keyIndex = {}
end

local function _pushKeyBinding(key: Enum.KeyCode, entry: KeyBindingEntry)
	if key == Enum.KeyCode.Unknown then
		return
	end
	local bucket = _keyIndex[key]
	if not bucket then
		bucket = {}
		_keyIndex[key] = bucket
	end
	table.insert(bucket, entry)
end

local function _rebuildKeyIndexAndWarnConflicts()
	_clearKeyIndex()

	local st = _store:getState()
	local bindCount = 0

	for screenId, def in pairs(st.screens) do
		local binds = def.meta.binds
		if binds then
			if binds.toggleKey then
				_pushKeyBinding(binds.toggleKey, { screenId = screenId, action = "toggle", key = binds.toggleKey })
				bindCount += 1
			end
			if binds.openKey then
				_pushKeyBinding(binds.openKey, { screenId = screenId, action = "open", key = binds.openKey })
				bindCount += 1
			end
			if binds.closeKey then
				_pushKeyBinding(binds.closeKey, { screenId = screenId, action = "close", key = binds.closeKey })
				bindCount += 1
			end
		end
	end

	for key, entries in pairs(_keyIndex) do
		local names = {}
		for _, e in ipairs(entries) do
			table.insert(names, ("%s:%s"):format(e.screenId, e.action))
		end
	end

	-- Warn conflicts
	for key, entries in pairs(_keyIndex) do
		if #entries > 1 then
			table.sort(entries, function(a, b)
				local ad = st.screens[a.screenId] and (st.screens[a.screenId].meta.displayOrder or 0) or 0
				local bd = st.screens[b.screenId] and (st.screens[b.screenId].meta.displayOrder or 0) or 0
				if ad == bd then
					return a.screenId < b.screenId
				end
				return ad > bd
			end)

			local names = {}
			for _, e in ipairs(entries) do
				table.insert(names, ("%s:%s"):format(e.screenId, e.action))
			end

			warn(
				("[ui_runtime] Keybind conflict on %s => [%s]. Winner: %s:%s"):format(
					tostring(key),
					table.concat(names, ", "),
					entries[1].screenId,
					entries[1].action
				)
			)
		end
	end
end

local function _bindingAllowedNow(def, binds, lifecycle)
	-- TextBox focus check
	local focused = UserInputService:GetFocusedTextBox()
	if focused and not (binds and binds.allowWhenTextBoxFocused) then
		return false
	end

	-- Character-lifetime screens need character ready
	local lifetime = def.meta.lifetime or "player"
	if lifetime == "character" and not lifecycle.isCharacterReady then
		return false
	end

	-- Explicit requireCharacterReady
	if binds and binds.requireCharacterReady and not lifecycle.isCharacterReady then
		return false
	end

	return true
end

local function _handleInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	local key = input.KeyCode
	if key == Enum.KeyCode.Unknown then
		return
	end

	local bucket = _keyIndex[key]
	if not bucket or #bucket == 0 then
		return
	end

	local st = _store:getState()
	local life = st.lifecycle

	local best: KeyBindingEntry? = nil
	local bestOrder = -math.huge

	for _, entry in ipairs(bucket) do
		local def = st.screens[entry.screenId]
		if def then
			local binds = def.meta.binds
			if _bindingAllowedNow(def, binds, life) then
				local order = def.meta.displayOrder or 0
				if order > bestOrder then
					bestOrder = order
					best = entry
				elseif order == bestOrder and best ~= nil then
					if entry.screenId < best.screenId then
						best = entry
					end
				end
			end
		end
	end

	if not best then
		return
	end

	if best.action == "toggle" then
		Runtime.toggle(best.screenId)
	elseif best.action == "open" then
		Runtime.open(best.screenId)
	elseif best.action == "close" then
		Runtime.close(best.screenId)
	end
end

export type MountOptions = {
	player: Player,
	playerGui: PlayerGui,
	serviceLocator: any,
	packages: Instance,
	app: any,
	config: {
		screenGuiName: string?,
		ignoreGuiInset: boolean?,
		displayOrder: number?,
	}?,
}

function Runtime.mount(opts: MountOptions)
	if _store:getState().mounted then
		error("[ui_runtime] mount() called twice.")
	end

	_player = opts.player
	_serviceLocator = opts.serviceLocator
	_packages = opts.packages

	_React = require(opts.packages:WaitForChild("React"))
	_ReactRoblox = require(opts.packages:WaitForChild("ReactRoblox"))

	_store:setState(function(s)
		s.mounted = true
		if opts.config then
			if opts.config.screenGuiName ~= nil then
				s.config.screenGuiName = opts.config.screenGuiName
			end
			if opts.config.ignoreGuiInset ~= nil then
				s.config.ignoreGuiInset = opts.config.ignoreGuiInset
			end
			if opts.config.displayOrder ~= nil then
				s.config.displayOrder = opts.config.displayOrder
			end
		end
	end)

	local st = _store:getState()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = st.config.screenGuiName
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = st.config.ignoreGuiInset
	screenGui.DisplayOrder = st.config.displayOrder
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = opts.playerGui

	local rootFrame = Instance.new("Frame")
	rootFrame.Name = "Root"
	rootFrame.BackgroundTransparency = 1
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.Position = UDim2.fromScale(0, 0)
	rootFrame.Parent = screenGui

	_screenGui = screenGui
	_rootFrame = rootFrame

	-- Wire up character lifecycle (player is already ready via service deps)
	local loader = _serviceLocator:Get("ClientLoaderService")
	if not loader then
		error("[ui_runtime] ClientLoaderService not found")
	end

	_store:setState(function(s)
		s.lifecycle.isCharacterReady = loader:IsCharacterReady()
		s.lifecycle.character = loader:GetCharacter()
		s.lifecycle.humanoid = loader:GetHumanoid()
	end)

	loader:OnCharacterReady(function(character)
		_store:setState(function(s)
			s.lifecycle.isCharacterReady = true
			s.lifecycle.character = character
			s.lifecycle.humanoid = loader:GetHumanoid()
			s.characterEpoch = (s.characterEpoch or 0) + 1
		end)
		Runtime._applyCharacterInitialScreens()
	end)

	loader.CharacterRemoving:Connect(function()
		_store:setState(function(s)
			s.lifecycle.isCharacterReady = false
			s.lifecycle.character = nil
			s.lifecycle.humanoid = nil
		end)
		Runtime._handleCharacterRemoving()
	end)

	_inputConn = UserInputService.InputBegan:Connect(_handleInputBegan)

	local RootModule = require(script.Parent.Root)
	local root = _ReactRoblox.createRoot(rootFrame)
	_rootHandle = root

	root:render(_React.createElement(RootModule.Root, {
		React = _React,
		store = _store,
		app = opts.app,
	}))
end

function Runtime.registerScreen(id: string, component: any, meta)
	assertMounted()

	if not id or id == "" then
		warn("[ui_runtime] ✗ registerScreen: empty id")
		return
	end

	if not component then
		warn(("[ui_runtime] ✗ registerScreen '%s': nil component"):format(id))
		return
	end

	local screenMeta = meta or {}
	local lifetime = screenMeta.lifetime or "player"
	screenMeta.lifetime = lifetime

	if screenMeta.displayOrder == nil then
		screenMeta.displayOrder = 0
	end

	if screenMeta.closeOnCharacterRemoving == nil then
		screenMeta.closeOnCharacterRemoving = (lifetime == "character")
	end

	if screenMeta.binds then
		if screenMeta.binds.allowWhenTextBoxFocused == nil then
			screenMeta.binds.allowWhenTextBoxFocused = false
		end
	end

	local existingDef = _store:getState().screens[id]
	if existingDef then
		warn(("[ui_runtime] ⚠ '%s' already registered - overwriting"):format(id))
	end

	_store:setState(function(s)
		s.screens[id] = {
			id = id,
			component = component,
			meta = screenMeta,
		}
	end)

	_rebuildKeyIndexAndWarnConflicts()
end

function Runtime.setInitialScreens(ids: { string })
	assertMounted()

	_store:setState(function(s)
		s.initialScreens = ids
	end)
	Runtime._applyInitialScreens()
end

-- ✅ NEW: Per-character initial screens (reapplied on every respawn)
function Runtime.setCharacterInitialScreens(ids: { string })
	assertMounted()

	_store:setState(function(s)
		s.characterInitialScreens = ids
	end)

	if _store:getState().lifecycle.isCharacterReady then
		Runtime._applyCharacterInitialScreens()
	end
end

function Runtime.open(id: string)
	assertMounted()
	local def = getScreenDef(id)
	local meta = def.meta

	_store:setState(function(s)
		if meta.exclusiveGroup then
			for otherId, otherDef in pairs(s.screens) do
				if otherId ~= id and otherDef.meta.exclusiveGroup == meta.exclusiveGroup then
					s.active[otherId] = nil
				end
			end
		end
		s.active[id] = true
	end)
end

function Runtime.close(id: string)
	assertMounted()
	_store:setState(function(s)
		s.active[id] = nil
	end)
end

function Runtime.toggle(id: string)
	assertMounted()
	if _store:getState().active[id] then
		Runtime.close(id)
	else
		Runtime.open(id)
	end
end

function Runtime.isOpen(id: string): boolean
	assertMounted()
	return _store:getState().active[id] == true
end

function Runtime.Root()
	assertMounted()
	local RootModule = require(script.Parent.Root)
	return _React.createElement(RootModule.RootView, {
		React = _React,
		store = _store,
	})
end

function Runtime.useAttribute(path: string, options)
	assertMounted()
	local useAttribute = require(script.Parent.Hooks.useAttribute)
	return useAttribute(_React, _serviceLocator, path, options)
end

function Runtime.useLifecycle()
	assertMounted()
	local useLifecycle = require(script.Parent.Hooks.useLifecycle)
	return useLifecycle(_React, _store)
end

function Runtime._applyInitialScreens()
	local st = _store:getState()
	if not st.mounted or #st.initialScreens == 0 then
		return
	end

	-- Only apply if nothing is currently open
	for _ in pairs(st.active) do
		return
	end

	for _, id in ipairs(st.initialScreens) do
		if st.screens[id] then
			Runtime.open(id)
		else
			warn(("[ui_runtime] ✗ Initial screen '%s' not registered"):format(id))
		end
	end
end

-- ✅ NEW: apply per-character initial screens (runs on every character ready)
function Runtime._applyCharacterInitialScreens()
	local st = _store:getState()
	if not st.mounted or not st.lifecycle.isCharacterReady then
		return
	end

	local ids = st.characterInitialScreens
	if not ids or #ids == 0 then
		return
	end

	-- Capture the current epoch so we can cancel if another respawn happens
	local epoch = st.characterEpoch or 0

	-- Defer so it happens after the current tick, then after a couple frames
	task.defer(function()
		-- Let CharacterRemoving cleanup + any React commit happen
		waitFrames(5)

		local st2 = _store:getState()
		if not st2.mounted then
			return
		end
		if not st2.lifecycle.isCharacterReady then
			return
		end
		if (st2.characterEpoch or 0) ~= epoch then
			-- A newer character took over; ignore
			return
		end

		local ids2 = st2.characterInitialScreens
		if not ids2 or #ids2 == 0 then
			return
		end

		for _, id in ipairs(ids2) do
			if st2.screens[id] then
				Runtime.open(id)
			else
				warn(("[ui_runtime] ✗ Character initial screen '%s' not registered"):format(id))
			end
		end
	end)
end

function Runtime._handleCharacterRemoving()
	_store:setState(function(s)
		for id, def in pairs(s.screens) do
			if def.meta.closeOnCharacterRemoving and s.active[id] then
				s.active[id] = nil
			end
		end
	end)
end

function Runtime.unmount()
	if _inputConn then
		_inputConn:Disconnect()
		_inputConn = nil
	end

	if _rootHandle then
		_rootHandle:unmount()
		_rootHandle = nil
	end

	if _screenGui then
		_screenGui:Destroy()
		_screenGui = nil
	end
	_rootFrame = nil
	_clearKeyIndex()

	_store:setState(function(s)
		s.mounted = false
		s.screens = {}
		s.active = {}
		s.initialScreens = {}
		s.characterInitialScreens = {}
		s.lifecycle.isCharacterReady = false
		s.lifecycle.character = nil
		s.lifecycle.humanoid = nil
	end)
end

return Runtime
