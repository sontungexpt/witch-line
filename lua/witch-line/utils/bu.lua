
-- --- Encode references in a table recursively
-- --- @param value any The value to encode
-- --- @return string|nil The encoded value or nil if the value is not encodable
-- local function deep_encode_refs(value)
-- 	local encoded_api_key = ("\0\f\t" .. math.random() .. uv.hrtime())

-- 	local function handle()
-- 		local value_type = type(value)
-- 		local str_hash = encoded_api_key .. tostring(value)

-- 		if value_type == "function" then
-- 			G_REFS[str_hash] = string.dump(value)
-- 			return str_hash
-- 		elseif value_type == "string" or value_type == "number" or value_type == "boolean" then
-- 			return value
-- 		elseif
-- 			value_type == "thread"
-- 			or value_type == "userdata"
-- 			or value_type == "nil"
-- 			or value == G_REFS
-- 			or value == Struct
-- 		then
-- 			return nil
-- 		end

-- 		-- table already managed
-- 		if G_REFS[str_hash] then
-- 			return value
-- 		end
-- 		G_REFS[str_hash] = value

-- 		for k, v in pairs(value) do
-- 			v = deep_encode_refs(v)
-- 			value[k] = v

-- 			local nk = deep_encode_refs(k)
-- 			value[k] = nil
-- 			if nk then
-- 				value[nk] = v
-- 			end
-- 		end

-- 		local metatable = getmetatable(value)
-- 		if metatable then
-- 			value[ENCODED_META_KEY] = deep_encode_refs(metatable)
-- 		end

-- 		return str_hash
-- 	end
-- 	handle()
-- end

-- --- Decode references in a table recursively
-- --- @param value any The value to decode
-- --- @param seen table|nil A table to keep track of already seen values to avoid infinite loops
-- --- @return any The decoded value
-- local function deep_decode_refs(value, seen)
-- 	if type(value) ~= "table" then
-- 		return value
-- 	end
-- 	seen = seen or {}
-- 	if seen[value] then
-- 		return value
-- 	end
-- 	seen[value] = true

-- 	for k, v in pairs(value) do
-- 		if type(v) == "string" then
-- 			v = G_REFS[v]
-- 			if type(v) == "table" then
-- 				v = deep_decode_refs(v, seen)
-- 			elseif v then
-- 				-- func
-- 				v = loadstring(v)
-- 			end
-- 			value[k] = v
-- 		end
-- 		if type(k) == "string" then
-- 			local old_k = G_REFS[k]
-- 			if type(old_k) == "table" then
-- 				old_k = deep_decode_refs(old_k, seen)
-- 			elseif old_k then
-- 				-- func
-- 				---@diagnostic disable-next-line: cast-local-type
-- 				old_k = loadstring(old_k)
-- 			end
-- 			if old_k then
-- 				value[old_k] = v
-- 				value[k] = nil
-- 			end
-- 		end
-- 	end

-- 	local meta_ref = value[ENCODED_META_KEY]
-- 	if not meta_ref or type(meta_ref) ~= "string" then
-- 		return value
-- 	end

-- 	local metatable = G_REFS[meta_ref]
-- 	if type(metatable) == "table" then
-- 		setmetatable(value, metatable)
-- 	end
-- 	value[ENCODED_META_KEY] = nil

-- 	return value
-- end
