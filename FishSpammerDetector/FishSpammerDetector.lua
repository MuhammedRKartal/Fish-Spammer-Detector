local addonName = "FeastSpamDetector"
local FeastSpamDetector = CreateFrame("Frame")

local SETTINGS = {
    spamWindowSeconds = 3,
    postSpamWindowSeconds = 6,
    cleanupWindowSeconds = 180,
    initialSpamThreshold = 4,
    hardSpamThreshold = 10,
    enableHarshMessage = true,
    debugMode = false,
}

local FEAST_SPELL_NAMES = {
    ["Great Feast"] = true,
    ["Fish Feast"] = true,
}

local feastSpammingPlayers = {}

FeastSpamDetector:RegisterEvent("PLAYER_ENTERING_WORLD")
FeastSpamDetector:RegisterEvent("GROUP_ROSTER_UPDATE")

local function DebugPrint(message)
    if not SETTINGS.debugMode then
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FeastSpamDetector:|r " .. tostring(message))
end

local function GetOutputChannel()
    if IsInRaid() then
        return "RAID"
    end

    if IsInGroup() then
        return "PARTY"
    end

    return nil
end

local function SendWarningMessage(message)
    if not message or message == "" then
        return
    end

    local outputChannel = GetOutputChannel()
    if not outputChannel then
        return
    end

    SendChatMessage(message, outputChannel)
end

local function CleanupOldEntries(currentTime)
    local playerName = nil
    local playerData = nil

    for playerName, playerData in pairs(feastSpammingPlayers) do
        if (currentTime - playerData.lastSeenTime) > SETTINGS.cleanupWindowSeconds then
            feastSpammingPlayers[playerName] = nil
        end
    end
end

local function CheckGroupStatus()
    if IsInRaid() or IsInGroup() then
        FeastSpamDetector:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        DebugPrint("Registered COMBAT_LOG_EVENT_UNFILTERED")
    else
        FeastSpamDetector:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        DebugPrint("Unregistered COMBAT_LOG_EVENT_UNFILTERED")
    end
end

local function GetOrCreatePlayerData(sourceName, currentTime)
    if not feastSpammingPlayers[sourceName] then
        feastSpammingPlayers[sourceName] = {
            count = 0,
            firstCastTime = currentTime,
            lastCastTime = 0,
            lastSeenTime = currentTime,
            isSpamming = false,
        }
    end

    return feastSpammingPlayers[sourceName]
end

local function BuildSpamMessage(sourceName, count)
    if count >= SETTINGS.hardSpamThreshold and SETTINGS.enableHarshMessage then
        return sourceName .. " STOP IT YOU DUMB FUCK! x" .. count
    end

    return sourceName .. " is spamming the feast! x" .. count
end

local function IsPlayerMe(sourceName)
    if not sourceName or sourceName == "" then
        return false
    end

    local playerName = UnitName("player")
    if sourceName == playerName then
        return true
    end

    local playerNameWithRealm = GetUnitName("player", true)
    if sourceName == playerNameWithRealm then
        return true
    end

    return false
end

local function HandleFeastCast(sourceName)
    if not sourceName or sourceName == "" then
        return
    end

    if IsPlayerMe(sourceName) then
        DebugPrint("Ignored own feast cast: " .. tostring(sourceName))
        return
    end

    local currentTime = GetTime()

    CleanupOldEntries(currentTime)

    local playerData = GetOrCreatePlayerData(sourceName, currentTime)
    playerData.lastSeenTime = currentTime

    if playerData.isSpamming then
        if (currentTime - playerData.lastCastTime) <= SETTINGS.postSpamWindowSeconds then
            playerData.count = playerData.count + 1
        else
            playerData.count = 1
            playerData.firstCastTime = currentTime
            playerData.isSpamming = false
        end
    else
        if (currentTime - playerData.firstCastTime) <= SETTINGS.spamWindowSeconds then
            playerData.count = playerData.count + 1
        else
            playerData.count = 1
            playerData.firstCastTime = currentTime
        end

        if playerData.count >= SETTINGS.initialSpamThreshold then
            playerData.isSpamming = true
        end
    end

    playerData.lastCastTime = currentTime

    if playerData.isSpamming then
        SendWarningMessage(BuildSpamMessage(sourceName, playerData.count))
    end

    DebugPrint(sourceName .. " count=" .. playerData.count .. " isSpamming=" .. tostring(playerData.isSpamming))
end

FeastSpamDetector:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        CheckGroupStatus()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp = nil
        local subEvent = nil
        local sourceGUID = nil
        local sourceName = nil
        local sourceFlags = nil
        local destGUID = nil
        local destName = nil
        local destFlags = nil
        local spellId = nil
        local spellName = nil
        local spellSchool = nil

        timestamp,
        subEvent,
        sourceGUID,
        sourceName,
        sourceFlags,
        destGUID,
        destName,
        destFlags,
        spellId,
        spellName,
        spellSchool = ...

        if subEvent ~= "SPELL_CAST_SUCCESS" then
            return
        end

        if not spellName or not FEAST_SPELL_NAMES[spellName] then
            return
        end

        HandleFeastCast(sourceName)
    end
end)