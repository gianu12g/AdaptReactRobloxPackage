--!strict
return function(React, store)
	local state, setState = React.useState(store:getState().lifecycle)

	React.useEffect(function()
		return store:subscribe(function(s)
			setState(s.lifecycle)
		end)
	end, { store })

	return state
end
