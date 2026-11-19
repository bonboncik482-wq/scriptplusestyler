-- Elevate thread identity so we can require game modules from a LocalScript
pcall(function() setthreadidentity(2) end)

if _G.MockTradeRunning then
    _G.MockTradeRunning = false
    task.wait(0.1)
end
_G.MockTradeRunning = true
_G._guiLocked = false

-- Destroy old GUI (Players not yet defined here — done below after service init)

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Destroy old GUI instance if re-executing
do local _oldGui = Players.LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("MockTradeControl")
if _oldGui then _oldGui:Destroy() end

end local CONFIG = {
    PARTNER_NAME               = "singboo1",
    PARTNER_USER_ID            = 1527418844,
    AUTO_ACCEPT_DELAY          = 0.55,
    AUTO_CONFIRM_DELAY         = 0.35,
    SPECTATOR_COUNT            = 4,
    NEGOTIATION_LOCK           = 5,
    CONFIRMATION_LOCK_PER_ITEM = 3,
    REACTIONS_PER_SECOND       = 2,
    REMOVE_SENT_PETS           = true,   -- spawned pets you send in a mock trade are removed from your backpack
    REMOVE_REAL_PETS           = true,   -- REAL pets you send in a mock trade are removed; OFF = they stay but drop to the very bottom of your backpack
    RECEIVE_PETS               = true,
    PARTNER_TAG                = "",  -- force a tag for mock partner: "founder" / "developer" / "staff" / "influencer" / "" = use real rank
    SELF_BADGE_TAG             = "founder",  -- founder / developer / staff / influencer / ""
    -- Fake partner backpack (what you can "Suggest" from) -----------------------------
    SUPPRESS_PET_DISCOVERY     = true,  -- never show the "New Pet Discovered" popup (any pet). Also: _G._setPetDiscoverySuppress(bool)
    RICH_COUNT_EQUIPPED        = true,  -- Rich Board also counts pets players currently have equipped
    BACKPACK_FROM_PROFILE      = false, -- true = build it from the partner's profile collection instead
    BACKPACK_VARIETY           = true,  -- every generated player gets a random type (whale / neon farmer / newbie / trader ...) that scales the counts below
    BACKPACK_TOTAL_MIN         = 34,    -- total pets in the backpack (min / max)
    BACKPACK_TOTAL_MAX         = 102,
    BACKPACK_HIGH_CHANCE       = 0.75,  -- chance a player has any high tier at all (frost dragon, giraffe, owl, bat dragon ...)
    BACKPACK_HIGH_MIN          = 1,     -- high tiers when they do, always FR or NFR (min / max)
    BACKPACK_HIGH_MAX          = 1,
    -- Showpiece roll (replaces the old exotic / high / mid counts): each player rolls ONE category, 10% roll a 2nd different one. Max 2 total.
    BACKPACK_SHOW_MEGA         = 0.08,  -- chance the roll is a 0.8+ AMVGG mega neon (always MFR)
    BACKPACK_SHOW_HIGH         = 0.20,  -- chance the roll is a high tier (FR / NFR)
    BACKPACK_SHOW_MID          = 0.62,  -- chance the roll is a mid tier (remaining 10% = no showpiece at all)
    BACKPACK_SHOW_DOUBLE       = 0.06,  -- chance of a 2nd showpiece (different category)
    BACKPACK_SHOW_COMBO        = 0.25,  -- when a 2nd showpiece rolls: chance a mega + high tier pairing is allowed (otherwise the 2nd is a mid)
    BACKPACK_MEGA_MIN_VALUE    = 0.8,   -- AMVGG MFR value for the big mega pool
    BACKPACK_SMALL_MEGA_CHANCE = 0.70,  -- when the roll is "mid": chance it's a small mega instead of a regular mid
    BACKPACK_SMALL_MEGA_MIN    = 0.05,  -- small mega AMVGG MFR range (starts at 0.05)
    BACKPACK_SMALL_MEGA_MAX    = 0.3,
    BACKPACK_EXOTIC_MIN        = 0,     -- MEGA exotics, always MFR (min / max)
    BACKPACK_EXOTIC_MAX        = 3,
    BACKPACK_MID_MIN           = 0,     -- mid tiers (min / max)
    BACKPACK_MID_MAX           = 5,
    BACKPACK_NEON_MIN          = 1,     -- neon showcase pets (alicorn, bush elephant, candicorn ...) always neon (min / max)
    BACKPACK_NEON_MAX          = 6,
    BACKPACK_RANDOM_MIN        = 8,      -- wildcard pets picked from the WHOLE pet database (min / max)
    BACKPACK_RANDOM_MAX        = 16,
    BACKPACK_RANDOM_MAX_VALUE  = 0.1,   -- wildcards must be worth less than this (regular AMVGG value)
    BACKPACK_MIN_VALUABLE      = 0.2,   -- every generated player holds at least one pet worth MORE than this on AMVGG (regular, neon or mega variant)
    BACKPACK_CHEAP_MEGA_MIN    = 0,     -- extra cheap mega neons sprinkled on top of the showpiece roll (min / max)
    BACKPACK_CHEAP_MEGA_MAX    = 2,
    -- everything left up to the total is tiny pets (king bee, ant, goldfish ...), duplicates allowed
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")

-- Safe pcall wrapper that logs errors to console
local function safeCall(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[MockTrade] " .. tostring(err)) end
end

-- UI factory: collapses Instance.new + property assignments into one call.
-- Parent is always applied last (Roblox best practice — avoids reparent churn).
local function mk(class, props)
    local o = Instance.new(class)
    if props then
        local parent = props.Parent
        props.Parent = nil
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
    end
    return o
end

local Fsys        = require(ReplicatedStorage:WaitForChild("Fsys"))
local load              = Fsys.load
local UIManager         = load("UIManager")
local ClientData        = load("ClientData")
local TableUtil   = load("TableUtil")
local InventoryDB = load("InventoryDB")
do local SharedConstants = load("SharedConstants")
end local KindDB         = load("KindDB")
local RouterClient_  = load("RouterClient")
local DownloadClient = load("DownloadClient")
do local PetRigs        = load("new:PetRigs")
end local IDB            = load("InventoryDB")
local AnimMgr        = load("AnimationManager")
local AilmentsClient = load("new:AilmentsClient")
local AilmentsDB     = load("new:AilmentsDB")

if UIManager.wait_for_initialization then
    UIManager:wait_for_initialization()
else
    task.wait(2)
end

local TradeApp        = UIManager.apps.TradeApp
local BackpackApp     = UIManager.apps.BackpackApp
local TradeHistoryApp = UIManager.apps.TradeHistoryApp

-- ════════════════════════════════════════════════════════════════════════
--  Pet Discovery suppressor — stops the "New Pet Discovered" popup (client side only) for SPAWNED pets only;
--  pets that are not in your spawned backpack still show it.
--  Three layers, any one is enough:
--    A. GUI lock       PlayerGui.PetDiscoveryApp stays disabled / hidden
--    B. Event sink     game connections on discovery RemoteEvents are disabled (needs getconnections)
--    C. Module stub    popup trigger functions on PetDiscoveryApp / PetDiscoveryAppClient become no-ops
--  Own function scope + pcall, so it costs no main-chunk locals and can never abort the script.
-- ════════════════════════════════════════════════════════════════════════
do
local function _petDiscoverySuppressor()
    _G._pdGen = (_G._pdGen or 0) + 1
    local GEN = _G._pdGen
    if _G._pdConns then
        for _, c in ipairs(_G._pdConns) do pcall(function() c:Disconnect() end) end
    end
    local conns = {}
    _G._pdConns = conns
    local function track(c) conns[#conns + 1] = c end

    local enabled = CONFIG.SUPPRESS_PET_DISCOVERY ~= false
    _G._pdLastSkipped, _G._pdLastShown = nil, nil

    -- ── WHICH pets get suppressed ───────────────────────────────────────────
    -- Only pets that are in your SPAWNED backpack (Spawn All Variants / High Tiers / Smalls, whatever you actually
    -- spawned). Any other brand new pet (e.g. one you receive in a trade) still gets its normal "New Pet Discovered!".
    local blockUntil, allowUntil = 0, 0
    local function recentSpawn() return _G._lastSpawnTick and (tick() - _G._lastSpawnTick) < 10 end
    local function extractKind(...)
        local petDb = (InventoryDB and InventoryDB.pets) or {}
        local function fromTable(t, depth)
            if type(t) ~= "table" or depth > 2 then return nil end
            for _, key in ipairs({ "kind", "pet_kind", "id", "pet_id", "item_kind", "item_id", "pet" }) do
                local v = t[key]
                if type(v) == "string" and petDb[v] then return v end
            end
            for _, key in ipairs({ "item", "pet", "data", "properties" }) do
                local k = fromTable(t[key], depth + 1)
                if k then return k end
            end
            return nil
        end
        for i = 1, select("#", ...) do
            local a = select(i, ...)
            if type(a) == "string" and petDb[a] then return a end
            local k = fromTable(a, 0)
            if k then return k end
        end
        return nil
    end
    -- every discovery trigger is suppressed while the toggle is ON (no popup at all)
    local function shouldSuppress(...)
        if not enabled then return false end
        _G._pdLastSkipped = extractKind(...) or "?"
        return true
    end
    local function guiShouldHide()
        return enabled
    end
    _G._pdShouldSuppress = shouldSuppress
    _G._setPetDiscoverySuppress = function(on) enabled = (on ~= false) end

    -- Layer A: GUI lock (only while the popup belongs to a spawned pet) -----
    local function lockInstance(inst)
        if inst:IsA("ScreenGui") then
            if guiShouldHide() then inst.Enabled = false end
            track(inst:GetPropertyChangedSignal("Enabled"):Connect(function()
                if inst.Enabled and guiShouldHide() then inst.Enabled = false end
            end))
        elseif inst:IsA("Frame") or inst:IsA("ScrollingFrame") or inst:IsA("CanvasGroup") then
            if guiShouldHide() then inst.Visible = false end
            track(inst:GetPropertyChangedSignal("Visible"):Connect(function()
                if inst.Visible and guiShouldHide() then inst.Visible = false end
            end))
        end
    end
    local function suppressGui(gui)
        lockInstance(gui)
        for _, d in ipairs(gui:GetDescendants()) do lockInstance(d) end
        track(gui.DescendantAdded:Connect(lockInstance))
    end
    task.spawn(function()
        local pgui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
        if not pgui or _G._pdGen ~= GEN then return end
        local existing = pgui:FindFirstChild("PetDiscoveryApp")
        if existing then suppressGui(existing) end
        track(pgui.ChildAdded:Connect(function(child)
            if child.Name == "PetDiscoveryApp" then suppressGui(child) end
        end))
    end)

    do   -- turning it back ON also hides a popup that is already open (if it is for a spawned pet)
        local baseSet = _G._setPetDiscoverySuppress
        _G._setPetDiscoverySuppress = function(on)
            baseSet(on)
            if guiShouldHide() then
                pcall(function()
                    local g = Players.LocalPlayer.PlayerGui:FindFirstChild("PetDiscoveryApp")
                    if not g then return end
                    if g:IsA("ScreenGui") then g.Enabled = false end
                    for _, d in ipairs(g:GetDescendants()) do
                        if d:IsA("Frame") or d:IsA("ScrollingFrame") or d:IsA("CanvasGroup") then d.Visible = false end
                    end
                end)
            end
        end
    end

    -- Layer B: server -> client discovery events ----------------------------
    -- The game's own handlers are taken over: skipped while the toggle is ON, run normally while it is OFF.
    local EVENT_NAMES = {
        petdiscovered = true, newpetdiscovered = true, petdiscovery = true, onpetdiscovered = true,
        notifypetdiscovery = true, discoverpet = true, journaldiscovery = true,
    }
    local function sink(re)
        if not getconnections then return end
        local taken = {}
        local function takeOver()
            local ok, list = pcall(getconnections, re.OnClientEvent)
            if ok and type(list) == "table" then
                for _, c in ipairs(list) do
                    if not taken[c] then
                        local okF, fn = pcall(function() return c.Function end)
                        if okF and type(fn) == "function" then
                            taken[c] = fn
                            pcall(function() c:Disable() end)
                        elseif not okF or fn == nil then
                            taken[c] = false          -- handler can't be re-run later: keep the old behaviour (swallow)
                            pcall(function() c:Disable() end)
                        end
                    end
                end
            end
        end
        takeOver()
        track(re.OnClientEvent:Connect(function(...)
            if shouldSuppress(...) then return end
            for _, fn in pairs(taken) do
                if fn then task.spawn(fn, ...) end
            end
        end))
        task.delay(2, takeOver)                           -- catch game handlers connected after us
    end
    local function consider(inst)
        if inst:IsA("RemoteEvent") then
            local n = inst.Name:lower()
            if EVENT_NAMES[n] or n:find("petdiscover", 1, true) then sink(inst) end
        end
    end
    pcall(function()
        for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do consider(d) end
        track(game:GetService("ReplicatedStorage").DescendantAdded:Connect(consider))
    end)

    -- Layer C: popup trigger functions on the discovery modules ---------------
    local KEYWORDS = { "discover", "notify", "newpet", "show" }
    local stubbed = setmetatable({}, { __mode = "k" })
    local function stubTable(t)
        if type(t) ~= "table" or stubbed[t] then return end
        stubbed[t] = true
        for k, v in pairs(t) do
            if type(v) == "function" and type(k) == "string" then
                local lk = k:lower()
                for _, kw in ipairs(KEYWORDS) do
                    if lk:find(kw, 1, true) then
                        local orig = v
                        t[k] = function(...)
                            if shouldSuppress(...) then return end
                            return orig(...)
                        end
                        break
                    end
                end
            end
        end
    end
    local function stubModule(mod)
        if type(mod) ~= "table" then return end
        stubTable(mod)
        local mt = getmetatable(mod)
        if type(mt) == "table" and type(mt.__index) == "table" then stubTable(mt.__index) end  -- class methods
    end
    for _, name in ipairs({ "PetDiscoveryApp", "PetDiscoveryAppClient" }) do
        local ok, mod = pcall(load, name)
        if ok then stubModule(mod) end
    end
    pcall(function()
        stubModule(UIManager.apps.PetDiscoveryApp)
        local pp = load("PetProgression")
        if type(pp) == "table" then stubModule(pp.PetDiscoveryAppClient) end   -- that sub-table only
    end)
end
local _pdOk, _pdErr = pcall(_petDiscoverySuppressor)
if not _pdOk then warn("[PetDiscovery] " .. tostring(_pdErr)) end
end




-- ════════════════════════════════════════════════════════════════════════
--  Auto Offer Pets engine. UI is built onto Misc Page 2 via _G._aoBuildControls.
--  Wrapped in an IIFE so its ~20 helpers use their OWN register budget (0 main-chunk cost).
--  realAdd captured here (before our trade hooks) so it's the pristine game function.
-- ════════════════════════════════════════════════════════════════════════
do
local function _aoEngine()
local AO = { enabled=false, running=false, speed=1, min=2, max=2, confirm=false }
local AO_MAX_PETS, AO_MIN_RARITY = 8, 3
local VIM = game:GetService("VirtualInputManager")
local LockTracker = (function() local ok,m = pcall(load,"BackpackLockTracker") return ok and m or nil end)()
local realAdd = TradeApp._add_item_to_my_offer
local function mockOn() return _G._mockState and _G._mockState.active end

local function tradeActive()
    local ok, st = pcall(function() return TradeApp:_get_local_trade_state() end)
    if ok and st and st.current_stage then return true end
    local s2 = TradeApp.local_trade_state
    return s2 ~= nil and s2.current_stage ~= nil
end
local function getMyOffer()
    local ok, offer = pcall(function() return (TradeApp:_get_my_offer()) end)
    if ok and offer then return offer end
    return nil
end
local function getMyOfferCount()
    local o = getMyOffer()
    return (o and o.items) and #o.items or 0
end
local function lockGoing()
    local lc = TradeApp.lock_countdown
    if lc and lc.is_going then
        local ok, going = pcall(function() return lc:is_going() end)
        if ok then return going end
    end
    return false
end
-- Real game lock duration (seconds) for the current stage — the exact time you must
-- wait before the offer unlocks. Negotiation = negotiation_lock_time; confirmation =
-- clamp(confirmation_lock_time_per_item * total_item_count, 5, 15). See TradeApp:_get_lock_time.
local function lockTime()
    local ok, t = pcall(function() return TradeApp:_get_lock_time() end)
    if ok and type(t) == "number" and t > 0 then return t end
    return 15  -- safe upper bound (game clamps the confirmation lock to <= 15s)
end

local function fireConnections(sig)
    if not (sig and getconnections) then return end
    local ok, conns = pcall(getconnections, sig)
    if not (ok and conns) then return end
    for _, c in ipairs(conns) do
        pcall(function() if c.Enable then c:Enable() end end)
        pcall(function() c:Fire() end)
        pcall(function() if c.Function then c.Function() end end)
    end
end
local function realClickAt(x, y)
    pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
    task.wait(0.03)
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true,  game, 1) end)
    task.wait(0.04)
    pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
end
local function fireEvent(b, name)
    local ok, signal = pcall(function() return b[name] end)
    if ok and signal then
        pcall(function() fireConnections(signal) end)
        pcall(function() if firesignal then firesignal(signal) end end)
    end
end
local function pressButton(b)
    if not b then return end
    fireEvent(b, "MouseButton1Down")
    fireEvent(b, "MouseButton1Up")
    fireEvent(b, "MouseButton1Click")
    fireEvent(b, "Activated")
    pcall(function()
        local c = b.AbsolutePosition + b.AbsoluteSize * 0.5
        realClickAt(c.X, c.Y)
    end)
end
local function buttonLabel(b)
    local label = ((b:IsA("TextButton") or b:IsA("TextLabel")) and b.Text) or ""
    if label == "" then
        for _, tl in ipairs(b:GetDescendants()) do
            if tl:IsA("TextLabel") and tl.Visible and tl.Text ~= "" then label = tl.Text; break end
        end
    end
    return label or ""
end
local SCAM_BAD = { "cancel", "decline", "go back", "no thanks", "report" }
local function looksNegative(s)
    s = tostring(s):lower()
    for _, b in ipairs(SCAM_BAD) do if s:find(b, 1, true) then return true end end
    return false
end
local function isOnScreen(o)
    if not o.Visible then return false end
    if o:IsA("GuiObject") and (o.AbsoluteSize.X < 4 or o.AbsoluteSize.Y < 4) then return false end
    local p = o.Parent
    while p and p:IsA("GuiObject") do
        if not p.Visible then return false end
        p = p.Parent
    end
    return true
end
local function tryDismiss(g)
    if not (g:IsA("ScreenGui") and g.Enabled) then return false end
    if g.Name == "MockTradeControl" or g.Name == "_AOFakeCursor" then return false end
    local shown = false
    for _, d in ipairs(g:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton"))
           and (d.Text or ""):lower():find("scam", 1, true) and isOnScreen(d) then
            shown = true; break
        end
    end
    if not shown then return false end
    for _, b in ipairs(g:GetDescendants()) do
        if (b:IsA("TextButton") or b:IsA("ImageButton"))
           and isOnScreen(b) and not looksNegative(buttonLabel(b)) then
            pressButton(b)
            return true
        end
    end
    return false
end
local function dismissScamDialog()
    local roots = {}
    local plg = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if plg then table.insert(roots, plg) end
    pcall(function() if gethui then table.insert(roots, gethui()) end end)
    pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
    for _, root in ipairs(roots) do
        local done = false
        pcall(function()
            for _, g in ipairs(root:GetChildren()) do
                if tryDismiss(g) then done = true; break end
            end
        end)
        if done then return end
    end
end

local function doOffer()
    if AO.running then return end
    AO.running = true
    task.spawn(function()
        local function w(t) task.wait(t / math.max(0.1, AO.speed)) end
        if not tradeActive() then AO.running = false; return end

        local inventory; pcall(function() inventory = ClientData.get("inventory") end)
        local pets = inventory and inventory.pets
        if not pets then AO.running = false; return end

        local offered = {}
        local o = getMyOffer()
        if o and o.items then for _, it in ipairs(o.items) do offered[it.unique] = true end end

        local function rarityOk(p)
            local db = InventoryDB.pets[p.kind]
            local r = (db and db.rarity)
            if r == nil and p.properties then r = p.properties.rarity end
            if r == nil then return true end
            if type(r) == "number" then return r >= AO_MIN_RARITY end
            r = tostring(r):lower()
            return not (r == "common" or r == "uncommon")
        end
        local function tradeable(p)
            local db = InventoryDB.pets[p.kind]
            if db and (db.not_tradeable or db.untradeable or db.not_tradable or db.cannot_trade) then return false end
            if p.not_tradeable or p.untradeable or p.not_tradable then return false end
            local pr = p.properties
            if pr and (pr.not_tradeable or pr.untradeable or pr.cannot_trade) then return false end
            return true
        end
        local function locked(p)
            if LockTracker and LockTracker.is_locked then
                local ok, isL = pcall(LockTracker.is_locked, p)
                if ok then return isL and true or false end
            end
            return p.locked == true or (p.properties and p.properties.locked == true) or false
        end

        local petList = {}
        for uid, p in pairs(pets) do
            if p and p.unique and p.category == "pets"
               and not offered[uid] and rarityOk(p) and tradeable(p) and not locked(p) then
                table.insert(petList, p)
            end
        end
        if #petList == 0 and not AO.confirm then AO.running = false; return end

        for i = #petList, 2, -1 do
            local j = math.random(1, i)
            petList[i], petList[j] = petList[j], petList[i]
        end

        local lo = math.min(AO.min, AO.max)
        local hi = math.max(AO.min, AO.max)
        local freeSlots = math.max(0, AO_MAX_PETS - getMyOfferCount())
        local target = math.min(math.random(lo, hi), freeSlots, #petList)
        if target <= 0 and not AO.confirm then AO.running = false; return end
        local addedCount = 0

        local vp = game.Workspace.CurrentCamera.ViewportSize
        local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")

        local cursorGui, cursor
        local curX, curY = vp.X * 0.82, vp.Y * 0.72
        pcall(function()
            cursorGui = Instance.new("ScreenGui")
            cursorGui.Name = "_AOFakeCursor"
            cursorGui.ResetOnSpawn = false
            cursorGui.DisplayOrder = 999
            cursorGui.IgnoreGuiInset = true
            cursorGui.Parent = playerGui
            cursor = Instance.new("ImageLabel", cursorGui)
            cursor.Size = UDim2.new(0, 72, 0, 72)
            cursor.BackgroundTransparency = 1
            cursor.Image = "rbxasset://textures/Cursors/KeyboardMouse/ArrowCursor.png"
            cursor.ZIndex = 100
            cursor.Position = UDim2.new(0, curX, 0, curY)
        end)

        local function setPos(x, y)
            pcall(function() if cursor then cursor.Position = UDim2.new(0, x, 0, y) end end)
        end
        local function buildFrameMap()
            local map = {}
            pcall(function()
                for uid in pairs(BackpackApp.button_by_unique or {}) do
                    local target = BackpackApp.content:FindFirstChild(uid, true)
                    if target and target:IsA("GuiObject") then map[uid] = target end
                end
            end)
            return map
        end
        local _frameMap = {}
        local _lastHoveredUid = nil
        local _tooltipTargetX, _tooltipTargetY = 0, 0
        local _origTooltipRefresh = nil
        local function getItemDataUnderCursor(cx, cy)
            for uid, frame in pairs(_frameMap) do
                if frame and frame.Visible then
                    local abs = frame.AbsolutePosition
                    local sz  = frame.AbsoluteSize
                    if cx >= abs.X and cx <= abs.X + sz.X and cy >= abs.Y and cy <= abs.Y + sz.Y then
                        local btnData = BackpackApp.button_by_unique[uid]
                        local itemData = btnData and btnData.item_data
                        if itemData then return uid, itemData end
                    end
                end
            end
            return nil, nil
        end
        local function patchTooltipRefresh()
            local innerTooltip = BackpackApp.tooltip and BackpackApp.tooltip.tooltip
            if not innerTooltip then return end
            if _origTooltipRefresh then return end
            _origTooltipRefresh = innerTooltip.refresh
            innerTooltip.refresh = function(self, ...)
                _origTooltipRefresh(self, ...)
                local container = self:get_container()
                if container then
                    container.AnchorPoint = Vector2.new(0, 0)
                    container.Position = UDim2.fromOffset(_tooltipTargetX + 52, _tooltipTargetY + 8)
                end
            end
        end
        local function unpatchTooltipRefresh()
            local innerTooltip = BackpackApp.tooltip and BackpackApp.tooltip.tooltip
            if innerTooltip and _origTooltipRefresh then
                innerTooltip.refresh = _origTooltipRefresh
                _origTooltipRefresh = nil
            end
        end
        local function updateHoverTooltip(cx, cy)
            pcall(function()
                local uid, itemData = getItemDataUnderCursor(cx, cy)
                if uid then
                    _tooltipTargetX, _tooltipTargetY = cx, cy
                    if uid ~= _lastHoveredUid then
                        _lastHoveredUid = uid
                        unpatchTooltipRefresh()
                        BackpackApp.tooltip:_hide_no_refresh()
                        patchTooltipRefresh()
                        BackpackApp.tooltip:_show_item_data(itemData)
                    end
                else
                    if _lastHoveredUid then
                        _lastHoveredUid = nil
                        unpatchTooltipRefresh()
                        BackpackApp.tooltip:hide()
                    end
                end
            end)
        end
        local function glideTo(sx, sy, tx, ty)
            local steps = math.random(10, 16)
            for s = 1, steps do
                local t = s / steps
                t = t < 0.5 and 2*t*t or -1+(4-2*t)*t
                local cx = sx + (tx-sx)*t
                local cy = sy + (ty-sy)*t
                setPos(cx, cy)
                updateHoverTooltip(cx, cy)
                w(0.012 + math.random()*0.008)
            end
            setPos(tx, ty)
            updateHoverTooltip(tx, ty)
        end
        local function extractFrame(d)
            if not d then return nil end
            if typeof(d) == "Instance" and d:IsA("GuiObject") then return d end
            if typeof(d) == "table" then
                for _, key in ipairs({"frame","instance","button","object"}) do
                    local v = d[key]
                    if v and typeof(v) == "Instance" and v:IsA("GuiObject") then return v end
                end
                for _, v in pairs(d) do
                    if typeof(v) == "Instance" and v:IsA("GuiObject") then return v end
                end
            end
        end
        local function findButton(unique)
            local f = extractFrame(BackpackApp.button_by_unique and BackpackApp.button_by_unique[unique])
            if f then return f end
            local c = BackpackApp.content
            if not c then return nil end
            for _, child in ipairs(c:GetChildren()) do
                if child.Name == unique then
                    for _, desc in ipairs(child:GetDescendants()) do
                        if (desc:IsA("ImageButton") or desc:IsA("TextButton")) and desc.AbsoluteSize.X > 8 then return desc end
                    end
                    return child
                end
            end
            for _, desc in ipairs(c:GetDescendants()) do
                if desc.Name == unique and desc:IsA("GuiObject") then return desc end
            end
        end
        local function scrollToAndGetPos(frame)
            local scroll = BackpackApp.scroll
            if scroll and scroll:IsA("ScrollingFrame") then
                local sY = scroll.AbsoluteSize.Y
                local cY = scroll.CanvasPosition.Y
                local btnTop = (frame.AbsolutePosition.Y - scroll.AbsolutePosition.Y) + cY
                local btnH   = frame.AbsoluteSize.Y
                local tgt = math.max(0, math.min(btnTop - sY*0.5 + btnH*0.5, scroll.CanvasSize.Y.Offset - sY))
                local diff = tgt - cY
                if math.abs(diff) > 5 then
                    local midX = scroll.AbsolutePosition.X + scroll.AbsoluteSize.X * 0.5
                    local midY = scroll.AbsolutePosition.Y + sY * 0.5
                    glideTo(curX, curY, midX, midY)
                    curX, curY = midX, midY
                    local steps = math.max(4, math.min(12, math.ceil(math.abs(diff) / 50)))
                    for s = 1, steps do
                        local t = s / steps
                        t = t < 0.5 and 2*t*t or -1+(4-2*t)*t
                        scroll.CanvasPosition = Vector2.new(0, cY + diff * t)
                        w(0.035)
                    end
                    scroll.CanvasPosition = Vector2.new(0, tgt)
                    RunService.RenderStepped:Wait()
                    RunService.RenderStepped:Wait()
                    w(0.1)
                end
            end
            local abs = frame.AbsolutePosition
            local sz  = frame.AbsoluteSize
            return abs.X + sz.X*0.5, abs.Y + sz.Y*0.5
        end
        local function clearSearch()
            pcall(function()
                if BackpackApp.search_bar then BackpackApp.search_bar.search_param = nil end
                local tb = BackpackApp.instance.Frame.Header.InsetSpace.Search.TextBox
                if tb then tb.Text = "" end
                BackpackApp:refresh_rendered_items()
            end)
        end

        for i = 1, #petList do
            if not AO.enabled then break end
            if not tradeActive() then break end
            if addedCount >= target then break end
            if getMyOfferCount() >= AO_MAX_PETS then break end
            local pet = petList[i]

            local petName = pet.kind or ""
            pcall(function()
                local e = InventoryDB.pets[pet.kind]
                if e and e.name then petName = e.name end
            end)

            local addBtnX, addBtnY = vp.X * 0.3, vp.Y * 0.6
            pcall(function()
                local btn = TradeApp.my_negotiation_offer_pane:get_add_item_button_if_exists()
                if btn and btn:IsA("GuiObject") then
                    addBtnX = btn.AbsolutePosition.X + btn.AbsoluteSize.X * 0.5
                    addBtnY = btn.AbsolutePosition.Y + btn.AbsoluteSize.Y * 0.5
                end
            end)
            glideTo(curX, curY, addBtnX, addBtnY)
            curX, curY = addBtnX, addBtnY
            w(0.12)
            setPos(curX, curY + 2) w(0.05) setPos(curX, curY)
            w(0.2)

            UIManager.set_app_visibility('BackpackApp', true)
            w(0.35)

            local searchX, searchY = vp.X * 0.5, vp.Y * 0.15
            pcall(function()
                local tb = BackpackApp.instance.Frame.Header.InsetSpace.Search.TextBox
                if tb then
                    searchX = tb.AbsolutePosition.X + tb.AbsoluteSize.X * 0.5
                    searchY = tb.AbsolutePosition.Y + tb.AbsoluteSize.Y * 0.5
                end
            end)
            glideTo(curX, curY, searchX, searchY)
            curX, curY = searchX, searchY
            w(0.08)

            for ci = 1, #petName do
                local typed = petName:sub(1, ci)
                pcall(function()
                    if BackpackApp.search_bar then BackpackApp.search_bar.search_param = typed end
                    local tb = BackpackApp.instance.Frame.Header.InsetSpace.Search.TextBox
                    if tb then tb.Text = typed end
                    BackpackApp:refresh_rendered_items()
                end)
                w(0.05 + math.random() * 0.04)
            end
            w(0.4 + math.random() * 0.3)

            _frameMap = buildFrameMap()
            w(0.12)

            local slotX, slotY = vp.X * 0.5, vp.Y * 0.4
            local frame = findButton(pet.unique)
            if frame then slotX, slotY = scrollToAndGetPos(frame) end
            glideTo(curX, curY, slotX, slotY)
            curX, curY = slotX, slotY

            _frameMap = buildFrameMap()
            _lastHoveredUid = nil
            updateHoverTooltip(slotX, slotY)
            w(0.55 + math.random() * 0.2)

            unpatchTooltipRefresh()
            pcall(function() BackpackApp.tooltip:hide() end)
            _lastHoveredUid = nil
            w(0.08)

            setPos(curX, curY + 2) w(0.05) setPos(curX, curY)
            w(0.08)

            unpatchTooltipRefresh()
            clearSearch()
            UIManager.set_app_visibility('BackpackApp', false)
            w(0.15)

            local before = getMyOfferCount()
            local origPick = BackpackApp.pick_item
            BackpackApp.pick_item = function()
                BackpackApp.pick_item = origPick
                return pet
            end
            -- Call the LIVE add method: routes to the original for real trades,
            -- and to the mock add (mockState.trade.sender_offer) during a showcase trade.
            local liveAdd = TradeApp._add_item_to_my_offer or realAdd
            pcall(function() liveAdd(TradeApp) end)
            if BackpackApp.pick_item ~= origPick then BackpackApp.pick_item = origPick end

            if getMyOfferCount() > before then addedCount = addedCount + 1 end

            local dx, dy = curX + math.random(-20, 20), curY + math.random(5, 25)
            glideTo(curX, curY, dx, dy); curX, curY = dx, dy
            w(0.5 + math.random() * 0.4)
        end

        if AO.confirm then
            local function stageNow()
                local ok, s = pcall(function() return TradeApp:_get_current_trade_stage() end)
                return ok and s or nil
            end
            local function findActionButton(word)
                local guis = {}
                local t = playerGui and playerGui:FindFirstChild("TradeApp")
                if t then table.insert(guis, t) end
                for _, g in ipairs(playerGui and playerGui:GetChildren() or {}) do
                    if g:IsA("ScreenGui") and g.Name:lower():find("trade") and g ~= t then table.insert(guis, g) end
                end
                for _, g in ipairs(guis) do
                    for _, d in ipairs(g:GetDescendants()) do
                        if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Visible and d.AbsoluteSize.X > 20 then
                            if buttonLabel(d):lower():find(word) then return d end
                        end
                    end
                end
                return nil
            end
            local function waitForActionButton(word, timeout)
                local b, g = findActionButton(word), 0
                while not b and AO.confirm and tradeActive() and g < timeout do
                    task.wait(0.2); g = g + 0.2
                    b = findActionButton(word)
                end
                return b
            end
            local function clickButton(b, fbX, fbY)
                local tx, ty = fbX, fbY
                if b then
                    tx = b.AbsolutePosition.X + b.AbsoluteSize.X * 0.5
                    ty = b.AbsolutePosition.Y + b.AbsoluteSize.Y * 0.5
                end
                glideTo(curX, curY, tx, ty); curX, curY = tx, ty
                w(0.12)
                setPos(curX, curY + 2) w(0.05) setPos(curX, curY)
                w(0.1)
            end

            if tradeActive() and stageNow() == "negotiation" then
                local cap, g = lockTime() + 2, 0   -- wait the real negotiation lock, + small buffer
                while AO.confirm and tradeActive() and stageNow() == "negotiation" and lockGoing() and g < cap do
                    task.wait(0.2); g = g + 0.2
                end
                local b = waitForActionButton("accept", 12)
                if tradeActive() and stageNow() == "negotiation" then
                    clickButton(b, vp.X * 0.5, vp.Y * 0.86)
                    pcall(function() TradeApp:_on_accept_pressed(TradeApp) end)
                    dismissScamDialog()
                end
            end

            local waited = 0
            while AO.confirm and tradeActive() and stageNow() ~= "confirmation" and waited < 300 do
                task.wait(0.25); waited = waited + 0.25
            end

            if AO.confirm and tradeActive() and stageNow() == "confirmation" then
                local cap, guard = lockTime() + 3, 0   -- wait the real confirmation lock, + small buffer
                while AO.confirm and tradeActive() and lockGoing() and guard < cap do
                    task.wait(0.2); guard = guard + 0.2
                end
                local b = waitForActionButton("confirm", 12)
                if tradeActive() and stageNow() == "confirmation" then
                    clickButton(b, vp.X * 0.5, vp.Y * 0.86)
                    pcall(function() TradeApp:_on_confirm_pressed(TradeApp) end)
                    dismissScamDialog()
                    task.wait(0.4); dismissScamDialog()
                end
            end
        end

        glideTo(curX, curY, vp.X * 0.82, vp.Y * 0.72)
        w(0.2)
        pcall(function() if cursorGui then cursorGui:Destroy() end end)
        AO.running = false
    end)
end

-- auto-run when a real trade opens while the toggle is on
task.spawn(function()
    local wasActive = false
    while true do
        local active = tradeActive()
        if AO.enabled and active and not wasActive then doOffer() end
        wasActive = active
        task.wait(0.5)
    end
end)
-- continuously dismiss scam popups while Accept+Confirm is on
task.spawn(function()
    while true do
        if AO.confirm then dismissScamDialog() end
        task.wait(0.25)
    end
end)

-- Build the compact Auto-Offer controls onto a parent frame (Misc Page 2).
-- Styled to match the Self-Badge section: FredokaOne, UICorner+UIStroke, same ON/OFF palette.
_G._aoBuildControls = function(parent)
    local GRN,GRNT,GRNS = Color3.fromRGB(30,80,50),  Color3.fromRGB(80,255,130), Color3.fromRGB(0,255,100)
    local RED,REDT,REDS = Color3.fromRGB(80,30,30),  Color3.fromRGB(255,90,90),  Color3.fromRGB(255,60,60)
    local PURP          = Color3.fromRGB(190,34,230)
    local NEUT,NEUTT    = Color3.fromRGB(40,40,52),  Color3.fromRGB(225,225,235)
    local function corner(o) Instance.new("UICorner", o).CornerRadius = UDim.new(0,3) end
    local function border(o,c) mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=c, Thickness=0.7, Transparency=0.4, Parent=o}) end

    -- Section header (matches "Self Badge")
    mk("TextLabel", {Size=UDim2.new(1,0,0,11), Position=UDim2.new(0,0,0,70), BackgroundTransparency=1, Text="Auto Offer", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=PURP, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=7, Parent=parent})

    -- Row A: two toggles side by side
    local rowA = mk("Frame", {Size=UDim2.new(1,0,0,15), Position=UDim2.new(0,0,0,84), BackgroundTransparency=1, ZIndex=7, Parent=parent})
    local function mkToggle(posx, onText, offText, get)
        local b = mk("TextButton", {Size=UDim2.new(0.5,-2,1,0), Position=UDim2.new(posx, posx>0 and 2 or 0,0,0), BackgroundColor3=RED, Text=offText, Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=REDT, ZIndex=7, Parent=rowA})
        corner(b)
        local st = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=REDS, Thickness=0.7, Transparency=0.3, Parent=b})
        local function ref()
            local on = get()
            b.Text = on and onText or offText
            b.BackgroundColor3 = on and GRN or RED
            b.TextColor3 = on and GRNT or REDT
            st.Color = on and GRNS or REDS
        end
        ref()
        return b, ref
    end
    local offerBtn, refOffer = mkToggle(0,   "Offer: ON",   "Offer: OFF",   function() return AO.enabled end)
    offerBtn.MouseButton1Click:Connect(function() AO.enabled = not AO.enabled; refOffer(); if AO.enabled and tradeActive() then doOffer() end end)
    local acBtn, refAC = mkToggle(0.5, "Confirm: ON",  "Confirm: OFF",  function() return AO.confirm end)
    acBtn.MouseButton1Click:Connect(function() AO.confirm = not AO.confirm; refAC() end)

    -- Row B: speed selector
    mk("TextLabel", {Size=UDim2.new(0,32,0,14), Position=UDim2.new(0,0,0,103), BackgroundTransparency=1, Text="Speed", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=NEUTT, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=7, Parent=parent})
    local speedBtns = {}
    local function refSpeed()
        for _,e in ipairs(speedBtns) do
            local on = e.v == AO.speed
            e.b.BackgroundColor3 = on and PURP or NEUT
            e.b.TextColor3 = on and Color3.fromRGB(255,255,255) or NEUTT
        end
    end
    for i,v in ipairs({1,2,3,5}) do
        local sb = mk("TextButton", {Size=UDim2.new(0,18,0,14), Position=UDim2.new(0,33+(i-1)*21,0,103), BackgroundColor3=NEUT, Text=v.."x", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=NEUTT, ZIndex=7, Parent=parent})
        corner(sb); border(sb, PURP)
        table.insert(speedBtns, {b=sb, v=v})
        sb.MouseButton1Click:Connect(function() AO.speed = v; refSpeed() end)
    end
    refSpeed()

    -- Row C: Min / Max steppers side by side (each group fits in half of the 118px inner width)
    local function mkStepper(px, nm, get, set)
        mk("TextLabel", {Size=UDim2.new(0,16,0,14), Position=UDim2.new(0,px,0,122), BackgroundTransparency=1, Text=nm, Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=NEUTT, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=7, Parent=parent})
        local minus = mk("TextButton", {Size=UDim2.new(0,13,0,14), Position=UDim2.new(0,px+16,0,122), BackgroundColor3=NEUT, Text="-", Font=Enum.Font.FredokaOne, TextSize=11, TextColor3=NEUTT, ZIndex=7, Parent=parent})
        corner(minus); border(minus, PURP)
        local val = mk("TextLabel", {Size=UDim2.new(0,13,0,14), Position=UDim2.new(0,px+29,0,122), BackgroundTransparency=1, Text=tostring(get()), Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=Color3.fromRGB(220,235,255), ZIndex=7, Parent=parent})
        local plus = mk("TextButton", {Size=UDim2.new(0,13,0,14), Position=UDim2.new(0,px+42,0,122), BackgroundColor3=NEUT, Text="+", Font=Enum.Font.FredokaOne, TextSize=11, TextColor3=NEUTT, ZIndex=7, Parent=parent})
        corner(plus); border(plus, PURP)
        local function rd() val.Text = tostring(get()) end
        minus.MouseButton1Click:Connect(function() set(get()-1); rd() end)
        plus.MouseButton1Click:Connect(function() set(get()+1); rd() end)
        return rd
    end
    local rdMax
    local rdMin = mkStepper(0, "Min", function() return AO.min end, function(v)
        AO.min = math.clamp(v,1,AO_MAX_PETS); if AO.max < AO.min then AO.max = AO.min; if rdMax then rdMax() end end
    end)
    rdMax = mkStepper(61, "Max", function() return AO.max end, function(v)
        AO.max = math.clamp(v,1,AO_MAX_PETS); if AO.min > AO.max then AO.min = AO.max; rdMin() end
    end)
end
end
_aoEngine()
end

_G._userInfoCache = _G._userInfoCache or {}
function _G._prefetchUserInfo(userId)
    if userId <= 0 or _G._userInfoCache[userId] then return end
    task.spawn(function()
        pcall(function()
            local UserService = game:GetService("UserService")
            local info = UserService:GetUserInfosByUserIdsAsync({ userId })
            if info and info[1] then
                _G._userInfoCache[userId] = _G._userInfoCache[userId] or {}
                _G._userInfoCache[userId].username    = info[1].Username
                _G._userInfoCache[userId].displayName = info[1].DisplayName
            end
        end)
        pcall(function()
            local img, ready
            repeat
                img, ready = game.Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                if not ready then task.wait(1) end
            until ready
            _G._userInfoCache[userId] = _G._userInfoCache[userId] or {}
            _G._userInfoCache[userId].thumbnail = img
        end)
    end)
end

-- Push cached username/thumbnail into the open profile header, retrying until the
-- prefetch fills (or the user navigates to a different profile). `want` is
-- "username" or "thumbnail". Calling set_header_info is what updates the visible UI.
function _G._applyCachedHeader(self, want)
    _G._prefetchUserInfo(self.user_id)  -- ensure a fetch is in flight for this user
    task.spawn(function()
        for _ = 1, 150 do  -- poll up to ~15s; apply only while this profile is the active one
            local c = _G._userInfoCache[self.user_id]
            if c and self.app and self.app.player_profile == self then
                if want == "username" and c.username then
                    self.username     = c.username
                    self.display_name = c.displayName or c.username
                    self.app:set_header_info({ username = self.username })
                    return
                elseif want == "thumbnail" and c.thumbnail then
                    self.image_id = c.thumbnail
                    self.app:set_header_info({ profile_icon = c.thumbnail })
                    return
                end
            end
            task.wait(0.1)
        end
    end)
end

-- Patch PlayerProfile immediately — must happen before any PlayerProfile.new()
-- call so _load_user_info and is_page_empty are fixed from the first profile open
do
    local ok, PlayerProfile = pcall(load, "PlayerProfile")
    if ok and PlayerProfile then
        -- Guard _load_user_info against nil UserService result (userId=0 or invalid)
        if PlayerProfile._load_user_info then
            local _orig = PlayerProfile._load_user_info
            PlayerProfile._load_user_info = function(self, ...)
                if not self.user_id or self.user_id <= 0 then return end
                -- Online players load instantly from their Player object — keep original
                -- (it also sets the in_trade button state). Offline presets: cache + retry.
                if self.player then return _orig(self, ...) end
                _G._applyCachedHeader(self, "username")
            end
        end
        if PlayerProfile._load_profile_pic then
            local _orig = PlayerProfile._load_profile_pic
            PlayerProfile._load_profile_pic = function(self, ...)
                if not self.user_id or self.user_id <= 0 then return end
                if self.player then return _orig(self, ...) end
                _G._applyCachedHeader(self, "thumbnail")
            end
        end
        -- Guard is_page_empty against nil profile_data and nil stickers per page
        if PlayerProfile.is_page_empty then
            local _orig = PlayerProfile.is_page_empty
            PlayerProfile.is_page_empty = function(self, page)
                if not self.profile_data then return true end
                local pages = self.profile_data.pages
                if pages then
                    local pageData = pages[page] or pages[tostring(page)]
                    if pageData then
                        for _, slotData in pairs(pageData) do
                            if slotData and next(slotData) then return false end
                        end
                    end
                end
                local stickers = self.profile_data.stickers
                if stickers == nil then return true end
                return not (stickers[page] and next(stickers[page]))
            end
        end
    end
end

-- Fake trade records injected into GetTradeHistory results
local _mockTradeHistory = {}  -- newest first

-- Hook _get_trade_history to inject mock records
do
    local _origGetTradeHistory = TradeHistoryApp._get_trade_history
    TradeHistoryApp._get_trade_history = function(self, useCached)
        local real = _origGetTradeHistory(self, useCached) or {}
        if #_mockTradeHistory == 0 then return real end
        -- Combine real + mock then sort oldest-first (ascending timestamp)
        -- so that after _refresh reverses it, newest appears at top
        local combined = {}
        for _, r in ipairs(real) do table.insert(combined, r) end
        for _, r in ipairs(_mockTradeHistory) do table.insert(combined, r) end
        -- Sort newest-first (descending) so the most recently completed trade
        -- always appears at the top of the history list, matching real game behaviour.
        table.sort(combined, function(a, b)
            return (a.timestamp or 0) > (b.timestamp or 0)
        end)
        return combined
    end
end

if not TradeApp then
    warn("[MockTrade] TradeApp not found — aborting")
    return
end

-- FAKE PET SPAWNER (for receiving mock trade items)
-- Hoisted outside do block so _addToInventory can access them
local _spawnerPets   = {}
-- Newness groups matching the real game's ordering (from blueprint.lua)
-- Higher = appears first in backpack. Each group decrements so newest appears top.
local _newnessGroups = {
    mega_neon_flyable_rideable = 990000,
    mega_neon_flyable          = 980000,
    mega_neon_rideable         = 970000,
    mega_neon                  = 960000,
    neon_flyable_rideable      = 950000,
    neon_flyable               = 940000,
    neon_rideable              = 930000,
    neon                       = 920000,
    flyable_rideable           = 910000,
    flyable                    = 900000,
    rideable                   = 890000,
    regular                    = 880000,
}

local function _getPropertyGroup(props)
    local isMega  = props.mega_neon or false
    local isNeon  = props.neon      or false
    local canFly  = props.flyable   or false
    local canRide = props.rideable  or false
    if isMega then
        if canFly and canRide then return "mega_neon_flyable_rideable"
        elseif canFly  then return "mega_neon_flyable"
        elseif canRide then return "mega_neon_rideable"
        else return "mega_neon" end
    elseif isNeon then
        if canFly and canRide then return "neon_flyable_rideable"
        elseif canFly  then return "neon_flyable"
        elseif canRide then return "neon_rideable"
        else return "neon" end
    else
        if canFly and canRide then return "flyable_rideable"
        elseif canFly  then return "flyable"
        elseif canRide then return "rideable"
        else return "regular" end
    end
end

-- Pet name generator (from blueprint.lua)
local _petNamesByType = {}
local _namePrefixes = {"★","☆","♡","☁️","✨","🍓","🌸","🍯","☕","🌙","🌈","❄️","🫧","🍬","🍪","🥛"}
local _nameWords    = {"Shadow","Blaze","Frost","Thunder","Moon","Star","Sky","Ocean","River","Storm",
    "Ember","Ash","Dusk","Dawn","Night","Day","Sun","Wind","Rain","Snow","Ice","Fire",
    "Nova","Cosmo","Galaxy","Orbit","Comet","Meteor","Aurora","Nebula","Crystal","Gem",
    "Ruby","Sapphire","Emerald","Diamond","Gold","Silver","Mystic","Magic","Enchant"}

local function generatePetName(petId)
    if petId and not _petNamesByType[petId] then _petNamesByType[petId] = {} end
    local name; local attempts = 0
    repeat
        local word = _nameWords[math.random(1, #_nameWords)]
        if math.random(1, 3) == 1 then
            name = _namePrefixes[math.random(1, #_namePrefixes)] .. word
        else
            name = word .. " " .. _namePrefixes[math.random(1, #_namePrefixes)]
        end
        attempts = attempts + 1
    until not (petId and _petNamesByType[petId][name]) or attempts > 100
    if petId and attempts <= 100 then _petNamesByType[petId][name] = true end
    return name
end

-- Hoisted helpers used by _addToInventory and spawner internals
local function updateData(key, fn)
    local d = ClientData.get(key)
    local c = table.clone(d)
    local result = fn(c)
    pcall(function() setthreadidentity(2) end)
    ClientData.predict(key, result)
    pcall(function() setthreadidentity(8) end)
end
do local function findIdx(arr, pred)
    for i,v in pairs(arr) do if pred(v,i) then return i end end
end

do

do local function _setupPetHandler()
    local ok, EP = pcall(load, "EquippedPets")
    if not ok or not EP then return end

    -- 1. Allow equipping 2 pets at once
    EP.get_max_equip_count = function() return 2 end

    -- 2. Fake pets never count as "equipped" so they don't block real slots
    local _origIsEquipped = EP.is_equipped
    if _origIsEquipped then
        EP.is_equipped = function(item)
            if item and item.unique and _spawnerPets[item.unique] then return false end
            return _origIsEquipped(item)
        end
    end

    -- 3. For equip-slot counting only, fake pets don't fill real slots.
    local _origGetMyEquipped = EP.get_my_equipped
    if _origGetMyEquipped then
        EP.get_my_equipped = function(...)
            -- Return full list including spawned pets so UI shows main/alt buttons
            return _origGetMyEquipped(...)
        end
    end
    -- Only filter for slot-count checks via a separate helper
    EP._get_real_equipped_count = function()
        local result = _origGetMyEquipped and _origGetMyEquipped() or {}
        local count = 0
        for _, wrapper in ipairs(result) do
            if not _spawnerPets[wrapper.pet_unique] then
                count = count + 1
            end
        end
        return count
    end

    -- Hook ClientData.get so subscription_manager ALWAYS contains equip_2x_pets,
    local function _getExpiry() return os.time() + 60 * 60 * 24 * 25 end

    local _origGet = ClientData.get
    ClientData.get = function(key, ...)
        local data = _origGet(key, ...)
        if key == "subscription_manager" then
            data = data or {}
            -- Always overwrite so expiry is always fresh and days-left is correct
            data.equip_2x_pets = { expiration = _getExpiry() }
        end
        return data
    end

    -- Hook get_server for alt accounts / observers
    local _origGetServer = ClientData.get_server
    if _origGetServer then
        ClientData.get_server = function(player, key, ...)
            local data = _origGetServer(player, key, ...)
            if key == "subscription_manager" and player == Players.LocalPlayer then
                data = data or {}
                data.equip_2x_pets = { expiration = _getExpiry() }
            end
            return data
        end
    end

    pcall(function()
        local id = (get_thread_identity and get_thread_identity()) or 8
        setthreadidentity(2)
        local sm = ClientData.get("subscription_manager") or {}
        ClientData.predict("subscription_manager", sm)
        ClientData.update("subscription_manager", sm)
        setthreadidentity(id)
    end)

    -- 5. Hook CertificateApp so the cert popup shows the correct Pet Handler text
    task.defer(function()
        pcall(function()
            local certApp = UIManager.apps and UIManager.apps.CertificateApp
            if not certApp then return end
            local orig = certApp.display_certificate
            certApp.display_certificate = function(self, sub_id, sub_data)
                if sub_id == "equip_2x_pets" then
                    local sm = ClientData.get("subscription_manager") or {}
                    local expiry = sm.equip_2x_pets and sm.equip_2x_pets.expiration
                    local dateStr = expiry
                        and DateTime.fromUnixTimestamp(expiry):FormatLocalTime("ll", "en-us")
                        or ""
                    self.expiration_date.Text = dateStr; self.body.CertificateName.Text = "PET HANDLER"
                    self.certificate_description.Text = "Certified to equip and care for multiple pets simultaneously."
                    self.certificate_icon.Image = "rbxassetid://135693406849779"; self.player_name.Text = Players.LocalPlayer.Name
                    self.UIManager.set_app_visibility(self.ClassName, true)
                else
                    return orig(self, sub_id, sub_data)
                end
            end
        end)
    end)
end
_setupPetHandler()

end local _equippedPets  = {} -- up to 2 slots: [1] and [2]
local _equippedPet   = nil -- kept for compatibility (points to most recently equipped)
local _currentRideId = nil
local _rideAnimTrack = nil
local _ailmentsCache = {}

-- Use the real game PetNeonHelper — it has correct timing for mega neon
local PetNeonHelper = load("PetNeonHelper")

local petModels = {}
local function getPetModel(kind)
    if petModels[kind] then return petModels[kind]:Clone() end
    local p = DownloadClient.promise_download_copy("Pets", kind)
    if p then local m=p:expect(); petModels[kind]=m; return m:Clone() end
end
local function applyNeonToModel(petModel, petData)
    local pm = petModel:FindFirstChild("PetModel"); if not pm then return end
    local entry = IDB and IDB.pets and IDB.pets[petData.id]; if not entry then return end
    if petData.properties.mega_neon and entry.mega_neon_parts then
        if entry.neon_parts then pcall(function() PetNeonHelper.apply_neon(pm, entry.neon_parts) end) end
        -- Use the real game PetNeonHelper.precache + step_mega_neon exactly like the blueprint script
        -- (these are real game functions with correct timing built in)
        task.spawn(function()
            local kindData = KindDB[petData.id] or KindDB[petData.kind]
            if not kindData or not kindData.mega_neon_parts then return end
            local cache = { cached_colors = nil, cached_parts = nil }
            pcall(function() PetNeonHelper.precache(cache, kindData, pm) end)
            while petModel.Parent do
                pcall(function() PetNeonHelper.step_mega_neon(cache, pm, kindData) end)
                RunService.RenderStepped:Wait()
            end
        end)
    elseif petData.properties.neon and entry.neon_parts then
        pcall(function() PetNeonHelper.apply_neon(pm, entry.neon_parts) end)
    end
end
local function addWrapper(w)
    updateData("pet_char_wrappers", function(t) w.unique=#t+1; w.index=#t+1; t[#t+1]=w; return t end)
end
local function addState(s)
    updateData("pet_state_managers", function(t) t[#t+1]=s; return t end)
end
local function removeWrapper(uid)
    updateData("pet_char_wrappers", function(t)
        local i=findIdx(t,function(w) return w.pet_unique==uid end)
        if i then table.remove(t,i); for j,w in pairs(t) do w.unique=j; w.index=j end end; return t
    end)
end
_G._removeWrapper = removeWrapper   -- _removeFromInventory (file scope) used to call this as a nil global and crash
local function removeState(uid)
    local pet=_spawnerPets[uid]; if not pet or not pet.model then return end
    updateData("pet_state_managers", function(t)
        local i=findIdx(t,function(s) return s.char==pet.model end)
        if i then table.remove(t,i) end; return t
    end)
end
local function clearPetStates(uid)
    local pet=_spawnerPets[uid]; if not pet or not pet.model then return end
    updateData("pet_state_managers", function(t)
        local i=findIdx(t,function(s) return s.char==pet.model end)
        if i then local u=table.clone(t); u[i]=table.clone(u[i]); u[i].states={}; return u end; return t
    end)
end
local function setPetState(uid, stateId)
    local pet=_spawnerPets[uid]; if not pet or not pet.model then return end
    updateData("pet_state_managers", function(t)
        local i=findIdx(t,function(s) return s.char==pet.model end)
        if i then local u=table.clone(t); u[i]=table.clone(u[i]); u[i].states={{id=stateId}}; return u end; return t
    end)
end
local function clearPlayerStates()
    updateData("state_manager", function(s) local u=table.clone(s); u.states={}; u.is_sitting=false; return u end)
end
local function setPlayerState(stateId)
    updateData("state_manager", function(s) local u=table.clone(s); u.states={{id=stateId}}; u.is_sitting=true; return u end)
end
local function attachRideConstraint(petModel)
    local char=Players.LocalPlayer.Character; if not char or not char.PrimaryPart then return false end
    local ridePos=petModel:FindFirstChild("RidePosition",true); if not ridePos then return false end
    local att = mk("Attachment", {Parent=ridePos, Position=Vector3.new(0,1.237,0), Name="SourceAttachment"})
    local rc = mk("RigidConstraint", {Name="StateConnection"})
    rc.Attachment0=att; rc.Attachment1=char.PrimaryPart.RootAttachment; rc.Parent=char; return true
end
local function dismount()
    if not _currentRideId then return end
    local pet=_spawnerPets[_currentRideId]
    if pet and pet.model then
        if _rideAnimTrack then _rideAnimTrack:Stop(); _rideAnimTrack:Destroy(); _rideAnimTrack=nil end
        local sa=pet.model:FindFirstChild("SourceAttachment",true); if sa then sa:Destroy() end
        local char=Players.LocalPlayer.Character
        if char then for _,p in pairs(char:GetDescendants()) do if p:IsA("BasePart") and p:GetAttribute("HaveMass") then p.Massless=false end end end
        clearPetStates(_currentRideId); clearPlayerStates(); pet.model:ScaleTo(1)
    end
    _currentRideId=nil
end
local function mount(uid, playerState, petState)
    local pet=_spawnerPets[uid]; if not pet or not pet.model then return end
    local char=Players.LocalPlayer.Character
    if not char or not char.PrimaryPart or not char:FindFirstChild("Humanoid") then return end
    dismount(); _currentRideId=uid
    setPetState(uid,petState); setPlayerState(playerState)
    pet.model:ScaleTo(2); attachRideConstraint(pet.model)
    _rideAnimTrack=char.Humanoid.Animator:LoadAnimation(AnimMgr.get_track("PlayerRidingPet"))
    char.Humanoid.Sit=true
    for _,p in pairs(char:GetDescendants()) do if p:IsA("BasePart") and p.Massless==false then p.Massless=true; p:SetAttribute("HaveMass",true) end end
    _rideAnimTrack:Play()
end

-- Ailments hook
do local _origGetServer = ClientData.get_server
ClientData.get_server = function(player, key, ...)
    local data = _origGetServer(player, key, ...)
    if key=="ailments_manager" and player==Players.LocalPlayer then
        local ad = data and table.clone(data) or {}; ad.ailments = ad.ailments or {}
        for petId in pairs(_spawnerPets) do
            if not _ailmentsCache[petId] then
                local types={}; for kind in pairs(AilmentsDB) do if kind~="at_work" and kind~="mystery" and kind~="walking" then table.insert(types,kind) end end
                local pa={}; local used={}
                for i=1,math.min(math.random(2,4),#types) do
                    local k; repeat k=types[math.random(1,#types)] until not used[k]; used[k]=true
                    pa[HttpService:GenerateGUID(false)]={components={},created_timestamp=os.time(),kind=k,progress=0,rate=0,rate_timestamp=os.time(),sort_order=i*100}
                end
                _ailmentsCache[petId]=pa
            end
            ad.ailments[petId]=_ailmentsCache[petId]
        end
        return ad
    end
    return data
end

end local function doUnequip(item)
    local pet=_spawnerPets[item.unique]; if not pet then return end
    if _currentRideId==item.unique then dismount() end
    removeWrapper(item.unique); removeState(item.unique)
    if pet.model then pet.model:Destroy(); pet.model=nil end
    if _equippedPet and _equippedPet.unique==item.unique then _equippedPet=nil end
    for i=#_equippedPets,1,-1 do
        if _equippedPets[i].unique==item.unique then table.remove(_equippedPets,i) end
    end
    _ailmentsCache[item.unique]=nil

    -- Rebalance FollowOffset for remaining pets after unequip
    task.defer(function()
        pcall(function()
            local wrappers = ClientData.get("pet_char_wrappers") or {}
            local idx = 0
            for _, w in ipairs(wrappers) do
                if w.controller == Players.LocalPlayer then
                    idx = idx + 1
                    local sp = _spawnerPets[w.pet_unique]
                    local m = sp and sp.model
                    if m then
                        local offset
                        if idx == 1 then offset = Vector3.new(3.5, 0, 0)
                        elseif idx == 2 then offset = Vector3.new(-3.5, 0, 0)
                        else offset = Vector3.new(0, 0, 3.5 * (idx-1)) end
                        m:SetAttribute("FollowOffset", offset)
                    end
                end
            end
        end)
    end)

    safeCall(function()
        setthreadidentity(2)
        local em=ClientData.get("equip_manager") or {}; local pets=em.pets or {}
        for i=#pets,1,-1 do if pets[i] and pets[i].unique==item.unique then table.remove(pets,i) end end
        em.pets=pets; ClientData.update("equip_manager",em); setthreadidentity(8)
    end)
end

local function doEquip(item)
    -- Don't equip same pet twice
    if _spawnerPets[item.unique] and _spawnerPets[item.unique].model then return end
    -- Allow up to 2 equipped pets (pet handler)
    if #_equippedPets >= 2 then
        doUnequip(_equippedPets[1])
    end
    safeCall(function()
        local EP=load("EquippedPets")
        if EP and not EP._spinnerHooked then
            EP._spinnerHooked=true
            -- Allow 2 slots (pet handler)
            EP.get_max_equip_count=function() return 2 end
            -- Spawned pets return false for is_equipped so they don't block the equip button
            local _origIE=EP.is_equipped
            if _origIE then EP.is_equipped=function(it) if _spawnerPets[it and it.unique] then return false end; return _origIE(it) end end
            -- Do NOT filter get_my_equipped — UI needs spawned pets in the list
            -- to show the main/alt interaction buttons
        end
    end)
    local model=getPetModel(item.kind); if not model then return end
    model.Parent=workspace
    applyNeonToModel(model, item)
    _spawnerPets[item.unique].model=model; _equippedPet=item
    table.insert(_equippedPets, item)

    -- Set FollowOffset so pets stand on opposite sides (matches reference script)
    pcall(function()
        local slotIndex = 0
        for _, sp in pairs(_spawnerPets) do
            if sp.model and sp.data then slotIndex = slotIndex + 1 end
        end
        local offset
        if slotIndex <= 1 then offset = Vector3.new(3.5, 0, 0)
        else offset = Vector3.new(-3.5, 0, 0) end
        local kindEntry = IDB and IDB.pets and IDB.pets[item.id or item.kind]
        if kindEntry and kindEntry.follow_offset_scale then
            offset = offset * kindEntry.follow_offset_scale
        end
        model:SetAttribute("FollowOffset", offset)
    end)
    local entry=IDB and IDB.pets and IDB.pets[item.id]
    local trickCount=entry and entry.tricks and #entry.tricks or 0
    local resolvedId=(entry and entry._base_kind) or item.id
    task.defer(function()
        local rpName = (item.properties.rp_name and item.properties.rp_name ~= "")
            and item.properties.rp_name or generatePetName(item.id or item.kind)
        -- Store name back on item so it persists
        item.properties.rp_name = rpName

        addWrapper({
            char               = model,
            mega_neon          = item.properties.mega_neon or false,
            neon               = item.properties.neon or false,
            player             = Players.LocalPlayer,
            entity_controller  = Players.LocalPlayer,
            controller         = Players.LocalPlayer,
            rp_name            = rpName,
            pet_trick_level    = math.max(item.properties.pet_trick_level or 0, trickCount),
            pet_unique         = item.unique,
            pet_id             = resolvedId,
            location           = { full_destination_id = "housing", destination_id      = "housing", house_owner         = Players.LocalPlayer, },
            pet_progression    = { age              = item.properties.age or math.random(1, 6), xp               = item.properties.xp or 0, friendship_level = item.properties.friendship_level or 0, percentage       = math.random(0, 99) / 100, },
            are_colors_sealed  = false,
            is_pet             = true,
        })

        addState({
            char                  = model,
            player                = Players.LocalPlayer,
            store_key             = "pet_state_managers",
            is_sitting            = false,
            chars_connected_to_me = {},
            states                = {},
        })

        task.wait(0.15)

        pcall(function() AilmentsClient.on_ailments_changed(Players.LocalPlayer) end)

        -- Force nametag by triggering a predict update on pet_char_wrappers
        -- CharWrapperClient listens to this and re-renders the name above the pet
        task.wait(0.1)
        safeCall(function()
            updateData("pet_char_wrappers", function(wrappers)
                for _, w in pairs(wrappers) do
                    if w.pet_unique == item.unique then
                        w.rp_name = item.properties.rp_name or ""
                    end
                end
                return wrappers
            end)
        end)

        safeCall(function()
            setthreadidentity(2)
            local em   = ClientData.get("equip_manager") or {}
            local pets = em.pets or {}
            for i = #pets, 1, -1 do
                if pets[i] and pets[i].unique == item.unique then
                    table.remove(pets, i)
                end
            end
            table.insert(pets, item)
            em.pets = pets
            -- predict updates UI instantly; update tells server
            ClientData.predict("equip_manager", em)
            ClientData.update("equip_manager", em)
            setthreadidentity(8)
        end)
    end)
end

-- Tricks — mirror the logic from the reference script exactly
task.spawn(function()
    safeCall(function()
        if type(setthreadidentity)=="function" then setthreadidentity(2) end
        local PA  = load("PetActions")
        local AM  = load("AnimationManager")
        local PEM = load("PetEntityManager")
        local IDB2 = load("InventoryDB")
        if not PA or not PA.do_trick then return end
        local origDoTrick = PA.do_trick
        PA.do_trick = function(wrapper)
            if not (wrapper and _spawnerPets and _spawnerPets[wrapper.pet_unique]) then
                return origDoTrick(wrapper)
            end
            local entry = IDB2.pets[wrapper.pet_id]
            if not entry or not entry.tricks or #entry.tricks == 0 then return end
            local buttons = {}
            for i, trick in ipairs(entry.tricks) do
                if (wrapper.pet_trick_level or 0) < i then
                    buttons[i] = { layout_order=i, text="???", button_state="inactive" }
                else
                    buttons[i] = { layout_order=i, text=trick[1] }
                end
            end
            task.spawn(function()
                local chosen = UIManager.apps.DialogApp:dialog({ dialog_type="ScrollingButtonsDialog", header="SELECT TRICK", buttons=buttons, exit_button=true, cells_per_row=2, padding=10 })
                if not chosen or chosen=="cancel" then return end
                local te = entry.tricks[chosen]; if not te then return end
                local tn = te[1]; local ak = te[2] or tn
                local char = wrapper.char
                local pm = char:FindFirstChild("PetModel")
                local ac = pm and pm:FindFirstChildOfClass("AnimationController")
                local anim = (ac and ac:FindFirstChildOfClass("Animator"))
                    or char:FindFirstChildWhichIsA("Animator", true)
                if not anim then return end
                local at = AM.get_track(ak) or AM.get_track(tn)
                if not at then return end
                -- Fire original to play windup on server
                pcall(function() origDoTrick(wrapper) end)
                task.wait(3)
                pcall(function() UIManager.apps.FocusPetApp:release_focus() end)
                safeCall(function()
                    local sp = _spawnerPets[wrapper.pet_unique]
                    if sp and sp._activeTrickTrack then
                        pcall(function() sp._activeTrickTrack:Stop(0.1) end)
                        sp._activeTrickTrack = nil
                    end
                    local track = anim:LoadAnimation(at)
                    track:Play()
                    if sp then sp._activeTrickTrack = track end
                    task.spawn(function()
                        local lp = Players.LocalPlayer
                        local lpChar = lp and lp.Character
                        local lastPos = lpChar and lpChar:FindFirstChild("HumanoidRootPart") and lpChar.HumanoidRootPart.Position
                        local t = 0
                        while t < 15 do
                            task.wait(0.1); t = t + 0.1
                            if not track.IsPlaying then break end
                            local entity = PEM and PEM.get_pet_entity(char)
                            if entity and entity.move_state and entity.move_state.is_moving then
                                track:Stop(0.2); break
                            end
                            lpChar = lp and lp.Character
                            local hrp = lpChar and lpChar:FindFirstChild("HumanoidRootPart")
                            if hrp and lastPos then
                                if (hrp.Position - lastPos).Magnitude > 1.5 then
                                    track:Stop(0.2); break
                                end
                            end
                            if hrp then lastPos = hrp.Position end
                        end
                        if sp then sp._activeTrickTrack = nil end
                    end)
                end)
            end)
        end
    end)
end)

if not _G._mockTradeRouterHooked then
    _G._mockTradeRouterHooked = true
    local oldGet = RouterClient_.get
    RouterClient_.get = function(name)
        if name=="ToolAPI/Equip" then return {InvokeServer=function(_,uid,meta) if _spawnerPets[uid] then doEquip(_spawnerPets[uid].data); return true,{action="equip",is_server=true} end; return oldGet(name):InvokeServer(uid,meta) end}
        elseif name=="ToolAPI/Unequip" then return {InvokeServer=function(_,uid) if _spawnerPets[uid] then doUnequip(_spawnerPets[uid].data); return true,{action="unequip",is_server=true} end; return oldGet(name):InvokeServer(uid) end}
        elseif name=="AdoptAPI/RidePet" then return {InvokeServer=function(_,pd) if _spawnerPets[pd.pet_unique] then mount(pd.pet_unique,"PlayerRidingPet","PetBeingRidden"); return true end; return oldGet(name):InvokeServer(pd) end}
        elseif name=="AdoptAPI/FlyPet" then return {InvokeServer=function(_,pd) if _spawnerPets[pd.pet_unique] then mount(pd.pet_unique,"PlayerFlyingPet","PetBeingFlown"); return true end; return oldGet(name):InvokeServer(pd) end}
        elseif name=="AdoptAPI/ExitSeatStates" then return {FireServer=function() if _currentRideId then dismount(); return true end; return oldGet(name):FireServer() end}
        elseif name=="SettingsAPI/SetPetRoleplayName" then return {InvokeServer=function(_, petUniqueId, newName)
            -- Only intercept spawned pets; real pets go to server
            if not _spawnerPets[petUniqueId] then
                return oldGet(name):InvokeServer(petUniqueId, newName)
            end
            -- Update wrapper rp_name so nametag re-renders
            updateData("pet_char_wrappers", function(wrappers)
                for i, w in pairs(wrappers) do
                    if w.pet_unique == petUniqueId then
                        local cw = table.clone(w)
                        cw.rp_name = newName
                        wrappers[i] = cw
                        break
                    end
                end
                return wrappers
            end)
            updateData("inventory", function(inv)
                if inv.pets and inv.pets[petUniqueId] then
                    inv.pets[petUniqueId].properties.rp_name = newName
                end
                return inv
            end)
            -- Update our local cache
            if _spawnerPets[petUniqueId] and _spawnerPets[petUniqueId].data then
                _spawnerPets[petUniqueId].data.properties.rp_name = newName
            end
            return true
        end}
        end; return oldGet(name)
    end
end

-- _spinnerCreate: called by the Spin tab claim flow to add a pet to inventory
_G._spinnerCreate = function(id, props)
    local uid = HttpService:GenerateGUID(false)
    local item = KindDB and KindDB[id]
    if not item then return nil end
    local newPet = {
        unique = uid, category = "pets", id = id,
        kind = item.kind or id,
        newness_order = _G._spawnNewness and _G._spawnNewness(item.kind or id, props or {}) or math.random(1, 900000),
        properties = props or {},
    }
    local inv = ClientData.get("inventory")
    if inv and inv.pets then
        inv.pets[uid] = newPet
        _spawnerPets[uid] = {data = newPet, model = nil}
        pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)
    end
    return newPet
end

end -- FAKE PET SPAWNER do block

-- _addToInventory/_removeFromInventory hoisted to file scope so trade completion can call them
-- Exact port of reference script's CreateInventoryItem
-- ════════════════════════════════════════════════════════════════════════
--  Spawned-pet backpack order: RARITY first (legendary > ultra rare > rare > uncommon > common),
--  then A-Z by pet name inside each rarity, then variant (MFR first) for the same pet.
--  The backpack lists higher newness_order first, so this builds a number that sorts that way.
--  (The old code ordered by variant group + spawn order, and the Spawn-All list by a hand-picked list.)
--  Own function scope: no main-chunk locals.
-- ════════════════════════════════════════════════════════════════════════
do
local function _spawnOrderSetup()
    local RARITY = {
        legendary = 5, ultra_rare = 4, ["ultra-rare"] = 4, ultrarare = 4, ["ultra rare"] = 4,
        rare = 3, uncommon = 2, common = 1,
    }
    local VARIANT = {   -- same pet: higher variant is listed first
        mega_neon_flyable_rideable = 11, mega_neon_flyable = 10, mega_neon_rideable = 9, mega_neon = 8,
        neon_flyable_rideable = 7, neon_flyable = 6, neon_rideable = 5, neon = 4,
        flyable_rideable = 3, flyable = 2, rideable = 1, regular = 0,
    }
    local nameRank, counters = nil, {}
    local function buildRanks()
        nameRank = {}
        local list = {}
        for kind, entry in pairs((InventoryDB and InventoryDB.pets) or {}) do
            if type(entry) == "table" then
                list[#list + 1] = { kind = kind, name = tostring(entry.name or kind):lower() }
            end
        end
        table.sort(list, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return tostring(a.kind) < tostring(b.kind)
        end)
        for i, e in ipairs(list) do nameRank[e.kind] = i end
    end
    local function rarityTier(kind)
        local r
        pcall(function() r = InventoryDB.pets[kind].rarity end)
        if r == nil then pcall(function() r = KindDB[kind].rarity end) end
        if type(r) == "string" then return RARITY[r:lower()] or 0 end
        if type(r) == "number" then return math.clamp(math.floor(r), 0, 5) end
        return 0
    end

    -- noCount = true for static lists (the picker) so the per-copy counter isn't advanced
    _G._spawnNewness = function(kind, props, noCount)
        if not nameRank then buildRanks() end
        local rank = math.min(nameRank[kind] or 4999, 4999)
        local v = VARIANT[_getPropertyGroup(props or {})] or 0
        local copy = 0
        if not noCount then
            local key = tostring(kind) .. "|" .. v
            copy = counters[key] or 0
            counters[key] = copy + 1
        end
        -- rarity * 10,000,000  +  (A-Z, A highest) * 1,000  +  variant * 60  +  newest-copy-first
        return rarityTier(kind) * 10000000 + (4999 - rank) * 1000 + v * 60 + (59 - math.min(copy, 59))
    end
end
local _sok, _serr = pcall(_spawnOrderSetup)
if not _sok then warn("[SpawnOrder] " .. tostring(_serr)) end
end

end do local _nextToyOrder = 60000
end local function _addToInventory(item)
    local itemId = item.id or item.kind
    local itemKindData = KindDB and KindDB[itemId]
    if not itemKindData then
        warn("[Spawner] KindDB entry not found: " .. tostring(itemId))
        return nil
    end

    local uniqueId = item.unique or HttpService:GenerateGUID(false)
    local properties = item.properties or {}
    local newnessValue

    -- Order: rarity, then A-Z, then variant (see _G._spawnNewness). Any hand-set _newness_order
    -- (the old Spawn-All list order) and the random one trades used to pass are ignored on purpose.
    properties._newness_order = nil
    if item.top_of_inventory then
        -- pets received from a mock trade: newer than everything else, so they sit at the very top of the
        -- backpack (it lists higher newness_order first; spawned pets top out around 6e7)
        _G._mockRecvSeq = (_G._mockRecvSeq or 0) + 1
        newnessValue = 1000000000 + _G._mockRecvSeq
    elseif _G._spawnNewness then
        newnessValue = _G._spawnNewness(itemId, properties)
    else
        local groupKey = _getPropertyGroup(properties)
        _newnessGroups[groupKey] = _newnessGroups[groupKey] - 1
        newnessValue = _newnessGroups[groupKey]
    end

    if not properties.ailments_completed then
        properties.ailments_completed = 0
    end
    if properties.rp_name == "__no_name__" then
        properties.rp_name = ""
    elseif not properties.rp_name or properties.rp_name == "" then
        properties.rp_name = generatePetName(itemId)
    end

    -- Verify InventoryDB also has this kind (needed by BackpackCategoryButtons + PracticeDogHider)
    local inventoryKindData = InventoryDB and InventoryDB.pets and InventoryDB.pets[itemId]
    if not inventoryKindData then
        -- Try KindDB kind field as fallback
        local kindKey = itemKindData.kind or itemId
        inventoryKindData = InventoryDB and InventoryDB.pets and InventoryDB.pets[kindKey]
        if inventoryKindData then
            itemId = kindKey
        else
            warn("[Spawner] InventoryDB.pets entry not found: " .. tostring(itemId))
            return nil
        end
    end

    local itemData = {
        unique        = uniqueId,
        category      = "pets",
        id            = itemId,
        kind          = itemId,
        newness_order = newnessValue,
        properties    = properties,
    }

    -- Write directly to live inventory (exact reference pattern)
    local identity = (get_thread_identity and get_thread_identity()) or 8
    setthreadidentity(2)
    local inventory = ClientData.get("inventory")
    if inventory and inventory["pets"] then
        inventory["pets"][uniqueId] = itemData
    end
    setthreadidentity(identity)

    _spawnerPets[uniqueId] = { data = itemData, model = nil }
    if not item.top_of_inventory then      -- spawner pets only (pets received in a trade are not "spawned")
        _G._spawnedUids = _G._spawnedUids or {}
        _G._spawnedUids[uniqueId] = itemId
        _G._lastSpawnTick = tick()
    end

    task.defer(function()
        pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)
    end)

    return itemData
end

-- is a pet of this kind currently in the SPAWNED backpack? (Spawn All Variants / High Tiers / Smalls ...)
-- Pets that were deleted again don't count, and neither do pets received in a trade.
_G._isSpawnedKind = function(kind)
    if not kind or not _G._spawnedUids then return false end
    local inv = ClientData.get("inventory")
    local pets = inv and inv.pets
    for uid, k in pairs(_G._spawnedUids) do
        if k == kind then
            if pets and pets[uid] then return true end
        end
    end
    return false
end
_G._firstSpawnedOfKind = function(kind, skip)
    if not kind or not _G._spawnedUids then return nil end
    local inv = ClientData.get("inventory")
    local pets = inv and inv.pets
    if not pets then return nil end
    for uid, k in pairs(_G._spawnedUids) do
        if k == kind and pets[uid] and not (skip and skip[uid]) then return pets[uid] end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════════
--  REAL pets (your actual game pets) vs fake ones (spawned / received / spinner = anything in _spawnerPets).
--  The backpack lists higher newness_order first. Spawned pets reach ~6e7 and mock-received pets use 1e9+,
--  so real pets (small server numbers) used to sink to the bottom. A background sweep lifts every real pet
--  to 5e8 + its original order (above spawned pets, below freshly received ones), so new real-trade pets
--  also land on top. Real pets sent in a mock trade with "Remove Real Pets" OFF get a negative order = bottom.
--  Own function scope: no main-chunk locals.
-- ════════════════════════════════════════════════════════════════════════
do
local function _realPetOrderSetup()
    _G._realSweepGen = (_G._realSweepGen or 0) + 1
    local GEN = _G._realSweepGen
    local LIFT = 500000000
    _G._realBottom = _G._realBottom or {}      -- uid -> forced (negative) newness_order
    _G._realBottomSeq = _G._realBottomSeq or 0

    local function livePets()
        local inv = ClientData.get("inventory")
        return inv and inv.pets
    end
    local function isRealPet(uid)
        if not uid then return false end
        local pets = livePets()
        return pets ~= nil and pets[uid] ~= nil and not _spawnerPets[uid]
    end
    _G._isRealPet = isRealPet

    local function refresh()
        task.defer(function() pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end) end)
    end
    local function setOrder(pet, value)
        local identity = (get_thread_identity and get_thread_identity()) or 8
        pcall(setthreadidentity, 2)
        local ok = pcall(function() pet.newness_order = value end)
        pcall(setthreadidentity, identity)
        return ok
    end

    -- sent real pet that you keep (Remove Real Pets OFF): park it at the very bottom
    _G._realPetToBottom = function(uid)
        local pets = livePets()
        local pet = pets and pets[uid]
        if not pet or _spawnerPets[uid] then return end
        _G._realBottomSeq = _G._realBottomSeq + 1
        local v = -_G._realBottomSeq
        _G._realBottom[uid] = v
        setOrder(pet, v)
        refresh()
    end

    local function sweep()
        local pets = livePets()
        if not pets then return end
        local changed = false
        for uid, pet in pairs(pets) do
            if type(pet) == "table" and not _spawnerPets[uid] then
                local n = pet.newness_order
                local forced = _G._realBottom[uid]
                if forced then
                    if n ~= forced and setOrder(pet, forced) then changed = true end
                elseif type(n) == "number" and n < LIFT then
                    if setOrder(pet, LIFT + n) then changed = true end
                end
            end
        end
        if changed then refresh() end
    end

    task.spawn(function()
        while _G._realSweepGen == GEN and _G.MockTradeRunning do
            pcall(sweep)
            task.wait(1)
        end
    end)
end
local _rok, _rerr = pcall(_realPetOrderSetup)
if not _rok then warn("[RealPetOrder] " .. tostring(_rerr)) end
end

local function _removeFromInventory(uid)
    local identity = (get_thread_identity and get_thread_identity()) or 8
    setthreadidentity(2)
    local inventory = ClientData.get("inventory")
    if inventory and inventory.pets then
        inventory.pets[uid] = nil
    end
    setthreadidentity(identity)
    if _spawnerPets[uid] then
        if _spawnerPets[uid].model then _spawnerPets[uid].model:Destroy() end
        _spawnerPets[uid] = nil
    end
    -- Remove from BackpackApp hidden items so BackpackItemHider doesn't hit nil
    pcall(function()
        local ba = UIManager and UIManager.apps and UIManager.apps.BackpackApp
        if ba and ba.hidden_items then
            for tag, tbl in pairs(ba.hidden_items) do
                if type(tbl) == "table" then tbl[uid] = nil end
            end
        end
        if ba and ba.remove_item_unique_hidden then
            ba:remove_item_unique_hidden(uid, "MockTradeApp")
        end
    end)
    if _G._removeWrapper then pcall(_G._removeWrapper, uid) end
end

-- The game's search checks rp_name (our random names like "Frost") which causes
task.defer(function()
    local BackpackApp = UIManager.apps.BackpackApp
    if not BackpackApp then return end

    -- Guard check_if_item_hidden against nil items (fake pets removed from inventory
    -- but still referenced in hidden_items table causes BackpackItemHider crash)
    -- Guard check_if_item_hidden against nil
    if BackpackApp.check_if_item_hidden then
        local _origCheckHidden = BackpackApp.check_if_item_hidden
        BackpackApp.check_if_item_hidden = function(self, item_data)
            if not item_data then return false end
            local ok, result = pcall(_origCheckHidden, self, item_data)
            return ok and result or false
        end
    end

    -- Guard _render_category_async so any remaining crashes don't break the backpack
    if BackpackApp._render_category_async then
        local _origRender = BackpackApp._render_category_async
        BackpackApp._render_category_async = function(self, ...)
            local ok, err = pcall(_origRender, self, ...)
            if not ok and not tostring(err):find("event_name") and not tostring(err):find("is_hidden_from_backpack") then
                warn("[BackpackApp] _render_category_async:", err)
            end
        end
    end

    if not BackpackApp.is_filtered_out then return end
    local _origFilteredOut = BackpackApp.is_filtered_out
    BackpackApp.is_filtered_out = function(self, item_data)
        if item_data and item_data.properties and _spawnerPets[item_data.unique] then
            local savedRpName = item_data.properties.rp_name
            -- Temporarily swap rp_name with the real pet species name for search matching
            local realName = IDB and IDB.pets
                and IDB.pets[item_data.id]
                and IDB.pets[item_data.id].name
                or savedRpName
            item_data.properties.rp_name = realName
            local result = _origFilteredOut(self, item_data)
            item_data.properties.rp_name = savedRpName -- restore immediately
            return result
        end
        return _origFilteredOut(self, item_data)
    end
end)

local mockState = {
    active               = false,
    trade                = nil,
    isAddingItem         = false,
    tradeCompleting      = false,
    scamWarningShown     = false,
    blockedTradeRequests = {},
    tradeHistory         = {},
    addedTradeIds        = {},
    originalFunctions    = {},
    spectatorLoop        = nil,   -- coroutine handle for spectator simulation
    spectatorReactionsEnabled = true,
}
_G._mockState = mockState  -- so the Auto-Offer engine can skip our mock showcase trades

-- De-confirm both offers and bump the offer version (revert to negotiation stage).
local function resetTradeNegotiation()
    mockState.trade.sender_offer.negotiated    = false
    mockState.trade.recipient_offer.negotiated = false
    if mockState.trade.current_stage == "confirmation" then
        mockState.trade.current_stage             = "negotiation"
        mockState.trade.sender_offer.confirmed    = false
        mockState.trade.recipient_offer.confirmed = false
    end
    mockState.trade.offer_version = mockState.trade.offer_version + 1
end

do local function storeOriginalFunctions()
    local funcs = {
        "_get_local_trade_state",
        "_overwrite_local_trade_state",
        "_change_local_trade_state",
        "_get_my_offer",
        "_get_partner_offer",
        "_get_my_player",
        "_get_partner",
        "_get_current_trade_stage",
        "_on_accept_pressed",
        "_on_confirm_pressed",
        "_on_unaccept_pressed",
        "_decline_trade",
        "_add_item_to_my_offer",
        "_remove_item_from_my_offer",
        "_lock_trade_for_appropriate_time",
        "_get_lock_time",
        "refresh_all",
        "_evaluate_trade_fairness",
        "_show_scam_victim_warning",
        "_show_scam_perpetrator_warning",
    }
    for _, name in ipairs(funcs) do
        if TradeApp[name] then
            mockState.originalFunctions[name] = TradeApp[name]
        end
    end
end
storeOriginalFunctions()

end local stopSpectatorAndReactionLoops  -- hoisted so it's visible outside this do block
local startSpectatorLoop             -- hoisted so it's visible outside this do block
do

-- Cached references grabbed from _initialize_spectate's upvalues
-- u467 = ReactionFrame, u468 = ReactionTemplate (detached), u41 = reaction asset IDs
local _reactionFrame    = nil
local _reactionTemplate = nil

-- Hook _initialize_spectate so we capture the exact template and frame
-- that the real game uses — same upvalues as u483 in TradeApp source
local _origInitSpectate = TradeApp._initialize_spectate
TradeApp._initialize_spectate = function(self, ...)
    local result = _origInitSpectate(self, ...)
    safeCall(function()
        _reactionFrame    = self.spectate_frame:FindFirstChild("ReactionFrame")
        -- Template was detached (Parent = nil) by _initialize_spectate
        if _reactionFrame then
            -- Try to find it still parented (race condition window)
            _reactionTemplate = _reactionFrame:FindFirstChild("ReactionTemplate")
            if not _reactionTemplate then
                -- Reconstruct matching the real ReactionTemplate exactly
                _reactionTemplate                        = Instance.new("ImageLabel")
                _reactionTemplate.Name                   = "ReactionTemplate"; _reactionTemplate.BackgroundTransparency = 1
                _reactionTemplate.ImageTransparency      = 1; _reactionTemplate.Size                   = UDim2.fromScale(0, 0)
                _reactionTemplate.Position               = UDim2.fromScale(0, 0); _reactionTemplate.AnchorPoint            = Vector2.new(0.5, 0.5)
                _reactionTemplate.ZIndex                 = 5
            end
        end
    end)
    return result
end

local _Spring  = load('Spring')
local _Promise = load('package:Promise')

-- The real template size from the actual GUI asset.
local REACTION_SIZE = UDim2.fromOffset(48, 48)

local function _spawnReaction(imageId)
    -- Use the captured frame from _initialize_spectate, same as u467/u468 in source
    local rf = _reactionFrame
    local tmpl = _reactionTemplate

    -- Fallback: search GUI tree (covers case where trade opened before hook fired)
    if not rf and TradeApp.spectate_frame then
        rf = TradeApp.spectate_frame:FindFirstChild("ReactionFrame")
    end
    if not rf then
        local tradeGui = Players.LocalPlayer.PlayerGui:FindFirstChild("TradeApp")
        if tradeGui then
            for _, desc in ipairs(tradeGui:GetDescendants()) do
                if desc.Name == "ReactionFrame" and desc:IsA("Frame") then
                    rf = desc
                    break
                end
            end
        end
    end
    if not rf then return end

    -- Clone from template exactly like u483 does
    local emoji
    if tmpl then
        emoji = tmpl:Clone()
    else
        emoji = Instance.new("ImageLabel")
        emoji.BackgroundTransparency = 1
        emoji.AnchorPoint            = Vector2.new(0.5, 0.5)
    end

    -- Set up exactly as u483 does in the source
    emoji.Image             = imageId; emoji.Parent            = rf           -- parent FIRST like u483 does
    emoji.ImageTransparency = 1; emoji.Size              = UDim2.fromScale(0, 0)  -- start at 0 size, tween to real size

    -- Tween in — matches u16.new(u470, TweenInfo.new(0.4, Sine, In), {ImageTransparency=0, Size=u468.Size})
    TweenService:Create(emoji, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { ImageTransparency = 0, Size              = REACTION_SIZE, }):Play()

    local rng       = Random.new()
    local totalDur  = rng:NextNumber(2, 3.5)
    local vertSpeed = rng:NextNumber(0.23, 0.29)
    local fadeStart = totalDur * rng:NextNumber(0.65, 0.8)
    local damping   = rng:NextNumber(0.35, 0.45)
    local frequency = rng:NextNumber(1.1, 1.25)
    local xGoal     = rng:NextNumber(0.1, 0.9)

    -- Spring starts at -0.5 (off-screen left) exactly like u477 in source
    -- this is what creates the "drizzy" sideways drift entry effect
    local spring = _Spring.new(damping, frequency, -0.5)
    spring:set_goal(xGoal)

    -- Position starts at bottom of ReactionFrame — emoji floats upward
    emoji.Position = UDim2.fromScale(-0.5, 1.0)

    local startTick = tick()
    local active    = {}

    local promise = _Promise.fromEvent(RunService.Heartbeat, function(dt)
        local elapsed = tick() - startTick
        if totalDur <= elapsed then return true end
        spring:update(dt)
        -- Exactly matches u470.Position = UDim2.fromScale(v482, v481) in source
        local newY = emoji.Position.Y.Scale - vertSpeed * dt
        local newX = spring:get_position()
        emoji.Position = UDim2.fromScale(newX, newY)
        if fadeStart <= elapsed then
            emoji.ImageTransparency = (elapsed - fadeStart) / (totalDur - fadeStart)
        end
        return false
    end)

    promise:finally(function()
        if emoji and emoji.Parent then emoji:Destroy() end
    end)
end

do
    -- Reactions now come from CloudValues, same as TradeApp uses
    local _reactions = nil
    pcall(function()
        local CloudValues = require(game.ReplicatedStorage.ClientModules.CloudValues)
        local r = CloudValues:getValue("player_chat", "trade_spectate_reactions")
        if type(r) == "table" and #r > 0 then _reactions = r end
    end)
    if not _reactions then
        _reactions = { "rbxassetid://14265113844", "rbxassetid://14265113687", "rbxassetid://14263448076", "rbxassetid://14265134988", "rbxassetid://14265113338", "rbxassetid://14265113443", "rbxassetid://14265113556", }
    end
    _G.EmojiSystem = {
        reactions = _reactions,
        _active   = {}
    }
end

_G.EmojiSystem.display = function(index)
    local r = _G.EmojiSystem.reactions
    if not r or not r[index] then return end
    if not mockState.active or not mockState.trade or not mockState.spectatorReactionsEnabled then return end
    if not mockState.trade.subscriber_count or mockState.trade.subscriber_count < 1 then return end
    pcall(_spawnReaction, r[index])
end

task.spawn(function()
    while true do
        task.wait(1 / CONFIG.REACTIONS_PER_SECOND)
        local r = _G.EmojiSystem and _G.EmojiSystem.reactions
        if r and #r > 0 and mockState.active and mockState.trade
            and mockState.spectatorReactionsEnabled
            and mockState.trade.subscriber_count and mockState.trade.subscriber_count > 0 then
            _G.EmojiSystem.display(math.random(1, #r))
        end
    end
end)
-- Always ramps 1, 2, 3 first (or 1, 2 if target < 3).
local _spectatorLoopId = 0  -- incremented each time loop starts, old loops self-invalidate

startSpectatorLoop = function()
    _spectatorLoopId = _spectatorLoopId + 1
    local myId = _spectatorLoopId
    mockState.spectatorLoop = true

    task.spawn(function()
        local current = 0

        local function applyCount()
            if myId ~= _spectatorLoopId then return end  -- stale loop, discard
            if mockState.trade then
                mockState.trade.subscriber_count = current
                pcall(function() TradeApp:_overwrite_local_trade_state(mockState.trade) end)
                pcall(function() TradeApp:refresh_all() end)
                pcall(function()
                    if TradeApp.spectate_frame then
                        TradeApp.spectate_frame.Visible = current > 0
                        if current > 0 then
                            TradeApp:_update_spectator_count(mockState.trade)
                        end
                    end
                end)
            end
        end

        while myId == _spectatorLoopId and mockState.spectatorLoop and mockState.active do
            local target = CONFIG.SPECTATOR_COUNT

            if target <= 0 then
                if current > 0 then
                    current = 0
                    applyCount()
                end
                task.wait(2)
                continue
            end

            task.wait(math.random(3, 7))
            if myId ~= _spectatorLoopId or not mockState.spectatorLoop or not mockState.active then break end
            target = CONFIG.SPECTATOR_COUNT

            local driftFloor = math.max(1, target - math.floor(target * 0.4))

            if current < math.min(3, target) then
                current = current + 1
            elseif current < target then
                local choices = {-1, 1, 1, 1}
                current = math.clamp(current + choices[math.random(1, #choices)], driftFloor, target)
            else
                local choices = {-2, -1, -1, 1, 1}
                local next = current + choices[math.random(1, #choices)]
                if next > target then next = current - 1 end
                current = math.clamp(next, driftFloor, target)
            end

            applyCount()
        end
    end)
end

stopSpectatorAndReactionLoops = function()
    mockState.spectatorLoop = false
end

end -- SPECTATOR SIMULATION do block

local mockPartner

local function createMockPartner()
    return setmetatable({ Name        = CONFIG.PARTNER_NAME, DisplayName = CONFIG.PARTNER_NAME, UserId      = CONFIG.PARTNER_USER_ID or 0, }, {
        __index = function(_, k)
            if k == "Parent" then return Players end
            if k == "IsA" then return function(_, cls) return cls == "Player" end end
        end,
        __tostring = function() return CONFIG.PARTNER_NAME end,
    })
end

local function createMockTrade()
    return {
        trade_id                    = "MOCK_" .. tick(),
        sender                      = Players.LocalPlayer,
        recipient                   = mockPartner,
        sender_offer                = {
            items       = {},
            player_name = Players.LocalPlayer.Name,
            negotiated  = false,
            confirmed   = false,
        },
        recipient_offer             = {
            items       = {},
            player_name = CONFIG.PARTNER_NAME,
            negotiated  = false,
            confirmed   = false,
        },
        current_stage               = "negotiation",
        offer_version               = 1,
        sender_has_trade_license    = true,
        recipient_has_trade_license = true,
        busy_indicators             = {},
        subscriber_count            = 0,  -- spectator loop ramps from 0
    }
end

-- GROUP RANK BADGE HOOK
local _cachedPartnerRank = 0

task.spawn(function()
    local ok, GroupRankHelper = pcall(load, "GroupRankHelper")
    if not ok or not GroupRankHelper then return end

    -- Keep get_rank_from_player hook as fallback
    local _origGetRankFromPlayer = GroupRankHelper.get_rank_from_player
    GroupRankHelper.get_rank_from_player = function(player, groupId)
        if mockState.active and mockState.trade then
            return _cachedPartnerRank
        end
        return _origGetRankFromPlayer(player, groupId)
    end
end)

-- Hook ClientData.get_server so promise_get_verified_status returns the right tag
do
    local _origGetServer = ClientData.get_server
    ClientData.get_server = function(player, key, ...)
        -- Self badge: inject in ALL contexts (trades, nametag, profile, everywhere)
        if key == "player_tags" and CONFIG.SELF_BADGE_TAG and CONFIG.SELF_BADGE_TAG ~= "" then
            local reqId = player and (type(player) == "table" and player.UserId or
                          (type(player) == "userdata" and player.UserId))
            if reqId and reqId == Players.LocalPlayer.UserId then
                return { CONFIG.SELF_BADGE_TAG }
            end
        end
        -- player_tags: return tag for mock partner
        if key == "player_tags" and mockState.active and mockState.trade then
            local partnerId = player and (type(player) == "table" and player.UserId or
                              (type(player) == "userdata" and player.UserId))
            -- PARTNER_TAG: inject for any queried player during mock trade
            -- (covers the case where PARTNER_USER_ID isn't resolved yet)
            if CONFIG.PARTNER_TAG and CONFIG.PARTNER_TAG ~= "" and partnerId then
                return { CONFIG.PARTNER_TAG }
            end
            if partnerId and partnerId == CONFIG.PARTNER_USER_ID and CONFIG.PARTNER_USER_ID ~= 0 then
                -- Fall back to cached rank from GroupRankHelper
                local GRH = pcall(load, "GroupRankHelper") and load("GroupRankHelper")
                if GRH and _cachedPartnerRank and _cachedPartnerRank > 0 then
                    local tagOk, tag = pcall(function() return GRH.get_tag_from_rank(_cachedPartnerRank) end)
                    if tagOk and tag then
                        local iconOk, icon = pcall(function() return GRH.get_icon_from_tag(tag) end)
                        if iconOk and icon then
                            return { tag }
                        end
                    end
                end
                return {}
            end
        end

        -- in_active_trade: tell PlayerProfileApp our mock partner is in a trade with us
        -- so it shows "Suggest" button instead of "Trade" on their profile
        if key == "in_active_trade" and mockState.active and mockState.trade then
            local partnerId = player and (type(player) == "table" and player.UserId or
                              (type(player) == "userdata" and player.UserId))
            if partnerId and partnerId == CONFIG.PARTNER_USER_ID then
                return true
            end
        end

        return _origGetServer(player, key, ...)
    end
end

-- _chatIntroShown declared here so it's visible to both hookTradeFunctions and the render hook
local _chatIntroShown = false
-- Per-trade intro dedup state lives on _G (avoids adding main-chunk locals; see render hook below)
_G._introSeen = _G._introSeen or {}

-- HOOK TRADEAPP FUNCTIONS
local function notifyProfileAppTradeState(active)
    safeCall(function()
        local ProfileApp = UIManager.apps.PlayerProfileApp
        if not ProfileApp then return end
        if not (ProfileApp.player_profile and ProfileApp.player) then return end
        if ProfileApp.player.UserId ~= CONFIG.PARTNER_USER_ID then return end
        local inTradeWithMe = false
        if active then
            safeCall(function()
                inTradeWithMe = TradeApp:_get_partner() ~= nil
            end)
        end
        ProfileApp:set_header_info({ in_trade         = active, in_trade_with_me = inTradeWithMe, })
    end)
end

do local function hookTradeFunctions()
task.spawn(function()
    task.wait(0.1)
    local PlayerText = load('new:PlayerText')
    if not PlayerText then return end
    local original_can_i_chat = PlayerText.can_i_chat_with_player
    local original_can_use_emojis = PlayerText.can_player_use_emojis
    PlayerText.can_i_chat_with_player = function(player, ...)
        if mockState.active then return true end
        return original_can_i_chat(player, ...)
    end
    PlayerText.can_player_use_emojis = function(...)
        if mockState.active then return true end
        return original_can_use_emojis(...)
    end
end)

    TradeApp._get_local_trade_state = function(self)
        if mockState.active and mockState.trade then
            return TableUtil.deep_copy(mockState.trade)
        end
        return mockState.originalFunctions._get_local_trade_state(self)
    end

    TradeApp._overwrite_local_trade_state = function(self, newState)
        if mockState.active then
            if newState then
                -- Capture old state BEFORE overwriting so _on_local_trade_state_changed
                local oldState = self.local_trade_state
                mockState.trade              = newState
                self.local_trade_state       = newState
                mockState.trade.subscriber_count = mockState.trade.subscriber_count or 0
                if self._on_local_trade_state_changed then
                    self:_on_local_trade_state_changed(newState, newState)
                end
                if self.refresh_all then self:refresh_all() end
            else
                mockState.trade  = nil; mockState.active = false
                mockState.scamWarningShown = false
                self.local_trade_state = nil
                lastAddedHighTier = nil
                _chatIntroShown = false
                stopSpectatorAndReactionLoops()
                if _G._autoChatStop then pcall(_G._autoChatStop) end   -- (the local is defined further down the file, so go through _G)
                notifyProfileAppTradeState(false)
                -- Sync CONFIG from textbox in case user changed name during trade
                task.defer(function()
                    if partnerBox and partnerBox.Text ~= "" then
                        updatePartnerFromUsername(partnerBox.Text)
                    end
                end)
            end
        else
            return mockState.originalFunctions._overwrite_local_trade_state(self, newState)
        end
    end

    TradeApp._get_my_offer = function(self)
        local state = self:_get_local_trade_state()
        if mockState.active and state then
            if Players.LocalPlayer == state.sender then
                return state.sender_offer, "sender_offer"
            else
                return state.recipient_offer, "recipient_offer"
            end
        end
        return mockState.originalFunctions._get_my_offer(self)
    end

    TradeApp._get_partner_offer = function(self)
        local state = self:_get_local_trade_state()
        if mockState.active and state then
            if Players.LocalPlayer == state.sender then
                return state.recipient_offer, "recipient_offer"
            else
                return state.sender_offer, "sender_offer"
            end
        end
        return mockState.originalFunctions._get_partner_offer(self)
    end

    TradeApp._get_my_player = function(self)
        if mockState.active and mockState.trade then
            return Players.LocalPlayer
        end
        return mockState.originalFunctions._get_my_player(self)
    end

    TradeApp._get_partner = function(self)
        if mockState.active and mockState.trade then
            return mockPartner
        end
        return mockState.originalFunctions._get_partner(self)
    end

    TradeApp._get_current_trade_stage = function(self)
        if mockState.active and mockState.trade then
            return mockState.trade.current_stage
        end
        return mockState.originalFunctions._get_current_trade_stage(self)
    end

    local function recursiveMerge(target, source)
        for k, v in pairs(source) do
            if type(v) == "table" and type(target[k]) == "table" then
                recursiveMerge(target[k], v)
            else
                target[k] = v
            end
        end
        return target
    end

    TradeApp._change_local_trade_state = function(self, changes, useReplace)
        if mockState.active then
            local current = self:_get_local_trade_state()
            local merged  = useReplace and changes or recursiveMerge(current, changes)
            self:_overwrite_local_trade_state(merged)
        else
            return mockState.originalFunctions._change_local_trade_state(self, changes, useReplace)
        end
    end

    TradeApp._get_lock_time = function(self)
        if mockState.active and mockState.trade then
            if self:_get_current_trade_stage() == "negotiation" then
                return CONFIG.NEGOTIATION_LOCK or 5
            end
            local count = #mockState.trade.sender_offer.items + #mockState.trade.recipient_offer.items
            return math.clamp((CONFIG.CONFIRMATION_LOCK_PER_ITEM or 3) * count, 5, 15)
        end
        return mockState.originalFunctions._get_lock_time(self)
    end

    TradeApp._lock_trade_for_appropriate_time = function(self)
        if mockState.active then
            if self.lock_countdown then
                self.lock_countdown:stop()
                self.lock_countdown:set_duration(self:_get_lock_time())
                self.lock_countdown:start()
            end
        else
            return mockState.originalFunctions._lock_trade_for_appropriate_time(self)
        end
    end

    TradeApp._on_accept_pressed = function(self)
        if mockState.active and mockState.trade then
            local _, key = self:_get_my_offer()

            mockState.trade[key].negotiated = true
            mockState.trade.offer_version = (mockState.trade.offer_version or 1) + 1
            TradeApp:_overwrite_local_trade_state(mockState.trade)
            self:refresh_all()

            -- Partner accepts after delay, then enter confirmation
            task.delay(CONFIG.AUTO_ACCEPT_DELAY, function()
                if not mockState.active or not mockState.trade then return end
                local partnerKey = (key == "sender_offer") and "recipient_offer" or "sender_offer"
                mockState.trade[partnerKey].negotiated = true
                mockState.trade.offer_version = (mockState.trade.offer_version or 1) + 1

                if mockState.trade.sender_offer.negotiated and mockState.trade.recipient_offer.negotiated then
                    mockState.trade.current_stage = "confirmation"
                    TradeApp:_overwrite_local_trade_state(mockState.trade)
                    if TradeApp.refresh_all then TradeApp:refresh_all() end

                    -- Fire fairness check and countdown directly — do not rely on
                    pcall(function() TradeApp:_evaluate_trade_fairness() end)
                    if TradeApp.lock_countdown then
                        TradeApp.lock_countdown:stop()
                        TradeApp.lock_countdown:set_duration(TradeApp:_get_lock_time())
                        TradeApp.lock_countdown:start()
                    end
                else
                    TradeApp:_overwrite_local_trade_state(mockState.trade)
                    if TradeApp.refresh_all then TradeApp:refresh_all() end
                end
            end)
        else
            return mockState.originalFunctions._on_accept_pressed(self)
        end
    end

    TradeApp._on_unaccept_pressed = function(self) --PLACEHOLDER
        if mockState.active and mockState.trade then
            local _, key = self:_get_my_offer()
            self:_change_local_trade_state({ [key] = { negotiated = false } })
            self:refresh_all()
        else
            return mockState.originalFunctions._on_unaccept_pressed(self)
        end
    end

    TradeApp._on_confirm_pressed = function(self)
        if mockState.active and mockState.trade then
            local _, key = self:_get_my_offer()
            mockState.trade[key].confirmed = true
            mockState.trade.offer_version = (mockState.trade.offer_version or 1) + 1
            TradeApp:_overwrite_local_trade_state(mockState.trade)
            self:refresh_all()

            task.delay(CONFIG.AUTO_CONFIRM_DELAY, function()
                if not mockState.active or not mockState.trade then return end
                local partnerKey = (key == "sender_offer") and "recipient_offer" or "sender_offer"
                mockState.trade[partnerKey].confirmed = true
                mockState.trade.offer_version = (mockState.trade.offer_version or 1) + 1
                TradeApp:_overwrite_local_trade_state(mockState.trade)
                if TradeApp.refresh_all then TradeApp:refresh_all() end

                -- Both confirmed — spin the arrow exactly like the real game does
                -- (TradeApp source: refresh_all detects both confirmed and calls
                pcall(function() TradeApp:_set_confirmation_arrow_rotating(true) end)

                -- Real game processes on server for ~3s before closing
                -- Mirror that delay so it feels identical
                task.wait(3)
                if not mockState.active then return end

                -- Capture offers BEFORE clearing trade state
                local myOffer      = mockState.trade.sender_offer
                local partnerOffer = mockState.trade.recipient_offer
                if mockState.trade.recipient == Players.LocalPlayer then
                    myOffer, partnerOffer = partnerOffer, myOffer
                end

                -- Stop arrow, close trade, show success hint
                pcall(function() TradeApp:_set_confirmation_arrow_rotating(false) end)
                stopSpectatorAndReactionLoops()
                mockState.active = false
                mockState.trade  = nil
                TradeApp.local_trade_state = nil
                UIManager.set_app_visibility("TradeApp", false)
                -- Sync CONFIG from textbox in case user changed name during trade
                task.defer(function()
                    if partnerBox and partnerBox.Text ~= "" then
                        updatePartnerFromUsername(partnerBox.Text)
                    end
                end)

                -- Apply trade results to inventory:
                -- Remove items we gave away, add items we received

                -- Remove our sent items from inventory (only if toggle is ON)
                -- Spawned pets follow "Remove Sent Pets"; REAL pets follow "Remove Real Pets"
                -- (OFF = the real pet stays in your backpack but moves to the very bottom).
                if myOffer then
                    for _, item in ipairs(myOffer.items or {}) do
                        local isReal = _G._isRealPet and _G._isRealPet(item.unique)
                        local doRemove
                        if isReal then doRemove = (CONFIG.REMOVE_REAL_PETS ~= false) else doRemove = CONFIG.REMOVE_SENT_PETS end
                        if doRemove then
                            if _G._realBottom then _G._realBottom[item.unique] = nil end
                            safeCall(function()
                                updateData("inventory", function(inv)
                                    if inv.pets then inv.pets[item.unique] = nil end
                                    return inv
                                end)
                            end)
                        elseif isReal and _G._realPetToBottom then
                            safeCall(function() _G._realPetToBottom(item.unique) end)
                        end
                    end
                end

                -- Add partner's items to our inventory (only if toggle is ON)
                if CONFIG.RECEIVE_PETS and partnerOffer then
                    -- walk the offer backwards so its first pet is added last = ends up topmost
                    local _recvItems = partnerOffer.items or {}
                    for _ri = #_recvItems, 1, -1 do
                        local item = _recvItems[_ri]
                        local ok, err = pcall(function()
                            local newItem = {
                                unique     = HttpService:GenerateGUID(false),
                                category   = "pets",
                                kind       = item.kind,
                                id         = item.kind,
                                top_of_inventory = true,
                                properties = ((_G._isEggKind and _G._isEggKind(item.kind)) and {} or { neon               = item.properties and item.properties.neon      or false, mega_neon          = item.properties and item.properties.mega_neon or false, flyable            = item.properties and item.properties.flyable   or false, rideable           = item.properties and item.properties.rideable  or false, age                = item.properties and item.properties.age       or 1, ailments_completed = 0, pet_trick_level    = 0, rp_name            = generatePetName(item.kind), }),
                            }
                            _addToInventory(newItem)
                        end)
                    end
                end

                pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)

                -- Record this mock trade in history so it appears in Trade History
                safeCall(function()
                    local LocalPlayer = Players.LocalPlayer
                    local record = {
                        trade_id        = "MOCK_" .. HttpService:GenerateGUID(false),
                        timestamp       = os.time(),
                        sender_user_id  = LocalPlayer.UserId,
                        sender_name     = LocalPlayer.Name,
                        recipient_user_id = CONFIG.PARTNER_USER_ID,
                        recipient_name  = CONFIG.PARTNER_NAME,
                        sender_items    = myOffer   and myOffer.items   or {},
                        recipient_items = partnerOffer and partnerOffer.items or {},
                        reported        = false,
                        reverted        = nil,
                    }
                    -- Check for duplicate (same trade_id)
                    local isDupe = false
                    for _, existing in ipairs(_mockTradeHistory) do
                        if existing.trade_id == record.trade_id then isDupe = true; break end
                    end
                    if not isDupe then
                        table.insert(_mockTradeHistory, 1, record)
                        -- Bust the real cached history so it refetches from server on next open
                        if TradeHistoryApp then
                            TradeHistoryApp.cached_trade_history = nil
                        end
                    end
                end)

                -- Store AMVgg value for auto spin using already-cached value display calc
                do
                    local val = _G._lastPartnerAmvgg or 0
                    if val > 0 then
                        local spins = math.floor(val / 0.1 + 0.5)
                        if _G._maxSpinsEnabled then
                            spins = math.min(spins, _G._maxSpinsValue)
                        end
                        if spins > 0 then
                            _G._autoSpinPending = (_G._autoSpinPending or 0) + spins
                            _G._autoSpinTriggered = false
                            _G._autoSpinWaitingForTrade = true
                            -- remember how many pets partner gave so we wait for all of them
                            _G._autoSpinRequiredPets = partnerOffer and #partnerOffer.items or 1
                        end
                    end
                end

                -- "The trade was successful!" hint shown by real game after completion
                local HintApp = UIManager.apps.HintApp
                if HintApp then
                    HintApp:hint({ text       = "The trade was successful!", length     = 5, overridable = true, yields     = false, })
                end
            end)
        else
            return mockState.originalFunctions._on_confirm_pressed(self)
        end
    end

    TradeApp._add_item_to_my_offer = function(self)
        if mockState.active and mockState.trade then
            if mockState.isAddingItem then return end
            mockState.isAddingItem = true
            if not TradeApp.can_suggest_removal_items then
                TradeApp.can_suggest_removal_items = {}
            end
            local pickedItem = BackpackApp:pick_item({
                keep_cached_scroll_positions_on_open = true,
                allow_callback = function() return true end,
            })
            if pickedItem then
                local already = false
                for _, item in ipairs(mockState.trade.sender_offer.items) do
                    if item.unique == pickedItem.unique then already = true; break end
                end
                if not already and #mockState.trade.sender_offer.items < 18 then
                    table.insert(mockState.trade.sender_offer.items, pickedItem)
                    resetTradeNegotiation()
                    TradeApp.can_suggest_removal_items[pickedItem.unique] = pickedItem
                    self:_overwrite_local_trade_state(mockState.trade)
                    self:_lock_trade_for_appropriate_time()
                    if BackpackApp.set_item_unique_hidden then
                        BackpackApp:set_item_unique_hidden(pickedItem.unique, self.ClassName)
                    end
                    mockState.scamWarningShown = false
                end
            end
            mockState.isAddingItem = false
        else
            return mockState.originalFunctions._add_item_to_my_offer(self)
        end
    end

    TradeApp._remove_item_from_my_offer = function(self, item)
        if mockState.active and mockState.trade then
            local items = mockState.trade.sender_offer.items
            for i, v in ipairs(items) do
                if v.unique == item.unique then
                    table.remove(items, i); break
                end
            end
            resetTradeNegotiation()
            self:_overwrite_local_trade_state(mockState.trade)
            self:_lock_trade_for_appropriate_time()
            if BackpackApp.reset_hidden_item_tag then
                BackpackApp:reset_hidden_item_tag(self.ClassName)
            end
            if TradeApp.can_suggest_removal_items then
                TradeApp.can_suggest_removal_items[item.unique] = nil
            end
        else
            return mockState.originalFunctions._remove_item_from_my_offer(self, item)
        end
    end

    -- Allow fairness evaluation and scam warnings during mock trades
    TradeApp._evaluate_trade_fairness = function(self)
        if mockState.scamWarningShown then return end
        return mockState.originalFunctions._evaluate_trade_fairness(self)
    end

    TradeApp._show_scam_victim_warning = function(self)
        if mockState.scamWarningShown then return end
        mockState.scamWarningShown = true
        return mockState.originalFunctions._show_scam_victim_warning(self)
    end

    TradeApp._show_scam_perpetrator_warning = function(self)
        if mockState.scamWarningShown then return end
        mockState.scamWarningShown = true
        return mockState.originalFunctions._show_scam_perpetrator_warning(self)
    end

    -- Keep spectate_frame visible when we have fake spectators
    -- _toggle_spectate(false) is called for non-spectators and hides it
    local _origToggleSpectate = TradeApp._toggle_spectate
    if _origToggleSpectate then
        TradeApp._toggle_spectate = function(self, spectating, ...)
            _origToggleSpectate(self, spectating, ...)
            if not spectating and mockState.active and mockState.trade
                and (mockState.trade.subscriber_count or 0) > 0 then
                if self.spectate_frame then
                    self.spectate_frame.Visible = true
                end
            end
        end
    end

    TradeApp._decline_trade = function(self, skipFireServer)
        if mockState.active then
            stopSpectatorAndReactionLoops()
            mockState.active           = false; mockState.trade            = nil
            mockState.scamWarningShown = false
            self.local_trade_state     = nil
            lastAddedHighTier          = nil
            _chatIntroShown            = false
            if self.lock_countdown then self.lock_countdown:stop() end
            UIManager.set_app_visibility("TradeApp", false)
            pcall(notifyProfileAppTradeState, false)
        else
            return mockState.originalFunctions._decline_trade(self, skipFireServer)
        end
    end
end

hookTradeFunctions()

-- Fix: intro fires exactly once per trade (old==new trick prevents game's own
-- _clear_chat + _show_intro_message from firing on every state update)
do
    local _startupShownForTrade = nil
    local _origShowIntro = TradeApp._show_intro_message
    if _origShowIntro then
        TradeApp._show_intro_message = function(self, ...)
            local result = _origShowIntro(self, ...)
            local state = self:_get_local_trade_state()
            local tid = state and state.trade_id
            if tid and _startupShownForTrade ~= tid then
                _startupShownForTrade = tid
            end
            return result
        end
    end
end

-- Block trade partner keybind (B key while in a mock or real trade)
do
    local _blockBindActive = true
    local UIS = game:GetService("UserInputService")
    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode ~= Enum.KeyCode.J then return end
        if not _blockBindActive then return end

        -- Get partner from mock trade or real trade state
        local target = nil
        pcall(function()
            if mockState.active and mockState.trade then
                -- Mock trade: use PARTNER_USER_ID to find real Player
                local partnerId = CONFIG.PARTNER_USER_ID
                if partnerId and partnerId ~= 0 then
                    target = Players:GetPlayerByUserId(partnerId)
                end
                if not target then
                    local partnerName = CONFIG.PARTNER_NAME
                    if partnerName and partnerName ~= "" then
                        target = Players:FindFirstChild(partnerName)
                    end
                end
            else
                -- Real trade: read active trade state
                local ts = ClientData.get("trade")
                if ts then
                    -- sender/recipient are Player objects
                    local partner
                    if ts.sender == Players.LocalPlayer then
                        partner = ts.recipient
                    else
                        partner = ts.sender
                    end
                    if partner and partner ~= Players.LocalPlayer then
                        target = partner
                    end
                end
            end
        end)

        if not target then return end

        -- Brief cooldown so holding B doesn't spam
        _blockBindActive = false
        task.delay(2, function() _blockBindActive = true end)

        -- silentBlockPlayer lives in Misc tab scope, accessed via _G
        local fn = _G._silentBlockPlayer
        if fn then
            task.spawn(fn, target)
        end
    end)
end

-- Force the admin nametag to show immediately on execution.
task.spawn(function()
    task.wait(0.5)
    -- Nudge char_wrappers so CharWrapperClient re-queries player_tags for all players
    pcall(function()
        local identity = get_thread_identity and get_thread_identity() or 8
        setthreadidentity(2)
        local wrappers = ClientData.get("char_wrappers") or {}
        local nudged = {}
        for i, w in ipairs(wrappers) do
            nudged[i] = table.clone(w)
        end
        ClientData.predict("char_wrappers", nudged)
        setthreadidentity(identity)
    end)
    -- Also nudge pet_char_wrappers for pet nametags
    pcall(function()
        local identity = get_thread_identity and get_thread_identity() or 8
        setthreadidentity(2)
        local wrappers = ClientData.get("pet_char_wrappers") or {}
        local nudged = {}
        for i, w in ipairs(wrappers) do
            nudged[i] = table.clone(w)
        end
        ClientData.predict("pet_char_wrappers", nudged)
        setthreadidentity(identity)
    end)
    task.wait(0.1)
    -- Trigger AilmentsClient refresh which also causes nametag re-render
    pcall(function()
        local AC = load("new:AilmentsClient")
        if AC and AC.on_ailments_changed then
            AC.on_ailments_changed(Players.LocalPlayer)
        end
    end)
end)

-- VERIFIED FRIEND HOOK
end local CONFIG_VERIFIED_FRIEND = true

do
    local FriendsClient = load("FriendsClient")
    if FriendsClient and FriendsClient.promise_get_is_friends_with then
        local _origIsFriends = FriendsClient.promise_get_is_friends_with
        FriendsClient.promise_get_is_friends_with = function(userId, ...)
            if CONFIG_VERIFIED_FRIEND and mockState.active then
                -- Return true for the partner regardless of whether UserId is resolved yet.
                if userId == CONFIG.PARTNER_USER_ID
                    or CONFIG.PARTNER_USER_ID == 0 then
                    local Promise = load("package:Promise")
                    return Promise.resolve(true)
                end
            end
            return _origIsFriends(userId, ...)
        end
    end
end

-- AUTO-DECLINE INCOMING TRADE REQUESTS DURING MOCK TRADE
task.spawn(function()
    task.wait(2) -- wait for TradeApp to finish initialising its connections
    local RouterClient = load("RouterClient")
    local remote = RouterClient.get_event("TradeAPI/TradeRequestReceived")
    if not remote then return end

    local ok, connections = pcall(getconnections, remote.OnClientEvent)
    if not ok or not connections then return end

    -- Add our handler BEFORE the original ones fire
    remote.OnClientEvent:Connect(function(requestingPlayer)
        if mockState.active then
            -- Disable originals so they don't also show a dialog
            for _, c in ipairs(connections) do
                pcall(function() c:Disable() end)
            end
            safeCall(function()
                RouterClient.get("TradeAPI/AcceptOrDeclineTradeRequest"):InvokeServer(requestingPlayer, false)
            end)
        end
        -- When not active, do nothing — originals handle it normally
    end)

    -- Re-enable originals whenever mock trade ends
    local _origDecline = TradeApp._decline_trade
    TradeApp._decline_trade = function(self, ...)
        for _, c in ipairs(connections) do
            pcall(function() c:Enable() end)
        end
        return _origDecline(self, ...)
    end
end)

-- BACKPACK / PROFILE SUGGESTION SYSTEM
-- Built from scratch using TradeApp source only.
do -- BACKPACK SUGGESTION
-- try_suggest_item   — checks backpack_access, requests it if nil
local RouterClient = load("RouterClient")
local DialogApp    = UIManager.apps.DialogApp

-- Suppress the game's "Trade request from <user> has expired!" popups when the Misc Page-2
-- toggle is on. The game spams these while we auto-decline lots of incoming requests during a
-- mock trade. Match on the text (username varies) and just swallow it — the game doesn't use
-- the return value. Only expired-trade dialogs match, so our own dialogs are unaffected.
if DialogApp and DialogApp.dialog and not DialogApp._expiredHooked then
    DialogApp._expiredHooked = true
    local _origDialog = DialogApp.dialog
    DialogApp.dialog = function(self, opts, ...)
        if _G._hideExpiredDialogs and type(opts) == "table" then
            local txt = (tostring(opts.text or "") .. " " .. tostring(opts.header or "")):lower()
            if txt:find("expired", 1, true) then
                return "Okay"
            end
        end
        return _origDialog(self, opts, ...)
    end
end

-- ════════════════════════════════════════════════════════════════════════
--  Fake partner backpack generator.
--  Composition: 50+ pets: 1 FR/NFR high tier, 2-4 MEGA exotics, a few mid tiers, the rest tiny pets.
--  Wrapped in do..end (exposes _G._genFakeBackpack) so it adds no main-chunk locals.
-- ════════════════════════════════════════════════════════════════════════
do
local function _fakeBackpackSetup()
-- the classic high tiers most players hold; these are rolled first
local FB_HIGH_CORE = {
    "Frost Dragon","Giraffe","Owl","Shadow Dragon","Bat Dragon","Haetae","Cryptid","Balloon Unicorn",
    "Parrot","Crow","Evil Unicorn","Blazing Lion","African Wild Dog","Giant Panda",
}
-- headline high tiers: ownership is controlled (~35% of players hold one, ~20% hold two or more)
local FB_HEADLINE = {
    "Giraffe","Owl","Bat Dragon","Shadow Dragon","Frost Dragon","Cryptid","Crow","Parrot","Haetae","Balloon Unicorn","Giant Panda",
}
-- random MEGA pets (always mega neon): sprinkled on top of the mega exotics
local FB_MEGA_RANDOM = {
    "Axolotl","Ghost Dog","Albino Monkey","Capybara","Jellyfish","Munchkin Cat","Puffin","Fallow Deer","Honey Badger",
    "Latte Kitsune","Lion Cub","Shark Puppy","Brown Bear","Candyfloss Chick","Nessie","Owlbear",
    "Glacier Moth","Irish Water Spaniel","Pig","Frost Fury",
}
-- small megas (~0.2-0.3 AMVGG). More are picked up automatically from AMVGG values in that range.
local FB_SMALL_MEGA = {
    "Ranger Beaver","Pretty Pony","Burger Bear","Hippogriff","Diamond King Penguin","Diamond Hamster",
}
local FB_HIGH = {
    "Bat Dragon","Shadow Dragon","Frost Dragon","Giraffe","Owl","Parrot","Crow",
    "Evil Unicorn","Blazing Lion","Balloon Unicorn","African Wild Dog","Giant Panda",
    "Dalmatian","Arctic Reindeer","Haetae","Cryptid","Orchid Butterfly","Diamond Butterfly",
    "Jekyll Hydra","Mermicorn","Monkey King","Undead Jousting Horse","Fairy Bat Dragon","Amethyst Penguin",
}
local FB_EXOTIC = {
    "Nessie","Owlbear","Lion Cub","Albino Monkey","Lavender Dragon","Pirate Ghost Capuchin Monkey",
    "Shark Puppy","Candicorn","Jellyfish","Munchkin Cat","Puffin","Fallow Deer","Brown Bear","Latte Kitsune",
    "Honey Badger","Capybara","Axolotl","Candyfloss Chick",
}
-- neon showcase pets: always rolled as neon (with random fly / ride)
local FB_NEON = {
    "Alicorn","Bush Elephant","Candicorn","Kangaroo","Turtle","Elephant",
    "Arctic Dusk Dragon","Pineapple Owl","Unicorn","Dragon","Griffin","Lion","Zebra","Rhino","Polar Bear","Flamingo",
    "Cheetah","Peacock","Llama","Crocodile","Dodo","Octopus","Toucan","Raven","Chocolate Chip Bat Dragon","Kitsune","Axolotl",
}
local FB_MID = {
    "Kangaroo","Turtle","Strawberry Shortcake Bat Dragon","Cow","Flamingo","Hedgehog",
    "Chocolate Chip Bat Dragon","Peppermint Penguin","Goose","Mini Pig","Hot Doggo","Pelican","Cabbit","Elephant","Sheeep","Goat",
}
local FB_TINY = {
    "King Bee","Ant","Goldfish","Bee","Ladybug","Mouse","Rat","Frog","Chick","Hamster","Chocolate Dutch Guinea Pig","Red Dutch Guinea Pig","Rabbit","Dragonfly","Spider","Scorpion","Lizard","Gecko","Chameleon","Bat","Starfish","Clownfish","Piranha","Pufferfish","Seagull","Robin","Chipmunk","Mosquito",
}

-- pets that must never show up in a generated backpack (lower case). Add names here to ban more.
local BANNED = { ["caterpillar"] = true }
-- substring bans: any pet whose lower-case name contains one of these is never generated
local BANNED_PARTS = { "tortoise" }
setmetatable(BANNED, { __index = function(_, k)
    if type(k) == "string" then
        for _, part in ipairs(BANNED_PARTS) do
            if k:find(part, 1, true) then return true end
        end
    end
    return nil
end })
local byName, kindName, randomKinds
local R = {}   -- resolved kind lists: R.high / R.exotic / R.mid / R.tiny

-- Player types: each generated backpack rolls one, so no two players look alike.
-- w = pick weight | ex/hi/neon/mid/rnd/tot = multipliers on the CONFIG.BACKPACK_* counts
-- mega = chance a high tier / neon showcase pet is MFR | dup = max extra copies of pets they already hold
-- egg = chance of holding a few eggs | old = chance a pet is already full grown
local ARCHETYPES = {
    { name = "regular",        w = 30, ex = 1,   hi = 1,   neon = 1,   mid = 1,   rnd = 1,   tot = 1,   mega = 0.05, dup = 1, egg = 0.15, old = 0.30 },
    { name = "whale",          w = 7,  ex = 2.2, hi = 3,   neon = 1.5, mid = 1,   rnd = 1.5, tot = 1.5, mega = 0.30, dup = 3, egg = 0.05, old = 0.85 },
    { name = "mega collector", w = 6,  ex = 2,   hi = 1.5, neon = 2,   mid = 0.7, rnd = 1,   tot = 1.2, mega = 0.50, dup = 2, egg = 0.05, old = 0.70 },
    { name = "neon farmer",    w = 14, ex = 0.4, hi = 0.5, neon = 2.6, mid = 1,   rnd = 1,   tot = 1.2, mega = 0.10, dup = 2, egg = 0.10, old = 0.70 },
    { name = "trader",         w = 12, ex = 1,   hi = 1.5, neon = 1,   mid = 2,   rnd = 1.6, tot = 1.6, mega = 0.08, dup = 4, egg = 0.20, old = 0.40 },
    { name = "event hoarder",  w = 8,  ex = 0.8, hi = 0.8, neon = 0.5, mid = 1,   rnd = 2.2, tot = 1.3, mega = 0.03, dup = 2, egg = 0.60, old = 0.20 },
    { name = "minimalist",     w = 12, ex = 1,   hi = 1,   neon = 0.5, mid = 0.3, rnd = 0.3, tot = 0.5, mega = 0.05, dup = 0, egg = 0.05, old = 0.60 },
    { name = "newbie",         w = 14, ex = 0,   hi = 0,   neon = 0.2, mid = 0.5, rnd = 0.6, tot = 0.4, mega = 0,    dup = 1, egg = 0.50, old = 0.00 },
}
local curA, curOld = ARCHETYPES[1], 0   -- the type being generated (read by rollNeonFlags / toProps)
-- n * mult, rounded up or down at random so 0.5 means "half the time one"
local function scale(n, mult)
    if mult <= 0 then return 0 end
    local v = n * mult
    local f = math.floor(v)
    if math.random() < v - f then f = f + 1 end
    return f
end
-- the only eggs fake players hold
local REAL_EGGS = {
    ["cracked egg"]=true, ["crystal egg"]=true, ["pet egg"]=true, ["royal egg"]=true, ["jungle egg"]=true,
    ["farm egg"]=true, ["aussie egg"]=true, ["fossil egg"]=true, ["ocean egg"]=true, ["basic egg"]=true, ["safari egg"]=true,
}
local function buildIndex()
    if byName then return end
    byName, kindName, randomKinds = {}, {}, {}
    local skip = {}
    R.eggs = {}
    for _, list in ipairs({ FB_HIGH, FB_EXOTIC, FB_MID, FB_TINY, FB_NEON, FB_MEGA_RANDOM, FB_SMALL_MEGA }) do
        for _, n in ipairs(list) do skip[n:lower()] = true end
    end
    local db = (InventoryDB and InventoryDB.pets) or {}
    for kind, entry in pairs(db) do
        local nm = type(entry) == "table" and entry.name
        if type(nm) == "string" then
            local l = nm:lower()
            kindName[kind] = l
            if REAL_EGGS[l] then R.eggs[#R.eggs + 1] = kind end   -- only the real eggs, nothing else
            if not byName[l] then byName[l] = kind end
            if not skip[l] and not BANNED[l] then randomKinds[#randomKinds + 1] = kind end
        end
    end
    -- exact name first; for exotics only, fall back to "name contains" (event names can carry a prefix)
    local function resolve(list, fuzzy, multiOnly)
        local out, seen = {}, {}
        for _, name in ipairs(list) do
            local l = name:lower()
            local kind = (not BANNED[l]) and byName[l] or nil
            if not kind and not BANNED[l] and fuzzy and (not multiOnly or l:find(" ", 1, true)) then
                for k, n in pairs(kindName) do
                    if n:find(l, 1, true) then kind = k break end
                end
            end
            if kind and not seen[kind] then seen[kind] = true; out[#out + 1] = kind end
        end
        return out
    end
    R.high, R.exotic = resolve(FB_HIGH), resolve(FB_EXOTIC, true)
    R.highCore = resolve(FB_HIGH_CORE)
    R.headline = resolve(FB_HEADLINE)
    R.megaRand = resolve(FB_MEGA_RANDOM, true, true)
    R.smallNamed = resolve(FB_SMALL_MEGA, true, true)
    R.headSet = {}
    for _, k in ipairs(R.headline) do R.headSet[k] = true end
    R.mid,  R.tiny   = resolve(FB_MID),  resolve(FB_TINY)
    R.neon           = resolve(FB_NEON, true, true)   -- exact name first; multi-word names may fuzzy match
    R.random         = randomKinds
    if #R.tiny == 0 then R.tiny = randomKinds end   -- none of the tiny names exist: use leftovers
end

-- Tiered high list (HIGH_TIER_PETS_TIERED): every pet has a max level.
--   "default" = FR at most | "neon" = up to NFR (no mega) | "any" = up to MFR
local capByKind
local function buildCaps()
    if capByKind then return end
    local list = _G._HIGH_TIER_TIERED
    if type(list) ~= "table" then return end
    buildIndex()
    local caps = {}
    for _, e in ipairs(list) do
        local k = byName[e.name:lower()]
        if k then caps[k] = e.max end
    end
    capByKind = caps
end
local function clampFlags(kind, f)
    buildCaps()
    local cap = capByKind and capByKind[kind]
    if not cap or cap == "any" then return f end
    local c = { N = f.N, M = f.M, F = f.F, R = f.R }
    if cap == "default" then c.N = nil; c.M = nil
    elseif cap == "neon" and c.M then c.M = nil; c.N = true end
    return c
end
_G._fakeClampFlags = clampFlags
-- roll a variant for a tiered pet, respecting its max level
local function rollTiered(kind)
    buildCaps()
    local cap = capByKind and capByKind[kind] or "default"
    local r = math.random(1, 100)
    local f
    if cap == "default" then f = { F = true, R = true }
    elseif cap == "neon" then f = (r <= 55) and { F = true, R = true } or { N = true, F = true, R = true }
    else
        if r <= 40 then f = { F = true, R = true }
        elseif r <= 75 then f = { N = true, F = true, R = true }
        else f = { M = true, F = true, R = true } end
        if math.random() < curA.mega * 0.5 then f = { M = true, F = true, R = true } end
    end
    return clampFlags(kind, f)
end

local function shuffled(t)
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    for i = #c, 2, -1 do
        local j = math.random(1, i)
        c[i], c[j] = c[j], c[i]
    end
    return c
end

-- flags: N neon, M mega, F fly, R ride
local function rollFlags(allowNeon)
    local r = math.random(1, 100)
    if r <= 12 then return {} end                              -- plain
    if r <= 62 then return { F = true, R = true } end          -- FR: by far the most common
    if r <= 68 then return { F = true } end
    if r <= 74 then return { R = true } end
    if not allowNeon then return { F = true, R = true } end    -- (tiny filler pets never neon)
    if r <= 91 then return { N = true, F = true, R = true } end   -- NFR
    if r <= 95 then return { M = true, F = true, R = true } end   -- MFR
    if r <= 98 then return { N = true } end
    return { M = true }
end

-- worthless / filler pets: always plain, no potions
local function rollFlagsNone() return {} end
-- low value wildcards: mostly plain, sometimes FR, never neon / mega
local function rollFlagsLow()
    if math.random(1, 100) <= 78 then return {} end
    return { F = true, R = true }
end
-- mid tiers: plain / FR / NFR only (never mega)
local function rollFlagsMid()
    local r = math.random(1, 100)
    if r <= 35 then return {} end
    if r <= 80 then return { F = true, R = true } end
    return { N = true, F = true, R = true }
end

-- valued mid tiers (0.1+ regular AMVGG): mostly FR, some NFR, rarely plain
local function rollFlagsMidVal()
    local r = math.random(1, 100)
    if r <= 10 then return {} end
    if r <= 70 then return { F = true, R = true } end
    return { N = true, F = true, R = true }
end

local function rollNeonFlags()
    local r = math.random(1, 100)
    if r <= 60 then return { N = true, F = true, R = true } end
    if r <= 80 then return { N = true } end
    if r <= 90 then return { N = true, F = true } end
    return { N = true, R = true }
end

local function toProps(flags, isEgg)
    if isEgg then
        return {}   -- eggs carry NO properties at all (no neon / mega / fly / ride / age)
    end
    return {
        neon = flags.N or false, mega_neon = flags.M or false,
        flyable = flags.F or false, rideable = flags.R or false,
        age = (math.random() < curOld) and 6 or math.random(1, 6), ailments_completed = 0,
    }
end

-- AMVGG values (shared loader from the value board). Mid tier = 0.1+ regular AMVGG value.
local amvgg
local function loadAmvgg()
    if amvgg then return end
    if type(_G._fetchAmvgg) == "function" then
        pcall(_G._fetchAmvgg, function(c) if c then amvgg = c end end)   -- sync if already cached, else loads in the background
    end
end
task.delay(4, loadAmvgg)   -- warm the cache so the first trade already has values
local function regularValue(kind)
    local nm = kindName and kindName[kind]
    local pd = nm and amvgg and amvgg[nm]
    if not pd then return nil end
    local v = pd.fr or 0
    if v == 0 then v = pd.r or 0 end
    return v
end
-- wildcard filter: cheap pets only. Rarity (legendary / ultra rare ...) says nothing about value, so only the AMVGG value is checked.
local function wildcardOk(kind)
    local nm = kindName and kindName[kind]
    if not nm then return true end
    local v = regularValue(kind)
    if v and v >= (CONFIG.BACKPACK_RANDOM_MAX_VALUE or 0.1) then return false end
    return true
end

local function buildMidPool()
    if R.midVal then return R.midVal end
    loadAmvgg()
    if not amvgg then return nil end
    buildIndex()
    local excl = {}
    for _, l in ipairs({ R.high, R.exotic, R.highCore, R.headline }) do
        for _, k in ipairs(l or {}) do excl[k] = true end
    end
    local pool, set = {}, {}
    for kind, nm in pairs(kindName) do
        if not excl[kind] and not nm:find("egg", 1, true) and not BANNED[nm] then
            local v = regularValue(kind)
            if v and v >= 0.1 then pool[#pool + 1] = kind; set[kind] = true end
        end
    end
    if #pool == 0 then return nil end
    R.midVal, R.midSet = pool, set
    return pool
end

local function buildBigMegaPool()
    if R.bigMega then return R.bigMega end
    loadAmvgg()
    buildIndex(); buildCaps()
    if amvgg then
        local pool, minV = {}, CONFIG.BACKPACK_MEGA_MIN_VALUE or 0.8
        for kind, nm in pairs(kindName) do
            if not nm:find("egg", 1, true) and not BANNED[nm] then
                local pd = amvgg[nm]
                local cap = capByKind and capByKind[kind]
                if pd and (pd.mfr or 0) >= minV and (not cap or cap == "any") then pool[#pool + 1] = kind end
            end
        end
        if #pool > 0 then R.bigMega = pool; return pool end
    end
    return R.exotic   -- fallback until AMVGG values load
end

local function buildSmallMegaPool()
    if R.smallMega then return R.smallMega end
    loadAmvgg()
    buildIndex(); buildCaps()
    local pool, seen = {}, {}
    for _, k in ipairs(R.smallNamed or {}) do
        local pdn = amvgg and kindName[k] and amvgg[kindName[k]]
        if not pdn or (pdn.mfr or 0) >= (CONFIG.BACKPACK_SMALL_MEGA_MIN or 0.05) then pool[#pool + 1] = k; seen[k] = true end
    end
    if amvgg then
        local lo, hi = CONFIG.BACKPACK_SMALL_MEGA_MIN or 0.05, CONFIG.BACKPACK_SMALL_MEGA_MAX or 0.3
        for kind, nm in pairs(kindName) do
            if not seen[kind] and not nm:find("egg", 1, true) and not BANNED[nm] then
                local pd = amvgg[nm]
                local cap = capByKind and capByKind[kind]
                local v = pd and (pd.mfr or 0) or 0
                if v >= lo and v <= hi and (not cap or cap == "any") then pool[#pool + 1] = kind; seen[kind] = true end
            end
        end
        R.smallMega = pool   -- values loaded: cache it
    end
    return pool
end

-- mid tier variant: mostly FR / NFR, MFR only now and then (and never above the pet's max level)
local function rollMidTiered(kind)
    local r = math.random(1, 100)
    local f
    if r <= 50 then f = { F = true, R = true }
    elseif r <= 90 then f = { N = true, F = true, R = true }
    else f = { M = true, F = true, R = true } end
    return clampFlags(kind, f)
end

_G._genFakeBackpack = function()
    buildIndex()
    -- roll this player's type
    local A = ARCHETYPES[1]
    if CONFIG.BACKPACK_VARIETY ~= false then
        local sum = 0
        for _, a in ipairs(ARCHETYPES) do sum = sum + a.w end
        local roll = math.random() * sum
        for _, a in ipairs(ARCHETYPES) do
            roll = roll - a.w
            if roll <= 0 then A = a; break end
        end
    end
    curA, curOld = A, A.old
    _G._lastBackpackType = A.name
    local out, used = {}, {}
    local function add(kind, flags, allowDupes)
        if not kind or BANNED[kindName[kind] or ""] then return false end
        if used[kind] and not allowDupes then return false end
        used[kind] = true
        flags = clampFlags(kind, flags or {})
        local isEgg = (kindName[kind] or ""):find("egg", 1, true) ~= nil
        out[#out + 1] = { kind = kind, properties = toProps(flags, isEgg) }
        return true
    end
    local function range(minK, maxK, dMin, dMax)
        local lo = math.max(0, CONFIG[minK] or dMin)
        return math.random(lo, math.max(lo, CONFIG[maxK] or dMax))
    end

    -- 1) showpiece roll: ONE of  [0.8+ mega neon | high tier | mid tier]  (or nothing), 10% chance of a 2nd from a DIFFERENT category.
    --    Max 2 total, so players don't stack a mega + high tier + mids all at once.
    local showSet = {}
    local cats = { "mega", "high", "mid" }
    local weights = {
        mega = CONFIG.BACKPACK_SHOW_MEGA or 0.20,
        high = CONFIG.BACKPACK_SHOW_HIGH or 0.20,
        mid  = CONFIG.BACKPACK_SHOW_MID  or 0.50,
    }
    if A.name == "newbie" then weights = { mega = 0, high = 0, mid = 0.35 } end
    local function pickCat(excl, noCombo)
        local total, ws = 0, {}
        for _, c in ipairs(cats) do
            ws[c] = (c == excl) and 0 or weights[c]
            if noCombo and ((excl == "mega" and c == "high") or (excl == "high" and c == "mega")) then ws[c] = 0 end
            total = total + ws[c]
        end
        local none = excl and 0 or math.max(0, 1 - total)   -- first roll can land on "no showpiece"
        if total + none <= 0 then return nil end
        local r = math.random() * (total + none)
        for _, c in ipairs(cats) do
            r = r - ws[c]
            if ws[c] > 0 and r <= 0 then return c end
        end
        return nil
    end
    local function givePiece(cat)
        if cat == "mega" then
            for _, kind in ipairs(shuffled(buildBigMegaPool() or {})) do
                if add(kind, { M = true, F = true, R = true }) then showSet[kind] = true; return true end
            end
        elseif cat == "high" then
            for _, kind in ipairs(shuffled(R.headline or {})) do
                local flags = (math.random() < 0.55) and { F = true, R = true } or { N = true, F = true, R = true }   -- FR or NFR only
                if add(kind, flags) then showSet[kind] = true; return true end
            end
        elseif cat == "mid" then
            if math.random() < (CONFIG.BACKPACK_SMALL_MEGA_CHANCE or 0.4) then
                for _, kind in ipairs(shuffled(buildSmallMegaPool() or {})) do
                    local flags = (math.random() < 0.85) and { M = true, F = true, R = true } or { M = true }
                    if add(kind, flags) then showSet[kind] = true; return true end
                end
            end
            buildCaps()
            for _, kind in ipairs(shuffled(buildMidPool() or R.mid)) do
                local flags = (capByKind and capByKind[kind]) and rollMidTiered(kind) or rollFlagsMidVal()
                if add(kind, flags) then showSet[kind] = true; return true end
            end
        end
        return false
    end
    local firstCat = pickCat(nil)
    if firstCat then
        givePiece(firstCat)
        if math.random() < (CONFIG.BACKPACK_SHOW_DOUBLE or 0.06) then
            local allowCombo = math.random() < (CONFIG.BACKPACK_SHOW_COMBO or 0.25)
            local second = pickCat(firstCat, not allowCombo)
            if second then givePiece(second) end
        end
    end

    -- 2b) a couple of cheap mega neons (small megas), the kind regular players actually hold
    do
        local cheapScale = (A.name == "newbie") and 0 or ((A.name == "minimalist") and 0.4 or 1)
        local lo = CONFIG.BACKPACK_CHEAP_MEGA_MIN or 0
        local hi = math.max(lo, CONFIG.BACKPACK_CHEAP_MEGA_MAX or 2)
        local cwant, cn = scale(math.random(lo, hi), cheapScale), 0
        for _, kind in ipairs(shuffled(buildSmallMegaPool() or {})) do
            if cn >= cwant then break end
            local flags = (math.random() < 0.85) and { M = true, F = true, R = true } or { M = true }
            if add(kind, flags) then cn = cn + 1 end
        end
    end

    -- 2c) GUARANTEE: everyone holds at least one pet worth MORE than BACKPACK_MIN_VALUABLE (0.2) on AMVGG,
    --     in whatever variant it is (regular FR, neon NFR or mega MFR). Rarity is ignored, only the value counts.
    do
        local minV = CONFIG.BACKPACK_MIN_VALUABLE or 0.2
        local getVal, getKey = _G._getPetVal, _G._getVariantKey
        local function entryValue(e)
            local nm = kindName[e.kind]
            local pd = nm and amvgg and amvgg[nm]
            if not pd or not getVal or not getKey then return 0 end
            return getVal(pd, getKey(e.properties))
        end
        local has = false
        for _, e in ipairs(out) do
            if not (kindName[e.kind] or ""):find("egg", 1, true) and entryValue(e) > minV then has = true; break end
        end
        if not has then
            loadAmvgg()
            local softCap = (A.name == "whale" or A.name == "mega collector") and 2.0 or 0.8
            local variants = { { F = true, R = true }, { N = true, F = true, R = true }, { M = true, F = true, R = true } }
            local cands, fallback = {}, {}
            if amvgg and getVal and getKey then
                local seenK, kinds = {}, {}
                for _, list in ipairs({ R.headline or {}, buildMidPool() or {}, buildSmallMegaPool() or {}, R.neon or {}, R.high or {} }) do
                    for _, k in ipairs(list) do if not seenK[k] then seenK[k] = true; kinds[#kinds + 1] = k end end
                end
                for _, kind in ipairs(shuffled(kinds)) do
                    local nm = kindName[kind]
                    local pd = nm and amvgg[nm]
                    if pd and not used[kind] and not nm:find("egg", 1, true) and not BANNED[nm] then
                        for _, base in ipairs(variants) do
                            local f = clampFlags(kind, base)
                            local v = getVal(pd, getKey({ neon = f.N, mega_neon = f.M, flyable = f.F, rideable = f.R }))
                            if v > minV then
                                local c = { kind = kind, flags = f }
                                if v <= softCap then cands[#cands + 1] = c else fallback[#fallback + 1] = c end
                            end
                        end
                    end
                end
            end
            local pick = cands[1] or fallback[1]
            if pick then
                if add(pick.kind, pick.flags) then showSet[pick.kind] = true end
            else
                -- values not loaded yet: best effort with a headline high tier (FR / NFR)
                for _, kind in ipairs(shuffled(R.headline or {})) do
                    local f = (math.random() < 0.55) and { F = true, R = true } or { N = true, F = true, R = true }
                    if add(kind, f) then showSet[kind] = true; break end
                end
            end
        end
    end

    -- 3) neon showcase pets (alicorn, bush elephant, candicorn, caterpillar, kangaroo, turtle ...)
    local want, n = scale(range("BACKPACK_NEON_MIN", "BACKPACK_NEON_MAX", 5, 9), A.neon), 0
    for _, kind in ipairs(shuffled(R.neon or {})) do
        if n >= want then break end
        if add(kind, rollNeonFlags()) then n = n + 1 end
    end

    -- 5) wildcards from the whole pet database (big variety)
    want, n = scale(range("BACKPACK_RANDOM_MIN", "BACKPACK_RANDOM_MAX", 8, 14), A.rnd), 0
    buildMidPool()   -- makes sure valued pets (R.midSet) are excluded from the wildcards even when no mid showpiece rolled
    local pool = shuffled(R.random or {})
    for i = 1, #pool do
        if n >= want then break end
        local nm = kindName[pool[i]] or ""
        if not nm:find("egg", 1, true) and not (R.midSet and R.midSet[pool[i]]) and wildcardOk(pool[i]) and add(pool[i], rollFlagsLow()) then n = n + 1 end
    end

    -- 5b) eggs for some player types
    -- eggs: each real egg rolls on its own chance, with its own max copies (eggs carry no properties)
    --   jungle / safari / farm: 5%, max 1 | aussie: 15%, max 2 | all other eggs: 40%, max 3
    local EGG_RULES = {
        ["jungle egg"] = { 0.05, 1 }, ["safari egg"] = { 0.05, 1 }, ["farm egg"] = { 0.05, 1 },
        ["aussie egg"] = { 0.15, 2 },
    }
    local eggByName = {}
    for _, k in ipairs(R.eggs or {}) do
        local nm = kindName[k]
        if nm and not eggByName[nm] then eggByName[nm] = k end
    end
    for nm, k in pairs(eggByName) do
        local rule = EGG_RULES[nm] or { 0.40, 3 }
        if math.random() < rule[1] then
            for _ = 1, math.random(1, rule[2]) do add(k, {}, true) end
        end
    end

    -- 5c) duplicates: people hold more than one copy of pets they like (often in a different variant)
    local nonEgg = {}
    for _, e in ipairs(out) do
        if not (kindName[e.kind] or ""):find("egg", 1, true) and not (R.headSet and R.headSet[e.kind]) and not showSet[e.kind] then nonEgg[#nonEgg + 1] = e end
    end
    if #nonEgg > 0 then
        local dupOf = {}   -- at most ONE extra copy per pet
        for _ = 1, math.random(0, A.dup) do
            local src = nonEgg[math.random(1, #nonEgg)]
            if not dupOf[src.kind] then
                dupOf[src.kind] = true
                local valuable = src.properties and (src.properties.neon or src.properties.mega_neon or (src.properties.flyable and src.properties.rideable))
                add(src.kind, valuable and rollFlagsMid() or rollFlagsLow(), true)
            end
        end
    end

    -- 6) fill the rest with tiny pets (king bee, ant, goldfish ...), duplicates allowed
    local total = math.max(8, math.floor(range("BACKPACK_TOTAL_MIN", "BACKPACK_TOTAL_MAX", 50, 65) * A.tot))
    local tries, copies = 0, {}
    for _, e in ipairs(out) do copies[e.kind] = (copies[e.kind] or 0) + 1 end   -- cap counts every copy, not just filler
    while #out < total and tries < 1000 and #R.tiny > 0 do
        tries = tries + 1
        local k = R.tiny[math.random(1, #R.tiny)]
        if (copies[k] or 0) < 2 and add(k, rollFlagsNone(), true) then copies[k] = (copies[k] or 0) + 1 end
    end
    -- the tiny list ran dry (many of its names aren't in this game's database): top up with random pets from the
    -- whole database instead of repeating the same few over and over
    tries = 0
    local rp = R.random or {}
    while #out < total and tries < 1500 and #rp > 0 do
        tries = tries + 1
        local k = rp[math.random(1, #rp)]
        if (copies[k] or 0) < 2 and not (kindName[k] or ""):find("egg", 1, true) and not (R.midSet and R.midSet[k]) and wildcardOk(k) and add(k, rollFlagsLow(), true) then
            copies[k] = (copies[k] or 0) + 1
        end
    end

    return shuffled(out)
end

-- One generated backpack per player id, shared by the Suggest picker AND the generated profile,
-- so a fake profile always shows the same pets as that player's (generated) items.
_G._fakeHighKinds = function()
    buildIndex()
    local t = {}
    for _, k in ipairs(R.high or {}) do t[#t + 1] = k end
    for _, k in ipairs(R.exotic or {}) do t[#t + 1] = k end
    return t
end

-- big, high value pets for wishlists ("dream pets"): the core high tiers first, then the rest of high + exotics
_G._fakeDreamKinds = function()
    buildIndex()
    local core, rest, seen = {}, {}, {}
    for _, k in ipairs(R.highCore or {}) do core[#core + 1] = k; seen[k] = true end
    for _, k in ipairs(R.high or {})   do if not seen[k] then rest[#rest + 1] = k; seen[k] = true end end
    for _, k in ipairs(R.exotic or {}) do if not seen[k] then rest[#rest + 1] = k; seen[k] = true end end
    return core, rest
end

-- is this kind an egg?  (eggs never get any properties)
_G._isEggKind = function(kind)
    buildIndex()
    local nm = kindName and kindName[kind]
    if type(nm) == "string" then return nm:find("egg", 1, true) ~= nil and not nm:find("eggplant", 1, true) end
    return type(kind) == "string" and kind:lower():find("egg", 1, true) ~= nil
end

local _bpCache, _bpType = {}, {}
_G._fakeBackpackFor = function(uid)
    uid = uid or 0
    if not _bpCache[uid] then
        local bp = _G._genFakeBackpack()
        local t = _G._lastBackpackType
        _bpType[uid] = t
        _bpCache[uid] = bp
    end
    return _bpCache[uid]
end
end
_fakeBackpackSetup()
end

-- The fake trade_partner_inventory injected during a mock trade.
local mockPartnerInventory = nil

-- True only while OUR mock trade is on screen. A real trade (non "MOCK_" trade id) is never touched,
-- so the generated items can never replace a real player's items.
_G._isMockTradeNow = function()
    if not (mockState.active and mockState.trade) then return false end
    local cur = TradeApp.local_trade_state
    if type(cur) == "table" and cur.trade_id ~= nil and not tostring(cur.trade_id):find("^MOCK_") then
        return false
    end
    return true
end

-- Per-trade profile cache so we only fetch once per partner
local profileCache = {}

-- Pull the partner's collection pets from PlayerProfileAPI/FetchProfile.
-- Returns a flat list of { kind, properties } tables.
local function fetchProfilePets(userId)
    if profileCache[userId] then return profileCache[userId] end
    local pets = {}
    safeCall(function()
        local data = RouterClient.get("PlayerProfileAPI/FetchProfile"):InvokeServer(userId)
        -- Profile data shape: { pages = { { widgets = { { data = { widget_kind, widget_data } } } } } }
        local pages = data and (data.pages or (data.profile and data.profile.pages))
        if not pages then return end
        for _, page in ipairs(pages) do
            for _, widget in ipairs(page.widgets or {}) do
                local wd = widget.data
                if wd and wd.widget_kind == "collection" then
                    for _, item in ipairs((wd.widget_data and wd.widget_data.items) or {}) do
                        if item.kind then
                            table.insert(pets, item)
                        end
                    end
                end
            end
        end
    end)
    profileCache[userId] = pets
    return pets
end
_G._fetchProfilePets = fetchProfilePets

-- Convert profile pet list into a trade_partner_inventory shaped table.
-- Each entry gets a fresh unique so the suggestion system can key on it.
local function buildPartnerInventory(pets)
    local inv = { pets = {} }
    for _, pet in ipairs(pets) do
        if InventoryDB.pets and InventoryDB.pets[pet.kind] then
            local uid = HttpService:GenerateGUID(false)
            local props = pet.properties or {}
            inv.pets[uid] = {
                unique     = uid,
                category   = "pets",
                kind       = pet.kind,
                id         = pet.kind,
                properties = ((_G._isEggKind and _G._isEggKind(pet.kind)) and {} or { neon               = props.neon       or false, mega_neon          = props.mega_neon  or false, flyable            = props.flyable    or false, rideable           = props.rideable   or false, age                = props.age        or 1, ailments_completed = 0, }),
            }
        end
    end
    return inv
end

-- _get_suggestible_items is called by suggest_item (source line 1241) to populate
-- the BackpackApp picker. Return our fake inventory during mock trades.
mockState.originalFunctions._get_suggestible_items = TradeApp._get_suggestible_items
TradeApp._get_suggestible_items = function(self)
    if _G._isMockTradeNow() then
        return mockPartnerInventory or { pets = {} }
    end
    return mockState.originalFunctions._get_suggestible_items(self)
end

-- try_suggest_item is called when the player presses the Suggest button
mockState.originalFunctions.try_suggest_item = TradeApp.try_suggest_item
TradeApp.try_suggest_item = function(self)
    if not _G._isMockTradeNow() then
        return mockState.originalFunctions.try_suggest_item(self)
    end

    -- Already granted — go straight to picker
    if TradeApp.backpack_access == true then
        TradeApp:suggest_item()
        return
    end

    -- backpack_access == false means partner denied — match real behaviour
    if TradeApp.backpack_access == false then
        if UIManager.apps.HintApp then
            UIManager.apps.HintApp:hint({ text = "Items access denied.", length = 3, overridable = true, yields = false, })
        end
        return
    end

    -- backpack_access == nil — request not sent yet
    if UIManager.apps.HintApp then
        UIManager.apps.HintApp:hint({ text = "Items access requested..", length = 3, overridable = true, yields = false, })
    end

    task.spawn(function()
        local partner = TradeApp:_get_partner()
        if not partner then return end

        -- Fake backpack: 50+ pets: 1 FR/NFR high tier, 2-4 mega exotics, a few mid tiers, lots of tiny pets.
        -- (Set CONFIG.BACKPACK_FROM_PROFILE = true to mirror the partner's profile collection instead.)
        mockPartnerInventory = { pets = {} }
        if CONFIG.BACKPACK_FROM_PROFILE then
            mockPartnerInventory = buildPartnerInventory(fetchProfilePets(partner.UserId))
        end
        if not next(mockPartnerInventory.pets) then
            mockPartnerInventory = buildPartnerInventory(
                (_G._fakeBackpackFor and _G._fakeBackpackFor(partner.UserId))
                or (_G._genFakeBackpack and _G._genFakeBackpack()) or {})
        end

        -- Small delay to simulate network round-trip
        task.wait(0.8)
        if not mockState.active then return end

        TradeApp.backpack_access = true

        -- Show the same dialog the real game shows (source line 1213)
        local res = UIManager.apps.DialogApp:dialog({ text  = string.format( "%s has granted you access to view their items! Make a suggestion now?", CONFIG.PARTNER_NAME), left  = "Cancel", right = "Suggest", })
        if res == "Suggest" then
            TradeApp:suggest_item()
        end
    end)
end

-- suggest_item is called once access is granted (source line 1239).
-- Opens the BackpackApp picker with inventory_override set to the fake partner inventory.
mockState.originalFunctions.suggest_item = TradeApp.suggest_item
TradeApp.suggest_item = function(self, preselected)
    if not _G._isMockTradeNow() then
        return mockState.originalFunctions.suggest_item(self, preselected)
    end

    local partner = TradeApp:_get_partner()
    if not partner then return end

    -- pick_item with inventory_override mirrors source line 1248
    local picked = preselected or BackpackApp:pick_item({
        title_override     = string.format("%s'S ITEMS", CONFIG.PARTNER_NAME:upper()),
        inventory_override = mockPartnerInventory or { pets = {} },
        force_no_filters   = true,
        friendship_hidden  = true,
        allow_callback     = function(item)
            -- Don't allow items already in the partner's offer (source line 1251)
            for _, existing in ipairs(mockState.trade.recipient_offer.items) do
                if existing.unique == item.unique then return false end
            end
            return true
        end,
    })

    if not picked then return end

    -- Ensure chat is open so suggestion card and message are visible
    if not TradeApp.negotiation_chat.Visible then
        TradeApp:toggle_chat_visibility(true)
    end

    -- _render_suggestion (TradeApp source line 1004):
    if not mockPartnerInventory then mockPartnerInventory = { pets = {} } end
    mockPartnerInventory.pets[picked.unique] = mockPartnerInventory.pets[picked.unique] or {
        unique     = picked.unique,
        category   = picked.category or "pets",
        kind       = picked.kind,
        id         = picked.kind,
        properties = picked.properties or {},
    }
    safeCall(function()
        TradeApp:_render_suggestion(picked.unique, partner)
    end)

    -- After 1.5s the partner "accepts" — matches _render_suggestion_finalized(source 1128)
    task.delay(1.5, function()
        if not mockState.active or not mockState.trade then return end

        -- Mark suggestion card as accepted
        safeCall(function()
            TradeApp:_render_suggestion_finalized(picked.unique, true, partner)
        end)

        -- Insert into recipient_offer exactly like _on_local_trade_state_changed does
        -- when it detects a new item in the partner offer (source line 778)
        local petName = picked.kind
        pcall(function() petName = InventoryDB.pets[picked.kind].name end)

        local petItem = {
            category   = "pets",
            kind       = picked.kind,
            unique     = picked.unique,
            properties = ((_G._isEggKind and _G._isEggKind(picked.kind)) and {} or { neon               = picked.properties and picked.properties.neon      or false, mega_neon          = picked.properties and picked.properties.mega_neon or false, flyable            = picked.properties and picked.properties.flyable   or false, rideable           = picked.properties and picked.properties.rideable  or false, age                = picked.properties and picked.properties.age       or 1, ailments_completed = 0, }),
        }

        table.insert(mockState.trade.recipient_offer.items, petItem)
        TradeApp.can_suggest_removal_items[petItem.unique] = petItem
        mockState.trade.sender_offer.negotiated    = false; mockState.trade.recipient_offer.negotiated = false
        mockState.trade.offer_version = mockState.trade.offer_version + 1
        TradeApp:_overwrite_local_trade_state(mockState.trade)
        if TradeApp._lock_trade_for_appropriate_time then
            TradeApp:_lock_trade_for_appropriate_time()
        end
        TradeApp:_render_message_in_trade_chat(nil,
            string.format("%s added %s.", CONFIG.PARTNER_NAME, petName), true)
    end)
end

-- Clear suggestion state when the trade ends (the nil path of _overwrite_local_trade_state)
-- We patch the already-hooked function to also clear our state
local _existingOverwrite = TradeApp._overwrite_local_trade_state
TradeApp._overwrite_local_trade_state = function(self, newState)
    if not newState then
        mockPartnerInventory      = nil
        TradeApp.backpack_access  = nil
    end
    return _existingOverwrite(self, newState)
end

end -- BACKPACK SUGGESTION do block

-- PROFILE SUGGESTION HOOK
do local _PlayerProfileApp = UIManager.apps.PlayerProfileApp

local function hookProfileWidgetItems()
    if not _PlayerProfileApp then return end
    if not mockState.active or not mockState.trade then return end

    local profileApp = _PlayerProfileApp
    if not profileApp.player_profile then return end

    local profileUserId = profileApp.player_profile.user_id
    if profileUserId ~= mockState.trade.recipient.UserId then return end

    local slotCount = 0
    for _ in pairs(profileApp.slots or {}) do slotCount = slotCount + 1 end

    -- Wire the Suggest button on the profile header
    safeCall(function()
        if profileApp.trade_button and profileApp.trade_button.instance then
            local btn = profileApp.trade_button.instance
            if not btn:GetAttribute("_mockSuggestHooked") then
                btn:SetAttribute("_mockSuggestHooked", true)
                btn.Activated:Connect(function()
                    if not mockState.active then return end
                    if not profileApp.player_profile then return end
                    if profileApp.player_profile.user_id ~= CONFIG.PARTNER_USER_ID then return end
                    UIManager.set_app_visibility("PlayerProfileApp", false)
                    UIManager.set_app_visibility("TradeApp", true)
                    task.defer(function()
                        pcall(function() TradeApp:try_suggest_item() end)
                    end)
                end)
            end
        end
    end)

    -- Walk profile slots; collection pets retain their existing Suggest interaction.
    for _, slot in pairs(profileApp.slots or {}) do
        local widget = slot.widget
        if widget and widget.ClassName == "CollectionPlayerProfileWidget" then
            local items = widget.save_data and widget.save_data.items or {}
            local itemInstances = widget.item_instances or {}

            for idx, itemBtn in pairs(itemInstances) do
                if itemBtn:IsA("ImageButton") and not itemBtn:GetAttribute("_mockHooked") then
                    itemBtn:SetAttribute("_mockHooked", true)
                    local item = items[idx]
                    if item and item.kind then
                        itemBtn.MouseButton1Click:Connect(function()
                            if not mockState.active or not mockState.trade then return end

                            local petDbEntry = InventoryDB.pets and InventoryDB.pets[item.kind]
                            local displayName = item.properties and item.properties.custom_name
                                or (petDbEntry and petDbEntry.name)
                                or item.kind

                            local response = UIManager.apps.DialogApp:dialog({
                                dialog_type = "ItemPreviewDialog",
                                item        = item,
                                text        = string.format(
                                    "Add suggestion for %s's %s?",
                                    CONFIG.PARTNER_NAME, displayName),
                                right = "Suggest",
                                left  = "Cancel",
                            })

                            if response ~= "Suggest" then return end

                            if not mockPartnerInventory then
                                mockPartnerInventory = { pets = {} }
                            end
                            mockPartnerInventory.pets[item.unique] = {
                                unique     = item.unique,
                                category   = item.category or "pets",
                                kind       = item.kind,
                                id         = item.kind,
                                properties = ((_G._isEggKind and _G._isEggKind(item.kind)) and {} or { neon      = item.properties and item.properties.neon      or false, mega_neon = item.properties and item.properties.mega_neon or false, flyable   = item.properties and item.properties.flyable   or false, rideable  = item.properties and item.properties.rideable  or false, age       = item.properties and item.properties.age       or 1, ailments_completed = 0, }),
                            }
                            TradeApp.backpack_access = true

                            UIManager.set_app_visibility("PlayerProfileApp", false)
                            if not TradeApp.negotiation_chat.Visible then
                                TradeApp:toggle_chat_visibility(true)
                            end

                            TradeApp:suggest_item(mockPartnerInventory.pets[item.unique])
                        end)
                    end
                end
            end
        end
    end
end

if _PlayerProfileApp then
    task.spawn(function()
        while true do
            task.wait(0.3)
            if not mockState.active then continue end
            local profileApp = _PlayerProfileApp
            if not profileApp.instance.Enabled then continue end
            if not profileApp.player_profile then continue end
            hookProfileWidgetItems()
        end
    end)

    -- Hook enable_profile_editing so the Suggest button appears when the mock
    -- partner's profile is opened during a trade.  We temporarily swap self.player
    -- to mockPartner so the real enable_profile_editing picks the TRADE_VISIBLE
    -- layout (shrinks the name label, shows the action button) without affecting
    -- real player profiles.
    local _origEnableEditing = _PlayerProfileApp.enable_profile_editing
    _PlayerProfileApp.enable_profile_editing = function(self, editing, ...)
        local isMockPartner = mockState.active
            and self.player_profile
            and self.player_profile.user_id == CONFIG.PARTNER_USER_ID

        if isMockPartner and not editing then
            local origPlayer = self.player
            self.player = mockPartner
            _origEnableEditing(self, editing, ...)
            self.player = origPlayer
            -- Force the header to show "Suggest" state (in_trade_with_me = true)
            safeCall(function()
                self:set_header_info({
                    in_trade         = true,
                    in_trade_with_me = true,
                })
            end)
        else
            _origEnableEditing(self, editing, ...)
        end
    end

    -- Hook open_player_profile_for_user_id so that opening the mock partner's
    -- profile during a trade automatically triggers the enable_profile_editing
    -- hook (via on_load_call) once the profile has finished loading, which sets
    -- the TRADE_VISIBLE layout and shows the Suggest button in the header.
    local _origSuggestOpen = _PlayerProfileApp.open_player_profile_for_user_id
    if _origSuggestOpen then
        _PlayerProfileApp.open_player_profile_for_user_id = function(self, userId, ...)
            local result = _origSuggestOpen(self, userId, ...)
            if mockState.active and userId == CONFIG.PARTNER_USER_ID then
                self:on_load_call(function()
                    safeCall(function()
                        self:enable_profile_editing(false)
                    end)
                end)
            end
            return result
        end
    end
end

-- SUGGEST REMOVAL HOOK
end do local _origRenderMessage = TradeApp._render_message_in_trade_chat
TradeApp._render_message_in_trade_chat = function(self, player, message, isPartner, ...)
    -- Deduplicate the intro system messages. They can fire twice and in varying order during
    -- mock trade init, so show each UNIQUE intro line exactly once per trade — order-independent.
    -- (The old single-flag logic dropped whichever line arrived after "change what trade chat",
    --  which is why the intro sometimes didn't fully show.)
    if mockState.active and type(message) == "string"
        and (message:find("chatting with")
            or message:find("change what trade chat")
            or message:find("system messages disabled")) then
        if _G._introTradeRef ~= mockState.trade then
            _G._introTradeRef = mockState.trade
            _G._introSeen = {}
        end
        if _G._introSeen[message] then return end
        _G._introSeen[message] = true
    end
    local result = _origRenderMessage(self, player, message, isPartner, ...)

    -- Detect the "You want X to remove Y" message fired by the real slot Activated
    if mockState.active and mockState.trade
        and type(message) == "string"
        and message:find("You want .+ to remove .+ from their offer") then

        -- Find which item was requested — it's the most recently flagged unique
        local petName = message:match("to remove (.+) from their offer")
        if petName then
            task.delay(1.5, function()
                if not mockState.active or not mockState.trade then return end
                local items = mockState.trade.recipient_offer.items
                for i = #items, 1, -1 do
                    local item = items[i]
                    local name = item.kind
                    pcall(function() name = InventoryDB.pets[item.kind].name end)
                    if name:lower() == petName:lower() then
                        local unique = item.unique
                        table.remove(items, i)
                        if TradeApp.can_suggest_removal_items then
                            TradeApp.can_suggest_removal_items[unique] = nil
                        end
                        resetTradeNegotiation()
                        TradeApp:_overwrite_local_trade_state(mockState.trade)
                        if TradeApp._lock_trade_for_appropriate_time then
                            TradeApp:_lock_trade_for_appropriate_time()
                        end
                        _origRenderMessage(self, nil,
                            string.format("%s removed %s.", CONFIG.PARTNER_NAME, name),
                            true)
                        break
                    end
                end
            end)
        end
    end

    return result
end

end local function addPetToPartnerOffer(petName, flags)
    if not mockState.active or not mockState.trade then return false end
    if mockState.trade.current_stage == "confirmation" then return false end
    if #mockState.trade.recipient_offer.items >= 18 then return false end
    if not TradeApp.can_suggest_removal_items then
        TradeApp.can_suggest_removal_items = {}
    end

    -- Show the partner "picking" busy indicator for 1 second
    local partnerId = tostring(mockState.trade.recipient.UserId)
    mockState.trade.busy_indicators = mockState.trade.busy_indicators or {}
    mockState.trade.busy_indicators[partnerId] = { picking = true }
    pcall(function() TradeApp:_update_busy_indicators(mockState.trade) end)

    for cn, ct in pairs(InventoryDB) do
        if cn == "pets" then
            for id, item in pairs(ct) do
                local nameLower    = item.name:lower()
                local nameClean    = nameLower:gsub("%s+", "")
                local inputLower   = petName:lower()
                local inputClean   = inputLower:gsub("%s+", "")
                if nameLower == inputLower or nameClean == inputClean then
                    local uuid    = HttpService:GenerateGUID()
                    -- Eggs don't support flyable/rideable/neon/mega_neon flags
                    local isEgg   = item.name:lower():find("egg") ~= nil
                    local petItem = {
                        category   = "pets",
                        kind       = id,
                        unique     = uuid,
                        properties = isEgg and {} or { flyable            = flags.F or false, rideable           = flags.R or false, neon               = flags.N or false, mega_neon          = flags.M or false, age                = 1, ailments_completed = 0, },
                    }
                    task.wait(1)
                    if not mockState.active or not mockState.trade then return false end
                    -- Clear the busy indicator before adding
                    mockState.trade.busy_indicators[partnerId] = nil
                    pcall(function() TradeApp:_update_busy_indicators(mockState.trade) end)
                    table.insert(mockState.trade.recipient_offer.items, petItem)
                    TradeApp.can_suggest_removal_items[uuid] = petItem
                    mockState.trade.sender_offer.negotiated    = false; mockState.trade.recipient_offer.negotiated = false
                    mockState.trade.offer_version = mockState.trade.offer_version + 1
                    TradeApp:_overwrite_local_trade_state(mockState.trade)
                    if TradeApp._lock_trade_for_appropriate_time then
                        TradeApp:_lock_trade_for_appropriate_time()
                    end
                    if TradeApp._render_message_in_trade_chat then
                        TradeApp:_render_message_in_trade_chat(nil, CONFIG.PARTNER_NAME .. " added " .. item.name .. ".", true)
                    end
                    mockState.scamWarningShown = false
                    return true
                end
            end
        end
    end
    return false
end

local function removeLatestPetFromPartnerOffer()
    if not mockState.active or not mockState.trade then return end
    local items = mockState.trade.recipient_offer.items
    if #items == 0 then return end
    local removed = table.remove(items)
    if TradeApp.can_suggest_removal_items and removed then
        TradeApp.can_suggest_removal_items[removed.unique] = nil
    end
    resetTradeNegotiation()
    TradeApp:_overwrite_local_trade_state(mockState.trade)
    if TradeApp._lock_trade_for_appropriate_time then
        TradeApp:_lock_trade_for_appropriate_time()
    end
end

local HIGH_TIER_PETS = {
    "Bat Dragon",
    "Shadow Dragon",
    "Giraffe",
    "Frost Dragon",
    "Owl",
    "Parrot",
    "Crow",
    "Balloon Unicorn",
    "African Wild Dog",
    "Giant Panda",
    "Haetae",
    "Cryptid",
    "Evil Unicorn",
    "Blazing Lion",
    "Hedgehog",
    "Orchid Butterfly",
    "Diamond Butterfly",
    "Dalmatian",
    "Arctic Reindeer",
    "Jekyll Hydra",
    "Mini Pig",
    "Hot Doggo",
    "Pelican",
    "Cow",
    "Mermicorn",
    "Strawberry Shortcake Bat Dragon",
    "Cabbit",
    "Chocolate Chip Bat Dragon",
    "Turtle",
    "Peppermint Penguin",
    "Goose",
    "Monkey King",
    "Undead Jousting Horse",
    "Flamingo",
    "Kangaroo",
    "Fairy Bat Dragon",
    -- mid tiers added (all 0.09+ on AMVGG, Oct 2026)
    "Werewolf",
    "Frostbite Bear",
    "Sugar Glider",
    "Siamese Cat",
    "Alpaca",
    "Bush Elephant",
    "Elephant",
    "Crocodile",
    "Albino Monkey",
    "Candyfloss Chick",
    "Strawberry Tortle",
}

-- Tiered high tier list: each entry has a max neon level
-- "default" = normal only, "neon" = neon max, "any" = mega neon allowed
local HIGH_TIER_PETS_TIERED = {
    { name = "Bat Dragon",                      max = "default" },
    { name = "Shadow Dragon",                   max = "default" },
    { name = "Giraffe",                         max = "default" },
    { name = "Frost Dragon",                    max = "neon"    },
    { name = "Owl",                             max = "neon"    },
    { name = "Parrot",                          max = "neon"    },
    { name = "Crow",                            max = "neon"    },
    { name = "Balloon Unicorn",                 max = "neon"    },
    { name = "African Wild Dog",                max = "neon"    },
    { name = "Giant Panda",                     max = "neon"    },
    { name = "Haetae",                          max = "neon"    },
    { name = "Cryptid",                         max = "neon"    },
    { name = "Evil Unicorn",                    max = "neon"    },
    { name = "Blazing Lion",                    max = "neon"    },
    { name = "Hedgehog",                        max = "neon"    },
    { name = "Orchid Butterfly",                max = "any"     },
    { name = "Diamond Butterfly",               max = "any"     },
    { name = "Dalmatian",                       max = "any"     },
    { name = "Arctic Reindeer",                 max = "any"     },
    { name = "Jekyll Hydra",                    max = "any"     },
    { name = "Mini Pig",                        max = "any"     },
    { name = "Hot Doggo",                       max = "any"     },
    { name = "Pelican",                         max = "any"     },
    { name = "Cow",                             max = "any"     },
    { name = "Mermicorn",                       max = "any"     },
    { name = "Strawberry Shortcake Bat Dragon", max = "any"     },
    { name = "Cabbit",                          max = "any"     },
    { name = "Chocolate Chip Bat Dragon",       max = "any"     },
    { name = "Turtle",                          max = "any"     },
    { name = "Peppermint Penguin",              max = "any"     },
    { name = "Goose",                           max = "any"     },
    { name = "Monkey King",                     max = "any"     },
    { name = "Undead Jousting Horse",           max = "any"     },
    { name = "Flamingo",                        max = "any"     },
    { name = "Kangaroo",                        max = "any"     },
    { name = "Werewolf", max = "any" },
    { name = "Frostbite Bear", max = "any" },
    { name = "Sugar Glider", max = "any" },
    { name = "Siamese Cat", max = "any" },
    { name = "Alpaca", max = "any" },
    { name = "Bush Elephant", max = "any" },
    { name = "Elephant", max = "any" },
    { name = "Crocodile", max = "any" },
    { name = "Albino Monkey", max = "any" },
    { name = "Candyfloss Chick", max = "any" },
}

_G._HIGH_TIER_TIERED = HIGH_TIER_PETS_TIERED   -- fake backpacks / profiles read the per-pet max neon level from here

local _useTieredList = true   -- ON by default; toggled in Misc tab

-- Flags for the pet add buttons — defined here so addRandomHighTier can use them
local activeFlags = { F = false, R = false, N = false, M = false }

-- All possible flag combinations with weighted probability
-- More common ones (FR, NFR, MFR) appear more often
local RANDOM_FLAG_COMBOS = {}
do
    -- w = how many copies go in the pool. FR / NFR / MFR (fly + ride) get w = 6, everything else w = 1,
    -- so a random item is FR/NFR/MFR about two thirds of the time. Change the weights to taste.
    local combos = {
        { F=false, R=false, N=false, M=false, w=1 }, -- Normal
        { F=true,  R=false, N=false, M=false, w=1 }, -- Fly
        { F=false, R=true,  N=false, M=false, w=1 }, -- Ride
        { F=true,  R=true,  N=false, M=false, w=6 }, -- FR
        { F=false, R=false, N=true,  M=false, w=1 }, -- Neon
        { F=true,  R=false, N=true,  M=false, w=1 }, -- NF
        { F=false, R=true,  N=true,  M=false, w=1 }, -- NR
        { F=true,  R=true,  N=true,  M=false, w=6 }, -- NFR
        { F=false, R=false, N=false, M=true,  w=1 }, -- Mega
        { F=true,  R=false, N=false, M=true,  w=1 }, -- MF
        { F=false, R=true,  N=false, M=true,  w=1 }, -- MR
        { F=true,  R=true,  N=false, M=true,  w=6 }, -- MFR
    }
    for _, c in ipairs(combos) do
        for _ = 1, c.w do
            RANDOM_FLAG_COMBOS[#RANDOM_FLAG_COMBOS + 1] = { F = c.F, R = c.R, N = c.N, M = c.M }
        end
    end
end

-- Tracks the last pet name picked by addRandomHighTier (set immediately,
local lastAddedHighTier = nil

local function addRandomHighTier()
    if not mockState.active or not mockState.trade then return end

    if _useTieredList then
        -- Tiered mode: pick pet respecting per-pet max neon level
        local shuffled = {}
        for _, entry in ipairs(HIGH_TIER_PETS_TIERED) do
            if entry.name ~= lastAddedHighTier then
                table.insert(shuffled, entry)
            end
        end
        TableUtil.shuffle(shuffled)
        for _, entry in ipairs(shuffled) do
            -- Build flags based on max tier (keys are F/R/N/M)
            local flags
            if entry.max == "default" then
                local pool = {}
                for _, fc in ipairs(RANDOM_FLAG_COMBOS) do
                    if not fc.N and not fc.M then table.insert(pool, fc) end
                end
                flags = pool[math.random(1, #pool)]
            elseif entry.max == "neon" then
                local pool = {}
                for _, fc in ipairs(RANDOM_FLAG_COMBOS) do
                    if not fc.M then table.insert(pool, fc) end
                end
                flags = pool[math.random(1, #pool)]
            else
                flags = RANDOM_FLAG_COMBOS[math.random(1, #RANDOM_FLAG_COMBOS)]
            end
            lastAddedHighTier = entry.name
            if addPetToPartnerOffer(entry.name, flags) then return end
        end
    else
        -- Normal mode: plain random from HIGH_TIER_PETS
        local shuffled = {}
        for _, v in ipairs(HIGH_TIER_PETS) do
            if v ~= lastAddedHighTier then
                table.insert(shuffled, v)
            end
        end
        TableUtil.shuffle(shuffled)
        local flags = RANDOM_FLAG_COMBOS[math.random(1, #RANDOM_FLAG_COMBOS)]
        for _, name in ipairs(shuffled) do
            lastAddedHighTier = name
            if addPetToPartnerOffer(name, flags) then return end
        end
    end
    lastAddedHighTier = nil
    warn("[MockTrade] No high tier pet names matched InventoryDB")
end

local function updatePartnerFromUsername(username)
    -- Block updates while a trade is active OR a trade request dialog is pending
    -- so the in-trade username never gets overwritten by keybind selections
    if mockState.active or _tradeRequestPending then return end
    CONFIG.PARTNER_NAME = username
    CONFIG.PARTNER_USER_ID = 0
    mockPartner = createMockPartner()
    -- Async lookup runs in background so UI doesn't freeze
    task.spawn(function()
        local ok, userId = pcall(function()
            return Players:GetUserIdFromNameAsync(username)
        end)
        if mockState.active or _tradeRequestPending then return end
        if CONFIG.PARTNER_NAME ~= username then return end -- user changed name again
        CONFIG.PARTNER_USER_ID = (ok and userId) and userId or 0
        mockPartner = createMockPartner()
    end)
end

local _tradeRequestPending = false
-- "Show Trade Request" (Misc tab toggle, _G._showTradeRequest):
--   ON  (default) = the "<name> sent you a trade request" Accept / Decline dialog shows before the mock trade starts
--   OFF           = the mock trade opens straight away, no dialog
local function initializeMockTrade()
    if mockState.active then return end
    if _tradeRequestPending then return end
    _tradeRequestPending = true

    -- Reset cached rank so stale badge from previous trade never carries over
    _cachedPartnerRank = 0

    mockPartner = createMockPartner()

    -- Opens the mock trade window (used by both the "accepted" path and the "no dialog" path)
    local function beginTrade()
        mockState.isAddingItem     = false; mockState.tradeCompleting  = false
        mockState.scamWarningShown = false; mockState.trade            = createMockTrade()
        mockState.active           = true
        notifyProfileAppTradeState(true)

        if not TradeApp.can_suggest_removal_items then
            TradeApp.can_suggest_removal_items = {}
        end

        TradeApp:_overwrite_local_trade_state(mockState.trade)
        UIManager.set_app_visibility("TradeApp", true)

        task.spawn(function()
            task.wait(0.2)
            if TradeApp.refresh_all then TradeApp:refresh_all() end
            -- Always show intro message
            pcall(function() if TradeApp._show_intro_message then TradeApp:_show_intro_message() end end)
            _G._autoSpinWaitingForTrade = false  -- new trade opened, auto spin can now fire
            -- Force spectate frame and ReactionFrame visible for fake reactions
            safeCall(function()
                local sf = TradeApp.spectate_frame
                if sf then
                    sf.Visible = true
                    local rf = sf:FindFirstChild("ReactionFrame")
                    if rf then rf.Visible = true end
                    -- Hide the close/emoji buttons so it doesnt look weird
                    local closeBtn = sf:FindFirstChild("Close")
                    if closeBtn then closeBtn.Visible = false end
                    local emojiFrame = sf:FindFirstChild("EmojiFrame")
                    if emojiFrame then emojiFrame.Visible = false end
                end
            end)
        end)

        if CONFIG.SPECTATOR_COUNT > 0 then
            startSpectatorLoop()
        end
        if _G._autoChatOn and _G._autoChatOn() then pcall(_G._autoChatStart) end   -- (the locals are defined further down the file, so go through _G)
    end

    -- Fetch rank synchronously so the badge is always correct and instant; returns the dialog header (or nil)
    local function buildHeader()
        local _dialogHeader = nil
        -- Friend badge takes priority if verified friend toggle is on
        if CONFIG_VERIFIED_FRIEND then
            safeCall(function()
                local GRH = load("GroupRankHelper")
                if GRH then
                    local icon = GRH.get_icon_from_tag("friend")
                    if icon then
                        _dialogHeader = { text = "Verified Friend", icon = icon }
                    end
                end
            end)
        end
        -- Group rank badge (only if friend badge not set)
        if not _dialogHeader and CONFIG.PARTNER_USER_ID ~= 0 then
            safeCall(function()
                local GRH = load("GroupRankHelper")
                if not GRH then return end
                local rank = GRH.get_rank_from_user_id(CONFIG.PARTNER_USER_ID)
                if not rank or rank == 0 then return end
                _cachedPartnerRank = rank
                local tag = GRH.get_tag_from_rank(rank)
                local icon = tag and GRH.get_icon_from_tag(tag)
                if tag and icon then
                    _dialogHeader = { text = "Verified " .. tag:sub(1,1):upper() .. tag:sub(2), icon = icon, }
                end
            end)
        end
        return _dialogHeader
    end

    local DialogApp = UIManager.apps.DialogApp
    if DialogApp and _G._showTradeRequest ~= false then
        task.spawn(function()
            pcall(function() setthreadidentity(2) end)
            local ok, response = pcall(function()
                local _dialogHeader = buildHeader()
                return DialogApp:dialog({ text   = CONFIG.PARTNER_NAME .. " sent you a trade request", left   = "Decline", right  = "Accept", handle = "trade_request", header = _dialogHeader, })
            end)
            _tradeRequestPending = false
            if not ok or response ~= "Accept" then
                return
            end
            beginTrade()
        end)
    else
        -- Show Trade Request is OFF (or no DialogApp): skip the dialog and open the trade directly
        task.spawn(function()
            pcall(function() setthreadidentity(2) end)
            pcall(buildHeader)  -- still resolve the partner rank so the in-trade badge is correct
            _tradeRequestPending = false
            beginTrade()
        end)
    end
end

-- PREFIX FLAGS (Pets tab)

local currentTab        = "Control"
local tabFrames         = {}
local tabButtons        = {}
local hasShownAnimation = {}
local playerListButtons = {}

local controlGui = mk("ScreenGui", {Name="MockTradeControl", ResetOnSpawn=false, DisplayOrder=10, Enabled=true, Parent=Players.LocalPlayer:WaitForChild("PlayerGui")})
_G._controlGui = controlGui

local blackFrame = mk("Frame", {Name="BlackFrame", Size=UDim2.new(0, 136, 0, 406), Position=UDim2.new(0, 0, 0.5, -203), BackgroundColor3=Color3.new(0, 0, 0), BorderSizePixel=0, ZIndex=0, Parent=controlGui})
Instance.new("UICorner", blackFrame).CornerRadius = UDim.new(0, 7)

local mainFrame = Instance.new("Frame")
_G._tradeGuiMainFrame = mainFrame  -- expose for spin tab dropdown
mainFrame.Size             = UDim2.new(0, 130, 0, 400); mainFrame.Position         = UDim2.new(0, 3, 0.5, -200)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40); mainFrame.BorderSizePixel  = 0
mainFrame.ZIndex           = 1; mainFrame.Parent           = controlGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 5)
local mainUIScale = mk("UIScale", {Scale=1, Parent=mainFrame})
do local mainStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=1.5, Parent=mainFrame})

end do local titleLabel = mk("TextLabel", {Size=UDim2.new(1, 0, 0, 13), Position=UDim2.new(0, 0, 0, 1), BackgroundTransparency=1, Text="saturnsecho on discord", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(190,34,230), Parent=mainFrame})
local titleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual, Color=Color3.new(0, 0, 0), Thickness=0.7, Parent=titleLabel})

end local tabContainer = mk("Frame", {Size=UDim2.new(0.94, 0, 0, 13), Position=UDim2.new(0.03, 0, 0, 16), BackgroundTransparency=1, Parent=mainFrame})

-- Close / reopen: the red X (top-right of the menu) hides the whole menu and shows a tiny button
-- in the bottom-left corner of the screen that brings it back. Also: _G._setMenuVisible(true/false)
do
    local PURPc = Color3.fromRGB(190, 34, 230)
    local closeX = mk("TextButton", {Name="CloseX", Size=UDim2.new(0, 11, 0, 11), Position=UDim2.new(1, -14, 0, 2), BackgroundColor3=Color3.fromRGB(80, 30, 30), Text="X", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(255, 90, 90), ZIndex=20, Parent=mainFrame})
    Instance.new("UICorner", closeX).CornerRadius = UDim.new(0, 3)
    mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 60, 60), Thickness=0.7, Transparency=0.3, Parent=closeX})
    local reopen = mk("TextButton", {Name="ReopenMenu", Size=UDim2.new(0, 16, 0, 16), Position=UDim2.new(0, 4, 1, -20), BackgroundColor3=Color3.fromRGB(30, 30, 40), Text="+", Font=Enum.Font.FredokaOne, TextSize=11, TextColor3=PURPc, Visible=false, ZIndex=60, Parent=controlGui})
    Instance.new("UICorner", reopen).CornerRadius = UDim.new(0, 4)
    mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=PURPc, Thickness=1, Transparency=0.2, Parent=reopen})
    _G._setMenuVisible = function(on)
        on = on and true or false
        mainFrame.Visible = on
        blackFrame.Visible = on
        reopen.Visible = not on
    end
    closeX.MouseButton1Click:Connect(function() _G._setMenuVisible(false) end)
    reopen.MouseButton1Click:Connect(function() _G._setMenuVisible(true) end)
end

local animatePlayerList  -- forward declaration, defined after Players tab build
local refreshPlayerList  -- forward declaration

local function setActiveTab(tabName)
    if currentTab == tabName then return end
    currentTab = tabName
    for name, data in pairs(tabButtons) do
        local isActive = name == tabName
        TweenService:Create(data.button, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundColor3 = isActive and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(40, 40, 50) }):Play()
        local targetColor     = isActive and Color3.fromRGB(190,34,230) or Color3.fromRGB(80, 80, 80)
        local targetThickness = isActive and 1.0 or 0.7
        TweenService:Create(data.stroke, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Color = targetColor, Thickness = targetThickness }):Play()
        if isActive then
            local fadeIn = TweenService:Create(data.stroke, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Color     = targetColor:Lerp(Color3.fromRGB(255, 255, 255), 0.25), Thickness = 1.3 })
            fadeIn:Play()
            fadeIn.Completed:Connect(function()
                TweenService:Create(data.stroke, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Color = targetColor, Thickness = 1.0 }):Play()
            end)
        end
    end
    for name, frame in pairs(tabFrames) do
        frame.Visible = name == tabName
    end
    if tabName == "Players" and not hasShownAnimation[tabName] then
        hasShownAnimation[tabName] = true
        animatePlayerList()
    end
    if tabName == "Rich" and _G._richBoardRefresh then
        _G._richBoardRefresh()
    end
end

do local tabs = { "Control", "Players", "Misc", "Spin" }
-- Tab icon asset ids (image icons + text; text hides when 5+ tabs are active)
local ICON_IDS = { Control=7059346386, Players=7992557371, Rich=6031280882, Misc=109065241613994, Spin=125246450296582, Anti=14939023900, Chat=14895333477, Spawn=13001190578 }

for i, tabName in ipairs(tabs) do
    local tabButton = mk("TextButton", {Size=UDim2.new(1 / #tabs - 0.02, 0, 1, 0), Position=UDim2.new((i - 1) * (1 / #tabs), 0, 0, 0), BackgroundColor3=i == 1 and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(40, 40, 50), BackgroundTransparency=0.2, Text="", Font=Enum.Font.FredokaOne, TextSize=5, TextColor3=Color3.fromRGB(255, 255, 255), Parent=tabContainer})
    Instance.new("UICorner", tabButton).CornerRadius = UDim.new(0, 3)
    local tabContent = mk("Frame", {AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,0,0,12), AutomaticSize=Enum.AutomaticSize.X, BackgroundTransparency=1, Parent=tabButton})
    mk("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, VerticalAlignment=Enum.VerticalAlignment.Center, Padding=UDim.new(0,2), SortOrder=Enum.SortOrder.LayoutOrder, Parent=tabContent})
    local tabIcon = mk("ImageLabel", {Size=UDim2.new(0,11,0,11), BackgroundTransparency=1, Image="rbxthumb://type=Asset&id="..ICON_IDS[tabName].."&w=150&h=150", ScaleType=Enum.ScaleType.Fit, LayoutOrder=1, Parent=tabContent})
    local tabLabel = mk("TextLabel", {Size=UDim2.new(0,0,0,11), AutomaticSize=Enum.AutomaticSize.X, BackgroundTransparency=1, Text=tabName, Font=Enum.Font.FredokaOne, TextSize=5, TextColor3=Color3.fromRGB(255,255,255), LayoutOrder=2, Parent=tabContent})
    local tabStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=i == 1 and Color3.fromRGB(190,34,230) or Color3.fromRGB(80, 80, 80), Thickness=i == 1 and 1.0 or 0.7, Transparency=0.3, Parent=tabButton})
    tabButtons[tabName] = { button = tabButton, stroke = tabStroke, icon = tabIcon, label = tabLabel }

    local tabFrame = Instance.new("Frame")
    tabFrame.Size     = UDim2.new(0.9, 0, 1, -33)
    tabFrame.Position = UDim2.new(0.05, 0, 0, 33)
    tabFrame.BackgroundTransparency = 1; tabFrame.Visible               = i == 1
    tabFrame.Parent                = mainFrame
    tabFrames[tabName] = tabFrame

    tabButton.MouseButton1Click:Connect(function() setActiveTab(tabName) end)
end

end _G._spinTabOn = false   -- the Spin tab starts HIDDEN; Misc > "Show Spin Tab" turns it on
local _spawnTabEnabled = false
local _antiTabEnabled  = false  -- legacy flag kept disabled; Anti Raid is a pop-out now
local _richTabEnabled  = false
local _chatTabEnabled  = true   -- auto-open on startup

-- Returns the ordered list of currently active tabs
local function _getActiveTabs()
    local t = { "Control", "Players" }
    if _richTabEnabled then table.insert(t, "Rich") end
    table.insert(t, "Misc")
    if _G._spinTabOn then table.insert(t, "Spin") end
    -- Anti Raid is intentionally not included here; it opens as a pop-out.
    if _chatTabEnabled  then table.insert(t, "Chat")  end
    if _spawnTabEnabled then table.insert(t, "Spawn") end
    return t
end

-- Rebuild all visible tab button sizes/positions
local function _rebuildTabPositions()
    local active = _getActiveTabs()
    local n = #active
    local iconOnly = n >= 5   -- crowded: center the icon, hide the text
    for idx, name in ipairs(active) do
        local data = tabButtons[name]
        if data then
            data.button.Size     = UDim2.new(1/n - 0.02, 0, 1, 0)
            data.button.Position = UDim2.new((idx-1)*(1/n), 0, 0, 0)
            if data.label then data.label.Visible = not iconOnly end
        end
    end
end

local function _addOptionalTab(name, icon, color)
    if tabButtons[name] then return end
    local active = _getActiveTabs()
    local n = #active
    local idx = 0
    for i, v in ipairs(active) do if v == name then idx = i end end
    local tabButton = mk("TextButton", {BackgroundColor3=Color3.fromRGB(40,40,50), BackgroundTransparency=0.2, Text="", Font=Enum.Font.FredokaOne, TextSize=5, TextColor3=Color3.fromRGB(255,255,255), Parent=tabContainer})
    Instance.new("UICorner", tabButton).CornerRadius = UDim.new(0,3)
    local tabContent = mk("Frame", {AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,0,0,12), AutomaticSize=Enum.AutomaticSize.X, BackgroundTransparency=1, Parent=tabButton})
    mk("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, VerticalAlignment=Enum.VerticalAlignment.Center, Padding=UDim.new(0,2), SortOrder=Enum.SortOrder.LayoutOrder, Parent=tabContent})
    -- Use emoji text label instead of image so optional-tab icons always render correctly
    local tabIcon = mk("TextLabel", {Size=UDim2.new(0,12,0,11), BackgroundTransparency=1, Text=icon or "", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=Color3.fromRGB(255,255,255), TextXAlignment=Enum.TextXAlignment.Center, LayoutOrder=1, Parent=tabContent})
    local tabLabel = mk("TextLabel", {Size=UDim2.new(0,0,0,11), AutomaticSize=Enum.AutomaticSize.X, BackgroundTransparency=1, Text=name, Font=Enum.Font.FredokaOne, TextSize=5, TextColor3=Color3.fromRGB(255,255,255), LayoutOrder=2, Parent=tabContent})
    local tabStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=color or Color3.fromRGB(80,80,80), Thickness=0.7, Transparency=0.3, Parent=tabButton})
    tabButtons[name] = { button = tabButton, stroke = tabStroke, icon = tabIcon, label = tabLabel }
    tabButton.MouseButton1Click:Connect(function() setActiveTab(name) end)
    _rebuildTabPositions()
end

local function _removeOptionalTab(name)
    local data = tabButtons[name]
    if data then data.button:Destroy(); tabButtons[name] = nil end
    if currentTab == name then setActiveTab("Misc") end
    if tabFrames[name] then tabFrames[name].Visible = false end
    _rebuildTabPositions()
end

-- Show / hide the Spin tab (its button; the tab itself is built as before). Also: _G._setSpinTabVisible(true/false)
_G._setSpinTabVisible = function(enabled)
    _G._spinTabOn = enabled and true or false
    local data = tabButtons["Spin"]
    if data then data.button.Visible = _G._spinTabOn end
    if not _G._spinTabOn then
        if currentTab == "Spin" then setActiveTab("Misc") end
        if tabFrames["Spin"] then tabFrames["Spin"].Visible = false end
    end
    _rebuildTabPositions()
end
_G._setSpinTabVisible(false)   -- hidden by default

local function _setSpawnTabVisible(enabled)
    _spawnTabEnabled = enabled
    if enabled then
        _addOptionalTab("Spawn", "🐾", Color3.fromRGB(80,80,80))
    else
        _removeOptionalTab("Spawn")
    end
end
_setSpawnTabVisible(true)  -- auto-open on startup

do local function _setAntiTabVisible(enabled)
    _antiTabEnabled = false
    _removeOptionalTab("Anti")
    if enabled and _G._toggleAntiPopup then
        _G._toggleAntiPopup(true)
    end
end

end local function _setRichTabVisible(enabled)
    _richTabEnabled = enabled
    if enabled then
        _addOptionalTab("Rich", "📊", Color3.fromRGB(190,34,230))
    else
        _removeOptionalTab("Rich")
    end
end
_setRichTabVisible(true)  -- Rich Board is a tab on startup

do local function _setChatTabVisible(enabled)
    if enabled then
        _addOptionalTab("Chat", "💬", Color3.fromRGB(60,120,200))
    else
        _removeOptionalTab("Chat")
    end
end
_setChatTabVisible(true)  -- auto-open on startup

-- Pre-create optional tab frames. Anti Raid is built separately as a pop-out.
do
    local spawnFrame = mk("Frame", {Size=UDim2.new(0.9,0,1,-33), Position=UDim2.new(0.05,0,0,33), BackgroundTransparency=1, Visible=false, Parent=mainFrame})
    tabFrames["Spawn"] = spawnFrame
end
do
    local richFrame = mk("Frame", {Size=UDim2.new(0.9,0,1,-33), Position=UDim2.new(0.05,0,0,33), BackgroundTransparency=1, Visible=false, Parent=mainFrame})
    tabFrames["Rich"] = richFrame
end
do
    local chatFrame = mk("Frame", {Size=UDim2.new(0.9,0,1,-33), Position=UDim2.new(0.05,0,0,33), BackgroundTransparency=1, Visible=false, Parent=mainFrame})
    tabFrames["Chat"] = chatFrame
end

do
    local spinTabFrame = mk("Frame", {Size=UDim2.new(0.9, 0, 1, -33), Position=UDim2.new(0.05, 0, 0, 33), BackgroundTransparency=1, Visible=false, Parent=mainFrame})
    tabFrames["Spin"] = spinTabFrame
end

local partnerBox, partnerStroke
do
local controlFrame = tabFrames["Control"]
do local controlLayout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0, 2), Parent=controlFrame})

end do local pulsationTweens = {}

local function createSettingRow(labelText, defaultValue, parent)
    local heading = mk("TextLabel", {Size=UDim2.new(1, 0, 0, 7), BackgroundTransparency=1, Text=labelText, Font=Enum.Font.SourceSansSemibold, TextSize=6, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=parent})
    local box = mk("TextBox", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(40, 40, 50), BackgroundTransparency=0.2, Text=tostring(defaultValue), Font=Enum.Font.SourceSans, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Center, Parent=parent})
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
    local stroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(100, 100, 100), Thickness=0.7, Transparency=0.5, Parent=box})
    box.Focused:Connect(function()
        if pulsationTweens[box] then pulsationTweens[box]:Cancel() end
        local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
        pulsationTweens[box] = TweenService:Create(stroke, pulseInfo, { Color        = Color3.fromRGB(100, 100, 255):Lerp(Color3.fromRGB(150, 150, 255), 0.5), Thickness    = 1.2, Transparency = 0.2, })
        pulsationTweens[box]:Play()
    end)
    box.FocusLost:Connect(function()
        if pulsationTweens[box] then pulsationTweens[box]:Cancel(); pulsationTweens[box] = nil end
        TweenService:Create(stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Color        = Color3.fromRGB(100, 100, 100), Thickness    = 0.7, Transparency = 0.5, }):Play()
    end)
    return box, stroke
end

partnerBox, partnerStroke = createSettingRow("Partner Username",  CONFIG.PARTNER_NAME,      controlFrame)
local acceptBox,   acceptStroke   = createSettingRow("Accept Delay (s)",  CONFIG.AUTO_ACCEPT_DELAY, controlFrame)
local confirmBox,  confirmStroke  = createSettingRow("Confirm Delay (s)", CONFIG.AUTO_CONFIRM_DELAY, controlFrame)
_G._acceptBox    = acceptBox
_G._confirmBox   = confirmBox

local spectatorLabel = mk("TextLabel", {Size=UDim2.new(1, 0, 0, 7), BackgroundTransparency=1, Text="Spectator Count", Font=Enum.Font.SourceSansSemibold, TextSize=6, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=controlFrame})

local spectatorRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 13), BackgroundTransparency=1, Parent=controlFrame})

local spectatorBox = Instance.new("TextBox")
_G._spectatorBox = spectatorBox
spectatorBox.Size                  = UDim2.new(0.5, -2, 1, 0); spectatorBox.Position              = UDim2.new(0, 0, 0, 0)
spectatorBox.BackgroundColor3      = Color3.fromRGB(40, 40, 50); spectatorBox.BackgroundTransparency = 0.2
spectatorBox.Text                  = tostring(CONFIG.SPECTATOR_COUNT); spectatorBox.Font                  = Enum.Font.SourceSans
spectatorBox.TextSize              = 7; spectatorBox.TextColor3            = Color3.fromRGB(255, 255, 255)
spectatorBox.ClearTextOnFocus      = false; spectatorBox.TextXAlignment        = Enum.TextXAlignment.Center
spectatorBox.Parent                = spectatorRow
Instance.new("UICorner", spectatorBox).CornerRadius = UDim.new(0, 3)
local spectatorStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(100, 100, 100), Thickness=0.7, Transparency=0.5, Parent=spectatorBox})
spectatorBox.Focused:Connect(function()
    if pulsationTweens[spectatorBox] then pulsationTweens[spectatorBox]:Cancel() end
    local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    pulsationTweens[spectatorBox] = TweenService:Create(spectatorStroke, pulseInfo, { Color        = Color3.fromRGB(100, 100, 255):Lerp(Color3.fromRGB(150, 150, 255), 0.5), Thickness    = 1.2, Transparency = 0.2, })
    pulsationTweens[spectatorBox]:Play()
end)
spectatorBox.FocusLost:Connect(function()
    if pulsationTweens[spectatorBox] then pulsationTweens[spectatorBox]:Cancel(); pulsationTweens[spectatorBox] = nil end
    TweenService:Create(spectatorStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Color        = Color3.fromRGB(100, 100, 100), Thickness    = 0.7, Transparency = 0.5, }):Play()
end)

local autoEnabled = true
local autoBtn = mk("TextButton", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0.5, 2, 0, 0), BackgroundColor3=Color3.fromRGB(30, 80, 50), BackgroundTransparency=0.2, Text="AUTO: ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80, 255, 130), Parent=spectatorRow})
Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, 3)
local autoBtnStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=0.7, Transparency=0.3, Parent=autoBtn})

autoBtn.MouseButton1Click:Connect(function()
    autoEnabled = not autoEnabled
    if autoEnabled then
        autoBtn.Text       = "AUTO: ON"
        autoBtn.TextColor3 = Color3.fromRGB(80, 255, 130)
        TweenService:Create(autoBtn, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(30, 80, 50) }):Play()
        TweenService:Create(autoBtnStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(0, 255, 100) }):Play()
        if mockState.active and CONFIG.SPECTATOR_COUNT > 0 then
            startSpectatorLoop()
        end
    else
        autoBtn.Text       = "AUTO: OFF"
        autoBtn.TextColor3 = Color3.fromRGB(255, 90, 90)
        TweenService:Create(autoBtn, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(80, 30, 30) }):Play()
        TweenService:Create(autoBtnStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 60, 60) }):Play()
        stopSpectatorAndReactionLoops()
    end
end)

local reactionLabel = mk("TextLabel", {Size=UDim2.new(1, 0, 0, 7), BackgroundTransparency=1, Text="Reactions / sec", Font=Enum.Font.SourceSansSemibold, TextSize=6, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=controlFrame})

local reactionRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 13), BackgroundTransparency=1, Parent=controlFrame})

local reactionRateBox = mk("TextBox", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0, 0, 0, 0), BackgroundColor3=Color3.fromRGB(40, 40, 50), BackgroundTransparency=0.2, Text=tostring(CONFIG.REACTIONS_PER_SECOND), Font=Enum.Font.SourceSans, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Center, Parent=reactionRow})
Instance.new("UICorner", reactionRateBox).CornerRadius = UDim.new(0, 3)
local reactionRateStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(100, 100, 100), Thickness=0.7, Transparency=0.5, Parent=reactionRateBox})
reactionRateBox.Focused:Connect(function()
    if pulsationTweens[reactionRateBox] then pulsationTweens[reactionRateBox]:Cancel() end
    local pulseInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    pulsationTweens[reactionRateBox] = TweenService:Create(reactionRateStroke, pulseInfo, { Color        = Color3.fromRGB(100, 100, 255):Lerp(Color3.fromRGB(150, 150, 255), 0.5), Thickness    = 1.2, Transparency = 0.2, })
    pulsationTweens[reactionRateBox]:Play()
end)
reactionRateBox.FocusLost:Connect(function()
    if pulsationTweens[reactionRateBox] then pulsationTweens[reactionRateBox]:Cancel(); pulsationTweens[reactionRateBox] = nil end
    TweenService:Create(reactionRateStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Color        = Color3.fromRGB(100, 100, 100), Thickness    = 0.7, Transparency = 0.5, }):Play()
    local v = tonumber(reactionRateBox.Text)
    if v and v > 0 then
        CONFIG.REACTIONS_PER_SECOND = v
    else
        reactionRateBox.Text = tostring(CONFIG.REACTIONS_PER_SECOND)
    end
end)

local reactionToggle = mk("TextButton", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0.5, 2, 0, 0), BackgroundColor3=Color3.fromRGB(30, 80, 50), BackgroundTransparency=0.2, Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80, 255, 130), Parent=reactionRow})
Instance.new("UICorner", reactionToggle).CornerRadius = UDim.new(0, 3)
local reactionToggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=0.7, Transparency=0.3, Parent=reactionToggle})

reactionToggle.MouseButton1Click:Connect(function()
    mockState.spectatorReactionsEnabled = not mockState.spectatorReactionsEnabled
    if mockState.spectatorReactionsEnabled then
        reactionToggle.Text       = "ON"
        reactionToggle.TextColor3 = Color3.fromRGB(80, 255, 130)
        TweenService:Create(reactionToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(30, 80, 50) }):Play()
        TweenService:Create(reactionToggleStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(0, 255, 100) }):Play()
    else
        reactionToggle.Text       = "OFF"
        reactionToggle.TextColor3 = Color3.fromRGB(255, 90, 90)
        TweenService:Create(reactionToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(80, 30, 30) }):Play()
        TweenService:Create(reactionToggleStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 60, 60) }):Play()
    end
end)

local spacer = mk("Frame", {Size=UDim2.new(1, 0, 0, 4), BackgroundTransparency=1, Parent=controlFrame})

local initButton = mk("TextButton", {Size=UDim2.new(1, 0, 0, 15), BackgroundColor3=Color3.fromRGB(50, 80, 60), BackgroundTransparency=0.2, Text="Start Trade", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=controlFrame})
Instance.new("UICorner", initButton).CornerRadius = UDim.new(0, 3)
local initStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=1.0, Transparency=0.3, Parent=initButton})

local petNameLabel = mk("TextLabel", {Size=UDim2.new(1, 0, 0, 7), BackgroundTransparency=1, Text="Pet Name To Add", Font=Enum.Font.SourceSansSemibold, TextSize=6, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=controlFrame})

local petBox = mk("TextBox", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(32, 32, 48), Text="", PlaceholderText="Enter pet name...", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(255, 255, 255), PlaceholderColor3=Color3.fromRGB(110, 110, 135), ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Center, Parent=controlFrame})
Instance.new("UICorner", petBox).CornerRadius = UDim.new(0, 4)
local pbS = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(180, 180, 200), Thickness=1.5, Parent=petBox})

local petGlowTween = nil
local function setPetGlow(col)
    if petGlowTween then petGlowTween:Cancel() end
    petGlowTween = TweenService:Create(pbS, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Color = col })
    petGlowTween:Play()
end

local function capWords(str)
    local out = ""; local i = 1
    while i <= #str do
        if str:sub(i, i):match("%S") then
            local s = i
            while i <= #str and str:sub(i, i):match("%S") do i = i + 1 end
            local w = str:sub(s, i - 1)
            out = out .. (w:sub(1, 1):upper() .. w:sub(2):lower())
        else
            out = out .. str:sub(i, i); i = i + 1
        end
    end
    return out
end

petBox:GetPropertyChangedSignal("Text"):Connect(function()
    local inp = petBox.Text
    local cap = capWords(inp)
    if cap ~= inp then petBox.Text = cap; return end
    if petBox.Text == "" then
        setPetGlow(Color3.fromRGB(180, 180, 200))
    else
        setPetGlow(Color3.fromRGB(220, 60, 60))
    end
end)

local flagSpacer = mk("Frame", {Size=UDim2.new(1, 0, 0, 4), BackgroundTransparency=1, Parent=controlFrame})

local flagRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 13), BackgroundTransparency=1, Parent=controlFrame})

local prefixDefs = {
    { key = "M", label = "M", col = Color3.fromRGB(170, 0,   255) },
    { key = "N", label = "N", col = Color3.fromRGB(0,   190, 80)  },
    { key = "F", label = "F", col = Color3.fromRGB(0,   175, 255) },
    { key = "R", label = "R", col = Color3.fromRGB(255, 45,  145) },
}
local prefBtns = {}
local btnW   = 26
local btnW   = 26
local btnH   = 13
local btnGap = math.floor((116 - btnW * 4) / 3)

for i, pd in ipairs(prefixDefs) do
    local xOff = (i - 1) * (btnW + btnGap)
    local pb = mk("TextButton", {Size=UDim2.new(0, btnW, 0, btnH), Position=UDim2.new(0, xOff, 0, 0), BackgroundColor3=Color3.fromRGB(22, 22, 34), Text=pd.label, Font=Enum.Font.GothamBold, TextSize=10, TextColor3=Color3.fromRGB(220, 220, 220), BorderSizePixel=0, Parent=flagRow})
    Instance.new("UICorner", pb).CornerRadius = UDim.new(0, 4)
    local s = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=pd.col, Thickness=1.5, Transparency=0.35, Parent=pb})
    local ts = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual, Color=Color3.new(0, 0, 0), Thickness=0.8, Transparency=0.5, Parent=pb})
    prefBtns[pd.key] = { btn = pb, stroke = s, textStroke = ts, col = pd.col }

    pb.MouseButton1Click:Connect(function()
        if pd.key == "M" and activeFlags["N"] then return end
        if pd.key == "N" and activeFlags["M"] then return end
        activeFlags[pd.key] = not activeFlags[pd.key]
        if activeFlags[pd.key] then
            local bright = pd.col:Lerp(Color3.new(1, 1, 1), 0.18)
            TweenService:Create(pb, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundColor3 = Color3.fromRGB(75, 75, 85), TextColor3       = bright, }):Play()
            TweenService:Create(s, TweenInfo.new(0.15), { Color        = bright, Thickness    = 1.8, Transparency = 0, }):Play()
        else
            TweenService:Create(pb, TweenInfo.new(0.15, Enum.EasingStyle.Quint), { BackgroundColor3 = Color3.fromRGB(22, 22, 34), TextColor3       = Color3.fromRGB(220, 220, 220), }):Play()
            TweenService:Create(s, TweenInfo.new(0.15), { Color        = pd.col, Thickness    = 1.5, Transparency = 0.35, }):Play()
        end
        updateInfoBox()
    end)
end

local infoSpacer = mk("Frame", {Size=UDim2.new(1, 0, 0, 5), BackgroundTransparency=1, Parent=controlFrame})

local infoBox = mk("Frame", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(0, 0, 0), BackgroundTransparency=0.42, Parent=controlFrame})
Instance.new("UICorner", infoBox).CornerRadius = UDim.new(0, 5)
local ibS = mk("UIStroke", {Color=Color3.fromRGB(200, 200, 210), Thickness=1.2, Transparency=0.6, Parent=infoBox})
local ibLayout = mk("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, HorizontalAlignment=Enum.HorizontalAlignment.Center, VerticalAlignment=Enum.VerticalAlignment.Center, Padding=UDim.new(0, 4), Parent=infoBox})

local flagCols = {
    M = Color3.fromRGB(170, 0,   255),
    N = Color3.fromRGB(0,   190, 80),
    F = Color3.fromRGB(0,   175, 255),
    R = Color3.fromRGB(255, 45,  145),
}

function updateInfoBox()
    for _, ch in ipairs(infoBox:GetChildren()) do
        if ch:IsA("TextLabel") then ch:Destroy() end
    end
    local cols, hasAny = {}, false
    for _, k in ipairs({ "M", "N", "F", "R" }) do
        if activeFlags[k] then
            hasAny = true
            table.insert(cols, flagCols[k])
            local lbl = mk("TextLabel", {Size=UDim2.new(0, 0, 1, 0), AutomaticSize=Enum.AutomaticSize.X, BackgroundTransparency=1, Text=k == "M" and "Mega Neon" or k == "N" and "Neon" or k == "F" and "Fly" or "Ride", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=flagCols[k]:Lerp(Color3.new(1, 1, 1), 0.18), TextXAlignment=Enum.TextXAlignment.Center, TextYAlignment=Enum.TextYAlignment.Center, Parent=infoBox})
        end
    end
    if not hasAny then
        local lbl = mk("TextLabel", {Size=UDim2.new(0, 0, 1, 0), AutomaticSize=Enum.AutomaticSize.X, BackgroundTransparency=1, Text="Normal", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=Color3.fromRGB(255, 255, 255), TextXAlignment=Enum.TextXAlignment.Center, TextYAlignment=Enum.TextYAlignment.Center, Parent=infoBox})
        TweenService:Create(ibS, TweenInfo.new(0.2), { Color        = Color3.fromRGB(200, 200, 210), Thickness    = 1.2, Transparency = 0.5, }):Play()
    else
        local r, g, b = 0, 0, 0
        for _, c in ipairs(cols) do
            local bright = c:Lerp(Color3.new(1, 1, 1), 0.18)
            r = r + bright.R; g = g + bright.G; b = b + bright.B
        end
        local blended = Color3.new(math.min(r / #cols, 1), math.min(g / #cols, 1), math.min(b / #cols, 1))
        TweenService:Create(ibS, TweenInfo.new(0.2), { Color        = blended, Thickness    = 1.5, Transparency = 0.2, }):Play()
    end
end
updateInfoBox()

local addSpacer = mk("Frame", {Size=UDim2.new(1, 0, 0, 5), BackgroundTransparency=1, Parent=controlFrame})

-- Add + Remove pet buttons side by side
local petBtnRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 13), BackgroundTransparency=1, Parent=controlFrame})

local addPetBtn = mk("TextButton", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0, 0, 0, 0), BackgroundColor3=Color3.fromRGB(0, 120, 220), Text="Add Pet", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=petBtnRow})
Instance.new("UICorner", addPetBtn).CornerRadius = UDim.new(0, 5)
local addPetStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 200, 255), Thickness=1.5, Parent=addPetBtn})

local removePetBtn = mk("TextButton", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0.5, 2, 0, 0), BackgroundColor3=Color3.fromRGB(180, 40, 40), Text="Remove Pet", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=petBtnRow})
Instance.new("UICorner", removePetBtn).CornerRadius = UDim.new(0, 5)
local removePetStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 80, 80), Thickness=1.5, Parent=removePetBtn})

local randomSpacer = mk("Frame", {Size=UDim2.new(1, 0, 0, 2), BackgroundTransparency=1, Parent=controlFrame})

local randomBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(100, 40, 160), BackgroundTransparency=0.2, Text="Add Random High Tier", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=controlFrame})
Instance.new("UICorner", randomBtn).CornerRadius = UDim.new(0, 5)
local randomBtnStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=1.5, Transparency=0.3, Parent=randomBtn})

local blockSpacer = mk("Frame", {Size=UDim2.new(1, 0, 0, 3), BackgroundTransparency=1, Parent=controlFrame})
local blockBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 8), BackgroundColor3=Color3.fromRGB(160, 30, 30), BackgroundTransparency=0.2, Text="Block Player", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=controlFrame})
Instance.new("UICorner", blockBtn).CornerRadius = UDim.new(0, 5)
local blockBtnStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 60, 60), Thickness=1.5, Transparency=0.3, Parent=blockBtn})

-- Silent block: triggers CoreGui block modal, hides it completely, clicks confirm
_G._silentBlockPlayer = nil  -- will be set after definition

-- Silencer: while any silent block is running (plus a short tail for the modal's closing animation) the
-- BlockingModalScreen is forced off-screen EVERY frame. The original only moved it until the confirm
-- button was found, so a modal that re-rendered / was re-shown between prompts could flash on screen.
if _G._silentBlockDebug == nil then _G._silentBlockDebug = true end   -- set false once it works
local function dbg(...)
    if _G._silentBlockDebug then print("[SilentBlock]", ...) end
end

-- Makes a whole GUI tree invisible (the original had this helper but never called it, so only the
-- Position trick hid the popup: if the popup re-laid-out, it was visible again).
local function hideTree(obj)
    pcall(function()
        if obj:IsA("GuiObject") then
            obj.BackgroundTransparency = 1
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                obj.TextTransparency = 1; obj.TextStrokeTransparency = 1
            end
            if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then obj.ImageTransparency = 1 end
            if obj:IsA("ScrollingFrame") then obj.ScrollBarImageTransparency = 1 end
            if obj:IsA("CanvasGroup") then obj.GroupTransparency = 1 end
        end
        if obj:IsA("UIStroke") then obj.Transparency = 1 end
        if obj:IsA("UIGradient") then obj.Enabled = false end
    end)
    for _, c in ipairs(obj:GetChildren()) do hideTree(c) end
end

-- Direct block with NO popup at all: Player:BlockUser, checked against the CoreScript blocked list.
-- It only counts as success if GetCore("GetBlockedUserIds") confirms it (otherwise we fall back to
-- the popup automation, so the control-panel button can never get worse).
local function silentDirectBlock(target)
    local StarterGui = game:GetService("StarterGui")
    local lp = Players.LocalPlayer
    local uid = target.UserId
    local function blockedHas()
        local ok, list = pcall(function() return StarterGui:GetCore("GetBlockedUserIds") end)
        if not (ok and type(list) == "table") then return nil end
        for _, id in ipairs(list) do if id == uid then return true end end
        return false
    end
    if blockedHas() == true then dbg("already blocked:", target.Name); return true end
    local okCall, err = pcall(function() lp:BlockUser(uid) end)
    dbg("BlockUser call:", okCall, okCall and "" or tostring(err))
    if not okCall then return false end
    local t = tick() + 1.5
    repeat
        local has = blockedHas()
        if has == true then return true end
        if has == nil then return false end   -- can't verify -> use the popup path instead
        task.wait(0.1)
    until tick() > t
    return false
end

local _silencer = { n = 0, conn = nil, seen = setmetatable({}, { __mode = "k" }), sizes = setmetatable({}, { __mode = "k" }) }
-- true / false = is this user id in the game's blocked list; nil = the list can't be read
_silencer.isBlocked = function(uid)
    local okB, list = pcall(function() return game:GetService("StarterGui"):GetCore("GetBlockedUserIds") end)
    if not (okB and type(list) == "table") then return nil end
    for _, id in ipairs(list) do if id == uid then return true end end
    return false
end
local function silencerStart()
    _silencer.n = _silencer.n + 1
    if _silencer.conn then return end
    local CoreGui = game:GetService("CoreGui")
    _silencer.conn = game:GetService("RunService").Heartbeat:Connect(function()
        pcall(function()
            local ov = CoreGui:FindFirstChild("FoundationOverlay")
            if not ov then return end
            local scr = ov:FindFirstChild("BlockingModalScreen", true)
            if not scr then return end
            local modal = scr:FindFirstChild("AlertModal", true)

            -- the dialog stays VISIBLE, but the dark full-screen backdrop is removed
            local function clearBackdrop(d)
                if not d:IsA("GuiObject") then return end
                if modal and (d == modal or d:IsDescendantOf(modal)) then return end
                local full = d.Size.X.Scale >= 0.99 and d.Size.Y.Scale >= 0.99
                local named = d.Name == "BlockingModalContainer" or d.Name == "BlockingModalContainerWrapper" or d.Name == "BlockingModal"
                if (full or named or d == scr) and d.BackgroundTransparency < 1 then d.BackgroundTransparency = 1 end
            end
            pcall(function() ov.BackgroundTransparency = 1 end)
            if not _silencer.seen[scr] then
                _silencer.seen[scr] = true
                dbg("popup appeared -> parked at the side, auto-click next")
                clearBackdrop(scr)
                for _, d in ipairs(scr:GetDescendants()) do pcall(clearBackdrop, d) end
                scr.DescendantAdded:Connect(function(d) pcall(clearBackdrop, d) end)
            end

            -- park the dialog on the FAR RIGHT edge, mostly off-screen (only a sliver visible), as a wide rectangle
            -- (re-applied every frame so a re-layout can't pull it back or change its shape).
            -- _G._blockModalSide = "left" mirrors it to the left edge; _G._blockModalPush = extra fraction of
            -- its width pushed off-screen (default 0.4 = ~10% visible; 0 = half visible).
            -- _G._blockModalRatio = length:width ratio (default 3).
            if modal and modal:IsA("GuiObject") then
                local info = _silencer.sizes[modal]
                if not info then
                    local abs = modal.AbsoluteSize
                    if abs.X > 0 and abs.Y > 0 then
                        -- keep the dialog's real height, make it RATIO times as long as it is tall
                        info = { w = abs.Y * (tonumber(_G._blockModalRatio) or 3), h = abs.Y }
                        _silencer.sizes[modal] = info
                    end
                end
                local right = _G._blockModalSide ~= "left"
                local push  = (tonumber(_G._blockModalPush) or 0.4) * (info and info.w or modal.AbsoluteSize.X)
                modal.AnchorPoint = Vector2.new(0.5, 0.5)          -- centre on the edge = half off-screen, then pushed further
                modal.Position    = UDim2.new(right and 1 or 0, right and push or -push, 0.5, 0)
                if info then modal.Size = UDim2.fromOffset(info.w, info.h) end
                for _, c in ipairs(modal:GetChildren()) do          -- stop size constraints from re-stretching it
                    if c:IsA("UISizeConstraint") then pcall(function()
                        c.MinSize = Vector2.new(0, 0)
                        c.MaxSize = Vector2.new(info and info.w or c.MaxSize.X, info and info.h or c.MaxSize.Y)
                    end) end
                end
            end
        end)
    end)
end
local function silencerStop(tail)
    task.delay(tail or 0.8, function()
        _silencer.n = math.max(0, _silencer.n - 1)
        if _silencer.n == 0 and _silencer.conn then
            _silencer.conn:Disconnect()
            _silencer.conn = nil
        end
    end)
end
local function silentBlockPlayer(targetPlayer, onDone)   -- onDone(success) fires when finished
    if not targetPlayer then if onDone then pcall(onDone, false) end return end
    task.spawn(function()
        pcall(function() setthreadidentity(8) end)
        silencerStart()

        -- 1) try the popup-less direct block first (only trusted when verified)
        if _G._silentBlockDirect ~= false and silentDirectBlock(targetPlayer) then
            dbg("blocked via direct API:", targetPlayer.Name)
            blockBtn.Text = "Block Player | Success"
            blockBtn.TextColor3 = Color3.fromRGB(100, 255, 140)
            task.delay(1, function()
                blockBtn.Text = "Block Player"
                blockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            end)
            silencerStop(0.2)
            pcall(function() setthreadidentity(2) end)
            if onDone then pcall(onDone, true) end
            return
        end
        dbg("direct block unavailable -> popup automation for", targetPlayer.Name)

        local StarterGui = game:GetService("StarterGui")
        local CoreGui    = game:GetService("CoreGui")
        local RunService = game:GetService("RunService")
        local VIM        = game:GetService("VirtualInputManager")
        local GuiService = game:GetService("GuiService")

        local function hideAll(obj)
            safeCall(function()
                if obj:IsA("GuiObject") then
                    obj.BackgroundTransparency = 1
                    obj.BorderSizePixel = 0
                    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                        obj.TextTransparency = 1
                        obj.TextStrokeTransparency = 1
                    end
                    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                        obj.ImageTransparency = 1
                    end
                    if obj:IsA("ScrollingFrame") then
                        obj.ScrollBarImageTransparency = 1
                        obj.ScrollBarThickness = 0
                    end
                end
                if obj:IsA("UIStroke")     then obj.Transparency = 1 end
                if obj:IsA("UIGradient")   then obj.Enabled = false end
                if obj:IsA("SelectionBox") then obj.SurfaceTransparency = 1 obj.LineThickness = 0 end
                if obj:IsA("Frame")        then obj.BorderSizePixel = 0 end
                if obj:IsA("CanvasGroup")  then obj.GroupTransparency = 1 end
            end)
            for _, child in ipairs(obj:GetChildren()) do
                hideAll(child)
            end
        end

        -- Hook FoundationOverlay BEFORE triggering the prompt so we hide it
        -- the exact frame it appears — before Roblox renders it even once
        StarterGui:SetCore("PromptBlockPlayer", targetPlayer)
        dbg("prompt requested for", targetPlayer.Name)

        local confirmBtn = nil
        local foundScreen = nil
        local btnSeenAt, hookedDesc = nil, false

        -- the modal text names the player being blocked: only confirm once it is THIS player's prompt
        -- (back-to-back blocks can otherwise grab the previous, stale prompt's button)
        local function mentionsTarget(screen)
            local n1 = (targetPlayer.Name or ""):lower()
            local n2 = (targetPlayer.DisplayName or ""):lower()
            for _, d in ipairs(screen:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local t = (d.Text or ""):lower()
                    if (n1 ~= "" and t:find(n1, 1, true)) or (n2 ~= "" and t:find(n2, 1, true)) then return true end
                end
            end
            return false
        end

        -- Watch CoreGui and FoundationOverlay for BlockingModalScreen appearing
        -- This covers both: FoundationOverlay already exists, or gets created now
        local function watchOverlay(overlay)
            safeCall(function()
                overlay.BackgroundTransparency = 1
                overlay.BackgroundColor3 = Color3.new(0, 0, 0)
            end)
            local existing = overlay:FindFirstChild("BlockingModalScreen", true)
            if existing then
                foundScreen = existing
                -- (the silencer parks it at the side)
                return
            end
            overlay.ChildAdded:Connect(function(child)
                if child.Name == "BlockingModalScreen" and not foundScreen then
                    foundScreen = child
                    -- (the silencer parks it at the side)
                end
            end)
            -- Also deep-watch in case it's nested
            overlay.DescendantAdded:Connect(function(desc)
                if desc.Name == "BlockingModalScreen" and not foundScreen then
                    foundScreen = desc
                    -- (the silencer parks it at the side)
                end
            end)
        end

        local overlay = CoreGui:FindFirstChild("FoundationOverlay")
        if overlay then
            watchOverlay(overlay)
        else
            CoreGui.ChildAdded:Connect(function(child)
                if child.Name == "FoundationOverlay" then
                    watchOverlay(child)
                end
            end)
        end

        -- Wait for "3" button to exist — first time React takes longer to render the tree
        local deadline = tick() + 6
        while not confirmBtn and tick() < deadline do
            RunService.Heartbeat:Wait()
            safeCall(function()
                local screen = foundScreen
                if not screen then
                    local ov = CoreGui:FindFirstChild("FoundationOverlay")
                    if ov then screen = ov:FindFirstChild("BlockingModalScreen", true) end
                end
                if not screen then return end
                -- (the silencer parks it at the side)
                -- "3" may not exist yet on first render — keep waiting
                local btn = screen:FindFirstChild("3", true)
                if not btn then
                    -- Hook DescendantAdded (once) to catch it when React adds it
                    if not hookedDesc then
                        hookedDesc = true
                        screen.DescendantAdded:Connect(function(d)
                            if d.Name == "3" and not confirmBtn then
                                confirmBtn = d
                            end
                        end)
                    end
                    return
                end
                btnSeenAt = btnSeenAt or tick()
                -- confirm when the prompt shows this player's name (or after 2.5s if the text can't be read)
                if mentionsTarget(screen) or (tick() - btnSeenAt) > 0.6 then confirmBtn = btn end
            end)
        end

        if not confirmBtn then
            dbg("FAILED: no confirm button found. popup seen =", foundScreen ~= nil,
                "| FoundationOverlay exists =", CoreGui:FindFirstChild("FoundationOverlay") ~= nil)
            silencerStop(0.8)
            pcall(function() setthreadidentity(2) end)
            if onDone then pcall(onDone, false) end
            return
        end

        -- Press confirm (selection + Return + gamepad A + Activate), then CHECK the block really happened.
        -- The old animation pressed once and assumed success; now the result is verified against the
        -- game's blocked list and the press is retried once if the popup swallowed it.
        local function pressConfirm()
            dbg("pressing confirm for", targetPlayer.Name)
            GuiService.SelectedObject = confirmBtn
            RunService.Heartbeat:Wait()
            VIM:SendKeyEvent(true,  Enum.KeyCode.Return,  false, game)
            VIM:SendKeyEvent(false, Enum.KeyCode.Return,  false, game)
            VIM:SendKeyEvent(true,  Enum.KeyCode.ButtonA, false, game)
            VIM:SendKeyEvent(false, Enum.KeyCode.ButtonA, false, game)
            RunService.Heartbeat:Wait()   -- one frame so the key events are processed while the button is still selected
            GuiService.SelectedObject = nil
            pcall(function() confirmBtn:Activate() end)
            pcall(function() confirmBtn:Activate() end)
        end

        local verified = nil   -- true = confirmed blocked, false = not blocked, nil = the game can't tell us
        for attempt = 1, 2 do
            pressConfirm()
            local waitUntil = tick() + 1.2
            repeat
                RunService.Heartbeat:Wait()
                verified = _silencer.isBlocked(targetPlayer.UserId)
            until verified ~= false or tick() > waitUntil
            if verified ~= false then break end   -- true, or unverifiable (assumed ok like the old version)
            dbg("block not confirmed, retrying (attempt " .. attempt .. ")")
            pcall(function()   -- the popup may have re-rendered: grab the current confirm button
                local ov  = CoreGui:FindFirstChild("FoundationOverlay")
                local scr = foundScreen or (ov and ov:FindFirstChild("BlockingModalScreen", true))
                local b   = scr and scr:FindFirstChild("3", true)
                if b then confirmBtn = b end
            end)
        end
        local success = verified ~= false

        blockBtn.Text = success and "Block Player | Success" or "Block Player | Failed"
        blockBtn.TextColor3 = success and Color3.fromRGB(100, 255, 140) or Color3.fromRGB(255, 120, 120)
        task.delay(1, function()
            blockBtn.Text = "Block Player"
            blockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        end)

        silencerStop(0.8)
        pcall(function() setthreadidentity(2) end)
        if onDone then pcall(onDone, success) end
    end)
end
_G._silentBlockPlayer = silentBlockPlayer

-- Sequential multi-block using the SAME silent logic. Each player is fully finished (and the previous
-- CoreGui block modal has closed) before the next prompt opens, so prompts never overlap.
_G._silentBlockMany = function(list, onProgress, onDone)
    task.spawn(function()
        pcall(function() setthreadidentity(8) end)
        silencerStart()                      -- modal stays hidden for the WHOLE run, including the gaps
        local CoreGui = game:GetService("CoreGui")
        local okCount = 0
        for i, p in ipairs(list) do
            if onProgress then pcall(onProgress, i, #list) end
            if p and p.Parent then
                local finished, success = false, false
                silentBlockPlayer(p, function(ok) finished, success = true, ok end)
                local deadline = tick() + 12
                while not finished and tick() < deadline do RunService.Heartbeat:Wait() end
                if success then okCount = okCount + 1 end
                local closeBy = tick() + 1.5
                while tick() < closeBy do
                    local still = false
                    local okC = pcall(function()
                        local ov = CoreGui:FindFirstChild("FoundationOverlay")
                        still = ov ~= nil and ov:FindFirstChild("BlockingModalScreen", true) ~= nil
                    end)
                    if okC and not still then break end
                    if not okC then task.wait(0.8) break end   -- can't inspect CoreGui: fixed pause instead
                    RunService.Heartbeat:Wait()
                end
                task.wait(0.05)
            end
        end
        silencerStop(0.8)
        pcall(function() setthreadidentity(2) end)
        if onDone then pcall(onDone, okCount, #list) end
    end)
end

blockBtn.MouseButton1Click:Connect(function()
    local name = partnerBox.Text
    if not name or name == "" then return end
    -- PromptBlockPlayer requires a real Player instance in the server
    local target = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == name:lower() then
            target = p
            break
        end
    end
    if not target then
        -- Player not in server — show hint
        local HintApp = UIManager.apps.HintApp
        if HintApp then
            HintApp:hint({ text = name .. " is not in this server.", length = 3, overridable = true, yields = false })
        end
        return
    end
    silentBlockPlayer(target)
end)

partnerBox.FocusLost:Connect(function()
    updatePartnerFromUsername(partnerBox.Text)
end)
acceptBox.FocusLost:Connect(function()
    local v = tonumber(acceptBox.Text)
    if v and v >= 0 then CONFIG.AUTO_ACCEPT_DELAY = v
    else acceptBox.Text = tostring(CONFIG.AUTO_ACCEPT_DELAY) end
end)
confirmBox.FocusLost:Connect(function()
    local v = tonumber(confirmBox.Text)
    if v and v >= 0 then CONFIG.AUTO_CONFIRM_DELAY = v
    else confirmBox.Text = tostring(CONFIG.AUTO_CONFIRM_DELAY) end
end)
spectatorBox.FocusLost:Connect(function()
    local v = tonumber(spectatorBox.Text)
    if v and v >= 0 then
        CONFIG.SPECTATOR_COUNT = v
        if mockState.active and autoEnabled then
            if v > 0 then
                startSpectatorLoop()
            else
                stopSpectatorAndReactionLoops()
                if mockState.trade then
                    mockState.trade.subscriber_count = 0
                    pcall(function() TradeApp:_overwrite_local_trade_state(mockState.trade) end)
                    pcall(function() TradeApp:refresh_all() end)
                end
            end
        end
    else
        spectatorBox.Text = tostring(CONFIG.SPECTATOR_COUNT)
    end
end)
initButton.MouseButton1Click:Connect(function()
    -- This fixes the stale partner bug after switching usernames during a trade
    local currentName = partnerBox.Text
    if currentName and currentName ~= "" and currentName ~= CONFIG.PARTNER_NAME then
        CONFIG.PARTNER_NAME = currentName
        CONFIG.PARTNER_USER_ID = 0
        mockPartner = createMockPartner()
    elseif currentName and currentName == CONFIG.PARTNER_NAME and CONFIG.PARTNER_USER_ID == 0 then
        task.spawn(function()
            local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(currentName) end)
            if ok and uid then CONFIG.PARTNER_USER_ID = uid; mockPartner = createMockPartner() end
        end)
    end
    initializeMockTrade()
end)
addPetBtn.MouseButton1Click:Connect(function()
    local n = petBox.Text
    if n and n ~= "" then task.spawn(addPetToPartnerOffer, n, activeFlags) end
end)
removePetBtn.MouseButton1Click:Connect(function()
    removeLatestPetFromPartnerOffer()
end)
randomBtn.MouseButton1Click:Connect(function()
    task.spawn(addRandomHighTier)
end)

-- Partner Accept / Partner Unaccept buttons
end do local partnerAcceptSpacer = mk("Frame", {Size=UDim2.new(1, 0, 0, 3), BackgroundTransparency=1, Parent=controlFrame})

end do local partnerAcceptRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 13), BackgroundTransparency=1, Parent=controlFrame})

local partnerAcceptBtn = mk("TextButton", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0, 0, 0, 0), BackgroundColor3=Color3.fromRGB(30, 80, 50), BackgroundTransparency=0.2, Text="Partner Accept", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80, 255, 130), Parent=partnerAcceptRow})
Instance.new("UICorner", partnerAcceptBtn).CornerRadius = UDim.new(0, 5)
local partnerAcceptStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=1.5, Transparency=0.3, Parent=partnerAcceptBtn})

local partnerUAcceptBtn = mk("TextButton", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0.5, 2, 0, 0), BackgroundColor3=Color3.fromRGB(80, 30, 30), BackgroundTransparency=0.2, Text="Partner Unaccept", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 90, 90), Parent=partnerAcceptRow})
Instance.new("UICorner", partnerUAcceptBtn).CornerRadius = UDim.new(0, 5)
local partnerUAcceptStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 60, 60), Thickness=1.5, Transparency=0.3, Parent=partnerUAcceptBtn})

-- Use the exact same state logic as the keybinds:
-- Partner Accept = negotiated in negotiation, confirmed in confirmation.
local function mockPartnerAccept()
    if not mockState.active or not mockState.trade then return end

    local _, myKey = TradeApp:_get_my_offer()
    local partnerKey = (myKey == "sender_offer") and "recipient_offer" or "sender_offer"
    local stage = TradeApp:_get_current_trade_stage()

    if stage == "confirmation" then
        -- IMPORTANT: do not touch negotiated/current_stage here.
        -- The confirmation-stage tick is the partner's Confirm tick.
        mockState.trade[partnerKey].confirmed = true
    else
        mockState.trade[partnerKey].negotiated = true
    end

    mockState.trade.offer_version = (mockState.trade.offer_version or 1) + 1
    TradeApp:_overwrite_local_trade_state(mockState.trade)
    if TradeApp.refresh_all then TradeApp:refresh_all() end
end

-- Partner Unaccept = the same action/state change used by the U keybind.
local function mockPartnerUnaccept()
    if not mockState.active or not mockState.trade then return end

    local _, myKey = TradeApp:_get_my_offer()
    local partnerKey = (myKey == "sender_offer") and "recipient_offer" or "sender_offer"

    mockState.trade[partnerKey].negotiated = false
    mockState.trade.offer_version = (mockState.trade.offer_version or 1) + 1
    TradeApp:_overwrite_local_trade_state(mockState.trade)
    if TradeApp.refresh_all then TradeApp:refresh_all() end
end

partnerAcceptBtn.MouseButton1Click:Connect(mockPartnerAccept)
partnerUAcceptBtn.MouseButton1Click:Connect(mockPartnerUnaccept)

-- Cancel Trade = behave exactly like the partner declining the trade.
-- Use the TradeApp decline path so the whole trade UI/state disappears cleanly.
end do local cancelTradeSpacer = mk("Frame", {Size=UDim2.new(1, 0, 0, 3), BackgroundTransparency=1, Parent=controlFrame})
end local cancelTradeButton = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(80, 30, 30), BackgroundTransparency=0.2, Text="Cancel Trade", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 90, 90), Parent=controlFrame})
Instance.new("UICorner", cancelTradeButton).CornerRadius = UDim.new(0, 5)
local cancelTradeStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 60, 60), Thickness=1.5, Transparency=0.3, Parent=cancelTradeButton})

cancelTradeButton.MouseButton1Click:Connect(function()
    if not mockState.active or not mockState.trade then return end
    TradeApp:_decline_trade(true)
end)

end -- CONTROL TAB do block

do
local playersFrame = tabFrames["Players"]

local customUsers = {
    {displayName = "0071219",             userId = 5651733505},
    {displayName = "a7ciq",               userId = 4785815547},
    {displayName = "bottleofthewater1",   userId = 8997575790},
    {displayName = "candyaregoated",      userId = 7474344877},
    {displayName = "caticaaa",            userId = 531075038},
    {displayName = "coolrainbow_dash2011",userId = 205386059},
    {displayName = "crafredicra",         userId = 1068227568},
    {displayName = "cris_24248",          userId = 2756771717},
    {displayName = "crnzqn",              userId = 5837852011},
    {displayName = "daisygirl6790",       userId = 0},
    {displayName = "danibanini_boi",      userId = 3823255098},
    {displayName = "flowergirlbunny555",  userId = 1408366882},
    {displayName = "fresh_fries984",      userId = 3814573204},
    {displayName = "girllll_crazy",       userId = 8168180345},
    {displayName = "landz_10",            userId = 1790233865},
    {displayName = "ling_15master",       userId = 1847186417},
    {displayName = "lol_xd141618",        userId = 4450334271},
    {displayName = "luv_x111",            userId = 5495319707},
    {displayName = "maryamcin",           userId = 1931527172},
    {displayName = "mdz_1219",            userId = 5259042075},
    {displayName = "memocaritamalvada",   userId = 2365311822},
    {displayName = "moisesgattoperdida",  userId = 4773927754},
    {displayName = "notsuperhero22321a",  userId = 2939736508},
    {displayName = "nyaashka_lavki",      userId = 5183439499},
    {displayName = "pergie41",            userId = 1444201029},
    {displayName = "rhae_mango333",       userId = 692474013},
    {displayName = "sasas3013",           userId = 971287458},
    {displayName = "saturnsecho",         userId = 5229973758},
    {displayName = "silentscenes",        userId = 2352256611},
    {displayName = "singboo1",            userId = 0},
    {displayName = "v4mp1ahz",            userId = 4263229599},
    {displayName = "winklebort",          userId = 232192602},
}

-- Preset users with userId = 0 are resolved from their username (real Roblox lookup), so you can add
-- someone by name only: {displayName = "somename", userId = 0}. Failed lookups stay 0 and are skipped
-- by Random Partner.
local function resolvePresetId(user)
    if user.userId and user.userId > 0 then return user.userId end
    local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(user.displayName) end)
    if ok and type(id) == "number" and id > 0 then user.userId = id end
    return user.userId
end

task.spawn(function()
    for _, user in ipairs(customUsers) do
        if not (user.userId and user.userId > 0) then resolvePresetId(user) end
        if user.userId and user.userId > 0 then
            _G._prefetchUserInfo(user.userId)
            task.wait(0.08)
        end
    end
end)

-- Helper: select a user (server player or preset) and go to Control tab
local function selectUser(name, userId)
    setActiveTab("Control")
    partnerBox.Text = name
    if mockState.active or _tradeRequestPending then return end
    if userId then
        CONFIG.PARTNER_NAME   = name
        CONFIG.PARTNER_USER_ID = userId
        mockPartner = createMockPartner()
    else
        updatePartnerFromUsername(name)
    end
    TweenService:Create(partnerStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Color = Color3.fromRGB(190,34,230), Thickness = 1.3, }):Play()
    task.delay(0.5, function()
        TweenService:Create(partnerStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Color = Color3.fromRGB(100, 100, 100), Thickness = 0.7, }):Play()
    end)
end

do local selectPartnerBtn = mk("TextButton", {Size=UDim2.new(0.82, -2, 0, 14), BackgroundColor3=Color3.fromRGB(30, 60, 80), BackgroundTransparency=0.15, Text="⟳  Select Partner", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(80, 200, 255), Parent=playersFrame})
Instance.new("UICorner", selectPartnerBtn).CornerRadius = UDim.new(0, 3)
local selectPartnerStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(80, 200, 255), Thickness=0.7, Transparency=0.4, Parent=selectPartnerBtn})
selectPartnerBtn.MouseButton1Click:Connect(function()
    local state = TradeApp:_get_local_trade_state()
    if not state then
        TweenService:Create(selectPartnerStroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(255, 60, 60) }):Play()
        task.delay(0.4, function()
            TweenService:Create(selectPartnerStroke, TweenInfo.new(0.3), { Color = Color3.fromRGB(80, 200, 255) }):Play()
        end)
        return
    end
    local me = Players.LocalPlayer
    local partner = (state.sender == me or state.sender.UserId == me.UserId)
        and state.recipient or state.sender
    if partner then
        selectUser(partner.Name, partner.UserId)
        TweenService:Create(selectPartnerStroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(0, 255, 120) }):Play()
        task.delay(0.4, function()
            TweenService:Create(selectPartnerStroke, TweenInfo.new(0.3), { Color = Color3.fromRGB(80, 200, 255) }):Play()
        end)
    end
end)


-- 🎲 Random Partner: picks a random preset (fake) user and puts them in the partner box.
-- It does NOT start a trade: press Start Trade yourself when you're ready.
end do local randomPartnerBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 14), Position=UDim2.new(0, 0, 0, 16), BackgroundColor3=Color3.fromRGB(70, 40, 90), BackgroundTransparency=0.15, Text="🎲  Random Partner", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(230, 170, 255), Parent=playersFrame})
Instance.new("UICorner", randomPartnerBtn).CornerRadius = UDim.new(0, 3)
local randomPartnerStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190, 34, 230), Thickness=0.7, Transparency=0.4, Parent=randomPartnerBtn})
local lastRandomPartner = nil
local function pickRandomPartner()
    local function flash(color)
        TweenService:Create(randomPartnerStroke, TweenInfo.new(0.15), { Color = color }):Play()
        task.delay(0.4, function()
            TweenService:Create(randomPartnerStroke, TweenInfo.new(0.3), { Color = Color3.fromRGB(190, 34, 230) }):Play()
        end)
    end
    -- can't swap partners while a trade (or a trade-request dialog) is already up
    if mockState.active or _tradeRequestPending then flash(Color3.fromRGB(255, 60, 60)); return end
    local pool = {}
    for _, u in ipairs(customUsers) do
        if u.userId and u.userId > 0 and u.displayName ~= lastRandomPartner then pool[#pool + 1] = u end
    end
    if #pool == 0 then return end
    local u = pool[math.random(1, #pool)]
    lastRandomPartner = u.displayName            -- never the same partner twice in a row
    flash(Color3.fromRGB(0, 255, 120))
    selectUser(u.displayName, u.userId)          -- fills the partner box + builds the mock partner (no trade sent)
end
randomPartnerBtn.MouseButton1Click:Connect(pickRandomPartner)
_G._randomPartner = pickRandomPartner

-- Anti Raid pop-out launcher
end do local popOutBtn = mk("TextButton", {Size=UDim2.new(0.18, 0, 0, 14), Position=UDim2.new(0.82, 2, 0, 0), BackgroundColor3=Color3.fromRGB(80,30,30), BackgroundTransparency=0.15, Text="🛡️", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=Color3.fromRGB(255,90,90), Parent=playersFrame})
Instance.new("UICorner", popOutBtn).CornerRadius = UDim.new(0, 3)
local popOutStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(220,50,50), Thickness=0.7, Transparency=0.4, Parent=popOutBtn})
_G._antiPopoutBtn = popOutBtn
_G._antiPopoutStroke = popOutStroke
popOutBtn.MouseButton1Click:Connect(function()
    if _G._toggleAntiPopup then _G._toggleAntiPopup() end
end)

end do local serverHeader = mk("TextLabel", {Size=UDim2.new(0.48, 0, 0, 11), Position=UDim2.new(0, 0, 0, 32), BackgroundTransparency=1, Text="Server", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(160, 160, 180), TextXAlignment=Enum.TextXAlignment.Center, Parent=playersFrame})

end do local presetHeader = mk("TextLabel", {Size=UDim2.new(0.48, 0, 0, 11), Position=UDim2.new(0.52, 0, 0, 32), BackgroundTransparency=1, Text="Presets", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(160, 160, 180), TextXAlignment=Enum.TextXAlignment.Center, Parent=playersFrame})

end local function makeColumn(xPos, width)
    local sf = mk("ScrollingFrame", {Size=UDim2.new(width, 0, 1, -43), Position=UDim2.new(xPos, 0, 0, 43), BackgroundColor3=Color3.fromRGB(25, 25, 35), BackgroundTransparency=0.5, BorderSizePixel=0, ScrollBarThickness=2, ScrollBarImageColor3=Color3.fromRGB(100, 100, 100), ScrollBarImageTransparency=0.5, CanvasSize=UDim2.new(0, 0, 0, 0), Parent=playersFrame})
    Instance.new("UICorner", sf).CornerRadius = UDim.new(0, 4)
    local layout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0, 3), Parent=sf})
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end)
    local pad = mk("UIPadding", {PaddingTop=UDim.new(0, 4), PaddingBottom=UDim.new(0, 4), PaddingLeft=UDim.new(0, 4), PaddingRight=UDim.new(0, 4), Parent=sf})
    return sf, layout
end

local serverColumn = makeColumn(0,    0.48)
do local presetColumn = makeColumn(0.52, 0.48)

local function makeRowBtn(parent, text, index)
    local btn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 22), BackgroundColor3=Color3.fromRGB(40, 40, 52), BackgroundTransparency=0.2, Text="", LayoutOrder=index, BorderSizePixel=0, Parent=parent})
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    local stroke = mk("UIStroke", {Color=Color3.fromRGB(80, 80, 80), Thickness=0.8, Transparency=0.5, Parent=btn})
    local lbl = mk("TextLabel", {Size=UDim2.new(1, -6, 1, 0), Position=UDim2.new(0, 4, 0, 0), BackgroundTransparency=1, Text=text, Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(235, 235, 255), TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Parent=btn})
    return btn, stroke
end

-- Wire a row button's tap feedback (quick transparency pulse) + click action.
local function bindRowClick(btn, onClick)
    btn.MouseButton1Click:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.05 }):Play()
        task.delay(0.12, function()
            TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { BackgroundTransparency = 0.2 }):Play()
        end)
        onClick()
    end)
end

for i, user in ipairs(customUsers) do
    local btn, stroke = makeRowBtn(presetColumn, user.displayName, i)
    bindRowClick(btn, function()
        if not (user.userId and user.userId > 0) then resolvePresetId(user) end   -- not resolved yet? do it now
        if user.userId and user.userId > 0 then selectUser(user.displayName, user.userId)
        else selectUser(user.displayName) end                                     -- fall back to name lookup
    end)
end

refreshPlayerList = function()
    for _, child in ipairs(serverColumn:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    playerListButtons = {}
    local list = Players:GetPlayers()
    table.sort(list, function(a, b) return a.Name:lower() < b.Name:lower() end)
    for i, player in ipairs(list) do
        local btn, stroke = makeRowBtn(serverColumn, player.Name, i)
        btn.BackgroundTransparency = 1
        stroke.Transparency        = 1
        local lbl = btn:FindFirstChildOfClass("TextLabel")
        if lbl then lbl.TextTransparency = 1 end
        table.insert(playerListButtons, btn)
        bindRowClick(btn, function() selectUser(player.Name, player.UserId) end)
    end
    -- Also refresh the Rich Board tab so player joins/leaves update it
    if _G._richBoard and _G._richBoard.Parent and _G._richBoardRefresh then _G._richBoardRefresh("debounced") end
end

animatePlayerList = function()
    for i, btn in ipairs(playerListButtons) do
        task.spawn(function()
            task.wait((i-1) * 0.06)
            local stroke = btn:FindFirstChildOfClass("UIStroke")
            local lbl    = btn:FindFirstChildOfClass("TextLabel")
            TweenService:Create(btn, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { BackgroundTransparency = 0.2, }):Play()
            if stroke then TweenService:Create(stroke, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Transparency = 0.5 }):Play() end
            if lbl    then TweenService:Create(lbl,    TweenInfo.new(0.2,  Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play() end
        end)
    end
end

end do local function selectRandomPresetUser()
    local user = customUsers[math.random(1, #customUsers)]
    if not (user.userId and user.userId > 0) then resolvePresetId(user) end
    if user.userId and user.userId > 0 then selectUser(user.displayName, user.userId) else selectUser(user.displayName) end
end
_G._selectRandomPresetUser = selectRandomPresetUser
_G._selectUser = selectUser

refreshPlayerList()

Players.PlayerAdded:Connect(function()
    hasShownAnimation["Players"] = false
    refreshPlayerList()
    if currentTab == "Players" then
        hasShownAnimation["Players"] = true
        animatePlayerList()
    end
end)
Players.PlayerRemoving:Connect(function()
    hasShownAnimation["Players"] = false
    refreshPlayerList()
    if currentTab == "Players" then
        hasShownAnimation["Players"] = true
        animatePlayerList()
    end
end)

end local playerListFrame = serverColumn

end -- PLAYERS TAB do block

do
local petsFrame  = tabFrames["Misc"]
local miscFrame  = petsFrame

local miscLayout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0, 4), Parent=miscFrame})

do

local _amvggCache = nil
local _amvggFetching = false
local _amvggCallbacks = {}

-- Scan a balanced JSON array starting 7 chars after `ps` in `text`, decode it.
-- Returns the decoded table, or nil on failure.
local function decodeJsonArrayAt(text, ps)
    local ai = ps + 7
    local depth, i, inStr, esc = 0, ai, false, false
    while i <= #text do
        local c = text:sub(i, i)
        if esc then esc = false
        elseif c == '\\' and inStr then esc = true
        elseif c == '"' then inStr = not inStr
        elseif not inStr then
            if c == '[' or c == '{' then depth = depth + 1
            elseif c == ']' or c == '}' then
                depth = depth - 1
                if depth == 0 then break end
            end
        end
        i = i + 1
    end
    local ok2, raw = pcall(function()
        return game:GetService("HttpService"):JSONDecode(text:sub(ai, i))
    end)
    if ok2 and type(raw) == "table" then return raw end
    return nil
end
_G._decodeJsonArrayAt = decodeJsonArrayAt  -- expose: _fhFetchAmvgg lives outside this do-block

local function httpGet(url)
    local ok, res = pcall(function()
        return request({ Url = url, Method = "GET", Headers = { ["RSC"] = "1" } })
    end)
    if ok and res and res.Body then return res.Body end
    local ok2, body = pcall(function() return HttpGet(url) end)
    if ok2 and body then return body end
    local ok3, body3 = pcall(function()
        return game:GetService("HttpService"):GetAsync(url, true)
    end)
    if ok3 and body3 then return body3 end
    return nil
end

local function fetchAmvgg(cb)
    if _amvggCache then cb(_amvggCache) return end
    table.insert(_amvggCallbacks, cb)
    if _amvggFetching then return end
    _amvggFetching = true
    task.spawn(function()
        local ok, text = pcall(httpGet, "https://amvgg.com/values/pets?_rsc=19zvn")
        if not ok or type(text) ~= "string" then
            _amvggFetching = false
            for _, fn in ipairs(_amvggCallbacks) do pcall(fn, nil) end
            _amvggCallbacks = {}
            return
        end
        local ps = text:find('"pets":%[{')
        if not ps then
            _amvggFetching = false
            for _, fn in ipairs(_amvggCallbacks) do pcall(fn, nil) end
            _amvggCallbacks = {}
            return
        end
        local raw = decodeJsonArrayAt(text, ps)
        if not raw then
            _amvggFetching = false
            for _, fn in ipairs(_amvggCallbacks) do pcall(fn, nil) end
            _amvggCallbacks = {}
            return
        end
        local cache = {}
        for _, p in ipairs(raw) do
            if p.name then
                local function n(v) return tonumber(v) or 0 end
                cache[p.name:lower()] = {
                    r            = n(p.fValue),
                    fr           = n(p.regularValue),
                    neon_regular = n(p.npNeonValue),
                    nf           = n(p.nfValue) ~= 0 and n(p.nfValue) or n(p.neonValue),
                    nr           = n(p.nrValue) ~= 0 and n(p.nrValue) or n(p.neonValue),
                    nfr          = n(p.neonValue),
                    mega_regular = n(p.npMegaValue),
                    mf           = n(p.mfValue) ~= 0 and n(p.mfValue) or n(p.megaValue),
                    mr           = n(p.mrValue) ~= 0 and n(p.mrValue) or n(p.megaValue),
                    mfr          = n(p.megaValue),
                }
            end
        end
        _amvggCache = cache
        _amvggFetching = false
        local cbs = _amvggCallbacks
        _amvggCallbacks = {}
        for _, fn in ipairs(cbs) do pcall(fn, cache) end
    end)
end
_G._fetchAmvgg = fetchAmvgg

local function getVariantKey(props)
    if not props then return "r" end
    if props.mega_neon then
        if props.flyable and props.rideable then return "mfr"
        elseif props.flyable  then return "mf"
        elseif props.rideable then return "mr"
        else return "mega_regular" end
    elseif props.neon then
        if props.flyable and props.rideable then return "nfr"
        elseif props.flyable  then return "nf"
        elseif props.rideable then return "nr"
        else return "neon_regular" end
    elseif props.flyable or props.rideable then return "fr"
    else return "r" end
end

local function getPetVal(pd, vk)
    if not pd then return 0 end
    local v = pd[vk] or 0
    if v == 0 then
        if vk == "nf" or vk == "nr"         then v = pd.nfr or 0
        elseif vk == "mf" or vk == "mr"     then v = pd.mfr or 0
        elseif vk == "neon_regular"          then v = pd.nfr or pd.nf or 0
        elseif vk == "mega_regular"          then v = pd.mfr or pd.mf or 0
        elseif vk == "r"                     then v = pd.fr  or 0
        elseif vk == "fr"                    then v = pd.r   or 0 end
    end
    return v
end
_G._getVariantKey = getVariantKey
_G._getPetVal = getPetVal

local function fmtVal(v)
    if v == 0 then return "N/A" end
    if v >= 1e6       then return string.format("%.1fM", v/1e6)
    elseif v >= 1e3   then return string.format("%.1fK", v/1e3)
    elseif v >= 100   then return string.format("%.0f", v)
    elseif v >= 1     then return string.format("%.1f", v)
    else                   return string.format("%.3f", v) end
end
_G._fmtVal = fmtVal

local function sumOffer(items, cache)
    local total = 0
    for _, item in ipairs(items or {}) do
        if item.category == "pets" and item.kind then
            local name = ""
            pcall(function()
                name = (InventoryDB.pets[item.kind] and InventoryDB.pets[item.kind].name) or item.kind
            end)
            local pd = cache[name:lower()]
            if not pd then
                for k, v in pairs(cache) do
                    if k:find(name:lower(), 1, true) then pd = v; break end
                end
            end
            total = total + getPetVal(pd, getVariantKey(item.properties))
        end
    end
    return total
end
_G._sumOffer = sumOffer

do local valueHeaderRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 7), BackgroundTransparency=1, Parent=miscFrame})
local valueHeaderLbl = mk("TextLabel", {Size=UDim2.new(1, 0, 1, 0), BackgroundTransparency=1, Text="Trade Values (AMVGG)", Font=Enum.Font.SourceSansSemibold, TextSize=6, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=valueHeaderRow})

end local valueRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 14), BackgroundTransparency=1, Parent=miscFrame})

local yourValBox = mk("TextLabel", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0, 0, 0, 0), BackgroundColor3=Color3.fromRGB(16, 24, 50), BackgroundTransparency=0.1, Text="You: —", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(110, 190, 255), TextXAlignment=Enum.TextXAlignment.Center, Parent=valueRow})
Instance.new("UICorner", yourValBox).CornerRadius = UDim.new(0, 3)
local yourValStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(60, 100, 180), Thickness=0.7, Parent=yourValBox})

local partnerValBox = mk("TextLabel", {Size=UDim2.new(0.5, -2, 1, 0), Position=UDim2.new(0.5, 2, 0, 0), BackgroundColor3=Color3.fromRGB(16, 36, 20), BackgroundTransparency=0.1, Text="Them: —", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(90, 230, 120), TextXAlignment=Enum.TextXAlignment.Center, Parent=valueRow})
Instance.new("UICorner", partnerValBox).CornerRadius = UDim.new(0, 3)
local partnerValStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(40, 130, 60), Thickness=0.7, Parent=partnerValBox})

local valueStatusRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 0), BackgroundTransparency=1, Parent=miscFrame})
local valueStatusLbl = mk("TextLabel", {Size=UDim2.new(1, 0, 1, 0), BackgroundTransparency=1, Text="", Font=Enum.Font.SourceSans, TextSize=6, TextColor3=Color3.fromRGB(150, 150, 150), TextXAlignment=Enum.TextXAlignment.Center, Parent=valueStatusRow})

local function refreshValues()
    local myOffer, partnerOffer

    if mockState.active and mockState.trade then
        local trade = mockState.trade
        myOffer      = trade.sender_offer
        partnerOffer = trade.recipient_offer
        local recipient = trade.recipient
        if recipient and (recipient == Players.LocalPlayer or
            recipient.UserId == Players.LocalPlayer.UserId) then
            myOffer, partnerOffer = partnerOffer, myOffer
        end
    else
        local ok, state = pcall(function()
            return mockState.originalFunctions._get_local_trade_state(TradeApp)
        end)
        if ok and state then
            if state.sender == Players.LocalPlayer then
                myOffer      = state.sender_offer
                partnerOffer = state.recipient_offer
            else
                myOffer      = state.recipient_offer
                partnerOffer = state.sender_offer
            end
        end
    end

    xpcall(function() if _G._spUpdate then _G._spUpdate(myOffer, partnerOffer) end end, function(e) warn("[StarPets][hook error] "..tostring(e)) end)
    if not myOffer and not partnerOffer then
        yourValBox.Text     = "You: —"
        partnerValBox.Text  = "Them: —"
        valueStatusLbl.Text = ""
        yourValStroke.Color    = Color3.fromRGB(60, 100, 180)
        partnerValStroke.Color = Color3.fromRGB(40, 130, 60)
        return
    end

    if not _amvggCache then
        valueStatusLbl.Text = "loading values..."
    end

    fetchAmvgg(function(cache)
        if not cache then
            valueStatusLbl.Text = "⚠ failed to load"
            return
        end
        valueStatusLbl.Text = ""
        local myTotal      = sumOffer(myOffer and myOffer.items or {}, cache)
        local partnerTotal = sumOffer(partnerOffer and partnerOffer.items or {}, cache)
        _G._lastPartnerAmvgg = partnerTotal  -- cached for auto spin
        yourValBox.Text    = "You: "  .. fmtVal(myTotal)
        partnerValBox.Text = "Them: " .. fmtVal(partnerTotal)
        if myTotal > 0 and partnerTotal > 0 then
            local ratio = partnerTotal / myTotal
            if ratio >= 0.9 and ratio <= 1.1 then
                yourValStroke.Color    = Color3.fromRGB(0, 255, 100)
                partnerValStroke.Color = Color3.fromRGB(0, 255, 100)
            elseif ratio > 1.1 then
                yourValStroke.Color    = Color3.fromRGB(0, 200, 255)
                partnerValStroke.Color = Color3.fromRGB(0, 200, 255)
            else
                yourValStroke.Color    = Color3.fromRGB(255, 80, 80)
                partnerValStroke.Color = Color3.fromRGB(255, 80, 80)
            end
        else
            yourValStroke.Color    = Color3.fromRGB(60, 100, 180)
            partnerValStroke.Color = Color3.fromRGB(40, 130, 60)
        end
    end)
end

-- Hook _overwrite_local_trade_state for mock trades
do local _origOverwriteForValues = TradeApp._overwrite_local_trade_state
TradeApp._overwrite_local_trade_state = function(self, newState)
    local result = _origOverwriteForValues(self, newState)
    task.defer(refreshValues)
    return result
end

-- Also hook the REAL _overwrite_local_trade_state (original) for real trades
end local _realOrigOverwrite = mockState.originalFunctions._overwrite_local_trade_state
if _realOrigOverwrite then
    mockState.originalFunctions._overwrite_local_trade_state = function(self, newState)
        local result = _realOrigOverwrite(self, newState)
        task.defer(refreshValues)

        -- Detect real trade completion and queue auto spins
        if _G._autoSpinEnabled and newState and newState.current_stage == "completed" and not mockState.active then
            pcall(function()
                local partnerItems = newState.recipient_offer and newState.recipient_offer.items
                if not partnerItems or #partnerItems == 0 then return end
                local val = _G._lastPartnerAmvgg or 0
                -- recalc from current display value if available
                if val <= 0 then return end
                local spins = math.floor(val / 0.1 + 0.5)
                if _G._maxSpinsEnabled then
                    spins = math.min(spins, _G._maxSpinsValue)
                end
                if spins > 0 then
                    _G._autoSpinPending = (_G._autoSpinPending or 0) + spins
                    _G._autoSpinRequiredPets = #partnerItems
                    _G._autoSpinTriggered = false
                    _G._autoSpinWaitingForTrade = true
                end
            end)
        end

        return result
    end
end

task.spawn(function()
    fetchAmvgg(function() end)
end)


-- ===================== STARPETS PRICE CHECK v2 (USD, verbose logging) =====================
-- Wrapped in its own function so it uses NONE of the main chunk's 200 local slots.
-- Console: every request/response/error prints with the [StarPets] prefix.
-- Helpers:  _G._spCopyLog()  copies the whole log to clipboard   _G._spDebug("Frost Dragon")
;xpcall(function()
local SP = { host = "https://market.apineural.com", cur = "usd", ttl = 600, cache = {}, inflight = {}, token = 0, ui = {}, err = "", logs = {} }
_G._SP = SP

function SP.log(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local s = "[StarPets] " .. table.concat(t, " ")
    print(s)
    SP.logs[#SP.logs + 1] = s
    if #SP.logs > 400 then table.remove(SP.logs, 1) end
end
function SP.warn(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local s = "[StarPets][ERROR] " .. table.concat(t, " ")
    warn(s)
    SP.logs[#SP.logs + 1] = s
    SP.err = table.concat(t, " ")
end
_G._spCopyLog = function()
    local ok, e = pcall(function() setclipboard(table.concat(SP.logs, "\n")) end)
    print("[StarPets] log copied:", ok, e or "")
end

SP.hdr = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
-- the catalog's "sorting" object shape isn't visible in the bundle, so try a few; the first one accepted is remembered
SP.sorts = { '{"price":"asc"}', '{"field":"price","direction":"asc"}', '{"field":"price","order":"asc"}', '{"by":"price","order":"asc"}', '{"type":"price","order":"asc"}', '{"price":"ASC"}', '{"price":1}', '{}' }
function SP.getReq()
    local env = (type(getgenv) == "function" and getgenv()) or {}
    return (type(request) == "function" and request)
        or (type(http_request) == "function" and http_request)
        or (type(env.request) == "function" and env.request)
        or (type(env.http_request) == "function" and env.http_request)
        or (syn and type(syn.request) == "function" and syn.request)
        or (http and type(http.request) == "function" and http.request)
        or (fluxus and type(fluxus.request) == "function" and fluxus.request)
        or nil
end
SP.reqFn = SP.getReq()
SP.log("loaded. request function:", SP.reqFn and "found" or "MISSING")

function SP.http(method, path, body)
    local req = SP.reqFn or SP.getReq()
    local url = SP.host .. path
    local res
    if req then
        local ok, r = pcall(req, { Url = url, Method = method, Headers = SP.hdr, Body = body })
        if ok and type(r) == "table" then res = r
        else
            SP.warn("request threw:", r, "- retrying at identity 8")
            pcall(function() setthreadidentity(8) end)
            local ok2, r2 = pcall(req, { Url = url, Method = method, Headers = SP.hdr, Body = body })
            pcall(function() setthreadidentity(2) end)
            if ok2 and type(r2) == "table" then res = r2 else SP.warn("retry threw:", r2) end
        end
    end
    if not res then   -- last resort for executors without a working request()
        local okf, raw0 = pcall(function()
            if method == "GET" then return game:HttpGet(url) end
            return game:HttpPost(url, body or "", "application/json")
        end)
        if okf and type(raw0) == "string" then res = { StatusCode = 200, Body = raw0 }
        else SP.warn("no working HTTP method on this executor:", raw0); return nil, nil end
    end
    local code = res.StatusCode or res.status_code
    local raw = res.Body or res.body or ""
    SP.log(method, path, "->", code, "|", #raw, "bytes")
    if body then SP.log("   sent:", body:sub(1, 220)) end
    SP.log("   got :", tostring(raw):sub(1, 300))
    local okj, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okj then data = nil; SP.warn("response is not JSON (HTTP " .. tostring(code) .. ")") end
    return data, code or 0, raw
end

-- one catalog page for a pet name
function SP.search(name, page)
    local function try(sort)
        local body = '{"game":0,"name":' .. HttpService:JSONEncode(name) .. ',"price":{"currency":"usd"},"sorting":' .. sort .. ',"page":' .. page .. ',"limit":72}'
        local d, code = SP.http("POST", "/api/v4/goods", body)
        if d and type(d.data) == "table" and type(d.data.items) == "table" then return d.data end
        return nil, code
    end
    if SP.sort then return try(SP.sort) end
    for _, s in ipairs(SP.sorts) do
        local r, code = try(s)
        if r then SP.sort = s; SP.log("catalog accepted sorting =", s); return r end
        if not code then return nil end   -- no network / no response: stop guessing
    end
    SP.warn("catalog rejected ALL sorting guesses - run the probe and paste me the output")
    return nil
end

function SP.parse(it)
    local f = {}
    if type(it.features) == "table" then
        for _, ft in ipairs(it.features) do
            if type(ft) == "table" and ft.key then f[ft.key] = tostring(ft.value) end
        end
    end
    return {
        id = it.id or it.product_id,
        name = it.display_name or it.name or it.title,
        price = tonumber(it.min_price) or tonumber(it.price) or tonumber(it.avg_price),
        pump = f.pumping, fly = (f.flyable == "true"), ride = (f.rideable == "true"),
    }
end

-- all listed variants of a pet name (cached)
function SP.variants(name)
    local key = name:lower()
    local c = SP.cache[key]
    if c and os.clock() - c.t < SP.ttl then return c.list end
    while SP.inflight[key] do task.wait(0.1) end
    c = SP.cache[key]
    if c and os.clock() - c.t < SP.ttl then return c.list end
    SP.inflight[key] = true
    local list, seen = {}, {}
    local ok, err = xpcall(function()
        for page = 1, 3 do
            local d = SP.search(name, page)
            if not d then break end
            local found = false
            for _, it in ipairs(d.items) do
                local p = SP.parse(it)
                if p.name then seen[p.name] = true end
                if p.name and p.name:lower() == key then list[#list + 1] = p; found = true end
            end
            if found or not d.pages or page >= d.pages then break end
        end
        local looked = 0
        for _, p in ipairs(list) do
            if not p.pump and p.id and looked < 14 then
                looked = looked + 1
                local d = SP.http("GET", "/api/v4/goods/" .. tostring(p.id) .. "?currency=usd")
                if d and type(d.data) == "table" then
                    local q = SP.parse(d.data)
                    p.pump, p.fly, p.ride = q.pump, q.fly, q.ride
                    p.price = q.price or p.price
                end
            end
        end
    end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
    SP.inflight[key] = nil
    if not ok then SP.warn("variants(" .. name .. ") crashed:", err) end
    if #list == 0 then
        local names = {}
        for n in pairs(seen) do if #names < 8 then names[#names + 1] = n end end
        SP.warn("no exact-name match for '" .. name .. "'. names the API returned:", #names > 0 and table.concat(names, ", ") or "(none)")
    else
        SP.cache[key] = { t = os.clock(), list = list }
        SP.log("'" .. name .. "':", #list, "variants cached")
    end
    return list
end

-- cheapest listing: exact fly/ride match -> FR fallback -> any (age ignored, potions are best-effort)
function SP.price(name, props)
    local pump = (props and props.mega_neon) and "mega_neon" or ((props and props.neon) and "neon" or "default")
    local fly, ride = (props and props.flyable) and true or false, (props and props.rideable) and true or false
    local exact, fr, any
    for _, c in ipairs(SP.variants(name)) do
        if c.price and c.price > 0 and (c.pump == pump or not c.pump) then
            if c.fly == fly and c.ride == ride and (not exact or c.price < exact) then exact = c.price end
            if c.fly and c.ride and (not fr or c.price < fr) then fr = c.price end
            if not any or c.price < any then any = c.price end
        end
    end
    local p = exact or fr or any
    SP.log("price:", name, pump, fly and "F" or "-", ride and "R" or "-", "=>", p and ("$" .. p) or "NONE", exact and "(exact)" or (fr and "(FR fallback)" or (any and "(any variant)" or "")))
    return p
end

function SP.side(items)
    local total, missing = 0, 0
    for _, item in ipairs(items or {}) do
        if item.category == "pets" and item.kind then
            local name = item.kind
            pcall(function() name = (InventoryDB.pets[item.kind] and InventoryDB.pets[item.kind].name) or item.kind end)
            local p = SP.price(name, item.properties)
            if p then total = total + p else missing = missing + 1 end
        end
    end
    return total, missing
end

function SP.fmt(v, miss)
    local s = "$" .. string.format("%.2f", v)
    if miss > 0 then s = s .. "+?" end
    return s
end

-- UI: sits right under the AMVGG boxes on the Misc tab
do
    local hdrRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 7), BackgroundTransparency = 1, Parent = miscFrame })
    SP.ui.hdr = mk("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "Money Value (StarPets, USD)", Font = Enum.Font.SourceSansSemibold, TextSize = 6, TextColor3 = Color3.fromRGB(180, 180, 180), TextXAlignment = Enum.TextXAlignment.Left, Parent = hdrRow })
    local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Parent = miscFrame })
    SP.ui.you = mk("TextLabel", { Size = UDim2.new(0.5, -2, 1, 0), BackgroundColor3 = Color3.fromRGB(44, 34, 14), BackgroundTransparency = 0.1, Text = "You: —", Font = Enum.Font.FredokaOne, TextSize = 7, TextColor3 = Color3.fromRGB(255, 205, 100), Parent = row })
    Instance.new("UICorner", SP.ui.you).CornerRadius = UDim.new(0, 3)
    mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.fromRGB(170, 120, 40), Thickness = 0.7, Parent = SP.ui.you })
    SP.ui.them = mk("TextLabel", { Size = UDim2.new(0.5, -2, 1, 0), Position = UDim2.new(0.5, 2, 0, 0), BackgroundColor3 = Color3.fromRGB(44, 34, 14), BackgroundTransparency = 0.1, Text = "Them: —", Font = Enum.Font.FredokaOne, TextSize = 7, TextColor3 = Color3.fromRGB(255, 205, 100), Parent = row })
    Instance.new("UICorner", SP.ui.them).CornerRadius = UDim.new(0, 3)
    mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.fromRGB(170, 120, 40), Thickness = 0.7, Parent = SP.ui.them })
    local stRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 7), BackgroundTransparency = 1, Parent = miscFrame })
    SP.ui.status = mk("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Font = Enum.Font.SourceSans, TextSize = 6, TextColor3 = Color3.fromRGB(150, 150, 150), TextXAlignment = Enum.TextXAlignment.Center, Parent = stRow })
end

function SP.compute(job)
    local tok = job.tok
    local ok, err = xpcall(function()
        SP.err = ""
        local mt, mm = SP.side(job.my and job.my.items)
        local pt, pm = SP.side(job.partner and job.partner.items)
        if tok ~= SP.token then return end
        SP.ui.you.Text = "You: " .. SP.fmt(mt, mm)
        SP.ui.them.Text = "Them: " .. SP.fmt(pt, pm)
        _G._lastPartnerMoney = pt
        local miss = mm + pm
        if miss > 0 and SP.err ~= "" then
            SP.ui.status.Text = "⚠ " .. SP.err:sub(1, 70)
        else
            SP.ui.status.Text = (miss > 0) and (miss .. " unpriced (+?)") or ""
        end
        SP.log("totals  you:", mt, "(missing " .. mm .. ")  them:", pt, "(missing " .. pm .. ")")
    end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
    if not ok then
        SP.warn("update crashed:", err)
        if tok == SP.token then SP.ui.status.Text = "⚠ error - see console (F9)" end
    end
end

-- Called from the game's trade callbacks: only records the latest offers (no network here).
function SP.update(myOffer, partnerOffer)
    SP.token = SP.token + 1
    if not myOffer and not partnerOffer then
        SP.pending = nil
        SP.ui.you.Text, SP.ui.them.Text, SP.ui.status.Text = "You: —", "Them: —", ""
        return
    end
    SP.pending = { my = myOffer, partner = partnerOffer, tok = SP.token, t = os.clock() }
    SP.ui.status.Text = "pricing..."
end

-- Worker thread, started from the script's own thread at load (same context mock trades use).
-- All StarPets HTTP happens here, debounced, so real-trade callbacks can't break or cancel it.
_G._spGen = (_G._spGen or 0) + 1
SP.gen = _G._spGen
task.spawn(function()
    while _G._spGen == SP.gen do
        local job = SP.pending
        if job and os.clock() - job.t >= 0.3 then
            SP.pending = nil
            SP.compute(job)
        end
        task.wait(0.1)
    end
end)
_G._spUpdate = SP.update

_G._spDebug = function(name)
    local l = SP.variants(name or "Frost Dragon")
    SP.log("debug: sort=", SP.sort, "variants=", #l, "lastErr=", SP.err)
    for i, v in ipairs(l) do if i <= 12 then SP.log(v.name, v.pump, v.fly, v.ride, v.price) end end
end
SP.log("ready. Console helpers: _G._spCopyLog()  _G._spDebug('Frost Dragon')")
end, function(e) warn("[StarPets][LOAD ERROR] " .. tostring(e) .. "\n" .. debug.traceback()) end)
-- =================== end STARPETS PRICE CHECK ===================

end -- TRADE VALUE DISPLAY do block

do  -- register-relief: scope the misc-tab UI locals so they free before the toggle rows (Volt 200-local limit)
do local GUI_SCALE = 1.0
local GUI_BASE_W, GUI_BASE_H = 130, 400

local function applyGuiScale()
    -- Capture the visual center before changing scale
    local oldVW = math.floor(GUI_BASE_W * mainUIScale.Scale)
    local oldVH = math.floor(GUI_BASE_H * mainUIScale.Scale)
    local cx = mainFrame.AbsolutePosition.X + oldVW / 2
    local cy = mainFrame.AbsolutePosition.Y + oldVH / 2

    mainUIScale.Scale = GUI_SCALE
    local vw = math.floor(GUI_BASE_W * GUI_SCALE)
    local vh = math.floor(GUI_BASE_H * GUI_SCALE)
    local nx = math.floor(cx - vw / 2)
    local ny = math.floor(cy - vh / 2)

    mainFrame.Size     = UDim2.new(0, GUI_BASE_W, 0, GUI_BASE_H)
    mainFrame.Position = UDim2.new(0, nx, 0, ny)
    blackFrame.Size     = UDim2.new(0, vw + 6, 0, vh + 6)
    blackFrame.Position = UDim2.new(0, nx - 3, 0, ny - 3)
end

local guiSizeRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})

local guiSizeLabel = mk("TextLabel", {Size=UDim2.new(0.44, -2, 1, 0), BackgroundTransparency=1, Text="GUI Size: 100%", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=guiSizeRow})

local guiSizeDown = mk("TextButton", {Size=UDim2.new(0.17, -1, 1, 0), Position=UDim2.new(0.44, 1, 0, 0), BackgroundColor3=Color3.fromRGB(60, 40, 80), BackgroundTransparency=0.2, Text="−", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=Color3.fromRGB(190,34,230), Parent=guiSizeRow})
Instance.new("UICorner", guiSizeDown).CornerRadius = UDim.new(0, 3)
local guiSizeDownStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=guiSizeDown})

local guiSizeUp = mk("TextButton", {Size=UDim2.new(0.17, -1, 1, 0), Position=UDim2.new(0.62, 1, 0, 0), BackgroundColor3=Color3.fromRGB(60, 40, 80), BackgroundTransparency=0.2, Text="+", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=Color3.fromRGB(190,34,230), Parent=guiSizeRow})
Instance.new("UICorner", guiSizeUp).CornerRadius = UDim.new(0, 3)
local guiSizeUpStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=guiSizeUp})

local guiLockBtn = mk("TextButton", {Size=UDim2.new(0.19, -1, 1, 0), Position=UDim2.new(0.80, 1, 0, 0), BackgroundColor3=Color3.fromRGB(40, 40, 60), BackgroundTransparency=0.2, Text="🔓", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(180, 180, 200), Parent=guiSizeRow})
Instance.new("UICorner", guiLockBtn).CornerRadius = UDim.new(0, 3)
local guiLockStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(100, 100, 140), Thickness=0.7, Transparency=0.4, Parent=guiLockBtn})

guiLockBtn.MouseButton1Click:Connect(function()
    _G._guiLocked = not _G._guiLocked
    if _G._applyGuiLock then pcall(_G._applyGuiLock, _G._guiLocked) end
    if _G._guiLocked then
        guiLockBtn.Text             = "🔒"; guiLockBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 40)
        guiLockBtn.TextColor3       = Color3.fromRGB(80, 255, 130)
        guiLockStroke.Color         = Color3.fromRGB(0, 200, 80)
        guiLockStroke.Transparency  = 0.2
    else
        guiLockBtn.Text             = "🔓"; guiLockBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        guiLockBtn.TextColor3       = Color3.fromRGB(180, 180, 200)
        guiLockStroke.Color         = Color3.fromRGB(100, 100, 140)
        guiLockStroke.Transparency  = 0.4
    end
end)

_G._setGuiLockVisual = function(locked)
    if locked then
        guiLockBtn.Text             = "🔒"; guiLockBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 40)
        guiLockBtn.TextColor3       = Color3.fromRGB(80, 255, 130)
        guiLockStroke.Color         = Color3.fromRGB(0, 200, 80)
        guiLockStroke.Transparency  = 0.2
    else
        guiLockBtn.Text             = "🔓"; guiLockBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        guiLockBtn.TextColor3       = Color3.fromRGB(180, 180, 200)
        guiLockStroke.Color         = Color3.fromRGB(100, 100, 140)
        guiLockStroke.Transparency  = 0.4
    end
end

guiSizeDown.MouseButton1Click:Connect(function()
    GUI_SCALE = math.max(0.5, math.round((GUI_SCALE - 0.1) * 10) / 10)
    guiSizeLabel.Text = string.format("GUI Size: %d%%", math.floor(GUI_SCALE * 100))
    applyGuiScale()
end)
guiSizeUp.MouseButton1Click:Connect(function()
    GUI_SCALE = math.min(3.0, math.round((GUI_SCALE + 0.1) * 10) / 10)
    guiSizeLabel.Text = string.format("GUI Size: %d%%", math.floor(GUI_SCALE * 100))
    applyGuiScale()
end)

end do local keybindsEnabled = true

local keybindsToggleRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})

local keybindsLabel = mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), Position=UDim2.new(0, 0, 0, 0), BackgroundTransparency=1, Text="Keybinds", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=keybindsToggleRow})

local keybindsToggle = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundColor3=Color3.fromRGB(30, 80, 50), BackgroundTransparency=0.2, Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80, 255, 130), Parent=keybindsToggleRow})
Instance.new("UICorner", keybindsToggle).CornerRadius = UDim.new(0, 3)
local keybindsToggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=0.7, Transparency=0.3, Parent=keybindsToggle})

keybindsToggle.MouseButton1Click:Connect(function()
    keybindsEnabled = not keybindsEnabled
    if keybindsEnabled then
        keybindsToggle.Text       = "ON"
        keybindsToggle.TextColor3 = Color3.fromRGB(80, 255, 130)
        TweenService:Create(keybindsToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(30, 80, 50) }):Play()
        TweenService:Create(keybindsToggleStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(0, 255, 100) }):Play()
    else
        keybindsToggle.Text       = "OFF"
        keybindsToggle.TextColor3 = Color3.fromRGB(255, 90, 90)
        TweenService:Create(keybindsToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(80, 30, 30) }):Play()
        TweenService:Create(keybindsToggleStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 60, 60) }):Play()
    end
end)

local function createKeybindRow(labelText, defaultKey, parent)
    local row = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=parent})

    local lbl = mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), Position=UDim2.new(0, 0, 0, 0), BackgroundTransparency=1, Text=labelText, Font=Enum.Font.SourceSans, TextSize=6, TextColor3=Color3.fromRGB(200, 200, 200), TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Parent=row})

    local keyBtn = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundColor3=Color3.fromRGB(40, 40, 55), BackgroundTransparency=0.2, Text=defaultKey, Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(190,34,230), Parent=row})
    Instance.new("UICorner", keyBtn).CornerRadius = UDim.new(0, 3)
    local keyStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=keyBtn})

    local binding = false
    keyBtn.MouseButton1Click:Connect(function()
        if binding then return end
        binding = true
        keyBtn.Text       = "..."
        keyBtn.TextColor3 = Color3.fromRGB(255, 200, 50)
        TweenService:Create(keyStroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(255, 200, 50), Transparency = 0 }):Play()
        local conn
        conn = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            local keyName = input.KeyCode.Name
            if keyName == "Unknown" then return end
            keyBtn.Text       = keyName
            keyBtn.TextColor3 = Color3.fromRGB(190,34,230)
            TweenService:Create(keyStroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(190,34,230), Transparency = 0.4 }):Play()
            conn:Disconnect()
            binding = false
        end)
    end)
    return keyBtn
end

local receivePetsRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})
local receivePetsLabel = mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), BackgroundTransparency=1, Text="Receive Pets", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=receivePetsRow})
local receivePetsToggle = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundColor3=Color3.fromRGB(30, 80, 50), BackgroundTransparency=0.2, Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80, 255, 130), Parent=receivePetsRow})
Instance.new("UICorner", receivePetsToggle).CornerRadius = UDim.new(0, 3)
local receivePetsStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=0.7, Transparency=0.3, Parent=receivePetsToggle})
receivePetsToggle.MouseButton1Click:Connect(function()
    CONFIG.RECEIVE_PETS = not CONFIG.RECEIVE_PETS
    if CONFIG.RECEIVE_PETS then
        receivePetsToggle.Text       = "ON"
        receivePetsToggle.TextColor3 = Color3.fromRGB(80, 255, 130)
        TweenService:Create(receivePetsToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(30, 80, 50) }):Play()
        TweenService:Create(receivePetsStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(0, 255, 100) }):Play()
    else
        receivePetsToggle.Text       = "OFF"
        receivePetsToggle.TextColor3 = Color3.fromRGB(255, 90, 90)
        TweenService:Create(receivePetsToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(80, 30, 30) }):Play()
        TweenService:Create(receivePetsStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 60, 60) }):Play()
    end
end)

local removeSentRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})
local removeSentLabel = mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), BackgroundTransparency=1, Text="Remove Sent Pets", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=removeSentRow})
local removeSentToggle = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundColor3=Color3.fromRGB(30, 80, 50), BackgroundTransparency=0.2, Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80, 255, 130), Parent=removeSentRow})
Instance.new("UICorner", removeSentToggle).CornerRadius = UDim.new(0, 3)
local removeSentStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=0.7, Transparency=0.3, Parent=removeSentToggle})
removeSentToggle.MouseButton1Click:Connect(function()
    CONFIG.REMOVE_SENT_PETS = not CONFIG.REMOVE_SENT_PETS
    if CONFIG.REMOVE_SENT_PETS then
        removeSentToggle.Text       = "ON"
        removeSentToggle.TextColor3 = Color3.fromRGB(80, 255, 130)
        TweenService:Create(removeSentToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(30, 80, 50) }):Play()
        TweenService:Create(removeSentStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(0, 255, 100) }):Play()
    else
        removeSentToggle.Text       = "OFF"
        removeSentToggle.TextColor3 = Color3.fromRGB(255, 90, 90)
        TweenService:Create(removeSentToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(80, 30, 30) }):Play()
        TweenService:Create(removeSentStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 60, 60) }):Play()
    end
end)

-- Remove Real Pets toggle row (own function scope = no extra main-chunk locals)
;(function()
    local row = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})
    mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), BackgroundTransparency=1, Text="Remove Real Pets", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=row})
    local btn = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundTransparency=0.2, Font=Enum.Font.FredokaOne, TextSize=7, Text="", Parent=row})
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
    local stroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Thickness=0.7, Transparency=0.3, Parent=btn})
    local function style()
        local on = (CONFIG.REMOVE_REAL_PETS ~= false)
        btn.Text = on and "ON" or "OFF"
        btn.TextColor3 = on and Color3.fromRGB(80, 255, 130) or Color3.fromRGB(255, 90, 90)
        btn.BackgroundColor3 = on and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(80, 30, 30)
        stroke.Color = on and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 60, 60)
    end
    style()
    btn.MouseButton1Click:Connect(function()
        CONFIG.REMOVE_REAL_PETS = not (CONFIG.REMOVE_REAL_PETS ~= false)
        style()
    end)
end)()

local verifiedFriendRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})
local verifiedFriendLabel = mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), BackgroundTransparency=1, Text="Verified Friend", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=verifiedFriendRow})
local verifiedFriendToggle = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundColor3=Color3.fromRGB(30, 80, 50), BackgroundTransparency=0.2, Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80, 255, 130), Parent=verifiedFriendRow})
Instance.new("UICorner", verifiedFriendToggle).CornerRadius = UDim.new(0, 3)
local verifiedFriendStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=0.7, Transparency=0.3, Parent=verifiedFriendToggle})
verifiedFriendToggle.MouseButton1Click:Connect(function()
    CONFIG_VERIFIED_FRIEND = not CONFIG_VERIFIED_FRIEND
    if CONFIG_VERIFIED_FRIEND then
        verifiedFriendToggle.Text       = "ON"
        verifiedFriendToggle.TextColor3 = Color3.fromRGB(80, 255, 130)
        TweenService:Create(verifiedFriendToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(30, 80, 50) }):Play()
        TweenService:Create(verifiedFriendStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(0, 255, 100) }):Play()
    else
        verifiedFriendToggle.Text       = "OFF"
        verifiedFriendToggle.TextColor3 = Color3.fromRGB(255, 90, 90)
        TweenService:Create(verifiedFriendToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(80, 30, 30) }):Play()
        TweenService:Create(verifiedFriendStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 60, 60) }):Play()
    end
end)

-- PUT YOUR CHAT LIST HERE ↓
local ChatList = {
    "what can you upgrade this to",
    "can I actually upgrade",
    "tysm",
    "omg ty",
    "ty for being trusted",
    "thanks",
    "does this meet the requirements?",
    "could I have a free pet",
    "bro please",
    "NO WAY",
    "I love you",
    "bruh pls bigger upgrade",
    "thx",
    "trusted",
    "vouch",
    "TRUSTED OMG",
    "how did you get so rich?",
    "can I upgrade again",
    "choose a pet from my inv",
    "can you upgrade me to my dp",
    "does this meet the requirements?",
    "can you upgrade my pet",
    "make sure to follow them guys they are trusted",
    "can I upgrade my pet",
    "im followed",
    "ofc",
    "BRO ACCEPT",
    "omg yesss",
    "im a real fan i trust u",
    "can i do mega bat dragonnn",
    "does this meet the requirements?",
    "can you upgrade my pet",
    "make sure to follow them guys they are trusted",
    "can I upgrade for mega battt",
    "YESSSS",
    "yh",
    "yeah i am",
    "i am",
    "nty",
    "nvm",
    "i wanna upgrade",
    "i want to upgrade",
    "what gift can u do",
    "what gift could u do",
    "can u add a small gift?",
    "could u add?",
    "would u be able to add",
    "can we do this",
    "are u sure",
    "wait fr?",
    "OMG YES",
    "YESS PLEASE",
    "ill do it",
    "nty sorry",
    "can i see ur inventory",
    "what are u lf",
    "what are u looking for",
    "i can add",
    "im trying to get my dp",
}
_G._ChatList = ChatList

do   -- (own scope: keeps the main chunk under Lua's local-variable limit)
-- ===== context based chat =====
-- A) I added pets and have NO trade history with this partner  -> thanks / follow lines
local ChatListGift = {
    "omg tysm!!", "im followed!", "my dp is mega bat", "everyone follow for free pets!",
    "omg ty so much", "tysm!!! following now", "wait ur actually giving free pets??", "followed!!",
    "my dp is mega frost dragon", "omg a free pet", "everyone go follow them for free pets", "ty omg im following",
    "wait this is real??", "i just followed!!", "my dp is mega owl", "OMG TYSM", "following rn thank you!!",
    "free pets for followers?? followed", "everyone follow them omg", "tysm ur so nice",
}
-- B) the mock partner added a pet to the trade -> upgrade requests
local ChatListUpgrade = {
    "can i upgrade this?", "can i skip the line and upgrade", "can i actually upgrade", "can i upgrade for mega bat",
    "can u upgrade this pet", "what can you upgrade this to", "can i upgrade to my dp", "does this meet the requirements?",
    "can i upgrade for mega frost dragon pls", "is this enough to upgrade", "can i upgrade again", "pls upgrade me",
    "can i skip the line pls", "can i upgrade for mega owl", "can you upgrade my pet", "can i upgrade my pet",
    "can I upgrade for mega battt", "can i do mega bat dragonnn",
    "i wanna upgrade", "i want to upgrade", "what can u upgrade this to",
    "can u do a bigger upgrade", "can u add a little", "what gift can u do",
    "what gift could u add", "could u add a small gift", "can i upgrade again after this",
    "YESSSS", "yh can i", "yeah i am", "nty sorry", "wait i can upgrade?",
    "can u upgrade me to my dp", "im trying to get my dp", "can u pick from my inv",
    "is this enough for an upgrade", "what would u offer for this",
}
-- C) last history item with this partner was THEM giving me a pet, and I returned it with an extra gift
local ChatListTrusted = {
    "tysm omg", "trusted!!!", "omg ur trusted", "YOOOOOOO OMG TYSM", "TRUSTED OMG", "omg thank you so much!!",
    "ur actually trusted wtf", "vouch!!", "NO WAY u gave extra", "tysm for the extra!!", "omg ty ur the best",
    "ily ur trusted", "W trade omg", "trusted trusted trusted", "ty for being trusted", "OMG TYSM UR SO TRUSTED",
    "make sure to follow them guys they are trusted", "im a real fan i trust u",
}
_G._ChatListGift, _G._ChatListUpgrade, _G._ChatListTrusted = ChatListGift, ChatListUpgrade, ChatListTrusted

-- most recent history record (mock or real) with the current partner
local _chatHistCache, _chatHistAt = nil, 0
local function _lastPartnerRecord()
    local pid, lp = CONFIG.PARTNER_USER_ID, Players.LocalPlayer
    if tick() - _chatHistAt > 15 or not _chatHistCache then
        local recs = {}
        for _, r in ipairs(_mockTradeHistory) do recs[#recs + 1] = r end
        pcall(function()
            if TradeHistoryApp then
                local list = TradeHistoryApp:_get_trade_history(true)
                for _, r in ipairs(list or {}) do recs[#recs + 1] = r end
            end
        end)
        _chatHistCache, _chatHistAt = recs, tick()
    end
    local best
    for _, r in ipairs(_chatHistCache) do
        if r.sender_user_id == pid or r.recipient_user_id == pid then
            if not best or (r.timestamp or 0) > (best.timestamp or 0) then best = r end
        end
    end
    if not best then return nil end
    local mine, theirs
    if best.sender_user_id == lp.UserId then mine, theirs = best.sender_items, best.recipient_items
    else mine, theirs = best.recipient_items, best.sender_items end
    return best, mine or {}, theirs or {}
end

local _recentChats = {}
local function _pickFrom(list)
    local pick
    for _ = 1, 8 do
        pick = list[math.random(1, #list)]
        local seen = false
        for _, m in ipairs(_recentChats) do if m == pick then seen = true; break end end
        if not seen then break end
    end
    table.insert(_recentChats, pick)
    if #_recentChats > 6 then table.remove(_recentChats, 1) end
    return pick
end

local function _pickChatMessage()
    local myOffer, theirOffer
    pcall(function()
        myOffer = TradeApp:_get_my_offer()
        theirOffer = TradeApp:_get_partner_offer()
    end)
    local myCount    = myOffer and #(myOffer.items or {}) or 0
    local theirCount = theirOffer and #(theirOffer.items or {}) or 0
    -- no chatting until at least one pet is in the trade (either side)
    if myCount == 0 and theirCount == 0 then return nil end
    local rec, recMine, recTheirs = _lastPartnerRecord()

    -- C) they gave me a pet last time, I'm sending pets back with something extra
    if rec and #recTheirs > 0 and #recMine == 0 and myCount > #recTheirs then
        return _pickFrom(ChatListTrusted)
    end
    -- B) the partner has added a pet -> asking for an upgrade
    if theirCount > 0 then
        return _pickFrom(ChatListUpgrade)
    end
    -- A) I added pets and there is no history with this partner
    if myCount > 0 and not rec then
        return _pickFrom(ChatListGift)
    end
    return _pickFrom(ChatList)
end
_G._pickChatMessage = _pickChatMessage
end
-- PUT YOUR CHAT LIST HERE ↑

local _autoChatEnabled  = false
local _autoChatLimit    = 1   -- messages per trade (default 1)
local _autoChatSent     = 0
local _autoChatLoopId   = 0

-- true once at least one pet is in the trade (either side)
local function _tradeHasPets()
    local mine, theirs
    pcall(function()
        mine, theirs = TradeApp:_get_my_offer(), TradeApp:_get_partner_offer()
    end)
    return (mine and #(mine.items or {}) or 0) + (theirs and #(theirs.items or {}) or 0) > 0
end

local function _sendAutoChat()
    if not mockState.active or not mockState.trade then return false end
    if _autoChatLimit > 0 and _autoChatSent >= _autoChatLimit then return false end
    local function _acWarn(m) _G._acWarned = _G._acWarned or {}; if not _G._acWarned[m] then _G._acWarned[m] = true; warn("[AutoChat] " .. m) end end
    if #ChatList == 0 then _acWarn("ChatList is empty"); return false end
    if not (TradeApp and TradeApp._render_message_in_trade_chat) then _acWarn("TradeApp._render_message_in_trade_chat missing"); return false end
    if not TradeApp.chat_scrolling_frame or not TradeApp.chat_message_template then _acWarn("trade chat frame/template not ready yet (will keep retrying)"); return false end
    if not _tradeHasPets() then return false end   -- no chatting until a pet is in the trade
    local msg = _G._pickChatMessage()
    if not msg then return end   -- nothing in the trade yet: stay quiet

    task.spawn(function()
        -- Typing indicator using the same pattern as _initialize_typing_indicator (source line 2443)
        local typingLabel = nil
        safeCall(function()
            local scrollFrame = TradeApp.chat_scrolling_frame
            local template = TradeApp.chat_message_template
            if not scrollFrame or not template then return end

            local atBottom = math.abs(
                scrollFrame.CanvasSize.Y.Offset
                - scrollFrame.AbsoluteSize.Y
                - scrollFrame.CanvasPosition.Y) < 40

            local clone = template:Clone()
            clone.Name = "TypingMessage"; clone.RichText = true
            clone.Text = string.format("<i><b>%s</b> is typing</i>", CONFIG.PARTNER_NAME:lower()); clone.TextColor3 = Color3.fromRGB(150, 150, 150)
            clone.TextSize = 22; clone.TextTransparency = 0
            clone.LayoutOrder = 1; clone.Parent = scrollFrame.Content

            local h = clone.TextBounds.Y
            clone.Size = UDim2.new(1, 0, 0, h)
            scrollFrame.CanvasSize = scrollFrame.CanvasSize + UDim2.new(0, 0, 0, h)
            if atBottom then
                scrollFrame.CanvasPosition = Vector2.new(0,
                    scrollFrame.CanvasSize.Y.Offset - scrollFrame.AbsoluteSize.Y)
            end
            typingLabel = clone
        end)

        -- Animate dots for ~1.8s
        local elapsed, dotTimer, dots = 0, 0, 0
        while elapsed < 0.9 and typingLabel and typingLabel.Parent do
            local dt = task.wait(0.05)
            elapsed = elapsed + dt
            dotTimer = dotTimer + dt
            if dotTimer >= 0.25 then
                dotTimer = dotTimer - 0.25
                dots = (dots % 3) + 1
                safeCall(function()
                    typingLabel.Text = string.format(
                        "<i><b>%s</b> is typing%s</i>",
                        CONFIG.PARTNER_NAME:lower(), string.rep(".", dots))
                end)
            end
        end

        safeCall(function()
            if typingLabel and typingLabel.Parent then
                local h = typingLabel.Size.Y.Offset
                TradeApp.chat_scrolling_frame.CanvasSize =
                    TradeApp.chat_scrolling_frame.CanvasSize - UDim2.new(0, 0, 0, h)
                typingLabel:Destroy()
            end
        end)

        if not mockState.active then return end

        -- Pass mockPartner as player so the function renders their name,
        -- and raw msg as the message string — same as _listen_to_global_chat does
        safeCall(function()
            TradeApp:_render_message_in_trade_chat(mockPartner, msg, true)
        end)
        _autoChatSent = _autoChatSent + 1
    end)
    return true
end

local function _startAutoChatLoop()
    _autoChatLoopId = _autoChatLoopId + 1
    local myId = _autoChatLoopId
    _autoChatSent = 0
    task.spawn(function()
        -- waits for a pet to appear in the trade, then chats ONCE for this trade
        while myId == _autoChatLoopId and _autoChatEnabled and mockState.active do
            task.wait(0.4)
            if myId ~= _autoChatLoopId or not _autoChatEnabled or not mockState.active then break end
            if _tradeHasPets() then
                task.wait(math.random(3, 10) / 10)   -- react a moment after the pet lands
                if myId ~= _autoChatLoopId or not _autoChatEnabled or not mockState.active then break end
                if _autoChatLimit > 0 and _autoChatSent >= _autoChatLimit then break end
                if _sendAutoChat() then task.wait(math.random(7, 15)) end   -- gap before the next message (if the limit allows one)
            end
        end
    end)
end

local function _stopAutoChatLoop()
    _autoChatLoopId = _autoChatLoopId + 1
end
_G._autoChatStart = _startAutoChatLoop
_G._autoChatStop  = _stopAutoChatLoop
_G._autoChatOn    = function() return _autoChatEnabled end

-- Hide Pet Discovery toggle row (own function scope = no extra main-chunk locals)
;(function()
    local on = (CONFIG.SUPPRESS_PET_DISCOVERY ~= false)
    local row = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})
    mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), BackgroundTransparency=1, Text="Hide Pet Discovery", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=row})
    local btn = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundTransparency=0.2, Font=Enum.Font.FredokaOne, TextSize=7, Text="", Parent=row})
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
    local stroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Thickness=0.7, Transparency=0.3, Parent=btn})
    local function style()
        btn.Text = on and "ON" or "OFF"
        btn.TextColor3 = on and Color3.fromRGB(80, 255, 130) or Color3.fromRGB(255, 90, 90)
        btn.BackgroundColor3 = on and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(80, 30, 30)
        stroke.Color = on and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 60, 60)
    end
    style()
    btn.MouseButton1Click:Connect(function()
        on = not on
        CONFIG.SUPPRESS_PET_DISCOVERY = on
        if _G._setPetDiscoverySuppress then pcall(_G._setPetDiscoverySuppress, on) end
        style()
    end)
end)()

-- Auto Chat toggle row
local autoChatRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})
local autoChatLabel = mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), BackgroundTransparency=1, Text="Auto Chat", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=autoChatRow})
local autoChatToggle = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundColor3=Color3.fromRGB(80, 30, 30), BackgroundTransparency=0.2, Text="OFF", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 90, 90), Parent=autoChatRow})
Instance.new("UICorner", autoChatToggle).CornerRadius = UDim.new(0, 3)
local autoChatStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 60, 60), Thickness=0.7, Transparency=0.3, Parent=autoChatToggle})
autoChatToggle.MouseButton1Click:Connect(function()
    _autoChatEnabled = not _autoChatEnabled
    if _autoChatEnabled then
        autoChatToggle.Text       = "ON"
        autoChatToggle.TextColor3 = Color3.fromRGB(80, 255, 130)
        TweenService:Create(autoChatToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(30, 80, 50) }):Play()
        TweenService:Create(autoChatStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(0, 255, 100) }):Play()
        if mockState.active then _startAutoChatLoop() end
    else
        autoChatToggle.Text       = "OFF"
        autoChatToggle.TextColor3 = Color3.fromRGB(255, 90, 90)
        TweenService:Create(autoChatToggle, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(80, 30, 30) }):Play()
        TweenService:Create(autoChatStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(255, 60, 60) }):Play()
        _stopAutoChatLoop()
    end
end)

local chatLimitRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})
local chatLimitLabel = mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), BackgroundTransparency=1, Text="Chat Limit (0=∞)", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=chatLimitRow})
local chatLimitBox = mk("TextBox", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundColor3=Color3.fromRGB(40, 40, 55), BackgroundTransparency=0.2, Text="1", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(190,34,230), PlaceholderText="0", Parent=chatLimitRow})
Instance.new("UICorner", chatLimitBox).CornerRadius = UDim.new(0, 3)
local chatLimitStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=chatLimitBox})
chatLimitBox.FocusLost:Connect(function()
    local v = tonumber(chatLimitBox.Text)
    if v and v >= 0 then
        _autoChatLimit = math.floor(v)
        chatLimitBox.Text = tostring(_autoChatLimit)
    else
        chatLimitBox.Text = tostring(_autoChatLimit)
    end
end)

local testChatBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 11), BackgroundColor3=Color3.fromRGB(40, 60, 100), BackgroundTransparency=0.2, Text="Send Random Message", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(120, 180, 255), Parent=miscFrame})
Instance.new("UICorner", testChatBtn).CornerRadius = UDim.new(0, 3)
local testChatStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(80, 140, 255), Thickness=0.7, Transparency=0.4, Parent=testChatBtn})
testChatBtn.MouseButton1Click:Connect(function()
    if not mockState.active or not mockState.trade then
        warn("[MockTrade] AutoChat test: no active trade")
        return
    end
    if #ChatList == 0 then
        warn("[MockTrade] AutoChat test: ChatList is empty")
        return
    end
    local msg = _G._pickChatMessage()
    warn("[MockTrade] AutoChat test: sending '" .. msg .. "'")
    safeCall(function()
        TradeApp:_render_message_in_trade_chat(mockPartner, msg, true)
    end)
    TweenService:Create(testChatStroke, TweenInfo.new(0.1), { Color = Color3.fromRGB(0, 255, 120) }):Play()
    task.delay(0.4, function()
        TweenService:Create(testChatStroke, TweenInfo.new(0.3), { Color = Color3.fromRGB(80, 140, 255) }):Play()
    end)
end)

local keybindListBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 11), BackgroundColor3=Color3.fromRGB(40, 40, 55), BackgroundTransparency=0.1, Text="⌨️ Keybinds", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 220), Parent=miscFrame})
Instance.new("UICorner", keybindListBtn).CornerRadius = UDim.new(0, 3)
local keybindListStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.8, Transparency=0.3, Parent=keybindListBtn})

-- Keybind popup panel — exact same style as misc tab rows, display-only
local keybindPanel = mk("Frame", {Size=UDim2.fromOffset(110, 10), AutomaticSize=Enum.AutomaticSize.Y, BackgroundColor3=Color3.fromRGB(30, 30, 40), BorderSizePixel=0, Visible=false, ZIndex=100, Parent=controlGui})
Instance.new("UICorner", keybindPanel).CornerRadius = UDim.new(0, 7)
local kpStroke = mk("UIStroke", {Color=Color3.fromRGB(190,34,230), Thickness=1.5, Parent=keybindPanel})
local kpPad = mk("UIPadding", {PaddingTop=UDim.new(0,4), PaddingBottom=UDim.new(0,4), PaddingLeft=UDim.new(0,4), PaddingRight=UDim.new(0,4), Parent=keybindPanel})
local kpLayout = mk("UIListLayout", {Padding=UDim.new(0, 2), SortOrder=Enum.SortOrder.LayoutOrder, Parent=keybindPanel})

local function addKeybindEntry(label, defaultKey, order)
    local row = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, LayoutOrder=order, ZIndex=101, Parent=keybindPanel})

    local lbl = mk("TextLabel", {Size=UDim2.new(0.6, -2, 1, 0), Position=UDim2.new(0, 0, 0, 0), BackgroundTransparency=1, Text=label, Font=Enum.Font.SourceSans, TextSize=6, TextColor3=Color3.fromRGB(200, 200, 200), TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ZIndex=102, Parent=row})

    local keyBtn = mk("TextButton", {Size=UDim2.new(0.315, 0, 1, 0), Position=UDim2.new(0.685, 0, 0, 0), BackgroundColor3=Color3.fromRGB(40, 40, 55), BackgroundTransparency=0.2, BorderSizePixel=0, Text=defaultKey, Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(190,34,230), ZIndex=102, Parent=row})
    Instance.new("UICorner", keyBtn).CornerRadius = UDim.new(0, 3)
    local keyStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=keyBtn})

    local binding = false
    keyBtn.MouseButton1Click:Connect(function()
        if binding then return end
        binding = true
        keyBtn.Text = "..."
        keyBtn.TextColor3 = Color3.fromRGB(255, 200, 50)
        TweenService:Create(keyStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(255,200,50), Transparency=0}):Play()
        local conn
        conn = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            local keyName = input.KeyCode.Name
            if keyName == "Unknown" then return end
            keyBtn.Text = keyName
            keyBtn.TextColor3 = Color3.fromRGB(190,34,230)
            TweenService:Create(keyStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(190,34,230), Transparency=0.4}):Play()
            conn:Disconnect()
            binding = false
        end)
    end)
    return keyBtn
end

local addRandomKeyBtn       = addKeybindEntry("Add Random High Tier",  "P", 1)
local startTradeKeyBtn      = addKeybindEntry("Start Trade",           "T", 2)
local partnerAcceptKeyBtn   = addKeybindEntry("Partner Accept",        "Y", 3)
local partnerUnacceptKeyBtn = addKeybindEntry("Partner Unaccept",      "U", 4)
local randomPlayerKeyBtn    = addKeybindEntry("Select Random Player",  "R", 5)
local randomPresetKeyBtn    = addKeybindEntry("Random Preset User",    "H", 6)
local selectPartnerKeyBtn   = addKeybindEntry("Select Trade Partner",  "MB4", 7)
addKeybindEntry("Block Partner",        "J", 8)  -- J block uses hardcoded KeyCode.J

local function updateKeybindPanelPos()
    local mf = _G._tradeGuiMainFrame
    if mf then
        local p = mf.AbsolutePosition
        local s = mf.AbsoluteSize
        keybindPanel.Position = UDim2.fromOffset(p.X + s.X + 6, p.Y)
    end
end

keybindListBtn.MouseButton1Click:Connect(function()
    keybindPanel.Visible = not keybindPanel.Visible
    if keybindPanel.Visible then updateKeybindPanelPos() end
end)

game:GetService("UserInputService").InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 and keybindPanel.Visible then
        local mp = i.Position; local ap = keybindPanel.AbsolutePosition; local as = keybindPanel.AbsoluteSize
        if not(mp.X>=ap.X and mp.X<=ap.X+as.X and mp.Y>=ap.Y and mp.Y<=ap.Y+as.Y) then
            keybindPanel.Visible = false
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not keybindsEnabled then return end
    local key = input.KeyCode.Name
    if key == addRandomKeyBtn.Text then
        task.spawn(addRandomHighTier)
    elseif key == partnerAcceptKeyBtn.Text then
        mockPartnerAccept()
    elseif key == partnerUnacceptKeyBtn.Text then
        mockPartnerUnaccept()
    elseif key == startTradeKeyBtn.Text then
        local currentName = partnerBox.Text
        if currentName and currentName ~= "" then
            updatePartnerFromUsername(currentName)
        end
        initializeMockTrade()
    elseif key == randomPlayerKeyBtn.Text then
        local playersList = Players:GetPlayers()
        local others = {}
        for _, p in ipairs(playersList) do
            if p ~= Players.LocalPlayer then table.insert(others, p) end
        end
        if #others > 0 then
            local picked = others[math.random(1, #others)]
            if _G._selectUser then _G._selectUser(picked.Name, picked.UserId) end
        end
    elseif key == randomPresetKeyBtn.Text then
        if _G._selectRandomPresetUser then _G._selectRandomPresetUser() end
    end
end)

-- Select trade partner via front mouse button (MouseButton4)
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not keybindsEnabled then return end
    if input.UserInputType.Name ~= "MouseButton4" then return end
    local state = TradeApp:_get_local_trade_state()
    if not state then return end
    local me = Players.LocalPlayer
    local partner = (state.sender == me or state.sender.UserId == me.UserId)
        and state.recipient or state.sender
    if partner then
        selectUser(partner.Name, partner.UserId)
    end
end)

-- Single row: [🍎 Add Random Food (50%)] [◀ (12.5%)] [count (25%)] [▶ (12.5%)]
end do local _foodCount = 1

local foodRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, Parent=miscFrame})

local addFoodBtn = mk("TextButton", {Size=UDim2.new(0.5,-3,1,0), Position=UDim2.new(0,0,0,0), BackgroundColor3=Color3.fromRGB(40,100,60), BackgroundTransparency=0.05, Text="Add Random Food", Font=Enum.Font.FredokaOne, TextSize=6, TextColor3=Color3.fromRGB(160,255,160), BorderSizePixel=0, Parent=foodRow})
Instance.new("UICorner", addFoodBtn).CornerRadius = UDim.new(0,4)
local addFoodStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(80,200,80), Thickness=1.2, Transparency=0.2, Parent=addFoodBtn})

-- Counter: single pill frame with ◀ number ▶ inside
local foodCounterFrame = mk("Frame", {Size=UDim2.new(0.5,-3,1,0), Position=UDim2.new(0.5,3,0,0), BackgroundColor3=Color3.fromRGB(60,30,90), BackgroundTransparency=0.05, BorderSizePixel=0, Parent=foodRow})
Instance.new("UICorner", foodCounterFrame).CornerRadius = UDim.new(0,4)
local foodCounterStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=1.2, Transparency=0.2, Parent=foodCounterFrame})

local foodPrevBtn = mk("TextButton", {Size=UDim2.new(0,16,1,0), Position=UDim2.new(0,0,0,0), BackgroundTransparency=1, Text="◀", Font=Enum.Font.GothamBold, TextSize=7, TextColor3=Color3.fromRGB(210,140,255), BorderSizePixel=0, Parent=foodCounterFrame})

local foodCountBox = mk("TextBox", {Size=UDim2.new(1,-32,1,0), Position=UDim2.new(0,16,0,0), BackgroundTransparency=1, Text="1", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(210,140,255), TextXAlignment=Enum.TextXAlignment.Center, ClearTextOnFocus=false, BorderSizePixel=0, Parent=foodCounterFrame})

local foodNextBtn = mk("TextButton", {Size=UDim2.new(0,16,1,0), Position=UDim2.new(1,-16,0,0), BackgroundTransparency=1, Text="▶", Font=Enum.Font.GothamBold, TextSize=7, TextColor3=Color3.fromRGB(210,140,255), BorderSizePixel=0, Parent=foodCounterFrame})

local function setFoodCount(n)
    _foodCount = math.max(1, math.min(18, n))
    foodCountBox.Text = tostring(_foodCount)
end
foodPrevBtn.MouseButton1Click:Connect(function() setFoodCount(_foodCount - 1) end)
foodNextBtn.MouseButton1Click:Connect(function() setFoodCount(_foodCount + 1) end)
foodCountBox.FocusLost:Connect(function()
    local n = tonumber(foodCountBox.Text)
    if n then setFoodCount(n) else foodCountBox.Text = tostring(_foodCount) end
end)

local _foodBusy = false
local function addRandomFoodToOffer()
    if _foodBusy then return end
    if not mockState.active or not mockState.trade then
        addFoodBtn.Text = "No active trade!"
        task.delay(1.5, function() addFoodBtn.Text = "Add Random Food" end)
        return
    end
    if mockState.trade.current_stage == "confirmation" then return end
    _foodBusy = true

    -- Build list of all food items from InventoryDB
    local foodList = {}
    pcall(function()
        local foodDB = InventoryDB and InventoryDB.food
        if foodDB then
            for id, data in pairs(foodDB) do
                -- Skip untradeable items
                if data.name and not data.not_tradeable and not data.untradeable and not data.not_tradable then
                    table.insert(foodList, {id=id, name=data.name})
                end
            end
        end
    end)
    if #foodList == 0 then
        addFoodBtn.Text = "No food found!"
        task.delay(1.5, function() addFoodBtn.Text = "Add Random Food" end)
        _foodBusy = false; return
    end

    local target   = _foodCount
    local added    = 0
    local partnerId = tostring(mockState.trade.recipient.UserId)

    task.spawn(function()
        for i = 1, target do
            if not mockState.active or not mockState.trade then break end
            if #mockState.trade.recipient_offer.items >= 18 then break end

            -- Show busy indicator
            mockState.trade.busy_indicators = mockState.trade.busy_indicators or {}
            mockState.trade.busy_indicators[partnerId] = { picking = true }
            pcall(function() TradeApp:_update_busy_indicators(mockState.trade) end)

            addFoodBtn.Text = "Adding "..i.."/"..target.."..."

            task.wait(1)

            if not mockState.active or not mockState.trade then break end

            local pick = foodList[math.random(1, #foodList)]
            local uuid = HttpService:GenerateGUID()
            local foodItem = {
                category   = "food",
                kind       = pick.id,
                unique     = uuid,
                properties = { age = 0 },
            }

            mockState.trade.busy_indicators[partnerId] = nil
            pcall(function() TradeApp:_update_busy_indicators(mockState.trade) end)
            table.insert(mockState.trade.recipient_offer.items, foodItem)
            if not TradeApp.can_suggest_removal_items then TradeApp.can_suggest_removal_items = {} end
            TradeApp.can_suggest_removal_items[uuid] = foodItem
            mockState.trade.sender_offer.negotiated    = false
            mockState.trade.recipient_offer.negotiated = false
            mockState.trade.offer_version = mockState.trade.offer_version + 1
            TradeApp:_overwrite_local_trade_state(mockState.trade)
            pcall(function() TradeApp:_lock_trade_for_appropriate_time() end)
            pcall(function() TradeApp:_render_message_in_trade_chat(nil, CONFIG.PARTNER_NAME.." added "..pick.name..".", true) end)
            mockState.scamWarningShown = false
            added = added + 1
        end

        addFoodBtn.Text = added > 0 and ("Added "..added.."!") or "Add Random Food"
        task.delay(1.5, function() addFoodBtn.Text = "Add Random Food" end)
        _foodBusy = false
    end)
end

addFoodBtn.MouseButton1Click:Connect(addRandomFoodToOffer)

-- Preload pet icons button
end do local preloadBtn = Instance.new("TextButton")
-- Row containing Preload + Setup Live side by side
local preloadSetupRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, Parent=miscFrame})

preloadBtn.Size = UDim2.new(0.5,-3,1,0); preloadBtn.Position = UDim2.new(0,0,0,0)
preloadBtn.BackgroundColor3 = Color3.fromRGB(30,60,90)
preloadBtn.BackgroundTransparency = 0.05; preloadBtn.Text = "Preload Pet Icons"
preloadBtn.Font = Enum.Font.FredokaOne; preloadBtn.TextSize = 7
preloadBtn.TextColor3 = Color3.fromRGB(120,200,255); preloadBtn.Parent = preloadSetupRow
Instance.new("UICorner", preloadBtn).CornerRadius = UDim.new(0,4)
local preloadStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(60,140,220), Thickness=1.2, Transparency=0.2, Parent=preloadBtn})

local _preloadBusy = false
preloadBtn.MouseButton1Click:Connect(function()
    if _preloadBusy then return end
    _preloadBusy = true

    task.spawn(function()
        local ContentProvider = game:GetService("ContentProvider")

        -- Collect all pet image IDs from InventoryDB
        local images = {}
        local seen = {}
        pcall(function()
            for id, data in pairs(InventoryDB.pets or {}) do
                local img = data.image or data.thumbnail
                if img and img ~= "" and img ~= "rbxassetid://0" and not seen[img] then
                    seen[img] = true
                    -- Create a temp ImageLabel to preload via PreloadAsync
                    local lbl = mk("ImageLabel", {Image=img})
                    table.insert(images, lbl)
                end
            end
        end)

        local total = #images
        if total == 0 then
            preloadBtn.Text = "No images found!"
            task.delay(2, function()
                preloadBtn.Text = "Preload Pet Icons"
                _preloadBusy = false
            end)
            return
        end

        preloadBtn.Text = "Preloading 0/"..total.."..."

        -- Preload in batches of 20
        local done = 0
        local BATCH = 20
        for i = 1, #images, BATCH do
            local batch = {}
            for j = i, math.min(i + BATCH - 1, #images) do
                table.insert(batch, images[j])
            end
            pcall(function()
                ContentProvider:PreloadAsync(batch)
            end)
            done = done + #batch
            preloadBtn.Text = "Preloading "..done.."/"..total.."..."
            task.wait()
        end

        -- Clean up temp labels
        for _, lbl in ipairs(images) do lbl:Destroy() end

        preloadBtn.Text = "✓ Done! ("..total.." icons)"
        preloadBtn.TextColor3 = Color3.fromRGB(100,255,150)
        task.delay(3, function()
            preloadBtn.Text = "Preload Pet Icons"
            preloadBtn.TextColor3 = Color3.fromRGB(120,200,255)
            _preloadBusy = false
        end)
    end)
end)

local setupLiveBtn = mk("TextButton", {Size=UDim2.new(0.5,-3,1,0), Position=UDim2.new(0.5,3,0,0), BackgroundColor3=Color3.fromRGB(220, 140, 20), BackgroundTransparency=0.05, Text="⚡ Setup Live", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 240, 180), Parent=preloadSetupRow})
Instance.new("UICorner", setupLiveBtn).CornerRadius = UDim.new(0, 4)
local setupLiveStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 200, 60), Thickness=1.2, Transparency=0.2, Parent=setupLiveBtn})

local setupLiveStatusLbl = mk("TextLabel", {Size=UDim2.new(1, 0, 0, 0), BackgroundTransparency=1, Text="", Font=Enum.Font.SourceSans, TextSize=6, TextColor3=Color3.fromRGB(180, 220, 180), TextXAlignment=Enum.TextXAlignment.Center, Parent=miscFrame})

-- Tiered list toggle row
local tieredRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, Parent=miscFrame})
local tieredLbl = mk("TextLabel", {Size=UDim2.new(0.65,0,1,0), BackgroundTransparency=1, Text="Tiered High Tier List", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180,180,180), TextXAlignment=Enum.TextXAlignment.Left, Parent=tieredRow})
local tieredToggleBtn = mk("TextButton", {Size=UDim2.new(0.33,0,1,0), Position=UDim2.new(0.67,0,0,0), BackgroundColor3=Color3.fromRGB(30,80,50), Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80,255,130), BorderSizePixel=0, Parent=tieredRow})
Instance.new("UICorner", tieredToggleBtn).CornerRadius = UDim.new(0,3)
local tieredToggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0,255,100), Thickness=0.7, Transparency=0.3, Parent=tieredToggleBtn})
_G._tieredToggleBtn = tieredToggleBtn; _G._tieredToggleStroke = tieredToggleStroke
tieredToggleBtn.MouseButton1Click:Connect(function()
    _useTieredList = not _useTieredList
    tieredToggleBtn.Text             = _useTieredList and "ON"  or "OFF"
    tieredToggleBtn.BackgroundColor3 = _useTieredList and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
    tieredToggleBtn.TextColor3       = _useTieredList and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
    tieredToggleStroke.Color         = _useTieredList and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)
end)

setupLiveBtn.MouseButton1Click:Connect(function()
    setupLiveBtn.Text = "Setting up..."
    setupLiveBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)

    task.spawn(function()
        local function setStatus(txt)
            setupLiveStatusLbl.Text = txt
        end

        setStatus("Setting delays...")
        CONFIG.AUTO_ACCEPT_DELAY  = 0.5
        CONFIG.AUTO_CONFIRM_DELAY = 0.5
        if _G._acceptBox   then _G._acceptBox.Text   = "0.5" end
        if _G._confirmBox  then _G._confirmBox.Text  = "0.5" end

        CONFIG.SPECTATOR_COUNT = 5
        if _G._spectatorBox then _G._spectatorBox.Text = "5" end

        task.wait(0.2)

        setStatus("Spawning all variants...")
        if _G._setupLiveRunSpawnAllVariants then
            _G._setupLiveRunSpawnAllVariants()
            local t0 = tick()
            local allVBtn = _G._setupLiveSpawnAllVariantsBtn
            if allVBtn then
                repeat task.wait(0.5) until allVBtn.Text == "Spawn All Variants" or tick()-t0 > 60
            end
        end

        task.wait(0.5)

        setStatus("Spawning fake inventory...")
        if _G._setupLiveRunFakeInv then
            _G._setupLiveRunFakeInv()
            local t0 = tick()
            local fInvBtn = _G._setupLiveFakeInvBtn
            if fInvBtn then
                repeat task.wait(0.5) until (fInvBtn.Text == "Spawn Fake Inventory" or fInvBtn.Text:find("Spawned")) or tick()-t0 > 30
            end
        end

        task.wait(0.5)

        setStatus("Spawning fake trade history...")
        if _G._setupLiveRunFakeHistory then
            _G._setupLiveRunFakeHistory()
            local t0 = tick()
            local fHistBtn = _G._setupLiveFakeHistoryBtn
            if fHistBtn then
                repeat task.wait(0.5) until fHistBtn.Text == "Spawn Fake Trade History" or tick()-t0 > 60
            end
        end

        task.wait(0.5)

        if _G._fakeProfileOn then   -- optional (Misc tab: "Fake Profile (Setup)")
        setStatus("Spawning fake profile...")
        pcall(function()
            for i, name in ipairs(HIGH_TIER_PETS) do
                if name:lower():find("bat") and name:lower():find("dragon") then
                    if _G._fpSetPet then _G._fpSetPet(i, name) end
                    break
                end
            end
            if _G._fpSetProps then
                _G._fpSetProps({ mega_neon=true, neon=false, flyable=true, rideable=true })
            end
        end)
        if _G._setupLiveRunFakeProfile then
            _G._setupLiveRunFakeProfile()
            local t0 = tick()
            local fProfBtn = _G._setupLiveFakeProfileBtn
            if fProfBtn then
                repeat task.wait(0.5) until fProfBtn.Text == "Spawn Fake Profile" or tick()-t0 > 60
            end
        end

        end -- optional fake profile

        setStatus("Enabling tabs...")
        if not _useTieredList then
            _useTieredList = true
            pcall(function()
                _G._tieredToggleBtn.Text = "ON"
                _G._tieredToggleBtn.BackgroundColor3 = Color3.fromRGB(30,80,50)
                _G._tieredToggleBtn.TextColor3 = Color3.fromRGB(80,255,130)
                _G._tieredToggleStroke.Color = Color3.fromRGB(0,255,100)
            end)
        end
        if not _chatTabEnabled then
            _chatTabEnabled = true
            _setChatTabVisible(true)
            pcall(function()
                _G._chatToggleBtn.Text = "ON"
                _G._chatToggleBtn.BackgroundColor3 = Color3.fromRGB(30,80,50)
                _G._chatToggleBtn.TextColor3 = Color3.fromRGB(80,255,130)
                _G._chatToggleStroke.Color = Color3.fromRGB(0,255,100)
            end)
        end
        setStatus("✅ Live setup complete!")
        setupLiveBtn.Text = "⚡ Setup Live"
        setupLiveBtn.BackgroundColor3 = Color3.fromRGB(220, 140, 20)
        task.delay(3, function() setupLiveStatusLbl.Text = "" end)
    end)
end)

end local _spawnToggleEnabled = true   -- auto-open on startup
local spawnToggleRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 11), BackgroundTransparency=1, Parent=miscFrame})

do local spawnToggleLbl = mk("TextLabel", {Size=UDim2.new(0.65, 0, 1, 0), BackgroundTransparency=1, Text="Show Spawn Tab", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180, 180, 180), TextXAlignment=Enum.TextXAlignment.Left, Parent=spawnToggleRow})

end local spawnToggleBtn = mk("TextButton", {Size=UDim2.new(0.33, 0, 1, 0), Position=UDim2.new(0.67, 0, 0, 0), BackgroundColor3=Color3.fromRGB(30,80,50), Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80,255,130), Parent=spawnToggleRow})
Instance.new("UICorner", spawnToggleBtn).CornerRadius = UDim.new(0, 3)
local spawnToggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0,255,100), Thickness=0.7, Transparency=0.3, Parent=spawnToggleBtn})
_G._spawnToggleBtn = spawnToggleBtn; _G._spawnToggleStroke = spawnToggleStroke

spawnToggleBtn.MouseButton1Click:Connect(function()
    _spawnToggleEnabled = not _spawnToggleEnabled
    _setSpawnTabVisible(_spawnToggleEnabled)
    spawnToggleBtn.Text             = _spawnToggleEnabled and "ON"  or "OFF"
    spawnToggleBtn.BackgroundColor3 = _spawnToggleEnabled and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
    spawnToggleBtn.TextColor3       = _spawnToggleEnabled and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
    spawnToggleStroke.Color         = _spawnToggleEnabled and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)
end)
end  -- register-relief: end misc-tab UI scope

-- Misc-tab toggles: "Show Trade Request" + "Fake Profile (Setup)"
do
    local function addMiscToggle(labelText, startOn, onChange)
        local row = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, Parent=miscFrame})
        mk("TextLabel", {Size=UDim2.new(0.65,0,1,0), BackgroundTransparency=1, Text=labelText, Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180,180,180), TextXAlignment=Enum.TextXAlignment.Left, Parent=row})
        local btn = mk("TextButton", {Size=UDim2.new(0.33,0,1,0), Position=UDim2.new(0.67,0,0,0), BackgroundColor3=Color3.fromRGB(30,80,50), Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80,255,130), Parent=row})
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,3)
        local stroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0,255,100), Thickness=0.7, Transparency=0.3, Parent=btn})
        local on = startOn
        local function paint()
            btn.Text             = on and "ON"  or "OFF"
            btn.BackgroundColor3 = on and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
            btn.TextColor3       = on and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
            stroke.Color         = on and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)
        end
        paint()
        btn.MouseButton1Click:Connect(function()
            on = not on
            paint()
            onChange(on)
        end)
    end

    -- ON = the "sent you a trade request" Accept/Decline dialog shows before a mock trade starts; OFF = trade opens instantly
    _G._showTradeRequest = true
    addMiscToggle("Show Trade Request", true, function(v) _G._showTradeRequest = v end)

    -- OFF (default) = Setup Live does NOT fill your own profile's Have sections with a fake profile
    _G._fakeProfileOn = false
    addMiscToggle("Fake Profile (Setup)", false, function(v) _G._fakeProfileOn = v end)

    -- Block method (every Block Player button uses it):
    --   ON  (default) = direct block, no popup at all (falls back to the hidden-popup method only if the direct call can't be verified)
    --   OFF           = the old block animation: the popup is opened VISIBLE at the side of the screen and auto-clicked (rebuilt for the new CoreGui layout)
    _G._silentBlockDirect = true
    addMiscToggle("Direct Block", true, function(v) _G._silentBlockDirect = v end)
end

local richToggleRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, Parent=miscFrame})
local richToggleLbl = mk("TextLabel", {Size=UDim2.new(0.65,0,1,0), BackgroundTransparency=1, Text="Show Rich Tab", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180,180,180), TextXAlignment=Enum.TextXAlignment.Left, Parent=richToggleRow})
local richToggleBtn = mk("TextButton", {Size=UDim2.new(0.33,0,1,0), Position=UDim2.new(0.67,0,0,0), BackgroundColor3=Color3.fromRGB(30,80,50), Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80,255,130), Parent=richToggleRow})
Instance.new("UICorner", richToggleBtn).CornerRadius = UDim.new(0,3)
local richToggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0,255,100), Thickness=0.7, Transparency=0.3, Parent=richToggleBtn})
_G._richToggleBtn = richToggleBtn; _G._richToggleStroke = richToggleStroke
richToggleBtn.MouseButton1Click:Connect(function()
    _richTabEnabled = not _richTabEnabled
    _setRichTabVisible(_richTabEnabled)
    richToggleBtn.Text             = _richTabEnabled and "ON"  or "OFF"
    richToggleBtn.BackgroundColor3 = _richTabEnabled and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
    richToggleBtn.TextColor3       = _richTabEnabled and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
    richToggleStroke.Color         = _richTabEnabled and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)
    if _richTabEnabled then setActiveTab("Rich") end
end)

local chatToggleRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, Parent=miscFrame})
local chatToggleLbl = mk("TextLabel", {Size=UDim2.new(0.65,0,1,0), BackgroundTransparency=1, Text="Show Chat Tab", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180,180,180), TextXAlignment=Enum.TextXAlignment.Left, Parent=chatToggleRow})
local chatToggleBtn = mk("TextButton", {Size=UDim2.new(0.33,0,1,0), Position=UDim2.new(0.67,0,0,0), BackgroundColor3=Color3.fromRGB(30,80,50), Text="ON", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(80,255,130), Parent=chatToggleRow})
Instance.new("UICorner", chatToggleBtn).CornerRadius = UDim.new(0,3)
local chatToggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0,255,100), Thickness=0.7, Transparency=0.3, Parent=chatToggleBtn})
_G._chatToggleBtn = chatToggleBtn; _G._chatToggleStroke = chatToggleStroke
chatToggleBtn.MouseButton1Click:Connect(function()
    _chatTabEnabled = not _chatTabEnabled
    _setChatTabVisible(_chatTabEnabled)
    chatToggleBtn.Text             = _chatTabEnabled and "ON"  or "OFF"
    chatToggleBtn.BackgroundColor3 = _chatTabEnabled and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
    chatToggleBtn.TextColor3       = _chatTabEnabled and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
    chatToggleStroke.Color         = _chatTabEnabled and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)
end)

do  -- ===== Misc page system: Page 1 (settings) / Page 2 (Self-Badge) =====
local miscTab = tabFrames["Misc"]

-- Page 2 overlay — starts BELOW the tab buttons (y=30) so the tabs stay visible & clickable
local page2 = mk("Frame", {Name="MiscPage2", Size=UDim2.new(1,0,1,-30), Position=UDim2.new(0,0,0,30), BackgroundColor3=Color3.fromRGB(30,30,40), BorderSizePixel=0, ZIndex=6, Visible=false, Parent=mainFrame})
-- Invisible catcher: a Frame doesn't block input, so this button swallows clicks meant for page-1 buttons underneath
mk("TextButton", {Size=UDim2.new(1,12,1,10), Position=UDim2.new(0,-6,0,-5), BackgroundTransparency=1, Text="", AutoButtonColor=false, ZIndex=6, Parent=page2})
mk("UIPadding", {PaddingTop=UDim.new(0,5), PaddingLeft=UDim.new(0,6), PaddingRight=UDim.new(0,6), Parent=page2})

mk("TextLabel", {Size=UDim2.new(1,0,0,11), Position=UDim2.new(0,0,0,1), BackgroundTransparency=1, Text="Self Badge", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=Color3.fromRGB(190,34,230), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=7, Parent=page2})

local BADGES = {"founder","developer","staff","influencer"}
local LABELS  = {founder="Founder", developer="Developer", staff="Staff", influencer="Influencer"}
local function isBadge(b) for _,x in ipairs(BADGES) do if x==b then return true end end return false end
local selectedBadge = isBadge(CONFIG.SELF_BADGE_TAG) and CONFIG.SELF_BADGE_TAG or "founder"
local badgeEnabled  = (CONFIG.SELF_BADGE_TAG or "") ~= ""
local function applyBadge() CONFIG.SELF_BADGE_TAG = badgeEnabled and selectedBadge or "" end

-- Single row: [ON/OFF toggle]  [badge dropdown]  side by side
local row = mk("Frame", {Size=UDim2.new(1,0,0,15), Position=UDim2.new(0,0,0,15), BackgroundTransparency=1, ZIndex=7, Parent=page2})

local toggleBtn = mk("TextButton", {Size=UDim2.new(0.42,-2,1,0), BackgroundColor3=Color3.fromRGB(80,30,30), Text="OFF", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(255,90,90), ZIndex=7, Parent=row})
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,3)
local toggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255,60,60), Thickness=0.7, Transparency=0.3, Parent=toggleBtn})

local ddBtn = mk("TextButton", {Size=UDim2.new(0.58,-2,1,0), Position=UDim2.new(0.42,2,0,0), BackgroundColor3=Color3.fromRGB(40,40,52), Text=LABELS[selectedBadge].."  ▾", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(225,225,235), ZIndex=7, Parent=row})
Instance.new("UICorner", ddBtn).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=ddBtn})

-- Dropdown list (expands under the dropdown button)
local ddList = mk("Frame", {Size=UDim2.new(0.58,-2,0,0), AutomaticSize=Enum.AutomaticSize.Y, Position=UDim2.new(0.42,2,0,17), BackgroundColor3=Color3.fromRGB(40,40,52), BorderSizePixel=0, ZIndex=9, Visible=false, Parent=row})
Instance.new("UICorner", ddList).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=ddList})
mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Parent=ddList})

local function refreshUI()
    toggleBtn.Text = badgeEnabled and "ON" or "OFF"
    toggleBtn.BackgroundColor3 = badgeEnabled and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
    toggleBtn.TextColor3 = badgeEnabled and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
    toggleStroke.Color = badgeEnabled and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)
    ddBtn.Text = LABELS[selectedBadge].."  ▾"
end
for i,b in ipairs(BADGES) do
    local opt = mk("TextButton", {Size=UDim2.new(1,0,0,14), BackgroundColor3=Color3.fromRGB(40,40,52), Text=LABELS[b], Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(215,215,225), LayoutOrder=i, ZIndex=10, Parent=ddList})
    opt.MouseButton1Click:Connect(function() selectedBadge=b; applyBadge(); ddList.Visible=false; refreshUI() end)
end
ddBtn.MouseButton1Click:Connect(function() ddList.Visible = not ddList.Visible end)
toggleBtn.MouseButton1Click:Connect(function() badgeEnabled = not badgeEnabled; applyBadge(); refreshUI() end)

-- Hide Expired Popups + Show Spin Tab (moved here from old positions)
_G._hideExpiredDialogs = true
do
    local function mkQuickToggle(parent, yPos, label, getState, setState)
        local row = mk("Frame", {Size=UDim2.new(1,0,0,15), Position=UDim2.new(0,0,0,yPos), BackgroundTransparency=1, ZIndex=7, Parent=parent})
        mk("TextLabel", {Size=UDim2.new(0.62,0,1,0), BackgroundTransparency=1, Text=label, Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(225,225,235), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=7, Parent=row})
        local btn = mk("TextButton", {Size=UDim2.new(0.36,0,1,0), Position=UDim2.new(0.64,0,0,0), BackgroundColor3=Color3.fromRGB(30,80,50), Text="ON", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(80,255,130), ZIndex=7, Parent=row})
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,3)
        local stroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0,255,100), Thickness=0.7, Transparency=0.3, Parent=btn})
        local function refresh()
            local on = getState()
            btn.Text = on and "ON" or "OFF"
            btn.BackgroundColor3 = on and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
            btn.TextColor3 = on and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
            stroke.Color = on and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)
        end
        btn.MouseButton1Click:Connect(function() setState(not getState()); refresh() end)
        refresh()
    end
    mkQuickToggle(page2, 34, "Hide Expired Popups",
        function() return _G._hideExpiredDialogs end,
        function(v) _G._hideExpiredDialogs = v end)
    mkQuickToggle(page2, 52, "Show Spin Tab",
        function() return _G._spinTabOn end,
        function(v)
            _G._setSpinTabVisible(v)
            if v then setActiveTab("Spin") end
        end)
end

-- Auto Offer Pets controls (engine + builder defined near the top of the script) — at bottom of page 2
if _G._aoBuildControls then _G._aoBuildControls(page2) end

-- ── Admin Spam section on Misc Page 2 ────────────────────────────────
-- Layout note: page2 uses absolute pixel positions (no UIListLayout).
-- Existing content ends at approx y=100 (AO Min/Max row at y=86, h=14).
-- We start at y=108. Inner width = page2 width minus UIPadding (6px each side) ≈ 106px.
-- All ZIndex >= 8 so we stay above the invisible click-catcher at ZIndex=6.
do
local ZS = 8  -- base ZIndex: above the transparent click-catcher (ZIndex=6)
local PURPLE_S   = Color3.fromRGB(190,34,230)
local ROW_BG_S   = Color3.fromRGB(40,40,52)
local DIM_TXT_S  = Color3.fromRGB(180,180,180)
local NEUT_TXT_S = Color3.fromRGB(225,225,235)
local WHITE_S    = Color3.fromRGB(255,255,255)
local GRN_BG_S   = Color3.fromRGB(30,80,50)
local RED_BG_S   = Color3.fromRGB(80,30,30)
local GRN_TXT_S  = Color3.fromRGB(80,255,130)
local RED_TXT_S  = Color3.fromRGB(255,90,90)
local GRN_STR_S  = Color3.fromRGB(0,255,100)
local RED_STR_S  = Color3.fromRGB(255,60,60)

local HIGH_TIER_PETS_S = {
    "Bat Dragon","Shadow Dragon","Giraffe","Frost Dragon","Owl","Parrot",
    "Balloon Unicorn","Crow","African Wild Dog","Giant Panda","Haetae","Cryptid",
    "Evil Unicorn","Blazing Lion","Hedgehog","Orchid Butterfly","Diamond Butterfly",
    "Dalmatian","Arctic Reindeer","Mini Pig","Jekyll Hydra","Hot Doggo","Mermicorn",
    "Cow","Strawberry Shortcake Bat Dragon","Goose","Chocolate Chip Bat Dragon",
    "Cabbit","Turtle","Peppermint Penguin","Monkey King","Undead Jousting Horse",
    "Flamingo","Kangaroo","Strawberry Tortle",
}
local SPAM_PRESETS_S = {
    "An Adopt Me admin gave you: ",
    "Adopt Me! has partnered with StarPets and given you: ",
    "Message from Jesseraen: \"Here are some pets to give to your loyal followers!\": ",
    "JesseRaen and NewFissy have given you a PERMANENT: ",
    "You've received a special gift from the Adopt Me team: ",
}
local PRESET_LABELS_S = { "Admin", "StarPets", "Jesseraen", "NewFissy", "Gift" }

local spamActive_S    = false
local spamThread_S    = nil
local bundleMode_S    = "random"
local spamLockedPet_S = nil
local currentDialogMsg_S = SPAM_PRESETS_S[1]
local DialogApp_S = UIManager.apps.DialogApp

local function doSpamDialog_S()
    while spamActive_S do
        pcall(function()
            pcall(setthreadidentity, 2)
            local petName = spamLockedPet_S or HIGH_TIER_PETS_S[math.random(1,#HIGH_TIER_PETS_S)]
            local petId, kd
            for id, item in pairs(InventoryDB.pets or {}) do
                if item.name and item.name:lower() == petName:lower() then
                    petId = id; kd = load("KindDB")[id]; break
                end
            end
            if not petId or not kd then return end
            local fly, ride, neon, mega
            if     bundleMode_S=="fr"  then fly=true; ride=true; neon=false; mega=false
            elseif bundleMode_S=="nfr" then fly=true; ride=true; neon=true;  mega=false
            elseif bundleMode_S=="mfr" then fly=true; ride=true; neon=false; mega=true
            else local r=math.random(1,3); fly=true; ride=true; neon=(r==2); mega=(r==3) end
            DialogApp_S:dialog({
                dialog_type="ItemPreviewDialog",
                text=currentDialogMsg_S..petName,
                item={
                    id=petId, name=petName, category="pets", kind=kd.kind or petId,
                    properties={
                        pet_trick_level=math.random(1,5),
                        neon=neon, mega_neon=mega, flyable=fly, rideable=ride,
                        age=math.random(1,900000), ailments_completed=0, rp_name=""
                    }
                },
                button="Okay!", yields=true
            })
            pcall(setthreadidentity, 8)
        end)
        RunService.Heartbeat:Wait()
    end
end

-- y=144  "Admin Spam" section header
local SY = 144
mk("TextLabel", {Size=UDim2.new(1,0,0,9), Position=UDim2.new(0,0,0,SY), BackgroundTransparency=1, Text="Admin Spam", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=PURPLE_S, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=ZS, Parent=page2})

-- y=119  Spam toggle [OFF] + Preset dropdown [Admin ▾] side by side
local spamRow_S = mk("Frame", {Size=UDim2.new(1,0,0,15), Position=UDim2.new(0,0,0,SY+11), BackgroundTransparency=1, ClipsDescendants=false, ZIndex=ZS, Parent=page2})

local spamTogBtn_S = mk("TextButton", {Size=UDim2.new(0.42,-2,1,0), BackgroundColor3=RED_BG_S, BackgroundTransparency=0.2, Text="OFF", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=RED_TXT_S, ZIndex=ZS, Parent=spamRow_S})
Instance.new("UICorner", spamTogBtn_S).CornerRadius = UDim.new(0,3)
local spamTogStroke_S = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=RED_STR_S, Thickness=0.7, Transparency=0.3, Parent=spamTogBtn_S})

local spamDdBtn_S = mk("TextButton", {Size=UDim2.new(0.58,-2,1,0), Position=UDim2.new(0.42,2,0,0), BackgroundColor3=ROW_BG_S, BackgroundTransparency=0.2, Text=PRESET_LABELS_S[1].."  ▾", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=NEUT_TXT_S, ZIndex=ZS, Parent=spamRow_S})
Instance.new("UICorner", spamDdBtn_S).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=PURPLE_S, Thickness=0.7, Transparency=0.4, Parent=spamDdBtn_S})

-- Preset dropdown list (opens downward, parented to spamRow_S, ZIndex above catcher)
local spamDdList_S = mk("Frame", {Size=UDim2.new(0.58,-2,0,0), AutomaticSize=Enum.AutomaticSize.Y, Position=UDim2.new(0.42,2,0,17), BackgroundColor3=ROW_BG_S, BorderSizePixel=0, ZIndex=ZS+2, Visible=false, ClipsDescendants=false, Parent=spamRow_S})
Instance.new("UICorner", spamDdList_S).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=PURPLE_S, Thickness=0.7, Transparency=0.4, Parent=spamDdList_S})
mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Parent=spamDdList_S})
for i, label in ipairs(PRESET_LABELS_S) do
    local capMsg = SPAM_PRESETS_S[i]; local capLabel = label
    local opt = mk("TextButton", {Size=UDim2.new(1,0,0,14), BackgroundColor3=ROW_BG_S, Text=label, Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(215,215,225), LayoutOrder=i, ZIndex=ZS+3, Parent=spamDdList_S})
    opt.MouseButton1Click:Connect(function()
        currentDialogMsg_S = capMsg; spamDdBtn_S.Text = capLabel.."  ▾"; spamDdList_S.Visible = false
    end)
end
spamDdBtn_S.MouseButton1Click:Connect(function() spamDdList_S.Visible = not spamDdList_S.Visible end)
spamTogBtn_S.MouseButton1Click:Connect(function()
    spamActive_S = not spamActive_S
    if spamActive_S then
        spamTogBtn_S.Text="ON"; spamTogBtn_S.TextColor3=GRN_TXT_S
        TweenService:Create(spamTogBtn_S, TweenInfo.new(0.2), {BackgroundColor3=GRN_BG_S}):Play()
        TweenService:Create(spamTogStroke_S, TweenInfo.new(0.2), {Color=GRN_STR_S}):Play()
        spamThread_S = task.spawn(doSpamDialog_S)
    else
        spamTogBtn_S.Text="OFF"; spamTogBtn_S.TextColor3=RED_TXT_S
        TweenService:Create(spamTogBtn_S, TweenInfo.new(0.2), {BackgroundColor3=RED_BG_S}):Play()
        TweenService:Create(spamTogStroke_S, TweenInfo.new(0.2), {Color=RED_STR_S}):Play()
        if spamThread_S then task.cancel(spamThread_S); spamThread_S=nil end
    end
    spamDdList_S.Visible = false
end)

-- y=138  "Bundle Mode" label
mk("TextLabel", {Size=UDim2.new(1,0,0,9), Position=UDim2.new(0,0,0,SY+30), BackgroundTransparency=1, Text="Bundle Mode", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=PURPLE_S, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=ZS, Parent=page2})

-- y=149  FR / NFR / MFR / Random buttons
do local BUNDLE_DEFS_S = {
    {key="fr",label="FR",color=Color3.fromRGB(30,130,220)},
    {key="nfr",label="NFR",color=Color3.fromRGB(30,180,90)},
    {key="mfr",label="MFR",color=PURPLE_S},
    {key="random",label="Rnd",color=NEUT_TXT_S},
}
local bundleRefs_S = {}
local BW_S=26; local BGAP_S=2
local bundleRow_S = mk("Frame", {Size=UDim2.new(1,0,0,13), Position=UDim2.new(0,0,0,SY+41), BackgroundTransparency=1, ZIndex=ZS, Parent=page2})
local function setBundleMode_S(key)
    bundleMode_S=key
    for _,ref in ipairs(bundleRefs_S) do
        local on=ref.key==key
        TweenService:Create(ref.btn, TweenInfo.new(0.12), {BackgroundColor3=on and Color3.fromRGB(55,20,80) or ROW_BG_S}):Play()
        TweenService:Create(ref.s,   TweenInfo.new(0.12), {Color=on and ref.color or Color3.fromRGB(80,80,100), Transparency=on and 0.3 or 0.6}):Play()
        ref.btn.TextColor3 = on and WHITE_S or DIM_TXT_S
    end
end
for i,def in ipairs(BUNDLE_DEFS_S) do
    local px=(i-1)*(BW_S+BGAP_S)
    local btn=mk("TextButton", {Size=UDim2.new(0,BW_S,0,13), Position=UDim2.new(0,px,0,0), BackgroundColor3=def.key=="random" and Color3.fromRGB(55,20,80) or ROW_BG_S, BackgroundTransparency=0.2, Text=def.label, Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=def.key=="random" and WHITE_S or DIM_TXT_S, BorderSizePixel=0, ZIndex=ZS, Parent=bundleRow_S})
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,3)
    local s=mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=def.key=="random" and def.color or Color3.fromRGB(80,80,100), Thickness=0.7, Transparency=def.key=="random" and 0.3 or 0.6, Parent=btn})
    local capDef=def
    btn.MouseButton1Click:Connect(function() setBundleMode_S(capDef.key) end)
    table.insert(bundleRefs_S,{key=def.key,btn=btn,s=s,color=def.color})
end

-- y=166  "Pet Selector" label
mk("TextLabel", {Size=UDim2.new(1,0,0,9), Position=UDim2.new(0,0,0,SY+58), BackgroundTransparency=1, Text="Pet Selector", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=PURPLE_S, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=ZS, Parent=page2})

-- y=177  Pet dropdown button
end local petRow_S = mk("Frame", {Size=UDim2.new(1,0,0,15), Position=UDim2.new(0,0,0,SY+69), BackgroundTransparency=1, ClipsDescendants=false, ZIndex=ZS, Parent=page2})
local petDdBtn_S = mk("TextButton", {Size=UDim2.new(1,0,1,0), BackgroundColor3=ROW_BG_S, BackgroundTransparency=0.2, Text="Random  ▾", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=NEUT_TXT_S, ZIndex=ZS, Parent=petRow_S})
Instance.new("UICorner", petDdBtn_S).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=PURPLE_S, Thickness=0.7, Transparency=0.4, Parent=petDdBtn_S})

-- Pet scrolling list (opens downward from petRow_S, max height 90px)
local petList_S = mk("ScrollingFrame", {Size=UDim2.new(1,0,0,90), Position=UDim2.new(0,0,0,17), BackgroundColor3=ROW_BG_S, BorderSizePixel=0, ScrollBarThickness=2, ScrollBarImageColor3=PURPLE_S, CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y, ZIndex=ZS+2, Visible=false, ClipsDescendants=true, Parent=petRow_S})
Instance.new("UICorner", petList_S).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=PURPLE_S, Thickness=0.7, Transparency=0.4, Parent=petList_S})
mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Parent=petList_S})
mk("UIPadding", {PaddingTop=UDim.new(0,2), PaddingBottom=UDim.new(0,2), Parent=petList_S})

local randOpt_S = mk("TextButton", {Size=UDim2.new(1,0,0,14), BackgroundColor3=Color3.fromRGB(55,20,80), Text="🎲 Random", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=NEUT_TXT_S, LayoutOrder=0, ZIndex=ZS+3, Parent=petList_S})
randOpt_S.MouseButton1Click:Connect(function() spamLockedPet_S=nil; petDdBtn_S.Text="Random  ▾"; petList_S.Visible=false end)
for i,petName in ipairs(HIGH_TIER_PETS_S) do
    local capName=petName
    local opt=mk("TextButton", {Size=UDim2.new(1,0,0,14), BackgroundColor3=ROW_BG_S, Text=petName, Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(215,215,225), LayoutOrder=i, ZIndex=ZS+3, Parent=petList_S})
    opt.MouseButton1Click:Connect(function() spamLockedPet_S=capName; petDdBtn_S.Text=capName.."  ▾"; petList_S.Visible=false end)
end
petDdBtn_S.MouseButton1Click:Connect(function() petList_S.Visible=not petList_S.Visible; spamDdList_S.Visible=false end)
spamDdBtn_S.MouseButton1Click:Connect(function() petList_S.Visible=false end)

end
-- ── End Admin Spam section ────────────────────────────────────────────
-- page2 content now ends at approx y = 108+69+15 = 192. mainFrame height bumped below.

-- HUD: an on-screen overlay (its own ScreenGui, so it stays visible even if the control menu is hidden) showing
-- your Roblox avatar + username. OFF by default. Misc Page 2 has the ON/OFF toggle and an "Edit" button that opens
-- an editor (background, opacity, size, corners, outline, avatar, text colour / size / font ...). Drag the HUD or the
-- editor anywhere. Also available as _G._setHud(true/false) and _G._hudSettings (table) + _G._hudApply().
-- Everything lives inside one function so it adds nothing to the main chunk's local-variable budget.
do
local _hudOk, _hudErr = pcall(function()
    local lp   = Players.LocalPlayer
    local PURP = Color3.fromRGB(190, 34, 230)
    local pg   = lp:WaitForChild("PlayerGui")
    for _, n in ipairs({ "MockTradeHUD", "MockTradeHUDEditor" }) do
        local o = pg:FindFirstChild(n)
        if o then o:Destroy() end
    end

    local DEFAULTS = {
        bg = "1E1E28", bgT = 0, scale = 1.0, corner = 10, preset = 7,
        stroke = true, strokeC = "BE22E6",
        avatar = true, circle = false,
        nameC = "EBEBF5", nameS = 17, font = 2,
        subOn = true, subC = "FFFFFF",
        nameText = "", subText = "Add to join!",   -- custom text for the two lines ("" = your real username / display name)
        textOutline = true, outlineC = "000000", outlineSize = 2,   -- text stroke/outline
    }
    local FONTS = {
        { "Fredoka",  Enum.Font.FredokaOne },
        { "Gotham",   Enum.Font.GothamBold },
        { "Source",   Enum.Font.SourceSansBold },
        { "Code",     Enum.Font.Code },
        { "Cartoon",  Enum.Font.Cartoon },
        { "Arcade",   Enum.Font.Arcade },
    }
    -- background presets: solid colour / gradients / images.  { name, kind, a, b, rotation }
    local ADOPT_ICON = "rbxthumb://type=GameIcon&id=383310974&w=512&h=512"   -- Adopt Me! universe id
    local PRESETS = {
        { "Solid colour",        "solid" },
        { "Midnight",            "grad", "0F0C29", "302B63", 135 },
        { "Sunset",              "grad", "FF512F", "DD2476", 135 },
        { "Ocean",               "grad", "2193B0", "6DD5ED", 135 },
        { "Neon purple",         "grad", "BE22E6", "3A1C71", 135 },
        { "Mint",                "grad", "11998E", "38EF7D", 135 },
        { "Adopt Me thumbnail",  "adoptme", 1 },   -- more thumbnails get appended here once fetched
        { "Adopt Me icon",       "img", ADOPT_ICON },
    }
    local adoptAssets, adoptTried, fetchAdopt = {}, false, nil
    local S = {}
    for k, v in pairs(DEFAULTS) do S[k] = v end
    _G._hudSettings = S

    local function hexToC3(h)
        h = tostring(h or ""):gsub("[#%s]", "")
        if #h == 3 then h = h:sub(1,1):rep(2) .. h:sub(2,2):rep(2) .. h:sub(3,3):rep(2) end
        if #h ~= 6 or h:find("%X") then return nil end
        return Color3.fromRGB(tonumber(h:sub(1,2), 16), tonumber(h:sub(3,4), 16), tonumber(h:sub(5,6), 16))
    end
    local function corner(o, r) Instance.new("UICorner", o).CornerRadius = UDim.new(0, r or 3) end

    local function makeDraggable(handle, target, skip)
        local dragging, dragStart, startPos = false, nil, nil
        handle.InputBegan:Connect(function(input)
            if skip and skip(input) then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, input.Position, target.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - dragStart
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end

    ------------------------------------------------------------------ the HUD itself
    local gui = mk("ScreenGui", { Name = "MockTradeHUD", ResetOnSpawn = false, DisplayOrder = 9, Enabled = false, Parent = pg })
    local pill = mk("ImageLabel", { Name = "HUD", Image = "", ScaleType = Enum.ScaleType.Crop, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.fromOffset(260, 130),
        BorderSizePixel = 0, Parent = gui })
    local pillCorner = Instance.new("UICorner", pill)
    local pillStroke = mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Transparency = 0.35, Parent = pill })
    local uiScale    = mk("UIScale", { Scale = 1, Parent = pill })
    local pillGrad   = mk("UIGradient", { Enabled = false, Parent = pill })

    local avatar = mk("ImageLabel", { Name = "Avatar", Size = UDim2.new(0, 30, 0, 30), BackgroundColor3 = Color3.fromRGB(25, 25, 35), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 1,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. lp.UserId .. "&w=150&h=150", Parent = pill })
    local avatarCorner = Instance.new("UICorner", avatar)
    local avatarStroke = mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Transparency = 1, Enabled = false, Parent = avatar })
    -- some executors render rbxthumb:// late or not at all: also ask Roblox for the thumbnail directly
    task.spawn(function()
        local ok, img = pcall(function()
            return Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
        end)
        if ok and type(img) == "string" and img ~= "" and avatar.Parent then avatar.Image = img end
    end)

    local texts = mk("Frame", { Name = "Texts", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, LayoutOrder = 2, Parent = pill })
    mk("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = texts })
    local nameLbl = mk("TextLabel", { Name = "Username", Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = lp.Name,
        TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, Parent = texts })
    local nameOutline = mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Thickness = 2, Transparency = 1, Parent = nameLbl })
    -- second line: "Add to join!" (or custom sub text). Always centre-aligned and white by default.
    local hasSub = true
    local subLbl = mk("TextLabel", { Name = "DisplayName", Size = UDim2.new(0, 0, 0, 11), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
        Text = "Add to join!", TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = texts })
    local subOutline = mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Thickness = 2, Transparency = 1, Parent = subLbl })

    local function apply()
        local bg = hexToC3(S.bg) or hexToC3(DEFAULTS.bg)
        local bT   = math.clamp(S.bgT, 0, 1)
        local pr   = PRESETS[S.preset] or PRESETS[1]
        local kind = pr[2]
        pill.BackgroundColor3       = bg
        pill.BackgroundTransparency = bT
        pill.Image, pill.ImageColor3, pill.ImageTransparency = "", Color3.new(1, 1, 1), 0
        pillGrad.Enabled = false
        if kind == "grad" then
            pill.BackgroundColor3 = Color3.new(1, 1, 1)
            pillGrad.Color    = ColorSequence.new(hexToC3(pr[3]) or bg, hexToC3(pr[4]) or bg)
            pillGrad.Rotation = pr[5] or 135
            pillGrad.Enabled  = true
        elseif kind == "img" or kind == "adoptme" then
            local img = pr[3]
            if kind == "adoptme" then img = adoptAssets[pr[3] or 1] or ADOPT_ICON; if fetchAdopt then fetchAdopt() end end
            pill.Image            = img or ""
            pill.ImageColor3      = Color3.fromRGB(170, 170, 170)   -- slight dim so the text stays readable
            pill.ImageTransparency = bT
        end
        pillCorner.CornerRadius     = UDim.new(0, S.corner)
        uiScale.Scale               = math.clamp(S.scale, 0.3, 4)
        local sc = hexToC3(S.strokeC) or hexToC3(DEFAULTS.strokeC)
        pillStroke.Enabled = S.stroke
        pillStroke.Color   = sc
        avatarStroke.Color = sc
        avatar.Visible     = S.avatar
        avatarCorner.CornerRadius = S.circle and UDim.new(1, 0) or UDim.new(0, 6)
        local font = (FONTS[S.font] or FONTS[1])[2]
        nameLbl.Font = font; nameLbl.TextSize = S.nameS; nameLbl.Size = UDim2.new(0, 0, 0, S.nameS + 1)
        nameLbl.TextXAlignment = Enum.TextXAlignment.Center
        nameLbl.Text = (S.nameText ~= "" and S.nameText) or lp.Name
        nameLbl.TextColor3 = hexToC3(S.nameC) or hexToC3(DEFAULTS.nameC)
        local subS = math.max(9, S.nameS - 2)
        subLbl.Font = font; subLbl.TextSize = subS; subLbl.Size = UDim2.new(0, 0, 0, subS)
        subLbl.AutomaticSize = Enum.AutomaticSize.X
        subLbl.TextXAlignment = Enum.TextXAlignment.Center
        subLbl.TextColor3 = hexToC3(S.subC) or Color3.new(1, 1, 1)
        subLbl.Text = (S.subText ~= "" and S.subText) or "Add to join!"
        subLbl.Visible = S.subOn
        local outlineC = hexToC3(S.outlineC) or Color3.new(0, 0, 0)
        local outlineT = S.textOutline and 0 or 1
        nameOutline.Color = outlineC; nameOutline.Thickness = S.outlineSize or 2; nameOutline.Transparency = outlineT
        subOutline.Color  = outlineC; subOutline.Thickness  = S.outlineSize or 2; subOutline.Transparency  = outlineT

        -- layout: wide pill (about 2.8:1), like the on-screen HUD. Avatar pinned to the far left, vertically centred;
        -- both text lines centred (as a block) in the space to the right of it. Re-runs on every change.
        local TS = game:GetService("TextService")
        local function tw(txt, size)
            local okT, v = pcall(function() return TS:GetTextSize(txt, size, font, Vector2.new(1000, 1000)) end)
            return okT and v.X or (#txt * size * 0.6)
        end
        local textW = math.max(tw(nameLbl.Text, S.nameS), S.subOn and tw(subLbl.Text, subS) or 0)
        local textH = (S.nameS + 1) + (S.subOn and subS or 0)
        local H = math.floor(textH / 0.55)                -- the two text lines fill ~55% of the pill height
        local W, A
        if S.avatar then
            A = math.floor(H * 0.9)                       -- avatar nearly fills the height, flush on the far left
            local padL, gap = 4, math.floor(H * 0.1)      -- gap left of the text = gap on its right
            W = padL + A + gap + math.floor(textW) + gap
            avatar.AnchorPoint = Vector2.new(0, 0.5)
            avatar.Position    = UDim2.new(0, padL, 0.5, 0)
            avatar.Size        = UDim2.fromOffset(A, A)
            texts.Position     = UDim2.new(0, math.floor(padL + A + gap + textW / 2), 0.5, 0)   -- centred in the space right of the avatar
        else
            W = math.max(80, math.floor(textW + H * 0.5))
            texts.Position     = UDim2.new(0.5, 0, 0.5, 0)
        end
        pill.Size = UDim2.fromOffset(W, H)
    end
    _G._hudApply = apply
    -- real Adopt Me thumbnails, fetched automatically from Roblox's thumbnail API (needs request / writefile / getcustomasset;
    -- while loading, or if the executor lacks them, the game icon is shown instead). Extra thumbnails become extra presets.
    fetchAdopt = function()
        if adoptTried then return end
        adoptTried = true
        task.spawn(function()
            local function fail(step, e) warn("[HUD] Adopt Me thumbnail: " .. step .. " failed: " .. tostring(e)) end
            local ok, r = pcall(request, { Url = "https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds=383310974&countPerUniverse=5&defaults=true&size=768x432&format=Png&isCircular=false", Method = "GET" })
            if not ok or type(r) ~= "table" then return fail("api request", r) end
            local okj, d = pcall(function() return HttpService:JSONDecode(r.Body) end)
            local list = okj and d and d.data and d.data[1] and d.data[1].thumbnails
            if type(list) ~= "table" then return fail("api response", tostring(r.StatusCode) .. " " .. tostring(r.Body):sub(1, 120)) end
            local n = 0
            for _, t in ipairs(list) do
                if t.imageUrl then
                    local okd, img = pcall(request, { Url = t.imageUrl, Method = "GET" })
                    if okd and type(img) == "table" and img.Body and #img.Body > 100 then
                        local oka, asset = pcall(function()
                            local fn = "adoptme_thumb_" .. (n + 1) .. ".png"
                            writefile(fn, img.Body)
                            return getcustomasset(fn)
                        end)
                        if oka and asset then
                            n = n + 1
                            adoptAssets[n] = asset
                            if n > 1 then PRESETS[#PRESETS + 1] = { "Adopt Me thumbnail " .. n, "adoptme", n } end
                            if n == 1 then apply() end
                        else fail("save/getcustomasset", asset) end
                    else fail("image download", img) end
                end
            end
        end)
    end
    makeDraggable(pill, pill)

    ------------------------------------------------------------------ the editor panel
    local edGui = mk("ScreenGui", { Name = "MockTradeHUDEditor", ResetOnSpawn = false, DisplayOrder = 11, Enabled = false, Parent = pg })
    local ed = mk("Frame", { Name = "Panel", Size = UDim2.new(0, 200, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(0, 146, 0.5, -190),
        BackgroundColor3 = Color3.fromRGB(30, 30, 40), BorderSizePixel = 0, Active = true, Parent = edGui })
    corner(ed, 6)
    mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = PURP, Thickness = 1, Transparency = 0.3, Parent = ed })
    mk("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6), Parent = ed })
    mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3), Parent = ed })

    local order = 0
    local refreshers = {}
    local TXT  = Color3.fromRGB(215, 215, 225)
    local BTN  = Color3.fromRGB(45, 45, 60)

    local header = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "HUD Editor  (drag me)", Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = PURP, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, Parent = ed })
    makeDraggable(header, ed)

    local function newRow(label)
        order = order + 1
        local r = mk("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = order, Parent = ed })
        mk("TextLabel", { Size = UDim2.new(0.44, 0, 1, 0), BackgroundTransparency = 1, Text = label, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = TXT,
            TextXAlignment = Enum.TextXAlignment.Left, Parent = r })
        return r
    end
    local function mkBtn(parent, text, props)
        props = props or {}
        props.Text = text; props.BackgroundColor3 = props.BackgroundColor3 or BTN; props.Font = Enum.Font.GothamBold; props.TextSize = 10
        props.TextColor3 = props.TextColor3 or TXT; props.AutoButtonColor = true; props.BorderSizePixel = 0; props.Parent = parent
        local b = mk("TextButton", props)
        corner(b, 3)
        return b
    end

    -- Common colours to cycle through (name, hex)
    local COLOUR_CYCLE = {
        { "White",      "FFFFFF" }, { "Purple",     "BE22E6" }, { "Pink",       "FF69B4" },
        { "Hot pink",   "FF1493" }, { "Red",        "FF3333" }, { "Orange",     "FF8C00" },
        { "Yellow",     "FFE033" }, { "Lime",       "38EF7D" }, { "Green",      "22C55E" },
        { "Teal",       "11998E" }, { "Cyan",       "6DD5ED" }, { "Sky",        "38BDF8" },
        { "Blue",       "3B82F6" }, { "Navy",       "302B63" }, { "Lavender",   "C084FC" },
        { "Gold",       "FFD700" }, { "Rose",       "FB7185" }, { "Mint",       "A7F3D0" },
        { "Silver",     "C0C0C0" }, { "Dark",       "1E1E28" }, { "Black",      "111111" },
    }
    local function hexIdx(hex)
        hex = hex:upper()
        for i, c in ipairs(COLOUR_CYCLE) do if c[2]:upper() == hex then return i end end
        return nil
    end
    local function colorRow(label, key)
        local r  = newRow(label)
        -- swatch square showing current colour
        local sw = mk("Frame", { Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0.44, 0, 0.5, -7), BorderSizePixel = 0, Parent = r })
        corner(sw, 3)
        -- click to cycle forward, right-click to cycle back
        local btn = mk("TextButton", { Size = UDim2.new(0.56, -16, 1, 0), Position = UDim2.new(0.44, 16, 0, 0),
            BackgroundColor3 = BTN, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 9,
            TextColor3 = TXT, AutoButtonColor = false, Parent = r })
        corner(btn, 3)
        local function refresh()
            local c3 = hexToC3(S[key]) or Color3.new(1, 1, 1)
            sw.BackgroundColor3 = c3
            local idx = hexIdx(S[key])
            btn.Text = idx and COLOUR_CYCLE[idx][1] or ("#" .. S[key]:upper())
            -- make button bg match swatch for a nice look
            btn.BackgroundColor3 = c3
            -- pick contrasting text colour
            local lum = c3.R * 0.299 + c3.G * 0.587 + c3.B * 0.114
            btn.TextColor3 = lum > 0.55 and Color3.fromRGB(20, 20, 30) or Color3.new(1, 1, 1)
        end
        local function cycle(dir)
            local idx = hexIdx(S[key]) or 1
            idx = ((idx - 1 + dir) % #COLOUR_CYCLE) + 1
            S[key] = COLOUR_CYCLE[idx][2]; apply(); refresh()
        end
        btn.MouseButton1Click:Connect(function() cycle(1) end)
        btn.MouseButton2Click:Connect(function() cycle(-1) end)
        refreshers[#refreshers + 1] = refresh; refresh()
    end
    local function numRow(label, key, lo, hi, step)
        local r = newRow(label)
        local minus = mkBtn(r, "-", { Size = UDim2.new(0, 22, 1, 0), Position = UDim2.new(0.44, 0, 0, 0) })
        local val = mk("TextLabel", { Size = UDim2.new(0.56, -46, 1, 0), Position = UDim2.new(0.44, 24, 0, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = TXT, Parent = r })
        local plus = mkBtn(r, "+", { Size = UDim2.new(0, 22, 1, 0), Position = UDim2.new(1, -22, 0, 0) })
        local function refresh() val.Text = string.format("%g", S[key]) end
        local function bump(dir)
            S[key] = tonumber(string.format("%.2f", math.clamp(S[key] + dir * step, lo, hi)))
            apply(); refresh()
        end
        minus.MouseButton1Click:Connect(function() bump(-1) end)
        plus.MouseButton1Click:Connect(function() bump(1) end)
        refreshers[#refreshers + 1] = refresh; refresh()
    end
    local function toggleRow(label, key, onText, offText)
        local r = newRow(label)
        local b = mkBtn(r, "", { Size = UDim2.new(0.56, 0, 1, 0), Position = UDim2.new(0.44, 0, 0, 0) })
        local function refresh()
            b.Text = S[key] and onText or offText
            b.BackgroundColor3 = S[key] and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(80, 30, 30)
            b.TextColor3 = S[key] and Color3.fromRGB(80, 255, 130) or Color3.fromRGB(255, 120, 120)
        end
        b.MouseButton1Click:Connect(function() S[key] = not S[key]; apply(); refresh() end)
        refreshers[#refreshers + 1] = refresh; refresh()
    end
    local function fontRow(label)
        local r = newRow(label)
        local b = mkBtn(r, "", { Size = UDim2.new(0.56, 0, 1, 0), Position = UDim2.new(0.44, 0, 0, 0) })
        local function refresh() b.Text = FONTS[S.font][1] .. "  >" end
        b.MouseButton1Click:Connect(function() S.font = (S.font % #FONTS) + 1; apply(); refresh() end)
        refreshers[#refreshers + 1] = refresh; refresh()
    end

    local function textRow(label, key, placeholder)
        local r  = newRow(label)
        local tb = mk("TextBox", { Size = UDim2.new(0.56, 0, 1, 0), Position = UDim2.new(0.44, 0, 0, 0), BackgroundColor3 = BTN, BorderSizePixel = 0, ClearTextOnFocus = false,
            Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = TXT, PlaceholderText = placeholder, PlaceholderColor3 = Color3.fromRGB(120, 120, 135),
            Text = "", TextTruncate = Enum.TextTruncate.AtEnd, Parent = r })
        corner(tb, 3)
        local function refresh() tb.Text = S[key] end
        tb.FocusLost:Connect(function() S[key] = string.sub(tb.Text, 1, 40); apply(); refresh() end)
        refreshers[#refreshers + 1] = refresh; refresh()
    end

    local function presetRow(label)
        local r = newRow(label)
        local prev = mkBtn(r, "<", { Size = UDim2.new(0, 18, 1, 0), Position = UDim2.new(0.3, 0, 0, 0) })
        local nm   = mk("TextLabel", { Size = UDim2.new(0.7, -40, 1, 0), Position = UDim2.new(0.3, 20, 0, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = TXT, TextTruncate = Enum.TextTruncate.AtEnd, Parent = r })
        local nxt  = mkBtn(r, ">", { Size = UDim2.new(0, 18, 1, 0), Position = UDim2.new(1, -18, 0, 0) })
        local function refresh() nm.Text = (PRESETS[S.preset] or PRESETS[1])[1] end
        local function step(d) S.preset = ((S.preset - 1 + d) % #PRESETS) + 1; apply(); refresh() end
        prev.MouseButton1Click:Connect(function() step(-1) end)
        nxt.MouseButton1Click:Connect(function() step(1) end)
        refreshers[#refreshers + 1] = refresh; refresh()
    end
    presetRow("Background")
    textRow("Main text", "nameText", lp.Name)
    textRow("Sub text", "subText", "@" .. lp.DisplayName)
    colorRow("Bg colour", "bg")
    numRow("BG fade", "bgT", 0, 1, 0.05)
    numRow("Size", "scale", 0.5, 3, 0.1)
    numRow("Corners", "corner", 0, 19, 1)
    toggleRow("Outline", "stroke", "ON", "OFF")
    colorRow("Outline col", "strokeC")
    colorRow("Name colour", "nameC")
    numRow("Name size", "nameS", 8, 30, 1)
    fontRow("Font")
    toggleRow("Display name", "subOn", "SHOWN", "HIDDEN")
    colorRow("Disp. colour", "subC")
    toggleRow("Text outline", "textOutline", "ON", "OFF")
    colorRow("Outline col", "outlineC")
    numRow("Outline size", "outlineSize", 1, 6, 1)
    toggleRow("Avatar", "avatar", "SHOWN", "HIDDEN")
    toggleRow("Avatar shape", "circle", "CIRCLE", "SQUARE")

    order = order + 1
    local btnRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = order, Parent = ed })
    local resetBtn = mkBtn(btnRow, "Reset", { Size = UDim2.new(0.5, -2, 1, 0), BackgroundColor3 = Color3.fromRGB(80, 30, 30), TextColor3 = Color3.fromRGB(255, 120, 120) })
    local closeBtn = mkBtn(btnRow, "Close", { Size = UDim2.new(0.5, -2, 1, 0), Position = UDim2.new(0.5, 2, 0, 0) })
    resetBtn.MouseButton1Click:Connect(function()
        for k, v in pairs(DEFAULTS) do S[k] = v end
        apply()
        for _, f in ipairs(refreshers) do f() end
    end)

    ------------------------------------------------------------------ Misc Page 2: toggle + edit button
    local ctl = mk("Frame", { Name = "HudToggle", Size = UDim2.new(1, 0, 0, 27), Position = UDim2.new(0, 0, 1, -39), BackgroundTransparency = 1, ZIndex = 7, Parent = page2 })
    mk("TextLabel", { Size = UDim2.new(1, 0, 0, 9), BackgroundTransparency = 1, Text = "HUD (on screen)", Font = Enum.Font.FredokaOne, TextSize = 7, TextColor3 = PURP,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = ctl })
    local btn = mk("TextButton", { Size = UDim2.new(0.58, -2, 0, 15), Position = UDim2.new(0, 0, 0, 11), BackgroundColor3 = Color3.fromRGB(80, 30, 30), Text = "HUD: OFF",
        Font = Enum.Font.FredokaOne, TextSize = 8, TextColor3 = Color3.fromRGB(255, 90, 90), ZIndex = 7, Parent = ctl })
    corner(btn, 3)
    local btnStroke = mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.fromRGB(255, 60, 60), Thickness = 0.7, Transparency = 0.3, Parent = btn })
    local editBtn = mk("TextButton", { Size = UDim2.new(0.42, -2, 0, 15), Position = UDim2.new(0.58, 2, 0, 11), BackgroundColor3 = Color3.fromRGB(40, 40, 52), Text = "Edit",
        Font = Enum.Font.FredokaOne, TextSize = 8, TextColor3 = Color3.fromRGB(225, 225, 235), ZIndex = 7, Parent = ctl })
    corner(editBtn, 3)
    mk("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = PURP, Thickness = 0.7, Transparency = 0.4, Parent = editBtn })

    -- while the editor is open the HUD is shown as a live preview, then it goes back to whatever ON/OFF says
    local function showHud() gui.Enabled = (_G._hudOn == true) or edGui.Enabled end
    local function setHud(on)
        on = on and true or false
        _G._hudOn = on
        btn.Text = on and "HUD: ON" or "HUD: OFF"
        btn.BackgroundColor3 = on and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(80, 30, 30)
        btn.TextColor3 = on and Color3.fromRGB(80, 255, 130) or Color3.fromRGB(255, 90, 90)
        btnStroke.Color = on and Color3.fromRGB(0, 255, 100) or Color3.fromRGB(255, 60, 60)
        showHud()
    end
    local function setEditor(open)
        edGui.Enabled = open and true or false
        editBtn.BackgroundColor3 = open and Color3.fromRGB(70, 40, 100) or Color3.fromRGB(40, 40, 52)
        showHud()
    end
    _G._setHud = setHud
    btn.MouseButton1Click:Connect(function() setHud(not _G._hudOn) end)
    editBtn.MouseButton1Click:Connect(function() setEditor(not edGui.Enabled) end)
    closeBtn.MouseButton1Click:Connect(function() setEditor(false) end)

    apply()
    task.defer(function() if fetchAdopt then fetchAdopt() end end)   -- pre-load the Adopt Me thumbnails so the preset is instant
    setHud(false)   -- automatically OFF until you switch it on
end)
if not _hudOk then warn("[HUD] " .. tostring(_hudErr)) end
end

-- Disable Expired Popups: hides the game's "Trade request from X has expired!" dialogs
-- (which spam while auto-declining requests during a mock trade). Read via _G._hideExpiredDialogs.
-- Back / forward arrows — the down-arrow decal rotated to point left (+90°) and right (-90°)
-- Arrow decal 153287168 — its UNDERLYING IMAGE asset (153287167) so Rotation renders (rbxthumb won't rotate here)
local ARROW_IMG = "rbxassetid://153287167"
local navBack = mk("ImageButton", {Size=UDim2.new(0,14,0,14), Position=UDim2.new(0.5,-15,1,-15), BackgroundTransparency=1, Image=ARROW_IMG, ImageColor3=Color3.fromRGB(110,110,120), Rotation=90, ScaleType=Enum.ScaleType.Fit, ZIndex=52, Visible=false, Parent=mainFrame})
local navFwd = mk("ImageButton", {Size=UDim2.new(0,14,0,14), Position=UDim2.new(0.5,1,1,-15), BackgroundTransparency=1, Image=ARROW_IMG, ImageColor3=Color3.fromRGB(200,180,255), Rotation=-90, ScaleType=Enum.ScaleType.Fit, ZIndex=52, Visible=false, Parent=mainFrame})

local function setPage(n)
    ddList.Visible = false
    page2.Visible  = (n==2) and miscTab.Visible
    navBack.Visible = miscTab.Visible
    navFwd.Visible  = miscTab.Visible
    navBack.ImageColor3 = (n==2) and Color3.fromRGB(200,180,255) or Color3.fromRGB(110,110,120)
    navFwd.ImageColor3  = (n==1) and Color3.fromRGB(200,180,255) or Color3.fromRGB(110,110,120)
end
navFwd.MouseButton1Click:Connect(function() setPage(2) end)
navBack.MouseButton1Click:Connect(function() setPage(1) end)
miscTab:GetPropertyChangedSignal("Visible"):Connect(function() setPage(1) end)
setPage(1)
refreshUI()
end

end -- MISC TAB do block

do
local spawnFrame = tabFrames["Spawn"]

do local _BackpackFavoriteTracker = nil
local _BackpackLockTracker = nil
pcall(function() _BackpackFavoriteTracker = load("BackpackFavoriteTracker") end)
pcall(function() _BackpackLockTracker = load("BackpackLockTracker") end)

local _allPetNames = {}
local _petNameToId = {}
for kindId, entry in pairs(InventoryDB.pets or {}) do
    if entry.name then
        table.insert(_allPetNames, entry.name)
        _petNameToId[entry.name:lower()] = kindId
    end
end
-- Candyfloss Chick: make sure it is searchable / spawnable even if the pet database lists it under a slightly different name
if not _petNameToId["candyfloss chick"] then
    for kindId, entry in pairs(InventoryDB.pets or {}) do
        local k  = tostring(kindId):lower()
        local nm = (type(entry) == "table" and type(entry.name) == "string") and entry.name:lower() or ""
        local isFloss = k:find("candyfloss", 1, true) or k:find("candy_floss", 1, true) or nm:find("candyfloss", 1, true) or nm:find("candy floss", 1, true)
        local isChick = k:find("chick", 1, true) or nm:find("chick", 1, true)
        if isFloss and isChick then
            _petNameToId["candyfloss chick"] = kindId
            table.insert(_allPetNames, "Candyfloss Chick")
            break
        end
    end
end
table.sort(_allPetNames, function(a, b) return a:lower() < b:lower() end)

local spawnFlags   = { F = false, R = false, N = false, M = false }
local _spawnAge    = 6  -- default full grown

local _ageOptions = {
    { label = "Newborn",    value = 0 },
    { label = "Junior",     value = 1 },
    { label = "Pre-Teen",   value = 2 },
    { label = "Teen",       value = 3 },
    { label = "Post-Teen",  value = 4 },
    { label = "Full Grown", value = 5 },
    { label = "Luminous",   value = 6 },
}

local function spawnFlagsToProps()
    return { flyable   = spawnFlags.F, rideable  = spawnFlags.R, neon      = spawnFlags.N, mega_neon = spawnFlags.M, age       = _spawnAge, ailments_completed = 0, pet_trick_level    = 0, }
end

local function doSpawnPet(kindId, extraProps)
    -- Otherwise merge onto current spawnFlags
    local props
    if extraProps and extraProps.mega_neon ~= nil then
        props = {}
        for k,v in pairs(extraProps) do props[k] = v end
    else
        props = spawnFlagsToProps()
        if extraProps then for k,v in pairs(extraProps) do props[k] = v end end
    end
    if not props.rp_name or props.rp_name == "" then
        props.rp_name = generatePetName(kindId)
    end
    if not props.age               then props.age               = 1 end
    if not props.ailments_completed then props.ailments_completed = 0 end
    if not props.pet_trick_level   then props.pet_trick_level   = 0 end
    local uid = HttpService:GenerateGUID(false)
    local newItem = {
        unique        = uid,
        category      = "pets",
        kind          = kindId,
        id            = kindId,
        newness_order = math.random(1, 900000),
        properties    = props,
    }
    _addToInventory(newItem)
end

local spawnLayout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0, 4), Parent=spawnFrame})

local searchBox = mk("TextBox", {Size=UDim2.new(1, 0, 0, 14), BackgroundColor3=Color3.fromRGB(32, 32, 48), BackgroundTransparency=0.2, Text="", PlaceholderText="Search pet name...", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), PlaceholderColor3=Color3.fromRGB(120, 120, 140), ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Left, Parent=spawnFrame})
Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 3)
local searchStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=1.0, Transparency=0.3, Parent=searchBox})
local searchPad = mk("UIPadding", {PaddingLeft=UDim.new(0, 4), PaddingRight=UDim.new(0, 4), Parent=searchBox})

local autocompleteFrame = mk("Frame", {Size=UDim2.new(0, 110, 0, 0), BackgroundColor3=Color3.fromRGB(30, 30, 42), BorderSizePixel=0, Visible=false, ZIndex=20, Parent=mainFrame})
Instance.new("UICorner", autocompleteFrame).CornerRadius = UDim.new(0, 3)
local autoStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.3, Parent=autocompleteFrame})
local autoLayout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Parent=autocompleteFrame})

local _autoMatches = {}
local _selectedAutoIdx = 0

local function hideAutocomplete()
    autocompleteFrame.Visible = false
    _autoMatches = {}
    _selectedAutoIdx = 0
end

local function applyAutoSelection(idx)
    if not _autoMatches[idx] then return end
    _selectedAutoIdx = idx
    for i, btn in ipairs(autocompleteFrame:GetChildren()) do
        if btn:IsA("TextButton") then
            btn.BackgroundColor3 = (i == idx)
                and Color3.fromRGB(80, 40, 120)
                or  Color3.fromRGB(30, 30, 42)
        end
    end
end

local function commitAutocomplete(idx)
    local name = _autoMatches[idx]
    if not name then return end
    searchBox.Text = name
    hideAutocomplete()
end

local function updateAutocomplete(text)
    for _, c in ipairs(autocompleteFrame:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    _autoMatches = {}
    _selectedAutoIdx = 0

    if text == "" then hideAutocomplete() return end

    local lower = text:lower()
    local matches = {}
    for _, name in ipairs(_allPetNames) do
        if name:lower():sub(1, #lower) == lower then
            table.insert(matches, name)
            if #matches >= 5 then break end
        end
    end
    -- Also do contains search if fewer than 5 prefix matches
    if #matches < 5 then
        for _, name in ipairs(_allPetNames) do
            if name:lower():find(lower, 1, true) and name:lower():sub(1, #lower) ~= lower then
                table.insert(matches, name)
                if #matches >= 5 then break end
            end
        end
    end

    if #matches == 0 then hideAutocomplete() return end

    _autoMatches = matches
    for i, name in ipairs(matches) do
        local btn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(30, 30, 42), BackgroundTransparency=0, Text=name, Font=Enum.Font.FredokaOne, TextSize=6, TextColor3=Color3.fromRGB(220, 220, 255), TextXAlignment=Enum.TextXAlignment.Left, BorderSizePixel=0, ZIndex=21, LayoutOrder=i, Parent=autocompleteFrame})
        local bpad = mk("UIPadding", {PaddingLeft=UDim.new(0, 4), Parent=btn})
        btn.MouseButton1Click:Connect(function()
            commitAutocomplete(i)
        end)
    end

    local absPos = searchBox.AbsolutePosition
    local frameAbsPos = mainFrame.AbsolutePosition
    local relX = absPos.X - frameAbsPos.X
    local relY = absPos.Y - frameAbsPos.Y + searchBox.AbsoluteSize.Y + 2
    local dropH = #matches * 13
    autocompleteFrame.Position = UDim2.new(0, relX, 0, relY); autocompleteFrame.Size     = UDim2.new(0, searchBox.AbsoluteSize.X, 0, dropH)
    autocompleteFrame.Visible  = true
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    updateAutocomplete(searchBox.Text)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not searchBox:IsFocused() then return end
    if input.KeyCode == Enum.KeyCode.Tab then
        if #_autoMatches > 0 then
            local next = (_selectedAutoIdx % #_autoMatches) + 1
            applyAutoSelection(next)
            commitAutocomplete(next)
        end
    elseif input.KeyCode == Enum.KeyCode.Down then
        if #_autoMatches > 0 then
            applyAutoSelection((_selectedAutoIdx % #_autoMatches) + 1)
        end
    elseif input.KeyCode == Enum.KeyCode.Up then
        if #_autoMatches > 0 then
            local prev = _selectedAutoIdx - 1
            if prev < 1 then prev = #_autoMatches end
            applyAutoSelection(prev)
        end
    elseif input.KeyCode == Enum.KeyCode.Return then
        if _selectedAutoIdx > 0 then
            commitAutocomplete(_selectedAutoIdx)
        elseif #_autoMatches > 0 then
            commitAutocomplete(1)
        end
        hideAutocomplete()
    elseif input.KeyCode == Enum.KeyCode.Escape then
        hideAutocomplete()
    end
end)

searchBox.FocusLost:Connect(function()
    task.delay(0.15, hideAutocomplete)
end)

local spawnFlagRow = mk("Frame", {Size=UDim2.new(1, 0, 0, 13), BackgroundTransparency=1, Parent=spawnFrame})

local _spawnFlagDefs = {
    { key="M", col=Color3.fromRGB(170, 0, 255)  },
    { key="N", col=Color3.fromRGB(0, 190, 80)   },
    { key="F", col=Color3.fromRGB(0, 175, 255)  },
    { key="R", col=Color3.fromRGB(255, 45, 145) },
}
local _spawnFlagBtns = {}
local _sfBtnW = 26
local _sfGap  = math.floor((116 - _sfBtnW * 4) / 3)

for i, fd in ipairs(_spawnFlagDefs) do
    local xOff = (i-1) * (_sfBtnW + _sfGap)
    local pb = mk("TextButton", {Size=UDim2.new(0, _sfBtnW, 1, 0), Position=UDim2.new(0, xOff, 0, 0), BackgroundColor3=Color3.fromRGB(32, 32, 48), BackgroundTransparency=0.2, Text=fd.key, Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(220, 220, 255), Parent=spawnFlagRow})
    Instance.new("UICorner", pb).CornerRadius = UDim.new(0, 3)
    local s = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=fd.col, Thickness=0.7, Transparency=0.3, Parent=pb})
    _spawnFlagBtns[fd.key] = { btn=pb, stroke=s, col=fd.col }

    pb.MouseButton1Click:Connect(function()
        if fd.key == "M" and spawnFlags.N then
            spawnFlags.N = false
            local nd = _spawnFlagBtns["N"]
            nd.btn.BackgroundColor3      = Color3.fromRGB(32, 32, 48); nd.btn.BackgroundTransparency = 0.2
            nd.stroke.Color              = nd.col; nd.stroke.Transparency       = 0.3
            nd.stroke.Thickness          = 0.7
        elseif fd.key == "N" and spawnFlags.M then
            spawnFlags.M = false
            local md = _spawnFlagBtns["M"]
            md.btn.BackgroundColor3      = Color3.fromRGB(32, 32, 48); md.btn.BackgroundTransparency = 0.2
            md.stroke.Color              = md.col; md.stroke.Transparency       = 0.3
            md.stroke.Thickness          = 0.7
        end
        spawnFlags[fd.key] = not spawnFlags[fd.key]
        if spawnFlags[fd.key] then
            pb.BackgroundColor3      = Color3.fromRGB(60, 60, 80)
            pb.BackgroundTransparency = 0.1
            s.Color                  = fd.col; s.Transparency           = 0
            s.Thickness              = 1.2
        else
            pb.BackgroundColor3      = Color3.fromRGB(32, 32, 48)
            pb.BackgroundTransparency = 0.2
            s.Color                  = fd.col; s.Transparency           = 0.3
            s.Thickness              = 0.7
        end
    end)
end

local spawnPetBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(0, 100, 200), BackgroundTransparency=0.15, Text="Spawn Pet", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=spawnFrame})
Instance.new("UICorner", spawnPetBtn).CornerRadius = UDim.new(0, 3)
local spawnPetStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 180, 255), Thickness=0.7, Transparency=0.3, Parent=spawnPetBtn})

spawnPetBtn.MouseButton1Click:Connect(function()
    local name = searchBox.Text
    if name == "" then return end
    local kindId = _petNameToId[name:lower()]
    if not kindId then
        local lower = name:lower()
        for n, id in pairs(_petNameToId) do
            if n:find(lower, 1, true) then kindId = id; break end
        end
    end
    if not kindId then
        spawnPetStroke.Color = Color3.fromRGB(255, 60, 60)
        task.delay(0.5, function() spawnPetStroke.Color = Color3.fromRGB(0, 180, 255) end)
        return
    end
    doSpawnPet(kindId)
    spawnPetStroke.Color = Color3.fromRGB(0, 255, 120)
    task.delay(0.4, function() spawnPetStroke.Color = Color3.fromRGB(0, 180, 255) end)
end)

-- Age selector row
local ageRow = mk("Frame", {Size=UDim2.new(1,0,0,13), BackgroundTransparency=1, Parent=spawnFrame})

local agePrevBtn = mk("TextButton", {Size=UDim2.new(0,13,1,0), BackgroundColor3=Color3.fromRGB(32,32,48), BackgroundTransparency=0.2, Text="◀", Font=Enum.Font.GothamBold, TextSize=7, TextColor3=Color3.fromRGB(180,180,220), BorderSizePixel=0, Parent=ageRow})
Instance.new("UICorner", agePrevBtn).CornerRadius = UDim.new(0,3)

local ageLbl = mk("TextButton", {Size=UDim2.new(1,-28,1,0), Position=UDim2.new(0,15,0,0), BackgroundColor3=Color3.fromRGB(32,32,48), BackgroundTransparency=0.2, Text="Luminous (6)", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(220,180,255), BorderSizePixel=0, Parent=ageRow})
Instance.new("UICorner", ageLbl).CornerRadius = UDim.new(0,3)
local ageLblStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=ageLbl})

local ageNextBtn = mk("TextButton", {Size=UDim2.new(0,13,1,0), Position=UDim2.new(1,-13,0,0), BackgroundColor3=Color3.fromRGB(32,32,48), BackgroundTransparency=0.2, Text="▶", Font=Enum.Font.GothamBold, TextSize=7, TextColor3=Color3.fromRGB(180,180,220), BorderSizePixel=0, Parent=ageRow})
Instance.new("UICorner", ageNextBtn).CornerRadius = UDim.new(0,3)

local _ageIdx = 7  -- starts at Luminous (index 7)
local function updateAgeLbl()
    local opt = _ageOptions[_ageIdx]
    ageLbl.Text = opt.label .. " (" .. opt.value .. ")"
    _spawnAge = opt.value
end
updateAgeLbl()
agePrevBtn.MouseButton1Click:Connect(function()
    _ageIdx = _ageIdx > 1 and _ageIdx - 1 or #_ageOptions
    updateAgeLbl()
end)
ageNextBtn.MouseButton1Click:Connect(function()
    _ageIdx = _ageIdx < #_ageOptions and _ageIdx + 1 or 1
    updateAgeLbl()
end)
ageLbl.MouseButton1Click:Connect(function()
    _ageIdx = _ageIdx < #_ageOptions and _ageIdx + 1 or 1
    updateAgeLbl()
end)

-- ===== SPAWN SMALLS =====
-- When ON, "Spawn All Variants" and "Spawn All High Tiers" also add the small pets below.
-- Flag mode: M = mega neon | N = neon | Normal = no neon | All = all three. Fly / ride potions are random.
local SMALLS_PETS = {
    "Astronaut Gorilla", "Pineapple Owl", "Arctic Fox", "Apple Owl", "Arctic Dusk Dragon", "Aurora Fox",
    "Black Chested Pheasant", "Goat", "Nessie", "Many Mackerel", "Sheeeeep", "Papa Moose", "Shark Puppy",
    "Midnight Dragon", "Dango Penguins", "Emperor Gorilla", "Jellyfish", "Strawberry Penguin", "Caelum Cervi", "Blue Dog",
}
local SMALLS_MIN, SMALLS_MAX = 4, 9   -- random copies of each pet per flag mode
local _spawnSmallsOn = false
local SMALLS_MODES = { "M", "N", "Normal", "All" }
local _smallsModeIdx = 4
-- Name matching that survives punctuation / spacing differences ("Black-Chested Pheasant"), checks the kind id too,
-- and only accepts kinds that exist in BOTH KindDB and InventoryDB.pets (otherwise _addToInventory refuses them).
local function _normName(str) return (tostring(str):lower():gsub("[^%w]", "")) end
local function _collapseRuns(str) return (str:gsub("(%w)%1+", "%1")) end
local _smallsIdx
local function _buildSmallsIdx()
    local idx = { byName = {}, byKey = {}, list = {} }
    for kindId, entry in pairs(InventoryDB.pets or {}) do
        if type(entry) == "table" and entry.name and KindDB and KindDB[kindId] then
            local n = _normName(entry.name)
            idx.byName[n] = idx.byName[n] or kindId
            idx.byKey[_normName(kindId)] = idx.byKey[_normName(kindId)] or kindId
            idx.list[#idx.list + 1] = { id = kindId, norm = n, display = entry.name }
        end
    end
    return idx
end
local function _smallsKind(name)
    _smallsIdx = _smallsIdx or _buildSmallsIdx()
    local idx = _smallsIdx
    local n = _normName(name)
    if idx.byName[n] then return idx.byName[n] end
    if idx.byKey[n] then return idx.byKey[n] end
    local n2 = n:gsub("s$", "")                       -- plural / singular ("Dango Penguins" vs "Dango Penguin")
    if idx.byName[n2] then return idx.byName[n2] end
    local c = _collapseRuns(n)                        -- stretched names ("Sheeeeep"): pick the longest spelling that collapses the same
    local best
    for _, e in ipairs(idx.list) do
        if _collapseRuns(e.norm) == c and #e.norm > #c + 0 and (not best or #e.norm > #best.norm) then best = e end
    end
    if best and #best.norm > 5 then warn("[Spawn Smalls] '" .. name .. "' matched '" .. best.display .. "'"); return best.id end
    local tokens = {}                                 -- every word of the name must appear in exactly one pet's name
    for w in tostring(name):lower():gmatch("%a+") do tokens[#tokens + 1] = w end
    local found, count = nil, 0
    for _, e in ipairs(idx.list) do
        local all = true
        for _, w in ipairs(tokens) do if not e.norm:find(w, 1, true) then all = false; break end end
        if all then found = found and (#e.norm < #found.norm and e or found) or e; count = count + 1 end
    end
    if found and (count == 1 or #tokens >= 2) then
        warn("[Spawn Smalls] '" .. name .. "' matched '" .. found.display .. "'")
        return found.id
    end
    return nil
end
local function _randPots()
    local r = math.random(1, 100)
    if r <= 40 then return true, true end     -- FR
    if r <= 60 then return true, false end    -- F
    if r <= 80 then return false, true end    -- R
    return false, false                       -- no potions
end
local function _spawnSmallPets()
    local modes = {}
    local m = SMALLS_MODES[_smallsModeIdx]
    if m == "M" then modes = { "M" } elseif m == "N" then modes = { "N" }
    elseif m == "Normal" then modes = { "Normal" } else modes = { "M", "N", "Normal" } end
    local spawned, missing, failedAdd = {}, {}, {}
    _smallsIdx = nil   -- rebuild the lookup each run (database may have loaded more pets)
    for _, name in ipairs(SMALLS_PETS) do
        local petId = _smallsKind(name)
        if petId then
            for _, mode in ipairs(modes) do
                for _ = 1, math.random(SMALLS_MIN, SMALLS_MAX) do
                    local fly, ride = _randPots()
                    if mode == "M" then   -- mega: only MFR or MR (never MF, never plain M)
                        fly = (math.random(1, 100) <= 60)
                        ride = true
                    end
                    local item = _addToInventory({
                        unique     = HttpService:GenerateGUID(false),
                        id         = petId,
                        kind       = petId,
                        category   = "pets",
                        properties = {
                            mega_neon          = (mode == "M"),
                            neon               = (mode == "N"),
                            flyable            = fly,
                            rideable           = ride,
                            age                = math.random(1, 6),
                            trick_level        = math.random(0, 5),
                            ailments_completed = 0,
                            rp_name            = generatePetName(petId),
                        },
                    })
                    if item then spawned[#spawned + 1] = { item = item, kind = petId }
                    else failedAdd[name] = (failedAdd[name] or 0) + 1 end
                end
            end
        else
            table.insert(missing, name)
        end
    end
    for nm, cnt in pairs(failedAdd) do warn("[Spawn Smalls] " .. nm .. ": " .. cnt .. " failed to add (see [Spawner] warning above)") end
    if #missing > 0 then warn("[Spawn Smalls] not found in game database: " .. table.concat(missing, ", ")) end
    print("[Spawn Smalls] spawned " .. #spawned .. " pets")
    return spawned
end

local smallsRow = mk("Frame", {Size=UDim2.new(1,0,0,13), BackgroundTransparency=1, Parent=spawnFrame})
local smallsToggleBtn = mk("TextButton", {Size=UDim2.new(0.62,-1,1,0), BackgroundColor3=Color3.fromRGB(40,40,55), BackgroundTransparency=0.15, Text="Spawn Smalls: OFF", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(220,220,235), BorderSizePixel=0, AutoButtonColor=false, Parent=smallsRow})
Instance.new("UICorner", smallsToggleBtn).CornerRadius = UDim.new(0,3)
local smallsToggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=smallsToggleBtn})
local smallsModeBtn = mk("TextButton", {Size=UDim2.new(0.38,0,1,0), Position=UDim2.new(0.62,0,0,0), BackgroundColor3=Color3.fromRGB(32,32,48), BackgroundTransparency=0.2, Text="Flags: All", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(180,180,220), BorderSizePixel=0, AutoButtonColor=false, Parent=smallsRow})
Instance.new("UICorner", smallsModeBtn).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=smallsModeBtn})
local function _refreshSmallsUI()
    smallsToggleBtn.Text = "Spawn Smalls: " .. (_spawnSmallsOn and "ON" or "OFF")
    smallsToggleBtn.BackgroundColor3 = _spawnSmallsOn and Color3.fromRGB(30,120,70) or Color3.fromRGB(40,40,55)
    smallsModeBtn.Text = "Flags: " .. SMALLS_MODES[_smallsModeIdx]
end
smallsToggleBtn.MouseButton1Click:Connect(function() _spawnSmallsOn = not _spawnSmallsOn; _refreshSmallsUI() end)
smallsModeBtn.MouseButton1Click:Connect(function()
    _smallsModeIdx = _smallsModeIdx % #SMALLS_MODES + 1
    _refreshSmallsUI()
end)
_refreshSmallsUI()

local spawnAllVariantsBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(100, 30, 180), BackgroundTransparency=0.15, Text="Spawn All Variants", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=spawnFrame})
Instance.new("UICorner", spawnAllVariantsBtn).CornerRadius = UDim.new(0, 3)
local spawnAllVStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.3, Parent=spawnAllVariantsBtn})

_G._setupLiveSpawnAllVariantsBtn = spawnAllVariantsBtn
local function _runSpawnAllVariants()
    spawnAllVariantsBtn.Text = "Spawning..."
    spawnAllVStroke.Color = Color3.fromRGB(255, 165, 0)
    task.spawn(function()
        local allSpawnedItems = {}
        local defaultVariants = {
            { name="MFR", mega_neon=true,  neon=false, flyable=true, rideable=true,  age=6 },
            { name="NFR", mega_neon=false, neon=true,  flyable=true, rideable=true,  age=6 },
            { name="FR",  mega_neon=false, neon=false, flyable=true, rideable=true,  age=6 },
        }
        local COPIES_PER_VARIANT = 8
        local allFlagCombos = {
            { mega_neon=false, neon=false, flyable=false, rideable=false },
            { mega_neon=false, neon=false, flyable=true,  rideable=false },
            { mega_neon=false, neon=false, flyable=false, rideable=true  },
            { mega_neon=false, neon=false, flyable=true,  rideable=true  },
            { mega_neon=false, neon=true,  flyable=false, rideable=false },
            { mega_neon=false, neon=true,  flyable=true,  rideable=false },
            { mega_neon=false, neon=true,  flyable=false, rideable=true  },
            { mega_neon=false, neon=true,  flyable=true,  rideable=true  },
            { mega_neon=true,  neon=false, flyable=false, rideable=false },
            { mega_neon=true,  neon=false, flyable=true,  rideable=false },
            { mega_neon=true,  neon=false, flyable=false, rideable=true  },
            { mega_neon=true,  neon=false, flyable=true,  rideable=true  },
        }

        local totalPets = #HIGH_TIER_PETS
        local totalSpawned = 0

        -- Each pet gets a block of 10000 newness units.
        -- Within that block, each variant tier (MFR/NFR/FR) gets 100 units,
        -- and random combos sit below all named variants.
        -- This guarantees no pet's variants ever bleed into another pet's range.
        local PET_STRIDE      = 10000  -- space between pets
        local VARIANT_STRIDE  = 100    -- space between variant tiers within a pet
        -- Named variants: varIdx 1=MFR, 2=NFR, 3=FR → descending offsets so MFR sorts highest
        -- varIdx 1 → offset (4-1)*100 = 300, varIdx 2 → 200, varIdx 3 → 100
        -- Random combos: offset 0..49 (below all named variants)

        for petIndex, petName in ipairs(HIGH_TIER_PETS) do
            local petId = _petNameToId[petName:lower()]
            if not petId then
                for n, id in pairs(_petNameToId) do
                    if n:find(petName:lower(), 1, true) then petId = id; break end
                end
            end
            if petId then
                -- Base for this pet: highest-index pet (last in list) gets lowest base so
                -- first pet in HIGH_TIER_PETS appears at the top of the backpack.
                local petBase = (totalPets - petIndex) * PET_STRIDE

                for varIdx, variant in ipairs(defaultVariants) do
                    -- varIdx 1 (MFR) → tierOffset 300, 2 (NFR) → 200, 3 (FR) → 100
                    local tierOffset = (4 - varIdx) * VARIANT_STRIDE
                    for copy = 1, COPIES_PER_VARIANT do
                        -- copies descend within the tier: copy 1 is newest
                        local newness = petBase + tierOffset + (COPIES_PER_VARIANT - copy)
                        local item = _addToInventory({
                            unique     = HttpService:GenerateGUID(false),
                            id         = petId,
                            kind       = petId,
                            category   = "pets",
                            properties = {
                                mega_neon          = variant.mega_neon,
                                neon               = variant.neon,
                                flyable            = variant.flyable,
                                rideable           = variant.rideable,
                                age                = variant.age,
                                trick_level        = 5,
                                ailments_completed = 0,
                                rp_name            = generatePetName(petId),
                                _newness_order     = newness,
                            },
                        })
                        if item then totalSpawned = totalSpawned + 1; table.insert(allSpawnedItems, {item=item, kind=petId}) end
                    end
                end
                -- Random combos sit in offset 0..49, below all three named variant tiers
                for r = 1, 8 do
                    local combo = allFlagCombos[math.random(1, #allFlagCombos)]
                    local newness = petBase + math.random(0, 49)
                    local item = _addToInventory({
                        unique     = HttpService:GenerateGUID(false),
                        id         = petId,
                        kind       = petId,
                        category   = "pets",
                        properties = {
                            mega_neon          = combo.mega_neon,
                            neon               = combo.neon,
                            flyable            = combo.flyable,
                            rideable           = combo.rideable,
                            age                = math.random(1, 6),
                            trick_level        = math.random(0, 5),
                            ailments_completed = 0,
                            rp_name            = generatePetName(petId),
                            _newness_order     = newness,
                        },
                    })
                    if item then totalSpawned = totalSpawned + 1; table.insert(allSpawnedItems, {item=item, kind=petId}) end
                end
            end
            if petIndex % 10 == 0 then
                task.wait()
            end
        end

        if _spawnSmallsOn then
            for _, e in ipairs(_spawnSmallPets()) do
                totalSpawned = totalSpawned + 1
                table.insert(allSpawnedItems, e)
            end
        end

        local favouritedCount = 0
        local lockedCount = 0
        local lockedKinds2 = {}
        -- lock about 100 out of every 1600 spawned pets (1 in 16), picked at random across all kinds
        local lockSet = {}
        do
            local order = {}
            for i = 1, #allSpawnedItems do order[i] = i end
            for i = #order, 2, -1 do local j = math.random(1, i); order[i], order[j] = order[j], order[i] end
            local lockTarget = math.floor(#allSpawnedItems / 16 + 0.5)
            for i = 1, lockTarget do lockSet[allSpawnedItems[order[i]]] = true end
        end
        for _, entry in ipairs(allSpawnedItems) do
            local itemData = entry.item
            local petKind  = entry.kind
            if math.random(1, 100) <= 30 then
                pcall(function()
                    if _BackpackFavoriteTracker and _BackpackFavoriteTracker.set_favorite then
                        _BackpackFavoriteTracker.set_favorite(itemData, true, true)
                        favouritedCount = favouritedCount + 1
                    else
                        local id = (get_thread_identity and get_thread_identity()) or 8
                        setthreadidentity(2)
                        local favs = ClientData.get("backpack_favorites") or {}
                        favs[itemData.unique] = true
                        ClientData.update("backpack_favorites", favs)
                        setthreadidentity(id)
                        favouritedCount = favouritedCount + 1
                    end
                end)
            end
            if lockSet[entry] then
                pcall(function()
                    if _BackpackLockTracker and _BackpackLockTracker.set_locked then
                        _BackpackLockTracker.set_locked(itemData, true, true)
                        lockedKinds2[petKind] = true
                        lockedCount = lockedCount + 1
                    else
                        local id = (get_thread_identity and get_thread_identity()) or 8
                        setthreadidentity(2)
                        local locks = ClientData.get("backpack_locks") or {}
                        locks[itemData.unique] = true
                        ClientData.update("backpack_locks", locks)
                        setthreadidentity(id)
                        lockedKinds2[petKind] = true
                        lockedCount = lockedCount + 1
                    end
                end)
            end
        end

        task.defer(function()
            pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)
        end)

        spawnAllVStroke.Color = Color3.fromRGB(0, 255, 120)
        spawnAllVariantsBtn.Text = "Spawned " .. totalSpawned .. " | ♥" .. favouritedCount .. " 🔒" .. lockedCount
        task.delay(3, function()
            spawnAllVariantsBtn.Text = "Spawn All Variants"
            spawnAllVStroke.Color = Color3.fromRGB(190,34,230)
        end)
    end)
end
spawnAllVariantsBtn.MouseButton1Click:Connect(_runSpawnAllVariants)
_G._setupLiveRunSpawnAllVariants = _runSpawnAllVariants






local spawnHighTierBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(160, 100, 20), BackgroundTransparency=0.15, Text="Spawn All High Tiers", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=spawnFrame})
Instance.new("UICorner", spawnHighTierBtn).CornerRadius = UDim.new(0, 3)
local spawnHTStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 180, 0), Thickness=0.7, Transparency=0.3, Parent=spawnHighTierBtn})

spawnHighTierBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        for _, petName in ipairs(HIGH_TIER_PETS) do
            local kindId = nil
            for id, entry in pairs(InventoryDB.pets or {}) do
                if entry.name and entry.name:lower() == petName:lower() then
                    kindId = id; break
                end
            end
            if kindId then
                doSpawnPet(kindId)
                task.wait(0.05)
            end
        end
        if _spawnSmallsOn then
            _spawnSmallPets()
            task.defer(function()
                pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)
            end)
        end
    end)
    spawnHTStroke.Color = Color3.fromRGB(0, 255, 120)
    task.delay(0.5, function() spawnHTStroke.Color = Color3.fromRGB(255, 180, 0) end)
end)

local petListBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(30, 70, 50), BackgroundTransparency=0.15, Text="Pet List (Browse & Spawn)", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=spawnFrame})
Instance.new("UICorner", petListBtn).CornerRadius = UDim.new(0, 3)
local petListStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0, 255, 100), Thickness=0.7, Transparency=0.3, Parent=petListBtn})

petListBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        local fakeInv = { pets = {} }
        -- Every entry is built like a real pet: it needs rp_name (the grid / sort / search read it, and
        -- pets without it failed to render so only eggs showed up) and its own newness_order.
        local entries = {}
        for kindId, entry in pairs(InventoryDB.pets or {}) do
            if type(entry) == "table" and entry.name then entries[#entries + 1] = { kindId, entry } end
        end
        table.sort(entries, function(a, b) return tostring(a[2].name) < tostring(b[2].name) end)
        for i, e in ipairs(entries) do
            local kindId, entry = e[1], e[2]
            local uid = HttpService:GenerateGUID(false)
            local props = spawnFlagsToProps()
            local isEggKind = tostring(entry.name):lower():find("egg", 1, true) ~= nil
            if isEggKind then
                props.flyable, props.rideable, props.neon, props.mega_neon = false, false, false, false
            else
                local okN, nm = pcall(generatePetName, kindId)
                props.rp_name = (okN and nm) or entry.name
            end
            props.age = props.age or 1
            props.ailments_completed = props.ailments_completed or 0
            props.pet_trick_level = props.pet_trick_level or 0
            fakeInv.pets[uid] = { unique = uid, category = "pets", kind = kindId, id = kindId,
                newness_order = _G._spawnNewness and _G._spawnNewness(kindId, props, true) or (800000 - i), properties = props }
        end
        local picked = BackpackApp:pick_item({
            title_override     = "SELECT PET TO SPAWN",
            inventory_override = fakeInv,
            visible_backpack_categories = {"pets"},
            force_no_filters   = true,
            allow_callback     = function() return true end,
        })
        if picked and picked.kind then
            doSpawnPet(picked.kind)
            petListStroke.Color = Color3.fromRGB(0, 255, 120)
            task.delay(0.4, function() petListStroke.Color = Color3.fromRGB(0, 255, 100) end)
        end
    end)
end)

end do local fakeInvBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(90, 50, 160), BackgroundTransparency=0.15, Text="Spawn Fake Inventory", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=spawnFrame})
Instance.new("UICorner", fakeInvBtn).CornerRadius = UDim.new(0, 3)
local fakeInvStroke = mk("UIStroke", {Color=Color3.fromRGB(190, 100, 255), Thickness=0.7, Parent=fakeInvBtn})

local FAKE_INV_CATEGORIES = {
    { db = "toys",            category = "toys"            },
    { db = "food",            category = "food"            },
    { db = "gifts",           category = "gifts"           },
    { db = "roleplay",        category = "roleplay"        },
    { db = "stickers",        category = "stickers"        },
    { db = "strollers",       category = "strollers"       },
    { db = "transport",       category = "transport"       },
    { db = "pet_accessories", category = "pet_accessories" },
}

_G._setupLiveFakeInvBtn = fakeInvBtn
local function _runFakeInv()
    fakeInvBtn.Text = "Spawning..."
    fakeInvStroke.Color = Color3.fromRGB(255, 165, 0)
    task.spawn(function()
        local totalSpawned = 0
        local totalFailed  = 0
        for _, catInfo in ipairs(FAKE_INV_CATEGORIES) do
            local dbTable = InventoryDB and InventoryDB[catInfo.db]
            if not dbTable then continue end
            local kindKeys = {}
            for kind in pairs(dbTable) do table.insert(kindKeys, kind) end
            if #kindKeys == 0 then continue end
            local count = math.random(5, 10)
            for _ = 1, count do
                local kind = kindKeys[math.random(1, #kindKeys)]
                local uid = HttpService:GenerateGUID(false)
                local ok = pcall(function()
                    local id = (get_thread_identity and get_thread_identity()) or 8
                    setthreadidentity(2)
                    local inv = ClientData.get("inventory")
                    if inv then
                        if not inv[catInfo.category] then inv[catInfo.category] = {} end
                        inv[catInfo.category][uid] = {
                            unique     = uid,
                            id         = kind,
                            kind       = kind,
                            category   = catInfo.category,
                            properties = {},
                        }
                    end
                    setthreadidentity(id)
                end)
                if ok then totalSpawned = totalSpawned + 1
                else totalFailed = totalFailed + 1 end
            end
        end
        task.defer(function()
            pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)
        end)
        fakeInvBtn.Text = "Spawned " .. totalSpawned .. "!"
        fakeInvStroke.Color = Color3.fromRGB(0, 255, 120)
        task.delay(2, function()
            fakeInvBtn.Text = "Spawn Fake Inventory"
            fakeInvStroke.Color = Color3.fromRGB(190, 100, 255)
        end)
    end)
end
fakeInvBtn.MouseButton1Click:Connect(_runFakeInv)
_G._setupLiveRunFakeInv = _runFakeInv

do
local fakeHistoryStatusLbl = mk("TextLabel", {Size=UDim2.new(1, 0, 0, 9), BackgroundTransparency=1, Text="", Font=Enum.Font.SourceSans, TextSize=6, TextColor3=Color3.fromRGB(150, 200, 150), TextXAlignment=Enum.TextXAlignment.Center, Parent=spawnFrame})
Instance.new("UICorner", fakeHistoryStatusLbl).CornerRadius = UDim.new(0, 3)

local fakeHistoryBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(180, 100, 20), BackgroundTransparency=0.1, Text="Spawn Fake Trade History", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 220, 140), Parent=spawnFrame})
Instance.new("UICorner", fakeHistoryBtn).CornerRadius = UDim.new(0, 3)
local fakeHistoryStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 180, 60), Thickness=0.7, Transparency=0.3, Parent=fakeHistoryBtn})

local _fhAmvggCache = nil
local function _fhHttpGet(url)
    local ok, res = pcall(function()
        return request({ Url = url, Method = "GET", Headers = { ["RSC"] = "1" } })
    end)
    if ok and res and res.Body then return res.Body end
    local ok2, body = pcall(function() return HttpGet(url) end)
    if ok2 and body then return body end
    local ok3, body3 = pcall(function()
        return game:GetService("HttpService"):GetAsync(url, true)
    end)
    if ok3 and body3 then return body3 end
    return nil
end

local function _fhFetchAmvgg(cb)
    if _fhAmvggCache then cb(_fhAmvggCache) return end
    task.spawn(function()
        local ok, text = pcall(_fhHttpGet, "https://amvgg.com/values/pets?_rsc=19zvn")
        if not ok or type(text) ~= "string" then cb(nil) return end
        local ps = text:find('"pets":%[{')
        if not ps then cb(nil) return end
        local raw = _G._decodeJsonArrayAt(text, ps)
        if not raw then cb(nil) return end
        local cache = {}
        for _, p in ipairs(raw) do
            if p.name then
                local function n(v) return tonumber(v) or 0 end
                cache[p.name:lower()] = n(p.megaValue)
            end
        end
        _fhAmvggCache = cache
        cb(cache)
    end)
end

local function _fhGetMfrValue(cache, petName)
    if not cache then return 0 end
    local v = cache[petName:lower()] or 0
    if v == 0 then
        for k, val in pairs(cache) do
            if k:find(petName:lower(), 1, true) then v = val break end
        end
    end
    return v
end

local function _fhMakeItem(petName, props)
    local kind = nil
    pcall(function()
        for id, data in pairs(InventoryDB.pets or {}) do
            if data.name and data.name:lower() == petName:lower() then kind = id break end
        end
    end)
    if not kind then return nil end
    return {
        category   = "pets",
        kind       = kind,
        id         = kind,
        unique     = HttpService:GenerateGUID(false),
        properties = props or { neon=false, mega_neon=false, flyable=false, rideable=false, age=1 },
    }
end

local function _fhMakeMFRItem(petName)
    return _fhMakeItem(petName, { neon=false, mega_neon=true, flyable=true, rideable=true, age=1 })
end

local function _fhInjectRecord(senderUserId, senderName, senderItems, recipientUserId, recipientName, recipientItems, timestamp)
    local record = {
        trade_id          = "MOCK_FH_" .. HttpService:GenerateGUID(false),
        timestamp         = timestamp or os.time(),
        sender_user_id    = senderUserId,
        sender_name       = senderName,
        recipient_user_id = recipientUserId,
        recipient_name    = recipientName,
        sender_items      = senderItems   or {},
        recipient_items   = recipientItems or {},
        reported          = false,
        reverted          = nil,
    }
    table.insert(_mockTradeHistory, 1, record)
    if TradeHistoryApp then
        TradeHistoryApp.cached_trade_history = nil
    end
    return record
end

local _fhPartnerNames = {
    "CammyxBoba", "RoplexYoutube", "NotLeah", "TheMeganPlays", "Kellyvault",
    "Rainbowriley321", "hweartsouls", "h3llsang3lx", "Hugso09", "ruthjavxn",
    "bubblesxwrldd", "Barborich2", "Bunzvii", "Sparklingorangelol", "Tr3ndzyy",
    "Cqvrleo", "Themeganplays", "Pradasvogue", "Lionheart_xo", "dwsiredsouls",
    "Xcallmeholly", "Agusmareborn", "Hugeinvestor", "Underthechemtrailss",
}
local _fhUsedNames = {}
local function _fhPickName()
    if #_fhUsedNames >= #_fhPartnerNames then _fhUsedNames = {} end
    local available = {}
    for _, n in ipairs(_fhPartnerNames) do
        local used = false
        for _, u in ipairs(_fhUsedNames) do if u == n then used = true break end end
        if not used then table.insert(available, n) end
    end
    local pick = available[math.random(1, #available)]
    table.insert(_fhUsedNames, pick)
    return pick
end

local _fhRunning = false

_G._setupLiveFakeHistoryBtn = fakeHistoryBtn
local function _runFakeHistory()
    if _fhRunning then return end
    _fhRunning = true
    fakeHistoryBtn.Text             = "Fetching amvgg..."
    fakeHistoryBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    fakeHistoryStatusLbl.Text       = "⏳ Loading amvgg values..."

    _fhFetchAmvgg(function(cache)
        if not cache then
            fakeHistoryStatusLbl.Text       = "❌ amvgg fetch failed"
            fakeHistoryBtn.Text             = "Spawn Fake Trade History"
            fakeHistoryBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 20)
            _fhRunning = false
            return
        end

        local validPets = {}
        for _, petName in ipairs(HIGH_TIER_PETS) do
            if _fhGetMfrValue(cache, petName) >= 0.1 then
                table.insert(validPets, petName)
            end
        end

        if #validPets == 0 then
            fakeHistoryStatusLbl.Text       = "❌ No pets passed 0.1gg threshold"
            fakeHistoryBtn.Text             = "Spawn Fake Trade History"
            fakeHistoryBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 20)
            _fhRunning = false
            return
        end

        local myUserId   = Players.LocalPlayer.UserId
        local myName     = Players.LocalPlayer.Name
        local tradeCount = math.random(8, 14)

        fakeHistoryBtn.Text       = "Generating " .. tradeCount .. " trades..."
        fakeHistoryStatusLbl.Text = "✅ " .. #validPets .. " valid pets | building " .. tradeCount .. " trades"

        task.spawn(function()
            local now     = os.time()
            local gapSecs = math.random(300, 600)

            for i = 1, tradeCount do
                local partnerName = _fhPickName()
                local partnerId   = math.random(100000000, 999999999)
                local pet1Name    = validPets[math.random(1, #validPets)]
                local pet1Props   = { neon=false, mega_neon=false, flyable=true, rideable=true, age=1 }
                local pet1Item    = _fhMakeItem(pet1Name, pet1Props)
                if not pet1Item then task.wait(0.05) continue end

                -- History displays oldest at bottom, newest at top
                -- So: top = you giving back, below = them giving to you
                local tsB = now - (i - 1) * gapSecs - math.random(0, 60)
                local tsA = tsB + math.random(30, 180)

                -- TRADE B (older): partner gives 1 high-tier to me first
                _fhInjectRecord(
                    partnerId, partnerName,
                    { pet1Item },
                    myUserId, myName,
                    {},
                    tsB
                )

                task.wait(0.04)

                -- TRADE A (newer): I give back same pet + MFR extras
                local myGiveItems = {}
                local returnItem = _fhMakeItem(pet1Name, pet1Props)
                if returnItem then table.insert(myGiveItems, returnItem) end
                for _ = 1, math.random(3, 6) do
                    local mfrItem = _fhMakeMFRItem(validPets[math.random(1, #validPets)])
                    if mfrItem then table.insert(myGiveItems, mfrItem) end
                end

                _fhInjectRecord(
                    myUserId, myName,
                    myGiveItems,
                    partnerId, partnerName,
                    {},
                    tsA
                )

                task.wait(0.04)
            end

            if TradeHistoryApp and UIManager.is_visible("TradeHistoryApp") then
                pcall(function() TradeHistoryApp:_refresh() end)
            end

            fakeHistoryStatusLbl.Text       = "✅ Injected " .. (tradeCount * 2) .. " trade records!"
            fakeHistoryBtn.Text             = "Spawn Fake Trade History"
            fakeHistoryBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 20)
            _fhRunning = false
        end)
    end)
end
fakeHistoryBtn.MouseButton1Click:Connect(_runFakeHistory)
_G._setupLiveRunFakeHistory = _runFakeHistory

end -- fake trade history do

do

-- Get profile constants via CloudValues (PlayerProfileHelper.get_cloud_value reads from "player_profiles" namespace)
local _WIDGETS_PER_PAGE     = 8
local _MAX_PAGES            = 10
local _MAX_COLLECTION_ITEMS = 80
pcall(function()
    local cv = require(game.ReplicatedStorage.ClientModules.CloudValues)
    _WIDGETS_PER_PAGE     = cv:getValue("player_profiles", "widgets_per_page")     or _WIDGETS_PER_PAGE
    _MAX_PAGES            = cv:getValue("player_profiles", "max_pages")            or _MAX_PAGES
    _MAX_COLLECTION_ITEMS = cv:getValue("player_profiles", "max_collection_items") or _MAX_COLLECTION_ITEMS
end)

local _fpRC = Fsys.load("RouterClient")

local _fpIsEnabled  = false  -- OPTIONAL: your own profile's Have sections are only faked after you press "Spawn Fake Profile" (or enable the Misc toggle for Setup Live)
local _fpHookedApps = {}

local _fpUniqueCounter = 0
local function _fpGenerateId()
    _fpUniqueCounter = _fpUniqueCounter + 1
    return string.format("fp_col_%d_%d", tick() * 1000, _fpUniqueCounter)
end

-- selectedFlags (defaults match uploaded script)
local _fpSelectedFlags = {
    mega_neon = true,
    neon      = false,
    flyable   = true,
    rideable  = true,
}

local _fpActivePetKind = "bat_dragon"  -- default

local function _fpGetRealUniques()
    local uniques = {}
    pcall(function()
        local inv = ClientData.get("inventory") or {}
        for uid, item in pairs(inv.pets or {}) do
            if item.kind == _fpActivePetKind then
                table.insert(uniques, { unique = uid, properties = item.properties or {} })
            end
        end
    end)
    return uniques
end

local function _fpBuildProperties()
    local props = {}
    if _fpSelectedFlags.mega_neon then props.mega_neon = true end
    if _fpSelectedFlags.neon and not _fpSelectedFlags.mega_neon then props.neon = true end
    if _fpSelectedFlags.flyable  then props.flyable  = true end
    if _fpSelectedFlags.rideable then props.rideable = true end
    return props
end

-- Exact same as uploaded script: widget_kind = "collection", uses real uniques where available
local function _fpBuildSlotData()
    local realPets = _fpGetRealUniques()
    local props    = _fpBuildProperties()
    if _G._isEggKind and _G._isEggKind(_fpActivePetKind) then props = {} end
    local items    = {}
    for i = 1, _MAX_COLLECTION_ITEMS do
        if i <= #realPets then
            items[i] = { kind       = _fpActivePetKind, category   = "pets", unique     = realPets[i].unique, properties = props, }
        else
            items[i] = { kind       = _fpActivePetKind, category   = "pets", unique     = _fpGenerateId(), properties = props, }
        end
    end
    return {
        widget_kind = "collection",
        expanded    = true,
        widget_data = { title = "", items = items },
    }
end

-- hookClientData: exact copy from uploaded script
local function _fpHookClientData()
    if ClientData._fp_cd_hooked then return end
    ClientData._fp_cd_hooked = true
    local originalGet = ClientData.get_server
    ClientData.get_server = function(player, key, ...)
        local result = originalGet(player, key, ...)
        if key == "player_profile" and result then
            if player == Players.LocalPlayer and _fpIsEnabled then
                result.pages = result.pages or {}
                for page = 1, _MAX_PAGES do
                    local pageEntry = nil
                    for _, entry in ipairs(result.pages) do
                        if entry.page_index == page then pageEntry = entry; break end
                    end
                    if not pageEntry then
                        pageEntry = { page_index = page, widgets = {}, stickers = {} }
                        table.insert(result.pages, pageEntry)
                    end
                    pageEntry.widgets = {}
                    for slot = 1, _WIDGETS_PER_PAGE do
                        table.insert(pageEntry.widgets, { slot = slot, data = _fpBuildSlotData() })
                    end
                end
            else
                -- Ensure stickers field exists on every page for any other player
                if result.pages then
                    for _, page in ipairs(result.pages) do
                        if page.stickers == nil then
                            page.stickers = {}
                        end
                    end
                end
            end
        end
        return result
    end
end

-- hookFetchProfile: intercepts PlayerProfileAPI/FetchProfile to inject fake widgets
-- Response shape from PlayerProfile module: {pages=[{page_index, widgets=[{slot,data}], stickers={}}], properties={}}

-- Patch PlayerProfile methods lazily on first profile open so the module
-- is guaranteed to be fully loaded and cached before we touch it.
-- PlayerProfile patched at top of script (see patch block near TradeApp load)
-- _patchPlayerProfile kept as no-op for compatibility
do local _ppPatched = true
end do local function _patchPlayerProfile() end


-- =====================================================================
-- RANDOM OFFLINE PROFILE GENERATOR
-- Generates a convincing fake profile for offline non-friend players
-- =====================================================================
end local _randProfileCache = {}  -- userId -> generated profile, consistent per session

local RAND_ABOUT_TITLES = {
    "about me!!",
    "elve values",
    "read b4 trading",
    "hi!!",
    "living doll . . .",
    "my dollhouse",
    "my poll diary",
    "house trader",
    "fair trades only",
    "collector",
    "trader info",
    "about me",
    "", "", "", "",
}
local RAND_ABOUT_BODIES = {
    [[i dont offer unless lf
fair trades > ovps
-> elve
-> amvgg]],
    [[:: not for trade
:: dreamy pets
:: looking for]],
    [[everything here is nft
pets pw . .
:: locket
:: looking for]],
    [[reminder: everything here is nft
fair trades only
pets pw . .]],
    [[i dont offer!!
nft means nft
amvgg vals only]],
    [[welcome to my profile
pw :: nft
i dont offer!!]],
    [[reminder!
everything here is nft
pets pw . .]],
    [[looking for:
marshmallow
valentine
sprinkles]],
    [[the only values i follow are in my head
nft
ft]],
    [[my bakery!
:: best pets
:: toppings
:: in the oven]],
    [[selling fits!
jellycats
m/n glowsticks!]],
    [[i dont offer unless lf
house trader
check wishlist!]],
    [[my dollhouse
pets pw . .
:: locket]],
    [[looking for
read ^^
:: best pets
:: about me]],
    [[living doll . . .
my dollhouse
pets pw]],
    [[huge collector
trading daily
check my inv!!]],
    [[shadow + bat = dream combo
all legit no dupes]],
    [[mostly online weekends
hit me with offers!]],
    "", "", "", "",
}
local RAND_WISHLIST_TITLES = {
    ":: looking for",
    ":: dreamy pets",
    ":: lf:",
    "looking for:",
    ":: wishlist!!",
    "dream pets",
    "lf:",
    ":: need these!!",
    "want list",
    "", "",
}
local RAND_COLLECTION_TITLES = {
    ":: baked",
    ":: recents!!",
    ":: for trade!",
    ":: best pets!!",
    "pets pw . .",
    ":: spookies",
    ":: glowsticks",
    ":: candies",
    ":: megas (more)",
    ":: neons (more)",
    ":: my loves (nft)",
    "vanity (nft)",
    ":: profile key!!",
    "my collection",
    "items",
    ":: items",
    "my items (nft)",
    "", "",
}

-- Decorative symbols / fancy fonts for generated profiles (unicode "fonts" + symbols).
local RAND_DECOR_L = { "★ ", "☆ ", "✦ ", "✧ ", "♡ ", "♥ ", "❀ ", "✿ ", "☁ ", "⋆ ", "˚ʚ ", "୨୧ ", "₊˚ ", "𓆩♡𓆪 ", "☾ ", "✩ ", "❥ ", "» ", "• ", ":: " }
local RAND_DECOR_R = { " ★", " ☆", " ✦", " ✧", " ♡", " ♥", " ❀", " ✿", " ☁", " ⋆", " ɞ˚", " ୨୧", " ₊˚", " ☾", " ✩", " ❥", " «", " • •", " !!", "" }
local _FANCY = {
    -- small caps
    function(str) local m = { a="ᴀ",b="ʙ",c="ᴄ",d="ᴅ",e="ᴇ",f="ꜰ",g="ɢ",h="ʜ",i="ɪ",j="ᴊ",k="ᴋ",l="ʟ",m="ᴍ",n="ɴ",o="ᴏ",p="ᴘ",q="ǫ",r="ʀ",s="ꜱ",t="ᴛ",u="ᴜ",v="ᴠ",w="ᴡ",x="x",y="ʏ",z="ᴢ" }
        return (str:lower():gsub("%a", function(c) return m[c] end)) end,
    -- bold
    function(str) return (str:gsub("%a", function(c)
        local b = c:byte()
        if b >= 65 and b <= 90 then return utf8.char(0x1D400 + b - 65) end
        return utf8.char(0x1D41A + b - 97) end)) end,
    -- plain lowercase
    function(str) return str:lower() end,
    -- plain
    function(str) return str end,
}
local function _decorTitle(str)
    if str == nil or str == "" then return str end
    local fn = _FANCY[math.random(1, #_FANCY)]
    local ok, out = pcall(fn, str)
    if ok and out then str = out end
    if math.random() < 0.8 then
        str = RAND_DECOR_L[math.random(1, #RAND_DECOR_L)] .. str .. RAND_DECOR_R[math.random(1, #RAND_DECOR_R)]
    end
    return str
end
-- section titles pick a themed look; blank titles are replaced
for i, str in ipairs(RAND_WISHLIST_TITLES) do
    if str == "" then RAND_WISHLIST_TITLES[i] = "dream pets" end
end
for i, str in ipairs(RAND_COLLECTION_TITLES) do
    if str == "" then RAND_COLLECTION_TITLES[i] = "best pets" end
end
for _, t in ipairs({ "have", "best pets", "my best pets", "top pets", "showcase", "my megas", "trade board", "inventory" }) do
    table.insert(RAND_COLLECTION_TITLES, t)
end
for _, t in ipairs({ "dream pets", "my dream pets", "wishlist", "want", "looking for", "dream list", "goals" }) do
    table.insert(RAND_WISHLIST_TITLES, t)
end

local RAND_COLLECTION_POOL = {}
local RAND_WISHLIST_POOL   = {}
-- Real InventoryDB kind keys (from check_pet_kinds.lua scan)
do local _KIND_REAL = {
    ["bat_dragon"]                      = "bat_dragon",
    ["shadow_dragon"]                   = "shadow_dragon",
    ["giraffe"]                         = "giraffe",
    ["frost_dragon"]                    = "frost_dragon",
    ["owl"]                             = "owl",
    ["parrot"]                          = "parrot",
    ["crow"]                            = "crow",
    ["balloon_unicorn"]                 = "summerfest_2024_balloon_unicorn",
    ["african_wild_dog"]                = "ugc_refresh_2023_african_wild_dog",
    ["giant_panda"]                     = "pet_recycler_2025_giant_panda",
    ["haetae"]                          = "lunar_2025_haetae",
    ["cryptid"]                         = "halloween_2025_cryptid",
    ["evil_unicorn"]                    = "evil_unicorn",
    ["blazing_lion"]                    = "lures_2023_blazing_lion",
    ["hedgehog"]                        = "elf_hedgehog",
    ["orchid_butterfly"]                = "butterfly_2025_orchid_butterfly",
    ["diamond_butterfly"]               = "sanctuary_2022_diamond_premium_butterfly",
    ["dalmatian"]                       = "santa_dog",
    ["arctic_reindeer"]                 = "arctic_reindeer",
    ["jekyll_hydra"]                    = "halloween_2024_jekyll_hydra",
    ["mini_pig"]                        = "summerfest_2024_minipig",
    ["hot_doggo"]                       = "summerfest_2023_hotdog_dog",
    ["pelican"]                         = "random_pets_sept_2023_pelican",
    ["cow"]                             = "cow",
    ["mermicorn"]                       = "summerfest_2025_mermicorn",
    ["strawberry_shortcake_bat_dragon"] = "winter_2022_strawberry_shortcake_bat_dragon",
    ["cabbit"]                          = "spring_2025_cabbit",
    ["chocolate_chip_bat_dragon"]       = "winter_2023_chocolate_chip_bat_dragon",
    ["turtle"]                          = "turtle",
    ["peppermint_penguin"]              = "winter_2023_peppermint_penguin",
    ["goose"]                           = "springfest_2023_goose",
    ["monkey_king"]                     = "monkey_king",
    ["undead_jousting_horse"]           = "halloween_2022_undead_jousting_horse",
    ["flamingo"]                        = "flamingo",
    ["kangaroo"]                        = "kangaroo",
}

for _, entry in ipairs(HIGH_TIER_PETS_TIERED) do
    local simpleKind = entry.name:lower():gsub(" ", "_"):gsub("[^%w_]", "")
    local realKind   = _KIND_REAL[simpleKind] or simpleKind
    local maxLevel   = entry.max
    local flags
    if maxLevel == "default" then
        flags = { {F=true,R=true}, {F=true,R=false}, {F=false,R=true}, {F=false,R=false} }
    elseif maxLevel == "neon" then
        flags = {
            {N=true,F=true,R=true}, {N=true,F=true,R=true},
            {N=true,F=false,R=false},
            {F=true,R=true}, {F=false,R=false},
        }
    else -- "any"
        flags = {
            {M=true,F=true,R=true}, {M=true,F=true,R=true},
            {N=true,F=true,R=true}, {N=true,F=true,R=true},
            {N=true,F=false,R=false},
            {F=true,R=true}, {F=false,R=false},
        }
    end
    table.insert(RAND_COLLECTION_POOL, { kind = realKind, flags = flags })
    table.insert(RAND_WISHLIST_POOL,   { kind = realKind, flags = flags })
end

end local function _randPick(t) return t[math.random(1, #t)] end
local function _randBool(chance) return math.random() < (chance or 0.5) end

local function _randPetItem(pool)
    pool = pool or RAND_COLLECTION_POOL
    local entry = pool[math.random(1, #pool)]
    local flags = _randPick(entry.flags)
    local props = {}
    if flags.M then props.mega_neon = true
    elseif flags.N then props.neon = true end
    if flags.F then props.flyable = true end
    if flags.R then props.rideable = true end
    props.age = math.random(1, 6)
    return { kind       = entry.kind, category   = "pets", unique     = string.format("rp_%d_%d", math.random(100000,999999), math.random(100,999)), properties = props, }
end

local function _buildRandAboutMe()
    -- 20% chance of no title, 30% chance of no body (realistic — lots of blank profiles)
    return {
        widget_kind = "about_me",
        expanded    = false,
        widget_data = { title = _decorTitle(_randBool(0.9) and _randPick(RAND_ABOUT_TITLES) or "about me"), body  = _randBool(0.85) and _randPick(RAND_ABOUT_BODIES) or "", },
    }
end

local function _buildRandWishlist()
    local items = {}
    local count = math.random(3, 8)
    local usedKinds = {}
    -- Dream pets are BIG high value pets, always FR / NFR / MFR (never junk, never eggs)
    local function props_for(kind)
        local r = math.random(1, 100)
        local f
        if r <= 25 then f = { F = true, R = true }                  -- FR
        elseif r <= 65 then f = { N = true, F = true, R = true }    -- NFR
        else f = { M = true, F = true, R = true } end               -- MFR
        if _G._fakeClampFlags then f = _G._fakeClampFlags(kind, f) end   -- tiered list max level (Bat Dragon = FR only, etc.)
        local props = { flyable = true, rideable = true }
        if f.N then props.neon = true end
        if f.M then props.mega_neon = true end
        return props
    end
    local core, rest = {}, {}
    if _G._fakeDreamKinds then core, rest = _G._fakeDreamKinds() end
    if #core == 0 and #rest == 0 then
        for _, e in ipairs(RAND_WISHLIST_POOL) do core[#core + 1] = e.kind end
    end
    local function shuf(t)
        for i = #t, 2, -1 do local j = math.random(1, i); t[i], t[j] = t[j], t[i] end
    end
    shuf(core); shuf(rest)
    local order = {}
    -- ~75% of the list comes from the core big pets, the rest from other high tiers / exotics
    local ci, ri = 1, 1
    while ci <= #core or ri <= #rest do
        if ci <= #core and (math.random() < 0.75 or ri > #rest) then order[#order + 1] = core[ci]; ci = ci + 1
        elseif ri <= #rest then order[#order + 1] = rest[ri]; ri = ri + 1
        else order[#order + 1] = core[ci]; ci = ci + 1 end
    end
    for _, kind in ipairs(order) do
        if #items >= count then break end
        if not usedKinds[kind] and not (_G._isEggKind and _G._isEggKind(kind)) then
            usedKinds[kind] = true
            table.insert(items, { kind = kind, category = "pets", properties = props_for(kind) })
        end
    end
    return {
        widget_kind = "wishlist",
        expanded    = _randBool(0.85),
        widget_data = { title = _decorTitle(_randPick(RAND_WISHLIST_TITLES)), items = items },
    }
end

-- Converts one generated-backpack pet into a profile collection item
_G._bpToProfileItem = function(pet)
    if _G._isEggKind and _G._isEggKind(pet.kind) then   -- eggs: no properties whatsoever
        return { kind = pet.kind, category = "pets",
                 unique = string.format("rp_%d_%d", math.random(100000,999999), math.random(100,999)),
                 properties = {} }
    end
    local pr, props = pet.properties or {}, {}
    if pr.mega_neon then props.mega_neon = true elseif pr.neon then props.neon = true end
    if pr.flyable   then props.flyable   = true end
    if pr.rideable  then props.rideable  = true end
    props.age = pr.age or math.random(1, 6)
    return { kind = pet.kind, category = "pets",
             unique = string.format("rp_%d_%d", math.random(100000,999999), math.random(100,999)),
             properties = props }
end

local function _buildRandCollection()
    -- Items are filled in afterwards from that player's generated backpack (see _fillCollectionsFromBackpack).
    -- If the generator is unavailable, fall back to the old small random pool.
    local items = {}
    if not (_G._fakeBackpackFor) then
        local count = math.random(5, math.min(20, _MAX_COLLECTION_ITEMS))
        for _ = 1, count do
            table.insert(items, _randPetItem(RAND_COLLECTION_POOL))
        end
    end
    return {
        widget_kind = "collection",
        expanded    = _randBool(0.75),
        widget_data = { title = _decorTitle(_randPick(RAND_COLLECTION_TITLES)), items = items },
    }
end

-- Page layout templates — gives each user a distinct feel
local PAGE_LAYOUTS = {
    -- layout 1: about + collection + wishlist
    function()
        return { _buildRandAboutMe(), _buildRandCollection(), _buildRandWishlist(), }
    end,
    -- layout 2: have + dream (no-nonsense trader)
    function()
        return { _buildRandCollection(), _buildRandWishlist() }
    end,
    -- layout 3: wishlist first then collection
    function()
        return { _buildRandWishlist(), _buildRandCollection(), }
    end,
    -- layout 4: about + dream + have
    function()
        return { _buildRandAboutMe(), _buildRandWishlist(), _buildRandCollection(), }
    end,
    -- layout 5: about + have + dream
    function()
        return { _buildRandAboutMe(), _buildRandCollection(), _buildRandWishlist() }
    end,
    -- layout 6: two collections (big collector energy)
    function()
        return { _buildRandCollection(), _buildRandCollection(), }
    end,
    -- layout 7: full house
    function()
        return { _buildRandAboutMe(), _buildRandCollection(), _buildRandWishlist(), _buildRandCollection(), }
    end,
}

local function _buildRandPage(pageNum, widgetList)
    local widgets = {}
    for i, data in ipairs(widgetList) do
        if i > _WIDGETS_PER_PAGE then break end
        table.insert(widgets, { slot = i, data = data })
    end
    return { page_index = pageNum, widgets = widgets, stickers = {} }
end

-- Fill every collection ("have") widget with the player's BEST pets only: high tiers / exotics first,
-- mega > neon > FR, no eggs, no plain filler. Sections are filled to a decent size.
_G._fillColsFromBackpack = function(pages, uid)
    if not _G._fakeBackpackFor then return end
    local all = _G._fakeBackpackFor(uid)
    if type(all) ~= "table" or #all == 0 then return end
    local core, rest = {}, {}
    if _G._fakeDreamKinds then
        local c, r = _G._fakeDreamKinds()
        for i, k in ipairs(c) do core[k] = true end
        for i, k in ipairs(r) do rest[k] = true end
    end
    local function score(pet)
        local pr, sc = pet.properties or {}, 0
        if core[pet.kind] then sc = sc + 140 elseif rest[pet.kind] then sc = sc + 100 end
        if pr.mega_neon then sc = sc + 70 elseif pr.neon then sc = sc + 35 end
        if pr.flyable then sc = sc + 6 end
        if pr.rideable then sc = sc + 6 end
        if pr.age == 6 then sc = sc + 2 end
        return sc + math.random()   -- random tie-break
    end
    local scored = {}
    for _, pet in ipairs(all) do
        if not (_G._isEggKind and _G._isEggKind(pet.kind)) then
            local sc = score(pet)
            if sc >= 20 then scored[#scored + 1] = { pet = pet, sc = sc } end   -- skip worthless filler
        end
    end
    if #scored == 0 then   -- nothing valuable at all (e.g. brand new player): show their top few anyway
        for _, pet in ipairs(all) do
            if not (_G._isEggKind and _G._isEggKind(pet.kind)) then scored[#scored + 1] = { pet = pet, sc = score(pet) } end
        end
    end
    table.sort(scored, function(x, y) return x.sc > y.sc end)
    local cols = {}
    for _, pg in ipairs(pages) do
        for _, w in ipairs(pg.widgets) do
            if w.data and w.data.widget_kind == "collection" then cols[#cols + 1] = w.data end
        end
    end
    if #cols == 0 then return end
    local keep = math.min(#scored, math.random(8, 16) * #cols, _MAX_COLLECTION_ITEMS * #cols)
    local per = math.ceil(keep / #cols)
    for ci, col in ipairs(cols) do
        col.widget_data.items = {}
        for i = (ci - 1) * per + 1, math.min(ci * per, keep) do
            table.insert(col.widget_data.items, _G._bpToProfileItem(scored[i].pet))
        end
    end
end

local function _buildRandomOfflineProfile(uid)
    -- Pick a random layout template
    local layout = _randPick(PAGE_LAYOUTS)()
    -- 25% chance of a second page with extra content
    local pages = { _buildRandPage(1, layout) }
    if _randBool(0.25) then
        local page2layout = _randPick(PAGE_LAYOUTS)()
        table.insert(pages, _buildRandPage(2, page2layout))
    end
    -- every profile gets a want (wishlist) section
    local hasWish = false
    for _, pg in ipairs(pages) do
        for _, w in ipairs(pg.widgets) do
            if w.data and w.data.widget_kind == "wishlist" then hasWish = true end
        end
    end
    if not hasWish then
        local pg = pages[#pages]
        if #pg.widgets < _WIDGETS_PER_PAGE then
            table.insert(pg.widgets, { slot = #pg.widgets + 1, data = _buildRandWishlist() })
        else
            pg.widgets[#pg.widgets].data = _buildRandWishlist()
        end
    end
    _G._fillColsFromBackpack(pages, uid)
    return { properties = {}, pages = pages }
end

-- eggs never carry properties: strip them from every item of a profile table
local function _eggSweepProfile(prof)
    if type(prof) ~= "table" then return prof end
    for _, pg in ipairs(prof.pages or {}) do
        for _, w in ipairs(pg.widgets or {}) do
            local wd = w.data and w.data.widget_data
            for _, it in ipairs((wd and wd.items) or {}) do
                if it.kind and _G._isEggKind and _G._isEggKind(it.kind) then it.properties = {} end
            end
        end
    end
    return prof
end
_G._eggSweepProfile = _eggSweepProfile

local function _getOrGenRandomProfile(userId)
    if not _randProfileCache[userId] then
        -- Seed with userId XOR'd with a salt so different userIds
        -- get genuinely different sequences (not just offset versions)
        local salt = 0x5A3C1F7B
        local seed = bit32 and bit32.bxor(userId % 2^31, salt)
                     or ((userId % 100000) * 31337 + salt) % 2^31
        math.randomseed(seed)
        _randProfileCache[userId] = _eggSweepProfile(_buildRandomOfflineProfile(userId))
        math.randomseed(tick() * 1000 + math.random())
    end
    return _randProfileCache[userId]
end

-- =====================================================================
-- FetchProfile hook via hookmetamethod
-- RemoteFunction instances are Roblox Instances — you cannot assign
-- properties or overwrite methods on them directly. The old approach
-- (`fetchRemote.InvokeServer = function...`) silently threw inside pcall
-- and never installed. This version uses hookmetamethod(__namecall).
-- =====================================================================
local _fpFetchRemote = nil
pcall(function() _fpFetchRemote = _fpRC.get("PlayerProfileAPI/FetchProfile") end)

local _fpNamecallInstalled = false
local function _fpInstallNamecallHook()
    if _fpNamecallInstalled then return end
    if type(hookmetamethod) ~= "function"
        or type(getnamecallmethod) ~= "function"
        or type(newcclosure) ~= "function" then
        warn("[FakeProfile] executor lacks hookmetamethod/getnamecallmethod/newcclosure — cannot hook FetchProfile")
        return
    end
    if not _fpFetchRemote then
        pcall(function() _fpFetchRemote = _fpRC.get("PlayerProfileAPI/FetchProfile") end)
    end
    if not _fpFetchRemote then
        warn("[FakeProfile] FetchProfile remote not found")
        return
    end
    _fpNamecallInstalled = true
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if self == _fpFetchRemote and getnamecallmethod() == "InvokeServer" then
            -- One-shot bypass: the Rich leaderboard sets this to read the REAL profile
            -- (no fake/random injection) so its AMVGG values are accurate.
            if _G._rlbRealFetch then _G._rlbRealFetch = false; return oldNamecall(self, ...) end
            local userId = (...)
            local lp = Players.LocalPlayer
            -- Own profile + fake mode on: inject full fake collection
            if userId == lp.UserId and _fpIsEnabled then
                local ok, real = pcall(oldNamecall, self, ...)
                local result = (ok and type(real) == "table") and real
                    or { properties = {}, pages = {} }
                result.pages = {}
                for page = 1, _MAX_PAGES do
                    local widgets = {}
                    for slot = 1, _WIDGETS_PER_PAGE do
                        widgets[slot] = { slot = slot, data = _fpBuildSlotData() }
                    end
                    result.pages[page] = {
                        page_index = page,
                        widgets    = widgets,
                        stickers   = {},
                    }
                end
                return result
            end
            -- Other player: try real fetch; on failure or empty content
            -- substitute a generated random profile
            if userId ~= lp.UserId then
                local ok, real = pcall(oldNamecall, self, ...)
                local hasWidgets = false
                if ok and type(real) == "table" and real.pages then
                    for _, page in ipairs(real.pages) do
                        if page.widgets and #page.widgets > 0 then
                            hasWidgets = true
                            break
                        end
                    end
                end
                -- REAL players always keep their real profile. A generated one is only used when
                --   * the lookup failed / came back empty AND the player is not in this server, or
                --   * it is the mock trade partner (so their profile matches their generated items).
                local inServer = Players:GetPlayerByUserId(userId) ~= nil
                local isMockPartnerId = _G._mockState and _G._mockState.active
                    and (userId == CONFIG.PARTNER_USER_ID)
                if not ok or type(real) ~= "table" or not hasWidgets then
                    if (not inServer) or isMockPartnerId then
                        return _getOrGenRandomProfile(userId)
                    end
                    if ok and type(real) == "table" then
                        for _, page in ipairs(real.pages or {}) do
                            if page.stickers == nil then page.stickers = {} end
                        end
                        return real
                    end
                    return oldNamecall(self, ...)
                end
                -- Real data — ensure stickers field exists per page
                for _, page in ipairs(real.pages) do
                    if page.stickers == nil then page.stickers = {} end
                end
                return real
            end
        end
        return oldNamecall(self, ...)
    end))
end

-- Also keep _fpHookFetchProfile as a no-op for compatibility
local function _fpHookFetchProfile() end

-- Install at startup
task.defer(_fpInstallNamecallHook)


-- hookProfileApp: matches current PlayerProfile/PlayerProfileApp structure exactly
local function _fpHookProfileApp(app)
    if not app or _fpHookedApps[app] then return end
    _fpHookedApps[app] = true

    -- Hook on_load_complete — called by PlayerProfile._refresh_profile_data:finally()
    -- At this point profile_data is fully populated and app.player_profile is set
    local orig_on_load = app.on_load_complete
    app.on_load_complete = function(self, ...)
        local result = orig_on_load(self, ...)
        pcall(function()
            if not _fpIsEnabled then return end
            local pp = self.player_profile
            if not pp or not pp.is_my_profile then return end
            -- Inject fake slot data directly into profile_data.pages
            pp.profile_data = pp.profile_data or {}
            pp.profile_data.pages = pp.profile_data.pages or {}
            for page = 1, _MAX_PAGES do
                pp.profile_data.pages[page] = {}
                for slot = 1, _WIDGETS_PER_PAGE do
                    pp.profile_data.pages[page][slot] = _fpBuildSlotData()
                end
            end
            -- Re-render current page slots so changes show immediately
            local curPage = self:get_page()
            for slot = 1, _WIDGETS_PER_PAGE do
                pcall(function() pp:render_slot(curPage, slot) end)
            end
        end)
        return result
    end

    -- Hook open_page to re-inject fake data whenever page changes
    local orig_open_page = app.open_page
    app.open_page = function(self, pageNumber, ...)
        pcall(function()
            if not _fpIsEnabled then return end
            local pp = self.player_profile
            if not pp or not pp.is_my_profile then return end
            pp.profile_data = pp.profile_data or {}
            pp.profile_data.pages = pp.profile_data.pages or {}
            pp.profile_data.pages[pageNumber] = {}
            for slot = 1, _WIDGETS_PER_PAGE do
                pp.profile_data.pages[pageNumber][slot] = _fpBuildSlotData()
            end
        end)
        return orig_open_page(self, pageNumber, ...)
    end
end

-- startWatcher: exact copy from uploaded script
task.spawn(function()
    while task.wait(1) do
        pcall(function()
            if not _fpIsEnabled then return end
            local app = UIManager.apps.PlayerProfileApp
            if app then _fpHookProfileApp(app) end
        end)
    end
end)

-- fireAllSaves: exact copy from uploaded script using raw _fpRC
do local function _fpFireAllSaves()
    local saveRemote = _fpRC.get("PlayerProfileAPI/SaveProfileSlot")
    for page = 1, _MAX_PAGES do
        for slot = 1, _WIDGETS_PER_PAGE do
            pcall(function() saveRemote:FireServer(page, slot, _fpBuildSlotData()) end)
            task.wait()
        end
    end
end

-- Spawner tab UI (unchanged — same buttons, same pet picker, same flags)
end local fakeProfileStatusLbl = mk("TextLabel", {Size=UDim2.new(1,0,0,9), BackgroundTransparency=1, Text="", Font=Enum.Font.SourceSans, TextSize=6, TextColor3=Color3.fromRGB(150,200,150), TextXAlignment=Enum.TextXAlignment.Center, Parent=spawnFrame})

local fakeProfileBtn = mk("TextButton", {Size=UDim2.new(1,0,0,13), BackgroundColor3=Color3.fromRGB(30,100,160), BackgroundTransparency=0.1, Text="Spawn Fake Profile", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(180,220,255), Parent=spawnFrame})
Instance.new("UICorner", fakeProfileBtn).CornerRadius = UDim.new(0,3)
do local fakeProfileStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(80,160,255), Thickness=0.7, Transparency=0.3, Parent=fakeProfileBtn})

end local _fpPetIndex = 1
local _fpPetName  = HIGH_TIER_PETS[1]
local fpPetRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, Parent=spawnFrame})
local fpPrevBtn = mk("TextButton", {Size=UDim2.new(0.12,0,1,0), BackgroundColor3=Color3.fromRGB(40,40,60), Text="◀", Font=Enum.Font.GothamBold, TextSize=6, TextColor3=Color3.fromRGB(180,180,220), BorderSizePixel=0, Parent=fpPetRow})
Instance.new("UICorner",fpPrevBtn).CornerRadius=UDim.new(0,3)
local fpPetLbl = mk("TextLabel", {Size=UDim2.new(0.76,0,1,0), Position=UDim2.new(0.12,0,0,0), BackgroundTransparency=1, Font=Enum.Font.FredokaOne, TextSize=6, TextColor3=Color3.fromRGB(200,220,255), TextXAlignment=Enum.TextXAlignment.Center, TextTruncate=Enum.TextTruncate.AtEnd, Text=_fpPetName, Parent=fpPetRow})
do local fpNextBtn = mk("TextButton", {Size=UDim2.new(0.12,0,1,0), Position=UDim2.new(0.88,0,0,0), BackgroundColor3=Color3.fromRGB(40,40,60), Text="▶", Font=Enum.Font.GothamBold, TextSize=6, TextColor3=Color3.fromRGB(180,180,220), BorderSizePixel=0, Parent=fpPetRow})
Instance.new("UICorner",fpNextBtn).CornerRadius=UDim.new(0,3)
fpPrevBtn.MouseButton1Click:Connect(function()
    _fpPetIndex=(_fpPetIndex-2)%#HIGH_TIER_PETS+1; _fpPetName=HIGH_TIER_PETS[_fpPetIndex]; fpPetLbl.Text=_fpPetName
end)
fpNextBtn.MouseButton1Click:Connect(function()
    _fpPetIndex=_fpPetIndex%#HIGH_TIER_PETS+1; _fpPetName=HIGH_TIER_PETS[_fpPetIndex]; fpPetLbl.Text=_fpPetName
end)

end do local fpFlagsRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, Parent=spawnFrame})
for i,fd in ipairs({{key="mega_neon",label="M",col=Color3.fromRGB(160,80,255)},{key="neon",label="N",col=Color3.fromRGB(0,255,100)},{key="flyable",label="F",col=Color3.fromRGB(0,200,220)},{key="rideable",label="R",col=Color3.fromRGB(255,90,150)}}) do
    local fb = mk("TextButton", {Size=UDim2.new(0.23,0,1,0), Position=UDim2.new((i-1)*0.255,0,0,0), Text=fd.label, Font=Enum.Font.GothamBold, TextSize=7, BackgroundColor3=_fpSelectedFlags[fd.key] and fd.col or Color3.fromRGB(44,48,72), TextColor3=Color3.fromRGB(255,255,255), BorderSizePixel=0, Parent=fpFlagsRow})
    Instance.new("UICorner",fb).CornerRadius=UDim.new(0,3)
    fb.MouseButton1Click:Connect(function()
        if fd.key=="mega_neon" and _fpSelectedFlags.neon then return end
        if fd.key=="neon" and _fpSelectedFlags.mega_neon then return end
        _fpSelectedFlags[fd.key]=not _fpSelectedFlags[fd.key]
        fb.BackgroundColor3=_fpSelectedFlags[fd.key] and fd.col or Color3.fromRGB(44,48,72)
    end)
end

end local _fpSaving = false
_G._setupLiveFakeProfileBtn = fakeProfileBtn
_G._fpGetState = function() return _fpPetIndex, _fpPetName, _fpSelectedFlags end
_G._fpSetPet = function(idx, name) _fpPetIndex=idx; _fpPetName=name; fpPetLbl.Text=name end
_G._fpSetProps = function(p)
    _fpSelectedFlags.mega_neon=p.mega_neon; _fpSelectedFlags.neon=p.neon
    _fpSelectedFlags.flyable=p.flyable; _fpSelectedFlags.rideable=p.rideable
end

local function _runFakeProfile()
    if _fpSaving then return end
    _fpSaving = true
    fakeProfileBtn.Text = "Saving..."; fakeProfileBtn.BackgroundColor3 = Color3.fromRGB(60,60,80)
    -- Resolve pet kind from name
    local petKind = nil
    pcall(function()
        for id, data in pairs(InventoryDB.pets or {}) do
            if data.name and data.name:lower() == _fpPetName:lower() then petKind=id; break end
        end
    end)
    if not petKind then
        fakeProfileStatusLbl.Text = "❌ Pet not found"
        fakeProfileBtn.Text = "Spawn Fake Profile"; fakeProfileBtn.BackgroundColor3 = Color3.fromRGB(30,100,160)
        _fpSaving = false; return
    end
    _fpActivePetKind = petKind
    _fpIsEnabled = true
    -- Install hooks in exact same order as uploaded script
    _fpHookClientData()
    _fpHookFetchProfile()
    pcall(function()
        local app = UIManager.apps.PlayerProfileApp
        if app then _fpHookProfileApp(app) end
    end)
    -- Fire all saves
    task.spawn(function()
        local total = _MAX_PAGES * _WIDGETS_PER_PAGE; local done = 0
        local saveRemote = _fpRC.get("PlayerProfileAPI/SaveProfileSlot")
        for page = 1, _MAX_PAGES do
            for slot = 1, _WIDGETS_PER_PAGE do
                pcall(function() saveRemote:FireServer(page, slot, _fpBuildSlotData()) end)
                done = done + 1; fakeProfileStatusLbl.Text = "Saving "..done.."/"..total.."..."; task.wait()
            end
        end
        -- Open own profile to commit (same as uploaded script)
        pcall(function() UIManager.apps.PlayerProfileApp:open_player_profile_for_user_id(Players.LocalPlayer.UserId) end)
        fakeProfileStatusLbl.Text = "✅ All "..total.." slots filled!"
        fakeProfileBtn.Text = "Spawn Fake Profile"; fakeProfileBtn.BackgroundColor3 = Color3.fromRGB(30,100,160)
        task.delay(2, function() fakeProfileStatusLbl.Text = "" end)
        _fpSaving = false
    end)
end
fakeProfileBtn.MouseButton1Click:Connect(_runFakeProfile)
_G._setupLiveRunFakeProfile = _runFakeProfile

-- Delete Fake Profile: clears _fpIsEnabled and fires SaveProfileSlot with an empty widget
-- for every page/slot, then re-opens the profile to commit the blank state.
do
local deleteFakeProfileBtn = mk("TextButton", {
    Size=UDim2.new(1,0,0,13), BackgroundColor3=Color3.fromRGB(120,20,20),
    BackgroundTransparency=0.1, Text="Delete Fake Profile",
    Font=Enum.Font.FredokaOne, TextSize=7,
    TextColor3=Color3.fromRGB(255,160,160), Parent=spawnFrame
})
Instance.new("UICorner", deleteFakeProfileBtn).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(200,50,50), Thickness=0.7, Transparency=0.3, Parent=deleteFakeProfileBtn})

local _fpDeleting = false
deleteFakeProfileBtn.MouseButton1Click:Connect(function()
    if _fpDeleting then return end
    _fpDeleting = true
    _fpIsEnabled = false
    deleteFakeProfileBtn.Text = "Deleting..."
    deleteFakeProfileBtn.BackgroundColor3 = Color3.fromRGB(60,30,30)
    task.spawn(function()
        local total = _MAX_PAGES * _WIDGETS_PER_PAGE
        local done  = 0
        local saveRemote = _fpRC.get("PlayerProfileAPI/SaveProfileSlot")
        for page = 1, _MAX_PAGES do
            for slot = 1, _WIDGETS_PER_PAGE do
                -- Remove the widget entirely (no leftover empty "collection" section).
                local removed = pcall(function() saveRemote:FireServer(page, slot, nil) end)
                if not removed then
                    -- Fallback for servers that reject nil: write a blank non-collection widget.
                    pcall(function()
                        saveRemote:FireServer(page, slot, {
                            widget_kind = "about_me",
                            expanded    = false,
                            widget_data = { title = "", text = "" },
                        })
                    end)
                end
                done = done + 1
                fakeProfileStatusLbl.Text = "Clearing " .. done .. "/" .. total .. "..."
                task.wait()
            end
        end
        -- Strip any remaining collection sections from the locally cached profile
        -- so they disappear from view immediately.
        pcall(function()
            local app = UIManager.apps.PlayerProfileApp
            local pp = app and app.player_profile
            if pp and pp.profile_data and pp.profile_data.pages then
                for _, page in pairs(pp.profile_data.pages) do
                    if type(page) == "table" then
                        for slot, data in pairs(page) do
                            local wd = data
                            if type(wd) == "table" and wd.data then wd = wd.data end
                            if type(wd) == "table" and wd.widget_kind == "collection" then
                                page[slot] = nil
                            end
                        end
                    end
                end
            end
        end)
        pcall(function()
            UIManager.apps.PlayerProfileApp:open_player_profile_for_user_id(Players.LocalPlayer.UserId)
        end)
        fakeProfileStatusLbl.Text = "✅ Profile cleared!"
        deleteFakeProfileBtn.Text = "Delete Fake Profile"
        deleteFakeProfileBtn.BackgroundColor3 = Color3.fromRGB(120,20,20)
        task.delay(2, function() fakeProfileStatusLbl.Text = "" end)
        _fpDeleting = false
    end)
end)
end

end -- fake profile do

end local deleteAllBtn = mk("TextButton", {Size=UDim2.new(1, 0, 0, 13), BackgroundColor3=Color3.fromRGB(120, 20, 20), BackgroundTransparency=0.15, Text="Delete All Spawned", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255, 255, 255), Parent=spawnFrame})
Instance.new("UICorner", deleteAllBtn).CornerRadius = UDim.new(0, 3)
local deleteStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(255, 60, 60), Thickness=0.7, Transparency=0.3, Parent=deleteAllBtn})

deleteAllBtn.MouseButton1Click:Connect(function()
    local toRemove = {}
    for uid in pairs(_spawnerPets) do
        table.insert(toRemove, uid)
    end
    for _, uid in ipairs(toRemove) do
        local ok, e = pcall(_removeFromInventory, uid)
        if not ok then warn("[DeleteAll] " .. tostring(e)) end
    end
    pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)
    deleteStroke.Color = Color3.fromRGB(0, 255, 120)
    task.delay(0.4, function() deleteStroke.Color = Color3.fromRGB(255, 60, 60) end)
end)

end -- SPAWNER TAB do block

-- ANTI-RAID POP-OUT
do
local function _antiRaidMain()
-- Generation token: re-executing bumps this, so the old run's loops stop and its connections are dropped.
_G._antiRaidGen = (_G._antiRaidGen or 0) + 1
local GEN = _G._antiRaidGen
local function alive() return _G._antiRaidGen == GEN end
if _G._antiRaidConns then
    for _, c in ipairs(_G._antiRaidConns) do pcall(function() c:Disconnect() end) end
end
local conns = {}
_G._antiRaidConns = conns
local function track(c) conns[#conns + 1] = c; return c end

local SCAN_INTERVAL = 2
local AUTO_EXCLUDE  = true

local antiRoot, antiScroll, antiStatusLbl, antiCountLbl
local popupMoved = false
local refreshAntiUI  -- forward declaration

local _flagged   = {}   -- uid -> { display_name, user_name, user_id, reasons, left, t }
local _dismissed = {}   -- uid -> true  (dismissed players are NOT re-flagged by the scan loop)
local _needRefresh = false

-- ── Matching ────────────────────────────────────────────────────────────
-- Keywords are matched as WHOLE WORDS (plus s / ed / ing), so "afraid", "Raider",
-- "Hackett", "Scripture" etc. no longer trip "raid" / "hack" / "script".
-- Spaced-out letters ("s c a m") and fancy unicode are still caught.
local BLACKLISTED_KEYWORDS = {
    "scam","scammer","scammers","scamming",
    "delta executor","synapse","exploit","exploiter","krnl",
    "free pets","duped","dupe","dupedpets",
    "botted","botting","botter","raid","raiding",
    "hacked","hacking","hack","hacker","cheat","cheater",
    "drop trade","trust trade",
    "phishing","free robux",
    "vedal","xeno","fluxus","arceus",
}

local UNICODE_RANGES = {
    {0x1D400,0x1D419,0x41},{0x1D41A,0x1D433,0x61},{0x1D434,0x1D44D,0x41},{0x1D44E,0x1D467,0x61},
    {0x1D468,0x1D481,0x41},{0x1D482,0x1D49B,0x61},{0x1D5A0,0x1D5B9,0x41},{0x1D5BA,0x1D5D3,0x61},
    {0x1D5D4,0x1D5ED,0x41},{0x1D5EE,0x1D607,0x61},{0x1D670,0x1D689,0x41},{0x1D68A,0x1D6A3,0x61},
    {0x24B6,0x24CF,0x41},{0x24D0,0x24E9,0x61},{0xFF21,0xFF3A,0x41},{0xFF41,0xFF5A,0x61},{0xFF10,0xFF19,0x30},
    {0x1F130,0x1F149,0x41},{0x1F150,0x1F169,0x41},{0x1F170,0x1F189,0x41},
}
local CHAR_MAP = {
    [0x0391]="a",[0x0392]="b",[0x0395]="e",[0x0397]="h",[0x0399]="i",[0x039A]="k",[0x039C]="m",[0x039D]="n",[0x039F]="o",[0x03A1]="p",
    [0x03A3]="s",[0x03A4]="t",[0x03A5]="y",[0x03A7]="x",[0x03B1]="a",[0x03B2]="b",[0x03B5]="e",[0x03B9]="i",[0x03BA]="k",
    [0x03BC]="m",[0x03BD]="n",[0x03BF]="o",[0x03C1]="r",[0x03C3]="s",[0x03C4]="t",[0x03C5]="u",[0x03C7]="x",
    [0x0410]="a",[0x0415]="e",[0x041A]="k",[0x041C]="m",[0x041D]="h",[0x041E]="o",[0x0420]="p",[0x0421]="c",[0x0422]="t",[0x0423]="y",[0x0425]="x",
    [0x0430]="a",[0x0435]="e",[0x043A]="k",[0x043C]="m",[0x043D]="h",[0x043E]="o",[0x0440]="p",[0x0441]="c",[0x0442]="t",[0x0443]="y",[0x0445]="x",
    [0x00C0]="a",[0x00C1]="a",[0x00C2]="a",[0x00C3]="a",[0x00C4]="a",[0x00C5]="a",[0x00C7]="c",[0x00C9]="e",[0x00D1]="n",[0x00D6]="o",[0x00DC]="u",
    [0x00E0]="a",[0x00E1]="a",[0x00E2]="a",[0x00E3]="a",[0x00E4]="a",[0x00E5]="a",[0x00E7]="c",[0x00E9]="e",[0x00F1]="n",[0x00F6]="o",[0x00FC]="u",[0x00DF]="s",
}

local function normalizeCp(cp)
    local s = CHAR_MAP[cp]; if s then return s end
    for _, r in ipairs(UNICODE_RANGES) do
        if cp >= r[1] and cp <= r[2] then return string.char(r[3]+(cp-r[1])):lower() end
    end
end

local function normalize(text)
    if type(text) ~= "string" then return "" end
    local out = {}
    pcall(function()
        for _, cp in utf8.codes(text) do
            local m = normalizeCp(cp)
            if m then out[#out + 1] = m
            elseif cp >= 0x30 and cp <= 0x39 then out[#out + 1] = string.char(cp)
            elseif cp >= 0x41 and cp <= 0x5A then out[#out + 1] = string.char(cp + 32)
            elseif cp >= 0x61 and cp <= 0x7A then out[#out + 1] = string.char(cp)
            else out[#out + 1] = " " end   -- separators / zero-width / symbols become spaces
        end
    end)
    return table.concat(out)
end

-- "s c a m" -> "scam"; returns the text padded with spaces so word-boundary checks are simple
local function collapseSingles(s)
    local out, run = {}, {}
    for w in s:gmatch("%S+") do
        if #w == 1 and w:match("%a") then
            run[#run + 1] = w
        else
            if #run > 0 then out[#out + 1] = table.concat(run); run = {} end
            out[#out + 1] = w
        end
    end
    if #run > 0 then out[#out + 1] = table.concat(run) end
    return " " .. table.concat(out, " ") .. " "
end

local OK_SUFFIX = { [""] = true, s = true, ed = true, ing = true }
local function hasWord(hay, kw)
    local init = 1
    while true do
        local s, e = hay:find(kw, init, true)
        if not s then return false end
        if not hay:sub(s - 1, s - 1):match("%a") then
            local tail = hay:sub(e + 1):match("^(%a*)") or ""
            if OK_SUFFIX[tail] then return true end
        end
        init = s + 1
    end
end

local KW, _seenKW = {}, {}
for _, kw in ipairs(BLACKLISTED_KEYWORDS) do
    local n = normalize(kw):gsub("^%s+", ""):gsub("%s+$", "")
    for _, v in ipairs({ n, (n:gsub("%s+", "")) }) do   -- "drop trade" also matches "droptrade"
        if v ~= "" and not _seenKW[v] then _seenKW[v] = true; KW[#KW + 1] = v end
    end
end

local function containsBad(text)
    local n = normalize(text)
    if n == "" then return false, nil end
    local hay = collapseSingles(n)
    for _, kw in ipairs(KW) do
        if hasWord(hay, kw) then return true, kw end
    end
    if hay:find("%d") then   -- leetspeak: sc4m, h4ck
        local l = hay:gsub("0", "o"):gsub("1", "i"):gsub("3", "e"):gsub("4", "a"):gsub("5", "s"):gsub("7", "t")
        for _, kw in ipairs(KW) do
            if hasWord(l, kw) then return true, kw end
        end
    end
    return false, nil
end

-- ── Remote user-id blacklist ────────────────────────────────────────────
local _blacklistIds = {}
local GIST_URL = "https://gist.githubusercontent.com/got4access-ops/23ee90f21946f84f602bc920904f07b2/raw/BlacklistedUserIDs"
local function fetchBlacklist()
    task.spawn(function()
        local ok, body = pcall(function()
            if syn and syn.request then return syn.request({Url=GIST_URL,Method="GET"}).Body
            elseif request then return request({Url=GIST_URL,Method="GET"}).Body
            elseif http and http.request then return http.request({url=GIST_URL,method="GET"}).body
            else return game:GetService("HttpService"):GetAsync(GIST_URL,true) end
        end)
        if not ok or type(body) ~= "string" then return end
        local new = {}
        for line in string.gmatch(body, "[^\r\n]+") do
            -- every line is checked (the old code always skipped line 1, which could be a real ID)
            local id = tonumber(string.match(line, "^%s*(%d+)%s*$"))
            if id then new[id] = true end
        end
        _blacklistIds = new
    end)
end
fetchBlacklist()
task.spawn(function()
    while alive() do
        task.wait(120)
        if not alive() then break end
        fetchBlacklist()
    end
end)

local _TradeExcluder = nil
pcall(function() _TradeExcluder = load("TradeExcluder") end)

local function flagPlayer(player, reason)
    if player == Players.LocalPlayer then return end
    local uid = player.UserId
    if _dismissed[uid] then return end          -- stays dismissed (old code re-flagged every 2s)
    local entry = _flagged[uid]
    local first = false
    if not entry then
        entry = {display_name=player.DisplayName, user_name=player.Name, user_id=uid, reasons={}, left=false, t=os.clock()}
        _flagged[uid] = entry
        first = true
    end
    for _, r in ipairs(entry.reasons) do if r == reason then return end end
    table.insert(entry.reasons, reason)
    _needRefresh = true
    if first and AUTO_EXCLUDE and _TradeExcluder then   -- once per player, not once per reason
        pcall(function() _TradeExcluder.trade_was_declined(player); _TradeExcluder.trade_was_declined(player); _TradeExcluder.trade_was_declined(player) end)
    end
end

local function scanPlayer(player)
    if player == Players.LocalPlayer then return end
    if _blacklistIds[player.UserId] then flagPlayer(player, "Blacklisted user ID") end
    local hit, kw = containsBad(player.DisplayName)
    if hit then flagPlayer(player, "Display name: '" .. kw .. "'") end
    hit, kw = containsBad(player.Name)
    if hit then flagPlayer(player, "Username: '" .. kw .. "'") end
end

local function scanPetNames()
    local CWC; pcall(function() CWC = load("CharWrapperClient") end)
    if not CWC then return end
    local ok, wrappers = pcall(CWC.get_all_char_wrappers)
    if not ok or not wrappers then return end
    for _, w in pairs(wrappers) do
        if w.pet_unique and w.player and w.player ~= Players.LocalPlayer then
            local rp = w.rp_name
            if rp and rp ~= "" then
                local hit, kw = containsBad(rp)
                if hit then flagPlayer(w.player, "Pet name: '" .. kw .. "' (" .. rp .. ")") end
            end
        end
    end
end

-- ── UI ──────────────────────────────────────────────────────────────────
local function updateAntiPopoutButton(open)
    local btn = _G._antiPopoutBtn
    local stroke = _G._antiPopoutStroke
    if btn then
        btn.BackgroundColor3 = open and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
        btn.TextColor3       = open and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
    end
    if stroke then
        stroke.Color = open and Color3.fromRGB(0,255,100) or Color3.fromRGB(220,50,50)
    end
end

-- Sits beside the main window. Falls back to default size if the main frame hasn't laid out yet
-- (the old code could build a 0x0 popup).
local function positionPopup()
    if not (antiRoot and antiRoot.Parent) then return end
    local main = _G._tradeGuiMainFrame
    local sz  = (main and main.Parent and main.AbsoluteSize) or Vector2.new(0, 0)
    local pos = (main and main.Parent and main.AbsolutePosition) or Vector2.new(205, 150)
    local W, H = sz.X, sz.Y
    if W < 40 or H < 40 then W, H = 130, 300 end
    -- far right edge of the screen (not beside the main window)
    local cam = workspace.CurrentCamera
    local sg = _G._controlGui
    local screenW = (sg and sg.AbsoluteSize.X > 0 and sg.AbsoluteSize.X) or (cam and cam.ViewportSize.X) or 1000
    local screenH = (sg and sg.AbsoluteSize.Y > 0 and sg.AbsoluteSize.Y) or (cam and cam.ViewportSize.Y) or 700
    local bx = math.max(0, screenW - (W + 6) - 6)
    local by = math.clamp(pos.Y - 3, 0, math.max(0, screenH - (H + 6)))
    antiRoot.Size     = UDim2.fromOffset(W + 6, H + 6)
    antiRoot.Position = UDim2.fromOffset(bx, by)
    local panel = antiRoot:FindFirstChild("Panel")
    if panel then panel.Size = UDim2.fromOffset(W, H) end
end

-- Builds the whole popup (frame + content) in one go, so a rebuild can never leave the list
-- parented to a dead frame (the old toggle rebuilt only the outer frame).
local function buildAntiPopup()
    if antiRoot and antiRoot.Parent then return true end
    local gui = _G._controlGui
    if not (gui and gui.Parent) then
        gui = Players.LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("MockTradeControl")
    end
    if not gui then return false end
    popupMoved = false

    antiRoot = mk("Frame", {Name="AntiRaidPopup", Size=UDim2.fromOffset(136, 306), Position=UDim2.fromOffset(0, 0), BackgroundColor3=Color3.new(0,0,0), BorderSizePixel=0, ZIndex=49, Visible=false, Parent=gui})
    Instance.new("UICorner", antiRoot).CornerRadius = UDim.new(0,7)
    local panel = mk("Frame", {Name="Panel", Size=UDim2.fromOffset(130, 300), Position=UDim2.fromOffset(3,3), BackgroundColor3=Color3.fromRGB(30,30,40), BorderSizePixel=0, ZIndex=50, Parent=antiRoot})
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0,5)
    mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(220,50,50), Thickness=1.5, Parent=panel})
    local title = mk("Frame", {Size=UDim2.new(1,0,0,18), BackgroundColor3=Color3.fromRGB(62,30,36), BorderSizePixel=0, ZIndex=51, Parent=panel})
    Instance.new("UICorner", title).CornerRadius = UDim.new(0,5)
    mk("TextLabel", {Size=UDim2.new(1,-24,1,0), Position=UDim2.new(0,6,0,0), BackgroundTransparency=1, Text="🛡️ Anti Raid", Font=Enum.Font.FredokaOne, TextSize=9, TextColor3=Color3.fromRGB(255,180,180), TextXAlignment=Enum.TextXAlignment.Left, ZIndex=52, Parent=title})
    local closeBtn = mk("ImageButton", {Size=UDim2.new(0,10,0,10), Position=UDim2.new(1,-15,0.5,-5), BackgroundTransparency=1, Image="rbxthumb://type=Asset&id=5107150321&w=150&h=150", ImageColor3=Color3.fromRGB(165,45,45), ScaleType=Enum.ScaleType.Fit, ZIndex=52, Parent=title})
    local content = mk("Frame", {Name="Content", Size=UDim2.new(1,-10,1,-26), Position=UDim2.new(0,5,0,22), BackgroundTransparency=1, ZIndex=51, Parent=panel})

    mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=content})
    local headerRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, LayoutOrder=1, Parent=content})
    antiStatusLbl = mk("TextLabel", {Size=UDim2.new(0.65,0,1,0), BackgroundTransparency=1, Text="Scanning...", Font=Enum.Font.SourceSans, TextSize=6, TextColor3=Color3.fromRGB(150,150,160), TextXAlignment=Enum.TextXAlignment.Left, Parent=headerRow})
    antiCountLbl  = mk("TextLabel", {Size=UDim2.new(0.35,0,1,0), Position=UDim2.new(0.65,0,0,0), BackgroundTransparency=1, Text="0 flagged", Font=Enum.Font.FredokaOne, TextSize=6, TextColor3=Color3.fromRGB(255,80,80), TextXAlignment=Enum.TextXAlignment.Right, Parent=headerRow})
    antiScroll = mk("ScrollingFrame", {Size=UDim2.new(1,0,1,-14), BackgroundColor3=Color3.fromRGB(25,25,35), BackgroundTransparency=0.5, BorderSizePixel=0, ScrollBarThickness=2, ScrollBarImageColor3=Color3.fromRGB(190,34,230), ScrollBarImageTransparency=0.4, CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y, LayoutOrder=3, Parent=content})
    Instance.new("UICorner", antiScroll).CornerRadius = UDim.new(0,4)
    mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=antiScroll})
    mk("UIPadding", {PaddingTop=UDim.new(0,3), PaddingBottom=UDim.new(0,3), PaddingLeft=UDim.new(0,3), PaddingRight=UDim.new(0,3), Parent=antiScroll})

    -- drag by title bar
    local root = antiRoot
    local dragging, dragStart, startPos = false, nil, nil
    track(title.InputBegan:Connect(function(input)
        if _G._guiLocked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; popupMoved = true; dragStart = input.Position; startPos = root.Position
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and not _G._guiLocked and root.Parent and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    closeBtn.MouseButton1Click:Connect(function()
        root.Visible = false
        updateAntiPopoutButton(false)
    end)
    -- Layering safety: every element inside the pop-out is kept above the panel background
    -- (labels / list / cards defaulted to ZIndex 1, which hides them behind the ZIndex-50 panel
    -- whenever the GUI uses global z-ordering).
    local function bump(o) if o:IsA("GuiObject") and o.ZIndex < 51 then o.ZIndex = 51 end end
    for _, d in ipairs(antiRoot:GetDescendants()) do bump(d) end
    track(antiRoot.DescendantAdded:Connect(bump))
    return true
end

refreshAntiUI = function()
    if not (antiScroll and antiScroll.Parent) then return end
    for _, c in ipairs(antiScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    local list = {}
    for _, data in pairs(_flagged) do list[#list + 1] = data end
    table.sort(list, function(a, b) return a.t < b.t end)   -- stable order (pairs() order flickered)

    for order, data in ipairs(list) do
        local uid = data.user_id
        local card = mk("Frame", {Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, BackgroundColor3=Color3.fromRGB(40,40,52), BackgroundTransparency=0.2, LayoutOrder=order, Parent=antiScroll})
        Instance.new("UICorner", card).CornerRadius = UDim.new(0,4)
        mk("UIStroke", {Color=Color3.fromRGB(80,80,80), Thickness=0.7, Transparency=0.5, Parent=card})
        mk("UIPadding", {PaddingTop=UDim.new(0,3), PaddingBottom=UDim.new(0,3), PaddingLeft=UDim.new(0,4), PaddingRight=UDim.new(0,4), Parent=card})
        mk("UIListLayout", {Padding=UDim.new(0,2), SortOrder=Enum.SortOrder.LayoutOrder, Parent=card})

        mk("TextLabel", {Size=UDim2.new(1,0,0,9), BackgroundTransparency=1, TextColor3=data.left and Color3.fromRGB(150,60,60) or Color3.fromRGB(220,50,50), Font=Enum.Font.FredokaOne, TextSize=7, Text=data.display_name..(data.left and " [LEFT]" or ""), TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, LayoutOrder=1, Parent=card})
        mk("TextLabel", {Size=UDim2.new(1,0,0,7), BackgroundTransparency=1, TextColor3=Color3.fromRGB(150,150,160), Font=Enum.Font.SourceSans, TextSize=6, Text="@"..data.user_name, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, LayoutOrder=2, Parent=card})
        for i = 1, math.min(#data.reasons, 2) do
            mk("TextLabel", {Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y, BackgroundTransparency=1, TextColor3=Color3.fromRGB(170,170,180), Font=Enum.Font.SourceSans, TextSize=6, Text="- "..data.reasons[i], TextXAlignment=Enum.TextXAlignment.Left, TextWrapped=true, LayoutOrder=2+i, Parent=card})
        end
        if #data.reasons > 2 then
            mk("TextLabel", {Size=UDim2.new(1,0,0,6), BackgroundTransparency=1, TextColor3=Color3.fromRGB(120,20,150), Font=Enum.Font.SourceSans, TextSize=6, Text="+"..(#data.reasons-2).." more", TextXAlignment=Enum.TextXAlignment.Left, LayoutOrder=5, Parent=card})
        end

        local btnRow = mk("Frame", {Size=UDim2.new(1,0,0,11), BackgroundTransparency=1, LayoutOrder=100, Parent=card})
        local dismissBtn = mk("TextButton", {Size=UDim2.new(0.48,0,1,0), BackgroundColor3=Color3.fromRGB(50,50,60), BackgroundTransparency=0.2, TextColor3=Color3.fromRGB(150,150,160), Font=Enum.Font.FredokaOne, TextSize=7, Text="Dismiss", Parent=btnRow})
        Instance.new("UICorner", dismissBtn).CornerRadius = UDim.new(0,3)
        local blockBtn = mk("TextButton", {Size=UDim2.new(0.48,0,1,0), Position=UDim2.new(0.52,0,0,0), BackgroundColor3=Color3.fromRGB(160,30,30), BackgroundTransparency=0.2, TextColor3=Color3.fromRGB(255,255,255), Font=Enum.Font.FredokaOne, TextSize=7, Text="Block", Parent=btnRow})
        Instance.new("UICorner", blockBtn).CornerRadius = UDim.new(0,3)
        mk("UIStroke", {Color=Color3.fromRGB(255,60,60), Thickness=0.7, Parent=blockBtn})

        dismissBtn.MouseButton1Click:Connect(function()
            _dismissed[uid] = true      -- remembered, so the next scan doesn't bring the card straight back
            _flagged[uid] = nil
            refreshAntiUI()
        end)
        blockBtn.MouseButton1Click:Connect(function()
            local target = Players:GetPlayerByUserId(uid)
            if target then
                blockBtn.Text = "..."
                if _G._silentBlockPlayer then _G._silentBlockPlayer(target) end
                task.delay(1.5, function()
                    if blockBtn.Parent then blockBtn.Text = "Done"; blockBtn.TextColor3 = Color3.fromRGB(80,255,130) end
                end)
            else
                blockBtn.Text = "Gone"
            end
        end)
    end

    local count = #list
    if antiCountLbl and antiCountLbl.Parent then
        antiCountLbl.Text = count > 0 and (count .. " flagged") or "0 flagged"
        antiCountLbl.TextColor3 = count > 0 and Color3.fromRGB(255,80,80) or Color3.fromRGB(100,255,150)
    end
    if antiStatusLbl and antiStatusLbl.Parent then
        antiStatusLbl.Text = count > 0 and "⚠ threats detected" or "✓ monitoring"
    end
    _needRefresh = false
end

_G._toggleAntiPopup = function(forceOpen)
    -- a half-built popup (an earlier build error) is thrown away and rebuilt instead of reused
    if antiRoot and antiRoot.Parent and not (antiScroll and antiScroll.Parent) then
        pcall(function() antiRoot:Destroy() end); antiRoot = nil
    end
    if not buildAntiPopup() then return end
    local open = forceOpen
    if open == nil then open = not antiRoot.Visible end
    if open and not popupMoved then positionPopup() end
    antiRoot.Visible = open
    updateAntiPopoutButton(open)
    if open then refreshAntiUI() end
end
updateAntiPopoutButton(false)

-- Exposed so other tabs can stay in sync
_G._raidFlagged = _flagged
_G._raidDismiss = function(uid) _dismissed[uid] = true; _flagged[uid] = nil; refreshAntiUI() end

-- ── Chat scanning ───────────────────────────────────────────────────────
local function scanChatMessage(player, text)
    if not player or player == Players.LocalPlayer then return end
    if type(text) ~= "string" or text == "" then return end
    local hit, kw = containsBad(text)
    if hit then
        flagPlayer(player, "Chat: '" .. kw .. "'  (" .. text:sub(1, 40) .. ")")
        if _needRefresh then refreshAntiUI() end
    end
end

task.spawn(function()
    local TextChatService = game:GetService("TextChatService")
    -- OnIncomingMessage fires client-side for EVERY incoming chat message (this is the hook the working version used).
    -- The game's own callback (if any) is stored once and still called, so chat formatting is untouched.
    pcall(function()
        if _G._antiOrigOnIncoming == nil then
            local okO, o = pcall(function() return TextChatService.OnIncomingMessage end)
            _G._antiOrigOnIncoming = (okO and o) or false
        end
        TextChatService.OnIncomingMessage = function(msg)
            if alive() then
                pcall(function()
                    local src = msg and msg.TextSource
                    if src and msg.Text and msg.Text ~= "" then
                        scanChatMessage(Players:GetPlayerByUserId(src.UserId), msg.Text)
                    end
                end)
            end
            local orig = _G._antiOrigOnIncoming
            if orig then return orig(msg) end
        end
    end)
    -- NOTE: the old version tracked hooked channels with `ch._antiHooked = true`. Instances reject
    -- unknown properties, so that line threw and NO chat hook was ever installed. Use a table instead.
    local hookedChannels = setmetatable({}, {__mode = "k"})
    local function hookChannel(ch)
        if hookedChannels[ch] then return end
        hookedChannels[ch] = true
        track(ch.MessageReceived:Connect(function(msg)
            pcall(function()
                if not alive() or not msg or not msg.TextSource then return end
                scanChatMessage(Players:GetPlayerByUserId(msg.TextSource.UserId), msg.Text or "")
            end)
        end))
    end
    pcall(function()
        for _, ch in ipairs(TextChatService:GetDescendants()) do
            if ch:IsA("TextChannel") then hookChannel(ch) end
        end
        track(TextChatService.DescendantAdded:Connect(function(ch)
            if ch:IsA("TextChannel") then hookChannel(ch) end
        end))
    end)

    -- Legacy chat (Players.Chatted)
    local hookedPlayers = {}
    local function hookLegacy(player)
        if hookedPlayers[player] then return end
        hookedPlayers[player] = true
        pcall(function()
            track(player.Chatted:Connect(function(msg)
                if alive() then scanChatMessage(player, msg) end
            end))
        end)
    end
    for _, p in ipairs(Players:GetPlayers()) do hookLegacy(p) end
    track(Players.PlayerAdded:Connect(hookLegacy))
end)

-- ── Player events + scan loop ───────────────────────────────────────────
track(Players.PlayerAdded:Connect(function(p)
    pcall(scanPlayer, p)
    task.delay(4, function()
        if not alive() or not p.Parent then return end
        pcall(scanPetNames)
        if _needRefresh then refreshAntiUI() end
    end)
    if _needRefresh then refreshAntiUI() end
end))
track(Players.PlayerRemoving:Connect(function(p)
    _dismissed[p.UserId] = nil
    if _flagged[p.UserId] then _flagged[p.UserId].left = true; _needRefresh = true end
    if _needRefresh then refreshAntiUI() end
end))

for _, p in ipairs(Players:GetPlayers()) do pcall(scanPlayer, p) end
do
    local okB, errB = pcall(buildAntiPopup)
    if not okB then warn("[AntiRaid] popup build failed: " .. tostring(errB)) end
    local okR, errR = pcall(refreshAntiUI)
    if not okR then warn("[AntiRaid] refresh failed: " .. tostring(errR)) end
end

task.spawn(function()
    while alive() do
        task.wait(SCAN_INTERVAL)
        if not alive() then break end
        -- pcall so one bad frame can't kill the scanner for the rest of the session
        pcall(function()
            for _, p in ipairs(Players:GetPlayers()) do scanPlayer(p) end
            scanPetNames()
            if _needRefresh then refreshAntiUI() end
        end)
    end
end)

end -- _antiRaidMain
local _ok, _err = pcall(_antiRaidMain)
if not _ok then warn('[AntiRaid] ' .. tostring(_err)) end

end -- ANTI-RAID POP-OUT do block

-- CHAT TAB
do
local chatFrame = tabFrames["Chat"]
if not chatFrame then
    chatFrame = Instance.new("Frame")
    chatFrame.Size = UDim2.new(0.9,0,1,-33); chatFrame.Position = UDim2.new(0.05,0,0,33)
    chatFrame.BackgroundTransparency = 1; chatFrame.Visible = false; chatFrame.Parent = mainFrame
    tabFrames["Chat"] = chatFrame
end

-- Custom-message row at the top: type your own line for the partner to "say", then Send.
local customRow = mk("Frame", {Size=UDim2.new(1,0,0,18), BackgroundTransparency=1, Parent=chatFrame})
local customBox = mk("TextBox", {Size=UDim2.new(1,-30,1,0), BackgroundColor3=Color3.fromRGB(40,40,52), Text="", PlaceholderText="Type a message...", PlaceholderColor3=Color3.fromRGB(120,120,140), Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(235,235,255), TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ClearTextOnFocus=false, ClipsDescendants=true, BorderSizePixel=0, Parent=customRow})
Instance.new("UICorner", customBox).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4, Parent=customBox})
mk("UIPadding", {PaddingLeft=UDim.new(0,4), PaddingRight=UDim.new(0,4), Parent=customBox})
local customSendBtn = mk("TextButton", {Size=UDim2.new(0,28,1,0), Position=UDim2.new(1,-28,0,0), BackgroundColor3=Color3.fromRGB(190,34,230), Text="Send", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255,255,255), BorderSizePixel=0, Parent=customRow})
Instance.new("UICorner", customSendBtn).CornerRadius = UDim.new(0,3)
mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(230,120,255), Thickness=0.7, Transparency=0.3, Parent=customSendBtn})

local chatStatusLbl = mk("TextLabel", {Size=UDim2.new(1,0,0,11), Position=UDim2.new(0,0,0,20), BackgroundTransparency=1, Text="Click a message to send", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(140,140,160), TextXAlignment=Enum.TextXAlignment.Left, Parent=chatFrame})
local _cspad = mk("UIPadding", {PaddingLeft=UDim.new(0,3), Parent=chatStatusLbl})

local chatScrollFrame = mk("ScrollingFrame", {Size=UDim2.new(1,0,1,-33), Position=UDim2.new(0,0,0,33), BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=2, ScrollBarImageColor3=Color3.fromRGB(190,34,230), CanvasSize=UDim2.new(0,0,0,0), Parent=chatFrame})
local chatListLayout = mk("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,3), Parent=chatScrollFrame})
local chatPad = mk("UIPadding", {PaddingTop=UDim.new(0,4), PaddingBottom=UDim.new(0,4), PaddingLeft=UDim.new(0,4), PaddingRight=UDim.new(0,4), Parent=chatScrollFrame})
chatListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    chatScrollFrame.CanvasSize = UDim2.new(0,0,0,chatListLayout.AbsoluteContentSize.Y + 8)
end)

local _chatQueue = {}
local _chatQueueRunning = false

local function _runChatQueue()
    if _chatQueueRunning then return end
    _chatQueueRunning = true
    task.spawn(function()
        while #_chatQueue > 0 do
            local item = table.remove(_chatQueue, 1)
            local msg, btn = item.msg, item.btn
            btn.TextColor3 = Color3.fromRGB(255,220,80)

            -- Typing indicator
            local typingLabel = nil
            safeCall(function()
                local scrollFrame = TradeApp.chat_scrolling_frame
                local template = TradeApp.chat_message_template
                if not scrollFrame or not template then return end
                local atBottom = math.abs(scrollFrame.CanvasSize.Y.Offset - scrollFrame.AbsoluteSize.Y - scrollFrame.CanvasPosition.Y) < 40
                local clone = template:Clone()
                clone.Name = "TypingMessage"; clone.RichText = true
                clone.Text = string.format("<i><b>%s</b> is typing</i>", CONFIG.PARTNER_NAME:lower())
                clone.TextColor3 = Color3.fromRGB(150,150,150); clone.TextSize = 22
                clone.TextTransparency = 0; clone.LayoutOrder = 1; clone.Parent = scrollFrame.Content
                local h = clone.TextBounds.Y
                clone.Size = UDim2.new(1,0,0,h)
                scrollFrame.CanvasSize = scrollFrame.CanvasSize + UDim2.new(0,0,0,h)
                if atBottom then scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.CanvasSize.Y.Offset - scrollFrame.AbsoluteSize.Y) end
                typingLabel = clone
            end)
            local elapsed, dotTimer, dots = 0, 0, 0
            while elapsed < 1.8 and typingLabel and typingLabel.Parent do
                local dt = task.wait(0.05)
                elapsed = elapsed + dt; dotTimer = dotTimer + dt
                if dotTimer >= 0.25 then
                    dotTimer = 0; dots = (dots % 3) + 1
                    typingLabel.Text = string.format("<i><b>%s</b> is typing%s</i>", CONFIG.PARTNER_NAME:lower(), string.rep(".", dots))
                end
            end
            if typingLabel and typingLabel.Parent then
                safeCall(function()
                    local scrollFrame = TradeApp.chat_scrolling_frame
                    scrollFrame.CanvasSize = scrollFrame.CanvasSize - UDim2.new(0,0,0,typingLabel.Size.Y.Offset)
                end)
                typingLabel:Destroy()
            end

            -- Send
            pcall(function()
                local partner = TradeApp:_get_partner()
                if partner then TradeApp:_render_message_in_trade_chat(partner, msg, true) end
            end)
            btn.TextColor3 = Color3.fromRGB(235,235,255)
            chatStatusLbl.Text = #_chatQueue > 0 and (#_chatQueue .. " queued...") or "Sent!"
            chatStatusLbl.TextColor3 = #_chatQueue > 0 and Color3.fromRGB(255,220,80) or Color3.fromRGB(100,255,150)
            if #_chatQueue == 0 then
                task.delay(1.5, function()
                    chatStatusLbl.Text = "Click a message to send"
                    chatStatusLbl.TextColor3 = Color3.fromRGB(140,140,160)
                end)
            end
            task.wait(0.15)
        end
        _chatQueueRunning = false
    end)
end

local function sendChatMessage(msg, btn)
    if not mockState.active or not mockState.trade then
        chatStatusLbl.Text = "No active trade!"
        chatStatusLbl.TextColor3 = Color3.fromRGB(255,100,100)
        task.delay(1.5, function()
            chatStatusLbl.Text = "Click a message to send"
            chatStatusLbl.TextColor3 = Color3.fromRGB(140,140,160)
        end)
        return
    end
    table.insert(_chatQueue, {msg=msg, btn=btn})
    chatStatusLbl.Text = #_chatQueue > 1 and (#_chatQueue .. " queued...") or "Sending..."
    chatStatusLbl.TextColor3 = Color3.fromRGB(255,220,80)
    _runChatQueue()
end

-- Custom-message send: take whatever's typed and make the partner "say" it, then clear.
local function _sendCustomChat()
    local txt = customBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if txt == "" then return end
    sendChatMessage(txt, customSendBtn)
    customBox.Text = ""
end
customSendBtn.MouseButton1Click:Connect(_sendCustomChat)
customBox.FocusLost:Connect(function(enterPressed) if enterPressed then _sendCustomChat() end end)

-- Build message buttons using same style as Players tab
local _chatBtns = {}
local function buildChatButtons()
    for _, child in ipairs(chatScrollFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    _chatBtns = {}
    local _cl = ChatList or _G._ChatList or {}
    for i, msg in ipairs(_cl) do
        local btn = mk("TextButton", {Size=UDim2.new(1,0,0,22), BackgroundColor3=Color3.fromRGB(40,40,52), BackgroundTransparency=0.2, Text="", LayoutOrder=i, BorderSizePixel=0, Parent=chatScrollFrame})
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,4)
        local stroke = mk("UIStroke", {Color=Color3.fromRGB(80,80,80), Thickness=0.8, Transparency=0.5, Parent=btn})
        local lbl = mk("TextLabel", {Size=UDim2.new(1,-6,1,0), Position=UDim2.new(0,4,0,0), BackgroundTransparency=1, Text=msg, Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(235,235,255), TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Parent=btn})
        table.insert(_chatBtns, btn)
        btn.MouseButton1Click:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency=0.05}):Play()
            task.delay(0.12, function()
                TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency=0.2}):Play()
            end)
            sendChatMessage(msg, lbl)
        end)
    end

    -- Special button: choose a random dream pet and a random Mega / Neon / regular variant.
    -- sendChatMessage() checks mockState.active + mockState.trade, so this cannot fire outside a mock trade.
    local randomPetBtn = mk("TextButton", {Size=UDim2.new(1,0,0,22), BackgroundColor3=Color3.fromRGB(55,42,82), BackgroundTransparency=0.2, Text="", LayoutOrder=0, BorderSizePixel=0, Parent=chatScrollFrame})
    Instance.new("UICorner", randomPetBtn).CornerRadius = UDim.new(0,4)
    local randomPetStroke = mk("UIStroke", {Color=Color3.fromRGB(160,110,255), Thickness=0.9, Transparency=0.35, Parent=randomPetBtn})
    local randomPetLbl = mk("TextLabel", {Size=UDim2.new(1,-6,1,0), Position=UDim2.new(0,4,0,0), BackgroundTransparency=1, Text="Random Pet Message", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(220,205,255), TextXAlignment=Enum.TextXAlignment.Left, Parent=randomPetBtn})
    table.insert(_chatBtns, randomPetBtn)
    randomPetBtn.MouseButton1Click:Connect(function()
        if not mockState.active or not mockState.trade then return end
        local pets = {"owl", "crow", "bat dragon", "shadow dragon", "frost dragon", "parrot", "cryptid", "giant panda", "balloon uni"}
        local pet = pets[math.random(1, #pets)]
        local flagRoll = math.random(1, 3)
        local petName = flagRoll == 1 and ("mega " .. pet) or flagRoll == 2 and ("neon " .. pet) or pet
        local messages = {
            "can i get a " .. petName,
            "my dream pet is " .. petName,
            "i want a " .. petName,
            "pleaseee can i get " .. petName,
            "i would love a " .. petName .. "!!!",
            "pls can i have " .. petName,
            "please can i get " .. petName,
            "ive always wanted a " .. petName,
        }
        TweenService:Create(randomPetBtn, TweenInfo.new(0.08, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency=0.05}):Play()
        task.delay(0.12, function()
            TweenService:Create(randomPetBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {BackgroundTransparency=0.2}):Play()
        end)
        sendChatMessage(messages[math.random(1, #messages)], randomPetLbl)
    end)

    -- Animate in like player list
    for i, btn in ipairs(_chatBtns) do
        btn.BackgroundTransparency = 1
        local s = btn:FindFirstChildOfClass("UIStroke")
        local l = btn:FindFirstChildOfClass("TextLabel")
        if s then s.Transparency = 1 end
        if l then l.TextTransparency = 1 end
        task.spawn(function()
            task.wait((i-1) * 0.04)
            TweenService:Create(btn, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency=0.2}):Play()
            if s then TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Transparency=0.5}):Play() end
            if l then TweenService:Create(l, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {TextTransparency=0}):Play() end
        end)
    end
end

buildChatButtons()
end -- CHAT TAB do block

do
local fsysLoad = load  -- our script's load = Fsys.load

-- =====================================================================
--  SPIN FIX: self-host + inject DailyLoginApp.
--  The game removed DailyLoginApp (which the pet spinner piggybacks on),
--  which patched the spinner. This rebuilds it from a saved GUI dump and
--  registers a working DailyLoginApp module into UIManager before the
--  spinner uses it. No-op if the game still provides DailyLoginApp.
-- =====================================================================
do
local fsysLoad    = load
local UIManager   = load("UIManager")
local InventoryDB = load("InventoryDB")
local HttpService = game:GetService("HttpService")
local PlayerGui   = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

-- ── Self-hosted ScriptUtil ────────────────────────────────────────────────────
local ScriptUtil = {
    create_continue = function(p1)
        local timeout = (p1 or {}).timeout or 1e999
        local be = Instance.new("BindableEvent")
        local fired = false
        local args = nil
        if timeout < 1e999 then
            delay(timeout, function() if be then fired=true; be:Fire() end end)
        end
        return {
            continue = function(...)
                if be then fired=true; args={...}; be:Fire() end
            end,
            yield = function()
                if not fired then be.Event:wait() end
                be:Destroy()
                return table.unpack(args or {})
            end
        }
    end
}

-- ── Self-hosted CloudValues stub ──────────────────────────────────────────────
local CloudValues
do
    local ok, cv = pcall(fsysLoad, "CloudValues")
    if ok and cv then
        CloudValues = cv
    else
        -- Minimal stub: getValue always returns nil (ads disabled fallback)
        CloudValues = {getValue=function() return nil end, onChange=function() end}
    end
end

-- ── RewardedAds stubs (script.Parent references won't work in executor) ───────
local RewardedAdsHelper = {
    are_rewarded_ads_enabled = function() return false end,
    is_ad_available          = function() return false end,
    preload_ad_async         = function() return false end,
}
local RewardedAdsAB = {
    get_group = function() return "control" end,
}
local DailyLoginDB
do
    local t1 = {week_length=5,month_length=30,daily_rewards_onboarding={},daily_rewards_consecutive={}}
    local t2={[1]=25,[2]=50,[3]=100,[4]=200}
    local t3={[1]=5,[2]=10,[3]=10,[4]=15,[5]=15,[6]=20}
    local t4={[1]=12,[2]=12,[3]=15,[4]=15,[5]=17,[6]=20}
    local t5={
        [1]={reward_type="gift",gift_type="smallgift",alternative_reward={reward_type="money",amount=300}},
        [2]={reward_type="gift",gift_type="biggift",alternative_reward={reward_type="money",amount=300}},
        [3]={reward_type="item",item_category="gifts",item_id="legend_hat_2022_simple_chest",alternative_reward={reward_type="money",amount=300}},
        [4]={reward_type="item",item_category="gifts",item_id="legend_hat_2022_regal_chest",alternative_reward={reward_type="money",amount=300}},
        [5]={reward_type="gift",gift_type="massivegift",alternative_reward={reward_type="money",amount=300}},
        [6]={reward_type="item",item_category="pets",item_id="cracked_egg",alternative_reward={reward_type="money",amount=500}},
    }
    for i=1,t1.month_length do
        local wk=math.floor(i/t1.week_length)
        local v8,v9
        if i%t1.week_length==0 then
            v8=table.clone(t5[wk]); v9=table.clone(t5[wk])
            v8.stars=t3[wk]; v9.stars=t4[wk]
        else
            v8={stars=1,reward_type="money",amount=t2[i%t1.week_length]}
            v9={stars=1,reward_type="money",amount=t2[i%t1.week_length]}
        end
        if v8.alternative_reward then v8.alternative_reward.stars=v8.stars end
        if v9.alternative_reward then v9.alternative_reward.stars=v9.stars end
        t1.daily_rewards_onboarding["day_"..i]=v8
        t1.daily_rewards_consecutive["day_"..i]=v9
    end
    function t1.get_reward_for_day(n,b)
        local v=((n>t1.month_length) and t1.daily_rewards_consecutive or t1.daily_rewards_onboarding)["day_"..((n-1)%t1.month_length+1)]
        if b and v and v.alternative_reward then return v.alternative_reward end
        return v
    end
    DailyLoginDB = t1
end

-- ── Self-hosted DailyLoginApp GUI + Module (game removed them) ──────────────
-- Build the GUI from the saved GUI2LUA dump, inject into PlayerGui,
-- then register a full DailyLoginApp using the saved module code.

local function buildAndInjectDailyLoginApp()
    if not (UIManager and UIManager.apps) then return end
    if UIManager.apps.DailyLoginApp then return end

    -- ── Step 1: inject GUI into UI_Resources so UIManager finds it ─────────
    local UI_Resources = game.ReplicatedStorage:FindFirstChild("Resources")
        and game.ReplicatedStorage.Resources:FindFirstChild("UI_Resources")
    if not UI_Resources then
        -- Try old path name
        UI_Resources = game.ReplicatedStorage:FindFirstChild("UI_Resources")
    end

    -- Remove stale PlayerGui instance
    local oldGui = PlayerGui:FindFirstChild("DailyLoginApp")
    if oldGui then oldGui:Destroy() end

    -- Build the GUI from the saved dump
    local G2L = {}
-- ReplicatedStorage.RawUI.DailyLoginApp
G2L["1"] = Instance.new("ScreenGui", game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"));
G2L["1"]["IgnoreGuiInset"] = true;
G2L["1"]["DisplayOrder"] = 7;
G2L["1"]["ScreenInsets"] = Enum.ScreenInsets.DeviceSafeInsets;
G2L["1"]["Name"] = [[DailyLoginApp]];
G2L["1"]["ZIndexBehavior"] = Enum.ZIndexBehavior.Sibling;
G2L["1"]["ResetOnSpawn"] = false;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame
G2L["2"] = Instance.new("Frame", G2L["1"]);
G2L["2"]["BackgroundColor3"] = Color3.fromRGB(249, 249, 249);
G2L["2"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["2"]["Size"] = UDim2.new(0, 592, 0, 308);
G2L["2"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);
G2L["2"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["2"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Shadow
G2L["3"] = Instance.new("ImageLabel", G2L["2"]);
G2L["3"]["ZIndex"] = 2;
G2L["3"]["SliceCenter"] = Rect.new(20, 20, 50, 50);
G2L["3"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["3"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["3"]["ImageColor3"] = Color3.fromRGB(0, 0, 0);
G2L["3"]["Image"] = [[rbxassetid://2577985667]];
G2L["3"]["Size"] = UDim2.new(1, 30, 1, 30);
G2L["3"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["3"]["BackgroundTransparency"] = 1;
G2L["3"]["Name"] = [[Shadow]];
G2L["3"]["Position"] = UDim2.new(0, -15, 0, -15);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body
G2L["4"] = Instance.new("Frame", G2L["2"]);
G2L["4"]["ZIndex"] = 4;
G2L["4"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["4"]["Size"] = UDim2.new(1, 0, 1, -40);
G2L["4"]["Position"] = UDim2.new(0, 0, 0, 40);
G2L["4"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["4"]["Name"] = [[Body]];
G2L["4"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer
G2L["5"] = Instance.new("Frame", G2L["4"]);
G2L["5"]["ZIndex"] = 4;
G2L["5"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["5"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["5"]["Size"] = UDim2.new(1, 0, 0, 155);
G2L["5"]["Position"] = UDim2.new(0.5, 0, 0.4, 0);
G2L["5"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["5"]["Name"] = [[DaysListContainer]];
G2L["5"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList
G2L["6"] = Instance.new("Frame", G2L["5"]);
G2L["6"]["ZIndex"] = 4;
G2L["6"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["6"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["6"]["ClipsDescendants"] = true;
G2L["6"]["Size"] = UDim2.new(0.9, 0, 1, 0);
G2L["6"]["Position"] = UDim2.new(0.5, 0, 0.37, 0);
G2L["6"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["6"]["Name"] = [[DaysList]];
G2L["6"]["LayoutOrder"] = 1;
G2L["6"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.UIPageLayout
G2L["7"] = Instance.new("UIPageLayout", G2L["6"]);
G2L["7"]["EasingStyle"] = Enum.EasingStyle.Quad;
G2L["7"]["GamepadInputEnabled"] = false;
G2L["7"]["TouchInputEnabled"] = false;
G2L["7"]["VerticalAlignment"] = Enum.VerticalAlignment.Center;
G2L["7"]["SortOrder"] = Enum.SortOrder.LayoutOrder;
G2L["7"]["TweenTime"] = 0.25;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate
G2L["8"] = Instance.new("Frame", G2L["6"]);
G2L["8"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["8"]["ClipsDescendants"] = true;
G2L["8"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["8"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["8"]["Name"] = [[DayBucketTemplate]];
G2L["8"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.UIListLayout
G2L["9"] = Instance.new("UIListLayout", G2L["8"]);
G2L["9"]["Padding"] = UDim.new(0, 12);
G2L["9"]["VerticalAlignment"] = Enum.VerticalAlignment.Center;
G2L["9"]["SortOrder"] = Enum.SortOrder.LayoutOrder;
G2L["9"]["FillDirection"] = Enum.FillDirection.Horizontal;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.UIPadding
G2L["a"] = Instance.new("UIPadding", G2L["8"]);
G2L["a"]["PaddingLeft"] = UDim.new(0, 12);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate
G2L["b"] = Instance.new("Frame", G2L["8"]);
G2L["b"]["ZIndex"] = 4;
G2L["b"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["b"]["Size"] = UDim2.new(0, 90, 0, 102);
G2L["b"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["b"]["Name"] = [[DayTemplate]];
G2L["b"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.FrameImage
G2L["c"] = Instance.new("ImageLabel", G2L["b"]);
G2L["c"]["ZIndex"] = 7;
G2L["c"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["c"]["ImageColor3"] = Color3.fromRGB(255, 94, 212);
G2L["c"]["Image"] = [[rbxassetid://2898171640]];
G2L["c"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["c"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["c"]["BackgroundTransparency"] = 1;
G2L["c"]["Name"] = [[FrameImage]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.MoneyIcon
G2L["d"] = Instance.new("ImageLabel", G2L["b"]);
G2L["d"]["ZIndex"] = 6;
G2L["d"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["d"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["d"]["Image"] = [[rbxassetid://6991531565]];
G2L["d"]["Size"] = UDim2.new(0, 86, 0, 68);
G2L["d"]["Visible"] = false;
G2L["d"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["d"]["BackgroundTransparency"] = 1;
G2L["d"]["Name"] = [[MoneyIcon]];
G2L["d"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.RewardLabel
G2L["e"] = Instance.new("TextLabel", G2L["b"]);
G2L["e"]["TextWrapped"] = true;
G2L["e"]["ZIndex"] = 8;
G2L["e"]["TextSize"] = 14;
G2L["e"]["TextScaled"] = true;
G2L["e"]["BackgroundColor3"] = Color3.fromRGB(0, 13, 255);
G2L["e"]["FontFace"] = Font.new([[rbxasset://fonts/families/Montserrat.json]], Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal);
G2L["e"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["e"]["BackgroundTransparency"] = 1;
G2L["e"]["AnchorPoint"] = Vector2.new(0.5, 1);
G2L["e"]["Size"] = UDim2.new(1, -2, 0, 16);
G2L["e"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["e"]["Text"] = [[Small Gift]];
G2L["e"]["Name"] = [[RewardLabel]];
G2L["e"]["Position"] = UDim2.new(0.5, 0, 1, -1);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.FrameFill
G2L["f"] = Instance.new("ImageLabel", G2L["b"]);
G2L["f"]["ZIndex"] = 5;
G2L["f"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["f"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["f"]["Image"] = [[rbxassetid://2898171579]];
G2L["f"]["Size"] = UDim2.new(1, -4, 1, -4);
G2L["f"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["f"]["BackgroundTransparency"] = 1;
G2L["f"]["Name"] = [[FrameFill]];
G2L["f"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.ClaimedFill
G2L["10"] = Instance.new("ImageLabel", G2L["b"]);
G2L["10"]["ZIndex"] = 8;
G2L["10"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["10"]["ImageTransparency"] = 1;
G2L["10"]["ImageColor3"] = Color3.fromRGB(58, 182, 75);
G2L["10"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["10"]["Image"] = [[rbxassetid://2898171579]];
G2L["10"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["10"]["Visible"] = false;
G2L["10"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["10"]["BackgroundTransparency"] = 1;
G2L["10"]["Name"] = [[ClaimedFill]];
G2L["10"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.ClaimedFill.Clipper
G2L["11"] = Instance.new("Frame", G2L["10"]);
G2L["11"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["11"]["ClipsDescendants"] = true;
G2L["11"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["11"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["11"]["Name"] = [[Clipper]];
G2L["11"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.ClaimedFill.Clipper.Checkmark
G2L["12"] = Instance.new("ImageLabel", G2L["11"]);
G2L["12"]["ZIndex"] = 7;
G2L["12"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["12"]["AnchorPoint"] = Vector2.new(0, 0.5);
G2L["12"]["Image"] = [[rbxassetid://2898171506]];
G2L["12"]["Size"] = UDim2.new(0, 79, 0, 78);
G2L["12"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["12"]["BackgroundTransparency"] = 1;
G2L["12"]["Name"] = [[Checkmark]];
G2L["12"]["Position"] = UDim2.new(0, 6, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.GiftIcon
G2L["13"] = Instance.new("ImageLabel", G2L["b"]);
G2L["13"]["ZIndex"] = 6;
G2L["13"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["13"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["13"]["Image"] = [[rbxassetid://2898171769]];
G2L["13"]["Size"] = UDim2.new(0, 76, 0, 64);
G2L["13"]["Visible"] = false;
G2L["13"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["13"]["BackgroundTransparency"] = 1;
G2L["13"]["Name"] = [[GiftIcon]];
G2L["13"]["Position"] = UDim2.new(0.5, 0, 0.5, 1);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.RadialPinstripe
G2L["14"] = Instance.new("ImageLabel", G2L["b"]);
G2L["14"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["14"]["ImageColor3"] = Color3.fromRGB(255, 0, 236);
G2L["14"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["14"]["Image"] = [[rbxassetid://2898324817]];
G2L["14"]["Size"] = UDim2.new(0, 133, 0, 133);
G2L["14"]["Visible"] = false;
G2L["14"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["14"]["BackgroundTransparency"] = 1;
G2L["14"]["Name"] = [[RadialPinstripe]];
G2L["14"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.StarsLabel
G2L["15"] = Instance.new("TextLabel", G2L["b"]);
G2L["15"]["TextWrapped"] = true;
G2L["15"]["ZIndex"] = 6;
G2L["15"]["TextSize"] = 14;
G2L["15"]["TextScaled"] = true;
G2L["15"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["15"]["FontFace"] = Font.new([[rbxasset://fonts/families/Montserrat.json]], Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal);
G2L["15"]["TextColor3"] = Color3.fromRGB(252, 177, 60);
G2L["15"]["BackgroundTransparency"] = 1;
G2L["15"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["15"]["Size"] = UDim2.new(1, -18, 0, 20);
G2L["15"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["15"]["Text"] = [[1111]];
G2L["15"]["Name"] = [[StarsLabel]];
G2L["15"]["Position"] = UDim2.new(0.5, 0, 0, -13);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.StarIcon
G2L["16"] = Instance.new("ImageLabel", G2L["b"]);
G2L["16"]["ZIndex"] = 6;
G2L["16"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["16"]["ImageColor3"] = Color3.fromRGB(252, 177, 60);
G2L["16"]["AnchorPoint"] = Vector2.new(1, 0.5);
G2L["16"]["Image"] = [[rbxassetid://4755042015]];
G2L["16"]["Size"] = UDim2.new(0, 16, 0, 16);
G2L["16"]["Visible"] = false;
G2L["16"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["16"]["BackgroundTransparency"] = 1;
G2L["16"]["Name"] = [[StarIcon]];
G2L["16"]["Position"] = UDim2.new(1, 0, 0, -13);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.ItemIcon
G2L["17"] = Instance.new("ImageLabel", G2L["b"]);
G2L["17"]["ZIndex"] = 6;
G2L["17"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["17"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["17"]["Image"] = [[rbxassetid://2898289028]];
G2L["17"]["Size"] = UDim2.new(0, 70, 0, 70);
G2L["17"]["Visible"] = false;
G2L["17"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["17"]["BackgroundTransparency"] = 1;
G2L["17"]["Name"] = [[ItemIcon]];
G2L["17"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.DaysList.DayBucketTemplate.DayTemplate.DayLabel
G2L["18"] = Instance.new("TextLabel", G2L["b"]);
G2L["18"]["TextWrapped"] = true;
G2L["18"]["ZIndex"] = 8;
G2L["18"]["TextSize"] = 14;
G2L["18"]["TextXAlignment"] = Enum.TextXAlignment.Left;
G2L["18"]["TextScaled"] = true;
G2L["18"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["18"]["FontFace"] = Font.new([[rbxasset://fonts/families/GothamSSm.json]], Enum.FontWeight.Bold, Enum.FontStyle.Normal);
G2L["18"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["18"]["BackgroundTransparency"] = 1;
G2L["18"]["Size"] = UDim2.new(0, 56, 0, 17);
G2L["18"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["18"]["Text"] = [[DAY 1]];
G2L["18"]["Name"] = [[DayLabel]];
G2L["18"]["Position"] = UDim2.new(0, 3, 0, 1);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.LeftArrowButtonContainer
G2L["19"] = Instance.new("Frame", G2L["5"]);
G2L["19"]["ZIndex"] = 2;
G2L["19"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["19"]["AnchorPoint"] = Vector2.new(0, 0.5);
G2L["19"]["Size"] = UDim2.new(0, 24, 0, 100);
G2L["19"]["Position"] = UDim2.new(0, 10, 0.5, 0);
G2L["19"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["19"]["Name"] = [[LeftArrowButtonContainer]];
G2L["19"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.LeftArrowButtonContainer.LeftArrowButton
G2L["1a"] = Instance.new("ImageButton", G2L["19"]);
G2L["1a"]["BackgroundTransparency"] = 1;
G2L["1a"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["1a"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["1a"]["Size"] = UDim2.new(0, 100, 0, 24);
G2L["1a"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["1a"]["Name"] = [[LeftArrowButton]];
G2L["1a"]["Rotation"] = -90;
G2L["1a"]["Position"] = UDim2.new(0.5, 0, 0.5, 1);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.LeftArrowButtonContainer.LeftArrowButton.InnerColor
G2L["1b"] = Instance.new("ImageLabel", G2L["1a"]);
G2L["1b"]["ZIndex"] = 3;
G2L["1b"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["1b"]["ImageColor3"] = Color3.fromRGB(255, 94, 212);
G2L["1b"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["1b"]["Image"] = [[rbxassetid://2615094545]];
G2L["1b"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["1b"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["1b"]["BackgroundTransparency"] = 1;
G2L["1b"]["Name"] = [[InnerColor]];
G2L["1b"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.LeftArrowButtonContainer.LeftArrowButton.Arrow
G2L["1c"] = Instance.new("ImageLabel", G2L["1a"]);
G2L["1c"]["ZIndex"] = 4;
G2L["1c"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["1c"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["1c"]["Image"] = [[rbxassetid://2615094557]];
G2L["1c"]["Size"] = UDim2.new(0, 50, 0, 26);
G2L["1c"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["1c"]["BackgroundTransparency"] = 1;
G2L["1c"]["Name"] = [[Arrow]];
G2L["1c"]["Position"] = UDim2.new(0.5, 4, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.RightArrowButtonContainer
G2L["1d"] = Instance.new("Frame", G2L["5"]);
G2L["1d"]["ZIndex"] = 2;
G2L["1d"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["1d"]["AnchorPoint"] = Vector2.new(1, 0.5);
G2L["1d"]["Size"] = UDim2.new(0, 24, 0, 100);
G2L["1d"]["Position"] = UDim2.new(1, -10, 0.5, 0);
G2L["1d"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["1d"]["Name"] = [[RightArrowButtonContainer]];
G2L["1d"]["LayoutOrder"] = 2;
G2L["1d"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.RightArrowButtonContainer.RightArrowButton
G2L["1e"] = Instance.new("ImageButton", G2L["1d"]);
G2L["1e"]["BackgroundTransparency"] = 1;
G2L["1e"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["1e"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["1e"]["Size"] = UDim2.new(0, 100, 0, 24);
G2L["1e"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["1e"]["Name"] = [[RightArrowButton]];
G2L["1e"]["Rotation"] = 90;
G2L["1e"]["Position"] = UDim2.new(0.5, 0, 0.5, -1);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.RightArrowButtonContainer.RightArrowButton.InnerColor
G2L["1f"] = Instance.new("ImageLabel", G2L["1e"]);
G2L["1f"]["ZIndex"] = 3;
G2L["1f"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["1f"]["ImageColor3"] = Color3.fromRGB(255, 94, 212);
G2L["1f"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["1f"]["Image"] = [[rbxassetid://2615094545]];
G2L["1f"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["1f"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["1f"]["BackgroundTransparency"] = 1;
G2L["1f"]["Name"] = [[InnerColor]];
G2L["1f"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.RightArrowButtonContainer.RightArrowButton.Arrow
G2L["20"] = Instance.new("ImageLabel", G2L["1e"]);
G2L["20"]["ZIndex"] = 4;
G2L["20"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["20"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["20"]["Image"] = [[rbxassetid://2615094557]];
G2L["20"]["Size"] = UDim2.new(0, 50, 0, 26);
G2L["20"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["20"]["BackgroundTransparency"] = 1;
G2L["20"]["Name"] = [[Arrow]];
G2L["20"]["Position"] = UDim2.new(0.5, 4, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.DaysListContainer.UIListLayout
G2L["21"] = Instance.new("UIListLayout", G2L["5"]);
G2L["21"]["HorizontalAlignment"] = Enum.HorizontalAlignment.Center;
G2L["21"]["VerticalAlignment"] = Enum.VerticalAlignment.Center;
G2L["21"]["SortOrder"] = Enum.SortOrder.LayoutOrder;
G2L["21"]["FillDirection"] = Enum.FillDirection.Horizontal;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.UIPadding
G2L["22"] = Instance.new("UIPadding", G2L["4"]);
G2L["22"]["PaddingTop"] = UDim.new(0, 6);
G2L["22"]["PaddingRight"] = UDim.new(0, 6);
G2L["22"]["PaddingLeft"] = UDim.new(0, 6);
G2L["22"]["PaddingBottom"] = UDim.new(0, 6);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons
G2L["23"] = Instance.new("Frame", G2L["4"]);
G2L["23"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["23"]["AnchorPoint"] = Vector2.new(0.5, 1);
G2L["23"]["Size"] = UDim2.new(0, 240, 0, 48);
G2L["23"]["Position"] = UDim2.new(0.5, 0, 1, -37);
G2L["23"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["23"]["Name"] = [[Buttons]];
G2L["23"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton
G2L["24"] = Instance.new("ImageButton", G2L["23"]);
G2L["24"]["Modal"] = true;
G2L["24"]["BackgroundTransparency"] = 1;
G2L["24"]["BackgroundColor3"] = Color3.fromRGB(249, 249, 249);
G2L["24"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["24"]["Size"] = UDim2.new(0, 180, 1, 0);
G2L["24"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["24"]["Name"] = [[ClaimButton]];
G2L["24"]["Position"] = UDim2.new(0, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Face
G2L["25"] = Instance.new("ImageLabel", G2L["24"]);
G2L["25"]["ZIndex"] = 2;
G2L["25"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["25"]["Size"] = UDim2.new(1, 0, 0.8, 0);
G2L["25"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["25"]["BackgroundTransparency"] = 1;
G2L["25"]["Name"] = [[Face]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Face.Colors
G2L["26"] = Instance.new("Frame", G2L["25"]);
G2L["26"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["26"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["26"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["26"]["Name"] = [[Colors]];
G2L["26"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Face.Colors.Base
G2L["27"] = Instance.new("ImageLabel", G2L["26"]);
G2L["27"]["SliceCenter"] = Rect.new(6, 6, 29, 21);
G2L["27"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["27"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["27"]["ImageColor3"] = Color3.fromRGB(75, 199, 86);
G2L["27"]["Image"] = [[rbxassetid://7445833582]];
G2L["27"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["27"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["27"]["BackgroundTransparency"] = 1;
G2L["27"]["Name"] = [[Base]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Face.Colors.Highlight
G2L["28"] = Instance.new("ImageLabel", G2L["26"]);
G2L["28"]["ZIndex"] = 2;
G2L["28"]["SliceCenter"] = Rect.new(9, 9, 28, 20);
G2L["28"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["28"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["28"]["ImageColor3"] = Color3.fromRGB(141, 217, 101);
G2L["28"]["Image"] = [[rbxassetid://7445833936]];
G2L["28"]["Size"] = UDim2.new(1, -2, 1, -2);
G2L["28"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["28"]["BackgroundTransparency"] = 1;
G2L["28"]["Name"] = [[Highlight]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Face.TextLabel
G2L["29"] = Instance.new("TextLabel", G2L["25"]);
G2L["29"]["TextWrapped"] = true;
G2L["29"]["TextSize"] = 14;
G2L["29"]["TextScaled"] = true;
G2L["29"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["29"]["FontFace"] = Font.new([[rbxasset://fonts/families/Montserrat.json]], Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal);
G2L["29"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["29"]["BackgroundTransparency"] = 1;
G2L["29"]["AnchorPoint"] = Vector2.new(0, 0.5);
G2L["29"]["Size"] = UDim2.new(1, -4, 1, -12);
G2L["29"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["29"]["Text"] = [[CLAIM!]];
G2L["29"]["Position"] = UDim2.new(0, 2, 0.5, 1);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Shadow
G2L["2a"] = Instance.new("ImageLabel", G2L["24"]);
G2L["2a"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["2a"]["Size"] = UDim2.new(1, 0, 0.8, 0);
G2L["2a"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["2a"]["BackgroundTransparency"] = 1;
G2L["2a"]["Name"] = [[Shadow]];
G2L["2a"]["Position"] = UDim2.new(0, 0, 0.2, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Shadow.Colors
G2L["2b"] = Instance.new("Frame", G2L["2a"]);
G2L["2b"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["2b"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["2b"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["2b"]["Name"] = [[Colors]];
G2L["2b"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Shadow.Colors.Left
G2L["2c"] = Instance.new("ImageLabel", G2L["2b"]);
G2L["2c"]["ZIndex"] = 2;
G2L["2c"]["SliceCenter"] = Rect.new(0, 7, 16, 21);
G2L["2c"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["2c"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["2c"]["ImageColor3"] = Color3.fromRGB(75, 199, 86);
G2L["2c"]["Image"] = [[rbxassetid://7445833791]];
G2L["2c"]["Size"] = UDim2.new(0, 16, 1, 0);
G2L["2c"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["2c"]["BackgroundTransparency"] = 1;
G2L["2c"]["Name"] = [[Left]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Shadow.Colors.Middle
G2L["2d"] = Instance.new("ImageLabel", G2L["2b"]);
G2L["2d"]["SliceCenter"] = Rect.new(6, 6, 29, 21);
G2L["2d"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["2d"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["2d"]["ImageColor3"] = Color3.fromRGB(44, 166, 70);
G2L["2d"]["AnchorPoint"] = Vector2.new(0, 1);
G2L["2d"]["Image"] = [[rbxassetid://7445833582]];
G2L["2d"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["2d"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["2d"]["BackgroundTransparency"] = 1;
G2L["2d"]["Name"] = [[Middle]];
G2L["2d"]["Position"] = UDim2.new(0, 0, 1, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Shadow.Colors.Right
G2L["2e"] = Instance.new("ImageLabel", G2L["2b"]);
G2L["2e"]["ZIndex"] = 2;
G2L["2e"]["SliceCenter"] = Rect.new(0, 7, 16, 21);
G2L["2e"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["2e"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["2e"]["ImageColor3"] = Color3.fromRGB(33, 141, 54);
G2L["2e"]["AnchorPoint"] = Vector2.new(1, 0);
G2L["2e"]["Image"] = [[rbxassetid://7445834073]];
G2L["2e"]["Size"] = UDim2.new(0, 16, 1, 0);
G2L["2e"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["2e"]["BackgroundTransparency"] = 1;
G2L["2e"]["Name"] = [[Right]];
G2L["2e"]["Position"] = UDim2.new(1, 0, 0, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton
G2L["2f"] = Instance.new("ImageButton", G2L["23"]);
G2L["2f"]["BackgroundTransparency"] = 1;
G2L["2f"]["BackgroundColor3"] = Color3.fromRGB(249, 249, 249);
G2L["2f"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["2f"]["Size"] = UDim2.new(0, 52, 1, 0);
G2L["2f"]["LayoutOrder"] = 2;
G2L["2f"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["2f"]["Name"] = [[MilestonesButton]];
G2L["2f"]["Position"] = UDim2.new(0.715, 0, 0.76, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Face
G2L["30"] = Instance.new("ImageLabel", G2L["2f"]);
G2L["30"]["ZIndex"] = 2;
G2L["30"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["30"]["Size"] = UDim2.new(1, 0, 0.8, 0);
G2L["30"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["30"]["BackgroundTransparency"] = 1;
G2L["30"]["Name"] = [[Face]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Face.Colors
G2L["31"] = Instance.new("Frame", G2L["30"]);
G2L["31"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["31"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["31"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["31"]["Name"] = [[Colors]];
G2L["31"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Face.Colors.Base
G2L["32"] = Instance.new("ImageLabel", G2L["31"]);
G2L["32"]["SliceCenter"] = Rect.new(6, 6, 29, 21);
G2L["32"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["32"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["32"]["ImageColor3"] = Color3.fromRGB(248, 148, 31);
G2L["32"]["Image"] = [[rbxassetid://7445833582]];
G2L["32"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["32"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["32"]["BackgroundTransparency"] = 1;
G2L["32"]["Name"] = [[Base]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Face.Colors.Highlight
G2L["33"] = Instance.new("ImageLabel", G2L["31"]);
G2L["33"]["ZIndex"] = 2;
G2L["33"]["SliceCenter"] = Rect.new(9, 9, 28, 20);
G2L["33"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["33"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["33"]["ImageColor3"] = Color3.fromRGB(252, 177, 60);
G2L["33"]["Image"] = [[rbxassetid://7445833936]];
G2L["33"]["Size"] = UDim2.new(1, -2, 1, -2);
G2L["33"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["33"]["BackgroundTransparency"] = 1;
G2L["33"]["Name"] = [[Highlight]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Face.StarIcon
G2L["34"] = Instance.new("ImageLabel", G2L["30"]);
G2L["34"]["ZIndex"] = 6;
G2L["34"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["34"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["34"]["Image"] = [[rbxassetid://4771960637]];
G2L["34"]["Size"] = UDim2.new(0, 24, 0, 24);
G2L["34"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["34"]["BackgroundTransparency"] = 1;
G2L["34"]["Name"] = [[StarIcon]];
G2L["34"]["Position"] = UDim2.new(0.5, 1, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Shadow
G2L["35"] = Instance.new("ImageLabel", G2L["2f"]);
G2L["35"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["35"]["Size"] = UDim2.new(1, 0, 0.8, 0);
G2L["35"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["35"]["BackgroundTransparency"] = 1;
G2L["35"]["Name"] = [[Shadow]];
G2L["35"]["Position"] = UDim2.new(0, 0, 0.2, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Shadow.Colors
G2L["36"] = Instance.new("Frame", G2L["35"]);
G2L["36"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["36"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["36"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["36"]["Name"] = [[Colors]];
G2L["36"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Shadow.Colors.Left
G2L["37"] = Instance.new("ImageLabel", G2L["36"]);
G2L["37"]["ZIndex"] = 2;
G2L["37"]["SliceCenter"] = Rect.new(0, 7, 16, 21);
G2L["37"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["37"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["37"]["ImageColor3"] = Color3.fromRGB(248, 148, 31);
G2L["37"]["Image"] = [[rbxassetid://7445833791]];
G2L["37"]["Size"] = UDim2.new(0, 16, 1, 0);
G2L["37"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["37"]["BackgroundTransparency"] = 1;
G2L["37"]["Name"] = [[Left]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Shadow.Colors.Middle
G2L["38"] = Instance.new("ImageLabel", G2L["36"]);
G2L["38"]["SliceCenter"] = Rect.new(6, 6, 29, 21);
G2L["38"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["38"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["38"]["ImageColor3"] = Color3.fromRGB(240, 115, 61);
G2L["38"]["AnchorPoint"] = Vector2.new(0, 1);
G2L["38"]["Image"] = [[rbxassetid://7445833582]];
G2L["38"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["38"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["38"]["BackgroundTransparency"] = 1;
G2L["38"]["Name"] = [[Middle]];
G2L["38"]["Position"] = UDim2.new(0, 0, 1, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.MilestonesButton.Shadow.Colors.Right
G2L["39"] = Instance.new("ImageLabel", G2L["36"]);
G2L["39"]["ZIndex"] = 2;
G2L["39"]["SliceCenter"] = Rect.new(0, 7, 16, 21);
G2L["39"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["39"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["39"]["ImageColor3"] = Color3.fromRGB(225, 99, 28);
G2L["39"]["AnchorPoint"] = Vector2.new(1, 0);
G2L["39"]["Image"] = [[rbxassetid://7445834073]];
G2L["39"]["Size"] = UDim2.new(0, 16, 1, 0);
G2L["39"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["39"]["BackgroundTransparency"] = 1;
G2L["39"]["Name"] = [[Right]];
G2L["39"]["Position"] = UDim2.new(1, 0, 0, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.UIListLayout
G2L["3a"] = Instance.new("UIListLayout", G2L["23"]);
G2L["3a"]["HorizontalAlignment"] = Enum.HorizontalAlignment.Center;
G2L["3a"]["Padding"] = UDim.new(0, 8);
G2L["3a"]["VerticalAlignment"] = Enum.VerticalAlignment.Center;
G2L["3a"]["SortOrder"] = Enum.SortOrder.LayoutOrder;
G2L["3a"]["FillDirection"] = Enum.FillDirection.Horizontal;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton
G2L["3b"] = Instance.new("ImageButton", G2L["23"]);
G2L["3b"]["Modal"] = true;
G2L["3b"]["BackgroundTransparency"] = 1;
G2L["3b"]["BackgroundColor3"] = Color3.fromRGB(249, 249, 249);
G2L["3b"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["3b"]["Size"] = UDim2.new(0, 250, 1, 0);
G2L["3b"]["LayoutOrder"] = 1;
G2L["3b"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["3b"]["Name"] = [[ClaimAdButton]];
G2L["3b"]["Position"] = UDim2.new(0, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face
G2L["3c"] = Instance.new("ImageLabel", G2L["3b"]);
G2L["3c"]["ZIndex"] = 2;
G2L["3c"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["3c"]["Size"] = UDim2.new(1, 0, 0.8, 0);
G2L["3c"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["3c"]["BackgroundTransparency"] = 1;
G2L["3c"]["Name"] = [[Face]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Colors
G2L["3d"] = Instance.new("Frame", G2L["3c"]);
G2L["3d"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["3d"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["3d"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["3d"]["Name"] = [[Colors]];
G2L["3d"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Colors.Base
G2L["3e"] = Instance.new("ImageLabel", G2L["3d"]);
G2L["3e"]["SliceCenter"] = Rect.new(6, 6, 29, 21);
G2L["3e"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["3e"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["3e"]["ImageColor3"] = Color3.fromRGB(158, 55, 255);
G2L["3e"]["Image"] = [[rbxassetid://7445833582]];
G2L["3e"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["3e"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["3e"]["BackgroundTransparency"] = 1;
G2L["3e"]["Name"] = [[Base]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Colors.Highlight
G2L["3f"] = Instance.new("ImageLabel", G2L["3d"]);
G2L["3f"]["ZIndex"] = 2;
G2L["3f"]["SliceCenter"] = Rect.new(9, 9, 28, 20);
G2L["3f"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["3f"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["3f"]["ImageColor3"] = Color3.fromRGB(186, 113, 255);
G2L["3f"]["Image"] = [[rbxassetid://7445833936]];
G2L["3f"]["Size"] = UDim2.new(1, -2, 1, -2);
G2L["3f"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["3f"]["BackgroundTransparency"] = 1;
G2L["3f"]["Name"] = [[Highlight]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Contents
G2L["40"] = Instance.new("Frame", G2L["3c"]);
G2L["40"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["40"]["AnchorPoint"] = Vector2.new(0, 0.5);
G2L["40"]["Size"] = UDim2.new(1, -4, 1, -6);
G2L["40"]["Position"] = UDim2.new(0, 2, 0.5, 1);
G2L["40"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["40"]["Name"] = [[Contents]];
G2L["40"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Contents.TextLabel
G2L["41"] = Instance.new("TextLabel", G2L["40"]);
G2L["41"]["TextWrapped"] = true;
G2L["41"]["LineHeight"] = 0.7;
G2L["41"]["TextSize"] = 14;
G2L["41"]["TextScaled"] = true;
G2L["41"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["41"]["FontFace"] = Font.new([[rbxasset://fonts/families/Montserrat.json]], Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal);
G2L["41"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["41"]["BackgroundTransparency"] = 1;
G2L["41"]["RichText"] = true;
G2L["41"]["Size"] = UDim2.new(0, 0, 1, 0);
G2L["41"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["41"]["Text"] = [[<font size="10">WATCH AD</font>
<font size="14">CLAIM 2X REWARD</font>]];
G2L["41"]["LayoutOrder"] = 1;
G2L["41"]["AutomaticSize"] = Enum.AutomaticSize.X;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Contents.TextLabel.UIFlexItem
G2L["42"] = Instance.new("UIFlexItem", G2L["41"]);
G2L["42"]["FlexMode"] = Enum.UIFlexMode.Shrink;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Contents.UIListLayout
G2L["43"] = Instance.new("UIListLayout", G2L["40"]);
G2L["43"]["HorizontalAlignment"] = Enum.HorizontalAlignment.Center;
G2L["43"]["Padding"] = UDim.new(0, 2);
G2L["43"]["SortOrder"] = Enum.SortOrder.LayoutOrder;
G2L["43"]["FillDirection"] = Enum.FillDirection.Horizontal;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Contents.Frame
G2L["44"] = Instance.new("Frame", G2L["40"]);
G2L["44"]["BorderSizePixel"] = 0;
G2L["44"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["44"]["Size"] = UDim2.new(0, 32, 0, 32);
G2L["44"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["44"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Contents.Frame.ImageLabel
G2L["45"] = Instance.new("ImageLabel", G2L["44"]);
G2L["45"]["BorderSizePixel"] = 0;
G2L["45"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["45"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["45"]["Image"] = [[rbxassetid://88724770246529]];
G2L["45"]["Size"] = UDim2.new(0, 28, 0, 28);
G2L["45"]["BorderColor3"] = Color3.fromRGB(0, 0, 0);
G2L["45"]["BackgroundTransparency"] = 1;
G2L["45"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Face.Contents.UIPadding
G2L["46"] = Instance.new("UIPadding", G2L["40"]);
G2L["46"]["PaddingRight"] = UDim.new(0, 4);
G2L["46"]["PaddingLeft"] = UDim.new(0, 4);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Shadow
G2L["47"] = Instance.new("ImageLabel", G2L["3b"]);
G2L["47"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["47"]["Size"] = UDim2.new(1, 0, 0.8, 0);
G2L["47"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["47"]["BackgroundTransparency"] = 1;
G2L["47"]["Name"] = [[Shadow]];
G2L["47"]["Position"] = UDim2.new(0, 0, 0.2, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Shadow.Colors
G2L["48"] = Instance.new("Frame", G2L["47"]);
G2L["48"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["48"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["48"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["48"]["Name"] = [[Colors]];
G2L["48"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Shadow.Colors.Left
G2L["49"] = Instance.new("ImageLabel", G2L["48"]);
G2L["49"]["ZIndex"] = 2;
G2L["49"]["SliceCenter"] = Rect.new(0, 7, 16, 21);
G2L["49"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["49"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["49"]["ImageColor3"] = Color3.fromRGB(158, 55, 255);
G2L["49"]["Image"] = [[rbxassetid://7445833791]];
G2L["49"]["Size"] = UDim2.new(0, 16, 1, 0);
G2L["49"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["49"]["BackgroundTransparency"] = 1;
G2L["49"]["Name"] = [[Left]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Shadow.Colors.Middle
G2L["4a"] = Instance.new("ImageLabel", G2L["48"]);
G2L["4a"]["SliceCenter"] = Rect.new(6, 6, 29, 21);
G2L["4a"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["4a"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["4a"]["ImageColor3"] = Color3.fromRGB(131, 34, 221);
G2L["4a"]["AnchorPoint"] = Vector2.new(0, 1);
G2L["4a"]["Image"] = [[rbxassetid://7445833582]];
G2L["4a"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["4a"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["4a"]["BackgroundTransparency"] = 1;
G2L["4a"]["Name"] = [[Middle]];
G2L["4a"]["Position"] = UDim2.new(0, 0, 1, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.Buttons.ClaimAdButton.Shadow.Colors.Right
G2L["4b"] = Instance.new("ImageLabel", G2L["48"]);
G2L["4b"]["ZIndex"] = 2;
G2L["4b"]["SliceCenter"] = Rect.new(0, 7, 16, 21);
G2L["4b"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["4b"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["4b"]["ImageColor3"] = Color3.fromRGB(104, 4, 192);
G2L["4b"]["AnchorPoint"] = Vector2.new(1, 0);
G2L["4b"]["Image"] = [[rbxassetid://7445834073]];
G2L["4b"]["Size"] = UDim2.new(0, 16, 1, 0);
G2L["4b"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["4b"]["BackgroundTransparency"] = 1;
G2L["4b"]["Name"] = [[Right]];
G2L["4b"]["Position"] = UDim2.new(1, 0, 0, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea
G2L["4c"] = Instance.new("Frame", G2L["4"]);
G2L["4c"]["BackgroundColor3"] = Color3.fromRGB(249, 249, 249);
G2L["4c"]["AnchorPoint"] = Vector2.new(0.5, 0);
G2L["4c"]["Size"] = UDim2.new(1, -40, 0, 30);
G2L["4c"]["Position"] = UDim2.new(0.5, 0, 0, -8);
G2L["4c"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["4c"]["Name"] = [[TaglineArea]];
G2L["4c"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.Tagline
G2L["4d"] = Instance.new("TextLabel", G2L["4c"]);
G2L["4d"]["TextWrapped"] = true;
G2L["4d"]["TextSize"] = 35;
G2L["4d"]["TextScaled"] = true;
G2L["4d"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["4d"]["FontFace"] = Font.new([[rbxasset://fonts/families/GothamSSm.json]], Enum.FontWeight.Bold, Enum.FontStyle.Normal);
G2L["4d"]["TextColor3"] = Color3.fromRGB(0, 0, 0);
G2L["4d"]["BackgroundTransparency"] = 1;
G2L["4d"]["Size"] = UDim2.new(1, -35, 1, 0);
G2L["4d"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["4d"]["Text"] = [[PLAY EVERY DAY TO GET BETTER PRIZES!]];
G2L["4d"]["Name"] = [[Tagline]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton
G2L["4e"] = Instance.new("ImageButton", G2L["4c"]);
G2L["4e"]["Visible"] = false;
G2L["4e"]["BackgroundTransparency"] = 1;
G2L["4e"]["BackgroundColor3"] = Color3.fromRGB(249, 249, 249);
G2L["4e"]["AnchorPoint"] = Vector2.new(1, 0.5);
G2L["4e"]["Size"] = UDim2.new(0, 30, 0, 30);
G2L["4e"]["LayoutOrder"] = 1;
G2L["4e"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["4e"]["Name"] = [[EarlyClaimExplainerButton]];
G2L["4e"]["Position"] = UDim2.new(1, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Face
G2L["4f"] = Instance.new("ImageLabel", G2L["4e"]);
G2L["4f"]["ZIndex"] = 2;
G2L["4f"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["4f"]["Size"] = UDim2.new(1, 0, 0.8, 0);
G2L["4f"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["4f"]["BackgroundTransparency"] = 1;
G2L["4f"]["Name"] = [[Face]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Face.Colors
G2L["50"] = Instance.new("Frame", G2L["4f"]);
G2L["50"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["50"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["50"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["50"]["Name"] = [[Colors]];
G2L["50"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Face.Colors.Base
G2L["51"] = Instance.new("ImageLabel", G2L["50"]);
G2L["51"]["SliceCenter"] = Rect.new(6, 6, 29, 21);
G2L["51"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["51"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["51"]["ImageColor3"] = Color3.fromRGB(248, 148, 31);
G2L["51"]["Image"] = [[rbxassetid://7445833582]];
G2L["51"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["51"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["51"]["BackgroundTransparency"] = 1;
G2L["51"]["Name"] = [[Base]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Face.Colors.Highlight
G2L["52"] = Instance.new("ImageLabel", G2L["50"]);
G2L["52"]["ZIndex"] = 2;
G2L["52"]["SliceCenter"] = Rect.new(9, 9, 28, 20);
G2L["52"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["52"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["52"]["ImageColor3"] = Color3.fromRGB(252, 177, 60);
G2L["52"]["Image"] = [[rbxassetid://7445833936]];
G2L["52"]["Size"] = UDim2.new(1, -2, 1, -2);
G2L["52"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["52"]["BackgroundTransparency"] = 1;
G2L["52"]["Name"] = [[Highlight]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Face.TextLabel
G2L["53"] = Instance.new("TextLabel", G2L["4f"]);
G2L["53"]["TextWrapped"] = true;
G2L["53"]["TextSize"] = 20;
G2L["53"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["53"]["FontFace"] = Font.new([[rbxasset://fonts/families/Montserrat.json]], Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal);
G2L["53"]["TextColor3"] = Color3.fromRGB(255, 255, 255);
G2L["53"]["BackgroundTransparency"] = 1;
G2L["53"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["53"]["Size"] = UDim2.new(1, -4, 1, -4);
G2L["53"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["53"]["Text"] = [[?]];
G2L["53"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Shadow
G2L["54"] = Instance.new("ImageLabel", G2L["4e"]);
G2L["54"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["54"]["Size"] = UDim2.new(1, 0, 0.8, 0);
G2L["54"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["54"]["BackgroundTransparency"] = 1;
G2L["54"]["Name"] = [[Shadow]];
G2L["54"]["Position"] = UDim2.new(0, 0, 0.2, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Shadow.Colors
G2L["55"] = Instance.new("Frame", G2L["54"]);
G2L["55"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["55"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["55"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["55"]["Name"] = [[Colors]];
G2L["55"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Shadow.Colors.Left
G2L["56"] = Instance.new("ImageLabel", G2L["55"]);
G2L["56"]["ZIndex"] = 2;
G2L["56"]["SliceCenter"] = Rect.new(0, 7, 16, 21);
G2L["56"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["56"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["56"]["ImageColor3"] = Color3.fromRGB(248, 148, 31);
G2L["56"]["Image"] = [[rbxassetid://7445833791]];
G2L["56"]["Size"] = UDim2.new(0, 16, 1, 0);
G2L["56"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["56"]["BackgroundTransparency"] = 1;
G2L["56"]["Name"] = [[Left]];


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Shadow.Colors.Middle
G2L["57"] = Instance.new("ImageLabel", G2L["55"]);
G2L["57"]["SliceCenter"] = Rect.new(6, 6, 29, 21);
G2L["57"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["57"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["57"]["ImageColor3"] = Color3.fromRGB(240, 115, 61);
G2L["57"]["AnchorPoint"] = Vector2.new(0, 1);
G2L["57"]["Image"] = [[rbxassetid://7445833582]];
G2L["57"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["57"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["57"]["BackgroundTransparency"] = 1;
G2L["57"]["Name"] = [[Middle]];
G2L["57"]["Position"] = UDim2.new(0, 0, 1, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.EarlyClaimExplainerButton.Shadow.Colors.Right
G2L["58"] = Instance.new("ImageLabel", G2L["55"]);
G2L["58"]["ZIndex"] = 2;
G2L["58"]["SliceCenter"] = Rect.new(0, 7, 16, 21);
G2L["58"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["58"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["58"]["ImageColor3"] = Color3.fromRGB(225, 99, 28);
G2L["58"]["AnchorPoint"] = Vector2.new(1, 0);
G2L["58"]["Image"] = [[rbxassetid://7445834073]];
G2L["58"]["Size"] = UDim2.new(0, 16, 1, 0);
G2L["58"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["58"]["BackgroundTransparency"] = 1;
G2L["58"]["Name"] = [[Right]];
G2L["58"]["Position"] = UDim2.new(1, 0, 0, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Body.TaglineArea.UIListLayout
G2L["59"] = Instance.new("UIListLayout", G2L["4c"]);
G2L["59"]["HorizontalAlignment"] = Enum.HorizontalAlignment.Center;
G2L["59"]["Padding"] = UDim.new(0, 5);
G2L["59"]["VerticalAlignment"] = Enum.VerticalAlignment.Center;
G2L["59"]["SortOrder"] = Enum.SortOrder.LayoutOrder;
G2L["59"]["FillDirection"] = Enum.FillDirection.Horizontal;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Header
G2L["5a"] = Instance.new("Frame", G2L["2"]);
G2L["5a"]["ZIndex"] = 4;
G2L["5a"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["5a"]["Size"] = UDim2.new(1, 0, 0, 40);
G2L["5a"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["5a"]["Name"] = [[Header]];
G2L["5a"]["BackgroundTransparency"] = 1;


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Header.NotebookSpiral
G2L["5b"] = Instance.new("ImageLabel", G2L["5a"]);
G2L["5b"]["ZIndex"] = 4;
G2L["5b"]["ScaleType"] = Enum.ScaleType.Tile;
G2L["5b"]["BackgroundColor3"] = Color3.fromRGB(255, 255, 255);
G2L["5b"]["AnchorPoint"] = Vector2.new(0.5, 1);
G2L["5b"]["Image"] = [[rbxassetid://2898171832]];
G2L["5b"]["TileSize"] = UDim2.new(0, 19, 1, 0);
G2L["5b"]["Size"] = UDim2.new(0, 542, 0, 50);
G2L["5b"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["5b"]["BackgroundTransparency"] = 1;
G2L["5b"]["Name"] = [[NotebookSpiral]];
G2L["5b"]["Position"] = UDim2.new(0.5, 1, 0.78, 0);


-- ReplicatedStorage.RawUI.DailyLoginApp.Frame.Foreground
G2L["5c"] = Instance.new("ImageLabel", G2L["2"]);
G2L["5c"]["ZIndex"] = 3;
G2L["5c"]["SliceCenter"] = Rect.new(8, 8, 204, 178);
G2L["5c"]["ScaleType"] = Enum.ScaleType.Slice;
G2L["5c"]["BackgroundColor3"] = Color3.fromRGB(249, 249, 249);
G2L["5c"]["AnchorPoint"] = Vector2.new(0.5, 0.5);
G2L["5c"]["Image"] = [[rbxassetid://2898228283]];
G2L["5c"]["Size"] = UDim2.new(1, 0, 1, 0);
G2L["5c"]["BorderColor3"] = Color3.fromRGB(28, 43, 54);
G2L["5c"]["BackgroundTransparency"] = 1;
G2L["5c"]["Name"] = [[Foreground]];
G2L["5c"]["Position"] = UDim2.new(0.5, 0, 0.5, 0);

    local screenGui = G2L["1"]
    screenGui.Enabled = true  -- UIManager will enable/disable it

    -- Inject into UI_Resources so UIManager.wrap works
    if UI_Resources then
        local existing = UI_Resources:FindFirstChild("DailyLoginApp")
        if existing then existing:Destroy() end
        screenGui.Parent = UI_Resources
    else
        screenGui.Parent = PlayerGui
    end

    -- ── Step 2: inject DailyLoginApp ModuleScript into UIManager's Apps ────
    -- Find the Apps folder UIManager uses
    local appsFolder = nil
    pcall(function()
        appsFolder = game.ReplicatedStorage.ClientModules.Core.UIManager.Apps
    end)

    -- Build a fake module that returns the DailyLoginApp class
    -- We do this by directly registering via UIManager.wrap + start pattern
    local load2 = fsysLoad
    local v2  = (function() local ok,m=pcall(load2,"ClientData")       return ok and m or {get=function()return{}end,register_callback_plus_existing=function()end,predict=function()end} end)()
    local v3  = ScriptUtil
    local v4  = (function() local ok,m=pcall(load2,"RouterClient")     return ok and m or {get=function()return{FireServer=function()end,InvokeServer=function()end,OnClientEvent={Connect=function()end}} end,get_event=function()return{OnClientEvent={Connect=function()end}}end} end)()
    local v5x = (function() local ok,m=pcall(load2,"XboxSupport")      return ok and m or {quick_watch=function()end} end)()
    local v6x = (function() local ok,m=pcall(load2,"Class")            return ok and m or function(n,b) local t={ClassName=n} t.__index=t; setmetatable(t,{__index=b,__call=function(cls,...) return setmetatable({UIManager=UIManager,ClassName=n},t) end}); return t end end)()
    local v7x = (function() local ok,m=pcall(load2,"ColorThemeManager") return ok and m or {get_theme_color=function()return"pink"end,lookup=function()return Color3.new(1,1,1)end,lookup_specific_color=function()return Color3.new(1,1,1)end} end)()
    local v8x = DailyLoginDB
    local v9x = InventoryDB
    local v10x= (function() local ok,m=pcall(load2,"SoundPlayer")      return ok and m or {FX={play=function()end},Interface={play=function()end}} end)()
    local v11x= RewardedAdsHelper
    local v12x= RewardedAdsAB
    local v13x= CloudValues
    local v14x= (function() local ok,m=pcall(load2,"package:Promise")  return ok and m or {try=function(f)local ok2,r=pcall(f);local t={};function t:timeout()return t end;function t:await()end;return t end,resolve=function()local t={};function t:andThen()return t end;return t end} end)()
    local TS2 = game:GetService("TweenService")
    local RS2 = game:GetService("RunService")
    local PL2 = game:GetService("Players")

    local icons = {
        day_2={Image="rbxassetid://6991531524",Size=UDim2.new(0,84,0,68),Position=UDim2.new(0.5,0,0.5,3)},
        day_3={Image="rbxassetid://6991531421",Size=UDim2.new(0,84,0,68),Position=UDim2.new(0.5,0,0.5,3)},
        day_4={Image="rbxassetid://6991531380",Size=UDim2.new(0,84,0,68),Position=UDim2.new(0.5,0,0.5,3)},
        day_0={Image="rbxassetid://6991531327",Size=UDim2.new(0,84,0,68),Position=UDim2.new(0.5,0,0.5,3)},
    }
    local function use_alt()
        if type(v12x.get_group)=="function" then
            return v12x:get_group(PL2.LocalPlayer)=="rewarded_ads_on"
        end
        return false
    end

    local UIBaseApp = (function() local ok,m=pcall(load2,"UIBaseApp") return ok and m or {} end)()
    local app = setmetatable({}, {__index=UIBaseApp})
    app.ClassName = "DailyLoginApp"
    app.UIManager = UIManager
    app.instance  = screenGui

    -- All UIBaseApp stubs
    function app:can_set_app_visibility() return true end
    function app:get_start_order() return 0 end
    function app:set_visibility(v) if v then self:show() else self:hide() end end

    function app:highlight_day_frame(p2)
        local clone=p2.FrameFill:Clone(); clone.Name="FrameImageShine"
        clone.ImageTransparency=1; clone.ImageColor3=Color3.fromRGB(255,255,255)
        clone.Size=UDim2.new(1,0,1,0); clone.ZIndex=p2.FrameImage.ZIndex+1; clone.Parent=p2
        spawn(function()
            while self.visible and self.claimable and p2.Parent~=nil do
                clone.ImageTransparency=1-(math.sin(tick()*2)/2+0.5)*0.6
                RS2.Heartbeat:Wait()
            end
            clone.ImageTransparency=1
        end)
    end
    function app:animate_gift_day_frame(p4)
        local rp=p4.RadialPinstripe; local spinning=false; local n=0
        spawn(function()
            while self.visible and p4.Parent~=nil do
                if p4:IsDescendantOf(self.page_layout.CurrentPage) then
                    if not spinning then spinning=true; n=tick()+0.175 end
                    rp.Rotation=tick()>n and tick()*10%360 or 0
                elseif spinning then spinning=false; rp.Rotation=0 end
                RS2.Heartbeat:Wait()
            end
        end)
    end
    function app:clear_day_list()
        for _,v in pairs(self.day_frames) do pcall(function()v:Destroy()end) end
        self.day_frames={}
    end
    function app:_convert_yellow_frame_to_purple(p7)
        local col=v7x.get_theme_color()=="yellow" and v7x.lookup_specific_color("purple","saturated") or v7x.lookup_specific_color("yellow","saturated")
        p7.FrameImage.ImageColor3=col; p7.RadialPinstripe.ImageColor3=col
    end
    function app:refresh_day_list()
        self:clear_day_list()
        local off=(self.streak-1)%v8x.week_length
        if self.streak<v8x.week_length then off=self.streak-1 end
        for i=1,v8x.month_length do
            local day=i-1+self.streak-off
            local clone=self.day_template:Clone()
            clone.Name="Day"..day; clone.LayoutOrder=day
            local reward=v8x.get_reward_for_day(day,use_alt())
            if reward.reward_type=="gift" then
                local g=v9x.gifts and v9x.gifts[reward.gift_type]
                clone.RadialPinstripe.Visible=true
                clone.RewardLabel.Text=g and g.name or "Gift"
                clone.GiftIcon.Visible=true; self:animate_gift_day_frame(clone); self:_convert_yellow_frame_to_purple(clone)
            elseif reward.reward_type=="money" then
                clone.RewardLabel.Text="$"..reward.amount; clone.MoneyIcon.Visible=true
                local ic=icons["day_"..i%v8x.week_length]
                if ic then for k,v in pairs(ic) do clone.MoneyIcon[k]=v end end
            elseif reward.reward_type=="item" then
                local cat=v9x[reward.item_category]; local it=cat and cat[reward.item_id]
                if it then clone.RewardLabel.Text=it.name; clone.ItemIcon.Visible=true; clone.ItemIcon.Image=it.image end
                self:_convert_yellow_frame_to_purple(clone)
            end
            if reward.stars==1 then clone.StarsLabel.Visible=false
            else clone.StarsLabel.Text=reward.stars.." STARS" end
            if day==self.streak then
                clone.DayLabel.Text="TODAY"
                if self.claimable then self:highlight_day_frame(clone) else self:mark_day_frame_as_claimed(clone) end
                self.today_frame=clone
            else clone.DayLabel.Text="DAY "..day end
            if day<self.streak then self:mark_day_frame_as_claimed(clone) end
            clone.Visible=true
            clone.Parent=self.day_buckets[math.ceil(i/v8x.week_length)]
            self.day_frames[i]=clone
        end
    end
    function app:mark_day_frame_as_claimed(p)
        p.ClaimedFill.Visible=true; p.ClaimedFill.ImageTransparency=0.4
        p.ClaimedFill.ImageColor3=p.FrameImage.ImageColor3
    end
    function app:trigger_claim_animation()
        local cf=self.today_frame.ClaimedFill; cf.Visible=true; cf.ImageTransparency=1
        cf.Clipper.Size=UDim2.new(0,0,1,0); cf.Clipper.Checkmark.ImageTransparency=1
        cf.ImageColor3=self.today_frame.FrameImage.ImageColor3
        TS2:Create(cf,TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{ImageTransparency=0.4}):Play()
        delay(0.12,function()
            TS2:Create(cf.Clipper,TweenInfo.new(0.4,Enum.EasingStyle.Quart,Enum.EasingDirection.InOut),{Size=UDim2.new(1,0,1,0)}):Play()
            TS2:Create(cf.Clipper.Checkmark,TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{ImageTransparency=0}):Play()
        end)
    end
    function app:refresh_scroll_buttons()
        if not self.left_button or not self.right_button then return end
        local cur=self.page_layout.CurrentPage
        if cur==self.day_buckets[#self.day_buckets] then self.right_button:disable(); self.left_button:enable()
        elseif cur==self.day_buckets[1] then self.right_button:enable(); self.left_button:disable()
        else self.right_button:enable(); self.left_button:enable() end
    end
    function app:update_daily_login_data()
        local dlm=v2.get("daily_login_manager") or {}
        self.streak=dlm.streak or 1; self.claimable=dlm.claimable~=false
        self.claimable_2x=dlm.claimable_2x
        self.day_of_month=(self.streak-1)%v8x.month_length+1
    end
    function app:can_claim_2x()
        return self.claimable_2x and v11x.are_rewarded_ads_enabled(PL2.LocalPlayer)
    end
    function app:refresh_claim_button()
        if self.claimable then
            pcall(function() self.claim_depth_button:set_state("normal") end)
            pcall(function() self.claim_button_instance.Face.TextLabel.Text="CLAIM!" end)
        else
            pcall(function() self.claim_depth_button:set_state("cancel") end)
            pcall(function() self.claim_button_instance.Face.TextLabel.Text="CLOSE" end)
        end
        pcall(function() self.claim_ad_button_instance.Visible=false end)
    end
    function app:start_countdown_timer()
        if self.claimable then return end
        coroutine.wrap(function()
            while self.visible do
                if self.time_until_next_streak then
                    local t=math.max(0,self.time_until_next_streak-(tick()-self.countdown_start))
                    local h=math.floor(t/3600); local m=math.floor((t%3600)/60); local s=math.floor(t%60)
                    pcall(function() self.tagline.Text=string.format("Next reward in %dh %02dm %02ds",h,m,s) end)
                end
                wait(0.2)
            end
        end)()
    end
    function app:show()
        self.visible=true
        self.instance.Enabled=true; self.instance.Frame.Visible=true
        self:update_daily_login_data(); self:refresh_claim_button()
        self:refresh_day_list(); self:refresh_scroll_buttons(); self:start_countdown_timer()
    end
    function app:hide()
        self.visible=false
        self.instance.Enabled=false; self.instance.Frame.Visible=false
        self:clear_day_list(); pcall(function() self.cont.continue() end)
    end
    function app:refresh(visibilities)
        -- Don't let UIManager hide us during a spin
        if _G._spinnerSpinning then return end
        local show = UIManager.is_closed({"MilestoneRewardsApp"})
        if not visibilities[self.ClassName] then show=false end
        self:set_visibility(show)
    end
    function app:yield_until_app_closed() self.cont.yield() end
    function app:show_claim_effects(n)
        task.spawn(function()
            local was=self.claimable; self.claimable=false; self.can_sprout_currency=true
            self:refresh_claim_button()
            if self.visible and was then self:trigger_claim_animation() end
        end)
    end

    -- ── Step 3: start() — wire all buttons exactly like the real module ──────
    function app:start()
        self.body = self.instance.Frame.Body
        self.claim_button_instance     = self.body.Buttons.ClaimButton
        self.claim_ad_button_instance  = self.body.Buttons.ClaimAdButton
        self.milestones_button_instance= self.body.Buttons.MilestonesButton
        self.tagline                   = self.body.TaglineArea.Tagline
        self.early_claim_explainer_button_instance = self.body.TaglineArea.EarlyClaimExplainerButton
        self.days_list_container       = self.body.DaysListContainer
        self.left_button_instance      = self.days_list_container.LeftArrowButtonContainer.LeftArrowButton
        self.right_button_instance     = self.days_list_container.RightArrowButtonContainer.RightArrowButton
        self.days_list                 = self.days_list_container.DaysList
        self.page_layout               = self.days_list.UIPageLayout
        self.day_bucket_template       = self.days_list.DayBucketTemplate
        self.day_template              = self.day_bucket_template.DayTemplate
        self.day_template.Parent       = nil
        self.day_bucket_template.Parent= nil
        self.star_icon_template        = self.day_template:FindFirstChild("StarIcon")
        if self.star_icon_template then self.star_icon_template.Parent=nil end
        self.day_buckets={}; self.day_frames={}; self.can_sprout_currency=false
        self.streak=1; self.claimable=true; self.cont=v3.create_continue()

        local buckets=math.ceil(v8x.month_length/v8x.week_length)
        for i=1,buckets do
            local c=self.day_bucket_template:Clone()
            c.LayoutOrder=i; c.Name="DayBucket"..i; c.Parent=self.days_list
            self.day_buckets[i]=c
        end

        -- ClaimButton DepthButton
        local db = UIManager.wrap(self.claim_button_instance,"DepthButton")
        db:start({mouse_button1_click=function()
            if self.claimable then
                self:show_claim_effects(1)
                -- Daily-login remotes were removed by the game; the fake spinner is
                -- fully client-side, so we do NOT call DailyLoginAPI/ClaimDailyReward
                -- (RouterClient.get would WaitForChild forever on the missing remote).
            else
                UIManager.set_app_visibility(self.ClassName,false)
                self.cont.continue()
                if v8x.get_reward_for_day(self.streak,use_alt()).reward_type=="money" and self.can_sprout_currency then
                    self.can_sprout_currency=false
                    pcall(function() UIManager.apps.SpecialEffectsApp:sprout_currency(PL2.LocalPlayer,"small") end)
                end
            end
        end})
        self.claim_depth_button=db

        -- Arrow buttons
        local function hrArr(p) p.InnerColor.ImageColor3=v7x.lookup("medium_light") end
        local function urArr(p) p.InnerColor.ImageColor3=v7x.lookup("saturated") end
        local function drArr(p) p.InnerColor.ImageColor3=Color3.fromRGB(150,150,150) end
        local lb=UIManager.wrap(self.left_button_instance,"CustomButton")
        self.left_button=lb
        lb:start({hover_render=hrArr,up_render=urArr,disabled_render=drArr,
            mouse_button1_down=function() self.page_layout:Previous() end})
        local rb=UIManager.wrap(self.right_button_instance,"CustomButton")
        self.right_button=rb
        rb:start({hover_render=hrArr,up_render=urArr,disabled_render=drArr,
            mouse_button1_down=function() self.page_layout:Next() end})

        -- ClaimAd + Milestones
        local adDb=UIManager.wrap(self.claim_ad_button_instance,"DepthButton")
        adDb:start({mouse_button1_click=function()
            if self:can_claim_2x() then
                pcall(function() v4.get("ProductsAPI/PromptProductPurchase"):FireServer("rewarded_ads_2025_double_daily_login_reward") end)
            end
        end})
        self.claim_ad_depth_button=adDb
        UIManager.wrap(self.milestones_button_instance,"DepthButton"):start({mouse_button1_click=function()
            UIManager.set_app_visibility("MilestoneRewardsApp",true)
        end})
        UIManager.wrap(self.early_claim_explainer_button_instance,"DepthButton"):start({mouse_button1_click=function()
            local txt=self.claimable and "You can claim tomorrow's reward early!" or "You claimed your reward early!"
            pcall(function() UIManager.apps.DialogApp:dialog({text=txt,button="Okay"}) end)
        end})

        -- Page layout scroll
        self.page_layout.Stopped:Connect(function() self:refresh_scroll_buttons() end)

        -- ClientData callbacks
        pcall(function()
            v2.register_callback_plus_existing("daily_login_manager",function(_,p)
                if p then self.time_until_next_streak=p.time_until_next_streak; self.countdown_start=tick() end
            end)
        end)
        -- DailyLoginAPI/SecondClaimCompleted was removed by the game; connecting
        -- to it via RouterClient.get would WaitForChild forever ("Infinite yield
        -- possible on remote DailyLoginAPI/SecondClaimCompleted"). Not needed for
        -- the fake spinner, so it is intentionally omitted.

        v5x.quick_watch({selection_parent=self.instance.Frame,default_selection=self.claim_button_instance,app_name=self.ClassName})
    end

    -- ── Step 4: register in UIManager exactly like init() does ───────────────
    UIManager.apps[app.ClassName] = app
    UIManager.app_visibilities[app.ClassName] = false

    -- Move GUI to PlayerGui (UIManager init would do this)
    screenGui.Parent = PlayerGui

    -- Call start()
    pcall(function() app:start() end)

    -- Trigger a refresh so UIManager knows about the new app
    pcall(function() UIManager.refresh_all_apps() end)
end

buildAndInjectDailyLoginApp()

end

-- Spawn a spun pet locally; if a trade is mid-negotiation, push it into the live offer.
local function addSpinPetToTrade(id, props)
    if not _G._spinnerCreate then return end
    local newPet = _G._spinnerCreate(id, props)
    if not newPet then return end
    task.defer(function()
        pcall(function()
            local TradeApp = UIManager and UIManager.apps and UIManager.apps.TradeApp
            local tradeState = TradeApp and TradeApp:_get_local_trade_state()
            if tradeState and tradeState.current_stage == "negotiation" then
                local RouterClient = fsysLoad("RouterClient")
                RouterClient.get("TradeAPI/AddItemToOffer"):FireServer(newPet.unique)
                local myOffer, offerKey = TradeApp:_get_my_offer()
                local items = {}
                for _,v in ipairs(myOffer.items) do table.insert(items,v) end
                table.insert(items, newPet)
                TradeApp:_change_local_trade_state({[offerKey]={items=items}})
                TradeApp:_lock_trade_for_appropriate_time()
                TradeApp:refresh_all()
            end
        end)
    end)
end

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local LocalPlayer      = Players.LocalPlayer
local PlayerGui        = LocalPlayer:WaitForChild("PlayerGui")
local InventoryDB  = (function() local ok,m = pcall(fsysLoad,"InventoryDB")  return ok and m or nil end)()
local DailyLoginDB = (function() local ok,m = pcall(fsysLoad,"DailyLoginDB") return ok and m or nil end)()
local UIManager    = (function() local ok,m = pcall(fsysLoad,"UIManager")    return ok and m or nil end)()

-- Anti-stack: every pet gets a unique hash so they never stack in backpack
do
    local ok, HashHelper = pcall(function()
        return fsysLoad("BackpackItemStackHashHelper")
    end)
    if ok and HashHelper and HashHelper.get_item_data_hash and not HashHelper._antiStackInstalled then
        HashHelper._antiStackInstalled = true
        local _orig = HashHelper.get_item_data_hash
        HashHelper.get_item_data_hash = function(item_data)
            if item_data and item_data.unique then
                return "nostack_" .. item_data.unique
            end
            return _orig(item_data)
        end
    end
end

local InventoryDB  = (function() local ok,m = pcall(fsysLoad,"InventoryDB")  return ok and m or nil end)()
local DailyLoginDB = (function() local ok,m = pcall(fsysLoad,"DailyLoginDB") return ok and m or nil end)()
local UIManager    = (function() local ok,m = pcall(fsysLoad,"UIManager")    return ok and m or nil end)()

local HttpService = game:GetService("HttpService")

-- _G._spinnerCreate is set by our main spawner loadSpawner()
-- _G._spinnerRouterHooked prevents double-hooking
local _spawnerPets = {}  -- spinner's own local reference (populated via _G._spinnerCreate)
local HttpService = game:GetService("HttpService")

task.spawn(function()
    pcall(function()
        if type(setthreadidentity)=="function" then setthreadidentity(2) end
        local PetActions    = fsysLoad("PetActions")
        local AnimMgr       = fsysLoad("AnimationManager")
        local PEM           = fsysLoad("PetEntityManager")
        local UIManager2    = fsysLoad("UIManager")
        local IDB2          = fsysLoad("InventoryDB")
        if not PetActions or not PetActions.do_trick then return end

        local origDoTrick = PetActions.do_trick
        PetActions.do_trick = function(wrapper)
            if not (wrapper and _spawnerPets and _spawnerPets[wrapper.pet_unique]) then
                return origDoTrick(wrapper)
            end
            local entry = IDB2.pets[wrapper.pet_id]
            if not entry or not entry.tricks or #entry.tricks==0 then return end

            local buttons = {}
            for i,trick in ipairs(entry.tricks) do
                local trickLevel = wrapper.pet_trick_level or 0
                if trickLevel < i then
                    buttons[i] = {layout_order=i, text="???", button_state="inactive"}
                else
                    buttons[i] = {layout_order=i, text=trick[1]}
                end
            end

            task.spawn(function()
                local chosen = UIManager2.apps.DialogApp:dialog({ dialog_type  = "ScrollingButtonsDialog", header       = "SELECT TRICK", buttons      = buttons, exit_button  = true, cells_per_row= 2, padding      = 10, })
                if not chosen or chosen=="cancel" then return end
                local trickEntry = entry.tricks[chosen]
                if not trickEntry then return end
                local trickName = trickEntry[1]
                local animKey   = trickEntry[2] or trickName
                local char      = wrapper.char
                local petModel  = char:FindFirstChild("PetModel")
                local animCtrl  = petModel and petModel:FindFirstChildOfClass("AnimationController")
                local animator  = (animCtrl and animCtrl:FindFirstChildOfClass("Animator"))
                              or char:FindFirstChildWhichIsA("Animator",true)
                if not animator then return end
                local animTrack = AnimMgr.get_track(animKey) or AnimMgr.get_track(trickName)
                if not animTrack then return end
                pcall(function() origDoTrick(wrapper) end)
                task.wait(3)
                pcall(function() UIManager2.apps.FocusPetApp:release_focus() end)
                pcall(function()
                    local sp = _spawnerPets[wrapper.pet_unique]
                    if sp and sp._activeTrickTrack then
                        pcall(function() sp._activeTrickTrack:Stop(0.1) end)
                        sp._activeTrickTrack = nil
                    end
                    local track = animator:LoadAnimation(animTrack)
                    track:Play()
                    if sp then sp._activeTrickTrack = track end
                    task.spawn(function()
                        local lp = LocalPlayer
                        local t = 0
                        while t < 15 do
                            task.wait(0.1); t=t+0.1
                            if not track.IsPlaying then break end
                            local lpChar = lp and lp.Character
                            local hrp = lpChar and lpChar:FindFirstChild("HumanoidRootPart")
                            local entity = PEM and PEM.get_pet_entity(char)
                            if entity and entity.move_state and entity.move_state.is_moving then
                                track:Stop(0.2); break
                            end
                        end
                        if sp then sp._activeTrickTrack=nil end
                    end)
                end)
            end)
        end
    end)
end)

local WEEK_LENGTH  = DailyLoginDB and DailyLoginDB.week_length  or 5

local COL_NORMAL = Color3.fromRGB(220, 60, 60)
local COL_GREEN  = Color3.fromRGB(80,  220, 100)
local COL_GREEN2 = Color3.fromRGB(160, 255, 140)

local SCALE_SELECTED = 1.18
local SCALE_NORMAL_V = 1.0
local SCALE_TWEEN    = 0.12
local CARD_GAP       = 8

local function corner(inst, r)
    local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 8) c.Parent=inst return c
end
local function splitCSV(str)
    local t={}
    for part in (str..","):gmatch("([^,]+),") do
        local s=part:match("^%s*(.-)%s*$") if #s>0 then table.insert(t,s) end
    end
    return t
end

local PREFS = {
    tagline    = "Spin to win your dream pet!",
    spinText   = "SPINNING",
    dialogText = "You got: ",
    showNotebookSpiral = true,
    showEggs           = false,
    randomKinds        = false,
}

local function shuffle(t)
    local s=table.clone(t)
    for i=#s,2,-1 do local j=math.random(i);s[i],s[j]=s[j],s[i] end
    return s
end
local function easeOutQuint(t) return 1-(1-t)^5 end

local petByName={}
local petList={}
if InventoryDB and InventoryDB.pets then
    for id,data in pairs(InventoryDB.pets) do
        if data.name and data.image then
            local e={id=id,name=data.name,image=data.image}
            petByName[data.name:lower()]=e
            table.insert(petList,e)
        end
    end
end
if #petList==0 then
    for _,name in ipairs({"Dog","Cat","Dragon","Unicorn","Griffin","Frost Dragon",
        "Shadow Dragon","Golden Unicorn","Bat Dragon","Turtle","Crow","Evil Unicorn",
        "Giraffe","Neon Dragon","Flamingo"}) do
        local e={id=name:lower():gsub(" ","_"),name=name,image="rbxassetid://0"}
        petByName[name:lower()]=e table.insert(petList,e)
    end
end

local function openApp(app)
    local ok=pcall(function()
        app.instance.Enabled=true
        app.instance.Frame.Visible=true
    end)
    return ok and app.instance.Enabled and app.instance.Frame.Visible
end

local function closeApp(app)
    pcall(function()
        app.instance.Frame.Visible=false
        app.instance.Enabled=false
        if app.days_list then app.days_list.Visible=false end
    end)
end

local function setArrowsVisible(app, visible)
    pcall(function() app.left_button_instance.Parent.Visible=visible end)
    pcall(function() app.right_button_instance.Parent.Visible=visible end)
end

local reelRoot   = nil
local stripFrame = nil

local function destroyReel(app)
    if reelRoot and reelRoot.Parent then reelRoot:Destroy() end
    reelRoot=nil stripFrame=nil
    if app then
        setArrowsVisible(app, true)
        pcall(function() if app.days_list then app.days_list.Visible=true end end)
    end
end

local lastCentredCard = nil

local function setFrameColor(card, color)
    if not card or not card.Parent then return end
    local fi=card:FindFirstChild("FrameImage")
    if fi then fi.ImageColor3=color end
end

local function setCardScale(card, scale, instant)
    if not card or not card.Parent then return end
    local s=card:FindFirstChildOfClass("UIScale")
    if not s then s=Instance.new("UIScale") s.Scale=SCALE_NORMAL_V s.Parent=card end
    if instant then s.Scale=scale
    else TweenService:Create(s,TweenInfo.new(SCALE_TWEEN,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=scale}):Play() end
end

local function updateCentredCard(cards, stripX, vpW, cardW)
    local step=cardW+CARD_GAP
    local centreInStrip=vpW/2-stripX
    local bestIdx,bestDist=nil,math.huge
    for i,card in ipairs(cards) do
        local cc=(i-1)*step+CARD_GAP+cardW/2
        local d=math.abs(cc-centreInStrip)
        if d<bestDist then bestDist=d bestIdx=i end
    end
    local newCard=bestIdx and cards[bestIdx] or nil
    if newCard~=lastCentredCard then
        if lastCentredCard and lastCentredCard.Parent then
            setFrameColor(lastCentredCard,COL_NORMAL)
            setCardScale(lastCentredCard,SCALE_NORMAL_V,false)
        end
        if newCard and newCard.Parent then
            setFrameColor(newCard,COL_GREEN)
            setCardScale(newCard,SCALE_SELECTED,false)
        end
        lastCentredCard=newCard
    else
        if newCard and newCard.Parent then
            local fi=newCard:FindFirstChild("FrameImage")
            if fi then fi.ImageColor3=COL_GREEN:Lerp(COL_GREEN2,(math.sin(tick()*5)+1)/2) end
        end
    end
end

local activeMutations={}  -- populated by control panel mutation buttons

local function buildReel(app, sequence, winnerIdx)
    destroyReel(nil)
    lastCentredCard=nil

    app.days_list.Visible=false
    setArrowsVisible(app,false)

    local dlc=app.days_list_container
    task.wait()
    local vpW=dlc.AbsoluteSize.X
    local vpH=dlc.AbsoluteSize.Y

    reelRoot=Instance.new("Frame")
    reelRoot.Name="SpinnerReelRoot"
    reelRoot.Size=UDim2.new(1,0,1,0)
    reelRoot.Position=UDim2.new(0,0,0,0)
    reelRoot.BackgroundTransparency=1
    reelRoot.BorderSizePixel=0
    reelRoot.ClipsDescendants=true
    reelRoot.ZIndex=10
    reelRoot.Parent=dlc

    local sampleCard=app.day_template:Clone()
    sampleCard.Visible=false sampleCard.Parent=reelRoot
    task.wait()
    local cW=math.max(sampleCard.AbsoluteSize.X,10)
    local cH=math.max(sampleCard.AbsoluteSize.Y,10)
    sampleCard:Destroy()

    local step=cW+CARD_GAP
    local stripW=#sequence*step+CARD_GAP
    local stripY=(vpH-cH)/2

    stripFrame=Instance.new("Frame")
    stripFrame.Name="Strip"
    stripFrame.Size=UDim2.fromOffset(stripW,cH)
    stripFrame.Position=UDim2.fromOffset(0,stripY)
    stripFrame.BackgroundTransparency=1
    stripFrame.BorderSizePixel=0
    stripFrame.ClipsDescendants=false
    stripFrame.ZIndex=11
    stripFrame.Parent=reelRoot

    local cards={}
    for i,pet in ipairs(sequence) do
        local card=app.day_template:Clone()
        card.Name="ReelCard"..i
        card.Size=UDim2.fromOffset(cW,cH)
        card.AnchorPoint=Vector2.new(0.5,0.5)
        card.Position=UDim2.fromOffset((i-1)*step+CARD_GAP+cW/2, cH/2)
        card.Visible=true
        card.ZIndex=12

        for _,child in card:GetChildren() do
            if child:IsA("UIListLayout") or child:IsA("UIGridLayout") then child:Destroy() end
        end

        local mi=card:FindFirstChild("MoneyIcon")
        local gi=card:FindFirstChild("GiftIcon")
        local ii=card:FindFirstChild("ItemIcon")
        local rl=card:FindFirstChild("RewardLabel")
        local rp=card:FindFirstChild("RadialPinstripe")
        local dl=card:FindFirstChild("DayLabel")
        local sl=card:FindFirstChild("StarsLabel")
        local cf=card:FindFirstChild("ClaimedFill")
        local fi=card:FindFirstChild("FrameImage")
        if mi then mi.Visible=false end
        if gi then gi.Visible=false end
        if rp then rp.Visible=false end
        if cf then cf.Visible=false end
        if ii then ii.Visible=true; ii.Image=pet.image end
        if rl then rl.Text=pet.name end
        if dl then dl.Text="REWARD" end  -- show REWARD instead of day number
        if sl then sl.Visible=false end
        if fi then fi.ImageColor3=COL_NORMAL end

        local ok, err = pcall(function()
            local template = game.ReplicatedStorage.Resources.UI_Resources.Templates.TagDisplayTemplate:Clone()
            template.Size     = UDim2.new(1, 0, 0, 15); template.Position = UDim2.new(0, 0, 1, -20)
            template.ZIndex   = card.ZIndex + 3; template.Parent   = card

            for _, child in template:GetChildren() do
                if child:IsA("Frame") or child:IsA("ImageLabel") then
                    child.Visible = false
                end
            end

            local showFly, showRide, showNeon, showMega
            local isWinnerCard = (winnerIdx and i == winnerIdx)
            if PREFS.randomKinds and not isWinnerCard then
                local neonRoll = math.random(3)
                showMega = (neonRoll == 1)
                showNeon = (neonRoll == 2)
                showFly  = (math.random(2) == 1)
                showRide = (math.random(2) == 1)
            else
                showFly  = activeMutations.fly      == true
                showRide = activeMutations.ride     == true
                showNeon = activeMutations.neon     == true
                showMega = activeMutations.megaNeon == true
            end

            local flyPip      = template:FindFirstChild("flyable")
            local ridePip     = template:FindFirstChild("rideable")
            local neonPip     = template:FindFirstChild("neon")
            local megaNeonPip = template:FindFirstChild("mega_neon")
            if flyPip      then flyPip.Visible      = showFly  end
            if ridePip     then ridePip.Visible     = showRide end
            if neonPip     then neonPip.Visible     = showNeon end
            if megaNeonPip then megaNeonPip.Visible = showMega end
        end)
        if not ok then warn("[PetSpinner] pip error: "..tostring(err)) end

        local uiScale = mk("UIScale", {Scale=SCALE_NORMAL_V, Parent=card})

        card.Parent=stripFrame
        cards[i]=card
    end

    return cards,cW,vpW,stripY
end

local isBusy=false
local spinState="idle"  -- "idle" | "spinning" | "claim"
local selectBtn  -- forward declared, set in control panel
local _spinnerPickerFn = nil  -- set when selectBtn is created, called by second backpack button
local function openSpinnerPicker()
    if _spinnerPickerFn then task.spawn(_spinnerPickerFn) end
end

local function _resetSpinState()
    isBusy=false
    spinState="idle"
    if SpinBtn then
        SpinBtn.Text="✨ SPIN!"
        TweenService:Create(SpinBtn,TweenInfo.new(0.15),{BackgroundColor3=Color3.fromRGB(30,80,50)}):Play()
    end
    if StatusLbl then
        StatusLbl.Text="Ready."
        StatusLbl.TextColor3=Color3.fromRGB(190,34,230)
    end
    pcall(function() if reelRoot and reelRoot.Parent then reelRoot:Destroy() end end)
    reelRoot=nil stripFrame=nil lastCentredCard=nil
end

local function doSpin(inputNames, targetName)
    if isBusy then return end
    isBusy=true

    local targetEntry
    if #targetName>0 then
        targetEntry=petByName[targetName:lower()]
                 or {id="custom",name=targetName,image="rbxassetid://0"}
    end

    local fillers={}
    local function isEgg(e) return e.name:lower():find("egg") ~= nil end
    if #inputNames>0 then
        for _,name in ipairs(inputNames) do
            local e=petByName[name:lower()] or {id="custom",name=name,image="rbxassetid://0"}
            if (PREFS.showEggs or not isEgg(e)) and (not targetEntry or e.name:lower()~=targetEntry.name:lower()) then
                table.insert(fillers,e)
            end
        end
    else
        local sh=shuffle(petList)
        for _,e in ipairs(sh) do
            if #fillers>=40 then break end
            if PREFS.showEggs or not isEgg(e) then
                table.insert(fillers,e)
            end
        end
    end

    if not targetEntry then
        if #fillers==0 then
            StatusLbl.Text="No pets in pool!" StatusLbl.TextColor3=Color3.fromRGB(220,80,80)
            _resetSpinState(); return
        end
        local idx=math.random(1,#fillers)
        targetEntry=fillers[idx] table.remove(fillers,idx)
    end

    if not UIManager then
        StatusLbl.Text="UIManager not available!" StatusLbl.TextColor3=Color3.fromRGB(220,80,80)
        _resetSpinState(); return
    end
    local app=UIManager.apps.DailyLoginApp
    if not app then
        StatusLbl.Text="DailyLoginApp not found!" StatusLbl.TextColor3=Color3.fromRGB(220,80,80)
        _resetSpinState(); return
    end

    StatusLbl.Text="Opening Daily Login..."
    StatusLbl.TextColor3=Color3.fromRGB(180,180,180)
    if not openApp(app) then
        StatusLbl.Text="Could not open Daily Login!" StatusLbl.TextColor3=Color3.fromRGB(220,80,80)
        _resetSpinState(); return
    end
    task.wait(0.15)

    -- Show admin badge above the DailyLogin dialog
    pcall(function()
        local dlFrame = PlayerGui.DailyLoginApp.Frame
        local old = dlFrame:FindFirstChild("AdminBadge")
        if old then old:Destroy() end

        local badge = mk("Frame", {Name="AdminBadge", Size=UDim2.new(0, 400, 0, 40), AnchorPoint=Vector2.new(0.5, 1), Position=UDim2.new(0.5, 0, 0, -22), BackgroundTransparency=1, BorderSizePixel=0, ZIndex=10, Parent=dlFrame})

        local ICON_SIZE = 28
        local txt = Instance.new("TextLabel", badge)
        txt.Size = UDim2.new(1, 0, 1, 0); txt.Position = UDim2.new(0, 0, 0, 0)
        txt.BackgroundTransparency = 1; txt.RichText = false
        txt.Text = "This feature is exclusive to Uplift Admins"; txt.Font = Enum.Font.FredokaOne
        txt.TextSize = 28; txt.TextColor3 = Color3.fromRGB(255, 255, 255)
        txt.TextScaled = false; txt.ZIndex = 11
        local tStroke = Instance.new("UIStroke", txt)
        tStroke.Color = Color3.new(0,0,0)
        tStroke.Thickness = 1.5

        task.defer(function()
            local tbX = txt.TextBounds.X
            local gap = 8
            local iconL = Instance.new("ImageLabel", badge)
            iconL.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE); iconL.AnchorPoint = Vector2.new(1, 0.5)
            iconL.Position = UDim2.new(0.5, -tbX/2 - gap, 0.5, 0); iconL.BackgroundTransparency = 1
            iconL.Image = "rbxassetid://5269331469"; iconL.ZIndex = 11

            local iconR = Instance.new("ImageLabel", badge)
            iconR.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE); iconR.AnchorPoint = Vector2.new(0, 0.5)
            iconR.Position = UDim2.new(0.5, tbX/2 + gap, 0.5, 0); iconR.BackgroundTransparency = 1
            iconR.Image = "rbxassetid://5269331469"; iconR.ZIndex = 11
        end)

        task.spawn(function()
            while badge and badge.Parent do
                TweenService:Create(txt, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {TextColor3=Color3.fromRGB(220,160,255)}):Play()
                task.wait(1.2)
                TweenService:Create(txt, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                    {TextColor3=Color3.fromRGB(255,255,255)}):Play()
                task.wait(1.2)
            end
        end)
    end)
    pcall(function()
        local buttons = PlayerGui.DailyLoginApp.Frame.Body.Buttons
        local claimAd    = buttons:FindFirstChild("ClaimAdButton")
        local milestones = buttons:FindFirstChild("MilestonesButton")
        if claimAd    then claimAd:Destroy() end
        if milestones then milestones:Destroy() end
        local layout = buttons:FindFirstChildOfClass("UIListLayout")
        if layout then layout:Destroy() end
        local h = buttons.AbsoluteSize.Y > 0 and buttons.AbsoluteSize.Y or 48
        buttons.Size = UDim2.new(1, -60, 0, h)
        pcall(function()
            local tagline = PlayerGui.DailyLoginApp.Frame.Body.TaglineArea.Tagline
            tagline.Text = PREFS.tagline
        end)
        pcall(function()
        end)
        local claimBtn = buttons:FindFirstChild("ClaimButton")
        if claimBtn then
            claimBtn.Size        = UDim2.new(1, 0, 1, 0); claimBtn.Position    = UDim2.new(0, 0, 0.5, 0)
            claimBtn.AnchorPoint = Vector2.new(0, 0.5)
        end
    end)

    local LEAD,TRAIL=28,5
    local sequence={}
    local function fillerAt(i)
        if #fillers==0 then return targetEntry end
        return fillers[(i-1)%#fillers+1]
    end
    for i=1,LEAD   do table.insert(sequence,fillerAt(i)) end
    table.insert(sequence,targetEntry)
    for i=1,TRAIL  do table.insert(sequence,fillerAt(LEAD+i)) end

    local winnerSeqIdx=LEAD+1

    pcall(function()
        local cb = PlayerGui.DailyLoginApp.Frame.Body.Buttons.ClaimButton
        cb.Active = false
        cb.AutoButtonColor = false
    end)

    StatusLbl.Text=PREFS.spinText.."."
    StatusLbl.TextColor3=Color3.fromRGB(180,180,180)
    if SpinBtn then
        SpinBtn.Text=PREFS.spinText.."."
        SpinBtn.BackgroundColor3=Color3.fromRGB(20,55,35)
    end

    local dotState=0
    local dotPatterns={PREFS.spinText..".", PREFS.spinText.."..", PREFS.spinText.."..."}
    local dotTimer=0
    local dotAnimConn
    dotAnimConn=RunService.Heartbeat:Connect(function(dt)
        dotTimer=dotTimer+dt
        if dotTimer>=0.4 then
            dotTimer=0
            dotState=(dotState+1)%3
            local txt=dotPatterns[dotState+1]
            StatusLbl.Text=txt
            if SpinBtn then SpinBtn.Text=txt end
            pcall(function()
                PlayerGui.DailyLoginApp.Frame.Body.Buttons.ClaimButton.Face.TextLabel.Text=txt
            end)
        end
    end)

    local cards,cW,vpW,stripY=buildReel(app,sequence,winnerSeqIdx)
    if not stripFrame then
        StatusLbl.Text="Failed to build reel!" StatusLbl.TextColor3=Color3.fromRGB(220,80,80)
        _resetSpinState(); return
    end

    local step=cW+CARD_GAP
    local winnerLeft=(winnerSeqIdx-1)*step+CARD_GAP
    local endX=vpW/2-winnerLeft-cW/2
    local startX=vpW/2-CARD_GAP-cW/2

    stripFrame.Position=UDim2.fromOffset(startX,stripY)

    lastCentredCard=nil
    updateCentredCard(cards,startX,vpW,cW)

    local SPIN_DUR=4.0
    local elapsed=0
    local pulseConn,conn

    pulseConn=RunService.Heartbeat:Connect(function()
        if not stripFrame or not stripFrame.Parent then pulseConn:Disconnect() return end
        if lastCentredCard and lastCentredCard.Parent then
            local fi=lastCentredCard:FindFirstChild("FrameImage")
            if fi then fi.ImageColor3=COL_GREEN:Lerp(COL_GREEN2,(math.sin(tick()*5)+1)/2) end
        end
    end)

    conn=RunService.Heartbeat:Connect(function(dt)
        elapsed=elapsed+dt
        local t=math.clamp(elapsed/SPIN_DUR,0,1)

        local eased
        if t<0.55 then
            local t2=t/0.55
            eased=0.55*(t2^3)
        else
            local t2=(t-0.55)/0.45
            eased=0.55+0.45*easeOutQuint(t2)
        end

        local currentX=startX+(endX-startX)*eased
        if stripFrame and stripFrame.Parent then
            stripFrame.Position=UDim2.fromOffset(currentX,stripY)
            updateCentredCard(cards,currentX,vpW,cW)
        end

        if t>=1 then
            conn:Disconnect()
            pulseConn:Disconnect()
            dotAnimConn:Disconnect()

            if stripFrame and stripFrame.Parent then
                stripFrame.Position=UDim2.fromOffset(endX,stripY)
            end

            if lastCentredCard and lastCentredCard~=cards[winnerSeqIdx] then
                setFrameColor(lastCentredCard,COL_NORMAL)
                setCardScale(lastCentredCard,SCALE_NORMAL_V,false)
            end
            lastCentredCard=cards[winnerSeqIdx]
            setFrameColor(lastCentredCard,COL_GREEN)
            setCardScale(lastCentredCard,SCALE_SELECTED,false)

            local s=cards[winnerSeqIdx]:FindFirstChildOfClass("UIScale")
            if s then
                TweenService:Create(s,
                    TweenInfo.new(0.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out,1,true),
                    {Scale=SCALE_SELECTED+0.08}):Play()
            end

            _G._spinnerWinner = targetEntry

            StatusLbl.Text=PREFS.dialogText..targetEntry.name.."!  Click CLAIM!"
            StatusLbl.TextColor3=Color3.fromRGB(190,34,230)

            spinState="claim"
            SpinBtn.Text="CLAIM!"
            SpinBtn.TextColor3=Color3.fromRGB(255,255,255)
            TweenService:Create(SpinBtn,TweenInfo.new(0.2),
                {BackgroundColor3=Color3.fromRGB(30,80,50)}):Play()

            pcall(function()
                local cb = PlayerGui.DailyLoginApp.Frame.Body.Buttons.ClaimButton
                cb.Active = true; cb.AutoButtonColor = true
                cb.Face.TextLabel.Text = "CLAIM!"
            end)
        end
    end)
end

-- Safety net: if DailyLoginApp gets destroyed mid-spin (e.g. game closes it),
-- reset spin state so the button isn't locked forever.
task.spawn(function()
    while true do
        task.wait(1)
        if isBusy and spinState ~= "claim" then
            local dla = PlayerGui:FindFirstChild("DailyLoginApp")
            if not dla then
                warn("[Spinner] DailyLoginApp gone mid-spin — resetting state")
                _resetSpinState()
            end
        end
    end
end)

-- CONTROL PANEL (67.lua style)
local mainFrame = tabFrames["Spin"]
local controlGui = nil  -- no standalone ScreenGui needed

local blackFrame = mk("Frame", {Name="BlackFrame", BackgroundTransparency=1, Size=UDim2.new(0,1,0,1), Parent=mainFrame})  -- kept for spinner refs but invisible

-- Tab system (spinner's internal Spin/Prefs sub-tabs)
local tabFrames={}
local currentTab=""
local activeTabPulseTween=nil

local tabContainer = mk("Frame", {Size=UDim2.new(1,0,0,13), Position=UDim2.new(0,0,0,0), BackgroundTransparency=1, Parent=mainFrame})

local tabButtons={}
local tabDefs={{"Spin","✨"},{"Prefs","⚙️"}}

local function setActiveTab(tabName)
    if currentTab==tabName then return end
    if activeTabPulseTween then activeTabPulseTween:Cancel(); activeTabPulseTween=nil end
    currentTab=tabName
    for name,data in pairs(tabButtons) do
        local isActive=name==tabName
        TweenService:Create(data.button,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{ BackgroundColor3=isActive and Color3.fromRGB(50,50,60) or Color3.fromRGB(40,40,50) }):Play()
        local targetColor=isActive and Color3.fromRGB(190,34,230) or Color3.fromRGB(80,80,80)
        TweenService:Create(data.stroke,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{ Color=targetColor, Thickness=isActive and 1.0 or 0.7 }):Play()
        if isActive then
            local pulseInfo=TweenInfo.new(1.5,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true)
            activeTabPulseTween=TweenService:Create(data.stroke,pulseInfo,{ Color=targetColor:Lerp(Color3.fromRGB(255,255,255),0.25), Thickness=1.3 })
            activeTabPulseTween:Play()
        end
    end
    for name,frame in pairs(tabFrames) do frame.Visible=(name==tabName) end
end

for i,def in ipairs(tabDefs) do
    local tabName,icon=def[1],def[2]
    local tabButton = mk("TextButton", {Size=UDim2.new(1/#tabDefs-0.02,0,1,0), Position=UDim2.new((i-1)*(1/#tabDefs),0,0,0), BackgroundColor3=i==1 and Color3.fromRGB(50,50,60) or Color3.fromRGB(40,40,50), BackgroundTransparency=0.2, Text=icon.." "..tabName, Font=Enum.Font.FredokaOne, TextSize=6, TextColor3=Color3.fromRGB(255,255,255), Parent=tabContainer})
    Instance.new("UICorner",tabButton).CornerRadius=UDim.new(0,3)
    local tabStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=i==1 and Color3.fromRGB(190,34,230) or Color3.fromRGB(80,80,80), Thickness=i==1 and 1.0 or 0.7, Transparency=0.3, Parent=tabButton})
    tabButtons[tabName]={button=tabButton,stroke=tabStroke}
    local tabFrame = mk("Frame", {Size=UDim2.new(1,0,1,-15), Position=UDim2.new(0,0,0,15), BackgroundTransparency=1, Visible=i==1, Parent=mainFrame})
    tabFrames[tabName]=tabFrame
    tabButton.MouseButton1Click:Connect(function() setActiveTab(tabName) end)
end

local spinFrame=tabFrames["Spin"]

local petNameLbl = mk("TextLabel", {Size=UDim2.new(1,0,0,9), Position=UDim2.new(0,0,0,-2), BackgroundTransparency=1, Text="Pet Names (comma sep.)", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180,180,180), TextXAlignment=Enum.TextXAlignment.Left, Parent=spinFrame})

local htBtn = mk("TextButton", {Size=UDim2.new(0,50,0,9), Position=UDim2.new(1,-50,0,-2), BackgroundColor3=Color3.fromRGB(180,120,50), Text="👑 High Tiers", Font=Enum.Font.FredokaOne, TextSize=5, TextColor3=Color3.fromRGB(255,255,255), BorderSizePixel=0, Parent=spinFrame})
Instance.new("UICorner",htBtn).CornerRadius=UDim.new(0,3)

local NamesBox = mk("TextBox", {Size=UDim2.new(1,0,0,16), Position=UDim2.new(0,0,0,9), BackgroundColor3=Color3.fromRGB(40,40,50), Text="", PlaceholderText="e.g. Shadow Dragon, Bat Dragon", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255,255,255), PlaceholderColor3=Color3.fromRGB(110,110,135), ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ClipsDescendants=true, BorderSizePixel=0, Parent=spinFrame})
Instance.new("UICorner",NamesBox).CornerRadius=UDim.new(0,4)
do local s=Instance.new("UIStroke") s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
s.Color=Color3.fromRGB(180,180,200) s.Thickness=1.5 s.Parent=NamesBox
local p=Instance.new("UIPadding") p.PaddingLeft=UDim.new(0,4) p.PaddingRight=UDim.new(0,4) p.Parent=NamesBox end

local targetLbl = mk("TextLabel", {Size=UDim2.new(1,0,0,9), Position=UDim2.new(0,0,0,27), BackgroundTransparency=1, Text="Target Pet (blank = random)", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180,180,180), TextXAlignment=Enum.TextXAlignment.Left, Parent=spinFrame})

local TargetBox = mk("TextBox", {Size=UDim2.new(1,0,0,16), Position=UDim2.new(0,0,0,37), BackgroundColor3=Color3.fromRGB(40,40,50), Text="", PlaceholderText="e.g. Shadow Dragon", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(255,255,255), PlaceholderColor3=Color3.fromRGB(110,110,135), ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, ClipsDescendants=true, BorderSizePixel=0, Parent=spinFrame})
Instance.new("UICorner",TargetBox).CornerRadius=UDim.new(0,4)
do local s=Instance.new("UIStroke") s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
s.Color=Color3.fromRGB(180,180,200) s.Thickness=1.5 s.Parent=TargetBox
local p=Instance.new("UIPadding") p.PaddingLeft=UDim.new(0,4) p.PaddingRight=UDim.new(0,4) p.Parent=TargetBox end

local rndBtn = mk("TextButton", {Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,59), BackgroundColor3=Color3.fromRGB(40,40,50), BackgroundTransparency=0.2, Text="🎲 Random High Tier Target", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(220,220,255), BorderSizePixel=0, Parent=spinFrame})
Instance.new("UICorner",rndBtn).CornerRadius=UDim.new(0,3)
local rndStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=1.0, Transparency=0.4, Parent=rndBtn})

local HighTierPetsRef={
    "Shadow Dragon","Bat Dragon","Frost Dragon","Giraffe","Blazing Lion",
    "African Wild Dog","Owl","Parrot","Crow","Evil Unicorn","Balloon Unicorn",
    "Dalmatian","Arctic Reindeer","Kangaroo","Turtle","Giant Panda","Hedgehog",
    "Cow","Chocolate Chip Bat Dragon","Flamingo","Peppermint Penguin",
    "Strawberry Shortcake Bat Dragon","Fairy Bat Dragon",
}
rndBtn.MouseButton1Click:Connect(function()
    local pick=HighTierPetsRef[math.random(1,#HighTierPetsRef)]
    TargetBox.Text=pick
    TweenService:Create(rndStroke,TweenInfo.new(0.1),{Color=Color3.fromRGB(60,220,110),Thickness=1.5,Transparency=0}):Play()
    task.delay(0.4,function()
        TweenService:Create(rndStroke,TweenInfo.new(0.3),{Color=Color3.fromRGB(190,34,230),Thickness=1.0,Transparency=0.4}):Play()
    end)
end)

StatusLbl=Instance.new("TextLabel")
StatusLbl.Size=UDim2.new(1,0,0,9)
StatusLbl.Position=UDim2.new(0,0,0,129)
StatusLbl.BackgroundTransparency=1
StatusLbl.Text="Ready."
StatusLbl.Font=Enum.Font.SourceSansSemibold
StatusLbl.TextSize=7
StatusLbl.TextColor3=Color3.fromRGB(190,34,230)
StatusLbl.TextXAlignment=Enum.TextXAlignment.Left
StatusLbl.Parent=spinFrame

SpinBtn=Instance.new("TextButton")
SpinBtn.Size=UDim2.new(1,0,0,20)
SpinBtn.Position=UDim2.new(0,0,0,140)
SpinBtn.BackgroundColor3=Color3.fromRGB(30,80,50)
SpinBtn.BackgroundTransparency=0.1
SpinBtn.Text="✨ SPIN!"
SpinBtn.Font=Enum.Font.FredokaOne
SpinBtn.TextSize=9
SpinBtn.TextColor3=Color3.fromRGB(255,255,255)
SpinBtn.BorderSizePixel=0
SpinBtn.Parent=spinFrame
Instance.new("UICorner",SpinBtn).CornerRadius=UDim.new(0,5)
local spinStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(0,255,100), Thickness=1.5, Parent=SpinBtn})

SpinBtn.MouseEnter:Connect(function()
    if spinState=="idle" then
        TweenService:Create(SpinBtn,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(40,110,65)}):Play()
    end
end)
SpinBtn.MouseLeave:Connect(function()
    if spinState=="idle" then
        TweenService:Create(SpinBtn,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(30,80,50)}):Play()
    end
end)

local function triggerSpin()
    if spinState=="idle" then
        spinState="spinning"
        task.spawn(function()
            local target = TargetBox.Text:match("^%s*(.-)%s*$") or ""
            doSpin(splitCSV(NamesBox.Text), target)
        end)
    end
end

SpinBtn.MouseButton1Click:Connect(function()
    if spinState=="idle" then
        triggerSpin()
    elseif spinState=="claim" then
        spinState="idle"
        SpinBtn.Text="..."
        SpinBtn.BackgroundColor3=Color3.fromRGB(20,55,35)
        task.spawn(function()
            if type(setthreadidentity)=="function" then setthreadidentity(2)
            elseif type(syn)=="table" and syn.set_thread_identity then syn.set_thread_identity(2)
            elseif type(setthreadcontext)=="function" then setthreadcontext(2) end
            local winner=_G._spinnerWinner
            if not winner then StatusLbl.Text="Error: no winner!"; _resetSpinState(); return end
            local appRef=UIManager and UIManager.apps and UIManager.apps.DailyLoginApp
            local ok, err = xpcall(function()
                pcall(function() PlayerGui.DailyLoginApp.Enabled=false end)
                UIManager.apps.DialogApp:dialog({
                    dialog_type="ItemPreviewDialog",
                    text=PREFS.dialogText..winner.name.."!",
                    button="Claim!",
                    item={id=winner.id,kind=winner.id,category="pets",unique="spinner_"..winner.id,image=winner.image,
                        properties={flyable=activeMutations.fly==true,rideable=activeMutations.ride==true,
                            neon=activeMutations.neon==true,mega_neon=activeMutations.megaNeon==true}},
                    yields=true,
                })
                pcall(function()
                    local props={flyable=activeMutations.fly==true,rideable=activeMutations.ride==true,
                        neon=activeMutations.neon==true,mega_neon=activeMutations.megaNeon==true,
                        age=6,ailments_completed=0,rp_name="",pet_trick_level=0}
                    addSpinPetToTrade(winner.id, props)
                end)
            end, function(e) return e end)
            if not ok then warn("[Spinner] claim error: "..tostring(err)) end
            -- Always clean up regardless of success or error
            if lastCentredCard then setFrameColor(lastCentredCard,COL_NORMAL); setCardScale(lastCentredCard,SCALE_NORMAL_V,true); lastCentredCard=nil end
            if appRef then destroyReel(appRef); closeApp(appRef) end
            _G._spinnerWinner=nil
            _G._autoSpinClaimDone = true  -- signal auto spin loop that claim fully finished
            _resetSpinState()
        end)
    end
end)

-- AUTO SPIN
_G._autoSpinEnabled  = false
_G._autoSpinPending  = 0     -- number of spins queued from last trade
_G._autoSpinTriggered = false

do -- autoSpin block
local autoSpinBtn = mk("TextButton", {Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,164), BackgroundColor3=Color3.fromRGB(40,30,70), BackgroundTransparency=0.1, Text="AUTO SPIN: OFF", Font=Enum.Font.FredokaOne, TextSize=8, TextColor3=Color3.fromRGB(160,130,255), BorderSizePixel=0, Parent=spinFrame})
Instance.new("UICorner", autoSpinBtn).CornerRadius = UDim.new(0,5)
local autoSpinStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(130,80,255), Thickness=1.2, Transparency=0.3, Parent=autoSpinBtn})

autoSpinBtn.MouseButton1Click:Connect(function()
    _G._autoSpinEnabled = not _G._autoSpinEnabled
    if _G._autoSpinEnabled then
        autoSpinBtn.Text = "AUTO SPIN: ON"
        autoSpinBtn.TextColor3 = Color3.fromRGB(120,255,160)
        TweenService:Create(autoSpinBtn, TweenInfo.new(0.2), {BackgroundColor3=Color3.fromRGB(25,65,40)}):Play()
        TweenService:Create(autoSpinStroke, TweenInfo.new(0.2), {Color=Color3.fromRGB(60,220,100),Transparency=0.1}):Play()
    else
        autoSpinBtn.Text = "AUTO SPIN: OFF"
        autoSpinBtn.TextColor3 = Color3.fromRGB(160,130,255)
        TweenService:Create(autoSpinBtn, TweenInfo.new(0.2), {BackgroundColor3=Color3.fromRGB(40,30,70)}):Play()
        TweenService:Create(autoSpinStroke, TweenInfo.new(0.2), {Color=Color3.fromRGB(130,80,255),Transparency=0.3}):Play()
    end
end)

-- Max spins row: toggle + input
_G._maxSpinsEnabled = false
_G._maxSpinsValue   = 8

local maxSpinsRow = mk("Frame", {Size=UDim2.new(1,0,0,11), Position=UDim2.new(0,0,0,180), BackgroundTransparency=1, Parent=spinFrame})

local maxSpinsToggle = mk("TextButton", {Size=UDim2.new(0.55,-2,1,0), BackgroundColor3=Color3.fromRGB(40,30,70), BackgroundTransparency=0.1, Text="Max Spins: OFF", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(160,130,255), BorderSizePixel=0, Parent=maxSpinsRow})
Instance.new("UICorner", maxSpinsToggle).CornerRadius = UDim.new(0,3)
local maxSpinsToggleStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(130,80,255), Thickness=0.7, Transparency=0.4, Parent=maxSpinsToggle})

local maxSpinsBox = mk("TextBox", {Size=UDim2.new(0.45,-2,1,0), Position=UDim2.new(0.55,2,0,0), BackgroundColor3=Color3.fromRGB(40,40,55), BackgroundTransparency=0.2, Text="8", Font=Enum.Font.FredokaOne, TextSize=7, TextColor3=Color3.fromRGB(200,200,220), TextXAlignment=Enum.TextXAlignment.Center, ClearTextOnFocus=false, BorderSizePixel=0, Parent=maxSpinsRow})
Instance.new("UICorner", maxSpinsBox).CornerRadius = UDim.new(0,3)
local maxSpinsBoxStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(130,80,255), Thickness=0.7, Transparency=0.5, Parent=maxSpinsBox})

maxSpinsToggle.MouseButton1Click:Connect(function()
    _G._maxSpinsEnabled = not _G._maxSpinsEnabled
    if _G._maxSpinsEnabled then
        maxSpinsToggle.Text = "Max Spins: ON"
        maxSpinsToggle.TextColor3 = Color3.fromRGB(120,255,160)
        TweenService:Create(maxSpinsToggle, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromRGB(25,65,40)}):Play()
        TweenService:Create(maxSpinsToggleStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(60,220,100),Transparency=0.1}):Play()
    else
        maxSpinsToggle.Text = "Max Spins: OFF"
        maxSpinsToggle.TextColor3 = Color3.fromRGB(160,130,255)
        TweenService:Create(maxSpinsToggle, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromRGB(40,30,70)}):Play()
        TweenService:Create(maxSpinsToggleStroke, TweenInfo.new(0.15), {Color=Color3.fromRGB(130,80,255),Transparency=0.4}):Play()
    end
end)

maxSpinsBox.FocusLost:Connect(function()
    local n = tonumber(maxSpinsBox.Text)
    if n and n >= 1 then
        _G._maxSpinsValue = math.floor(n)
        maxSpinsBox.Text = tostring(_G._maxSpinsValue)
    else
        maxSpinsBox.Text = tostring(_G._maxSpinsValue)
    end
end)

-- Auto spin counter label (shows pending spins)
local autoSpinCountLbl = mk("TextLabel", {Size=UDim2.new(1,0,0,9), Position=UDim2.new(0,0,0,193), BackgroundTransparency=1, Text="Pending spins: 0", Font=Enum.Font.SourceSans, TextSize=7, TextColor3=Color3.fromRGB(160,160,180), TextXAlignment=Enum.TextXAlignment.Left, Parent=spinFrame})

-- Watch for pending spins and auto-trigger
task.spawn(function()
    while true do
        task.wait(0.5)
        -- Update label
        local _pend = _G._autoSpinPending or 0
        if not _G._autoSpinTriggered then
            -- inner loop manages label when running
            local _status = ""
            if not _G._autoSpinEnabled then _status = " (off)"
            elseif _pend <= 0 then _status = " (done)"
            elseif _G._autoSpinWaitingForTrade then _status = " (waiting for retrade)"
            end
            autoSpinCountLbl.Text = "Pending: ".._pend.._status
        end

        if not _G._autoSpinEnabled then continue end
        if _pend <= 0 then continue end
        if _G._autoSpinTriggered then continue end
        if _G._autoSpinWaitingForTrade then continue end
        if spinState ~= "idle" then continue end

        _G._autoSpinTriggered = true

        task.spawn(function()
            local required = _G._autoSpinRequiredPets or 1

            while (_G._autoSpinPending or 0) > 0 do

                -- STEP 1: Wait for you to add ALL the pets they gave you back into the trade
                local needed = required
                autoSpinCountLbl.Text = "Pending: ".._G._autoSpinPending.." (add "..needed.." pet(s) to trade)"
                local w = 0
                while w < 300 do
                    task.wait(0.5); w = w + 0.5
                    local ts = mockState.trade
                    local items = ts and ts.sender_offer and ts.sender_offer.items
                    if items and #items >= needed then break end
                end
                do
                    local ts = mockState.trade
                    local items = ts and ts.sender_offer and ts.sender_offer.items
                    if not items or #items < needed then break end
                end

                -- 0.5s pause after pets added
                task.wait(0.5)

                -- STEP 2: Fire spin
                spinState = "idle"; isBusy = false
                _G._autoSpinClaimDone = false
                autoSpinCountLbl.Text = "Pending: ".._G._autoSpinPending.." (spinning...)"
                task.wait(0.2)

                -- snapshot my current item count before spin
                local myCountBefore = 0
                pcall(function()
                    local ts = mockState.trade
                    local items = ts and ts.sender_offer and ts.sender_offer.items
                    myCountBefore = items and #items or 0
                end)

                _G._autoSpinPending = _G._autoSpinPending - 1
                if HighTierPetsRef and #HighTierPetsRef > 0 then
                    TargetBox.Text = HighTierPetsRef[math.random(1, #HighTierPetsRef)]
                end
                triggerSpin()

                -- STEP 3: Wait for claim to complete
                -- Primary signal: _autoSpinClaimDone (set when isBusy goes false after dialog)
                -- Fallback signal: my item count increased (claimed pet auto-added to trade)
                autoSpinCountLbl.Text = "Pending: ".._G._autoSpinPending.." (claim the pet!)"
                w = 0
                while w < 120 do
                    task.wait(0.3); w = w + 0.3
                    if _G._autoSpinClaimDone then break end
                    -- fallback: pet was added to my offer = claim done
                    pcall(function()
                        local ts = mockState.trade
                        local items = ts and ts.sender_offer and ts.sender_offer.items
                        if items and #items > myCountBefore then
                            _G._autoSpinClaimDone = true
                        end
                    end)
                end
                spinState = "idle"; isBusy = false
                task.wait(0.3)
            end
            _G._autoSpinTriggered = false
            autoSpinCountLbl.Text = "Pending: 0"
        end)
    end
end)

end -- autoSpin do block
-- Static fallback high tier list (used until AMVGG loads)
local _HT_STATIC={
    "Shadow Dragon","Bat Dragon","Frost Dragon","Giraffe","Owl","Parrot","Crow",
    "Evil Unicorn","Arctic Reindeer","Hedgehog","Dalmatian","Turtle","Kangaroo",
    "Lion","Elephant","Rhino","Chocolate Chip Bat Dragon","Cow","Blazing Lion",
    "African Wild Dog","Flamingo","Diamond Butterfly","Mini Pig","Caterpillar",
    "Albino Monkey","Candyfloss Chick","Pelican","Blue Dog","Pink Cat","Haetae",
    "Peppermint Penguin","Winged Tiger","Sugar Glider","Shark Puppy","Goat",
    "Sheeeeep","Lion Cub","Nessie","Frostbite Bear","Balloon Unicorn",
    "Honey Badger","Hot Doggo","Crocodile","Hare","Ram","Yeti","Meetkat",
    "Jellyfish","Happy Clown","Orchid Butterfly","Many Mackerel",
    "Strawberry Shortcake Bat Dragon","Zombie Buffalo","Fairy Bat Dragon",
    "Strawberry Penguin","Frost Unicorn","Papa Moose","Dango Penguins",
    "Monkey King","Cryptid","Diamond Amazon","Arctic Dusk Dragon",
    "Pirate Ghost Capuchin Monkey","Alpaca","Border Collie","Irish Water Spaniel",
    "Mermicorn","Mechapup","Giant Panda","Fallow Deer","Tortuga De La Isla",
    "Glacier Kitsune","Undead Jousting Horse","Jekyll Hydra","Field mouse",
    "Werewolf","Platypus","Snowball Pug","Diamond Hamster","Moose Calf",
    "Bush Elephant","Meerkat","Puffin","Ring-Tailed Lemur","Christmas Pudding Pup",
    "Goose","Cabbit","Unicorn","Pig","Grim Dragon","Frost Fury","Cupid Dragon",
    "Midnight Dragon","Brown Bear","Polar Bear","Groundhog","Dragonfruit Fox",
}
-- HighTierPets: live list, rebuilt from AMVGG (fr >= 0.1). Falls back to _HT_STATIC.
local HighTierPets = {table.unpack(_HT_STATIC)}
local function _rebuildHTFromAMVGG(cache)
    if not cache then return end
    local filtered = {}
    for _, name in ipairs(_HT_STATIC) do
        local pd = cache[name:lower()]
        if pd and (pd.fr or 0) >= 0.1 then
            filtered[#filtered+1] = name
        end
    end
    if #filtered > 0 then
        -- replace contents of HighTierPets in place so all existing references see the update
        for i = #HighTierPets, 1, -1 do HighTierPets[i] = nil end
        for i, v in ipairs(filtered) do HighTierPets[i] = v end
    end
end
-- Kick off the filter as soon as AMVGG is available (non-blocking)
task.spawn(function()
    if type(_G._fetchAmvgg) == "function" then
        _G._fetchAmvgg(function(cache)
            _rebuildHTFromAMVGG(cache)
            -- Refresh NamesBox if it already has all high tiers loaded
            pcall(function()
                if NamesBox and NamesBox.Parent and NamesBox.Text ~= "" then
                    NamesBox.Text = table.concat(HighTierPets, ", ")
                end
            end)
        end)
    end
end)

local htList = mk("Frame", {Size=UDim2.fromOffset(128,160)})
do -- htList/flags block
htList.BackgroundColor3=Color3.fromRGB(25,25,35)
htList.BorderSizePixel=0 htList.Visible=false htList.ZIndex=100
htList.Parent=Players.LocalPlayer.PlayerGui:WaitForChild("MockTradeControl")
htList.ClipsDescendants=false
Instance.new("UICorner",htList).CornerRadius=UDim.new(0,5)
local htStroke2 = mk("UIStroke", {Color=Color3.fromRGB(190,34,230)})
htStroke2.Thickness=1.5 htStroke2.Parent=htList

local htScroll=Instance.new("ScrollingFrame")
htScroll.Size=UDim2.new(1,-4,1,-4) htScroll.Position=UDim2.new(0,2,0,2)
htScroll.BackgroundTransparency=1 htScroll.BorderSizePixel=0
htScroll.ScrollBarThickness=3 htScroll.ScrollBarImageColor3=Color3.fromRGB(190,34,230)
htScroll.CanvasSize=UDim2.new(0,0,0,0) htScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
htScroll.ZIndex=101 htScroll.Parent=htList

local htLayout2 = mk("UIListLayout", {Padding=UDim.new(0,2)})
htLayout2.SortOrder=Enum.SortOrder.LayoutOrder htLayout2.Parent=htScroll
local htPad=Instance.new("UIPadding") htPad.PaddingTop=UDim.new(0,3) htPad.PaddingLeft=UDim.new(0,3)
htPad.PaddingRight=UDim.new(0,3) htPad.Parent=htScroll

local htAllBtn=Instance.new("TextButton")
htAllBtn.Size=UDim2.new(1,0,0,14) htAllBtn.LayoutOrder=0
htAllBtn.BackgroundColor3=Color3.fromRGB(180,120,50)
htAllBtn.Text="⚡ Add ALL" htAllBtn.Font=Enum.Font.FredokaOne htAllBtn.TextSize=7
htAllBtn.TextColor3=Color3.fromRGB(255,255,255) htAllBtn.BorderSizePixel=0
htAllBtn.ZIndex=102 htAllBtn.Parent=htScroll
Instance.new("UICorner",htAllBtn).CornerRadius=UDim.new(0,3)
htAllBtn.MouseButton1Click:Connect(function()
    NamesBox.Text=table.concat(HighTierPets,", ")
    htList.Visible=false
end)

for i,petName in ipairs(HighTierPets) do
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,0,13) btn.LayoutOrder=i
    btn.BackgroundColor3=Color3.fromRGB(40,40,50)
    btn.BackgroundTransparency=0.2
    btn.Text=petName btn.Font=Enum.Font.FredokaOne btn.TextSize=7
    btn.TextColor3=Color3.fromRGB(255,255,255)
    btn.TextXAlignment=Enum.TextXAlignment.Left
    btn.BorderSizePixel=0 btn.ZIndex=102 btn.Parent=htScroll
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,3)
    local bp=Instance.new("UIPadding") bp.PaddingLeft=UDim.new(0,4) bp.Parent=btn
    btn.MouseButton1Click:Connect(function()
        local cur=NamesBox.Text:match("^%s*(.-)%s*$")
        NamesBox.Text=cur=="" and petName or cur..", "..petName
        htList.Visible=false
    end)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(55,55,70)}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(40,40,50)}):Play()
    end)
end

local function updateHTListPos()
    local mf = _G._tradeGuiMainFrame
    if mf then
        local p = mf.AbsolutePosition
        local s = mf.AbsoluteSize
        htList.Position = UDim2.fromOffset(p.X + s.X + 6, p.Y)
    end
end
htBtn.MouseButton1Click:Connect(function()
    htList.Visible=not htList.Visible
    if htList.Visible then updateHTListPos() end
end)
UserInputService.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 and htList.Visible then
        local mp=i.Position; local ap=htList.AbsolutePosition; local as=htList.AbsoluteSize
        if not(mp.X>=ap.X and mp.X<=ap.X+as.X and mp.Y>=ap.Y and mp.Y<=ap.Y+as.Y) then
            htList.Visible=false
        end
    end
end)

-- FLAGS (on main Spin tab)
local activeMutations=activeMutations or {}
local activeFlags={M=true,N=false,F=true,R=true}
-- pre-apply MFR mutations so doSpin picks them up from the start
activeMutations.megaNeon=true activeMutations.fly=true activeMutations.ride=true

local flagsLbl = mk("TextLabel", {Size=UDim2.new(1,0,0,9), Position=UDim2.new(0,0,0,75), BackgroundTransparency=1, Text="Flags", Font=Enum.Font.SourceSansSemibold, TextSize=7, TextColor3=Color3.fromRGB(180,180,180), TextXAlignment=Enum.TextXAlignment.Left, Parent=spinFrame})

local prefixDefs={
    {key="M",mutKey="megaNeon",label="M",col=Color3.fromRGB(170,0,255)},
    {key="N",mutKey="neon",    label="N",col=Color3.fromRGB(0,190,80)},
    {key="F",mutKey="fly",     label="F",col=Color3.fromRGB(0,175,255)},
    {key="R",mutKey="ride",    label="R",col=Color3.fromRGB(255,45,145)},
}
local prefBtns={}
local btnW=26; local btnH=18
local btnGap=math.floor((116-btnW*4)/3)

for i,pd in ipairs(prefixDefs) do
    local xOff=(i-1)*(btnW+btnGap)
    local pb = mk("TextButton", {Size=UDim2.new(0,btnW,0,btnH), Position=UDim2.new(0,xOff,0,89), BackgroundColor3=Color3.fromRGB(22,22,34)})
    pb.Text=pd.label pb.Font=Enum.Font.GothamBold pb.TextSize=10
    pb.TextColor3=Color3.fromRGB(220,220,220)
    pb.BorderSizePixel=0 pb.Parent=spinFrame
    Instance.new("UICorner",pb).CornerRadius=UDim.new(0,4)
    local s = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
    s.Color=pd.col s.Thickness=1.5 s.Transparency=0.35 s.Parent=pb
    local ts = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual})
    ts.Color=Color3.new(0,0,0) ts.Thickness=0.8 ts.Transparency=0.5 ts.Parent=pb
    prefBtns[pd.key]={btn=pb,stroke=s,textStroke=ts,col=pd.col,mutKey=pd.mutKey}
    pb.MouseButton1Click:Connect(function()
        if pd.key=="M" and activeFlags["N"] then return end
        if pd.key=="N" and activeFlags["M"] then return end
        activeFlags[pd.key]=not activeFlags[pd.key]
        activeMutations[pd.mutKey]=activeFlags[pd.key] or nil
        if activeFlags[pd.key] then
            TweenService:Create(pb,TweenInfo.new(0.15,Enum.EasingStyle.Quint),{BackgroundColor3=Color3.fromRGB(75,75,85)}):Play()
            TweenService:Create(s,TweenInfo.new(0.15),{Color=Color3.fromRGB(60,220,110),Thickness=1.8,Transparency=0}):Play()
        else
            TweenService:Create(pb,TweenInfo.new(0.15,Enum.EasingStyle.Quint),{BackgroundColor3=Color3.fromRGB(22,22,34)}):Play()
            TweenService:Create(s,TweenInfo.new(0.15),{Color=pd.col,Thickness=1.5,Transparency=0.35}):Play()
        end
        updateInfoBox()
    end)
end

local infoBox = mk("Frame", {Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,113), BackgroundColor3=Color3.fromRGB(0,0,0), BackgroundTransparency=0.42, Parent=spinFrame})
Instance.new("UICorner",infoBox).CornerRadius=UDim.new(0,5)
local ibS=Instance.new("UIStroke")
ibS.Color=Color3.fromRGB(200,200,210) ibS.Thickness=1.2 ibS.Transparency=0.6 ibS.Parent=infoBox
local ibLayout = mk("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, HorizontalAlignment=Enum.HorizontalAlignment.Center, VerticalAlignment=Enum.VerticalAlignment.Center})
ibLayout.Padding=UDim.new(0,4) ibLayout.Parent=infoBox

local flagCols={M=Color3.fromRGB(170,0,255),N=Color3.fromRGB(0,190,80),F=Color3.fromRGB(0,175,255),R=Color3.fromRGB(255,45,145)}

function updateInfoBox()
    for _,ch in ipairs(infoBox:GetChildren()) do if ch:IsA("TextLabel") then ch:Destroy() end end
    local cols,hasAny={},false
    for _,k in ipairs({"M","N","F","R"}) do
        if activeFlags[k] then
            hasAny=true; table.insert(cols,flagCols[k])
            local lbl=Instance.new("TextLabel")
            lbl.Size=UDim2.new(0,0,1,0) lbl.AutomaticSize=Enum.AutomaticSize.X
            lbl.BackgroundTransparency=1
            lbl.Text=k=="M" and "Mega Neon" or k=="N" and "Neon" or k=="F" and "Fly" or "Ride"
            lbl.Font=Enum.Font.FredokaOne lbl.TextSize=9
            lbl.TextColor3=flagCols[k]
            lbl.TextXAlignment=Enum.TextXAlignment.Center lbl.TextYAlignment=Enum.TextYAlignment.Center
            lbl.Parent=infoBox
        end
    end
    if not hasAny then
        local lbl=Instance.new("TextLabel")
        lbl.Size=UDim2.new(0,0,1,0) lbl.AutomaticSize=Enum.AutomaticSize.X
        lbl.BackgroundTransparency=1 lbl.Text="Normal"
        lbl.Font=Enum.Font.FredokaOne lbl.TextSize=9
        lbl.TextColor3=Color3.fromRGB(255,255,255)
        lbl.TextXAlignment=Enum.TextXAlignment.Center lbl.TextYAlignment=Enum.TextYAlignment.Center
        lbl.Parent=infoBox
        TweenService:Create(ibS,TweenInfo.new(0.2),{Color=Color3.fromRGB(200,200,210),Thickness=1.2,Transparency=0.5}):Play()
    else
        local r,g,b=0,0,0
        for _,c in ipairs(cols) do r=r+c.R; g=g+c.G; b=b+c.B end
        TweenService:Create(ibS,TweenInfo.new(0.2),{Color=Color3.new(math.min(r/#cols,1),math.min(g/#cols,1),math.min(b/#cols,1)),Thickness=1.5,Transparency=0.2}):Play()
    end
end
updateInfoBox()

-- Apply MFR active visuals to flag buttons that start ON
for _, pd in ipairs(prefixDefs) do
    if activeFlags[pd.key] then
        local bt = prefBtns[pd.key]
        if bt then
            bt.btn.BackgroundColor3 = Color3.fromRGB(75,75,85)
            bt.stroke.Color = Color3.fromRGB(60,220,110)
            bt.stroke.Thickness = 1.8
            bt.stroke.Transparency = 0
        end
    end
end

-- Auto-populate NamesBox with all high tiers on load
NamesBox.Text = table.concat(HighTierPets, ", ")
end -- htList do block

do -- prefsFrame block
local prefsFrame=tabFrames["Prefs"]

local pulsationTweens={}
local function makePrefRow(parent, labelText, defaultVal, y)
    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(1,0,0,8) lbl.Position=UDim2.new(0,0,0,y)
    lbl.BackgroundTransparency=1 lbl.Text=labelText
    lbl.Font=Enum.Font.SourceSansSemibold lbl.TextSize=7
    lbl.TextColor3=Color3.fromRGB(180,180,180)
    lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.Parent=parent

    local box=Instance.new("TextBox")
    box.Size=UDim2.new(1,0,0,14) box.Position=UDim2.new(0,0,0,y+9)
    box.BackgroundColor3=Color3.fromRGB(40,40,50)
    box.BackgroundTransparency=0.2
    box.Text=defaultVal
    box.Font=Enum.Font.SourceSans lbl.TextSize=7
    box.TextSize=7 box.TextColor3=Color3.fromRGB(255,255,255)
    box.ClearTextOnFocus=false
    box.TextXAlignment=Enum.TextXAlignment.Left
    box.TextTruncate=Enum.TextTruncate.AtEnd
    box.ClipsDescendants=true
    box.BorderSizePixel=0 box.Parent=parent
    Instance.new("UICorner",box).CornerRadius=UDim.new(0,3)
    local pad=Instance.new("UIPadding") pad.PaddingLeft=UDim.new(0,4) pad.Parent=box
    local s = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
    s.Color=Color3.fromRGB(80,80,80) s.Thickness=0.7 s.Transparency=0.5 s.Parent=box
    box.Focused:Connect(function()
        if pulsationTweens[box] then pulsationTweens[box]:Cancel() end
        pulsationTweens[box]=TweenService:Create(s,TweenInfo.new(0.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{ Color=Color3.fromRGB(190,34,230), Thickness=1.2, Transparency=0.2 })
        pulsationTweens[box]:Play()
    end)
    box.FocusLost:Connect(function()
        if pulsationTweens[box] then pulsationTweens[box]:Cancel(); pulsationTweens[box]=nil end
        TweenService:Create(s,TweenInfo.new(0.3,Enum.EasingStyle.Quad),{ Color=Color3.fromRGB(80,80,80), Thickness=0.7, Transparency=0.5 }):Play()
    end)
    return box
end

local taglineBox  = makePrefRow(prefsFrame, "Tagline text",   PREFS.tagline,    0)
local spinTxtBox  = makePrefRow(prefsFrame, "Spinning text",  PREFS.spinText,  25)
local dialogTxtBox= makePrefRow(prefsFrame, "Dialog prefix",  PREFS.dialogText,50)

taglineBox.FocusLost:Connect(function()
    if taglineBox.Text~="" then PREFS.tagline=taglineBox.Text end
end)
spinTxtBox.FocusLost:Connect(function()
    if spinTxtBox.Text~="" then PREFS.spinText=spinTxtBox.Text end
end)
dialogTxtBox.FocusLost:Connect(function()
    PREFS.dialogText=dialogTxtBox.Text
end)

local function makeToggleRow(parent, y, labelText, initVal, onChange)
    local row=Instance.new("Frame")
    row.Size=UDim2.new(1,0,0,13) row.Position=UDim2.new(0,0,0,y)
    row.BackgroundTransparency=1 row.Parent=parent
    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(0.675,0,1,0) lbl.BackgroundTransparency=1
    lbl.Text=labelText lbl.Font=Enum.Font.SourceSansSemibold lbl.TextSize=7
    lbl.TextColor3=Color3.fromRGB(180,180,180)
    lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.Parent=row
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(0.315,0,1,0) btn.Position=UDim2.new(0.685,0,0,0)
    btn.BackgroundColor3=initVal and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)
    btn.BackgroundTransparency=0.2
    btn.Text=initVal and "ON" or "OFF"
    btn.Font=Enum.Font.FredokaOne btn.TextSize=7
    btn.TextColor3=initVal and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
    btn.BorderSizePixel=0 btn.Parent=row
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,3)
    local bStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=initVal and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)})
    bStroke.Thickness=0.7 bStroke.Transparency=0.3 bStroke.Parent=btn
    local state=initVal
    btn.MouseButton1Click:Connect(function()
        state=not state
        btn.Text=state and "ON" or "OFF"
        btn.TextColor3=state and Color3.fromRGB(80,255,130) or Color3.fromRGB(255,90,90)
        TweenService:Create(btn,TweenInfo.new(0.2),
            {BackgroundColor3=state and Color3.fromRGB(30,80,50) or Color3.fromRGB(80,30,30)}):Play()
        TweenService:Create(bStroke,TweenInfo.new(0.2),
            {Color=state and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,60,60)}):Play()
        onChange(state)
    end)
end

makeToggleRow(prefsFrame, 76, "Notebook Spiral", PREFS.showNotebookSpiral, function(val)
    PREFS.showNotebookSpiral=val
    pcall(function()
        PlayerGui.DailyLoginApp.Frame.Header.NotebookSpiral.Visible=val
    end)
end)

makeToggleRow(prefsFrame, 92, "Show Eggs in Spin", PREFS.showEggs, function(val)
    PREFS.showEggs=val
end)

makeToggleRow(prefsFrame, 108, "Random Filler Kinds", PREFS.randomKinds, function(val)
    PREFS.randomKinds=val
end)

local spinnerBpBtn = nil
makeToggleRow(prefsFrame, 124, "Spin Backpack Button", false, function(val)
    if val then
        task.spawn(function()
            local toolApp, hotbar, openBackpack
            for _=1,20 do
                toolApp = PlayerGui:FindFirstChild("ToolApp", true)
                hotbar = toolApp and toolApp:FindFirstChild("Hotbar", true)
                openBackpack = hotbar and hotbar:FindFirstChild("OpenBackpack", true)
                if openBackpack then break end
                task.wait(0.2)
            end
            if not openBackpack then return end

            local rPos = openBackpack.AbsolutePosition
            local rSz  = openBackpack.AbsoluteSize
            local sz   = math.floor(rSz.X * 0.85)

            spinnerBpBtn = openBackpack:Clone()
            spinnerBpBtn.Name     = "SpinnerOpenBackpack"; spinnerBpBtn.Size     = UDim2.fromOffset(sz, sz)
            spinnerBpBtn.Position = UDim2.fromOffset(rPos.X - sz - 10, rPos.Y + (rSz.Y-sz)/2); spinnerBpBtn.ZIndex   = 20

            pcall(function()
                local CTM = fsysLoad("ColorThemeManager")
                CTM.exclude_instance_from_color_themeing(spinnerBpBtn)
                for _,v in ipairs(spinnerBpBtn:GetDescendants()) do
                    CTM.exclude_instance_from_color_themeing(v)
                end
            end)

            local GREEN = Color3.fromRGB(55, 185, 65)
            local innerColor = spinnerBpBtn:FindFirstChild("InnerColor")
            if innerColor then
                innerColor.ImageColor3 = GREEN
                innerColor:GetPropertyChangedSignal("ImageColor3"):Connect(function()
                    if innerColor.ImageColor3 ~= GREEN then
                        innerColor.ImageColor3 = GREEN
                    end
                end)
            end

            spinnerBpBtn.Parent = hotbar

            -- Find the clickable button inside and hook it
            local _bpDebounce = false
            local function hookClicks(root)
                for _, c in ipairs(root:GetDescendants()) do
                    if c:IsA("ImageButton") or c:IsA("TextButton") then
                        c.MouseButton1Click:Connect(function()
                            if spinState ~= "idle" then return end
                            if _bpDebounce then return end
                            _bpDebounce = true
                            task.spawn(openSpinnerPicker)
                            task.delay(1, function() _bpDebounce = false end)
                        end)
                    end
                end
                if root:IsA("ImageButton") or root:IsA("TextButton") then
                    root.MouseButton1Click:Connect(function()
                        if spinState ~= "idle" then return end
                        if _bpDebounce then return end
                        _bpDebounce = true
                        task.spawn(openSpinnerPicker)
                        task.delay(1, function() _bpDebounce = false end)
                    end)
                end
            end
            hookClicks(spinnerBpBtn)

            task.spawn(function()
                while spinnerBpBtn and spinnerBpBtn.Parent do
                    local op = openBackpack.AbsolutePosition
                    local os = openBackpack.AbsoluteSize
                    spinnerBpBtn.Position = UDim2.fromOffset(op.X - sz - 10, op.Y + (os.Y-sz)/2)
                    task.wait(0.5)
                end
            end)
        end)
    else
        if spinnerBpBtn then spinnerBpBtn:Destroy(); spinnerBpBtn=nil end
    end
end)

local selectedPetUnique = nil
local selectedPetName = "None"

local selectLbl=Instance.new("TextLabel")
selectLbl.Size=UDim2.new(1,0,0,8) selectLbl.Position=UDim2.new(0,0,0,156)
selectLbl.BackgroundTransparency=1 selectLbl.Text="🐾 Boost Pet"
selectLbl.Font=Enum.Font.SourceSansSemibold selectLbl.TextSize=7
selectLbl.TextColor3=Color3.fromRGB(180,180,180)
selectLbl.TextXAlignment=Enum.TextXAlignment.Left selectLbl.Parent=prefsFrame

local selectedLbl=Instance.new("TextLabel")
selectedLbl.Size=UDim2.new(1,0,0,8) selectedLbl.Position=UDim2.new(0,0,0,165)
selectedLbl.BackgroundTransparency=1 selectedLbl.Text="Selected: None"
selectedLbl.Font=Enum.Font.SourceSans selectedLbl.TextSize=7
selectedLbl.TextColor3=Color3.fromRGB(120,180,255)
selectedLbl.TextXAlignment=Enum.TextXAlignment.Left selectedLbl.Parent=prefsFrame

selectBtn=Instance.new("TextButton")
selectBtn.Size=UDim2.new(1,0,0,14) selectBtn.Position=UDim2.new(0,0,0,175)
selectBtn.BackgroundColor3=Color3.fromRGB(40,40,50)
selectBtn.BackgroundTransparency=0.2
selectBtn.Text="Select Pet..."
selectBtn.Font=Enum.Font.FredokaOne selectBtn.TextSize=7
selectBtn.TextColor3=Color3.fromRGB(200,210,255)
selectBtn.BorderSizePixel=0 selectBtn.Parent=prefsFrame
Instance.new("UICorner",selectBtn).CornerRadius=UDim.new(0,3)
local selStroke = mk("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
selStroke.Color=Color3.fromRGB(190,34,230) selStroke.Thickness=0.8
selStroke.Transparency=0.4 selStroke.Parent=selectBtn

local _pickerBody = function()
    pcall(function()
        local BackpackApp = UIManager and UIManager.apps and UIManager.apps.BackpackApp
        if BackpackApp and BackpackApp:is_picking_item() then
            BackpackApp:try_pick_item(nil)
            task.wait(0.1)
        end
        -- so pick_item starts from a clean state (no add button visible)
        if BackpackApp and UIManager.is_visible("BackpackApp") then
            UIManager.set_app_visibility("BackpackApp", false)
            task.wait(0.05)
        end
    end)
    task.spawn(function()
        pcall(function()
            if type(setthreadidentity)=="function" then setthreadidentity(2) end
            local BackpackApp = UIManager and UIManager.apps and UIManager.apps.BackpackApp
            if not BackpackApp then return end

            local frame = BackpackApp.instance.Frame
            local body = frame:FindFirstChild("Body")
            local cats = body and body:FindFirstChild("Categories")
            local scrollComplex = body and body:FindFirstChild("ScrollComplex")

            local origCatsVisible  = cats and cats.Visible
            local origScrollSize   = scrollComplex and scrollComplex.Size
            local origScrollPos    = scrollComplex and scrollComplex.Position

            if cats then cats.Visible=false end

            local scrollComplex = body and body:FindFirstChild("ScrollComplex")
            local origScrollSize = scrollComplex and scrollComplex.Size
            local origScrollPos  = scrollComplex and scrollComplex.Position
            if scrollComplex then
                scrollComplex.Size     = UDim2.new(1, 0, scrollComplex.Size.Y.Scale, scrollComplex.Size.Y.Offset)
                scrollComplex.Position = UDim2.new(0, 0, scrollComplex.Position.Y.Scale, scrollComplex.Position.Y.Offset)
            end

            -- Hook BackpackItemGrid to use more cells per row and smaller size
            local BackpackItemGrid = pcall(fsysLoad, "BackpackItemGrid") and fsysLoad("BackpackItemGrid")
            local origStart      = BackpackItemGrid and BackpackItemGrid.start
            local origCreateCell = BackpackItemGrid and BackpackItemGrid._create_cell
            local origRenderRow  = BackpackItemGrid and BackpackItemGrid.render_row
            if BackpackItemGrid then
                BackpackItemGrid.start = function(self, app)
                    self.backpack_app = app
                    local VerticalGrid = fsysLoad("VerticalGrid")
                    VerticalGrid.start(self, app.scroll, app.content, { row_height    = 76, cells_per_row = 6, padding       = 0, })
                    return self
                end
                BackpackItemGrid._create_cell = function(self, col, order, data)
                    if data.type == "add_item" or data.type == "add_more" then
                        local dummy = mk("Frame", {Size=UDim2.fromOffset(0,0), BackgroundTransparency=1, LayoutOrder=order})
                        return dummy
                    end
                    local btn = self.backpack_app.button_creator[data.type](self.backpack_app.button_creator, data)
                    btn.Size        = UDim2.fromOffset(76, 76); btn.Position    = UDim2.fromOffset((col-1)*76, 0)
                    btn.LayoutOrder = order
                    return btn
                end
                BackpackItemGrid.render_row = function(self, rowIdx, cells)
                    local row = mk("Frame", {Name="Row"..rowIdx, BackgroundTransparency=1, Size=UDim2.new(1, 0, 0, 76)})
                    local base = rowIdx * 6
                    for i, data in ipairs(cells) do
                        self:_create_cell(i, base+i, data).Parent = row
                    end
                    return row
                end
            end

            local destroyedAddBtns = {}
            pcall(function()
                for _,v in ipairs(frame:GetDescendants()) do
                    local n = v.Name:lower()
                    if v:IsA("GuiObject") and (n == "addbutton" or n == "additem" or n:find("^add")) then
                        table.insert(destroyedAddBtns, {inst=v, parent=v.Parent, nextSibling=nil})
                        v.Parent = nil  -- detach without destroying so we can restore
                    end
                end
            end)
            local addBtn = scrollComplex and scrollComplex:FindFirstChild("AddButton", true)
            local origAddVis = addBtn and addBtn.Visible
            if addBtn then addBtn.Visible = false end

            local picked = BackpackApp:pick_item({
                visible_backpack_categories = {"pets"},
                keep_cached_scroll_positions_on_open = false,
                allow_callback = function(item)
                    return item.category == "pets"
                end,
            })

            if cats then cats.Visible = origCatsVisible end
            if scrollComplex and origScrollSize then
                scrollComplex.Size     = origScrollSize
                scrollComplex.Position = origScrollPos
            end
            if BackpackItemGrid and origStart then
                BackpackItemGrid.start       = origStart; BackpackItemGrid._create_cell = origCreateCell
                BackpackItemGrid.render_row  = origRenderRow
            end
            if addBtn then addBtn.Visible = origAddVis end
            for _,entry in ipairs(destroyedAddBtns) do
                pcall(function() entry.inst.Parent = entry.parent end)
            end
            pcall(function() BackpackApp:refresh_rendered_items() end)

            if picked then
                selectedPetUnique = picked.unique
                local IDB = fsysLoad("InventoryDB")
                local entry = IDB and IDB.pets and IDB.pets[picked.id]
                selectedPetName = (entry and entry.name) or picked.id
                selectedLbl.Text = "Selected: "..selectedPetName
                TweenService:Create(selStroke,TweenInfo.new(0.2),{Color=Color3.fromRGB(60,220,110),Thickness=1.5,Transparency=0}):Play()
                task.delay(1, function()
                    TweenService:Create(selStroke,TweenInfo.new(0.3),{Color=Color3.fromRGB(190,34,230),Thickness=0.8,Transparency=0.4}):Play()
                end)
                selectBtn.Text = selectedPetName

                local confirmed = false
                pcall(function()
                    local result = UIManager.apps.DialogApp:dialog({
                        dialog_type  = "ScrollingDialog",
                        use_stacks   = false,
                        items        = { picked },
                        labels       = {
                            { text    = "⚠️ You will NOT lose this pet!", size    = 34, padding = 20, },
                            { text    = "Your pet stays safe in your inventory and will not be affected. Ready to proceed?", size    = 22, padding = 16, },
                        },
                        left         = "Cancel",
                        right        = "Let's Spin!",
                        accept_delay = 2,
                        exit_button  = true,
                    })
                    confirmed = (result == "Yes" or result == "Let's Spin!")
                end)

                if not confirmed then
                    selectedPetUnique = nil
                    selectedPetName   = "None"
                    selectedLbl.Text  = "Selected: None"
                    selectBtn.Text    = "Select Pet..."
                    return
                end

                if spinState == "idle" then
                    spinState = "spinning"
                    task.spawn(function()
                        local target = TargetBox.Text:match("^%s*(.-)%s*$") or ""
                        doSpin(splitCSV(NamesBox.Text), target)
                    end)
                end
            end
        end)
    end)
end
_spinnerPickerFn = _pickerBody
selectBtn.MouseButton1Click:Connect(_pickerBody)

local prefNote=Instance.new("TextLabel")
prefNote.Size=UDim2.new(1,0,0,16) prefNote.Position=UDim2.new(0,0,0,194)
prefNote.BackgroundTransparency=1
prefNote.Text="Text changes apply next spin."
prefNote.Font=Enum.Font.SourceSans prefNote.TextSize=7
prefNote.TextColor3=Color3.fromRGB(120,120,150)
prefNote.TextXAlignment=Enum.TextXAlignment.Left
prefNote.TextWrapped=true prefNote.Parent=prefsFrame

-- Permanently hide extra buttons and expand ClaimButton whenever app is visible
task.spawn(function()
    local app
    repeat task.wait(0.1) 
        if UIManager then
            local ok,a = pcall(function() return UIManager.apps.DailyLoginApp end)
            if ok and a then app = a end
        end
    until app

    -- Hook claim_depth_button.set_state so it ALWAYS stays "normal" (green)
    -- The real DailyLoginApp calls set_state("cancel") when not claimable — we block that
    task.spawn(function()
        -- Wait for claim_depth_button to be assigned (it's set in app:start())
        local deadline = tick() + 10
        while not app.claim_depth_button and tick() < deadline do task.wait(0.1) end
        pcall(function()
            local db = app.claim_depth_button
            if db and db.set_state then
                local _orig = db.set_state
                db.set_state = function(self, state)
                    -- Block "cancel" (red) — always use "normal" (green)
                    return _orig(self, "normal")
                end
                pcall(function() db:set_state("normal") end)
            end
        end)
    end)
    local function fixButtons()
        pcall(function()
            local buttons = PlayerGui.DailyLoginApp.Frame.Body.Buttons
            local layout = buttons:FindFirstChildOfClass("UIListLayout")
            if layout then layout:Destroy() end
            local claimAd = buttons:FindFirstChild("ClaimAdButton")
            local milestones = buttons:FindFirstChild("MilestonesButton")
            if claimAd then claimAd:Destroy() end
            if milestones then milestones:Destroy() end
            local h = buttons.AbsoluteSize.Y > 0 and buttons.AbsoluteSize.Y or 48
            buttons.Size = UDim2.new(1, -60, 0, h)
            pcall(function()
                local tagline = PlayerGui.DailyLoginApp.Frame.Body.TaglineArea.Tagline
                tagline.Text = PREFS.tagline
            end)
            pcall(function()
            end)
            local claimBtn = buttons:FindFirstChild("ClaimButton")
            if claimBtn then
                claimBtn.Size        = UDim2.new(1, 0, 1, 0); claimBtn.Position    = UDim2.new(0, 0, 0.5, 0)
                claimBtn.AnchorPoint = Vector2.new(0, 0.5)
                -- Green is handled by the claim_depth_button.set_state hook above
                claimBtn.MouseButton1Click:Connect(function()
                    if spinState ~= "claim" then return end
                    if not _G._spinnerWinner then return end
                    spinState = "idle"

                    PlayerGui.DailyLoginApp.Enabled = false

                    task.spawn(function()
                        if type(setthreadidentity)=="function" then setthreadidentity(2)
                        elseif type(syn)=="table" and syn.set_thread_identity then syn.set_thread_identity(2)
                        elseif type(setthreadcontext)=="function" then setthreadcontext(2) end

                        local winner = _G._spinnerWinner
                        local dialogApp = UIManager.apps.DialogApp
                        dialogApp:dialog({
                            dialog_type = "ItemPreviewDialog",
                            text        = PREFS.dialogText..winner.name.."!",
                            button      = "Claim!",
                            item        = {
                                id         = winner.id,
                                kind       = winner.id,
                                category   = "pets",
                                unique     = "spinner_"..winner.id,
                                image      = winner.image,
                                properties = { flyable   = activeMutations.fly      == true, rideable  = activeMutations.ride     == true, neon      = activeMutations.neon     == true, mega_neon = activeMutations.megaNeon == true, }
                            },
                            yields = true,
                        })

                        pcall(function()
                            local props = {
                                flyable           = activeMutations.fly      == true,
                                rideable          = activeMutations.ride     == true,
                                neon              = activeMutations.neon     == true,
                                mega_neon         = activeMutations.megaNeon == true,
                                age               = 6,
                                ailments_completed = 0,
                                rp_name           = "",
                                pet_trick_level   = 0,
                            }
                            addSpinPetToTrade(winner.id, props)
                        end)
                        if lastCentredCard then
                            setFrameColor(lastCentredCard,COL_NORMAL)
                            setCardScale(lastCentredCard,SCALE_NORMAL_V,true)
                            lastCentredCard=nil
                        end
                        local appRef = UIManager and UIManager.apps and UIManager.apps.DailyLoginApp
                        if appRef then destroyReel(appRef); closeApp(appRef) end
                        StatusLbl.Text="Ready."
                        StatusLbl.TextColor3=Color3.fromRGB(190,34,230)
                        SpinBtn.Text="SPIN!"
                        TweenService:Create(SpinBtn,TweenInfo.new(0.15),{BackgroundColor3=Color3.fromRGB(30,80,50)}):Play()
                        isBusy=false
                        _G._spinnerWinner=nil
                    end)
                end)
            end
        end)
    end
    fixButtons()
    app.instance.Frame:GetPropertyChangedSignal("Visible"):Connect(function()
        if app.instance.Frame.Visible then
            task.wait(0.05) fixButtons()
            task.wait(0.1)  fixButtons()
            task.wait(0.2)  fixButtons()
        end
    end)
    pcall(function()
        local claimBtn = PlayerGui.DailyLoginApp.Frame.Body.Buttons.ClaimButton
        claimBtn:GetPropertyChangedSignal("Size"):Connect(function()
            task.wait(0.05)
            fixButtons()
        end)
    end)
end)

end -- prefsFrame do block
end -- SPIN TAB do block

end local dragging, dragStart, startPos
mainFrame.InputBegan:Connect(function(input)
    if _G._guiLocked then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging  = true
        dragStart = input.Position
        startPos  = mainFrame.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and not _G._guiLocked and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
        blackFrame.Position = UDim2.new(
            mainFrame.Position.X.Scale, mainFrame.Position.X.Offset - 3,
            mainFrame.Position.Y.Scale, mainFrame.Position.Y.Offset - 3
        )
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ════════════════════════════════════════════════════════════════════════
--  GUI LOCK (🔒 button).  While locked the GUI:
--    * sits above everything     DisplayOrder is pinned to the maximum and re-asserted if changed
--    * never moves               main window + border are pinned to their position (any code that
--                                tries to move them is snapped back); dragging is off everywhere
--    * blocks clicks underneath  every top-level panel is made Active, so mouse / touch input is
--                                consumed instead of reaching game UI or the 3D world behind it
--  Unlocking restores DisplayOrder, Active flags and free movement.
-- ════════════════════════════════════════════════════════════════════
do
local function _guiLockSetup()
    local gui = controlGui
    local MAX_ORDER = 2147483647
    local normalOrder = gui.DisplayOrder
    local savedActive, pinned, pinConns, extra = {}, {}, {}, {}

    local function sinkInput(inst)
        if inst:IsA("GuiObject") then
            if savedActive[inst] == nil then savedActive[inst] = inst.Active end
            inst.Active = true
        end
    end
    local function pin(inst)
        if pinned[inst] then return end
        pinned[inst] = inst.Position
        pinConns[#pinConns + 1] = inst:GetPropertyChangedSignal("Position"):Connect(function()
            if _G._guiLocked and pinned[inst] and inst.Position ~= pinned[inst] then
                inst.Position = pinned[inst]
            end
        end)
    end

    -- DisplayOrder watcher lives for the life of the GUI and only acts while locked
    gui:GetPropertyChangedSignal("DisplayOrder"):Connect(function()
        if _G._guiLocked and gui.DisplayOrder ~= MAX_ORDER then gui.DisplayOrder = MAX_ORDER end
    end)
    -- pop-outs / panels added to the GUI while locked are covered too.
    -- Only TOP-LEVEL panels are made Active. Making every descendant Active (the first version)
    -- put Active labels / icons / content frames on top of the tab buttons and swallowed their clicks.
    gui.ChildAdded:Connect(function(c)
        if _G._guiLocked then sinkInput(c) end
    end)

    _G._applyGuiLock = function(locked)
        if locked then
            gui.DisplayOrder = MAX_ORDER
            for _, c in ipairs(gui:GetChildren()) do sinkInput(c) end
            pin(mainFrame)
            pin(blackFrame)
            dragging = false      -- cancel any drag already in progress
        else
            for _, c in ipairs(pinConns) do c:Disconnect() end
            pinConns, pinned = {}, {}
            for inst, was in pairs(savedActive) do
                if inst.Parent then inst.Active = was end
            end
            savedActive = {}
            gui.DisplayOrder = normalOrder
        end
    end
end
local _glOk, _glErr = pcall(_guiLockSetup)
if not _glOk then warn("[GuiLock] " .. tostring(_glErr)) end
-- AUTO-LOCK: the GUI starts locked (🔒) at the far left of the screen; press the lock button in the Misc tab to unlock / drag it.
if _glOk and _G._applyGuiLock then
    _G._guiLocked = true
    pcall(_G._applyGuiLock, true)
    if _G._setGuiLockVisual then pcall(_G._setGuiLockVisual, true) end
end
end


-- =====================================================================
-- RICH BOARD TAB  (server players ranked by AMVGG profile value)
-- =====================================================================
do
local richFrame = tabFrames["Rich"]
if not richFrame then
    richFrame = mk("Frame", {Size=UDim2.new(0.9,0,1,-33), Position=UDim2.new(0.05,0,0,33), BackgroundTransparency=1, Visible=false, Parent=mainFrame})
    tabFrames["Rich"] = richFrame
end
_G._richBoard = richFrame

local Players          = game:GetService("Players")
local InventoryDB       = load("InventoryDB")
local RouterClient      = load("RouterClient")
local UIManager         = load("UIManager")

local function new(cls, props, parent)
    local o = Instance.new(cls)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 3) }, o) end

local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
}, richFrame)
new("TextLabel", {
    Size = UDim2.new(1, -25, 1, 0), BackgroundTransparency = 1,
    Text = "🏆 Rich Board", Font = Enum.Font.FredokaOne, TextSize = 9,
    TextColor3 = Color3.fromRGB(235, 200, 255), TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local refreshBtn = new("TextButton", {
    Size = UDim2.new(0, 21, 0, 13), Position = UDim2.new(1, -21, 0, 1),
    BackgroundColor3 = Color3.fromRGB(70, 40, 90), BackgroundTransparency = 0.1,
    Text = "↻", Font = Enum.Font.FredokaOne, TextSize = 9,
    TextColor3 = Color3.fromRGB(220, 170, 255), BorderSizePixel = 0,
}, header)
corner(refreshBtn, 3)
new("UIStroke", {ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Color=Color3.fromRGB(190,34,230), Thickness=0.7, Transparency=0.4}, refreshBtn)

local list = new("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, -19), Position = UDim2.new(0, 0, 0, 19),
    BackgroundColor3 = Color3.fromRGB(22, 22, 32), BackgroundTransparency = 0.4, BorderSizePixel = 0,
    ScrollBarThickness = 2, ScrollBarImageColor3 = Color3.fromRGB(120, 120, 120), ScrollBarImageTransparency = 0.5,
    CanvasSize = UDim2.new(0, 0, 0, 0),
}, richFrame)
corner(list, 4)
do local layout = new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, list)
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, list)
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
end)

end local status = new("TextLabel", {
    Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 0, 36), BackgroundTransparency = 1,
    Text = "Loading…", Font = Enum.Font.FredokaOne, TextSize = 8, TextColor3 = Color3.fromRGB(170, 170, 190),
    TextXAlignment = Enum.TextXAlignment.Center,
}, richFrame)

local fmt = _G._fmtVal or tostring

-- Total AMVGG value of a player's profile COLLECTION pets, using the SAME calculation
-- as the Misc-tab value calculator (_G._sumOffer → getPetVal/getVariantKey).
-- Dedupes by `unique`: the profile collection repeats the same pets across its
-- paginated widgets, which would otherwise multiply each player's value.
local function petListValue(pets, cache)
    local seen, items = {}, {}
    for _, item in ipairs(pets or {}) do
        if item.kind then
            local u = item.unique
            if not (u and seen[u]) then
                if u then seen[u] = true end
                table.insert(items, { category = "pets", kind = item.kind, properties = item.properties })
            end
        end
    end
    return _G._sumOffer(items, cache)
end

-- Fetch a player's REAL profile collection pets. For players in the server the game
-- reads the replicated profile via ClientData.get_server(player, "player_profile")
-- (FetchProfile is only used for offline players and returns empty for online ones).
-- Bypassed FetchProfile is kept as a fallback.
local ClientData   = load("ClientData")
-- uid -> { pets = {...}, t = os.clock(), empty = bool }
-- Old version cached forever (even EMPTY results, e.g. a player who just joined whose profile hadn't
-- replicated yet) and the refresh button never cleared it, so values could never update.
local realPetCache = {}

local function collectPets(profile, pets)
    if type(profile) ~= "table" then return end
    local pages = profile.pages or (profile.profile and profile.profile.pages)
    for _, page in ipairs(pages or {}) do
        for _, widget in ipairs(page.widgets or {}) do
            local wd = widget.data
            if wd and wd.widget_kind == "collection" then
                for _, item in ipairs((wd.widget_data and wd.widget_data.items) or {}) do
                    if item.kind then table.insert(pets, item) end
                end
            end
        end
    end
end

local function fetchRealPets(plr)
    local uid = plr.UserId
    local c = realPetCache[uid]
    if c and (os.clock() - c.t) < (c.empty and 30 or 120) then return c.pets end
    local pets = {}
    -- Primary: replicated profile (same source the game uses for in-server players)
    pcall(function() collectPets(ClientData.get_server(plr, "player_profile"), pets) end)
    -- Fallback: real FetchProfile, bypassing the fake-profile injection
    if #pets == 0 then
        _G._rlbRealFetch = true
        local ok, data = pcall(function()
            return RouterClient.get("PlayerProfileAPI/FetchProfile"):InvokeServer(uid)
        end)
        _G._rlbRealFetch = false
        if ok then collectPets(data, pets) end
    end
    realPetCache[uid] = { pets = pets, t = os.clock(), empty = (#pets == 0) }
    return pets
end

-- ── Equipped pets ─────────────────────────────────────────────────────
-- Reads the live pet char wrappers (the same source the anti-raid uses for pet names) to see which
-- pets each player currently has out. These are added on top of the profile collection, so a player
-- with a blank profile but an Owl equipped still shows up on the board.
local EQ = {}
function EQ.scan()
    local byOwner = {}
    local CWC; pcall(function() CWC = load("CharWrapperClient") end)
    if not CWC then return byOwner end
    local ok, wrappers = pcall(CWC.get_all_char_wrappers)
    if not ok or type(wrappers) ~= "table" then return byOwner end
    local fake = _spawnerPets or {}                    -- pets made by the Spawner tab never count
    local db = InventoryDB and InventoryDB.pets or {}
    for _, w in pairs(wrappers) do
        local owner = w.player
        local kind = w.pet_id or w.pet_kind
        if w.pet_unique and kind and db[kind] and typeof(owner) == "Instance" and owner:IsA("Player")
           and not fake[w.pet_unique] then
            local list = byOwner[owner]
            if not list then list = {}; byOwner[owner] = list end
            list[#list + 1] = {
                category = "pets", kind = kind, unique = w.pet_unique,
                properties = {
                    neon = w.neon == true, mega_neon = w.mega_neon == true,
                    flyable = w.flyable == true, rideable = w.rideable == true,
                },
            }
        end
    end
    return byOwner
end
-- Returns the extra equipped items that are NOT already in the profile list (same unique, or same
-- kind + variant, counts as already there so nothing is double counted).
function EQ.extra(profilePets, equipped)
    local haveU, haveV = {}, {}
    local vk = _G._getVariantKey or function() return "r" end
    for _, it in ipairs(profilePets or {}) do
        if it.unique then haveU[it.unique] = true end
        if it.kind then haveV[it.kind .. "|" .. vk(it.properties)] = true end
    end
    local out = {}
    for _, it in ipairs(equipped or {}) do
        local key = it.kind .. "|" .. vk(it.properties)
        if not haveU[it.unique] and not haveV[key] then
            out[#out + 1] = it
            haveV[key] = true
        end
    end
    return out
end
-- Most valuable single pet in a player's list (profile + equipped extras) -> { name, value } or nil
function EQ.top(pets, extra, cache)
    local best, bestV, seen = nil, 0, {}
    local vk = _G._getVariantKey or function() return "r" end
    local function consider(list)
        for _, it in ipairs(list or {}) do
            if it.kind then
                local key = it.kind .. "|" .. vk(it.properties)
                if not seen[key] then
                    seen[key] = true
                    local ok, v = pcall(_G._sumOffer, { { category = "pets", kind = it.kind, properties = it.properties } }, cache)
                    if ok and type(v) == "number" and v > bestV then best, bestV = it, v end
                end
            end
        end
    end
    consider(pets); consider(extra)
    if not best then return nil end
    local p, nm = best.properties or {}, "Pet"
    pcall(function() nm = InventoryDB.pets[best.kind].name or nm end)
    local tag = (p.mega_neon and "M" or (p.neon and "N" or "")) .. (p.flyable and "F" or "") .. (p.rideable and "R" or "")
    return { name = (tag ~= "" and (tag .. " ") or "") .. nm, value = bestV }
end
-- Debug: run `_G._rbDumpEquipped()` to print every field the game puts on other players' pet wrappers
-- (use it to check flyable / rideable / pet_id are what this code expects).
_G._rbDumpEquipped = function()
    local CWC; pcall(function() CWC = load("CharWrapperClient") end)
    local ok, wrappers = pcall(CWC.get_all_char_wrappers)
    if not ok then return warn("[RichBoard] no wrappers: " .. tostring(wrappers)) end
    for _, w in pairs(wrappers) do
        if w.pet_unique then
            local keys = {}
            for k, v in pairs(w) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
            table.sort(keys)
            print("[RichBoard] " .. tostring(w.player) .. " -> " .. table.concat(keys, ", "))
        end
    end
end

-- ── Selection / block bar (top of the tab) ────────────────────────────
-- Normal mode : tap a player's row -> Trade / Profile buttons slide out under it.
-- Select mode : tap rows to tick players; the bar blocks everyone ticked, one at a time (silent block).
local SEL = { mode = false, ids = {}, busy = false, open = nil }
SEL.actionBar = new("Frame", {
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 18), BackgroundTransparency = 1,
}, richFrame)
SEL.enterBtn = new("TextButton", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 40, 48), BackgroundTransparency = 0.1,
    Text = "☑  Select players to block", Font = Enum.Font.FredokaOne, TextSize = 7,
    TextColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0,
}, SEL.actionBar)
corner(SEL.enterBtn, 3)
SEL.selectBar = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, SEL.actionBar)
SEL.blockBtn = new("TextButton", {
    Size = UDim2.new(1, -69, 1, 0), BackgroundColor3 = Color3.fromRGB(90, 40, 44), BackgroundTransparency = 0.1,
    Text = "Block selected (0)", Font = Enum.Font.FredokaOne, TextSize = 7,
    TextColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0,
}, SEL.selectBar)
corner(SEL.blockBtn, 3)
function SEL.barBtn(text, x, w)
    local b = new("TextButton", {
        Size = UDim2.new(0, w or 21, 1, 0), Position = UDim2.new(1, x, 0, 0),
        BackgroundColor3 = Color3.fromRGB(50, 50, 64), BackgroundTransparency = 0.1,
        Text = text, Font = Enum.Font.FredokaOne, TextSize = 6,
        TextColor3 = Color3.fromRGB(200, 200, 220), BorderSizePixel = 0,
    }, SEL.selectBar)
    corner(b, 3)
    return b
end
SEL.allBtn, SEL.noneBtn, SEL.doneBtn = SEL.barBtn("All", -66), SEL.barBtn("None", -43), SEL.barBtn("✕", -20, 20)
list.Position = UDim2.new(0, 0, 0, 35)
list.Size     = UDim2.new(1, 0, 1, -35)

function SEL.count() local n = 0; for _ in pairs(SEL.ids) do n = n + 1 end; return n end
function SEL.update()
    if SEL.busy then return end
    local n = SEL.count()
    SEL.blockBtn.Text = "Block selected (" .. n .. ")"
    SEL.blockBtn.BackgroundColor3 = n > 0 and Color3.fromRGB(170, 32, 32) or Color3.fromRGB(90, 40, 44)
end
SEL.rerender = function() end   -- replaced below once the row builder exists
function SEL.setMode(on)
    if SEL.busy then return end
    SEL.mode, SEL.open = on, nil
    if not on then SEL.ids = {} end
    SEL.enterBtn.Visible  = not on
    SEL.selectBar.Visible = on
    SEL.update()
    SEL.rerender()
end

local function makeRow(rank, r)
    local isSelf = (r.player == Players.LocalPlayer)
    -- wrapper grows when the Trade / Profile strip is open, pushing the rows below it down
    local wrap = new("Frame", {
        Size = UDim2.new(1, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = rank,
    }, list)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, wrap)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = Color3.fromRGB(40, 40, 54),
        BackgroundTransparency = 0.15, BorderSizePixel = 0, LayoutOrder = 1,
    }, wrap)
    corner(row, 3)
    -- whole row is one big button, so you can tap anywhere on it
    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
    }, row)
    local medal = (rank == 1 and "🥇") or (rank == 2 and "🥈") or (rank == 3 and "🥉") or ("#" .. rank)
    new("TextLabel", {
        Size = UDim2.new(0, 16, 1, 0), Position = UDim2.new(0, 2, 0, 0), BackgroundTransparency = 1,
        Text = medal, Font = Enum.Font.FredokaOne, TextSize = 8, TextColor3 = Color3.fromRGB(235, 215, 150),
        TextXAlignment = Enum.TextXAlignment.Center,
    }, row)
    local baseName = r.name .. ((r.eq and r.eq > 0) and " 🐾" or "")
    local nameLbl = new("TextLabel", {
        Size = UDim2.new(1, -64, 0, r.top and 11 or 20), Position = UDim2.new(0, 18, 0, r.top and 1 or 0), BackgroundTransparency = 1,
        Text = baseName, Font = Enum.Font.FredokaOne, TextSize = 7, TextColor3 = Color3.fromRGB(235, 235, 255),
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    if r.top then   -- best pet under the name
        new("TextLabel", {
            Size = UDim2.new(1, -64, 0, 8), Position = UDim2.new(0, 18, 0, 11), BackgroundTransparency = 1,
            Text = "★ " .. r.top.name .. "  " .. fmt(r.top.value), Font = Enum.Font.SourceSansBold, TextSize = 6,
            TextColor3 = Color3.fromRGB(240, 200, 90), TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
    end
    new("TextLabel", {
        Size = UDim2.new(0, 42, 1, 0), Position = UDim2.new(1, -45, 0, 0), BackgroundTransparency = 1,
        Text = fmt(r.value), Font = Enum.Font.FredokaOne, TextSize = 7, TextColor3 = Color3.fromRGB(120, 230, 150),
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)

    local function paint()
        local on = (not isSelf) and SEL.ids[r.uid] == true
        row.BackgroundColor3 = on and Color3.fromRGB(95, 38, 44) or Color3.fromRGB(40, 40, 54)
        nameLbl.Text = (on and "✓ " or "") .. baseName
    end
    paint()

    -- Trade / Profile strip (hidden until you tap the row)
    local strip = new("Frame", {
        Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = Color3.fromRGB(34, 36, 52),
        BackgroundTransparency = 0.1, BorderSizePixel = 0, LayoutOrder = 2, Visible = false,
    }, wrap)
    corner(strip, 3)
    local function stripBtn(text, color, textColor, xScale, wScale, xOff, wOff)
        local b = new("TextButton", {
            Size = UDim2.new(wScale, wOff, 0, 12), Position = UDim2.new(xScale, xOff, 0.5, -6),
            BackgroundColor3 = color, Text = text, Font = Enum.Font.FredokaOne, TextSize = 7,
            TextColor3 = textColor, BorderSizePixel = 0,
        }, strip)
        corner(b, 3)
        return b
    end
    if not isSelf then
        local tradeBtn = stripBtn("🤝 Trade", Color3.fromRGB(30, 80, 48), Color3.fromRGB(150, 240, 170), 0, 0.5, 4, -6)
        tradeBtn.MouseButton1Click:Connect(function()
            if not (r.player and r.player.Parent) then tradeBtn.Text = "Gone"; return end
            pcall(function() RouterClient.get("TradeAPI/SendTradeRequest"):FireServer(r.player) end)
            tradeBtn.Text = "✓ Sent"
            task.delay(1.2, function() if tradeBtn.Parent then tradeBtn.Text = "🤝 Trade" end end)
        end)
    end
    local profileBtn = isSelf
        and stripBtn("👤 Profile", Color3.fromRGB(44, 50, 90), Color3.fromRGB(170, 190, 255), 0, 1, 4, -8)
        or  stripBtn("👤 Profile", Color3.fromRGB(44, 50, 90), Color3.fromRGB(170, 190, 255), 0.5, 0.5, 2, -6)
    profileBtn.MouseButton1Click:Connect(function()
        pcall(function()
            local PPA = UIManager and UIManager.apps and UIManager.apps.PlayerProfileApp
            if PPA then PPA:open_player_profile_for_user_id(r.uid) end
        end)
    end)

    hit.MouseButton1Click:Connect(function()
        if SEL.mode then                                   -- select mode: tick / untick
            if isSelf or SEL.busy then return end
            if SEL.ids[r.uid] then SEL.ids[r.uid] = nil else SEL.ids[r.uid] = true end
            paint()
            SEL.update()
        else                                               -- normal mode: open Trade / Profile
            if SEL.open and SEL.open ~= strip and SEL.open.Parent then SEL.open.Visible = false end
            strip.Visible = not strip.Visible
            SEL.open = strip.Visible and strip or nil
        end
    end)
end

local function clearRows()
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("GuiObject") then c:Destroy() end
    end
end

-- Rebuild is single-flight. A request that arrives mid-scan is remembered and re-run afterwards
-- (the old code silently dropped it, and any error mid-scan left `refreshing = true` forever,
-- permanently freezing the board).
local st = { refreshing = false, pending = false, pendingForce = false, run = 0, deb = 0, last = {} }
SEL.rerender = function()
    clearRows()
    for rank, r in ipairs(st.last) do makeRow(rank, r) end
    SEL.update()
end
SEL.enterBtn.MouseButton1Click:Connect(function() SEL.setMode(true) end)
SEL.doneBtn.MouseButton1Click:Connect(function() SEL.setMode(false) end)
SEL.allBtn.MouseButton1Click:Connect(function()
    if SEL.busy then return end
    for _, r in ipairs(st.last) do
        if r.player ~= Players.LocalPlayer and r.player and r.player.Parent then SEL.ids[r.uid] = true end
    end
    SEL.rerender()
end)
SEL.noneBtn.MouseButton1Click:Connect(function()
    if SEL.busy then return end
    SEL.ids = {}; SEL.rerender()
end)
SEL.blockBtn.MouseButton1Click:Connect(function()
    if SEL.busy then return end
    local targets = {}
    for uid in pairs(SEL.ids) do
        local p = Players:GetPlayerByUserId(uid)
        if p and p ~= Players.LocalPlayer then targets[#targets + 1] = p end
    end
    if #targets == 0 then return end
    if not _G._silentBlockMany then SEL.blockBtn.Text = "Unavailable"; return end
    SEL.busy = true
    _G._silentBlockMany(targets,
        function(i, n) SEL.blockBtn.Text = string.format("Blocking %d/%d…", i, n) end,
        function(okCount, n)
            SEL.blockBtn.Text = (okCount == n) and ("Blocked " .. n) or string.format("Blocked %d/%d", okCount, n)
            task.delay(1.5, function()
                SEL.ids, SEL.busy = {}, false
                SEL.rerender()
            end)
        end)
end)
local function rebuild(force)
    if not richFrame.Parent then return end
    if st.refreshing then
        st.pending = true
        if force == true then st.pendingForce = true end
        return
    end
    st.refreshing = true
    st.run = st.run + 1
    local myRun = st.run
    local done, gotCache = false, false

    local function finish()
        if done then return end
        done = true
        st.refreshing = false
        if st.pending and richFrame.Parent then
            local f = st.pendingForce
            st.pending, st.pendingForce = false, false
            task.defer(rebuild, f)
        end
    end

    if force == true then realPetCache = {} end
    clearRows()
    status.Visible = true
    status.Text = "Loading values…"
    if type(_G._fetchAmvgg) ~= "function" then
        status.Text = "Value loader unavailable"
        return finish()
    end

    -- safety net: if the AMVGG request never calls back, don't stay stuck forever
    task.delay(25, function()
        if myRun == st.run and not done and not gotCache then
            status.Visible = true
            status.Text = "Timed out - tap ↻"
            finish()
        end
    end)

    _G._fetchAmvgg(function(cache)
        if done then return end
        gotCache = true
        if not richFrame.Parent then return finish() end
        if not cache then status.Text = "Failed to load AMVGG values"; return finish() end
        task.spawn(function()
            local ok, err = pcall(function()
                local results, plrs = {}, Players:GetPlayers()
                local me = Players.LocalPlayer
                local okE, equipped = pcall(function()
                    return (CONFIG.RICH_COUNT_EQUIPPED ~= false) and EQ.scan() or {}
                end)
                if not okE then equipped = {} end
                for i, plr in ipairs(plrs) do
                    if done or not richFrame.Parent then return end
                    status.Text = string.format("Scanning %d / %d…", i, #plrs)
                    local value, eqValue = 0, 0
                    local okp, pets = pcall(fetchRealPets, plr)       -- one bad player can't break the board
                    if not okp then pets = {} end
                    pets = pets or {}
                    local okv, v = pcall(petListValue, pets, cache)
                    if okv and type(v) == "number" then value = v end
                    local extraItems = {}
                    if equipped[plr] then
                        local oke, extra = pcall(EQ.extra, pets, equipped[plr])
                        if oke and #extra > 0 then
                            extraItems = extra
                            local oke2, ev = pcall(petListValue, extra, cache)
                            if oke2 and type(ev) == "number" then eqValue = ev; value = value + ev end
                        end
                    end
                    local okt, top = pcall(EQ.top, pets, extraItems, cache)
                    if not okt then top = nil end
                    if plr.Parent then
                        local nm = plr.Name                           -- usernames, not display names
                        if plr == me then nm = nm .. " (you)" end
                        table.insert(results, { name = nm, value = value, eq = eqValue, top = top, player = plr, uid = plr.UserId })
                    end
                end
                table.sort(results, function(a, b)
                    if a.value ~= b.value then return a.value > b.value end
                    return a.name:lower() < b.name:lower()
                end)
                if done or not richFrame.Parent then return end
                st.last = results
                local present = {}
                for _, r in ipairs(results) do present[r.uid] = true end
                for uid in pairs(SEL.ids) do if not present[uid] then SEL.ids[uid] = nil end end   -- drop players who left
                SEL.open = nil
                clearRows()
                for rank, r in ipairs(results) do makeRow(rank, r) end
                SEL.update()
                status.Visible = (#results == 0)
                status.Text = (#results == 0) and "No players found" or ""
            end)
            if not ok then
                warn("[RichBoard] " .. tostring(err))
                status.Visible = true
                status.Text = "Error - tap ↻"
            end
            finish()
        end)
    end)
end

-- _G._richBoardRefresh()            → immediate (used when the tab is opened)
-- _G._richBoardRefresh("debounced") → used by player join/leave: coalesces bursts, skips if tab hidden
-- _G._richBoardRefresh(true)        → force: drop the cache and re-fetch everyone
_G._richBoardRefresh = function(mode)
    if mode == "debounced" then
        st.deb = st.deb + 1
        local my = st.deb
        task.delay(1.5, function()
            if my ~= st.deb or not richFrame.Parent or not richFrame.Visible then return end
            rebuild()
        end)
    else
        rebuild(mode == true)
    end
end
_G._openRichBoard = function()
    _setRichTabVisible(true)
    setActiveTab("Rich")
    rebuild()
end
refreshBtn.MouseButton1Click:Connect(function() rebuild(true) end)
rebuild()
end

setActiveTab("Control")
