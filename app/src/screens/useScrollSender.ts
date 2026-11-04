import { useCallback, useEffect, useRef } from 'react';
import * as Haptics from 'expo-haptics';
import { NOTCH_PT, ScrollCoalescer, VelocityTracker, fingerToScroll, momentumSteps } from '../motion/scroll';
import type { Msg } from '../transport/types';

type Options = { natural: boolean; speed: number };

// Smooth scroll gesture -> `scroll` messages with phases (motion/scroll.ts):
// begin on finger down, fractional `move` deltas coalesced per frame, `end`
// on finger up, then after a flick phone-side `momentum` deltas closed by a
// zero-delta `momentum` (Mac contract, spec section 3).
export function useScrollSender(send: (m: Msg) => void, opts: Options) {
  const sendRef = useRef(send);
  const optsRef = useRef(opts);
  useEffect(() => {
    sendRef.current = send;
    optsRef.current = opts;
  });

  const st = useRef({
    active: false,
    frame: null as number | null,
    momentum: null as number | null,
    total: 0, // for a selection tick per whole notch
    coalescer: new ScrollCoalescer(),
    tracker: new VelocityTracker(),
  });

  const stopMomentum = useCallback(() => {
    const s = st.current;
    if (s.momentum === null) return false;
    cancelAnimationFrame(s.momentum);
    s.momentum = null;
    return true;
  }, []);

  const flushFrame = useCallback(() => {
    const s = st.current;
    s.frame = null;
    const dy = s.coalescer.take();
    if (dy !== null) sendRef.current({ t: 'scroll', dy, phase: 'move' });
  }, []);

  const begin = useCallback(() => {
    const s = st.current;
    stopMomentum(); // a finger caught the coast: the new begin ends it on the Mac
    if (s.active) sendRef.current({ t: 'scroll', dy: 0, phase: 'end' });
    s.active = true;
    s.total = 0;
    s.coalescer.drain();
    s.tracker.reset();
    sendRef.current({ t: 'scroll', dy: 0, phase: 'begin' });
  }, [stopMomentum]);

  // fingerUpPx > 0 = finger moved up the screen since the last call.
  // Haptic tick per notch scrolled (12 pt).
  const move = useCallback((fingerUpPx: number) => {
    const s = st.current;
    if (!s.active || fingerUpPx === 0) return;
    const dy = fingerToScroll(fingerUpPx, optsRef.current.natural, optsRef.current.speed);
    s.coalescer.add(dy);
    s.tracker.add(dy, Date.now());
    const before = Math.trunc(s.total / NOTCH_PT);
    s.total += dy;
    if (Math.trunc(s.total / NOTCH_PT) !== before) Haptics.selectionAsync();
    if (s.frame === null) s.frame = requestAnimationFrame(flushFrame);
  }, [flushFrame]);

  const end = useCallback(() => {
    const s = st.current;
    if (!s.active) return;
    s.active = false;
    if (s.frame !== null) cancelAnimationFrame(s.frame);
    s.frame = null;
    const rest = s.coalescer.drain();
    if (rest !== 0) sendRef.current({ t: 'scroll', dy: rest, phase: 'move' });
    sendRef.current({ t: 'scroll', dy: 0, phase: 'end' }); // finger up
    const steps = momentumSteps(s.tracker.perFrame(Date.now()));
    if (steps.length === 0) return;
    let i = 0;
    const step = () => {
      if (i >= steps.length) {
        s.momentum = null;
        sendRef.current({ t: 'scroll', dy: 0, phase: 'momentum' }); // zero momentum = fling over
        return;
      }
      sendRef.current({ t: 'scroll', dy: steps[i++], phase: 'momentum' });
      s.momentum = requestAnimationFrame(step);
    };
    s.momentum = requestAnimationFrame(step);
  }, []);

  // Leaving Remote mid-gesture or mid-coast: close the phase on the Mac.
  useEffect(() => {
    const s = st.current;
    return () => {
      if (s.frame !== null) cancelAnimationFrame(s.frame);
      const coasting = s.momentum !== null;
      if (coasting) cancelAnimationFrame(s.momentum!);
      if (s.active) sendRef.current({ t: 'scroll', dy: 0, phase: 'end' });
      else if (coasting) sendRef.current({ t: 'scroll', dy: 0, phase: 'momentum' });
    };
  }, []);

  return { begin, move, end };
}
