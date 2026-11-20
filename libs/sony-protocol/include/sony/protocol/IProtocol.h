#pragma once

#include "SemanticTypes.h"
#include "SonyError.h"
#include <string>
#include <vector>

namespace sony::protocol {

enum class ProtocolGeneration {
    V1,
    V2
};

class IProtocol {
public:
    virtual ~IProtocol() = default;

    [[nodiscard]] virtual ProtocolGeneration generation() const noexcept = 0;

    virtual void initDevice() = 0;

    virtual BatteryState getBattery() = 0;

    virtual NoiseControlState getNoiseControl() = 0;
    virtual void setNoiseControl(const NoiseControlState& state) = 0;

    virtual EqualizerState getEqualizer() = 0;
    virtual void setEqualizerPreset(int preset) = 0;
    // bands.size() is 5 for legacy devices, 10 for tenBandEqualizer devices
    // (clearBass is ignored by implementations in the latter case).
    virtual void setEqualizerCustom(int clearBass, const std::vector<int>& bands) = 0;

    virtual bool getDsee() = 0;
    virtual void setDsee(bool enabled) = 0;

    virtual std::string getFirmwareVersion() = 0;
    virtual std::string getCodec() = 0;

    virtual int getAutoPowerOff() = 0;
    virtual void setAutoPowerOff(int index) = 0;

    virtual bool getSpeakToChat() = 0;
    virtual void setSpeakToChat(bool enabled) = 0;

    // Speak-to-Chat auto-close timeout: 0 ~15 s, 1 Standard ~30 s, 2 ~1 min,
    // 3 do not close. The headset cannot report it back, so the value is
    // remembered for later enables and only written now when `apply` is set
    // (the feature is on). Only generations with a verified layout override.
    virtual void setSpeakToChatTimeout(int /*timeout*/, bool /*apply*/) {
        throw SonyException(SonyErrorCode::Unsupported, "Speak-to-Chat timeout is not supported");
    }

    // Turns the headset off. The link drops right after, so callers must not
    // expect a reply. Unsupported unless a generation overrides it.
    virtual void powerOff() {
        throw SonyException(SonyErrorCode::Unsupported, "Remote power off is not supported");
    }

    virtual bool getAdaptiveVolume() = 0;
    virtual void setAdaptiveVolume(bool enabled) = 0;
};

} // namespace sony::protocol
