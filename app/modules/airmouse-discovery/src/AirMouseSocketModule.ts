import { NativeModule, requireOptionalNativeModule } from 'expo';

type Events = {
  onSocketOpen: (e: { id: string }) => void;
  onSocketMessage: (e: { id: string; text: string }) => void;
  onSocketClose: (e: { id: string; error?: string }) => void;
};

declare class AirMouseSocketModule extends NativeModule<Events> {
  open(id: string, url: string): void;
  send(id: string, text: string): void;
  close(id: string): void;
}

// iOS-only WebSocket with TCP_NODELAY. null elsewhere (or in an older build):
// callers fall back to the JS WebSocket.
export const AirMouseSocket = requireOptionalNativeModule<AirMouseSocketModule>('AirMouseSocket');
