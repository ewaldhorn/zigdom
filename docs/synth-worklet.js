// ------------------------------------------------------------------------------------------------
// synth-worklet.js — AudioWorkletProcessor: 1980s Retrowave Synthesizer
// Ported from src/sound.zig (Zig WASM synth) to run on the dedicated audio thread.
// ------------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------------
// Music Theory & Sequencer Data
// ------------------------------------------------------------------------------------------------

// A minor Chord Progression: Am -> F -> C -> G (64 steps total, 16 steps per bar)
// MIDI note pitches:
const CHORD_BASS_LOW = [33.0, 29.0, 36.0, 31.0];   // A1, F1, C2, G1
const CHORD_BASS_HIGH = [45.0, 41.0, 48.0, 43.0];  // A2, F2, C3, G2

const CHORD_ARPS = [
  [57.0, 60.0, 64.0, 69.0], // Am (A3, C4, E4, A4)
  [53.0, 57.0, 60.0, 65.0], // F  (F3, A3, C4, F4)
  [60.0, 64.0, 67.0, 72.0], // C  (C4, E4, G4, C5)
  [55.0, 59.0, 62.0, 67.0], // G  (G3, B3, D4, G4)
];

// Dotted eighth/sixteenth arpeggiator repeating pattern
const ARP_PATTERN = [0, 1, 2, 3, 2, 1, 0, 2];

// Step duration at 125 BPM: (44100 * 60) / (125 * 4) = 5292 samples per 16th note step
const SAMPLES_PER_STEP = 5292;
const SAMPLE_RATE = 44100;

// ------------------------------------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------------------------------------

function midiToFreq(midi) {
  return 440.0 * Math.pow(2.0, (midi - 69.0) / 12.0);
}

function softClip(x) {
  return x / (1.0 + Math.abs(x));
}

// ------------------------------------------------------------------------------------------------
// Envelope Stage
// ------------------------------------------------------------------------------------------------
const EnvStage = Object.freeze({ ATTACK: 0, DECAY: 1, SUSTAIN: 2, RELEASE: 3, IDLE: 4 });

// ------------------------------------------------------------------------------------------------
// Synthesizer State
// ------------------------------------------------------------------------------------------------

class SynthEngine {
  constructor() {
    // Sequencer counters
    this.currentSample = 0;
    this.currentStep = 0;

    // Voice 1: Bass (Detuned Dual-Sawtooth)
    this.bassPhase1 = 0.0;
    this.bassPhase2 = 0.0;
    this.bassFreq1 = 0.0;
    this.bassFreq2 = 0.0;
    this.bassEnvAmp = 0.0;
    this.bassEnvStage = EnvStage.IDLE;

    // Voice 2: Arp Lead (Triangle)
    this.arpPhase = 0.0;
    this.arpFreq = 0.0;
    this.arpEnvAmp = 0.0;
    this.arpEnvStage = EnvStage.IDLE;

    // Dotted-eighth echo delay line (approx 360ms delay at 44.1kHz = 15876 samples)
    this.delayBuffer = new Float32Array(16000);
    this.delayWritePtr = 0;

    // Playing state
    this.playing = false;
  }

  triggerBass(midiNote) {
    const baseF = midiToFreq(midiNote);
    this.bassFreq1 = baseF;
    this.bassFreq2 = baseF * 1.006; // detune for chorus effect
    this.bassEnvStage = EnvStage.ATTACK;
  }

  triggerArp(midiNote) {
    this.arpFreq = midiToFreq(midiNote);
    this.arpEnvStage = EnvStage.ATTACK;
  }

  handleSequencerStep() {
    const stepInChord = this.currentStep % 16;
    const chordIdx = Math.floor(this.currentStep / 16);

    // 1. Trigger the Arpeggiator Lead on every step (sixteenth notes)
    const arpNoteIdx = ARP_PATTERN[stepInChord % ARP_PATTERN.length];
    const arpNote = CHORD_ARPS[chordIdx][arpNoteIdx];
    this.triggerArp(arpNote);

    // 2. Trigger the driving octave Bass on even steps (eighth notes)
    if (this.currentStep % 2 === 0) {
      const isOffbeat = (this.currentStep % 4) === 2;
      const bassNote = isOffbeat ? CHORD_BASS_HIGH[chordIdx] : CHORD_BASS_LOW[chordIdx];
      this.triggerBass(bassNote);
    }
  }

  nextSample() {
    // Check sequencer step boundaries
    if (this.currentSample >= SAMPLES_PER_STEP) {
      this.currentSample = 0;
      this.currentStep = (this.currentStep + 1) % 64;
      this.handleSequencerStep();
    }

    // Gate Off (note release) transitions:
    // Arpeggiator release starts at 75% of sixteenth note step
    if (this.currentSample === 3969) {
      if (this.arpEnvStage !== EnvStage.IDLE) this.arpEnvStage = EnvStage.RELEASE;
    }
    // Bass release starts at 50% of eighth note step (which is step 1, half-sample count)
    if (this.currentStep % 2 === 1 && this.currentSample === 2646) {
      if (this.bassEnvStage !== EnvStage.IDLE) this.bassEnvStage = EnvStage.RELEASE;
    }

    this.currentSample += 1;

    // ----------------------------------------------------------------------------------------
    // Render Bass Voice (Detuned Dual-Sawtooth)
    // ----------------------------------------------------------------------------------------
    let bassOut = 0.0;
    if (this.bassEnvStage !== EnvStage.IDLE) {
      // Oscillator 1
      this.bassPhase1 += this.bassFreq1 / SAMPLE_RATE;
      if (this.bassPhase1 >= 1.0) this.bassPhase1 -= 1.0;
      const osc1 = -1.0 + 2.0 * this.bassPhase1;

      // Oscillator 2 (slightly detuned)
      this.bassPhase2 += this.bassFreq2 / SAMPLE_RATE;
      if (this.bassPhase2 >= 1.0) this.bassPhase2 -= 1.0;
      const osc2 = -1.0 + 2.0 * this.bassPhase2;

      // Envelope calculations
      const attackRate = 1.0 / (0.005 * SAMPLE_RATE);    // 5ms attack
      const decayRate = (1.0 - 0.45) / (0.10 * SAMPLE_RATE);  // 100ms decay to 45% sustain
      const releaseRate = 0.45 / (0.12 * SAMPLE_RATE);   // 120ms release

      switch (this.bassEnvStage) {
        case EnvStage.ATTACK:
          this.bassEnvAmp += attackRate;
          if (this.bassEnvAmp >= 1.0) {
            this.bassEnvAmp = 1.0;
            this.bassEnvStage = EnvStage.DECAY;
          }
          break;
        case EnvStage.DECAY:
          this.bassEnvAmp -= decayRate;
          if (this.bassEnvAmp <= 0.45) {
            this.bassEnvAmp = 0.45;
            this.bassEnvStage = EnvStage.SUSTAIN;
          }
          break;
        case EnvStage.SUSTAIN:
          break;
        case EnvStage.RELEASE:
          this.bassEnvAmp -= releaseRate;
          if (this.bassEnvAmp <= 0.0) {
            this.bassEnvAmp = 0.0;
            this.bassEnvStage = EnvStage.IDLE;
          }
          break;
        default:
          break;
      }

      bassOut = 0.5 * (osc1 + osc2) * this.bassEnvAmp;
    }

    // ----------------------------------------------------------------------------------------
    // Render Arpeggiator Lead Voice (Triangle)
    // ----------------------------------------------------------------------------------------
    let arpOut = 0.0;
    if (this.arpEnvStage !== EnvStage.IDLE) {
      this.arpPhase += this.arpFreq / SAMPLE_RATE;
      if (this.arpPhase >= 1.0) this.arpPhase -= 1.0;

      // Triangle Wave
      const osc = this.arpPhase < 0.5
        ? -1.0 + 4.0 * this.arpPhase
        : 3.0 - 4.0 * this.arpPhase;

      // Envelope calculations
      const attackRate = 1.0 / (0.015 * SAMPLE_RATE);   // 15ms attack
      const decayRate = (1.0 - 0.35) / (0.15 * SAMPLE_RATE);  // 150ms decay to 35% sustain
      const releaseRate = 0.35 / (0.22 * SAMPLE_RATE);  // 220ms release

      switch (this.arpEnvStage) {
        case EnvStage.ATTACK:
          this.arpEnvAmp += attackRate;
          if (this.arpEnvAmp >= 1.0) {
            this.arpEnvAmp = 1.0;
            this.arpEnvStage = EnvStage.DECAY;
          }
          break;
        case EnvStage.DECAY:
          this.arpEnvAmp -= decayRate;
          if (this.arpEnvAmp <= 0.35) {
            this.arpEnvAmp = 0.35;
            this.arpEnvStage = EnvStage.SUSTAIN;
          }
          break;
        case EnvStage.SUSTAIN:
          break;
        case EnvStage.RELEASE:
          this.arpEnvAmp -= releaseRate;
          if (this.arpEnvAmp <= 0.0) {
            this.arpEnvAmp = 0.0;
            this.arpEnvStage = EnvStage.IDLE;
          }
          break;
        default:
          break;
      }

      arpOut = osc * this.arpEnvAmp;
    }

    // ----------------------------------------------------------------------------------------
    // Mix & Echo Delay Effect
    // ----------------------------------------------------------------------------------------
    const mixed = (bassOut * 0.35) + (arpOut * 0.22);

    // Fetch spatial echo from delay line (3 sixteenth notes = 15876 samples)
    const delaySamples = 15876;
    const readPtr = (this.delayWritePtr + (16000 - delaySamples)) % 16000;
    const echo = this.delayBuffer[readPtr];

    // Write feedback to circular buffer
    this.delayBuffer[this.delayWritePtr] = mixed + (echo * 0.45);
    this.delayWritePtr = (this.delayWritePtr + 1) % 16000;

    // Combine Dry and Wet (echo) signals
    const finalOut = mixed * 0.75 + echo * 0.32;

    return softClip(finalOut);
  }
}

// ------------------------------------------------------------------------------------------------
// AudioWorkletProcessor
// ------------------------------------------------------------------------------------------------

class SynthWorkletProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.synth = new SynthEngine();

    // Listen for control messages from the main thread
    this.port.onmessage = (event) => {
      const msg = event.data;
      switch (msg.type) {
        case 'play':
          this.synth.playing = msg.value;
          // Reset sequencer on play start for clean loop entry
          if (msg.value) {
            this.synth.currentSample = 0;
            this.synth.currentStep = 0;
          }
          break;
      }
    };
  }

  process(inputs, outputs, parameters) {
    const output = outputs[0];
    if (!output || output.length === 0) return true;

    const channelData = output[0];
    const numSamples = channelData.length;

    if (!this.synth.playing) {
      channelData.fill(0);
      return true;
    }

    for (let i = 0; i < numSamples; i++) {
      channelData[i] = this.synth.nextSample();
    }

    return true; // Keep the processor alive
  }
}

registerProcessor('synth-worklet', SynthWorkletProcessor);
