--- Enhanced assertion library for witch-line tests.
--- Extends the base helper with additional assertion patterns.

local M = {}

--- Base counters (shared state across all helpers).
M.passed = 0
M.failed = 0
M.errors = {}

function M.eq(a, b, msg)
    if a ~= b then
        M.failed = M.failed + 1
        local err = string.format("  expected %s, got %s", vim.inspect(b), vim.inspect(a))
        if msg then err = err .. " -- " .. msg end
        M.errors[#M.errors + 1] = err
        return
    end
    M.passed = M.passed + 1
end

function M.neq(a, b, msg)
    if a == b then
        M.failed = M.failed + 1
        local err = string.format("  expected %s to differ from %s", vim.inspect(a), vim.inspect(b))
        if msg then err = err .. " -- " .. msg end
        M.errors[#M.errors + 1] = err
        return
    end
    M.passed = M.passed + 1
end

function M.is_true(v, msg)
    M.eq(v, true, msg)
end

function M.is_false(v, msg)
    M.eq(v, false, msg)
end

function M.is_nil(v, msg)
    if v ~= nil then
        M.failed = M.failed + 1
        local err = string.format("  expected nil, got %s", vim.inspect(v))
        if msg then err = err .. " -- " .. msg end
        M.errors[#M.errors + 1] = err
        return
    end
    M.passed = M.passed + 1
end

function M.not_nil(v, msg)
    if v == nil then
        M.failed = M.failed + 1
        local err = "  expected non-nil, got nil"
        if msg then err = err .. " -- " .. msg end
        M.errors[#M.errors + 1] = err
        return
    end
    M.passed = M.passed + 1
end

function M.matches(str, pattern, msg)
    if type(str) ~= "string" or not str:match(pattern) then
        M.failed = M.failed + 1
        local err = string.format("  %s does not match %s", vim.inspect(str), pattern)
        if msg then err = err .. " -- " .. msg end
        M.errors[#M.errors + 1] = err
        return
    end
    M.passed = M.passed + 1
end

function M.is_type(v, expected_type, msg)
    if type(v) ~= expected_type then
        M.failed = M.failed + 1
        local err = string.format("  expected type %s, got %s (%s)", expected_type, type(v), vim.inspect(v))
        if msg then err = err .. " -- " .. msg end
        M.errors[#M.errors + 1] = err
        return
    end
    M.passed = M.passed + 1
end

function M.has_field(t, field, msg)
    if type(t) ~= "table" then
        M.failed = M.failed + 1
        M.errors[#M.errors + 1] = "  has_field: first arg is not a table" .. (msg and " -- " .. msg or "")
        return
    end
    if rawget(t, field) == nil and (getmetatable(t) or {}).__index == nil then
        M.failed = M.failed + 1
        local err = string.format("  expected table to have field %s", vim.inspect(field))
        if msg then err = err .. " -- " .. msg end
        M.errors[#M.errors + 1] = err
        return
    end
    M.passed = M.passed + 1
end

function M.table_eq(actual, expected, msg)
    if type(actual) ~= "table" or type(expected) ~= "table" then
        M.eq(actual, expected, msg)
        return
    end
    for k, v in pairs(expected) do
        M.eq(actual[k], v, (msg and msg .. "." or "") .. tostring(k))
    end
    for k in pairs(actual) do
        if expected[k] == nil then
            M.failed = M.failed + 1
            M.errors[#M.errors + 1] = string.format("  unexpected key %s in result", vim.inspect(k))
        end
    end
end

function M.table_has_entries(t, count, msg)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    M.eq(n, count, msg)
end

function M.no_error(fn, msg)
    local ok, err = pcall(fn)
    if not ok then
        M.failed = M.failed + 1
        local e = string.format("  expected no error, got: %s", tostring(err))
        if msg then e = e .. " -- " .. msg end
        M.errors[#M.errors + 1] = e
        return
    end
    M.passed = M.passed + 1
end

function M.expect_error(fn, pattern, msg)
    local ok, err = pcall(fn)
    if ok then
        M.failed = M.failed + 1
        M.errors[#M.errors + 1] = "  expected error, but function succeeded" .. (msg and " -- " .. msg or "")
        return
    end
    if pattern and not tostring(err):match(pattern) then
        M.failed = M.failed + 1
        local e = string.format("  error %q does not match pattern %q", tostring(err), pattern)
        if msg then e = e .. " -- " .. msg end
        M.errors[#M.errors + 1] = e
        return
    end
    M.passed = M.passed + 1
end

---@return boolean
function M.summary()
    local total = M.passed + M.failed
    print(string.format("\n%d/%d passed, %d failed", M.passed, total, M.failed))
    if #M.errors > 0 then
        print("Errors:")
        for _, err in ipairs(M.errors) do
            print(err)
        end
    end
    return M.failed == 0
end

function M.reset()
    M.passed = 0
    M.failed = 0
    M.errors = {}
end

return M
