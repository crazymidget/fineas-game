/*
    Procedural techno music generator.
    Synthesizes a looping techno beat as a WAV file at runtime.
*/

import Foundation

class TechnoMusicGenerator {
    
    private static let sampleRate: Float = 44100
    private static let bpm: Float = 128
    private static let bars = 4
    
    /// Generates a techno loop WAV file and returns its URL.
    static func generate() -> URL {
        let beatDuration = 60.0 / bpm
        let totalBeats = bars * 4
        let totalDuration = Float(totalBeats) * beatDuration
        let sampleCount = Int(totalDuration * sampleRate)
        
        var buffer = [Float](repeating: 0, count: sampleCount)
        
        // 1. Kick drum — 4 on the floor
        for beat in 0..<totalBeats {
            let offset = Int(Float(beat) * beatDuration * sampleRate)
            synthKick(into: &buffer, at: offset)
        }
        
        // 2. Hi-hat — every 16th note, accented on off-8ths
        let sixteenthDuration = beatDuration / 4
        for step in 0..<(totalBeats * 4) {
            let offset = Int(Float(step) * sixteenthDuration * sampleRate)
            let isOffEighth = step % 2 == 1 && step % 4 == 2
            let isDownbeat = step % 4 == 0
            let volume: Float = isOffEighth ? 0.18 : (isDownbeat ? 0.06 : 0.10)
            synthHiHat(into: &buffer, at: offset, volume: volume)
        }
        
        // 3. Clap on beats 2 and 4
        for bar in 0..<bars {
            for clapBeat in [1, 3] {
                let beat = bar * 4 + clapBeat
                let offset = Int(Float(beat) * beatDuration * sampleRate)
                synthClap(into: &buffer, at: offset)
            }
        }
        
        // 4. Sub bass
        synthBass(into: &buffer, beatDuration: beatDuration)
        
        // 5. Acid synth line
        synthAcid(into: &buffer, beatDuration: beatDuration)
        
        // Normalize and soft-clip
        let peak = buffer.map { abs($0) }.max() ?? 1.0
        let gain: Float = peak > 0 ? 0.85 / peak : 1.0
        for i in 0..<buffer.count {
            buffer[i] = softClip(buffer[i] * gain)
        }
        
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("techno.wav")
        writeWAV(buffer, to: url)
        return url
    }
    
    // MARK: - Synthesis
    
    /// Kick drum: pitch-swept sine with amplitude decay
    private static func synthKick(into buffer: inout [Float], at offset: Int) {
        let duration: Float = 0.28
        let samples = Int(duration * sampleRate)
        var phase: Float = 0
        
        for i in 0..<samples {
            guard offset + i < buffer.count else { break }
            let t = Float(i) / sampleRate
            let n = t / duration
            
            // Pitch sweep: 160Hz -> 42Hz
            let freq = 42 + 118 * exp(-n * 10)
            phase += freq / sampleRate
            
            let amp = exp(-n * 5.5) * 0.9
            buffer[offset + i] += sin(phase * 2 * .pi) * amp
        }
    }
    
    /// Hi-hat: filtered noise burst
    private static func synthHiHat(into buffer: inout [Float], at offset: Int, volume: Float) {
        let duration: Float = 0.04
        let samples = Int(duration * sampleRate)
        
        // Simple pseudo-random using a seed based on offset for consistency
        var rng = UInt32(offset & 0x7FFFFFFF)
        
        for i in 0..<samples {
            guard offset + i < buffer.count else { break }
            let n = Float(i) / Float(samples)
            
            // Simple noise via LCG
            rng = rng &* 1664525 &+ 1013904223
            let noise = Float(Int32(bitPattern: rng)) / Float(Int32.max)
            
            let amp = exp(-n * 25) * volume
            buffer[offset + i] += noise * amp
        }
    }
    
    /// Clap: layered noise bursts
    private static func synthClap(into buffer: inout [Float], at offset: Int) {
        let duration: Float = 0.12
        let samples = Int(duration * sampleRate)
        var rng = UInt32((offset ^ 0xDEAD) & 0x7FFFFFFF)
        
        for i in 0..<samples {
            guard offset + i < buffer.count else { break }
            let n = Float(i) / Float(samples)
            
            rng = rng &* 1664525 &+ 1013904223
            let noise = Float(Int32(bitPattern: rng)) / Float(Int32.max)
            
            // Three quick transients then tail
            var env: Float = 0
            if n < 0.04 { env = 0.4 }
            else if n < 0.06 { env = 0.15 }
            else if n < 0.10 { env = 0.5 }
            else { env = 0.5 * exp(-(n - 0.10) * 18) }
            
            buffer[offset + i] += noise * env * 0.22
        }
    }
    
    /// Sub bass: simple pattern with square-ish tone
    private static func synthBass(into buffer: inout [Float], beatDuration: Float) {
        // Note frequencies per beat in the pattern (Hz): E1, E1, G1, A1
        let pattern: [Float] = [41.2, 41.2, 49.0, 55.0]
        let totalBeats = bars * 4
        
        for beat in 0..<totalBeats {
            let freq = pattern[beat % pattern.count]
            let startSample = Int(Float(beat) * beatDuration * sampleRate)
            let noteSamples = Int(beatDuration * sampleRate)
            
            var phase: Float = 0
            for i in 0..<noteSamples {
                guard startSample + i < buffer.count else { break }
                let t = Float(i) / sampleRate
                let n = Float(i) / Float(noteSamples)
                
                phase += freq / sampleRate
                let p = phase - floor(phase)
                
                // Mix sine + soft square
                let sine = sin(p * 2 * .pi)
                let sq = tanh(sine * 3) // soft square
                let wave = sine * 0.6 + sq * 0.4
                
                // Envelope: fast attack, sustain, release at end
                let attack = min(1, t / 0.008)
                let release: Float = n > 0.85 ? (1 - n) / 0.15 : 1
                let amp = attack * release * 0.3
                
                buffer[startSample + i] += wave * amp
            }
        }
    }
    
    /// Acid-style synth: sawtooth with filter sweep
    private static func synthAcid(into buffer: inout [Float], beatDuration: Float) {
        let sixteenthDuration = beatDuration / 4
        let totalSteps = bars * 16
        
        // Pattern: frequencies in Hz, 0 = rest
        let pattern: [Float] = [
            130.8, 0, 164.8, 130.8,   0, 196.0, 0, 130.8,
            164.8, 0, 0, 220.0,       196.0, 0, 164.8, 0
        ]
        // Accent pattern (louder + more filter)
        let accents: [Bool] = [
            true, false, false, true,  false, true, false, false,
            true, false, false, true,  false, false, true, false
        ]
        
        for step in 0..<totalSteps {
            let idx = step % pattern.count
            let freq = pattern[idx]
            guard freq > 0 else { continue }
            
            let accent = accents[idx]
            let startSample = Int(Float(step) * sixteenthDuration * sampleRate)
            let gateLength = sixteenthDuration * 0.75
            let noteSamples = Int(gateLength * sampleRate)
            
            var phase: Float = 0
            // Simple one-pole low-pass state
            var lpState: Float = 0
            
            for i in 0..<noteSamples {
                guard startSample + i < buffer.count else { break }
                let t = Float(i) / sampleRate
                let n = Float(i) / Float(noteSamples)
                
                phase += freq / sampleRate
                
                // Sawtooth
                let saw = 2 * (phase - floor(phase + 0.5))
                
                // Filter envelope: cutoff sweeps down
                let filterAmount: Float = accent ? 0.9 : 0.5
                let cutoff = 0.15 + filterAmount * exp(-n * 12)
                
                // One-pole LPF
                lpState += cutoff * (saw - lpState)
                
                // Add some resonance via feedback
                let resonance: Float = accent ? 0.4 : 0.2
                let filtered = lpState + resonance * (lpState - saw) * cutoff
                
                // Envelope
                let attack = min(1, t / 0.003)
                let release: Float = n > 0.6 ? (1 - n) / 0.4 : 1
                let vol: Float = accent ? 0.18 : 0.12
                let amp = attack * release * vol
                
                buffer[startSample + i] += filtered * amp
            }
        }
    }
    
    // MARK: - Utilities
    
    /// Soft clipper for gentle saturation
    private static func softClip(_ x: Float) -> Float {
        return tanh(x)
    }
    
    /// Write 16-bit mono WAV file
    private static func writeWAV(_ samples: [Float], to url: URL) {
        let numSamples = samples.count
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(numSamples) * UInt32(blockAlign)
        
        var data = Data(capacity: 44 + Int(dataSize))
        
        // Helper to append little-endian values
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        
        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        append32(36 + dataSize)                             // file size - 8
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        append32(16)                                        // chunk size
        append16(1)                                         // PCM format
        append16(numChannels)
        append32(UInt32(sampleRate))
        append32(byteRate)
        append16(blockAlign)
        append16(bitsPerSample)
        
        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        append32(dataSize)
        
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16val = Int16(clamped * 32767)
            withUnsafeBytes(of: int16val.littleEndian) { data.append(contentsOf: $0) }
        }
        
        try? data.write(to: url)
    }
}
