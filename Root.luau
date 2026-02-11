--!strict

local function useStore(React, store)
	-- Use a counter to force re-renders when store emits
	local _, forceUpdate = React.useReducer(function(count)
		return count + 1
	end, 0)

	React.useEffect(function()
		return store:subscribe(function(_newState)
			forceUpdate()
		end)
	end, { store })

	return store:getState()
end

local function Root(props)
	local React = props.React
	local AppShell = props.app
	return React.createElement(AppShell, {})
end

local function RootView(props)
	local React = props.React
	local store = props.store
	local state = useStore(React, store)

	local activeList = {}
	for screenId in pairs(state.active) do
		local def = state.screens[screenId]
		if def then
			table.insert(activeList, def)
		end
	end

	table.sort(activeList, function(a, b)
		local ao = a.meta.displayOrder or 0
		local bo = b.meta.displayOrder or 0
		if ao == bo then
			return a.id < b.id
		end
		return ao < bo
	end)

	local children = {}

	for _, def in ipairs(activeList) do
		local meta = def.meta
		local lifetime = meta.lifetime or "player"

		-- Only character-lifetime screens need character ready check
		if lifetime == "character" and not state.lifecycle.isCharacterReady then
			continue
		end

		local order = meta.displayOrder or 0

		children[def.id] = React.createElement("Frame", {
			Name = "Screen_" .. def.id,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			ZIndex = order,
		}, {
			Screen = React.createElement(def.component, {
				__screenId = def.id,
			}),
		})
	end

	return React.createElement("Frame", {
		Name = "RuntimeRoot",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
	}, children)
end

return {
	Root = Root,
	RootView = RootView,
}
