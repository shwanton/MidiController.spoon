-- Config for Melbourne Instruments Roto-Control MIDI controller

local rekordbox = require("rekordbox")

local obj = {}

obj.name = "Roto-Control"
obj.id = "rotocontrol"
obj.channels = {1}
obj.ccMap = {
    SYSTEM_MUTE = 1,
    REKORDBOX_PLAY = 2,
    REKORDBOX_PREV = 3,
    REKORDBOX_NEXT = 4,
    REKORDBOX_LAUNCH = 5,
    SYSTEM_VOLUME = 9,
    REKORDBOX_VOLUME = 10,
    REKORDBOX_JUMP_BACK = 11,
    REKORDBOX_JUMP_FORWARD = 12,
}

obj.logger = hs.logger.new('rotocontrol')
obj.logger.setLogLevel('error')

obj.savedVolume = 20

function obj:init()
    obj = {}
end

function obj:receiveSystemVolume(message)
    local newVolume = self.utils.midiToPercentage(message.ccValue)
    hs.audiodevice.defaultOutputDevice():setVolume(newVolume)
end

function obj:receiveSystemMute(message)
    local audioDevice = hs.audiodevice.defaultOutputDevice()
    if message.ccValue == 0 then
        obj.savedVolume = audioDevice:volume() or obj.savedVolume
        audioDevice:setVolume(0)
        hs.alert.show("Muted")
    elseif message.ccValue == 127 then
        audioDevice:setVolume(obj.savedVolume)
        hs.alert.show("Playing audio")
        self.logger.d("Playing: " .. math.floor(obj.savedVolume) .. "%")
    end
end

function obj:receiveRekordboxPlay(message)
    if message.ccValue == 127 then
        rekordbox.togglePlay()
    end
end

function obj:receiveRekordboxPrev(message)
    if message.ccValue == 127 then
        rekordbox.prevTrack()
    end
end

function obj:receiveRekordboxNext(message)
    if message.ccValue == 127 then
        rekordbox.nextTrack()
    end
end

function obj:receiveRekordboxJumpForward(message)
    if message.ccValue > 0 then
        self.debouncedSend = self.utils.debounce(rekordbox.jumpForward)
        self.debouncedSend()
    end
    local resetMessage = {
        channel = message.channel,
        ccNumber = obj.ccMap.REKORDBOX_JUMP_FORWARD,
        ccValue = 0
    }
    obj.logger.d("Resetting jump forward value", resetMessage)
    self.debouncedReset = self.utils.debounce(function() self:sendControlChange(resetMessage) end)
    self.debouncedReset(2.0)
end

function obj:receiveRekordboxJumpBack(message)
    if message.ccValue < 127 then
        self.debouncedSend = self.utils.debounce(rekordbox.jumpBackward)
        self.debouncedSend()
    end
    local resetMessage = {
        channel = message.channel,
        ccNumber = obj.ccMap.REKORDBOX_JUMP_BACK,
        ccValue = 127
    }
    self.debouncedReset = self.utils.debounce(function() self:sendControlChange(resetMessage) end)
    self.debouncedReset(2.0)
end

function obj:receiveRekordboxVolume(message)
    if not self._volumeHandler then
        self._volumeHandler = self.utils.debounce(function(ccValue)
            rekordbox.setVolume(self.utils.midiToPercentage(ccValue))
            local actualVolume = rekordbox.getMasterVolume()
            if actualVolume then
                local sendMessage = {
                    channel = message.channel,
                    ccNumber = obj.ccMap.REKORDBOX_VOLUME,
                    ccValue = self.utils.percentageToMidi(actualVolume)
                }
                self:sendControlChange(sendMessage)
            end
        end, 0.1)
    end
    self._volumeHandler(message.ccValue)
end

function obj:receiveRekordboxLaunch(message)
    if message.ccValue == 127 then
        rekordbox.launchRekordbox()
    elseif message.ccValue == 0 then
        rekordbox.hideRekordbox()
    end
end

function obj:transmitSystemVolume(message)
    local audioDevice = hs.audiodevice.defaultOutputDevice()
    if not audioDevice then
        hs.alert.show("No audio device found")
        return
    end
    local volume = audioDevice:volume() or 0
    local txMessage = {
        channel = message.channel,
        ccNumber = message.ccNumber,
        ccValue = self.utils.percentageToMidi(volume)
    }
    self:sendControlChange(txMessage)
    obj.logger.d("Sent initial volume to " .. volume .. "%")
end

function obj:transmitJumpForwardValue(message)
    if not rekordbox.getWindow() then return end
    local txMessage = {
        channel = message.channel,
        ccNumber = message.ccNumber,
        ccValue = 0
    }
    self:sendControlChange(txMessage)
    obj.logger.d("Reset initial jump forward value")
end

function obj:transmitJumpBackValue(message)
    if not rekordbox.getWindow() then return end
    local txMessage = {
        channel = message.channel,
        ccNumber = message.ccNumber,
        ccValue = 127
    }
    self:sendControlChange(txMessage)
    obj.logger.d("Sent initial jump back value")
end

function obj:transmitRekordboxVolume(message)
    if not rekordbox.getWindow() then return end
    local currentVolume = rekordbox.getMasterVolume()
    obj.logger.d("Current Rekordbox volume: " .. currentVolume .. "%")
    local txMessage = {
        channel = message.channel,
        ccNumber = message.ccNumber,
        ccValue = self.utils.percentageToMidi(currentVolume)
    }
    self:sendControlChange(txMessage)
    obj.logger.d("Sent initial volume to " .. currentVolume .. "%")
end

function obj:transmitRekordboxLaunch(message)
    local txMessage = {
        channel = message.channel,
        ccNumber = message.ccNumber,
        ccValue = rekordbox.isRekordboxFocused() and 127 or 0
    }
    self:sendControlChange(txMessage)
    obj.logger.d("Sent initial launch value", hs.inspect(txMessage))
end

function obj:createConfig()
    return {
        name = obj.name,
        id = obj.id,
        channels = obj.channels,
        ccHandlers = {
            [obj.ccMap.SYSTEM_VOLUME] = obj.receiveSystemVolume,
            [obj.ccMap.SYSTEM_MUTE] = obj.receiveSystemMute,
            [obj.ccMap.REKORDBOX_LAUNCH] = obj.receiveRekordboxLaunch,
            [obj.ccMap.REKORDBOX_VOLUME] = obj.receiveRekordboxVolume,
            [obj.ccMap.REKORDBOX_PLAY] = obj.receiveRekordboxPlay,
            [obj.ccMap.REKORDBOX_PREV] = obj.receiveRekordboxPrev,
            [obj.ccMap.REKORDBOX_NEXT] = obj.receiveRekordboxNext,
            [obj.ccMap.REKORDBOX_JUMP_FORWARD] = obj.receiveRekordboxJumpForward,
            [obj.ccMap.REKORDBOX_JUMP_BACK] = obj.receiveRekordboxJumpBack,
        },
        initialTx = {
            [obj.ccMap.SYSTEM_VOLUME] = obj.transmitSystemVolume,
            [obj.ccMap.REKORDBOX_LAUNCH] = obj.transmitRekordboxLaunch,
            [obj.ccMap.REKORDBOX_VOLUME] = obj.transmitRekordboxVolume,
            [obj.ccMap.REKORDBOX_JUMP_FORWARD] = obj.transmitJumpForwardValue,
            [obj.ccMap.REKORDBOX_JUMP_BACK] = obj.transmitJumpBackValue,
        }
    }
end

return obj
