#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace sony::protocol {

enum class SonyProtocolVersion : signed char
{
    V1 = 0,
    V2 = 1
};

enum class SonyModel
{
    Unknown,

    WH1000XM3,
    WH1000XM4,
    WH1000XM5,
    WH1000XM6,

    WF1000XM4,
    WF1000XM5,
    WF1000XM6,

    WHCH720N,
    ULTWear,
    LinkBudsS
};

enum class NoiseControlLayout : uint8_t { Standard = 0x17, Wf1000Xm4 = 0x15, Wh1000Xm6 = 0x19 };

struct DeviceCapabilities
{
    bool battery = false;
    bool dualBattery = false;

    bool noiseCancelling = false;
    bool ambientSound = false;
    bool focusOnVoice = false;

    bool equalizer = false;
    bool clearBass = false;
    // True on devices that speak the newer 10-band equalizer layout (inquired
    // type 0x04, no separate Clear Bass slot) instead of the legacy 5-band +
    // Clear Bass layout (inquired type 0x00/0x01). Verified on the WH-1000XM6
    // via a Sound Connect btsnoop capture -- see issue #10.
    bool tenBandEqualizer = false;
    // Model-specific GET layouts; XM6 retains the standard 0x17 SET path.
    NoiseControlLayout noiseControlLayout = NoiseControlLayout::Standard;

    bool dsee = false;

    bool speakToChat = false;
    bool adaptiveVolume = false;

    bool autoPowerOff = false;

    bool firmwareInfo = false;
    bool codecInfo = false;

    bool wearSensor = false;

    bool multipoint = false;

    // Speak-to-Chat auto-close timeout is writable. Only the V1 Smart
    // Talking Mode config layout (FC 05 00 <sens> <focus> <timeout>) is
    // documented; V2 keeps its device default until a capture confirms it.
    bool speakToChatTimeout = false;

    // Remote power off, sent in the frame of the model's own generation:
    // V2 (XM5, XM6) POWER_SET `24 03 01`, from Gadgetbridge's
    // SonyProtocolImplV2.powerOff; V1 (XM4) opcode 0x22, `22 00`. Enabled
    // per model only once that model is named here, and only ever sent
    // from the Turn Off action, never on connect.
    bool powerOff = false;

    // Auto power off is only Off / "when taken off" (indices 0 and 5 of the
    // APO table); the timed codes are not offered. Set for the WH-1000XM5:
    // on firmware 2.5.1 every timed code (5 min, 30 min, 1 h, 3 h) was
    // stored as "when taken off" (10 00), confirmed on hardware through the
    // readback in SonyDevice::setAutoPowerOff.
    bool autoPowerOffTakenOffOnly = false;
};

struct DeviceProfile
{
    SonyModel model{SonyModel::Unknown};
    SonyProtocolVersion protocol{SonyProtocolVersion::V1};
    DeviceCapabilities capabilities{};
};

[[nodiscard]] constexpr std::string_view to_string(SonyModel model) noexcept {
    switch (model) {
        case SonyModel::WH1000XM3: return "WH-1000XM3";
        case SonyModel::WH1000XM4: return "WH-1000XM4";
        case SonyModel::WH1000XM5: return "WH-1000XM5";
        case SonyModel::WH1000XM6: return "WH-1000XM6";
        case SonyModel::WF1000XM4: return "WF-1000XM4";
        case SonyModel::WF1000XM5: return "WF-1000XM5";
        case SonyModel::WF1000XM6: return "WF-1000XM6";
        case SonyModel::WHCH720N:  return "WH-CH720N";
        case SonyModel::ULTWear:    return "ULT WEAR";
        case SonyModel::LinkBudsS:  return "LinkBuds S";
        case SonyModel::Unknown:   return "Unknown";
    }
    return "Unknown";
}

[[nodiscard]] constexpr std::string_view to_string(SonyProtocolVersion version) noexcept {
    switch (version) {
        case SonyProtocolVersion::V1: return "V1";
        case SonyProtocolVersion::V2: return "V2";
    }
    return "Unknown";
}

} // namespace sony::protocol
