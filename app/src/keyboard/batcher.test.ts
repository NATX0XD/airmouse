/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { TextBatcher, diffText } from './batcher.ts';
import type { Msg } from '../transport/types';

function setup() {
  const sent: Msg[] = [];
  let pending: (() => void) | null = null;
  const timers = {
    set: (cb: () => void) => {
      pending = cb;
      return 1;
    },
    clear: () => {
      pending = null;
    },
  };
  const b = new TextBatcher((m) => sent.push(m), 50, timers);
  const tick = () => {
    const cb = pending;
    pending = null;
    cb?.();
  };
  return { b, sent, tick };
}

test('characters typed within the window go out as one text message', () => {
  const { b, sent, tick } = setup();
  b.type('H');
  b.type('i');
  b.type(' there');
  assert.equal(sent.length, 0);
  tick();
  assert.deepEqual(sent, [{ t: 'text', s: 'Hi there' }]);
});

test('backspace eats pending text first, then sends the key', () => {
  const { b, sent, tick } = setup();
  b.type('ab👍');
  b.backspace();
  tick();
  assert.deepEqual(sent, [{ t: 'text', s: 'ab' }]);
  b.backspace();
  assert.deepEqual(sent.at(-1), { t: 'key', k: 'backspace' });
});

test('keys flush pending text so order is kept', () => {
  const { b, sent } = setup();
  b.type('abc');
  b.key('tab');
  assert.deepEqual(sent, [{ t: 'text', s: 'abc' }, { t: 'key', k: 'tab' }]);
});

test('pasted newlines become Enter taps', () => {
  const { b, sent, tick } = setup();
  b.type('one\ntwo');
  tick();
  assert.deepEqual(sent, [{ t: 'text', s: 'one' }, { t: 'key', k: 'enter' }, { t: 'text', s: 'two' }]);
});

test('empty input and empty flush send nothing', () => {
  const { b, sent } = setup();
  b.type('');
  b.flush();
  assert.deepEqual(sent, []);
});

test('diffText finds appended text, deletions and replacements', () => {
  assert.deepEqual(diffText('', 'a'), { deletes: 0, added: 'a' });
  assert.deepEqual(diffText('hello', 'hello wor'), { deletes: 0, added: ' wor' });
  assert.deepEqual(diffText('hello', 'hell'), { deletes: 1, added: '' });
  assert.deepEqual(diffText('I teh', 'I the '), { deletes: 2, added: 'he ' });
  assert.deepEqual(diffText('ok👍', 'ok'), { deletes: 1, added: '' });
  assert.deepEqual(diffText('same', 'same'), { deletes: 0, added: '' });
});
