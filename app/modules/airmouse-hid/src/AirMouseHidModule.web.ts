import { registerWebModule, NativeModule } from 'expo';

// AirMouseHidModule is not available on the web platform.
class AirMouseHidModule extends NativeModule<{}> {}

export default registerWebModule(AirMouseHidModule, 'AirMouseHidModule');
