--!strict
local RunService = game:GetService("RunService")

export type UseAttributeOptions = {
	fireOnConnect: boolean?,
	throttleHz: number?,
}

return function(React, serviceLocator, path: string, options: UseAttributeOptions?)
	options = options or {}
	local fireOnConnect = if options.fireOnConnect == nil then true else options.fireOnConnect
	local throttleHz = options.throttleHz

	local listener = serviceLocator:Get("AttributeListenerService")
	if not listener then
		error("[ui_runtime.useAttribute] AttributeListenerService not found")
	end

	local value, setValue = React.useState(nil)

	React.useEffect(function()
		local alive = true
		local latest = nil
		local dirty = false

		local function commit(v)
			if not alive then
				return
			end
			setValue(v)
		end

		local conn = listener:Connect(path, function(newValue, _oldValue)
			if not alive then
				return
			end
			if throttleHz and throttleHz > 0 then
				latest = newValue
				dirty = true
			else
				commit(newValue)
			end
		end, fireOnConnect)

		local hbConn = nil
		if throttleHz and throttleHz > 0 then
			local interval = 1 / throttleHz
			local acc = 0

			hbConn = RunService.Heartbeat:Connect(function(dt)
				acc += dt
				if acc >= interval then
					acc = 0
					if dirty then
						dirty = false
						commit(latest)
					end
				end
			end)
		end

		return function()
			alive = false
			conn:Disconnect()
			if hbConn then
				hbConn:Disconnect()
			end
		end
	end, { path, fireOnConnect, throttleHz })

	return value
end
