-- Configuration for Faderfox UC4 MIDI controller

local obj = {}

obj.name = "Faderfox UC4"
obj.id = "ff_uc4"
obj.channels = {2}
obj.ccMap = {
    SYSTEM_MUTE = 13,
    SYSTEM_VOLUME = 31,
}

obj.logger = hs.logger.new(obj.id)
obj.logger.setLogLevel('error')

obj.savedVolume = 20

function obj:receiveSystemVolume(message)
    local newVolume = self.utils.midiToPercentage(message.ccValue)
    obj.logger.d("Set volume to " .. newVolume .. "%")
    hs.audiodevice.defaultOutputDevice():setVolume(newVolume)
end

function obj:receiveSystemMute(message)
    local audioDevice = hs.audiodevice.defaultOutputDevice()
    if message.ccValue == 0 then
        obj.savedVolume = audioDevice:volume()
        audioDevice:setVolume(0)
        hs.alert.show("Muted")
    elseif message.ccValue == 127 then
        audioDevice:setVolume(obj.savedVolume)
        hs.alert.show("Playing")
        obj.logger.d("Playing at: " .. math.floor(obj.savedVolume) .. "%")
    end
end

function obj:transmitSystemVolume(message)
    local audioDevice = hs.audiodevice.defaultOutputDevice()
    if not audioDevice then
        obj.logger.e("No audio device found")
        return
    end
    local volume = audioDevice:volume() or 0
    local txMessage = {
        channel = message.channel,
        ccNumber = message.ccNumber,
        ccValue = self.utils.percentageToMidi(volume)
    }
    self:sendControlChange(txMessage)
end

function obj:createConfig()
    return {
        name = self.name,
        id = self.id,
        channels = self.channels,
        ccHandlers = {
            [self.ccMap.SYSTEM_VOLUME] = self.receiveSystemVolume,
            [self.ccMap.SYSTEM_MUTE] = self.receiveSystemMute,
        },
        initialTx = {
            [self.ccMap.SYSTEM_VOLUME] = self.transmitSystemVolume,
        },
    }
end

return obj
