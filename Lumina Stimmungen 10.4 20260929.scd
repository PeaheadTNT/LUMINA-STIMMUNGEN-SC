/*
LUMINA X — Tuning editor with custom tunings, stability update 2026-09-29
Target: SuperCollider 3.13/3.14, standard installation with Qt GUI.

START: Select this entire file (Ctrl+A), then evaluate it (Ctrl+Enter / Cmd+Enter).
Stop older Lumina scripts first with Ctrl+. / Cmd+.

USAGE
  - 11 built-in tunings in Earth/Ingong/Trane/Noskori/Vula, 7 instruments.
    Includes Sawtooth and Noise Pad (filtered pink noise).
    Default reference: A4/MIDI 69 = 440 Hz.
  - The + button beside Tuning opens the tuning editor with a circle,
    cents/ratio values, MIDI keys and frequencies. Confirm edits with Enter.
    Remove notes with minus; add notes using + below the list (up to 64 notes).
    Save the result under a new name in a chosen category.
    Drafts become active only after saving; closing the editor discards unsaved edits.
    #0 is the reference (1/1). Editing its Hz leaves the other note frequencies unchanged.
    The Cycle row sets the repetition factor and cannot be removed.
    Custom tunings also store their reference key and root frequency.
  - Each MIDI key advances ONE scale step. 19-TET uses 19 keys per octave.
  - Changing the reference note updates the Hz field and slider to that note's
    existing frequency. ALL MIDI pitches stay the same, including unequal scales.
    Example in 12-TET: A4 = 440 Hz -> C4 = 261.626 Hz; A4 remains 440 Hz.
  - Adjusting the main Hz control transposes NEW notes.
    A different built-in tuning places step 0 at the chosen reference note.
    Custom tunings restore their saved reference key and root frequency.
    Notes already sounding keep their current frequency.
  - Instrument volume and master volume also affect notes already sounding.
  - Open test window: C2–C7 keyboard, test tone, full scale with endpoint,
    velocity, step duration and Sustain/Sostenuto/Soft buttons.
    Hold the mouse button to play; release it to release the note.
    Repeated presses retrigger the key without accumulating unmatched held voices.
    Releases are retried and verified against the audio server.
    Every voice has a renewed server lease: a failed language-side controller cannot
    leave a synth running forever. Legitimately held notes have no maximum duration.
    Missing MIDI note-offs cannot be inferred reliably; use PANIC if the device
    sends neither a release nor a reset. Window deactivation stops test notes.
    Test pedals affect test notes only; MIDI pedals are isolated by device/channel.
    Scale playback captures tuning, reference, instrument and velocity at its start.
    Stop scale ends only scale notes; Stop all test notes ends all test notes.
    Closing the test window stops test notes; MIDI playing remains active.
  - The main window is centered in the available screen area. Other windows
    open offset from it, constrained to the available screen area.
    Controls adapt as the window is resized. In a narrow tuning editor, the
    circle and table stack vertically; wide windows show them side by side.
    Scrollbars appear below the minimum content size.
    Clicking an open window's launcher aligns it again with the main window.
  - The test tone releases automatically. PANIC stops all Lumina voices and scales.
  - Presets: enter a name, optionally set a trigger CC, then click Save new.
    Selecting a preset loads it. Overwrite and Delete affect the selected preset.
  - Preset CC: -1 = off; 0–119 except 7, 11, 64, 66 and 67.
    Triggered when the value crosses from below 64 to 64 or higher; one CC per preset.
  - CC7 = Master, CC11 = Expression, CC64 = Sustain.
    CC66 = Sostenuto (holds only keys held when the pedal is pressed).
    CC67 = Soft (continuous: softer, darker and quieter).
    Sustain brightens the timbre and increases reverb. Percussive Ingong sounds
    still decay naturally; the pedal does not create an endless sustained tone.
    CC120 = immediate voice stop; CC123–127 = release notes and clear holding pedals.
    CC121 resets pedals and expression; keys still physically held remain sounding.
    Note-offs and pedal-up/reset messages remain effective after an input-filter change.
    One shared stereo reverb replaces per-voice reverbs to reduce polyphonic load.
    The shared reverb has a natural tail; PANIC also clears this tail.
  - Voices are isolated by MIDI device/channel; select channels 1–16 or All.
  - DEV only: test window, SynthDef reload, self-test and MIDI debug output.
    Switching to LIVE closes the test window and stops its notes/scale; MIDI stays active.
    Rebuilding running audio is shown only in DEV. Start audio remains available
    in LIVE when audio is stopped. PANIC, the level meter and tuning editor remain available.
    Reload SynthDefs requires no server restart. Existing voices keep their old
    definitions; new notes use the updated definitions.
  - After Ctrl+. / Cmd+., use Start audio to resume.
  - Closing the main window saves settings and removes only this Lumina instance.
  - Evaluating the file again replaces Lumina cleanly without Server.killAll.

STORAGE
  Two alternating archives in the SuperCollider user application-support folder.
  Custom tunings, presets and settings are stored; no JSON plugin is required.
  Older Lumina files are not overwritten or automatically imported.
  Restore last settings at startup is OFF by default: saved presets and custom
  tunings are loaded, but the sound starts with default settings. Enable for session restore.
  Internal tuning/category IDs and archive filenames remain unchanged for compatibility.
  User-defined preset and tuning names retain their original spelling.
*/
(
var lum, server, previous, carry, noteNames, synthNames, tuningNames;
var normalize, defaults, cents, makeKey, status, syncGUI;

previous = ~lumina;
carry = nil;
if(previous.notNil) {
    if(previous[\snapshot].notNil) { carry = previous[\snapshot].value };
    if(previous[\dispose].notNil) { previous[\dispose].value };
};

server = Server.default;
lum = IdentityDictionary.new;
~lumina = lum;
lum[\alive] = true;
lum[\ready] = false;
lum[\starting] = false;
lum[\live] = true;
lum[\devViews] = List.new;
lum[\voices] = List.new;
lum[\retiringVoices] = Dictionary.new;
lum[\syncPending] = false;
lum[\testRefreshPending] = false;
lum[\tuningRefreshPending] = false;
lum[\masterRefreshPending] = false;
lum[\pedalFlushPending] = false;
lum[\dirtyPedals] = Dictionary.new;
lum[\levelsPending] = false;
lum[\pedals] = Dictionary.new;
lum[\sostenuto] = Dictionary.new;
lum[\soft] = Dictionary.new;
lum[\testKeys] = Dictionary.new;
lum[\testVoices] = Dictionary.new;
lum[\testVelocity] = 100;
lum[\testStepTime] = 0.35;
lum[\ccPrevious] = Dictionary.new;
lum[\expression] = 1.0;
lum[\presets] = List.new;
lum[\selected] = -1;
lum[\generation] = 0;
lum[\restore] = false;
lum[\channel] = -1;
lum[\source] = nil;
lum[\debug] = false;
lum[\message] = "Initializing ...";
lum[\freqRange] = [200.0,500.0];
lum[\archiveBase] = Platform.userAppSupportDir +/+ "Lumina8";

noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
synthNames = [\SineSmooth, \PulseSmooth, \SawSmooth, \FMBellSmooth, \NoisePad, \Ingong1, \Ingong2];
tuningNames = ['12-TET', '19-TET', 'Pythagoreisch', 'Mitteltönig',
    'Werckmeister III', 'Vallotti', 'Ingong 1', 'Ingong 2', 'Trane 1',
    'Noskori HM', 'Vula'];
lum[\categories] = [\Erde, \Ingong, \Trane, \Noskori, \Vula];
lum[\tuningGroups] = IdentityDictionary[
    \Erde -> ['12-TET','19-TET','Pythagoreisch','Mitteltönig','Werckmeister III','Vallotti'],
    \Ingong -> ['Ingong 1','Ingong 2'], \Trane -> ['Trane 1'],
    \Noskori -> ['Noskori HM'], \Vula -> ['Vula']
];
// Keep stored identifiers stable; translate built-in names only for display.
lum[\displayName] = { |name|
    switch(name,
        \Erde, { "Earth" },
        'Pythagoreisch', { "Pythagorean" },
        'Mitteltönig', { "Meantone" },
        { name.asString }
    )
};
lum[\synthLabels] = ["Sine", "Pulse", "Sawtooth", "FM Bell", "Noise Pad", "Ingong 1", "Ingong 2"];
cents = { |array| array.collect { |c| 2 ** (c / 1200) } };
lum[\tunings] = IdentityDictionary[
    '12-TET' -> (steps: Array.fill(12, { |i| 2 ** (i / 12) }), factor: 2),
    '19-TET' -> (steps: Array.fill(19, { |i| 2 ** (i / 19) }), factor: 2),
    'Pythagoreisch' -> (steps: [1, 256/243, 9/8, 32/27, 81/64, 4/3,
        729/512, 3/2, 128/81, 27/16, 16/9, 243/128], factor: 2),
    'Mitteltönig' -> (steps: [1, 1.0699, 1.1180, 1.1963, 1.25, 1.3375,
        1.3975, 1.495, 1.580, 1.671, 1.781, 1.888], factor: 2),
    'Werckmeister III' -> (steps: [1, 1.0667, 1.125, 1.2, 1.25, 1.333,
        1.4, 1.5, 1.6, 1.666, 1.777, 1.888], factor: 2),
    'Vallotti' -> (steps: [1, 1.059, 1.122, 1.193, 1.25, 1.334,
        1.392, 1.503, 1.584, 1.666, 1.777, 1.888], factor: 2),
    'Ingong 1' -> (steps: cents.([0,59,118,177,236,295,354,413,472,531,590,649]), factor: 1.5),
    'Ingong 2' -> (steps: cents.([0,55,111.7,165,203.9,266.9,315.6,386.3,435.1,498,551.3,617.5]), factor: 1.5),
    'Trane 1' -> (steps: cents.([0,85,170,255,339,425,510,595,680,765,850,935]), factor: 2 ** (1017/1200)),
    'Noskori HM' -> (steps: cents.([0,50,100,150,200,250,300,350,400,450,500,550]), factor: 2),
	'Vula' -> (steps: cents.([0,17,33,50,67,84,100,117,133,150,167,183]), factor: 2 ** (200/1200))
];
lum[\defs] = IdentityDictionary[
    \SineSmooth -> \Lumina8Sine, \PulseSmooth -> \Lumina8Pulse,
    \FMBellSmooth -> \Lumina8FM, \Ingong1 -> \Lumina8Ingong1,
    \Ingong2 -> \Lumina8Ingong2, \SawSmooth -> \Lumina8Saw, \NoisePad -> \Lumina8Noise
];

defaults = {
    (synth: \SineSmooth, tuning: '12-TET', base: 9, origin: 9, root: 440.0,
        master: 0.65, maxVoices: 64, cc: -1,
        amps: IdentityDictionary[\SineSmooth -> 0.5, \PulseSmooth -> 0.35,
            \FMBellSmooth -> 0.55, \SawSmooth -> 0.35, \NoisePad -> 0.5,
            \Ingong1 -> 0.5, \Ingong2 -> 0.65])
};
normalize = { |data|
    var result, value;
    result = defaults.value;
    if(data.isKindOf(Dictionary)) {
        if(synthNames.includes(data[\synth])) { result[\synth] = data[\synth] };
        if(tuningNames.includes(data[\tuning])) { result[\tuning] = data[\tuning] };
        [\base, \origin, \root, \master, \maxVoices, \cc].do { |key|
            value = data[key];
            if(value.isNumber) {
                if(value.isNaN.not and: { value.abs < 1e9 }) { result[key] = value };
            };
        };
        if(data[\amps].isKindOf(Dictionary)) {
            synthNames.do { |key|
                value = data[\amps][key];
                if(value.isNumber) {
                    if(value.isNaN.not and: { value.abs < 1e9 }) {
                        result[\amps][key] = value.clip(0, 1);
                    };
                };
            };
        };
    };
    result[\base] = result[\base].asInteger.clip(0, 11);
    // Older version-8 presets always placed step 0 at their reference note.
    if(data.isKindOf(Dictionary) and: { data[\origin].isNumber }) {
        result[\origin] = result[\origin].asInteger.clip(0, 11);
    } {
        result[\origin] = result[\base];
    };
    result[\root] = result[\root].clip(0.001, 100000000);
    result[\master] = result[\master].clip(0, 1);
    result[\maxVoices] = result[\maxVoices].asInteger.clip(8, 128);
    result[\cc] = result[\cc].asInteger.clip(-1, 119);
    if([7,11,64,66,67].includes(result[\cc])) { result[\cc] = -1 };
    result
};
lum[\config] = defaults.value;
lum[\snapshot] = { lum[\config].deepCopy };
status = { |text|
    lum[\message] = text;
    ("Lumina: " ++ text).postln;
    { if(lum[\alive] and: { lum[\statusView].notNil }) {
        lum[\statusView].string_(text);
    } }.defer;
    if(lum[\updateModeUI].notNil) { lum[\updateModeUI].value };
};
// At most one pending full refresh, even during a dense controller stream.
syncGUI = {
    if(lum[\syncPending].not) {
        lum[\syncPending] = true;
        {
            lum[\syncPending] = false;
            if(lum[\alive] and: { lum[\sync].notNil }) { lum[\sync].value };
        }.defer(0.04);
    };
};
lum[\refreshMaster] = {
    if(lum[\masterRefreshPending].not) {
        lum[\masterRefreshPending] = true;
        {
            lum[\masterRefreshPending] = false;
            if(lum[\alive] and: { lum[\syncMaster].notNil }) { lum[\syncMaster].value };
        }.defer(0.04);
    };
};
makeKey = { |src, chan| src.asString ++ ":" ++ chan.asString };

// Load custom tunings before presets so their tuning identifiers can be resolved.
lum[\userTunings] = List.new;
lum[\validPositive] = { |value, lo=0.000001, hi=100000000|
    value.isNumber and: { value.isNaN.not } and: { value >= lo } and: { value <= hi }
};
lum[\registerTuning] = { |record|
    var ok, name, category, steps;
    ok = record.isKindOf(Dictionary);
    if(ok) {
        name = record[\name]; category = record[\category]; steps = record[\steps];
        ok = name.isKindOf(Symbol) and: { name.asString.size > 0 }
            and: { name.asString.size <= 80 } and: { tuningNames.includes(name).not }
            and: { lum[\categories].includes(category) }
            and: { steps.isKindOf(SequenceableCollection) }
            and: { (steps.size >= 1) and: { steps.size <= 64 } }
            and: { steps.every { |v| lum[\validPositive].value(v) } }
            and: { (steps.first-1).abs < 0.0000001 }
            and: { lum[\validPositive].value(record[\factor]) }
            and: { lum[\validPositive].value(record[\root],0.001) }
            and: { record[\base].isKindOf(Integer) }
            and: { (record[\base] >= 0) and: { record[\base] <= 11 } };
    };
    if(ok) {
        lum[\tunings][name] = (steps: steps.asArray.copy, factor: record[\factor]);
        tuningNames = tuningNames.add(name);
        lum[\tuningGroups][category] = lum[\tuningGroups][category].add(name);
        lum[\userTunings].add(record.deepCopy);
    };
    ok
};
lum[\selectTuning] = { |name|
    var record;
    lum[\config][\tuning] = name;
    record = lum[\userTunings].detect { |item| item[\name] == name };
    if(record.notNil) {
        lum[\config][\base] = record[\base]; lum[\config][\root] = record[\root];
    };
    lum[\config][\origin] = lum[\config][\base];
};
lum[\saveCustomTuning] = { |record|
    var oldConfig, ok, name, category;
    oldConfig = lum[\config].deepCopy; name = record[\name]; category = record[\category];
    ok = lum[\registerTuning].value(record);
    if(ok) {
        lum[\selectTuning].value(name);
        ok = lum[\save].value;
        if(ok) {
            lum[\selected] = -1;
            syncGUI.value;
            status.("New tuning saved: " ++ name.asString);
        } {
            lum[\config] = oldConfig;
            lum[\tunings].removeAt(name);
            tuningNames = tuningNames.reject { |item| item == name };
            lum[\tuningGroups][category] = lum[\tuningGroups][category].reject { |item| item == name };
            lum[\userTunings].removeAt(lum[\userTunings].size-1);
        };
    } { status.("Tuning not saved: name already exists or values are invalid.") };
    ok
};

// Keep a complete second archive if a write fails.
lum[\load] = {
    var newest;
    newest = nil;
    ["_a.archive", "_b.archive"].do { |suffix|
        var path, data;
        path = lum[\archiveBase] ++ suffix;
        if(File.exists(path)) {
            try {
                data = Object.readArchive(path);
                if(data.isKindOf(Dictionary) and: { data[\schema] == 8 }
                    and: { data[\generation].isKindOf(Integer) }
                    and: { data[\presets].isKindOf(SequenceableCollection) }
                    and: { data[\settings].isKindOf(Dictionary) }) {
                    if(newest.isNil or: { data[\generation] > newest[\generation] }) { newest = data };
                };
            } { |error| ("Lumina: Cannot read archive: " ++ path).warn };
        };
    };
    if(newest.notNil) {
        lum[\generation] = newest[\generation];
        lum[\restore] = newest[\restore] == true;
        if(newest[\userTunings].isKindOf(SequenceableCollection)) {
            newest[\userTunings].do { |record|
                if(lum[\registerTuning].value(record).not) {
                    "Lumina: Skipped an invalid custom tuning in the archive.".warn;
                };
            };
        };
        newest[\presets].do { |p|
            if(p.isKindOf(Dictionary) and: { p[\name].isKindOf(String) }
                and: { p[\settings].isKindOf(Dictionary) }) {
                lum[\presets].add((name: p[\name], settings: normalize.(p[\settings])));
            };
        };
        if(lum[\restore]) { lum[\config] = normalize.(newest[\settings]) };
    };
};
lum[\save] = {
    var gen, path, data, check, ok;
    ok = false;
    gen = lum[\generation] + 1;
    path = lum[\archiveBase] ++ if(gen.odd) { "_a.archive" } { "_b.archive" };
    data = (schema: 8, generation: gen, restore: lum[\restore],
        settings: lum[\snapshot].value, presets: lum[\presets].deepCopy,
        userTunings: lum[\userTunings].deepCopy);
    try {
        data.writeArchive(path);
        check = Object.readArchive(path);
        if(check[\generation] != gen) { Error("Archive verification failed").throw };
        lum[\generation] = gen;
        ok = true;
    } { |error| status.("Saving failed: " ++ error.asString) };
    ok
};
lum[\load].value;
if(carry.notNil) { lum[\config] = normalize.(carry) };

lum[\ratioAt] = { |distance, tuning|
    var count, index, cycle;
    count = tuning[\steps].size;
    cycle = (distance / count).floor;
    index = distance - (cycle * count);
    tuning[\steps][index.asInteger] * (tuning[\factor] ** cycle)
};
lum[\frequency] = { |num, config|
    var c, tuning, origin, numerator, denominator;
    c = config ? lum[\config];
    tuning = lum[\tunings][c[\tuning]];
    origin = c[\origin] ? c[\base];
    numerator = lum[\ratioAt].value(num - (60 + origin), tuning);
    denominator = lum[\ratioAt].value(c[\base] - origin, tuning);
    c[\root] * (numerator / denominator)
};
lum[\changeBase] = { |newBase, config|
    var c, nextBase, nextFreq;
    c = config ? lum[\config];
    nextBase = newBase.asInteger.clip(0,11);
    // Measure in the OLD reference system before changing the reference note.
    // Preserve origin, including the ordering of unequal intervals.
    nextFreq = lum[\frequency].value(60 + nextBase, c);
    c[\base] = nextBase;
    c[\root] = nextFreq;
    c
};
lum[\updateFreqRange] = {
    var root;
    root = lum[\config][\root];
    // Only expand the range; never clip the new frequency to 200–500 Hz.
    if(root < lum[\freqRange][0]) { lum[\freqRange][0] = root * 0.5 };
    if(root > lum[\freqRange][1]) { lum[\freqRange][1] = root * 1.5 };
};

// Standard UGens only. All voices have gate and doneAction controls.
lum[\defineSynths] = {
    var color;
    // Shared continuous pedal control in every instrument SynthDef.
    color = { |signal, freq, soft, sustain, out, baseWet=0|
        var softness, resonance, cutoff, dry, mix;
        softness = Lag.kr(soft.clip(0,1),0.04);
        resonance = Lag.kr(sustain.clip(0,1),0.06);
        cutoff = (freq * (8 - (softness*6)) * (1 + (resonance*0.3)))
            .clip(100, SampleRate.ir*0.45);
        dry = LPF.ar(signal,cutoff) * (1 - (softness*0.35));
        mix = (baseWet + (resonance*0.45)).clip(0,0.75);
        Out.ar(out+2, (dry*mix) ! 2);
        dry * (1-mix)
    };
    SynthDef(\Lumina8Master, { |in=16, out=0, master=0.65, expression=1|
        var sig, wet;
        wet = In.ar(in+2,2);
        sig = LeakDC.ar(In.ar(in,2) + FreeVerb2.ar(wet[0],wet[1],1,0.85,0.4));
        sig = sig * Lag.kr(master.clip(0,1) * expression.clip(0,1), 0.03);
        sig = Compander.ar(sig, sig, 0.5, 1, 0.4, 0.005, 0.1);
        sig = Limiter.ar(sig.softclip, 0.9, 0.01);
        Out.ar(out, sig);
    }).add;
    SynthDef(\Lumina8Sine, { |out=16, freq=440, amp=0.5, vel=0.7, gate=1, soft=0, sustain=0, t_alive=1|
        var env, sig;
        FreeSelf.kr(Sweep.kr(t_alive) > 4); // renewed every 0.5 s by the voice watchdog
        env = EnvGen.kr(Env.asr(0.02,1,0.4,-4), gate, doneAction:2);
        sig = SinOsc.ar(freq) * env * Lag.kr(amp,0.02) * vel.clip(0,1).pow(1.8) * 0.22;
        sig = color.(sig,freq,soft,sustain,out);
        Out.ar(out, sig ! 2);
    }).add;
    SynthDef(\Lumina8Pulse, { |out=16, freq=440, amp=0.35, vel=0.7, gate=1, soft=0, sustain=0, t_alive=1|
        var env, sig;
        FreeSelf.kr(Sweep.kr(t_alive) > 4); // renewed every 0.5 s by the voice watchdog
        env = EnvGen.kr(Env.asr(0.01,1,0.6,-4), gate, doneAction:2);
        sig = Pulse.ar(freq,0.45) * env * Lag.kr(amp,0.02) * vel.clip(0,1).pow(1.4) * 0.15;
        sig = color.(sig,freq,soft,sustain,out);
        Out.ar(out, sig ! 2);
    }).add;

    SynthDef(\Lumina8Saw, { |out=16, freq=440, amp=0.35, vel=0.7, gate=1, soft=0, sustain=0, t_alive=1|
        var env, sig;
        FreeSelf.kr(Sweep.kr(t_alive) > 4); // renewed every 0.5 s by the voice watchdog
        env = EnvGen.kr(Env.asr(0.015,1,0.5,-4),gate,doneAction:2);
        sig = Saw.ar(freq) * env * Lag.kr(amp,0.02) * vel.clip(0,1).pow(1.4) * 0.16;
        sig = color.(sig,freq,soft,sustain,out);
        Out.ar(out,sig ! 2);
    }).add;
    SynthDef(\Lumina8Noise, { |out=16, freq=440, amp=0.5, vel=0.7, gate=1, soft=0, sustain=0, t_alive=1|
        var env, sig, cutoff;
        FreeSelf.kr(Sweep.kr(t_alive) > 4); // renewed every 0.5 s by the voice watchdog
        env = EnvGen.kr(Env.asr(0.12,1,0.9,-4),gate,doneAction:2);
        cutoff = (freq*2).clip(80,SampleRate.ir*0.4);
        sig = LPF.ar(PinkNoise.ar,cutoff) * env * Lag.kr(amp,0.02)
            * vel.clip(0,1).pow(1.4) * 0.35;
        sig = color.(sig,freq,soft,sustain,out);
        Out.ar(out,sig ! 2);
    }).add;
    SynthDef(\Lumina8FM, { |out=16, freq=440, amp=0.55, vel=0.7, gate=1, soft=0, sustain=0, t_alive=1|
        var env, mod, sig;
        FreeSelf.kr(Sweep.kr(t_alive) > 4); // renewed every 0.5 s by the voice watchdog
        env = EnvGen.kr(Env.asr(0.01,1,1,-4), gate, doneAction:2);
        mod = SinOsc.ar(freq*2, 0, freq * (0.5 - (Lag.kr(soft,0.04)*0.3)));
        sig = SinOsc.ar(freq+mod) * env * Lag.kr(amp,0.02) * vel.clip(0,1).pow(1.4) * 0.18;
        sig = color.(sig,freq,soft,sustain,out);
        Out.ar(out, sig ! 2);
    }).add;
    SynthDef(\Lumina8Ingong1, { |out=16, freq=440, amp=0.5, vel=0.7, gate=1, soft=0, sustain=0, t_alive=1|
        var bodyEnv, bellEnv, life, release, noise, tone, body, bell, sig;
        FreeSelf.kr(Sweep.kr(t_alive) > 4); // renewed every 0.5 s by the voice watchdog
        bodyEnv = EnvGen.kr(Env([0,1,0.8,0],[0.01,0.12,0.55],[-4,-2,-4]));
        bellEnv = EnvGen.kr(Env.perc(0.04,1.9,1,-5));
        life = EnvGen.kr(Env.linen(0.001,3.0,0.5), doneAction:2);
        release = EnvGen.kr(Env.asr(0.001,1,0.6,-4), gate, doneAction:2);
        noise = WhiteNoise.ar * EnvGen.kr(Env.perc(0.001,0.012,1,-8));
        noise = LPF.ar(HPF.ar(noise,500), (freq*4).clip(500,16000)) * 0.35;
        tone = Mix.fill(3, { |i| Pulse.ar(freq * (1 + ((i-1)*0.002)),0.45) }) / 3;
        body = (LPF.ar(HPF.ar(tone,200),9000 - (Lag.kr(soft,0.04)*6500))
            + (noise * (1 - (soft*0.55)))) * bodyEnv;
        bell = Mix(SinOsc.ar(freq * [2,2.71,3.18,5.03], 0, [0.25,0.22,0.18,0.1])) * bellEnv;
        sig = ((body*0.5) + (bell*0.7)) * life * release
            * Lag.kr(amp,0.02) * vel.clip(0,1).pow(1.4) * 0.3;
        sig = color.(sig,freq,soft,sustain,out,0.25);
        Out.ar(out, sig ! 2);
    }).add;
    SynthDef(\Lumina8Ingong2, { |out=16, freq=440, amp=0.65, vel=0.7, gate=1, soft=0, sustain=0, t_alive=1|
        var excitation, life, release, sig, click, body;
        FreeSelf.kr(Sweep.kr(t_alive) > 4); // renewed every 0.5 s by the voice watchdog
        excitation = LPF.ar(PinkNoise.ar,6000) * EnvGen.kr(Env.perc(0.001,0.015,1,-6));
        click = HPF.ar(WhiteNoise.ar,8000) * EnvGen.kr(Env.perc(0.0005,0.005,0.1,-6));
        excitation = excitation + (click * (1-soft));
        life = EnvGen.kr(Env.linen(0.001,2.0,1.0), doneAction:2);
        release = EnvGen.kr(Env.asr(0.001,1,0.6,-4), gate, doneAction:2);
        sig = Mix(CombL.ar(excitation,0.06,1/(freq*[1,0.996]),1.8));
        body = BPF.ar(sig,(freq*2).clip(40,16000),0.6,0.2)
            + BPF.ar(sig,(freq*3.1).clip(40,16000),0.5,0.15);
        sig = LPF.ar(HPF.ar(sig+body,400),8000 - (Lag.kr(soft,0.04)*6800)) * life * release
            * Lag.kr(amp,0.02) * vel.clip(0,1).pow(1.4) * 0.65;
        sig = color.(sig,freq,soft,sustain,out);
        Out.ar(out, sig ! 2);
    }).add;
};

lum[\panic] = {
    if(lum[\scaleTask].notNil) { lum[\scaleTask].stop; lum[\scaleTask] = nil };
    if(server.serverRunning and: { lum[\voiceGroup].notNil }) { lum[\voiceGroup].freeAll };
    lum[\voices].copy.do { |v| lum[\retireVoice].value(v) };
    if(lum[\ready] and: { server.serverRunning } and: { lum[\masterNode].notNil }) {
        lum[\masterNode] = Synth.replace(lum[\masterNode], \Lumina8Master,
            [\in,lum[\bus].index, \master,lum[\config][\master], \expression,lum[\expression]]);
    };
    lum[\dirtyPedals].clear;
    lum[\pedals].clear;
    lum[\sostenuto].clear;
    lum[\soft].clear;
    lum[\testVoices].clear;
    lum[\ccPrevious].clear;
    if(lum[\refreshTest].notNil) { lum[\refreshTest].value };
};
lum[\protected] = { |voice|
    var key;
    key = makeKey.(voice[\src],voice[\chan]);
    ((lum[\pedals][key] ? 0) >= 0.5) or: {
        ((lum[\sostenuto][key] ? 0) >= 0.5) and: { voice[\captured] == true }
    }
};
lum[\keyUp] = { |voice|
    if(voice.notNil and: { lum[\voices].includes(voice) }) {
        voice[\held] = false;
        if(lum[\protected].value(voice).not) { lum[\release].value(voice) };
    };
};
lum[\pedal] = { |cc, value, chan, src|
    var key, level, old;
    key = makeKey.(src,chan);
    level = value.clip(0,127)/127;
    if(cc == 64) { lum[\pedals][key] = level };
    if(cc == 67) { lum[\soft][key] = level };
    if(cc == 66) {
        old = lum[\sostenuto][key] ? 0;
        lum[\sostenuto][key] = level;
        if(level >= 0.5 and: { old < 0.5 }) {
            lum[\voices].do { |v|
                if((v[\src] == src) and: { v[\chan] == chan }) {
                    v[\captured] = v[\held] and: { v[\releasing].not };
                };
            };
        };
        if(level < 0.5) {
            lum[\voices].do { |v|
                if((v[\src] == src) and: { v[\chan] == chan }) { v[\captured] = false };
            };
        };
    };
    if(cc != 66) { lum[\queuePedalSound].value(src,chan) };
    lum[\voices].do { |v|
        if((v[\src] == src) and: { v[\chan] == chan }) {
            if(v[\held].not and: { lum[\protected].value(v).not }) { lum[\release].value(v) };
        };
    };
    if(lum[\refreshTest].notNil) { lum[\refreshTest].value };
};

// Sound updates are batched on SystemClock; note/pedal release never waits for the GUI.
lum[\queuePedalSound] = { |src, chan|
    lum[\dirtyPedals][makeKey.(src,chan)] = [src,chan];
    if(lum[\pedalFlushPending].not) {
        lum[\pedalFlushPending] = true;
        SystemClock.sched(0.02, {
            var dirty;
            lum[\pedalFlushPending] = false;
            dirty = lum[\dirtyPedals]; lum[\dirtyPedals] = Dictionary.new;
            if(lum[\alive] and: { lum[\ready] } and: { server.serverRunning }) {
                lum[\voices].asArray.clump(16).do { |batch|
                    server.makeBundle(nil, {
                        batch.do { |v|
                            var key, soft, sustain;
                            key = makeKey.(v[\src],v[\chan]);
                            if(dirty[key].notNil) {
                                soft = lum[\soft][key] ? 0; sustain = lum[\pedals][key] ? 0;
                                if((v[\sentSoft] != soft) or: { v[\sentSustain] != sustain }) {
                                    v[\node].set(\soft,soft,\sustain,sustain);
                                    v[\sentSoft] = soft; v[\sentSustain] = sustain;
                                };
                            };
                        };
                    });
                };
            };
            nil
        });
    };
};
lum[\resetChannel] = { |src, chan, releaseKeys=false, immediate=false|
    var key;
    key = makeKey.(src,chan);
    [lum[\pedals],lum[\sostenuto],lum[\soft]].do { |dict| dict.removeAt(key) };
    lum[\queuePedalSound].value(src,chan);
    lum[\voices].copy.do { |v|
        if((v[\src] == src) and: { v[\chan] == chan }) {
            v[\captured] = false;
            if(immediate) { lum[\retireVoice].value(v) } {
                if(releaseKeys or: { v[\held].not }) { lum[\release].value(v) };
            };
        };
    };
    if(lum[\refreshTest].notNil) { lum[\refreshTest].value };
};
lum[\release] = { |voice|
    if(voice[\releasing].not) {
        voice[\held] = false;
        voice[\releasing] = true;
        voice[\releasedAt] = Main.elapsedTime;
    };
    // A repeated note-off must also retry voices already marked as releasing.
    if(server.serverRunning) { voice[\node].set(\gate,0) };
};
lum[\forgetNode] = { |id|
    lum[\retiringVoices].removeAt(id);
    lum[\voices] = lum[\voices].reject { |v| v[\node].nodeID == id };
};
lum[\retireVoice] = { |voice|
    var id;
    id = voice[\node].nodeID;
    lum[\voices].remove(voice);
    if(lum[\retiringVoices][id].isNil) {
        lum[\retiringVoices][id] = (node: voice[\node], lastTry: Main.elapsedTime);
    };
    if(server.serverRunning) { voice[\node].free };
};
lum[\startVoiceWatchdog] = {
    if(lum[\voiceWatchdog].notNil) { lum[\voiceWatchdog].stop };
    lum[\voiceWatchdog] = Routine({
        var heartbeatAt, queryAt;
        heartbeatAt = 0; queryAt = 0;
        while { lum[\alive] } {
            // An individual send error must not terminate all future cleanup.
            try {
                if(lum[\ready] and: { server.serverRunning }) {
                    var now;
                    now = Main.elapsedTime;
                    lum[\voices].copy.do { |v|
                        if(v[\held].not and: { lum[\protected].value(v).not }
                            and: { v[\releasing].not }) { lum[\release].value(v) };
                        if(v[\releasing] and: { (now-v[\releasedAt]) > 2 }) {
                            lum[\retireVoice].value(v);
                        };
                    };
                    if((now-heartbeatAt) >= 0.5) {
                        heartbeatAt = now;
                        lum[\voices].asArray.clump(16).do { |batch|
                            server.makeBundle(nil, {
                                batch.do { |v|
                                    var key;
                                    key = makeKey.(v[\src],v[\chan]);
                                    // Repair lost parameter/release packets as well as renewing the lease.
                                    v[\node].set(\t_alive,1, \gate,if(v[\releasing]) { 0 } { 1 },
                                        \soft,lum[\soft][key] ? 0, \sustain,lum[\pedals][key] ? 0,
                                        \amp,lum[\config][\amps][v[\synth]]);
                                };
                            });
                        };
                        lum[\masterNode].set(\master,lum[\config][\master],\expression,lum[\expression]);
                    };
                    lum[\retiringVoices].copy.keysValuesDo { |id, entry|
                        if((now-entry[\lastTry]) >= 1) {
                            entry[\node].free;
                            entry[\lastTry] = now;
                        };
                    };
                    if((now-queryAt) >= 2) {
                        queryAt = now;
                        // Explicit missing-node replies also recover a lost /n_end notification.
                        (lum[\voices].collect { |v| v[\node].nodeID }.asArray
                            ++ lum[\retiringVoices].keys.asArray).clump(16).do { |ids|
                            server.makeBundle(nil, { ids.do { |id| server.sendMsg('/n_query',id) } });
                        };
                    };
                };
            } { |error| ("Lumina watchdog: " ++ error.asString).warn };
            0.1.wait;
        };
    }).play(SystemClock);
};
lum[\applyLevels] = { |includeVoices=true|
    lum[\levelsNeedVoices] = (lum[\levelsNeedVoices] ? false) or: { includeVoices };
    if(lum[\levelsPending].not) {
        lum[\levelsPending] = true;
        SystemClock.sched(0.02, {
            var updateVoices;
            lum[\levelsPending] = false;
            updateVoices = lum[\levelsNeedVoices]; lum[\levelsNeedVoices] = false;
            if(lum[\alive] and: { lum[\ready] } and: { server.serverRunning }) {
                lum[\masterNode].set(\master,lum[\config][\master], \expression,lum[\expression]);
                if(updateVoices) {
                    lum[\voices].asArray.clump(16).do { |batch|
                        server.makeBundle(nil, {
                            batch.do { |v| v[\node].set(\amp,lum[\config][\amps][v[\synth]]) };
                        });
                    };
                };
            };
            nil
        });
    };
};
lum[\trimVoices] = {
    // The list follows creation order, including voices in their release stage.
    while { lum[\voices].size > lum[\config][\maxVoices] } {
        var old;
        old = lum[\voices][lum[\voices].detectIndex { |v| v[\held].not } ? 0];
        lum[\retireVoice].value(old);
    };
};
lum[\spawn] = { |freq, velocity=100, num = -1, chan = -1, src = -1, synthKind|
    var node, voice, old, kind, key;
    voice = nil;
    if(lum[\alive] and: { lum[\ready] } and: { server.serverRunning }) {
        if(freq >= 20 and: { freq <= 18000 }
            and: { (lum[\voices].size + lum[\retiringVoices].size) < (lum[\config][\maxVoices]*2) }) {
            while { lum[\voices].size >= lum[\config][\maxVoices] } {
                old = lum[\voices][lum[\voices].detectIndex { |v| v[\held].not } ? 0];
                lum[\retireVoice].value(old);
            };
            kind = synthKind ? lum[\config][\synth];
            key = makeKey.(src,chan);
            node = Synth(lum[\defs][kind], [\out,lum[\bus].index, \freq,freq,
                \amp,lum[\config][\amps][kind], \vel,velocity.clip(1,127)/127,
                \soft,lum[\soft][key] ? 0, \sustain,lum[\pedals][key] ? 0], lum[\voiceGroup]);
            voice = (node: node, synth: kind, num: num, chan: chan, src: src,
                held: true, releasing: false, captured: false,
                sentSoft: lum[\soft][key] ? 0, sentSustain: lum[\pedals][key] ? 0);
            lum[\voices].add(voice);
        } {
            status.("Skipped note (frequency outside 20–18000 Hz or cleanup backlog): " ++ freq.round(0.01));
        };
    };
    voice
};
// One physically held key per note/device/channel. Release tails may overlap.
// Repair duplicate note-ons without leaving unmatched held voices behind.
lum[\releaseHeldKey] = { |num, chan, src, testType, onlyHeld=false|
    lum[\voices].copy.do { |voice|
        if((voice[\num] == num) and: { voice[\chan] == chan }
            and: { voice[\src] == src } and: { onlyHeld.not or: { voice[\held] } }
            and: { testType.isNil or: { voice[\testType] == testType } }) {
            lum[\keyUp].value(voice);
        };
    };
};
lum[\noteOn] = { |velocity, num, chan, src|
    if(lum[\debug]) { [\noteOn,num,\velocity,velocity,\channel,chan+1,\source,src].postln };
    lum[\releaseHeldKey].value(num,chan,src,nil,true);
    lum[\spawn].value(lum[\frequency].value(num),velocity,num,chan,src);
};
lum[\noteOff] = { |num, chan, src|
    if(lum[\debug]) { [\noteOff,num,\channel,chan+1,\source,src].postln };
    lum[\releaseHeldKey].value(num,chan,src);
};
lum[\accept] = { |chan, src|
    lum[\alive] and: { (lum[\channel] < 0) or: { lum[\channel] == chan } }
        and: { lum[\source].isNil or: { lum[\source] == src } }
};
lum[\applyPreset] = { |index|
    if(index >= 0 and: { index < lum[\presets].size }) {
        lum[\selected] = index;
        lum[\config] = normalize.(lum[\presets][index][\settings]);
        lum[\applyLevels].value;
        lum[\trimVoices].value;
        { if(lum[\alive] and: { lum[\nameField].notNil }) {
            lum[\nameField].string_(lum[\presets][index][\name]);
        } }.defer;
        syncGUI.value;
        status.("Preset loaded: " ++ lum[\presets][index][\name]);
    };
};
lum[\handleCC] = { |value, cc, chan, src|
    var key, prior, index, accepted, safety;
    accepted = lum[\accept].value(chan,src);
    safety = [120,121,123,124,125,126,127].includes(cc)
        or: { [64,66,67].includes(cc) and: { value < 64 } };
    if(lum[\debug]) {
        [\CC,cc,\value,value,\channel,chan+1,\source,src,\accepted,accepted,\safety,safety].postln;
    };
    if(lum[\alive] and: { accepted or: { safety } }) {
        key = makeKey.(src,chan);
        case
        { cc == 7 } {
            if(lum[\config][\master] != (value/127)) {
                lum[\config][\master] = value/127;
                lum[\applyLevels].value(false); lum[\refreshMaster].value;
            };
        }
        { cc == 11 } {
            if(lum[\expression] != (value/127)) {
                lum[\expression] = value/127; lum[\applyLevels].value(false);
            };
        }
        { [64,66,67].includes(cc) } { lum[\pedal].value(cc,value,chan,src) }
        { cc == 121 } {
            lum[\resetChannel].value(src,chan);
            if(accepted) { lum[\expression] = 1; lum[\applyLevels].value(false) };
            lum[\ccPrevious].keys.asArray.do { |k|
                if(k.beginsWith(key ++ ":")) { lum[\ccPrevious].removeAt(k) };
            };
        }
        { [120,123,124,125,126,127].includes(cc) } {
            lum[\resetChannel].value(src,chan,true,cc == 120);
        }
        {
            key = key ++ ":" ++ cc.asString;
            prior = lum[\ccPrevious][key] ? 0;
            lum[\ccPrevious][key] = value;
            if(value >= 64 and: { prior < 64 }) {
                index = lum[\presets].detectIndex { |p| p[\settings][\cc] == cc };
                if(index.notNil) { lum[\applyPreset].value(index) };
            };
        };
    };
};
lum[\initMIDI] = {
    try {
        MIDIClient.init;
        MIDIIn.connectAll;
        MIDIdef.noteOn(\Lumina8On, { |vel, num, chan, src|
            if(lum[\alive]) {
                if(vel == 0) { lum[\noteOff].value(num,chan,src) } {
                    if(lum[\accept].value(chan,src)) { lum[\noteOn].value(vel,num,chan,src) } {
                        if(lum[\debug]) { [\ignoredNoteOn,num,\channel,chan+1,\source,src].postln };
                    };
                };
            };
        }).permanent_(true);
        MIDIdef.noteOff(\Lumina8Off, { |vel, num, chan, src|
            if(lum[\alive]) { lum[\noteOff].value(num,chan,src) };
        }).permanent_(true);
        MIDIdef.cc(\Lumina8CC, { |value, cc, chan, src|
            lum[\handleCC].value(value,cc,chan,src);
        }).permanent_(true);
        MIDIdef.reset(\Lumina8Reset, { |src|
            if(lum[\alive]) { 16.do { |chan| lum[\resetChannel].value(src,chan,true,true) } };
        }).permanent_(true);
        status.("MIDI connected");
    } { |error| status.("MIDI unavailable; the test tone is still available in DEV mode. " ++ error.asString) };
};

lum[\updateModeUI] = {
    {
        if(lum[\alive]) {
            lum[\devViews].do { |view| view.visible_(lum[\live].not) };
            if(lum[\audioButton].notNil) {
                lum[\audioButton].visible_(lum[\live].not or: { lum[\ready].not });
                lum[\audioButton].states_([[if(lum[\live]) {
                    "Start audio"
                } { "Start / rebuild audio" }]]);
            };
            if(lum[\debugView].notNil) { lum[\debugView].value_(lum[\debug]) };
        };
    }.defer;
};
lum[\setLive] = { |live|
    lum[\live] = live;
    if(live) {
        lum[\debug] = false;
        if(lum[\reloadTask].notNil) { lum[\reloadTask].stop; lum[\reloadTask] = nil };
        if(lum[\testWindow].notNil) { lum[\testWindow].close } {
            lum[\stopTest].value;
        };
    };
    lum[\updateModeUI].value;
};

lum[\startAudio] = {
    if(lum[\starting].not and: { lum[\alive] }) {
        if(lum[\live] and: { lum[\ready] }) {
            status.("LIVE: Rebuilding is disabled. Switch to DEV first.");
        } {
            lum[\starting] = true;
            lum[\ready] = false;
            lum[\panic].value;
            if(server.serverRunning and: { lum[\rootGroup].notNil }) { lum[\rootGroup].free };
            lum[\rootGroup] = nil;
            lum[\voiceGroup] = nil;
            status.("Preparing audio ...");
            server.waitForBoot({
                if(lum[\alive]) {
                    lum[\buildTask] = Routine({
                        try {
                            lum[\defineSynths].value;
                            server.sync;
                            if(lum[\alive]) {
                                if(lum[\bus].notNil) { lum[\bus].free };
                                lum[\bus] = Bus.audio(server,4);
                                lum[\rootGroup] = Group.tail(server.defaultGroup);
                                lum[\voiceGroup] = Group.head(lum[\rootGroup]);
                                lum[\masterNode] = Synth.tail(lum[\rootGroup], \Lumina8Master,
                                    [\in,lum[\bus].index, \master,lum[\config][\master], \expression,lum[\expression]]);
                                server.sync;
                                lum[\ready] = true;
                                lum[\startVoiceWatchdog].value;
                                status.("Audio ready — play via MIDI. The test window is available in DEV mode.");
                            };
                        } { |error| lum[\ready] = false; status.("Audio error: " ++ error.asString) };
                        lum[\starting] = false;
                    }).play(SystemClock);
                };
            }, onFailure: {
                lum[\starting] = false;
                status.("Server failed to start. Check the audio device in SuperCollider.");
                false
            });
        };
    };
};

OSCdef(\Lumina8NodeEnd, { |message|
    var id;
    id = message[1];
    lum[\forgetNode].value(id);
    if(lum[\refreshTest].notNil) { lum[\refreshTest].value };
    if(lum[\rootGroup].notNil and: { lum[\rootGroup].nodeID == id }) {
        lum[\ready] = false;
        lum[\rootGroup] = nil;
        lum[\voiceGroup] = nil;
        lum[\updateModeUI].value;
    };
}, '/n_end', server.addr).permanent_(true);
OSCdef(\Lumina8QueryFail, { |message|
    var parts, id;
    if(message.size >= 3 and: { message[1].asString == "/n_query" }) {
        parts = message[2].asString.split($ );
        if(parts.size == 4 and: { parts[0] == "Node" }
            and: { parts[2] == "not" } and: { parts[3] == "found" }) {
            id = parts[1].asInteger;
            if((id.asString == parts[1]) and: { (lum[\retiringVoices][id].notNil)
                or: { lum[\voices].any { |v| v[\node].nodeID == id } } }) {
                lum[\forgetNode].value(id);
                if(lum[\refreshTest].notNil) { lum[\refreshTest].value };
            };
        };
    };
}, '/fail', server.addr).permanent_(true);


lum[\stopHook] = {
    if(lum[\voiceWatchdog].notNil) { lum[\voiceWatchdog].stop; lum[\voiceWatchdog] = nil };
    if(lum[\buildTask].notNil) { lum[\buildTask].stop };
    if(lum[\scaleTask].notNil) { lum[\scaleTask].stop; lum[\scaleTask] = nil };
    lum[\ready] = false;
    lum[\starting] = false;
    lum[\voices].clear; lum[\retiringVoices].clear;
    lum[\dirtyPedals].clear;
    [\syncPending,\testRefreshPending,\tuningRefreshPending,\masterRefreshPending,
        \pedalFlushPending,\levelsPending,\levelsNeedVoices].do { |key| lum[key] = false };
    lum[\pedals].clear;
    lum[\sostenuto].clear;
    lum[\soft].clear;
    lum[\testVoices].clear;
    if(lum[\refreshTest].notNil) { lum[\refreshTest].value };
    lum[\ccPrevious].clear;
    lum[\rootGroup] = nil;
    lum[\voiceGroup] = nil;
    status.("Stopped. Click 'Start audio' to resume.");
};
lum[\quitHook] = {
    lum[\stopHook].value;
    // A server restart resets the bus allocator: do not free the old bus.
    lum[\bus] = nil;
};
CmdPeriod.add(lum[\stopHook]);
ServerQuit.add(lum[\quitHook],server);

// Runs synchronously with isolated state. No synth is created or stopped.
// The routing/pedal functions under test are the same ones used by the MIDI callbacks.
lum[\voiceLogicTest] = { |assert|
    var keys, saved, releases, retired, onCalls, makeVoice, a, b, c, d;
    keys = [\voices,\retiringVoices,\pedals,\sostenuto,\soft,\ccPrevious,
        \channel,\source,\debug,\expression,\release,\retireVoice,\queuePedalSound,
        \refreshTest,\applyLevels,\refreshMaster,\noteOn];
    saved = IdentityDictionary.new;
    keys.do { |key| saved[key] = lum[key] };
    releases = List.new; retired = List.new; onCalls = 0;
    makeVoice = { |num=60, chan=0, src=101, held=true|
        (num: num, chan: chan, src: src, held: held, releasing: false, captured: false)
    };
    protect {
        lum[\voices] = List.new; lum[\retiringVoices] = Dictionary.new;
        lum[\pedals] = Dictionary.new; lum[\sostenuto] = Dictionary.new;
        lum[\soft] = Dictionary.new; lum[\ccPrevious] = Dictionary.new;
        lum[\channel] = -1; lum[\source] = nil; lum[\debug] = false;
        lum[\release] = { |v| v[\held] = false; v[\releasing] = true; releases.add(v) };
        lum[\retireVoice] = { |v| retired.add(v); lum[\voices].remove(v) };
        [\queuePedalSound,\refreshTest,\applyLevels,\refreshMaster].do { |key| lum[key] = {} };
        lum[\noteOn] = { onCalls = onCalls+1 };

        a = makeVoice.(60); b = makeVoice.(60); c = makeVoice.(60,1); d = makeVoice.(60,0,202);
        lum[\voices].addAll([a,b,c,d]);
        lum[\noteOff].value(60,0,101);
        assert.(a[\releasing] and: { b[\releasing] },"note-off releases all matching voices");
        assert.(c[\held] and: { d[\held] },"note-off preserves other channels/devices");
        lum[\noteOff].value(60,0,101);
        assert.(releases.size == 4,"repeated note-off retries release");

        a = makeVoice.(61); b = makeVoice.(62); lum[\voices] = List[a,b];
        lum[\pedal].value(64,127,0,101);
        lum[\keyUp].value(a);
        assert.(a[\held].not and: { a[\releasing].not },"sustain holds released keys");
        lum[\handleCC].value(0,121,0,101);
        assert.(a[\releasing],"CC121 releases pedal-held notes");
        assert.(b[\held] and: { b[\releasing].not },"CC121 preserves physically held keys");

        a = makeVoice.(63); lum[\voices] = List[a];
        lum[\pedal].value(66,127,0,101);
        b = makeVoice.(64); lum[\voices].add(b);
        lum[\keyUp].value(a); lum[\keyUp].value(b);
        assert.(a[\releasing].not and: { b[\releasing] },"sostenuto captures only existing held keys");
        lum[\pedal].value(66,0,0,101);
        assert.(a[\releasing],"sostenuto-up releases captured key");

        [123,124,125,126,127].do { |cc|
            a = makeVoice.(65); b = makeVoice.(65,1); lum[\voices] = List[a,b];
            lum[\handleCC].value(0,cc,0,101);
            assert.(a[\releasing] and: { b[\held] },"CC" ++ cc ++ " channel-scoped release");
        };
        a = makeVoice.(66); lum[\voices] = List[a];
        lum[\handleCC].value(0,120,0,101);
        assert.(retired.includes(a) and: { lum[\voices].isEmpty },"CC120 uses tracked retirement");

        // A stale input filter must never strand a voice already owned by Lumina.
        lum[\channel] = 9; lum[\source] = 999;
        a = makeVoice.(67); lum[\voices] = List[a];
        if(MIDIdef(\Lumina8Off).notNil) {
            MIDIdef(\Lumina8Off).func.value(0,67,0,101);
            assert.(a[\releasing],"note-off bypasses changed input filter");
            a = makeVoice.(68); lum[\voices] = List[a];
            MIDIdef(\Lumina8On).func.value(0,68,0,101);
            assert.(a[\releasing],"velocity-zero note-on bypasses changed input filter");
            MIDIdef(\Lumina8On).func.value(100,69,0,101);
            assert.(onCalls == 0,"new notes still obey input filter");
        };
        a = makeVoice.(70,0,101,false); lum[\voices] = List[a];
        lum[\pedals][makeKey.(101,0)] = 1;
        lum[\handleCC].value(0,64,0,101);
        assert.(a[\releasing],"pedal-up bypasses changed input filter");
        a = makeVoice.(71); lum[\voices] = List[a];
        lum[\handleCC].value(0,123,0,101);
        assert.(a[\releasing],"all-notes-off bypasses changed input filter");
    } {
        keys.do { |key| lum[key] = saved[key] };
    };
};

lum[\diagnoseVoices] = {
    if(lum[\live]) { status.("Voice diagnostics are only available in DEV mode.") } {
    [\averageCPU,server.avgCPU,\peakCPU,server.peakCPU,
        \tracked,lum[\voices].size,\awaitingRemoval,lum[\retiringVoices].size].postln;
    lum[\voices].do { |v|
        [\node,v[\node].nodeID,\note,v[\num],\channel,v[\chan],\source,v[\src],
            \held,v[\held],\pedalHeld,lum[\protected].value(v),\releasing,v[\releasing]].postln;
    };
    if(server.serverRunning and: { lum[\voiceGroup].notNil }) {
        server.sendMsg('/g_dumpTree',lum[\voiceGroup].nodeID,0);
    };
    };
};

lum[\selfTest] = {
    var checks, assert, c, n, f0;
    checks = 0;
    assert = { |condition, text|
        if(condition.not) { Error("Self-test: " ++ text).throw };
        checks = checks + 1;
    };
    if(lum[\live]) { status.("Self-test is only available in DEV mode.") } {
    try {
        tuningNames.do { |name|
            c = defaults.value; c[\tuning] = name;
            n = lum[\tunings][name][\steps].size;
            f0 = lum[\frequency].value(69,c);
            assert.((f0-440).abs < 0.00001, lum[\displayName].value(name) ++ " reference pitch");
            (-24..24).do { |offset|
                var a, b;
                a = lum[\frequency].value(69+offset,c);
                b = lum[\frequency].value(69+offset+n,c);
                assert.(((b/a)-lum[\tunings][name][\factor]).abs < 0.00001,
                    lum[\displayName].value(name) ++ " cycle " ++ offset);
            };
            (0..11).do { |newBase|
                var changed, restored;
                changed = lum[\changeBase].value(newBase,c.deepCopy);
                (0..127).do { |num|
                    var before, after;
                    before = lum[\frequency].value(num,c);
                    after = lum[\frequency].value(num,changed);
                    assert.(((after/before)-1).abs < 0.0000001,
                        lum[\displayName].value(name) ++ " reference-note change: MIDI " ++ num);
                };
                // Preset normalization must preserve the shifted scale position.
                restored = normalize.(changed);
                assert.((lum[\frequency].value(69,restored)-440).abs < 0.00001,
                    lum[\displayName].value(name) ++ " preset reference note");
            };
        };
        c = defaults.value;
        (0..127).do { |num|
            assert.((lum[\frequency].value(num,c)-num.midicps).abs < 0.00001,"12-TET MIDI " ++ num);
        };
        assert.(makeKey.(1,0) != makeKey.(1,1),"MIDI channel isolation");
        assert.(makeKey.(1,0) != makeKey.(2,0),"MIDI device isolation");
        lum[\voiceLogicTest].value(assert);
        status.(checks.asString ++ " self-tests passed (excluding audio/hardware tests).");
    } { |error| status.(error.asString) };
    };
};

lum[\dispose] = {
    if(lum[\alive]) {
        lum[\save].value;
        lum[\alive] = false;
        if(lum[\voiceWatchdog].notNil) { lum[\voiceWatchdog].stop; lum[\voiceWatchdog] = nil };
        lum[\ready] = false;
        if(lum[\buildTask].notNil) { lum[\buildTask].stop };
        if(lum[\reloadTask].notNil) { lum[\reloadTask].stop };
        if(lum[\scaleTask].notNil) { lum[\scaleTask].stop; lum[\scaleTask] = nil };
        [\Lumina8On,\Lumina8Off,\Lumina8CC,\Lumina8Reset].do { |key|
            if(MIDIdef(key).notNil) { MIDIdef(key).free };
        };
        [\Lumina8NodeEnd,\Lumina8QueryFail].do { |key|
            if(OSCdef(key).notNil) { OSCdef(key).free };
        };
        CmdPeriod.remove(lum[\stopHook]);
        ServerQuit.remove(lum[\quitHook],server);
        if(server.serverRunning and: { lum[\rootGroup].notNil }) { lum[\rootGroup].free };
        if(lum[\bus].notNil) { lum[\bus].free; lum[\bus] = nil };
        lum[\voices].clear; lum[\retiringVoices].clear;
        if(lum[\testWindow].notNil) {
            { if(lum[\testWindow].notNil) {
                lum[\testWindow].onClose_({}); lum[\testWindow].close; lum[\testWindow] = nil;
            } }.defer;
        };
        if(lum[\tuningWindow].notNil) {
            { if(lum[\tuningWindow].notNil) {
                lum[\tuningWindow].onClose_({}); lum[\tuningWindow].close;
                lum[\tuningWindow] = nil; lum[\tuningRefresh] = nil;
            } }.defer;
        };
        if(lum[\window].notNil) {
            { lum[\window].onClose_({}); lum[\window].close }.defer;
        };
    };
};

// Separate test source: no interaction with MIDI pedals.
lum[\refreshTest] = {
    if(lum[\testRefreshPending].not) {
        lum[\testRefreshPending] = true;
    {
        lum[\testRefreshPending] = false;
        if(lum[\alive] and: { lum[\testWindow].notNil }) {
            var key, c;
            key = makeKey.(\luminaTest,0); c = lum[\config];
            lum[\testKeys].keysValuesDo { |num, view|
                var voice;
                voice = lum[\testVoices][num];
                if(voice.notNil and: { lum[\voices].includes(voice).not }) {
                    lum[\testVoices].removeAt(num); voice = nil;
                };
                view.value_(if(voice.notNil and: { voice[\held] }) { 1 } { 0 });
            };
            [lum[\pedals],lum[\sostenuto],lum[\soft]].do { |dict,i|
                lum[\testPedalViews][i].value_(if((dict[key] ? 0) >= 0.5) { 1 } { 0 });
            };
            lum[\testContext].string_(lum[\displayName].value(c[\tuning]) ++ " | "
                ++ lum[\synthLabels][synthNames.indexOf(c[\synth])] ++ " | Reference: "
                ++ noteNames[c[\base]] ++ "4 = " ++ c[\root].round(0.001) ++ " Hz");
        };
    }.defer(0.04);
    };
};
lum[\stopScale] = {
    if(lum[\scaleTask].notNil) { lum[\scaleTask].stop; lum[\scaleTask] = nil };
    lum[\voices].copy.do { |v|
        if((v[\src] == \luminaTest) and: { v[\testType] == \scale }) {
            lum[\retireVoice].value(v);
        };
    };
    lum[\refreshTest].value;
};
lum[\stopTest] = {
    var key;
    lum[\stopScale].value;
    lum[\voices].copy.do { |v|
        if(v[\src] == \luminaTest) {
            lum[\retireVoice].value(v);
        };
    };
    key = makeKey.(\luminaTest,0);
    [lum[\pedals],lum[\sostenuto],lum[\soft]].do { |dict| dict.removeAt(key) };
    lum[\testVoices].clear; lum[\refreshTest].value;
};
lum[\playScale] = {
    var config, count, duration, velocity;
    lum[\stopScale].value;
    if(lum[\ready] and: { lum[\live].not }) {
        config = lum[\config].deepCopy;
        count = lum[\tunings][config[\tuning]][\steps].size;
        duration = lum[\testStepTime]; velocity = lum[\testVelocity];
        lum[\scaleTask] = Routine({
            (0..count).do { |step|
                var num, voice;
                num = 60 + config[\base] + step;
                voice = lum[\spawn].value(lum[\frequency].value(num,config),
                    velocity,num,0,\luminaTest,config[\synth]);
                if(voice.notNil) { voice[\testType] = \scale };
                (duration*0.75).wait;
                lum[\keyUp].value(voice);
                (duration*0.25).wait;
            };
            lum[\scaleTask] = nil; lum[\refreshTest].value;
        }).play(SystemClock);
    } { status.("Scale playback requires DEV mode and running audio.") };
};
// Available screen area: allow space for borders and the title bar.
lum[\fitWindowBounds] = { |width, height, parent, offset=32|
    var screen, w, h, x, y, minX, minY, maxX, maxY;
    screen = Window.availableBounds;
    minX = screen.left + 12; minY = screen.top + 12;
    w = width.min((screen.width-24).max(1));
    h = height.min((screen.height-60).max(1));
    maxX = (screen.left+screen.width-w-12).max(minX);
    maxY = (screen.top+screen.height-h-48).max(minY);
    if(parent.notNil) {
        x = parent.left+offset; y = parent.top+parent.height-h-offset;
    } {
        x = screen.left+((screen.width-w)/2);
        y = screen.top+((screen.height-h)/2);
    };
    Rect(x.clip(minX,maxX),y.clip(minY,maxY),w,h)
};
lum[\childBounds] = { |width, height, offset=32|
    var parent;
    parent = if(lum[\window].notNil) { lum[\window].bounds } { nil };
    lum[\fitWindowBounds].value(width,height,parent,offset)
};
// Respond to window resizing while preserving all control actions.
lum[\installResponsive] = { |scroll, body, designWidth, designHeight, kind|
    var entries, arrange, busy;
    busy = false;
    entries = body.children.collect { |view|
        [view,view.bounds.copy,if(view.respondsTo(\font)) { view.font } { nil }]
    };
    arrange = {
        var width, height, sx, sy, narrow, circleWidth, circleHeight, tableTop, footer, scale, viewport;
        // Qt may deliver a queued resize event after a child window has closed.
        viewport = scroll.bounds;
        if(busy.not and: { viewport.notNil } and: { body.isClosed.not }) {
            busy = true;
            // Scrollbar allowance prevents layout oscillation at the breakpoint.
            width = (viewport.width-20).max(1);
            height = (viewport.height-20).max(1);
            narrow = (kind == \tuning) and: { width < 940 };
            if(narrow) {
                width = width.max(540);
                circleWidth = (width-40).min(600); circleHeight = circleWidth*470/510;
                tableTop = 135+circleHeight+55; footer = tableTop+480;
                height = height.max(footer+365);
            } {
                width = width.max(if(kind == \main) { 780 } {
                    if(kind == \test) { 800 } { 940 }
                });
                height = height.max(designHeight*0.92);
            };
            sx = width/designWidth; sy = height/designHeight;
            body.bounds_(Rect(0,0,width,height));
            entries.do { |entry|
                var view, r, rect, font;
                view = entry[0]; r = entry[1]; font = entry[2];
                rect = Rect(r.left*sx,r.top*sy,r.width*sx,r.height*sy);
                scale = sx.min(sy).clip(0.88,1.35);
                if(narrow) {
                    scale = 1;
                    case
                    { r.top == 15 } { rect = Rect(20,15,width-40,30) }
                    { r.top == 18 } { rect = Rect(20,55,175,28) }
                    { r.top == 58 } { rect = Rect(r.left,94,r.width,r.height) }
                    { (r.left == 10) and: { r.top == 100 } } {
                        rect = Rect((width-circleWidth)/2,135,circleWidth,circleHeight);
                    }
                    { (r.left >= 535) and: { r.top <= 559 } } {
                        var tx;
                        tx = (width-40)/445;
                        rect = Rect(20+((r.left-535)*tx),
                            if(r.top == 65) { tableTop-35 } { tableTop+r.top-100 },
                            r.width*tx,r.height);
                    }
                    { r.top == 582 } { rect = Rect(20,footer,width-40,70) }
                    { r.top == 653 and: { r.left < 535 } } {
                        rect = Rect(r.left,footer+82,r.width,r.height);
                    }
                    { r.top == 653 } { rect = Rect(20,footer+120,width-40,28) }
                    { r.top == 700 } { rect = Rect(20,footer+250,width-40,32) }
                    { r.top == 701 and: { r.left == 20 } } { rect = Rect(20,footer+165,55,26) }
                    { r.top == 701 and: { r.left == 80 } } { rect = Rect(80,footer+165,width-100,26) }
                    { r.top == 701 and: { r.left == 370 } } { rect = Rect(20,footer+205,80,26) }
                    { r.top == 701 } { rect = Rect(115,footer+205,width-135,26) }
                    { r.top == 742 } { rect = Rect(20,footer+295,width-40,60) };
                };
                view.bounds_(rect);
                if(font.notNil) {
                    view.font_(Font(font.name,(font.size*scale).max(9)));
                };
            };
            body.refresh;
            busy = false;
        };
    };
    scroll.onResize_({ arrange.value });
    arrange.value;
};

lum[\openTest] = {
    var scroll, body;
    var win, label, button, whiteIndex, keyWidth, addKey;
    if(lum[\live]) { status.("The test window is only available in DEV mode.") } {
    if(lum[\testWindow].notNil) {
        win = lum[\testWindow];
        win.bounds_(lum[\childBounds].value(win.bounds.width,win.bounds.height,48));
        win.front;
    } {
        win = Window("Lumina — Sound and scale testing",lum[\childBounds].value(900,410,48)).front;
        scroll = ScrollView(win,win.view.bounds).resize_(5).hasBorder_(false);
        body = CompositeView(scroll,Rect(0,0,900,410));
        lum[\testWindow] = win; lum[\testKeys].clear;
        label = { |text,x,y,width=850| StaticText(body,Rect(x,y,width,24)).string_(text) };
        button = { |text,x,y,width,action|
            Button(body,Rect(x,y,width,28)).states_([[text]]).action_(action)
        };
        lum[\testContext] = label.("",20,12);
        button.("Test tone",20,48,160,{
            var voice;
            voice = lum[\spawn].value(lum[\config][\root],lum[\testVelocity],-1,0,\luminaTest);
            if(voice.notNil) {
                voice[\testType] = \tone;
                AppClock.sched(0.7,{
                    if(lum[\voices].includes(voice)) { lum[\release].value(voice) }; nil
                });
            } { status.("Test tone unavailable. Check audio and frequency.") };
        });
        button.("Play full scale",195,48,160,{ lum[\playScale].value });
        button.("Stop scale",370,48,160,{ lum[\stopScale].value });
        button.("Stop all test notes",545,48,160,{ lum[\stopTest].value });
        label.("Velocity (1–127)",20,88,150);
        NumberBox(body,Rect(175,88,65,24)).value_(lum[\testVelocity])
            .clipLo_(1).clipHi_(127).decimals_(0).action_({ |v|
                lum[\testVelocity] = v.value.round.asInteger.clip(1,127);
                v.value_(lum[\testVelocity]);
            });
        label.("Seconds / step",275,88,160);
        NumberBox(body,Rect(440,88,75,24)).value_(lum[\testStepTime])
            .clipLo_(0.1).clipHi_(2).decimals_(2).action_({ |v|
                lum[\testStepTime] = v.value.clip(0.1,2); v.value_(lum[\testStepTime]);
            });
        keyWidth = 23; whiteIndex = 0;
        addKey = { |num, x, black|
            var view, text, keyLabel, foreground, background, width, height, releaseKey;
            text = noteNames[num%12] ++ ((num.div(12))-1).asString;
            keyLabel = if(black) { "#" } { text };
            foreground = if(black) { Color.white } { Color.black };
            background = if(black) { Color.black } { Color.white };
            width = if(black) { 16 } { keyWidth-1 };
            height = if(black) { 85 } { 135 };
            releaseKey = { |v|
                lum[\releaseHeldKey].value(num,0,\luminaTest,\keyboard);
                lum[\testVoices].removeAt(num);
                v.value_(0);
                lum[\refreshTest].value;
                nil // Allow Qt to complete normal mouse-event processing.
            };
            view = Button(body,Rect(x,135,width,height)).font_(Font("Sans",9))
                .toolTip_(text)
                .states_([[keyLabel,foreground,background],[keyLabel,Color.black,Color.yellow]])
                .mouseDownAction_({ |v, x, y, modifiers, mouseButton|
                    var voice;
                    if(mouseButton == 0) {
                        // Recover if an earlier mouse-up did not reach this key.
                        releaseKey.value(v);
                        voice = lum[\spawn].value(lum[\frequency].value(num,lum[\config]),
                            lum[\testVelocity],num,0,\luminaTest);
                        if(voice.notNil) {
                            voice[\testType] = \keyboard;
                            lum[\testVoices][num] = voice;
                            v.value_(1);
                        } { v.value_(0); status.("Note unavailable. Check audio and frequency.") };
                        lum[\refreshTest].value;
                    };
                    nil // Default processing keeps mouse capture until the button is released.
                })
                .mouseUpAction_({ |v, x, y, modifiers, mouseButton|
                    if(mouseButton == 0) { releaseKey.value(v) };
                    nil
                })
                // For a normal click, Button.action follows mouseUpAction.
                // Repeated release is harmless and resets the visual state.
                .action_(releaseKey)
                .focusLostAction_(releaseKey);
            lum[\testKeys][num] = view;
        };
        (36..96).do { |num|
            if([0,2,4,5,7,9,11].includes(num%12)) {
                addKey.(num,20+(whiteIndex*keyWidth),false); whiteIndex = whiteIndex+1;
            };
        };
        whiteIndex = 0;
        (36..96).do { |num|
            if([0,2,4,5,7,9,11].includes(num%12)) { whiteIndex = whiteIndex+1 } {
                addKey.(num,20+(whiteIndex*keyWidth)-8,true);
            };
        };
        lum[\testPedalViews] = ["Sustain", "Sostenuto", "Soft"].collect { |name,i|
            Button(body,Rect(20+(i*220),288,205,30))
                .states_([[name ++ " off"],[name ++ " on",Color.black,Color.yellow]])
                .action_({ |v| lum[\pedal].value([64,66,67][i],v.value*127,0,\luminaTest) });
        };
        label.("Hold the mouse button to play; release to end the note. Test pedals apply only here.",20,330);
        label.("Scale: one period plus its endpoint. Settings are captured when playback starts.",20,355);
        label.("Noise Pad: pitch controls the filter; noise has no single fundamental frequency.",20,380);
        lum[\installResponsive].value(scroll,body,900,410,\test);
        win.endFrontAction_({ if(lum[\alive]) { lum[\stopTest].value } });
        win.onClose_({ lum[\testWindow] = nil; lum[\stopTest].value; lum[\testKeys].clear });
        lum[\refreshTest].value;
    };
    };
};

// The tuning circle and table use the same frequency function as MIDI.
lum[\refreshTuning] = {
    if(lum[\tuningRefreshPending].not) {
        lum[\tuningRefreshPending] = true;
    {
        lum[\tuningRefreshPending] = false;
        if(lum[\alive] and: { lum[\tuningWindow].notNil }) {
            lum[\tuningRefresh].value;
        };
    }.defer(0.04);
    };
};
lum[\openTuning] = {
    var scroll, body;
    var win, title, description, circle, units, base, hz, rows, refresh;
    var draft, draftFactor, draftBase, draftName, loaded, dirty, loadDraft, editValue, removeTone;
    var nameField, categoryMenu, message, tell, parseNumber, validDraft, testShortcut;
    var toneTable, tableBody, addButton, addTone, layoutRows;
    var selected, data, count, period, mode, fg, muted, panel, accent, label, intervalText;
    if(lum[\tuningWindow].notNil) {
        win = lum[\tuningWindow];
        win.bounds_(lum[\childBounds].value(win.bounds.width,win.bounds.height));
        win.front;
    } {
        fg = Color.gray(0.92); muted = Color.gray(0.67);
        panel = Color.gray(0.17); accent = Color(0.4,0.78,0.9);
        dirty = false; loaded = nil;
        selected = 0; mode = 0; data = []; count = 0; period = 1200;
        win = Window("Lumina — Tuning editor",lum[\childBounds].value(990,790)).front;
        scroll = ScrollView(win,win.view.bounds).resize_(5).hasBorder_(false);
        body = CompositeView(scroll,Rect(0,0,990,790));
        win.view.background_(Color.gray(0.1));
        body.background_(Color.gray(0.1));
        lum[\tuningWindow] = win;
        label = { |text,x,y,width=430,height=24|
            StaticText(body,Rect(x,y,width,height)).string_(text).stringColor_(fg)
        };
        title = label.("",20,15,700,30).font_(Font("Sans",20));
        label.("Values",20,58,60);
        units = PopUpMenu(body,Rect(85,58,190,26)).items_(["Cents", "Ratio"])
            .action_({ |v| mode = v.value; refresh.value });
        testShortcut = Button(body,Rect(755,18,175,28)).states_([["Open test window"]])
            .action_({ lum[\openTest].value });
        tell = { |text| message.string_(text); status.(text) };
        parseNumber = { |text, allowFraction=false|
            var parts, result, valid;
            parts = text.stripWhiteSpace.replace(",",".").replace(":","/").split($/);
            result = nil;
            valid = (parts.size == 1) or: { allowFraction and: { parts.size == 2 } };
            valid = valid and: { parts.every { |part|
                "^[+-]?[0-9]+([.][0-9]+)?$".matchRegexp(part.stripWhiteSpace)
            } };
            if(valid) {
                result = parts[0].stripWhiteSpace.asFloat;
                if(parts.size == 2) {
                    if(parts[1].stripWhiteSpace.asFloat == 0) { result = nil } {
                        result = result / parts[1].stripWhiteSpace.asFloat;
                    };
                };
            };
            result
        };
        validDraft = { |values, factor|
            values.notEmpty and: { values.every { |f| lum[\validPositive].value(f,0.001) } }
                and: { lum[\validPositive].value(factor) }
                and: { lum[\validPositive].value(values.first*factor,0.001) }
                and: { values.every { |f| lum[\validPositive].value(f/values.first) } }
        };
        loadDraft = {
            var c, tuning, category;
            c = lum[\config]; loaded = c.deepCopy;
            tuning = lum[\tunings][c[\tuning]];
            draft = Array.fill(tuning[\steps].size,{ |i|
                lum[\frequency].value(60+c[\base]+i,c)
            });
            draftFactor = tuning[\factor]; draftBase = c[\base]; draftName = lum[\displayName].value(c[\tuning]);
            category = lum[\categories].detect { |cat| lum[\tuningGroups][cat].includes(c[\tuning]) };
            categoryMenu.value_(lum[\categories].indexOf(category));
            nameField.string_(draftName ++ " Copy");
            dirty = false; selected = 0;
        };
        editValue = { |index, value, kind|
            var values, factor, frequency;
            values = draft.copy; factor = draftFactor; frequency = nil;
            if(value.isNumber) {
                frequency = case
                    { kind == \hz } { value }
                    { kind == \cents } { values.first * (2 ** (value/1200)) }
                    { values.first * value };
            };
            if(frequency.notNil) {
                if(index == values.size) { factor = frequency/values.first } {
                    values[index] = frequency;
                };
            };
            if(frequency.notNil and: { validDraft.value(values,factor) }) {
                draft = values; draftFactor = factor; selected = index; dirty = true;
                tell.("Draft changed. Click 'Save as new tuning' to save and activate it.");
            } { tell.("Invalid value. Hz must be positive; enter a ratio such as 3/2 or 1.5.") };
            refresh.value;
        };
        removeTone = { |index|
            var values;
            if(draft.size > 1 and: { index < draft.size }) {
                values = draft.copy; values.removeAt(index);
                if(validDraft.value(values,draftFactor)) {
                    draft = values; dirty = true; selected = index.clip(0,draft.size-1);
                    tell.("Note removed. Following notes shift by one MIDI key; the cycle has fewer steps.");
                } { tell.("Removing this note would produce invalid ratios.") };
            } { tell.("At least one note must remain. The endpoint defines the cycle.") };
            refresh.value;
        };
        addTone = {
            var frequency, endpoint, values;
            if(draft.size < 64) {
                endpoint = draft.first*draftFactor;
                // Halfway between the last note and the cycle endpoint in logarithmic pitch.
                frequency = (draft.last*endpoint).sqrt;
                if((frequency-draft.last).abs < 0.000001) {
                    frequency = draft.last * (2 ** (50/1200));
                };
                values = draft.copy.add(frequency);
                if(validDraft.value(values,draftFactor)) {
                    draft = values; selected = draft.size-1; dirty = true;
                    tell.("New note added. Enter Hz or an interval and press Enter to confirm.");
                    refresh.value;
                    toneTable.visibleOrigin_(0@((selected*23)-150).max(0));
                } { tell.("No note added: frequency is outside the allowed range.") };
            } { tell.("A tuning can contain up to 64 notes.") };
        };
        intervalText = { |entry|
            if(mode == 0) { entry[\cents].round(0.01).asString ++ " ct" } {
                entry[\ratio].round(0.000001).asString ++ " : 1"
            }
        };
        circle = UserView(body,Rect(10,100,510,470)).background_(panel);
        circle.drawFunc_({
            var center, radius, angle, point, labelPoint, fraction, entry, text, drawScale;
            drawScale = (circle.bounds.width/510).min(circle.bounds.height/470);
            Pen.translate((circle.bounds.width-(510*drawScale))/2,
                (circle.bounds.height-(470*drawScale))/2);
            Pen.scale(drawScale,drawScale);
            center = 255@235; radius = 173;
            Pen.fillColor = Color.gray(0.24);
            Pen.fillOval(Rect(82,62,346,346));
            Pen.strokeColor = muted; Pen.width = 1;
            Pen.strokeOval(Rect(82,62,346,346));
            count.do { |i|
                entry = data[i];
                // Factor 1 has no cents period: display the step sequence instead.
                fraction = if(period.abs > 0.000001) {
                    (entry[\cents] / period).mod(1)
                } { i/count };
                angle = (fraction * 2pi) - (pi/2);
                point = center + ((angle.cos*radius)@(angle.sin*radius));
                Pen.strokeColor = if((i == selected) or: { (selected == count) and: { i == 0 } }) {
                    accent
                } { Color.gray(0.48) };
                Pen.width = if(i == selected) { 2 } { 1 };
                Pen.moveTo(center); Pen.lineTo(point); Pen.stroke;
                Pen.fillColor = if(i == selected) { accent } { fg };
                Pen.fillOval(Rect(point.x-4,point.y-4,8,8));
                labelPoint = center + ((angle.cos*(radius+34))@(angle.sin*(radius+34)));
                text = intervalText.value(entry);
                if((count <= 24) or: { i == selected } or: { (i % (count/12).ceil.asInteger) == 0 }) {
                    Pen.stringCenteredIn(text,Rect(labelPoint.x-48,labelPoint.y-10,96,20),Font("Sans",10),fg);
                };
            };
            if(data.notEmpty) {
                Pen.fillColor = panel; Pen.fillOval(Rect(199,179,112,112));
                Pen.stringCenteredIn("#" ++ selected ++ "\n" ++ intervalText.value(data[selected]),
                    Rect(195,207,120,55),Font("Sans",12),accent);
            };
        });
        label.("Step",535,65,65); label.("Key / MIDI",599,65,94);
        label.("Interval",696,65,105); label.("Hz",805,65,92);
        label.("Del.",904,65,40);
        toneTable = ScrollView(body,Rect(535,100,435,440)).hasBorder_(false);
        tableBody = CompositeView(toneTable,Rect(0,0,410,460));
        rows = Array.fill(65,{ |i|
            var y, button, key, interval, frequency, remove;
            y = i*23;
            button = Button(tableBody,Rect(0,y,60,22)).states_([["#" ++ i]])
                .action_({ selected = i; refresh.value });
            key = StaticText(tableBody,Rect(64,y,94,22)).stringColor_(fg);
            interval = TextField(tableBody,Rect(161,y,105,22)).action_({ |v|
                editValue.value(i,parseNumber.value(v.string,mode == 1),
                    if(mode == 0) { \cents } { \ratio });
            });
            frequency = NumberBox(tableBody,Rect(270,y,92,22)).decimals_(3)
                .action_({ |v| editValue.value(i,v.value,\hz) });
            remove = Button(tableBody,Rect(369,y,28,22)).states_([["−"]])
                .action_({ removeTone.value(i) });
            [button,key,interval,frequency,remove]
        });
        layoutRows = {
            var width, scale, positions, widths;
            width = (toneTable.bounds.width-20).max(410); scale = width/410;
            tableBody.bounds_(Rect(0,0,width,(count+1)*23));
            positions = [0,64,161,270,369]; widths = [60,94,105,92,28];
            rows.do { |row,i|
                row.do { |view,j|
                    view.bounds_(Rect(positions[j]*scale,i*23,widths[j]*scale,22));
                };
            };
        };
        toneTable.onResize_({ layoutRows.value });
        addButton = Button(body,Rect(535,548,435,28)).states_([["+ Add note"]])
            .action_({ addTone.value });
        description = label.("",20,582,950,55).background_(panel);
        label.("Reference key",20,653,90);
        base = PopUpMenu(body,Rect(115,653,100,26)).items_(noteNames.collect { |n| n ++ "4" })
            .action_({ |v|
                var tuning, values, delta;
                tuning = (steps: draft.collect { |f| f/draft.first }, factor: draftFactor);
                delta = v.value - draftBase;
                values = Array.fill(draft.size,{ |i|
                    draft.first * lum[\ratioAt].value(delta+i,tuning)
                });
                if(validDraft.value(values,draftFactor)) {
                    draft = values; draftBase = v.value; dirty = true;
                    tell.("Reference key updated; the pitch of every MIDI key is preserved.");
                } { tell.("This reference key would produce values outside the allowed range.") };
                refresh.value;
            });
        label.("Root Hz",240,653,90);
        hz = NumberBox(body,Rect(330,653,130,26)).decimals_(3)
            .action_({ |v| editValue.value(0,v.value,\hz) });
        Button(body,Rect(535,653,435,28)).states_([["Discard draft / reload current tuning"]])
            .action_({ loadDraft.value; refresh.value; tell.("Current tuning reloaded as a draft.") });
        label.("Name",20,701,55);
        nameField = TextField(body,Rect(80,701,275,26)).action_({ dirty = true });
        label.("Category",370,701,80);
        categoryMenu = PopUpMenu(body,Rect(455,701,170,26))
            .items_(lum[\categories].collect { |name| lum[\displayName].value(name) }).action_({ dirty = true });
        Button(body,Rect(640,700,330,28)).states_([["Save as new tuning"]]).action_({
            var name, record;
            name = nameField.string.stripWhiteSpace;
            if(name.isEmpty or: { name.size > 80 }) {
                tell.("Enter a new name of 1 to 80 characters.");
            } {
                if(tuningNames.includes(name.asSymbol)) {
                    tell.("This name already exists. Please choose a new name.");
                } {
                    record = (name: name.asSymbol, category: lum[\categories][categoryMenu.value],
                        steps: draft.collect { |f| f/draft.first }, factor: draftFactor,
                        root: draft.first, base: draftBase);
                    if(lum[\saveCustomTuning].value(record)) {
                        loadDraft.value; refresh.value;
                        tell.("Saved and activated: " ++ name);
                    } { tell.("Saving failed. Your draft is still available here.") };
                };
            };
        });
        message = label.("Draft: press Enter to confirm values. Unsaved changes are lost when this window closes.",20,742,950,38);
        refresh = {
            var c, anchor, note, details;
            c = lum[\config];
            if(loaded.isNil or: { dirty.not and: {
                (loaded[\tuning] != c[\tuning]) or: { loaded[\root] != c[\root] }
                    or: { loaded[\base] != c[\base] } or: { loaded[\origin] != c[\origin] }
            } }) { loadDraft.value };
            count = draft.size; selected = selected.clip(0,count);
            period = 1200 * draftFactor.log2; anchor = 60+draftBase;
            title.string_(draftName ++ if(dirty) { " — Draft *" } { " — Original" });
            data = Array.fill(count+1,{ |i|
                var frequency, ratio;
                frequency = if(i == count) { draft.first*draftFactor } { draft[i] };
                ratio = frequency/draft.first;
                (freq: frequency, ratio: ratio, cents: 1200*ratio.log2)
            });
            rows.do { |row,i|
                row.do { |v| v.visible_(i <= count) };
                if(i <= count) {
                    note = anchor+i;
                    row[0].states_([[if(i == count) { "Cycle" } { "#" ++ i },
                        Color.black,if(i == selected) { accent } { Color.gray(0.75) }]]);
                    row[1].string_(noteNames[note%12] ++ (note.div(12)-1) ++ " / " ++ note);
                    row[2].string_(if(mode == 0) { data[i][\cents].round(0.000001).asString } {
                        data[i][\ratio].round(0.000001).asString
                    }).enabled_(i > 0);
                    row[3].value_(data[i][\freq]);
                    row[4].enabled_((i < count) and: { count > 1 });
                };
            };
            details = count.asString ++ " notes | Cycle: " ++ period.round(0.01)
                ++ " ct / Factor " ++ draftFactor.round(0.000001)
                ++ "\n#0 = reference (1/1). Hz edits affect only that note; editing #0 updates all ratios.";
            if(period.abs < 0.000001) { details = details ++ " Circle: step order." };
            description.string_(details);
            base.value_(draftBase); hz.value_(draft.first);
            addButton.enabled_(count < 64); layoutRows.value; circle.refresh;
        };
        lum[\installResponsive].value(scroll,body,990,790,\tuning);
        lum[\tuningRefresh] = refresh;
        lum[\devViews].add(testShortcut);
        lum[\updateModeUI].value;
        win.onClose_({
            lum[\devViews].remove(testShortcut);
            lum[\tuningWindow] = nil; lum[\tuningRefresh] = nil;
        });
        refresh.value;
    };
};

// GUI on AppClock; all parameter actions use the same configuration.
{
    var scroll, body;
    var win, label, button, synthMenu, tuningMenu, baseMenu, freqSlider, freqBox;
    var ampSlider, ampBox, masterSlider, masterBox, voiceBox, presetMenu, nameField, ccBox;
    var sourceMenu, channelMenu, restoreBox, modeButton, info, endpoints, refreshSources;
    var savePreset, selectedValid, categoryMenu, visibleTunings;
    var testButton, reloadButton, selfTestButton;
    if(lum[\alive]) {
        win = Window("Lumina X — Tuning and sound",lum[\fitWindowBounds].value(850,760)).front;
        scroll = ScrollView(win,win.view.bounds).resize_(5).hasBorder_(false);
        body = CompositeView(scroll,Rect(0,0,850,760));
        lum[\window] = win;
        win.onClose_({ lum[\dispose].value });
        label = { |text,x,y,width=160| StaticText(body,Rect(x,y,width,22)).string_(text) };
        button = { |text,x,y,width,action|
            Button(body,Rect(x,y,width,28)).states_([[text]]).action_(action)
        };
        label.("LUMINA 10",20,12,250).font_(Font("Helvetica",22));
        modeButton = Button(body,Rect(650,12,180,28))
            .states_([["LIVE"],["DEV"]])
            .action_({ |view| lum[\setLive].value(view.value == 0) });

        label.("Category",20,57);
        categoryMenu = PopUpMenu(body,Rect(185,57,645,24))
            .items_(lum[\categories].collect { |name| lum[\displayName].value(name) }).action_({ |view|
                var names;
                names = lum[\tuningGroups][lum[\categories][view.value]];
                if(names.includes(lum[\config][\tuning]).not) {
                    lum[\selectTuning].value(names.first);
                };
                syncGUI.value;
            });
        label.("Tuning",20,98);
        button.("+",795,96,35,{ lum[\openTuning].value }).toolTip_("Show tuning circle and intervals");
        visibleTunings = lum[\tuningGroups][\Erde];
        tuningMenu = PopUpMenu(body,Rect(185,98,600,24)).items_(visibleTunings.collect { |name| lum[\displayName].value(name) })
            .action_({ |view|
                if(lum[\config][\tuning] != visibleTunings[view.value]) {
                    lum[\selectTuning].value(visibleTunings[view.value]);
                };
                syncGUI.value;
            });

        label.("Instrument",20,138);
        synthMenu = PopUpMenu(body,Rect(185,138,645,24)).items_(lum[\synthLabels])
            .action_({ |view| lum[\config][\synth] = synthNames[view.value]; syncGUI.value });

        label.("Reference note (oct. 4)",20,178);
        baseMenu = PopUpMenu(body,Rect(185,178,100,24)).items_(noteNames)
            .action_({ |view| lum[\changeBase].value(view.value); syncGUI.value });
        label.("Reference frequency / Hz",320,178,160);
        freqSlider = Slider(body,Rect(485,178,230,24)).action_({ |view|
            lum[\config][\root] = view.value.linlin(0,1,lum[\freqRange][0],lum[\freqRange][1]);
            syncGUI.value;
        });
        freqBox = NumberBox(body,Rect(730,178,100,24)).clipLo_(0.001).clipHi_(100000000).decimals_(3)
            .action_({ |view|
                lum[\config][\root] = view.value.clip(0.001,100000000); syncGUI.value;
            });

        label.("Instrument volume",20,219);
        ampSlider = Slider(body,Rect(185,219,145,24)).action_({ |view|
            lum[\config][\amps][lum[\config][\synth]] = view.value;
            lum[\applyLevels].value; syncGUI.value;
        });
        ampBox = NumberBox(body,Rect(340,219,80,24)).clipLo_(0).clipHi_(1).decimals_(2)
            .action_({ |view|
                lum[\config][\amps][lum[\config][\synth]] = view.value.clip(0,1);
                lum[\applyLevels].value; syncGUI.value;
            });
        label.("Master",440,219,95);
        masterSlider = Slider(body,Rect(535,219,180,24)).action_({ |view|
            lum[\config][\master] = view.value; lum[\applyLevels].value(false); lum[\refreshMaster].value;
        });
        masterBox = NumberBox(body,Rect(730,219,100,24)).clipLo_(0).clipHi_(1).decimals_(2)
            .action_({ |view| lum[\config][\master] = view.value.clip(0,1); lum[\applyLevels].value(false); lum[\refreshMaster].value });
        label.("Maximum voices",20,260);
        voiceBox = NumberBox(body,Rect(185,260,100,24)).clipLo_(8).clipHi_(128).decimals_(0)
            .action_({ |view|
                lum[\config][\maxVoices] = view.value.asInteger.clip(8,128);
                lum[\trimVoices].value; syncGUI.value;
            });
        testButton = button.("Open test window",320,258,160,{ lum[\openTest].value });
        button.("PANIC / all notes off",495,258,205,{
            lum[\panic].value; lum[\expression] = 1; lum[\applyLevels].value;
            status.("All Lumina voices stopped.");
        });
        button.("Level meter",715,258,115,{ server.meter });

        label.("PRESETS",20,305,140);
        presetMenu = PopUpMenu(body,Rect(185,302,645,25)).action_({ |view|
            if(view.value > 0) { lum[\applyPreset].value(view.value-1) } {
                lum[\selected] = -1; nameField.string_("New preset");
            };
        });
        label.("Name",20,341);
        nameField = TextField(body,Rect(185,341,355,25)).string_("New preset");
        lum[\nameField] = nameField;
        label.("Trigger CC (-1 = off)",555,341,175);
        ccBox = NumberBox(body,Rect(740,341,90,25)).clipLo_(-1).clipHi_(119).decimals_(0)
            .action_({ |view|
                var cc;
                cc = view.value.asInteger.clip(-1,119);
                if([7,11,64,66,67].includes(cc)) { cc = -1; status.("CC7, 11, 64, 66 and 67 are reserved.") };
                lum[\config][\cc] = cc; view.value_(cc);
            });
        selectedValid = { lum[\selected] >= 0 and: { lum[\selected] < lum[\presets].size } };
        savePreset = { |overwrite=false|
            var name, conflict, index, p;
            name = nameField.string.stripWhiteSpace;
            index = if(overwrite) { lum[\selected] } { -1 };
            conflict = lum[\presets].detectIndex { |item, i|
                (i != index) and: { (item[\name] == name) or: {
                    (lum[\config][\cc] >= 0) and: { item[\settings][\cc] == lum[\config][\cc] }
                } }
            };
            if(name.isEmpty) { status.("Please enter a preset name.") } {
                if(overwrite and: { selectedValid.value.not }) { status.("No preset selected.") } {
                    if(conflict.notNil) { status.("Name or trigger CC already in use. Choose another value.") } {
                        p = (name: name, settings: lum[\snapshot].value);
                        if(overwrite) { lum[\presets][index] = p } {
                            lum[\presets].add(p); lum[\selected] = lum[\presets].size-1;
                        };
                        if(lum[\save].value) { status.("Preset saved: " ++ name) };
                        syncGUI.value;
                    };
                };
            };
        };
        button.("Save new",20,381,185,{ savePreset.(false) });
        button.("Overwrite",220,381,185,{ savePreset.(true) });
        button.("Delete",420,381,185,{
            if(selectedValid.value) {
                lum[\presets].removeAt(lum[\selected]); lum[\selected] = -1;
                lum[\config][\cc] = -1; nameField.string_("New preset");
                if(lum[\save].value) { status.("Preset deleted; current sound settings are unchanged.") };
                syncGUI.value;
            } { status.("No preset selected.") };
        });
        button.("Save settings",620,381,210,{
            if(lum[\save].value) { status.("Settings saved.") };
        });
        restoreBox = CheckBox(body,Rect(20,422,280,24)).string_("Restore last settings at startup")
            .value_(lum[\restore]).action_({ |view| lum[\restore] = view.value });
        CheckBox(body,Rect(325,422,170,24)).string_("Always on top")
            .action_({ |view| win.alwaysOnTop_(view.value) });
        lum[\debugView] = CheckBox(body,Rect(555,422,275,24)).string_("Log MIDI notes and CC")
            .action_({ |view| lum[\debug] = view.value and: { lum[\live].not } });

        label.("MIDI input",20,467);
        sourceMenu = PopUpMenu(body,Rect(185,467,300,24));
        refreshSources = {
            endpoints = MIDIClient.sources ? [];
            sourceMenu.items_(["All inputs"] ++ endpoints.collect { |ep| ep.device ++ " / " ++ ep.name });
            sourceMenu.value_(0); lum[\source] = nil;
        };
        sourceMenu.action_({ |view|
            lum[\panic].value;
            lum[\source] = if(view.value == 0) { nil } { endpoints[view.value-1].uid };
        });
        label.("Channel",500,467,55);
        channelMenu = PopUpMenu(body,Rect(555,467,95,24)).items_(["All"] ++ (1..16).collect(_.asString))
            .action_({ |view| lum[\panic].value; lum[\channel] = view.value-1 });
        button.("Connect MIDI",665,465,165,{
            lum[\panic].value; lum[\initMIDI].value; refreshSources.value;
        });
        refreshSources.value;

        lum[\audioButton] = button.("Start / rebuild audio",20,513,270,{ lum[\startAudio].value });
        reloadButton = button.("Reload SynthDefs",305,513,200,{
            if(lum[\live].not and: { lum[\ready] } and: { server.serverRunning }) {
                if(lum[\reloadTask].notNil) { lum[\reloadTask].stop };
                lum[\reloadTask] = Routine({
                    lum[\defineSynths].value; server.sync;
                    if(lum[\alive]) { status.("SynthDefs loaded; new notes use the updated definitions.") };
                }).play(SystemClock);
            } { status.("Start audio first.") };
        });
        selfTestButton = button.("Self-test",520,513,140,{ lum[\selfTest].value });
        button.("Defaults",675,513,155,{
            lum[\config] = defaults.value; lum[\selected] = -1;
            nameField.string_("New preset"); lum[\expression] = 1;
            lum[\applyLevels].value; lum[\trimVoices].value; syncGUI.value;
        });
        info = TextView(body,Rect(20,560,810,130)).editable_(false);
        lum[\statusView] = StaticText(body,Rect(20,700,810,40)).string_(lum[\message]);
        lum[\syncMaster] = {
            masterSlider.value_(lum[\config][\master]); masterBox.value_(lum[\config][\master]);
        };
        lum[\sync] = {
            var c, t, lines, category;
            c = lum[\config]; t = lum[\tunings][c[\tuning]];
            synthMenu.value_(synthNames.indexOf(c[\synth]));
            category = lum[\categories].detect { |cat| lum[\tuningGroups][cat].includes(c[\tuning]) };
            categoryMenu.value_(lum[\categories].indexOf(category));
            visibleTunings = lum[\tuningGroups][category];
            tuningMenu.items_(visibleTunings.collect { |name| lum[\displayName].value(name) });
            tuningMenu.value_(visibleTunings.indexOf(c[\tuning]));
            baseMenu.value_(c[\base]);
            lum[\updateFreqRange].value;
            freqSlider.value_(c[\root].linlin(lum[\freqRange][0],lum[\freqRange][1],0,1));
            freqBox.value_(c[\root]);
            ampSlider.value_(c[\amps][c[\synth]]); ampBox.value_(c[\amps][c[\synth]]);
            masterSlider.value_(c[\master]); masterBox.value_(c[\master]);
            voiceBox.value_(c[\maxVoices]); ccBox.value_(c[\cc]);
            presetMenu.items_(["— no preset selected —"] ++ lum[\presets].collect { |p| p[\name] });
            presetMenu.value_(lum[\selected]+1);
            lines = lum[\displayName].value(c[\tuning]) ++ " | " ++ t[\steps].size ++ " steps | Factor " ++ t[\factor].round(0.00001)
                ++ "\nReference: " ++ noteNames[c[\base]] ++ "4 (MIDI " ++ (60+c[\base]) ++ ") = " ++ c[\root].round(0.01) ++ " Hz\n";
            t[\steps].do { |ratio,i|
                lines = lines ++ i ++ ": " ++ lum[\frequency].value(60+c[\base]+i).round(0.01) ++ " Hz   ";
            };
            info.string_(lines);
            lum[\refreshTuning].value;
            lum[\refreshTest].value;
            lum[\updateModeUI].value;
        };
        lum[\devViews].addAll([testButton,reloadButton,selfTestButton,lum[\debugView]]);
        lum[\installResponsive].value(scroll,body,850,760,\main);
        lum[\sync].value;
    };
}.defer;
lum[\initMIDI].value;
lum[\startAudio].value;
)
