import type { KeyName, Msg } from '../transport/types';

// Phone keyboard -> Mac. Pure, so it runs under `node --test`.
//
// The hidden TextInput stays empty; every change is "added text". Text is
// batched for ~50 ms into one `text` message. Keys flush pending text first
// so order is kept. Backspace eats a pending character before it is sent.

export const TEXT_BATCH_MS = 50;

type Timers = {
  set: (cb: () => void, ms: number) => unknown;
  clear: (id: unknown) => void;
};

const realTimers: Timers = {
  set: (cb, ms) => setTimeout(cb, ms),
  clear: (id) => clearTimeout(id as ReturnType<typeof setTimeout>),
};

export class TextBatcher {
  private buf = '';
  private timer: unknown = null;
  private readonly out: (m: Msg) => void;
  private readonly delay: number;
  private readonly timers: Timers;

  constructor(out: (m: Msg) => void, delay = TEXT_BATCH_MS, timers: Timers = realTimers) {
    this.out = out;
    this.delay = delay;
    this.timers = timers;
  }

  // Text added in the input. Newlines become Enter key taps.
  type(added: string) {
    if (!added) return;
    const parts = added.replace(/\r\n?/g, '\n').split('\n');
    parts.forEach((part, i) => {
      if (i > 0) this.key('enter');
      if (part) {
        this.buf += part;
        if (this.timer === null) this.timer = this.timers.set(() => this.flush(), this.delay);
      }
    });
  }

  backspace() {
    if (this.buf) {
      const chars = Array.from(this.buf); // keep emoji surrogate pairs whole
      chars.pop();
      this.buf = chars.join('');
      return;
    }
    this.key('backspace');
  }

  key(k: KeyName) {
    this.flush();
    this.out({ t: 'key', k });
  }

  flush() {
    if (this.timer !== null) {
      this.timers.clear(this.timer);
      this.timer = null;
    }
    if (!this.buf) return;
    const s = this.buf;
    this.buf = '';
    this.out({ t: 'text', s });
  }
}

// What changed between two input values, assuming the caret is at the end
// (it is: the box is hidden). Counted in code points so an emoji is one
// backspace. Autocorrect "teh" -> "the" = 3 deletes + "the".
export function diffText(prev: string, next: string): { deletes: number; added: string } {
  const a = Array.from(prev);
  const b = Array.from(next);
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i += 1;
  return { deletes: a.length - i, added: b.slice(i).join('') };
}
