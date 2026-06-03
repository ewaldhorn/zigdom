// ------------------------------------------------------------------------------------------------
// sound.zig — Zero-heap sound effects generator
// Pre-renders UI sound effect buffers for low-latency, hardware-accelerated playback.
// The retro soundtrack synthesizer lives in docs/synth-worklet.js (AudioWorklet).
// ------------------------------------------------------------------------------------------------

pub const SAMPLE_RATE: f32 = 44100.0;

// ------------------------------------------------------------------------------------------------
// Sound Effect: UI click — descending-frequency triangle blip with exponential decay.
// Call once to pre-render into a static buffer, then play via AudioBufferSourceNode in JS.
// ~50ms buffer recommended (2205 samples at 44.1kHz).
// ------------------------------------------------------------------------------------------------
pub fn fillClick(buf: []f32) void {
    const freq_start: f32 = 2000.0; // Hz
    const freq_end: f32 = 600.0; // Hz
    const decay_rate: f32 = 20.0; // e^(-20*t) — ~37% at 50ms, ~14% at 100ms

    var phase: f32 = 0.0;
    for (0..buf.len) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / SAMPLE_RATE;
        const progress: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(buf.len));
        const freq = freq_start + (freq_end - freq_start) * progress;

        phase += freq / SAMPLE_RATE;
        if (phase >= 1.0) phase -= 1.0;

        // Triangle wave (odd harmonics give presence without harshness)
        const osc = if (phase < 0.5)
            -1.0 + 4.0 * phase
        else
            3.0 - 4.0 * phase;

        buf[i] = osc * @exp(-decay_rate * t) * 0.25;
    }
}
