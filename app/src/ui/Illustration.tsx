import type { ReactNode } from 'react';
import { Image, View, type ImageSourcePropType } from 'react-native';
import Svg, { Circle, Defs, G, Line, LinearGradient as SvgGradient, Path, Rect, Stop, Text as SvgText } from 'react-native-svg';
import { IconBadge, type SymbolName } from './components';
import { usePalette } from './tokens';
import { GetMacArt, HeroPointingArt, HowItWorksArt } from './vectorArt';

export type IllustrationName =
  | 'hero-pointing'
  | 'calib-place'
  | 'calib-point-left'
  | 'calib-point-right'
  | 'calib-done'
  | 'connect-wifi'
  | 'connect-bluetooth'
  | 'connect-qr'
  | 'connect-ip'
  | 'gyro-axes'
  | 'how-it-works'
  | 'get-mac';

// Raster art (generated later into assets/illustrations/). To switch one on,
// replace `null` with require('../../assets/illustrations/<name>.png').
// Until then the vector placeholder (or the animated `children`) is shown.
const RASTER: Record<IllustrationName, ImageSourcePropType | null> = {
  'hero-pointing': require('../../assets/illustrations/hero-pointing.png'),
  'calib-place': require('../../assets/illustrations/calib-place.png'),
  'calib-point-left': null,
  'calib-point-right': null,
  'calib-done': require('../../assets/illustrations/calib-done.png'),
  'connect-wifi': null,
  'connect-bluetooth': null,
  'connect-qr': null,
  'connect-ip': null,
  'gyro-axes': null,
  'how-it-works': null,
  'get-mac': require('../../assets/illustrations/get-mac.png'),
};

const BADGES: Partial<Record<IllustrationName, { icon: SymbolName; color: string; gradient?: boolean }>> = {
  'connect-wifi': { icon: 'wifi', color: '#0A84FF' },
  'connect-bluetooth': { icon: 'antenna.radiowaves.left.and.right', color: '#0A84FF' },
  'connect-qr': { icon: 'qrcode.viewfinder', color: '#FF9F0A' },
  'connect-ip': { icon: 'network', color: '#30B0C7' },
};

// One switch point for static art. `children` = the code/SVG placeholder
// (animated pieces in calibration); `overlay` stays on top of the raster too.
export function Illustration(p: { name: IllustrationName; width: number; height: number; children?: ReactNode; overlay?: ReactNode }) {
  const raster = RASTER[p.name];
  if (raster) {
    return (
      <View style={{ width: p.width, height: p.height }}>
        <Image source={raster} style={{ width: p.width, height: p.height }} resizeMode="contain" />
        {p.overlay}
      </View>
    );
  }
  if (p.children) return <>{p.children}</>;
  if (p.name === 'gyro-axes') return <GyroAxes width={p.width} height={p.height} />;
  if (p.name === 'hero-pointing') return <HeroPointingArt width={p.width} height={p.height} />;
  if (p.name === 'how-it-works') return <HowItWorksArt width={p.width} height={p.height} />;
  if (p.name === 'get-mac') return <GetMacArt width={p.width} height={p.height} />;
  const badge = BADGES[p.name];
  if (badge) return <IconBadge name={badge.icon} color={badge.color} gradient={badge.gradient} size={Math.min(p.width, p.height)} />;
  return <View style={{ width: p.width, height: p.height }} />;
}

// Vector placeholder: phone in perspective with the three rotation axes.
function GyroAxes({ width, height }: { width: number; height: number }) {
  const c = usePalette();
  const cx = 150;
  const cy = 112;
  return (
    <Svg width={width} height={height} viewBox="0 6 300 200">
      <Defs>
        <SvgGradient id="gscreen" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#0A84FF" />
          <Stop offset="0.5" stopColor="#5E5CE6" />
          <Stop offset="1" stopColor="#BF5AF2" />
        </SvgGradient>
      </Defs>
      {/* phone lying flat, seen from above at an angle */}
      <G transform={`translate(${cx} ${cy}) skewX(-18) scale(1 0.62)`}>
        <Rect x={-34} y={-78} width={68} height={156} rx={14} fill={c.dark ? '#3A3A3C' : '#D1D1D6'} />
        <Rect x={-31} y={-75} width={62} height={150} rx={12} fill="url(#gscreen)" />
      </G>
      {/* Z: yaw, vertical axis */}
      <Line x1={cx} y1={cy} x2={cx} y2={18} stroke={c.axisZ} strokeWidth={3} strokeLinecap="round" />
      <Path d={`M ${cx - 22} 40 A 22 8 0 1 0 ${cx + 22} 40`} fill="none" stroke={c.axisZ} strokeWidth={2.5} strokeLinecap="round" />
      <SvgText x={cx + 10} y={22} fill={c.axisZ} fontSize={14} fontWeight="600">
        Z yaw
      </SvgText>
      {/* X: pitch, across the phone */}
      <Line x1={cx} y1={cy} x2={cx + 112} y2={cy} stroke={c.axisX} strokeWidth={3} strokeLinecap="round" />
      <Path d={`M ${cx + 92} ${cy - 18} A 8 18 0 1 1 ${cx + 92} ${cy + 18}`} fill="none" stroke={c.axisX} strokeWidth={2.5} strokeLinecap="round" />
      <SvgText x={cx + 70} y={cy + 38} fill={c.axisX} fontSize={14} fontWeight="600">
        X pitch
      </SvgText>
      {/* Y: roll, along the phone */}
      <Line x1={cx} y1={cy} x2={cx + 44} y2={cy - 70} stroke={c.axisY} strokeWidth={3} strokeLinecap="round" />
      <SvgText x={cx + 50} y={cy - 62} fill={c.axisY} fontSize={14} fontWeight="600">
        Y roll
      </SvgText>
      <Circle cx={cx} cy={cy} r={4} fill={c.label} />
    </Svg>
  );
}
