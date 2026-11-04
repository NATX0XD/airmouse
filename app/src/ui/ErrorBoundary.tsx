import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

type State = { error: Error | null; stack?: string };

// Release builds swallow JS errors into a blank screen; show them instead.
// Plain RN only, so it still renders if the design system itself is broken.
export class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    this.setState({ error, stack: info.componentStack ?? undefined });
  }

  render() {
    const { error, stack } = this.state;
    if (!error) return this.props.children;
    return (
      <View style={styles.root}>
        <ScrollView contentContainerStyle={styles.content}>
          <Text style={styles.title}>Something Went Wrong</Text>
          <Text style={styles.body}>AirMouse hit an error. Please send this text to the developer.</Text>
          <Text selectable style={styles.code}>
            {`${error.name}: ${error.message}\n\n${error.stack ?? ''}\n${stack ?? ''}`}
          </Text>
          <Pressable style={styles.button} onPress={() => this.setState({ error: null, stack: undefined })}>
            <Text style={styles.buttonText}>Try Again</Text>
          </Pressable>
        </ScrollView>
      </View>
    );
  }
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  content: { padding: 24, paddingTop: 80, gap: 16 },
  title: { color: '#FFF', fontSize: 28, fontWeight: '700' },
  body: { color: 'rgba(235,235,245,0.6)', fontSize: 17 },
  code: { color: '#FF6961', fontSize: 13, fontFamily: 'Menlo' },
  button: { backgroundColor: '#0A84FF', borderRadius: 14, height: 50, alignItems: 'center', justifyContent: 'center' },
  buttonText: { color: '#FFF', fontSize: 17, fontWeight: '600' },
});
