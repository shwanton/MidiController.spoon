-- Unit tests for MidiController core functionality
-- Run with: lua tests/init_test.lua

-- ============================================================================
-- Test Framework (minimal)
-- ============================================================================

local tests_run = 0
local tests_passed = 0
local tests_failed = 0

local function test(name, fn)
    tests_run = tests_run + 1
    local ok, err = pcall(fn)
    if ok then
        tests_passed = tests_passed + 1
        print("  ✓ " .. name)
    else
        tests_failed = tests_failed + 1
        print("  ✗ " .. name)
        print("    " .. tostring(err))
    end
end

local function assertEqual(actual, expected, msg)
    if actual ~= expected then
        error((msg or "assertEqual") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTableEqual(actual, expected, msg)
    if type(actual) ~= "table" or type(expected) ~= "table" then
        error((msg or "assertTableEqual") .. ": both values must be tables")
    end
    if #actual ~= #expected then
        error((msg or "assertTableEqual") .. ": length mismatch, expected " .. #expected .. ", got " .. #actual)
    end
    for i, v in ipairs(expected) do
        if actual[i] ~= v then
            error((msg or "assertTableEqual") .. ": mismatch at index " .. i .. ", expected " .. tostring(v) .. ", got " .. tostring(actual[i]))
        end
    end
end

local function assertTrue(value, msg)
    if not value then
        error((msg or "assertTrue") .. ": expected true, got " .. tostring(value))
    end
end

local function assertFalse(value, msg)
    if value then
        error((msg or "assertFalse") .. ": expected false, got " .. tostring(value))
    end
end

local function assertNil(value, msg)
    if value ~= nil then
        error((msg or "assertNil") .. ": expected nil, got " .. tostring(value))
    end
end

local function assertNotNil(value, msg)
    if value == nil then
        error((msg or "assertNotNil") .. ": expected non-nil value")
    end
end

-- ============================================================================
-- Mocks for Hammerspoon globals
-- ============================================================================

-- Mock hs.logger
local mockLogMessages = {}
hs = {
    logger = {
        new = function(name)
            return {
                d = function(...) table.insert(mockLogMessages, {level = "debug", args = {...}}) end,
                i = function(...) table.insert(mockLogMessages, {level = "info", args = {...}}) end,
                w = function(...) table.insert(mockLogMessages, {level = "warn", args = {...}}) end,
                e = function(...) table.insert(mockLogMessages, {level = "error", args = {...}}) end,
                setLogLevel = function() end,
            }
        end
    },
    spoons = {
        resourcePath = function(subpath)
            return "./" .. subpath
        end
    },
    inspect = function(t)
        if type(t) ~= "table" then return tostring(t) end
        local parts = {}
        for k, v in pairs(t) do
            table.insert(parts, tostring(k) .. "=" .. tostring(v))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end,
    midi = {
        devices = function() return {} end,
        new = function(name)
            return {
                callback = function(self, fn) end,
                sendCommand = function(self, cmd, data) end,
            }
        end
    },
    timer = {
        doAfter = function(delay, fn)
            return { stop = function() end }
        end
    },
}

-- Helper to clear mock state
local function clearMocks()
    mockLogMessages = {}
end

-- ============================================================================
-- Load the module
-- ============================================================================

package.path = package.path .. ";./?.lua"
local MidiController = dofile("init.lua")

-- ============================================================================
-- Tests: Utility Functions
-- ============================================================================

print("\n=== Utils: resolveChannels ===")

test("resolveChannels with array returns same array", function()
    local result = MidiController.utils.resolveChannels({1, 2, 3})
    assertTableEqual(result, {1, 2, 3})
end)

test("resolveChannels with single-element array", function()
    local result = MidiController.utils.resolveChannels({5})
    assertTableEqual(result, {5})
end)

test("resolveChannels with 'all' returns all 16 channels", function()
    local result = MidiController.utils.resolveChannels("all")
    assertEqual(#result, 16)
    assertEqual(result[1], 1)
    assertEqual(result[16], 16)
end)

test("resolveChannels with nil returns default {1}", function()
    local result = MidiController.utils.resolveChannels(nil)
    assertTableEqual(result, {1})
end)

test("resolveChannels with invalid type returns default {1}", function()
    local result = MidiController.utils.resolveChannels("invalid")
    assertTableEqual(result, {1})
end)

print("\n=== Utils: channelAllowed ===")

test("channelAllowed returns true for channel in list", function()
    assertTrue(MidiController.utils.channelAllowed(2, {1, 2, 3}))
end)

test("channelAllowed returns false for channel not in list", function()
    assertFalse(MidiController.utils.channelAllowed(5, {1, 2, 3}))
end)

test("channelAllowed returns true for single channel match", function()
    assertTrue(MidiController.utils.channelAllowed(1, {1}))
end)

test("channelAllowed returns false for empty list", function()
    assertFalse(MidiController.utils.channelAllowed(1, {}))
end)

print("\n=== Utils: percentageToMidi ===")

test("percentageToMidi converts 0% to 0", function()
    assertEqual(MidiController.utils.percentageToMidi(0), 0)
end)

test("percentageToMidi converts 100% to 127", function()
    assertEqual(MidiController.utils.percentageToMidi(100), 127)
end)

test("percentageToMidi converts 50% to 63", function()
    assertEqual(MidiController.utils.percentageToMidi(50), 63)
end)

print("\n=== Utils: midiToPercentage ===")

test("midiToPercentage converts 0 to 0%", function()
    assertEqual(MidiController.utils.midiToPercentage(0), 0)
end)

test("midiToPercentage converts 127 to 100%", function()
    assertEqual(MidiController.utils.midiToPercentage(127), 100)
end)

test("midiToPercentage converts 63 to 49%", function()
    -- 63/127 * 100 = 49.6 -> floor = 49
    assertEqual(MidiController.utils.midiToPercentage(63), 49)
end)

-- ============================================================================
-- Tests: addControllerConfig
-- ============================================================================

print("\n=== addControllerConfig ===")

test("addControllerConfig requires name", function()
    clearMocks()
    MidiController:init()
    MidiController:addControllerConfig({ channels = {1} })
    assertNil(MidiController._config)
end)

test("addControllerConfig requires channels", function()
    clearMocks()
    MidiController:init()
    MidiController:addControllerConfig({ name = "Test Device" })
    assertNil(MidiController._config)
end)

test("addControllerConfig stores valid config", function()
    clearMocks()
    MidiController:init()
    local config = {
        name = "Test Device",
        channels = {1, 2},
        ccHandlers = {}
    }
    MidiController:addControllerConfig(config)
    assertNotNil(MidiController._config)
    assertEqual(MidiController._config.name, "Test Device")
end)

test("addControllerConfig resolves channels to _channels", function()
    clearMocks()
    MidiController:init()
    local config = {
        name = "Test Device",
        channels = {3, 4, 5},
        ccHandlers = {}
    }
    MidiController:addControllerConfig(config)
    assertTableEqual(MidiController._config._channels, {3, 4, 5})
end)

test("addControllerConfig resolves 'all' channels", function()
    clearMocks()
    MidiController:init()
    local config = {
        name = "Test Device",
        channels = "all",
        ccHandlers = {}
    }
    MidiController:addControllerConfig(config)
    assertEqual(#MidiController._config._channels, 16)
end)

-- ============================================================================
-- Tests: _handleControlChange
-- ============================================================================

print("\n=== _handleControlChange ===")

test("_handleControlChange calls handler for matching CC and channel", function()
    clearMocks()
    MidiController:init()

    local handlerCalled = false
    local receivedMessage = nil

    local config = {
        name = "Test Device",
        channels = {1},
        _channels = {1},
        ccHandlers = {
            [31] = function(self, message)
                handlerCalled = true
                receivedMessage = message
            end
        }
    }

    local message = { channel = 1, ccNumber = 31, ccValue = 100 }
    MidiController:_handleControlChange(message, config)

    assertTrue(handlerCalled, "Handler should be called")
    assertEqual(receivedMessage.ccValue, 100)
end)

test("_handleControlChange ignores non-matching CC number", function()
    clearMocks()
    MidiController:init()

    local handlerCalled = false

    local config = {
        name = "Test Device",
        channels = {1},
        _channels = {1},
        ccHandlers = {
            [31] = function(self, message)
                handlerCalled = true
            end
        }
    }

    local message = { channel = 1, ccNumber = 99, ccValue = 100 }
    MidiController:_handleControlChange(message, config)

    assertFalse(handlerCalled, "Handler should not be called for wrong CC")
end)

test("_handleControlChange ignores non-matching channel", function()
    clearMocks()
    MidiController:init()

    local handlerCalled = false

    local config = {
        name = "Test Device",
        channels = {1},
        _channels = {1},
        ccHandlers = {
            [31] = function(self, message)
                handlerCalled = true
            end
        }
    }

    local message = { channel = 2, ccNumber = 31, ccValue = 100 }
    MidiController:_handleControlChange(message, config)

    assertFalse(handlerCalled, "Handler should not be called for wrong channel")
end)

test("_handleControlChange respects per-handler channel override", function()
    clearMocks()
    MidiController:init()

    local handlerCalled = false

    local config = {
        name = "Test Device",
        channels = {1, 2, 3},
        _channels = {1, 2, 3},
        ccHandlers = {
            [31] = {
                handler = function(self, message)
                    handlerCalled = true
                end,
                channels = {2}  -- Only listen on channel 2
            }
        }
    }

    -- Channel 1 should be ignored (not in handler's channels)
    local message1 = { channel = 1, ccNumber = 31, ccValue = 100 }
    MidiController:_handleControlChange(message1, config)
    assertFalse(handlerCalled, "Handler should not be called for channel 1")

    -- Channel 2 should trigger handler
    local message2 = { channel = 2, ccNumber = 31, ccValue = 100 }
    MidiController:_handleControlChange(message2, config)
    assertTrue(handlerCalled, "Handler should be called for channel 2")
end)

test("_handleControlChange uses controller channels when handler has no override", function()
    clearMocks()
    MidiController:init()

    local callCount = 0

    local config = {
        name = "Test Device",
        channels = {1, 2},
        _channels = {1, 2},
        ccHandlers = {
            [31] = function(self, message)
                callCount = callCount + 1
            end
        }
    }

    -- Both channels should work
    MidiController:_handleControlChange({ channel = 1, ccNumber = 31, ccValue = 100 }, config)
    MidiController:_handleControlChange({ channel = 2, ccNumber = 31, ccValue = 100 }, config)
    MidiController:_handleControlChange({ channel = 3, ccNumber = 31, ccValue = 100 }, config)

    assertEqual(callCount, 2, "Handler should be called twice (channels 1 and 2)")
end)

-- ============================================================================
-- Summary
-- ============================================================================

print("\n" .. string.rep("=", 50))
print(string.format("Tests: %d passed, %d failed, %d total", tests_passed, tests_failed, tests_run))
print(string.rep("=", 50))

if tests_failed > 0 then
    os.exit(1)
end
