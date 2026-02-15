# Client-side prediction and framerate independence

Two things that are easy to get wrong in a networked game: making movement feel responsive despite network latency, and making physics behave identically regardless of monitor refresh rate. Here's how Tilefun handles both.

## The problem

The server is authoritative — it runs all physics and sends state to clients. But if the player has to wait for a round trip before seeing their character move, it feels terrible. And if game logic runs inside `requestAnimationFrame`, a player on a 240Hz monitor moves four times faster than one on 60Hz.

These are separate problems but they interlock: the fixed timestep that solves framerate independence also creates the tick boundaries that prediction and interpolation need to work across.

## Fixed timestep with interpolation

The game loop runs physics at a fixed 60Hz regardless of display refresh rate. The classic accumulator pattern from [Fix Your Timestep](https://gafferongames.com/post/fix_your_timestep/):

```typescript
private tick = (nowMs: number): void => {
  const now = nowMs / 1000;
  let frameTime = now - this.lastTime;
  this.lastTime = now;

  // Cap frame time to prevent "spiral of death" on lag spikes
  if (frameTime > MAX_FRAME_TIME) {
    frameTime = MAX_FRAME_TIME;
  }

  this.accumulator += frameTime;

  while (this.accumulator >= FIXED_DT) {
    this.callbacks.update(FIXED_DT);
    this.accumulator -= FIXED_DT;
  }

  // Alpha = fraction between two fixed updates [0, 1)
  const alpha = this.accumulator / FIXED_DT;
  this.callbacks.render(alpha);
};
```

Every `update()` call gets the same `dt` (1/60s). Rendering happens at whatever rate the browser wants, but receives an `alpha` value that says "you're 40% of the way between the last two physics ticks." The renderer then interpolates between previous and current positions:

```typescript
function lerpPos(item: Renderable, alpha: number): { wx: number; wy: number } {
  if (item.prevPosition) {
    return {
      wx: item.prevPosition.wx + (item.position.wx - item.prevPosition.wx) * alpha,
      wy: item.prevPosition.wy + (item.position.wy - item.prevPosition.wy) * alpha,
    };
  }
  return item.position;
}
```

This means every entity, the camera, and even jump arcs all get smooth sub-tick rendering. On a 120Hz display you see twice as many interpolated frames as physics ticks — silky smooth without changing game behavior.

## Prediction vs interpolation

These are complementary, not alternatives:

**Interpolation** is for *other* entities. The server says "chicken is at (100, 200) this tick, (102, 200) next tick." Between those ticks, the renderer draws the chicken at a lerped position. This introduces one tick of visual latency (you're always rendering between the *previous* two known states), but for non-player entities that's invisible.

**Prediction** is for the *local player*. You can't interpolate your own movement — it would feel like moving through molasses. Instead, the client runs the same physics code locally, immediately, using your input. When the server confirms what happened, the client reconciles any differences.

## Input replay reconciliation

The prediction system stores every input in a ring buffer with a sequence number:

```typescript
storeInput(seq: number, movement: Movement, dt: number): void {
  if (this.inputBuffer.length >= INPUT_BUFFER_SIZE) {
    this.inputBuffer.shift();
  }
  this.inputBuffer.push({ seq, movement, dt });
}
```

When the server sends back state, it includes the last input sequence it processed. Reconciliation then:

1. Snaps to the server's authoritative position
2. Discards all inputs the server has already processed
3. Replays unacknowledged inputs on top of the server state

```typescript
// Snap to server's authoritative position
this.predicted.position.wx = serverPlayer.position.wx;
this.predicted.position.wy = serverPlayer.position.wy;

// Trim acknowledged inputs
this.trimInputBuffer(lastProcessedInputSeq);

// Replay unacknowledged inputs on top of server position
for (const input of this.inputBuffer) {
  this.applyInput(input.movement, input.dt, world, props, entities);
}
```

If the client and server agree (which they usually do, since they run the same physics), the replayed position matches the predicted position and the player sees nothing. If they disagree (server rejected a move, or collision was different), the player smoothly corrects.

For teleports or knockbacks where the correction is large (>32 pixels), we snap instantly instead of interpolating to avoid a weird slide effect.

## Shared physics via MovementContext

The key to prediction working is that client and server run *identical* physics. We achieve this with a `MovementContext` interface — same movement code, different data sources:

```typescript
interface MovementContext {
  getCollision(tx: number, ty: number): number;
  getHeight(tx: number, ty: number): number;
  isEntityBlocked(aabb: AABB): boolean;
  isPropBlocked(aabb: AABB): boolean;
  noclip: boolean;
}
```

The server builds a context from its spatial hash and live entities. The client builds one from snapshot arrays. The actual `moveAndCollide()` function doesn't know or care which side it's running on.

## Camera interpolation

One subtle issue: the camera follows the player with an exponential lerp (`camera += (target - camera) * 0.1` per tick). Naively interpolating this creates jitter at tick boundaries because the camera's lerp curve doesn't match linear entity interpolation. The fix is to use the exponential form for sub-tick camera motion:

```typescript
// Exponential decay matches the follow() curve for smooth sub-tick motion
const f = 1 - (1 - CAMERA_LERP) ** alpha;
gc.camera.x = gc.camera.prevX + (playerX - gc.camera.prevX) * f;
gc.camera.y = gc.camera.prevY + (playerY - gc.camera.prevY) * f;
```

This eliminates the derivative discontinuity at tick boundaries that causes visible jitter on high refresh rate displays.

## Riding mounts

This gets more interesting when the player is riding a cow. The predictor maintains a separate predicted mount entity — input drives the mount's velocity, and the player's position is derived from mount position + offset. Reconciliation replays inputs on the mount, not the player directly. The entire system (prediction, reconciliation, interpolation) runs for both entities in lockstep.

## What's next

The prediction system currently handles movement and jumping. Next up: predicting entity interactions (mounting/dismounting, picking up items) for instant feedback even before the server confirms. And exploring dead reckoning for other players in multiplayer — extrapolating their movement between server updates rather than just interpolating.
