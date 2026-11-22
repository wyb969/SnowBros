export const BUILD = 'arcade-20261122';
export const STORAGE_KEY = 'snowbro.touch-layout.v1';
export const DEFAULTS = {
  joy: { x: .16, y: .84, scale: 1 },
  jump: { x: .67, y: .66, scale: 1 },
  fire: { x: .90, y: .87, scale: 1 },
  opacity: .86, sound: false
};
export const BASE_SIZE = { joy: 140, jump: 104, fire: 128 };
export const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
export function normalize(raw) {
  const result = structuredDefaults();
  const number = (value, fallback, lo, hi) => typeof value === 'number' && Number.isFinite(value) ? clamp(value, lo, hi) : fallback;
  for (const key of Object.keys(BASE_SIZE)) {
    const value = raw?.[key];
    result[key] = {
      x: number(value?.x, DEFAULTS[key].x, 0, 1),
      y: number(value?.y, DEFAULTS[key].y, 0, 1),
      scale: number(value?.scale, 1, .7, 1.7)
    };
  }
  result.opacity = number(raw?.opacity, DEFAULTS.opacity, .35, 1);
  result.sound = raw?.sound === true;
  return result;
}
export function structuredDefaults() {
  return JSON.parse(JSON.stringify(DEFAULTS));
}
export function loadSettings(storage) {
  try { return normalize(JSON.parse(storage.getItem(STORAGE_KEY))); }
  catch { return structuredDefaults(); }
}
export function saveSettings(storage, value) {
  try { storage.setItem(STORAGE_KEY, JSON.stringify(normalize(value))); return true; }
  catch { return false; }
}
export function controlBox(key, value, width, height, insets = {}) {
  const radius = Math.min(BASE_SIZE[key] * value.scale / 2, width * .23, (height - 80) * .25);
  const left = Math.max(8, insets.left || 0), right = Math.max(8, insets.right || 0);
  const bottom = Math.max(8, insets.bottom || 0), top = Math.max(68, insets.top || 0);
  return {
    x: clamp(width * value.x, left + radius, width - right - radius),
    y: clamp(height * value.y, top + radius, height - bottom - radius),
    size: radius * 2, radius
  };
}
export function joystickVector(dx, dy, radius) {
  if (![dx, dy, radius].every(Number.isFinite) || radius <= 0) return { x: 0, y: 0, axis: 0 };
  const length = Math.hypot(dx, dy);
  const factor = length > radius ? radius / length : 1;
  const x = dx * factor / radius, y = dy * factor / radius;
  return { x, y, axis: Math.abs(x) < .12 ? 0 : x };
}
export class InputState {
  constructor() { this.pointers = new Map(); this.axis = 0; }
  down(id, control) {
    if (this.pointers.has(id) || (control === 'joy' && [...this.pointers.values()].includes('joy'))) return false;
    this.pointers.set(id, control);
    return control === 'jump';
  }
  move(id, dx, dy, radius) {
    if (this.pointers.get(id) !== 'joy') return null;
    const v = joystickVector(dx, dy, radius);
    this.axis = v.axis; return v;
  }
  up(id) {
    const control = this.pointers.get(id);
    this.pointers.delete(id);
    if (control === 'joy' && ![...this.pointers.values()].includes('joy')) this.axis = 0;
    return control;
  }
  reset() { this.pointers.clear(); this.axis = 0; }
  snapshot() { return { type: 'input', axis: this.axis, fire: [...this.pointers.values()].includes('fire') }; }
}
