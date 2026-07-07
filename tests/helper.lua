local M = {}

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
