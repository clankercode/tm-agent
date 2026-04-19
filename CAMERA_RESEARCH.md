# Trackmania 2020 Editor Camera Control Research

## Goal
After an AI agent places or removes a block at block-coordinate `(x, y, z)`, smoothly retarget the editor camera to the block's midpoint.

## Summary

The orbital camera in Trackmania 2020 is controlled by four values accessible through `CGameCtnEditorFree`:
- **Target position** (`m_TargetedPosition`): world-space point the camera orbits around
- **Distance** (`m_CameraToTargetDistance`): radius from camera to target
- **Horizontal angle** (`m_CurrentHAngle`): yaw, radians
- **Vertical angle** (`m_CurrentVAngle`): pitch, radians

To move the camera to a block's midpoint with smooth animation, convert the block coordinate to world space, then animate the camera to that position.

---

## Setting the Camera Target

### Direct (snappy) target change:
```angelscript
// Get the editor instance
auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
if (editor is null) return;

// Set the target position directly
editor.OrbitalCameraControl.m_TargetedPosition = targetWorldPos;
```

### Smooth animated transition:
```angelscript
// Use the animation function from tm-editor-plus-plus
Editor::SetCamAnimationGoTo(
    vec2(horizontalAngle, verticalAngle),  // Look direction (radians)
    targetWorldPos,                        // Target position
    cameraDistance                         // Distance from camera to target
);
```

### The two-part property set (important for going out-of-bounds):
From `Camera.as` in tm-editor-plus-plus:
```angelscript
void SetCamTargetedPosition(vec3 pos) {
    cast<CGameCtnEditorFree>(GetApp().Editor).PluginMapType.CameraTargetPosition = pos;
    // set m_TargetedPosition 2nd so the camera will update and we can go out of bounds.
    cast<CGameCtnEditorFree>(GetApp().Editor).OrbitalCameraControl.m_TargetedPosition = pos;
}
```

**Why two properties?** The engine clamps `CameraTargetPosition` to map bounds. Setting `m_TargetedPosition` second allows the camera to position itself at out-of-bounds coordinates if needed.

---

## Block Coordinate to World-Space Conversion

### Formula for standard blocks (32 × 8 × 32 m):

**Block corner (minimum coordinate):**
```angelscript
vec3 CoordToPos(const int3 &in coord, vec2 xySize = vec2(32, 8), float baseHeightOffset = 64) {
    return vec3(
        coord.x * xySize.x, 
        (float(coord.y) - (baseHeightOffset / xySize.y)) * xySize.y, 
        coord.z * xySize.x
    );
}
```

**Block midpoint (what you want):**
```angelscript
// Add half the block size to the corner position
vec3 BlockCoordToMidpoint(int3 blockCoord) {
    const vec3 HALF_COORD = vec3(16., 4., 16.);  // Half block size: 32/2, 8/2, 32/2
    return CoordToPos(blockCoord) + HALF_COORD;
}

// Or directly:
vec3 BlockCoordToMidpoint(int3 blockCoord) {
    const float baseHeightOffset = 64.0;
    return vec3(
        blockCoord.x * 32.0 + 16.0,
        (float(blockCoord.y) - (baseHeightOffset / 8.0)) * 8.0 + 4.0,
        blockCoord.z * 32.0 + 16.0
    );
}
```

### Constants:
- **Block size:** 32m (X) × 8m (Y) × 32m (Z)
- **Half block size:** 16m (X) × 4m (Y) × 16m (Z)
- **baseHeightOffset:** 64.0 (standard default; may vary by map config, see `ExtendsBelowZero`)

---

## Real-World Usage Examples from tm-editor-plus-plus

### Example 1: Smooth camera pan to a bounding box center with automatic distance
From `Components/Cursor/Gizmo.as`:
```angelscript
Editor::SetCamAnimationGoTo(
    lookUv,                               // Keep current view direction
    bb.pos,                               // Target position (center of bounding box)
    bb.halfDiag.Length() * 4.              // Distance: 4× the half-diagonal
);
```

### Example 2: Camera focus with chained modifiers
From `Components/Map/Map_EditProps.as`:
```angelscript
auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
Editor::SetCamAnimationGoTo(
    Editor::GetCurrentCamState(editor)
        .withAdditionalHAngle(1.5)        // Rotate 1.5 radians around
        .withPos(MTCoordToPos(center, size))  // Focus on block center
        .withTargetDist(MTCoordToPos(blockSize).Length())  // Distance = block diagonal
);
```

### Example 3: Quick retarget using helper function
```angelscript
// From Camera_Shared.as - simpler approach without animation
void SetEditorOrbitalTarget(const vec3 &in pos) {
    auto editor = cast<CGameCommon>(GetApp().Editor);
    auto orbital = editor.OrbitalCameraControl;
    
    float h = (orbital.m_CurrentHAngle + Math::PI / 2) * -1;
    float v = orbital.m_CurrentVAngle;
    
    // Compute new camera position from target, angles, and distance
    vec4 axis(1, 0, 0, 0);
    axis = axis * mat4::Rotate(v, vec3(0, 0, -1));
    axis = axis * mat4::Rotate(h, vec3(0, 1, 0));
    
    orbital.m_TargetedPosition = pos;
    orbital.Pos = pos + axis.xyz * orbital.m_CameraToTargetDistance;
}
```

---

## Gotchas and Important Notes

### 1. Map Bounds Clamping
- `CameraTargetPosition` is silently clamped to the map's playable volume by the engine
- On a 48×40×48 map, the Y ceiling is ~256 m
- Setting a target above this will clamp it without warning
- **Workaround:** Use the two-property approach (set `PluginMapType.CameraTargetPosition` first, then `m_TargetedPosition`)

### 2. Animation Behavior
- `SetCamAnimationGoTo()` runs over ~250ms (can be customized with `S_AnimationDuration`)
- It disables user input during animation via `EnableCustomCameraInputs()`
- The animation must be updated each frame via `UpdateAnimAndCamera()` in your main loop

### 3. Orbital vs Free Camera
- The orbital camera orbits around a target point; it's NOT a free flight camera
- Always specify distance, angles, and position together for consistent behavior

### 4. The `baseHeightOffset` Parameter
- Default is 64.0 (corresponds to `ExtendsBelowZero = 64` map property)
- This shifts the Y origin; maps with different `ExtendsBelowZero` need different offsets
- If blocks appear offset vertically, check the map's base height configuration

### 5. Coordinate Types
- Use `int3` or `nat3` for block coordinates (not `float`)
- `nat3` is unsigned (for coordinates guaranteed ≥ 0)
- `int3` is signed (for general-purpose math)

### 6. Direction Calculation Warning
- `Editor::DirToLookUv()` in Camera.as is **incorrect at steep pitches** (±65°+)
- Use `LookDirToOrbitalAngles()` from `McpTools.as` instead for accurate angle conversion
- At shallow angles (~30°), the error is negligible; at ±65° pitch, error is ~25°

---

## Recommended Implementation for tm-agent

```angelscript
// 1. Define a helper function in your code:
vec3 GetBlockMidpoint(int x, int y, int z) {
    const float baseHeightOffset = 64.0;
    return vec3(
        x * 32.0 + 16.0,
        (float(y) - (baseHeightOffset / 8.0)) * 8.0 + 4.0,
        z * 32.0 + 16.0
    );
}

// 2. After placing or removing a block, smoothly pan the camera:
void FocusOnBlock(int blockX, int blockY, int blockZ) {
    auto editor = cast<CGameCtnEditorFree>(GetApp().Editor);
    if (editor is null) return;
    
    vec3 midpoint = GetBlockMidpoint(blockX, blockY, blockZ);
    float distance = 80.0;  // ~2.5× block diagonal (40m)
    
    // Smooth animation (250ms default)
    Editor::SetCamAnimationGoTo(
        Editor::GetCurrentCamState(editor).LookUV,  // Keep current view angle
        midpoint,
        distance
    );
}

// 3. Call from your main render loop:
void Update() {
    UpdateAnimAndCamera();  // Must be called every frame for animation
    // ... rest of your code
}
```

---

## File References

- **Core camera API:** `/home/xertrov/src/openplanet/my-plugins/tm-editor-plus-plus/src/Editor/Camera.as`
- **Camera state helper:** `/home/xertrov/src/openplanet/my-plugins/tm-editor-plus-plus/src/Editor/Camera_Shared.as`
- **Coordinate math:** `/home/xertrov/src/openplanet/my-plugins/tm-editor-plus-plus/src/Editor/Math.as`
- **Camera documentation:** `/home/xertrov/src/openplanet/my-plugins/tm-control-mcp/CameraMaths.md`

