-- Tiny assert helper shared by test_*.lua. Load with: local T = dofile("test/helpers.lua")
local T = { passed = 0, failed = 0 }

function T.check(name, cond)
    if cond then
        T.passed = T.passed + 1
    else
        T.failed = T.failed + 1
        print("FAIL: " .. name)
    end
end

function T.eq(name, actual, expected)
    local ok = actual == expected
    if not ok then name = name .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")" end
    T.check(name, ok)
end

function T.near(name, actual, expected, eps)
    eps = eps or 1e-6
    local ok = type(actual) == "number" and math.abs(actual - expected) <= eps
    if not ok then name = name .. " (expected ~" .. tostring(expected) .. ", got " .. tostring(actual) .. ")" end
    T.check(name, ok)
end

function T.finish()
    print(T.passed .. " passed, " .. T.failed .. " failed")
    if T.failed > 0 then error(T.failed .. " test(s) failed", 0) end
end

function T.runtime()
    if type(jit) == "table" and jit.version then return jit.version end
    return _VERSION
end

return T
