// ペンギンすべりだいの効果音とBGM（開発用サウンドラボと書き出しで共通）。
// 各音は OfflineAudioContext で合成する。ラボの試聴も、アプリ用のWAV書き出し（ci/render-sounds.cjs）も
// 同じ render() を通るので、ラボで聞いた音がそのままアプリに入る。
//
// 方針（幼児向けの効果音の定石）：
// - 成功・行動の音は上がる音程、長調、明るく丸い音色（サイン・三角波・ベル）。
// - 低いブザー音（のこぎり波・矩形波の低音）と下がる音程は「まちがい」に聞こえるので、
//   まちがい以外では使わない。まちがいの音もやさしく短く。
// - ふしぎ音（たまに鳴る面白い音）も上がる・弾む音だけにする。
(function () {
  const SR = 44100;

  // 名前ごとに同じ乱数列（書き出しを再現可能にする）。
  function rng(name) {
    let h = 2166136261;
    for (const c of name) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
    return function () {
      h += 0x6d2b79f5;
      let t = h;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // 値の折れ線 [[時刻, 値], ...] を AudioParam に設定する。exp=true は指数的に変化（周波数向き）。
  function curve(param, points, t0, exp) {
    if (typeof points === "number") {
      param.setValueAtTime(points, t0);
      return;
    }
    param.setValueAtTime(points[0][1], t0 + points[0][0]);
    for (const [t, v] of points.slice(1)) {
      if (exp) param.exponentialRampToValueAtTime(Math.max(v, 0.0001), t0 + t);
      else param.linearRampToValueAtTime(v, t0 + t);
    }
  }

  function waves(ctx) {
    // ベル・オルゴール：倍音を少し足したサイン。
    const bell = ctx.createPeriodicWave(new Float32Array([0, 0, 0, 0, 0]), new Float32Array([0, 1, 0.12, 0.28, 0.06]));
    // 木琴・マリンバ風：基音と4倍音。
    const wood = ctx.createPeriodicWave(new Float32Array([0, 0, 0, 0, 0]), new Float32Array([0, 1, 0, 0, 0.18]));
    return { bell, wood };
  }

  // 音程・音量の変化つきの音。
  function tone(ctx, out, o) {
    const start = o.at || 0;
    const osc = ctx.createOscillator();
    if (o.wave) osc.setPeriodicWave(o.wave);
    else osc.type = o.type || "sine";
    curve(osc.frequency, o.freq, start, o.linear !== true);
    if (o.vibrato) {
      const lfo = ctx.createOscillator();
      const depth = ctx.createGain();
      lfo.frequency.value = o.vibrato.rate;
      curve(depth.gain, o.vibrato.depth, start, false);
      lfo.connect(depth).connect(osc.frequency);
      lfo.start(start);
      lfo.stop(start + o.dur);
    }
    const gain = ctx.createGain();
    curve(gain.gain, o.gain, start, false);
    let node = osc.connect(gain);
    if (o.lowpass) {
      const filter = ctx.createBiquadFilter();
      filter.type = "lowpass";
      curve(filter.frequency, o.lowpass, start, true);
      node = node.connect(filter);
    }
    node.connect(out);
    osc.start(start);
    osc.stop(start + o.dur);
  }

  // フィルターを通した雑音（しぶき・こすれる音）。
  function noise(ctx, out, random, o) {
    const start = o.at || 0;
    const length = Math.ceil(o.dur * SR);
    const buffer = ctx.createBuffer(1, length, SR);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i++) data[i] = random() * 2 - 1;
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = o.filter || "lowpass";
    filter.Q.value = o.q || 0.7;
    curve(filter.frequency, o.cutoff, start, true);
    const gain = ctx.createGain();
    curve(gain.gain, o.gain, start, false);
    source.connect(filter).connect(gain).connect(out);
    source.start(start);
  }

  // 減衰する打楽器的な音（ベル・木琴）。
  // decay は音量が 1/e になるまでの秒数。
  function strike(ctx, out, wave, f, at, o = {}) {
    const decay = o.decay || 0.5;
    const osc = ctx.createOscillator();
    osc.setPeriodicWave(wave);
    osc.frequency.value = f;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0, at);
    gain.gain.linearRampToValueAtTime(o.level || 0.5, at + 0.004);
    gain.gain.setTargetAtTime(0, at + 0.004, decay);
    osc.connect(gain).connect(out);
    osc.start(at);
    osc.stop(at + 0.004 + decay * 6);
  }

  const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);

  // 各音：dur 秒、level は書き出し時の最大振幅（ほかの音との音量バランス）。
  const SOUNDS = {
    // ── ゲームの効果音 ──
    pop: {
      label: "ぽっ（出てくる・戻る）", dur: 0.16, level: 0.7,
      make: (c, out) => tone(c, out, { freq: [[0, 520], [0.09, 1900]], dur: 0.16, gain: [[0, 0], [0.005, 0.9], [0.16, 0]] }),
    },
    pi: {
      label: "ピコッ（氷をえらぶ）", dur: 0.3, level: 0.6,
      make: (c, out, r, w) => {
        strike(c, out, w.bell, midi(88), 0, { decay: 0.06, level: 0.6 });
        strike(c, out, w.bell, midi(93), 0.07, { decay: 0.08, level: 0.6 });
      },
    },
    slide: {
      label: "しゅーっ（すべる）", dur: 1.2, level: 0.55,
      make: (c, out, r, w) => {
        // 氷をこする音：帯域を上げていく雑音。下がる音程は使わない。
        noise(c, out, r, { dur: 1.2, filter: "bandpass", q: 1.2, cutoff: [[0, 900], [1.1, 2600]], gain: [[0, 0], [0.12, 0.9], [0.9, 0.7], [1.2, 0]] });
        // きらきら：上がっていく小さなベル。
        [84, 88, 91, 96].forEach((n, i) => strike(c, out, w.bell, midi(n), 0.15 + i * 0.22, { decay: 0.07, level: 0.22 }));
      },
    },
    jump: {
      label: "ぴょーん（とぶ）", dur: 0.45, level: 0.6,
      make: (c, out) => {
        tone(c, out, { type: "triangle", freq: [[0, 620], [0.22, 1500]], dur: 0.45, vibrato: { rate: 14, depth: [[0, 40], [0.45, 0]] },
          gain: [[0, 0], [0.01, 0.9], [0.18, 0.6], [0.45, 0]] });
        tone(c, out, { freq: [[0, 1240], [0.22, 3000]], dur: 0.3, gain: [[0, 0], [0.01, 0.15], [0.3, 0]] });
      },
    },
    land: {
      label: "ぽふっ（着地）", dur: 0.3, level: 0.6,
      make: (c, out, r, w) => {
        noise(c, out, r, { dur: 0.2, cutoff: [[0, 2500], [0.2, 500]], gain: [[0, 0], [0.005, 0.8], [0.2, 0]] });
        tone(c, out, { freq: [[0, 260], [0.12, 160]], dur: 0.16, gain: [[0, 0], [0.005, 0.5], [0.16, 0]] });
        strike(c, out, w.wood, midi(84), 0.02, { decay: 0.05, level: 0.25 });
      },
    },
    splash: {
      label: "ばしゃーん（海に落ちる）", dur: 1.0, level: 0.75,
      make: (c, out, r) => {
        noise(c, out, r, { dur: 1.0, cutoff: [[0, 5000], [1.0, 700]], gain: [[0, 0], [0.01, 1], [1.0, 0]] });
        for (let i = 0; i < 8; i++) {
          const at = 0.12 + r() * 0.65;
          tone(c, out, { freq: [[0, 500 + r() * 300], [0.05, 2500 + r() * 1500]], at, dur: 0.06, gain: [[0, 0], [0.01, 0.25], [0.06, 0]] });
        }
      },
    },
    correct: {
      label: "せいかい（ドミソド）", dur: 1.1, level: 0.65,
      make: (c, out, r, w) => [84, 88, 91, 96].forEach((n, i) => strike(c, out, w.bell, midi(n), i * 0.085, { decay: 0.2, level: 0.45 })),
    },
    wrong: {
      label: "ざんねん（やさしく ぽよん）", dur: 0.8, level: 0.5,
      // 丸い音で2音だけ下がる。ブザーやトロンボーンの「ぶぶー」にはしない。
      make: (c, out, r, w) => {
        tone(c, out, { wave: w.wood, freq: [[0, midi(67)], [0.18, midi(67)]], dur: 0.2, gain: [[0, 0], [0.01, 0.6], [0.2, 0]] });
        tone(c, out, { wave: w.wood, freq: [[0, midi(64)], [0.5, midi(62)]], at: 0.22, dur: 0.55, vibrato: { rate: 6, depth: [[0, 0], [0.2, 6], [0.55, 6]] },
          gain: [[0, 0], [0.01, 0.6], [0.55, 0]] });
      },
    },
    fanfare: {
      label: "ファンファーレ（5問ごと）", dur: 1.5, level: 0.7,
      make: (c, out) => {
        const notes = [[72, 0, 0.11], [76, 0.12, 0.11], [79, 0.24, 0.11], [84, 0.36, 0.22], [79, 0.6, 0.11], [84, 0.72, 0.7]];
        for (const [n, at, len] of notes) {
          for (const detune of [1, 1.004]) {
            tone(c, out, { type: "sawtooth", freq: midi(n) * detune, at, dur: len + 0.05, lowpass: [[0, 1200], [0.05, 3200], [len, 1800]],
              gain: [[0, 0], [0.015, 0.22], [len, 0.18], [len + 0.05, 0]] });
          }
        }
      },
    },
    sparkle: {
      label: "きらきら", dur: 0.75, level: 0.45,
      make: (c, out, r, w) => {
        for (let i = 0; i < 9; i++) strike(c, out, w.bell, 2000 + r() * 2200, r() * 0.45, { decay: 0.05, level: 0.3 });
      },
    },
    munch: {
      label: "もぐもぐ（たべる）", dur: 0.85, level: 0.55,
      // かむ音：短くこもった雑音と、上がる丸い「ぽっ」を3回。
      make: (c, out, r) => [0, 0.24, 0.48].forEach((at, i) => {
        noise(c, out, r, { at, dur: 0.12, cutoff: [[0, 1400], [0.12, 400]], gain: [[0, 0], [0.01, 0.7], [0.12, 0]] });
        tone(c, out, { freq: [[0, 300 + i * 40], [0.1, 520 + i * 60]], at: at + 0.02, dur: 0.12, gain: [[0, 0], [0.01, 0.55], [0.12, 0]] });
      }),
    },
    blub: {
      label: "ぽこっ（氷が沈む）", dur: 0.35, level: 0.5,
      make: (c, out) => [0, 0.14].forEach((at) => tone(c, out, { freq: [[0, 240], [0.12, 700]], at, dur: 0.12, gain: [[0, 0], [0.02, 0.8], [0.12, 0]] })),
    },
    whale: {
      // 低く長い「ぶお〜ん」は霧笛のようでこわいので、高めで上がる2音の「ぷお〜ん♪」（おもちゃのオカリナ風）にする。
      label: "ぷお〜ん♪（クジラ）", dur: 1.1, level: 0.5,
      make: (c, out) => {
        tone(c, out, { type: "triangle", freq: [[0, 300], [0.12, 392], [0.4, 392]], dur: 0.4, lowpass: 1800, vibrato: { rate: 6, depth: 4 },
          gain: [[0, 0], [0.05, 0.7], [0.3, 0.55], [0.4, 0]] });
        tone(c, out, { type: "triangle", freq: [[0, 392], [0.15, 523], [0.7, 540]], at: 0.38, dur: 0.7, lowpass: 2000, vibrato: { rate: 5.5, depth: [[0, 0], [0.3, 7]] },
          gain: [[0, 0], [0.06, 0.8], [0.45, 0.6], [0.7, 0]] });
      },
    },
    // ── ふしぎ音（たまに鳴る面白い音）：上がる・弾む音だけ ──
    boing: {
      label: "びよよ〜ん", dur: 0.8, level: 0.6, funny: true,
      make: (c, out) => tone(c, out, { freq: [[0, 330], [0.8, 520]], dur: 0.8, vibrato: { rate: 22, depth: [[0, 150], [0.8, 10]] },
        gain: [[0, 0], [0.01, 0.8], [0.8, 0]] }),
    },
    whistle: {
      label: "ぴゅい〜っ（スライドホイッスル）", dur: 0.6, level: 0.5, funny: true,
      make: (c, out) => tone(c, out, { freq: [[0, 600], [0.55, 1900]], dur: 0.6, vibrato: { rate: 7, depth: 18 }, gain: [[0, 0], [0.04, 0.7], [0.5, 0.7], [0.6, 0]] }),
    },
    squeak: {
      label: "きゅっきゅっ（おもちゃ）", dur: 0.4, level: 0.45, funny: true,
      make: (c, out) => [0, 0.18].forEach((at) => tone(c, out, { freq: [[0, 1800], [0.06, 2700], [0.13, 2200]], at, dur: 0.13, gain: [[0, 0], [0.02, 0.7], [0.13, 0]] })),
    },
    pikopiko: {
      label: "ピコピコッ（上がる）", dur: 0.55, level: 0.45, funny: true,
      make: (c, out) => [72, 76, 79, 84].forEach((n, i) => tone(c, out, { type: "square", freq: midi(n + 12), at: i * 0.07, dur: 0.09, lowpass: 4000,
        gain: [[0, 0], [0.005, 0.25], [0.08, 0.2], [0.09, 0]] })),
    },
    bubble: {
      label: "ぽこぽこぽこ", dur: 0.6, level: 0.5, funny: true,
      make: (c, out) => [0, 0.11, 0.2, 0.28].forEach((at, i) => tone(c, out, { freq: [[0, 300 + i * 120], [0.08, 900 + i * 250]], at, dur: 0.09,
        gain: [[0, 0], [0.01, 0.8], [0.09, 0]] })),
    },
  };

  // BGM：オルゴールと木琴のゆったりしたループ（C–Am–F–G ×2、100BPM）。
  const BEAT = 0.6;
  const MELODY = [76, 79, 84, 79, 81, 79, 76, 72, 77, 81, 84, 81, 79, 74, 79, 83,
                  76, 79, 76, 72, 81, 84, 81, 76, 77, 76, 74, 72, 74, 79, 84, -1];
  const CHORDS = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62], [60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]];
  const LOOP = MELODY.length * BEAT;
  const MUSIC = {
    label: "BGM（ループ）", dur: LOOP, level: 0.6, loop: true,
    make: (c, out, r, w) => {
      MELODY.forEach((n, i) => { if (n > 0) strike(c, out, w.bell, midi(n), i * BEAT, { decay: 0.35, level: 0.32 }); });
      CHORDS.forEach((chord, bar) => {
        const at = bar * BEAT * 4;
        strike(c, out, w.wood, midi(chord[0] - 12), at, { decay: 0.45, level: 0.35 });
        strike(c, out, w.wood, midi(chord[0] - 12), at + BEAT * 2, { decay: 0.3, level: 0.22 });
        // 裏拍に小さな和音（ウクレレのような刻み）。
        for (const beat of [1, 3]) chord.forEach((n) => strike(c, out, w.wood, midi(n), at + beat * BEAT, { decay: 0.08, level: 0.07 }));
      });
    },
  };

  async function render(name) {
    const sound = name === "music" ? MUSIC : SOUNDS[name];
    // ループは余韻の分を長めに合成し、はみ出した分を頭に重ねてつなぎ目をなくす。
    const tail = sound.loop ? 3 : 0;
    const length = Math.ceil((sound.dur + tail) * SR);
    const ctx = new OfflineAudioContext(1, length, SR);
    const out = ctx.createGain();
    out.connect(ctx.destination);
    sound.make(ctx, out, rng(name), waves(ctx));
    const rendered = await ctx.startRendering();
    const data = rendered.getChannelData(0);
    const count = Math.ceil(sound.dur * SR);
    const result = new Float32Array(count);
    for (let i = 0; i < data.length; i++) result[i % count] += data[i];
    let peak = 0;
    for (const v of result) peak = Math.max(peak, Math.abs(v));
    const scale = peak > 0 ? sound.level / peak : 1;
    const fade = sound.loop ? 0 : Math.min(400, count);
    for (let i = 0; i < count; i++) {
      const edge = i >= count - fade ? (count - i) / fade : 1;
      result[i] *= scale * edge;
    }
    return result;
  }

  // 16bit・モノラルのWAV。
  function wav(samples) {
    const buffer = new ArrayBuffer(44 + samples.length * 2);
    const view = new DataView(buffer);
    const text = (at, s) => [...s].forEach((ch, i) => view.setUint8(at + i, ch.charCodeAt(0)));
    text(0, "RIFF"); view.setUint32(4, 36 + samples.length * 2, true); text(8, "WAVE");
    text(12, "fmt "); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
    view.setUint32(24, SR, true); view.setUint32(28, SR * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
    text(36, "data"); view.setUint32(40, samples.length * 2, true);
    samples.forEach((v, i) => view.setInt16(44 + i * 2, Math.max(-1, Math.min(1, v)) * 32767, true));
    return buffer;
  }

  window.SoundLab = { SR, SOUNDS, MUSIC, render, wav, names: [...Object.keys(SOUNDS), "music"] };
})();
