import { useEffect, useRef, useState } from 'react';
import { Keyboard, LayoutAnimation, Platform, Pressable, StyleSheet, TextInput, View, type KeyboardEvent, type TextInputInstance } from 'react-native';
import * as Haptics from 'expo-haptics';
import { TextBatcher, diffText } from '../keyboard/batcher';
import type { KeyName, Msg } from '../transport/types';
import { Icon, Material, T, type SymbolName } from '../ui/components';
import { radius, space, usePalette } from '../ui/tokens';

const MAX_BUFFER = 200; // clear the hidden box past this, it never needs history

// Height of the system keyboard, animated like KeyboardAvoidingView does.
export function useKeyboardHeight(): number {
  const [h, setH] = useState(0);
  useEffect(() => {
    const ios = Platform.OS === 'ios';
    const apply = (e: KeyboardEvent | null, next: number) => {
      if (e && ios && e.duration) {
        LayoutAnimation.configureNext({ duration: e.duration, update: { duration: e.duration, type: LayoutAnimation.Types.keyboard } });
      }
      setH(next);
    };
    const show = Keyboard.addListener(ios ? 'keyboardWillShow' : 'keyboardDidShow', (e) => apply(e, e.endCoordinates.height));
    const hide = Keyboard.addListener(ios ? 'keyboardWillHide' : 'keyboardDidHide', (e) => apply(e, 0));
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);
  return h;
}

type SpecialKey = { k: KeyName; label?: string; icon?: SymbolName; a11y: string };
const KEYS: SpecialKey[] = [
  { k: 'escape', label: 'esc', a11y: 'Escape' },
  { k: 'tab', label: 'tab', a11y: 'Tab' },
  { k: 'left', icon: 'arrow.left', a11y: 'Left Arrow' },
  { k: 'up', icon: 'arrow.up', a11y: 'Up Arrow' },
  { k: 'down', icon: 'arrow.down', a11y: 'Down Arrow' },
  { k: 'right', icon: 'arrow.right', a11y: 'Right Arrow' },
  { k: 'enter', icon: 'return', a11y: 'Return' },
];

type Props = {
  send: (m: Msg) => void;
  onTyped: () => void;
  onDone: () => void;
  // Changes when the Mac focuses a new text field: start a fresh buffer.
  fieldId: number;
};

// Glass bar above the system keyboard. A hidden TextInput holds focus so the
// iOS keyboard stays up; its content is diffed and sent as text / key messages.
export function KeyboardPanel(p: Props) {
  const c = usePalette();
  const input = useRef<TextInputInstance>(null);
  const prev = useRef('');
  const sendRef = useRef(p.send);
  const typedRef = useRef(p.onTyped);
  const batcherRef = useRef<TextBatcher | null>(null);
  // Created on first use (handlers / effects only, never during render).
  const batch = () => (batcherRef.current ??= new TextBatcher((m) => sendRef.current(m)));

  useEffect(() => {
    sendRef.current = p.send;
    typedRef.current = p.onTyped;
  }, [p.send, p.onTyped]);

  useEffect(() => () => batcherRef.current?.flush(), []);

  const reset = () => {
    batch().flush();
    prev.current = '';
    input.current?.clear();
  };

  useEffect(() => {
    batcherRef.current?.flush();
    prev.current = '';
    input.current?.clear();
  }, [p.fieldId]);

  const onChangeText = (text: string) => {
    const { deletes, added } = diffText(prev.current, text);
    prev.current = text;
    if (!deletes && !added) return;
    for (let i = 0; i < deletes; i++) batch().backspace();
    batch().type(added);
    typedRef.current();
    if (text.length > MAX_BUFFER) reset();
  };

  const tap = (k: KeyName) => {
    batch().key(k);
    typedRef.current();
    Haptics.selectionAsync();
    if (k === 'enter' || k === 'tab' || k === 'escape') reset(); // new line / field: old text is no longer ours to edit
  };

  return (
    <Material style={styles.panel}>
      <TextInput
        ref={input}
        autoFocus
        style={styles.hidden}
        onChangeText={onChangeText}
        onKeyPress={(e) => {
          // A change event covers backspace when the box has text; an empty box only reports the key.
          if (e.nativeEvent.key === 'Backspace' && prev.current === '') {
            batch().backspace();
            typedRef.current();
          }
        }}
        onSubmitEditing={() => tap('enter')}
        submitBehavior="submit"
        returnKeyType="default"
        autoCapitalize="sentences"
        keyboardAppearance={c.dark ? 'dark' : 'light'}
        caretHidden
        contextMenuHidden
        accessibilityLabel="Type on Mac"
      />
      <View style={styles.header}>
        <Pressable style={styles.headerLeft} onPress={() => input.current?.focus()} accessibilityRole="button" accessibilityLabel="Show Keyboard">
          <Icon name="keyboard" size={17} color={c.tint} weight="semibold" />
          <T v="subhead" weight="600">
            Typing on Mac
          </T>
        </Pressable>
        <Pressable
          hitSlop={10}
          onPress={() => {
            batch().flush();
            Keyboard.dismiss();
            p.onDone();
          }}
          accessibilityRole="button"
          accessibilityLabel="Done"
        >
          <T v="headline" color={c.tint}>
            Done
          </T>
        </Pressable>
      </View>
      <View style={styles.keys}>
        {KEYS.map((key) => (
          <Pressable
            key={key.k}
            onPress={() => tap(key.k)}
            style={({ pressed }) => [styles.key, { backgroundColor: pressed ? c.fillStrong : c.card }]}
            accessibilityRole="button"
            accessibilityLabel={key.a11y}
          >
            {key.icon ? (
              <Icon name={key.icon} size={17} color={c.label} weight="semibold" />
            ) : (
              <T v="subhead" weight="600">
                {key.label}
              </T>
            )}
          </Pressable>
        ))}
      </View>
    </Material>
  );
}

const styles = StyleSheet.create({
  panel: { borderRadius: radius.card, borderCurve: 'continuous', padding: space.md, gap: space.md },
  hidden: { position: 'absolute', width: 1, height: 1, opacity: 0, left: 0, top: 0 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: space.xs },
  headerLeft: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  keys: { flexDirection: 'row', gap: 6 },
  key: { flex: 1, height: 42, borderRadius: radius.control, borderCurve: 'continuous', alignItems: 'center', justifyContent: 'center' },
});
