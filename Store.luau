--!strict

export type ScreenBinds = {
	toggleKey: Enum.KeyCode?,
	openKey: Enum.KeyCode?,
	closeKey: Enum.KeyCode?,
	allowWhenTextBoxFocused: boolean?,
	requireCharacterReady: boolean?,
}

export type ScreenMeta = {
	lifetime: "player" | "character"?,
	displayOrder: number?,
	exclusiveGroup: string?,
	closeOnCharacterRemoving: boolean?,
	binds: ScreenBinds?,
}

export type ScreenDef = {
	id: string,
	component: any,
	meta: ScreenMeta,
}

export type LifecycleState = {
	isCharacterReady: boolean,
	character: Instance?,
	humanoid: Instance?,
}

export type State = {
	mounted: boolean,
	config: {
		screenGuiName: string,
		ignoreGuiInset: boolean,
		displayOrder: number,
	},

	screens: { [string]: ScreenDef },
	active: { [string]: boolean },
	initialScreens: { string },

	lifecycle: LifecycleState,
}

local Store = {}
Store.__index = Store

local function shallowCopy<T>(t: T): T
	local copy = {}
	for k, v in pairs(t :: any) do
		copy[k] = v
	end
	return copy :: T
end

function Store.new()
	local self = setmetatable({}, Store)
	self._subs = {} :: { [any]: (State) -> () }

	self._state = {
		mounted = false,
		config = {
			screenGuiName = "AppUI",
			ignoreGuiInset = true,
			displayOrder = 0,
		},

		screens = {},
		active = {},
		initialScreens = {},

		lifecycle = {
			isCharacterReady = false,
			character = nil,
			humanoid = nil,
		},
	} :: State

	return self
end

function Store:getState(): State
	return self._state
end

function Store:subscribe(cb: (State) -> ())
	self._subs[cb] = cb
	return function()
		self._subs[cb] = nil
	end
end

function Store:_emit()
	local s = self._state
	for _, cb in pairs(self._subs) do
		cb(s)
	end
end

function Store:setState(mutator: (State) -> ())
	mutator(self._state)
	-- Create a new reference so React detects the change
	self._state = shallowCopy(self._state)
	self:_emit()
end

return Store
