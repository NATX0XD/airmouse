// Per-view finger tracking for raw onTouchStart / onTouchEnd. Pure (node --test).
//
// The responder system has one owner at a time, so the pad and the click
// buttons could not be held together. Raw touch events fire per view and
// carry touch identifiers; each view keeps its own set, so lifting one
// finger never ends another view's touch.

export type TouchPoint = { identifier: number | string };

export class TouchSet {
  private ids = new Set<string>();

  get active(): boolean {
    return this.ids.size > 0;
  }

  get count(): number {
    return this.ids.size;
  }

  has(id: number | string): boolean {
    return this.ids.has(String(id));
  }

  // Returns true when this view went from no fingers to pressed.
  down(id: number | string): boolean {
    const was = this.active;
    this.ids.add(String(id));
    return !was;
  }

  // Fingers lifted (changedTouches). Ids we do not own are ignored.
  // Returns true when the last finger left.
  up(points: readonly TouchPoint[]): boolean {
    if (!this.active) return false;
    points.forEach((t) => this.ids.delete(String(t.identifier)));
    return !this.active;
  }

  // Safety net: keep only fingers still on screen (nativeEvent.touches), so a
  // lost end event can't leave a button held down.
  sync(onScreen: readonly TouchPoint[]): boolean {
    if (!this.active) return false;
    const live = new Set(onScreen.map((t) => String(t.identifier)));
    [...this.ids].forEach((id) => !live.has(id) && this.ids.delete(id));
    return !this.active;
  }

  clear(): boolean {
    const was = this.active;
    this.ids.clear();
    return was;
  }
}
