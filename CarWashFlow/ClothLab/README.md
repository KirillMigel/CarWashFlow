# ClothLab

Interactive fabric simulations from the Cloth Lab design, ported to SwiftUI + Metal.
Grab any of them anywhere on screen and pull.

| # | Effect | What it is |
|---|--------|-----------|
| 01 | `.greyCloth` | Flat unlit colour — the fill and nothing over it |
| 06 | `.holoSheet` | Thin-film iridescence on polished metal — every fold shifts the light |
| 21 | `.dissolvePoints` | A point cloud that scatters apart and reassembles — tap to burst it |

## Install

Copy the `ClothLab` folder into your project. That's it — no package, no dependency, no
build-phase step. The Metal shaders are compiled at launch from a Swift string, so there
is no `.metal` file to remember to add and no resource bundle to wire up.

Runs on iOS, macOS and visionOS from the same source.

## One line

Drop in an image name — asset catalog name, or a plain file in the bundle. That's the
whole thing:

```swift
ClothView("im1")
```

Another effect, same one line:

```swift
ClothView("im1", effect: .holoSheet)
ClothView("im1", effect: .dissolvePoints)
```

Or with no picture at all, on the default grey:

```swift
ClothView(.greyCloth)
```

As a live background behind anything:

```swift
Text("Cloth Lab").clothEffect("im1")

VStack { … }.clothEffect(.holoSheet)
```

Interaction is built in: drag to grab and pull the fabric from anywhere, double-tap to
reset it, tap to burst Dissolve Points.

## Colour or image

Every effect defaults to the **same grey** (`#A7ABB2`). Swap it for anything, on any of
them — not just Grey Cloth:

```swift
ClothView(.greyCloth)                             // default grey
ClothView(.greyCloth, fill: .color(.indigo))      // any colour
ClothView(.greyCloth, fill: .gradient([.orange, .purple]))
ClothView(.greyCloth, fill: .image("poster"))     // asset catalog or bundled file
```

Images can come from anywhere:

```swift
.image("poster")                  // asset catalog name, or a file in the bundle
.image(url: someFileOrRemoteURL)
.image(data: pngOrJpegData)       // e.g. straight out of PhotosPicker
.image(cgImage: rendered)
```

The picture is fitted to the sheet with `.cover` by default (crop the overflow, like the
original). Change it with `.imageFit(.contain)`, `.imageFit(.stretch)` or
`.imageFit(.tile([3, 4]))`.

When a picture is in play the material switches to the "image ready" look from the
original Grey Cloth page — matte, lightly self-lit so it stays readable in the folds, weave
turned down. Tune that:

```swift
ClothView(.greyCloth
    .image("poster")
    .imageBrightness(0.8)         // how much the picture self-illuminates
    .imageTint(.orange))          // multiplied over the picture
```

On Dissolve Points the picture colours the dots, so it scatters into its own pixels.

## Customising everything

Every preset is a value you can chain off. Nothing is hidden.

```swift
ClothView(.greyCloth
    .color(.teal)
    .wind(2.4)                          // gust strength
    .gravity(-0.5)
    .grid(cols: 70, rows: 44)           // simulation resolution
    .size(width: 4, height: 2)          // sheet size in world units
    .pins(.topCorners)                  // .none .top .topCorners .left .corners .custom
    .stiffness(shear: 0.9, bend: 0.5, iterations: 4)
    .grab(radius: 0.5, lift: 0.4, strength: 0.4)
    .roughness(0.6)
    .metalness(0.2)
    .sheen(1, color: .white, roughness: 0.4)
    .iridescence(1, ior: 2.1, thickness: [110, 620])
    .bumpScale(0.4)
    .weave(ClothWeave(size: 64, step: 3, thread: 1, speck: 1800, tile: [24, 16]))
    .environmentIntensity(0.8)
    .camera(distance: 6, fov: 42)
    .rotation(x: 0.05, y: -0.3)
    .scale(1)                           // 1 fills the frame; the presets ship at 0.7
    .speed(1)                           // clock rate: default 6, 1 = original timing, 0 freezes
    .exposure(1.2)
    .background(.radial(inner: .black, mid: .black, outer: .black))
    .grain(ClothGrain(overlay: 0.2, screen: 0.03))
    .lighting(lights: true, environment: true))
```

For anything not covered by a named modifier, edit the structs directly:

```swift
ClothView(.greyCloth
    .material { $0.sheenColor = .cyan; $0.whenWearingAnImage.emissive = 0.9 }
    .physics  { $0.settle = 900; $0.damping = 0.996 }
    .scene    { $0.environmentBlur = 0.02 })
```

### Two knobs worth knowing about

**Grain.** The originals lay a film-grain wash over everything — two noise layers, one
`overlay` at 55%, one `screen` at 5%. It is ported exactly, but the presets ship with it
**off**, because at phone pixel density the speckle reads as dirt on the screen. Turn it on
per effect if you want the original look:

```swift
ClothView(.greyCloth.grain(ClothGrain(overlay: 0.18, screen: 0.03)))   // subtle
ClothView(.greyCloth.grain(ClothGrain()))                             // as the design shipped
```

**Background.** Each effect paints its own dark backdrop. To float the cloth over your own
UI instead:

```swift
ZStack {
    MyContent()
    ClothView(.chiffonLikeSheet.transparentBackground())
}
```

### The original tints

They all default to the same grey on purpose. `ClothPalette` keeps the colours the design
originally shipped with, if you want them back:

```swift
ClothView(.holoSheet.color(ClothPalette.holo))
```

## What's in the folder

| File | Role |
|------|------|
| `ClothEffect.swift` | Everything you can configure, plus the presets |
| `ClothView.swift` | `ClothView`, `.clothEffect(_:)`, gestures, platform glue |
| `ClothSimulation.swift` | The verlet solver — a port of `cloth-core.js` |
| `ClothShaders.swift` | Metal source: PBR + sheen + iridescence + bump + points + grain |
| `ClothRenderer.swift` | Metal pipeline, two passes, picking |
| `ClothTextures.swift` | Procedural weave height map, fill baking, image decoding |
| `ClothLabTester.swift` | The test screen the app opens on — list, ‹ › stepper, image button |
| `ClothLabGallery.swift` | The designed index page, reachable from the bottom of the test list |
| `ClothLabDemo.png` | Fallback picture, used until you add your own `im1` |

`ClothLabTester.swift` and `ClothLabGallery.swift` are demos. Delete both and the library
still works.

## Testing it by hand

The app opens on **Cloth Lab · test**: a list of the effects. Open one and you get the
effect running full screen, wearing your image, with **‹ ›** to step straight to the next
without going back. Put `ClothView("im1")` in `ContentView` instead to see the one line on
its own.

Clock rate is `.speed(_:)` on any effect — 0 freezes the cloth mid-fold, 1 is the original
browser timing, and the presets ship at **6**.

**The default clock is 6×**, not the original browser timing. The effects were authored
at an ambient, slow pace that reads as sluggish on a phone. `.speed(1)` puts any of them back
to the timing the design shipped with — worth knowing because the clock scales everything:
wind gusts, the swing of a drape, and Dissolve Points' 13-second scatter cycle, which at 6×
comes round every ~2.2 seconds.

The test screen looks for an image named **`im1`** — drop one into the project (asset
catalog or a plain file in the folder) and it is picked up automatically. Until then it
falls back to the bundled `ClothLabDemo.png`.

Interaction on every effect: **drag** anywhere to grab and pull, **double-tap** to reset,
and on Dissolve Points **tap** to burst it.

## Performance

The solver never touches the main thread. It runs on its own serial queue and publishes a
snapshot of positions and normals; `draw(in:)` only copies that snapshot into a GPU buffer.
Three things used to stall the main thread and no longer do:

- **The settle pre-roll.** `ClothPhysics.settle` runs a few hundred steps to pre-drape a
  sheet — hundreds of milliseconds of constraint solving. It is deferred out of `init`, and run
  on the simulation queue in slices of 40 steps, publishing each one. The rest pose is
  published synchronously the moment the simulation is built, so the sheet is on screen from
  the very first frame and visibly falls into its drape over the next few. Running the whole
  pre-roll in one go — even off the main thread — just swaps a freeze for an empty screen.
- **Shader compilation.** The Metal source was compiled per ClothView. It is now built once
  per device and shared, and `ClothGPU.warmUp()` (called from `PaperApp.init`) compiles it in
  the background while the first screen draws.
- **Texture baking.** Decoding a picture, fitting it to the sheet and building its mip chain
  runs on a background queue. Baked textures are then cached, and `ClothTextures.readyFill`
  returns a cached one synchronously — so a navigation push draws the real fill on its first
  frame instead of showing placeholder grey while the bake catches up. `ClothTextures.prewarm`
  bakes ahead of time (the demo calls it at launch) so even the first push is warm.

## Notes on fidelity

The simulation is a direct port: same grid, same constraint set (structural, shear, two
bend spans plus diagonals), same fold-through repair and lock-up healing, same fixed 1/120
step with up to three substeps a frame, same grab falloff.

The shading is a port of three.js `MeshPhysicalMaterial` — Lambert + GGX, Charlie sheen
with Neubelt visibility, Belcour/Barla thin-film iridescence, ACES filmic tone mapping.

Two places deliberately differ, because a straight port looks wrong on a phone:

- **Bump mapping.** three derives the weave from screen-space height derivatives, which ties
  its strength to pixel density — the same cloth reads as fine linen on a laptop and as
  hessian on a 3× phone. ClothLab samples a fixed texel step and builds a cotangent frame
  instead, so the weave looks the same everywhere and still fades through the mip chain
  when the sheet is drawn small.
- **Environment.** three uses a PMREM of `RoomEnvironment`. ClothLab uses an analytic studio
  room — floor/wall/ceiling gradient plus four soft panels, energy-normalised so blurring a
  panel preserves its energy rather than its peak brightness.
