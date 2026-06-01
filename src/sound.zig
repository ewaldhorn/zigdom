// ------------------------------------------------------------------------------------------------
// sound.zig — Zero-heap 1980s Retro Analog Synthesizer & Sequencer
// Generates synthwave audio samples dynamically.
// ------------------------------------------------------------------------------------------------

const std = @import("std");

// ------------------------------------------------------------------------------------------------
// Audio Constants
// ------------------------------------------------------------------------------------------------
pub const SAMPLE_RATE: f32 = 44100.0;
pub const BPM: f32 = 125.0;

// ------------------------------------------------------------------------------------------------
// Music Theory & Sequencer Data
// ------------------------------------------------------------------------------------------------

// A minor Chord Progression: Am -> F -> C -> G (64 steps total, 16 steps per bar)
// Midi note pitches:
const chord_bass_low = [_]f32{ 33.0, 29.0, 36.0, 31.0 };  // A1, F1, C2, G1
const chord_bass_high = [_]f32{ 45.0, 41.0, 48.0, 43.0 }; // A2, F2, C3, G2

const chord_arps = [_][4]f32{
    [_]f32{ 57.0, 60.0, 64.0, 69.0 }, // Am (A3, C4, E4, A4)
    [_]f32{ 53.0, 57.0, 60.0, 65.0 }, // F  (F3, A3, C4, F4)
    [_]f32{ 60.0, 64.0, 67.0, 72.0 }, // C  (C4, E4, G4, C5)
    [_]f32{ 55.0, 59.0, 62.0, 67.0 }, // G  (G3, B3, D4, G4)
};

// Dotted eighth/sixteenth arpeggiator repeating pattern
const arp_pattern = [_]usize{ 0, 1, 2, 3, 2, 1, 0, 2 };

// ------------------------------------------------------------------------------------------------
// Helper: Convert MIDI note number to frequency in Hz
// ------------------------------------------------------------------------------------------------
inline fn midiToFreq(midi: f32) f32 {
    return 440.0 * std.math.pow(f32, 2.0, (midi - 69.0) / 12.0);
}

// ------------------------------------------------------------------------------------------------
// Helper: Soft Clipper (Warm compression / saturation)
// ------------------------------------------------------------------------------------------------
inline fn softClip(x: f32) f32 {
    return x / (1.0 + @abs(x));
}

// ------------------------------------------------------------------------------------------------
// Envelope Stage Enum
// ------------------------------------------------------------------------------------------------
const EnvelopeStage = enum {
    attack,
    decay,
    sustain,
    release,
    idle,
};

// ------------------------------------------------------------------------------------------------
// Synthesizer State
// ------------------------------------------------------------------------------------------------
pub const Synth = struct {
    // Sequencer counters
    current_sample: u32 = 0,
    current_step: u32 = 0,

    // Voice 1: Bass (Detuned Dual-Sawtooth)
    bass_phase1: f32 = 0.0,
    bass_phase2: f32 = 0.0,
    bass_freq1: f32 = 0.0,
    bass_freq2: f32 = 0.0,
    bass_env_amp: f32 = 0.0,
    bass_env_stage: EnvelopeStage = .idle,

    // Voice 2: Arp Lead (Triangle)
    arp_phase: f32 = 0.0,
    arp_freq: f32 = 0.0,
    arp_env_amp: f32 = 0.0,
    arp_env_stage: EnvelopeStage = .idle,

    // Dotted-eighth echo delay line (approx 360ms delay at 44.1kHz = 15876 samples)
    // Zero heap allocation: static array size in data segment.
    delay_buffer: [16000]f32 = [_]f32{0.0} ** 16000,
    delay_write_ptr: usize = 0,

    // --------------------------------------------------------------------------------------------
    // Triggers
    // --------------------------------------------------------------------------------------------
    pub fn triggerBass(self: *Synth, midi_note: f32) void {
        const base_f = midiToFreq(midi_note);
        self.bass_freq1 = base_f;
        // Detune the second oscillator slightly to create a rich chorus effect
        self.bass_freq2 = base_f * 1.006;
        self.bass_env_stage = .attack;
    }

    pub fn triggerArp(self: *Synth, midi_note: f32) void {
        self.arp_freq = midiToFreq(midi_note);
        self.arp_env_stage = .attack;
    }

    // --------------------------------------------------------------------------------------------
    // Step Sequencer Logic
    // --------------------------------------------------------------------------------------------
    fn handleSequencerStep(self: *Synth) void {
        const step_in_chord = self.current_step % 16;
        const chord_idx = self.current_step / 16;

        // 1. Trigger the Arpeggiator Lead on every step (sixteenth notes)
        const arp_note_idx = arp_pattern[step_in_chord % arp_pattern.len];
        const arp_note = chord_arps[chord_idx][arp_note_idx];
        self.triggerArp(arp_note);

        // 2. Trigger the driving octave Bass on even steps (eighth notes)
        if (self.current_step % 2 == 0) {
            const is_offbeat = (self.current_step % 4) == 2;
            const bass_note = if (is_offbeat) chord_bass_high[chord_idx] else chord_bass_low[chord_idx];
            self.triggerBass(bass_note);
        }
    }

    // --------------------------------------------------------------------------------------------
    // Synthesize a Single Mono Audio Sample
    // --------------------------------------------------------------------------------------------
    pub fn nextSample(self: *Synth) f32 {
        // Step duration at 125 BPM: (44100 * 60) / (125 * 4) = 5292 samples per 16th note step
        const samples_per_step: u32 = 5292;

        // Check sequencer step boundaries
        if (self.current_sample >= samples_per_step) {
            self.current_sample = 0;
            self.current_step = (self.current_step + 1) % 64;
            self.handleSequencerStep();
        }

        // Gate Off (note release) transitions:
        // Arpeggiator release starts at 75% of sixteenth note step
        if (self.current_sample == 3969) {
            if (self.arp_env_stage != .idle) self.arp_env_stage = .release;
        }
        // Bass release starts at 75% of eighth note step (which is step 1, 50% sample count)
        if (self.current_step % 2 == 1 and self.current_sample == 2646) {
            if (self.bass_env_stage != .idle) self.bass_env_stage = .release;
        }

        self.current_sample += 1;

        // ----------------------------------------------------------------------------------------
        // Render Bass Voice (Detuned Dual-Sawtooth)
        // ----------------------------------------------------------------------------------------
        var bass_out: f32 = 0.0;
        if (self.bass_env_stage != .idle) {
            // Oscillator 1
            self.bass_phase1 += self.bass_freq1 / SAMPLE_RATE;
            if (self.bass_phase1 >= 1.0) self.bass_phase1 -= 1.0;
            const osc1 = -1.0 + 2.0 * self.bass_phase1;

            // Oscillator 2 (slightly detuned)
            self.bass_phase2 += self.bass_freq2 / SAMPLE_RATE;
            if (self.bass_phase2 >= 1.0) self.bass_phase2 -= 1.0;
            const osc2 = -1.0 + 2.0 * self.bass_phase2;

            // Envelope calculations
            const attack_rate = 1.0 / (0.005 * SAMPLE_RATE); // 5ms attack
            const decay_rate = (1.0 - 0.45) / (0.10 * SAMPLE_RATE); // 100ms decay to 45% sustain
            const release_rate = 0.45 / (0.12 * SAMPLE_RATE); // 120ms release

            switch (self.bass_env_stage) {
                .attack => {
                    self.bass_env_amp += attack_rate;
                    if (self.bass_env_amp >= 1.0) {
                        self.bass_env_amp = 1.0;
                        self.bass_env_stage = .decay;
                    }
                },
                .decay => {
                    self.bass_env_amp -= decay_rate;
                    if (self.bass_env_amp <= 0.45) {
                        self.bass_env_amp = 0.45;
                        self.bass_env_stage = .sustain;
                    }
                },
                .sustain => {},
                .release => {
                    self.bass_env_amp -= release_rate;
                    if (self.bass_env_amp <= 0.0) {
                        self.bass_env_amp = 0.0;
                        self.bass_env_stage = .idle;
                    }
                },
                .idle => {},
            }

            bass_out = 0.5 * (osc1 + osc2) * self.bass_env_amp;
        }

        // ----------------------------------------------------------------------------------------
        // Render Arpeggiator Lead Voice (Triangle)
        // ----------------------------------------------------------------------------------------
        var arp_out: f32 = 0.0;
        if (self.arp_env_stage != .idle) {
            self.arp_phase += self.arp_freq / SAMPLE_RATE;
            if (self.arp_phase >= 1.0) self.arp_phase -= 1.0;

            // Triangle Wave
            const osc = if (self.arp_phase < 0.5)
                -1.0 + 4.0 * self.arp_phase
            else
                3.0 - 4.0 * self.arp_phase;

            // Envelope calculations
            const attack_rate = 1.0 / (0.015 * SAMPLE_RATE); // 15ms attack
            const decay_rate = (1.0 - 0.35) / (0.15 * SAMPLE_RATE); // 150ms decay to 35% sustain
            const release_rate = 0.35 / (0.22 * SAMPLE_RATE); // 220ms release

            switch (self.arp_env_stage) {
                .attack => {
                    self.arp_env_amp += attack_rate;
                    if (self.arp_env_amp >= 1.0) {
                        self.arp_env_amp = 1.0;
                        self.arp_env_stage = .decay;
                    }
                },
                .decay => {
                    self.arp_env_amp -= decay_rate;
                    if (self.arp_env_amp <= 0.35) {
                        self.arp_env_amp = 0.35;
                        self.arp_env_stage = .sustain;
                    }
                },
                .sustain => {},
                .release => {
                    self.arp_env_amp -= release_rate;
                    if (self.arp_env_amp <= 0.0) {
                        self.arp_env_amp = 0.0;
                        self.arp_env_stage = .idle;
                    }
                },
                .idle => {},
            }

            arp_out = osc * self.arp_env_amp;
        }

        // ----------------------------------------------------------------------------------------
        // Mix & Echo Delay Effect
        // ----------------------------------------------------------------------------------------
        const mixed = (bass_out * 0.35) + (arp_out * 0.22);

        // Fetch spatial echo from delay line (3 sixteenth notes = 15876 samples)
        const delay_samples = 15876;
        const read_ptr = (self.delay_write_ptr + (16000 - delay_samples)) % 16000;
        const echo = self.delay_buffer[read_ptr];

        // Write feedback to circular buffer
        self.delay_buffer[self.delay_write_ptr] = mixed + (echo * 0.45);
        self.delay_write_ptr = (self.delay_write_ptr + 1) % 16000;

        // Combine Dry and Wet (echo) signals
        const final_out = mixed * 0.75 + echo * 0.32;

        return softClip(final_out);
    }
};
