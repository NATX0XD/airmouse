import { StyleSheet, View } from 'react-native';
import Svg, { Circle, Defs, G, LinearGradient as SvgGradient, Path, Rect, Stop } from 'react-native-svg';
import { Icon, T, type SymbolName } from './components';
import { aurora, glow, space, usePalette } from './tokens';

// Code-drawn placeholders for the onboarding raster art (see Illustration.tsx).

function Gradients() {
  return (
    <Defs>
      <SvgGradient id="aur" x1="0" y1="0" x2="1" y2="1">
        <Stop offset="0" stopColor={aurora.colors[0]} />
        <Stop offset="0.5" stopColor={aurora.colors[1]} />
        <Stop offset="1" stopColor={aurora.colors[2]} />
      </SvgGradient>
      <SvgGradient id="scr" x1="0" y1="0" x2="1" y2="1">
        <Stop offset="0" stopColor="#0B1430" />
        <Stop offset="1" stopColor="#070B16" />
      </SvgGradient>
    </Defs>
  );
}

function Laptop({ x, y, w, children }: { x: number; y: number; w: number; children?: React.ReactNode }) {
  const h = w * 0.62;
  return (
    <G transform={`translate(${x} ${y})`}>
      <Rect x={0} y={0} width={w} height={h} rx={10} fill="#2C2C2E" />
      <Rect x={5} y={5} width={w - 10} height={h - 10} rx={6} fill="url(#scr)" />
      <Path d={`M ${-w * 0.08} ${h + 2} L ${w * 1.08} ${h + 2} L ${w * 1.02} ${h + 12} L ${-w * 0.02} ${h + 12} Z`} fill="#8E8E93" />
      {children}
    </G>
  );
}

// Phone -> waves -> Mac cursor.
export function HeroPointingArt({ width, height }: { width: number; height: number }) {
  return (
    <Svg width={width} height={height} viewBox="0 0 320 200">
      <Gradients />
      <Circle cx={222} cy={100} r={86} fill="url(#aur)" opacity={0.12} />
      <Laptop x={146} y={40} w={148}>
        {/* glowing cursor trail */}
        <Path d="M 22 70 Q 50 30 92 46" stroke={glow.core} strokeOpacity={0.55} strokeWidth={3} strokeLinecap="round" strokeDasharray="1 7" fill="none" />
        <G transform="translate(92 36) scale(1.15)">
          <Path d="M0 0 L0 20 L5 15 L9 24 L12.5 22.5 L8.5 14 L15 14 Z" fill="#FFFFFF" stroke="#000" strokeWidth={1} strokeLinejoin="round" />
        </G>
      </Laptop>
      {/* waves */}
      {[0, 1, 2].map((i) => (
        <Path key={i} d={`M ${104 + i * 13} ${86 - i * 9} A ${22 + i * 13} ${22 + i * 13} 0 0 1 ${104 + i * 13} ${132 + i * 9}`} stroke={glow.core} strokeOpacity={0.9 - i * 0.25} strokeWidth={4} strokeLinecap="round" fill="none" transform={`rotate(-20 ${104 + i * 13} 109)`} />
      ))}
      {/* phone, tilted like a remote */}
      <G transform="rotate(-18 60 120)">
        <Rect x={34} y={58} width={56} height={114} rx={13} fill="#E5E5EA" />
        <Rect x={37} y={61} width={50} height={108} rx={10} fill="#1C1C1E" />
        <Rect x={40} y={64} width={44} height={102} rx={8} fill="url(#aur)" />
        <Rect x={53} y={69} width={18} height={5} rx={2.5} fill="#000" />
      </G>
    </Svg>
  );
}

function Stage({ icon, color, title, sub }: { icon: SymbolName; color: string; title: string; sub: string }) {
  const c = usePalette();
  return (
    <View style={styles.stage}>
      <View style={[styles.stageIcon, { backgroundColor: color }]}>
        <Icon name={icon} size={30} color="#FFFFFF" weight="semibold" />
      </View>
      <T v="subhead" weight="600" center>
        {title}
      </T>
      <T v="footnote" color={c.secondaryLabel} center>
        {sub}
      </T>
    </View>
  );
}

// Gyroscope -> Smoothing -> Cursor.
export function HowItWorksArt({ width }: { width: number; height: number }) {
  const c = usePalette();
  return (
    <View style={[styles.how, { width }]}>
      <Stage icon="gyroscope" color="#5E5CE6" title="Gyroscope" sub="Feels each turn" />
      <Icon name="chevron.right" size={16} color={c.tertiaryLabel} weight="bold" style={{ marginTop: 22 }} />
      <Stage icon="waveform.path" color="#0A84FF" title="Smoothing" sub="One Euro filter" />
      <Icon name="chevron.right" size={16} color={c.tertiaryLabel} weight="bold" style={{ marginTop: 22 }} />
      <Stage icon="cursorarrow.rays" color="#BF5AF2" title="Cursor" sub="Moves on your Mac" />
    </View>
  );
}

// Mac mock-up showing the pairing QR code.
export function GetMacArt({ width, height }: { width: number; height: number }) {
  const cells = [
    [0, 0], [1, 0], [2, 0], [0, 1], [2, 1], [0, 2], [1, 2], [2, 2],
    [4, 0], [6, 1], [5, 2], [4, 4], [5, 3], [6, 5], [3, 6], [5, 6], [6, 6], [3, 4], [4, 5],
    [0, 4], [1, 4], [2, 4], [0, 5], [2, 5], [0, 6], [1, 6], [2, 6],
  ];
  return (
    <Svg width={width} height={height} viewBox="0 0 320 200">
      <Gradients />
      <Circle cx={160} cy={100} r={90} fill="url(#aur)" opacity={0.12} />
      <Laptop x={72} y={30} w={176}>
        <Rect x={64} y={24} width={48} height={48} rx={6} fill="#FFFFFF" />
        {cells.map(([cx, cy], i) => (
          <Rect key={i} x={68 + cx * 5.8} y={28 + cy * 5.8} width={5.4} height={5.4} rx={1} fill="#000" />
        ))}
        <Rect x={52} y={80} width={72} height={6} rx={3} fill="#FFFFFF" opacity={0.5} />
        <Rect x={64} y={92} width={48} height={5} rx={2.5} fill="#FFFFFF" opacity={0.25} />
      </Laptop>
    </Svg>
  );
}

const styles = StyleSheet.create({
  how: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: space.xs },
  stage: { flex: 1, alignItems: 'center', gap: 6 },
  stageIcon: { width: 64, height: 64, borderRadius: 18, borderCurve: 'continuous', alignItems: 'center', justifyContent: 'center' },
});
