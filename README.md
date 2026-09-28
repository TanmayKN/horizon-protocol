# The Horizon Protocol

A first-person military shooter made in **Godot 4.7** by **Tanmay (TanmayKN)**.

You are **Vance**, a Vanguard operative sent alone into the Kranor mountains to stop Colonel Raskov and the Horizon Protocol. Sneak through a forest outpost, break into a logistics yard, survive an ambush in the dark, escape through the mountain pass in a truck and storm Raskov's command bunker.

## The mission

| Segment | Name | What happens |
|---|---|---|
| 1 | **The Perimeter Breach** (Timberline Outpost) | Cut through the fence in the rain, take out the guard tower sniper, sneak down past the logging yard |
| 2 | **Kranor Logistics Yard** | Get through the container maze, climb the stacks, break into the admin block and download the intel |
| 3 | **Blackout** | The comms get jammed and the lights go out. Fight your way out along the catwalks and jump from the window |
| 4 | **The Escape Vector** (Mountain Access Pass) | Ride in the back of the truck shooting the technicals chasing you. When Sgt. Reyes gets hit, **you drive**. Dodge the rockfall |
| 5 | **Vanguard Command Bunker** | Breach the bunker, reach the server room, face Raskov and take the drive. Then the helicopter lands... and Colonel Hale steps out |
| 6 | **The Buyer** (Vostok Airfield, dawn) | Hale betrayed you. Sneak onto his airfield, wreck the tower radar so his jet can't leave, rescue Reyes from Hangar 1, then take down Hale at the jet |

The story has full cutscenes (hold **Space** to skip) and every line is voiced. Find all 8 intel documents for the best ending.

## Weapons and ammo

You have **5 weapon slots** (keys 1-5). You start with a suppressed **M4 carbine** (5.56), a **P226 pistol** (9mm) and a **combat knife** (silent, one hit up close), plus 2 empty slots. Any weapon can go in any slot.

- Every enemy you take down **drops his gun**. Walk up to it and press **F** to take it: it goes into a free slot, or swaps with the gun in your hands if all 5 are full. Press **G** to drop a weapon. Kranor soldiers carry the **AK-74** (7.62), and their snipers carry a scoped **SVD marksman rifle** (.308) that zooms in when you aim.
- Ammo pickups are floating, spinning ammo cans with a coloured glow: **green** = 5.56, **orange** = 7.62, **red** = .308, **purple** = 9mm. Intel is a red folder with a blue glow.
- Ammo is separate for each calibre and **you have to pick it up**: soldiers drop ammo pouches, and each checkpoint has a supply cache with 5.56 and 9mm. Press F on a gun you already have to take its ammo.
- Your M4 is suppressed, so only nearby enemies hear it. The captured guns are **loud** and alert everyone around.

The data you download at Kranor tells you where the Horizon Protocol is hidden and gives you the vault code. Everything you learn is saved in **Esc → Intel & Story**. Find all **6 hidden intel documents** to find out who the traitor 'H' is (it changes the ending).

Find the **6 hidden intel documents** and listen in on the guards' conversations to learn the full story.

## Controls

| Key | Action |
|---|---|
| W A S D / arrow keys | Move |
| Mouse | Look |
| Left click | Shoot |
| Right click | Aim down sights |
| R | Reload |
| 1 - 5 or mouse wheel | Switch between your 5 weapon slots |
| G | Drop the weapon in your hands |
| Shift | Sprint (uses stamina). Sprint + C to slide |
| C / Ctrl | Crouch |
| Z | Prone |
| Space | Jump (and jump off a ladder) |
| Q / E | Lean left / right |
| F | Interact (cut fences, download intel, pick up guns) |
| W / S on a ladder | Climb up / down |
| W / S / A / D in the truck | Accelerate / brake / steer |
| V | Switch between first and third person |
| Esc | Pause menu (controls, difficulty, mouse sensitivity, restart) |

You can change any key in **Esc → Controls**: click a key and press the new one.

## Download and play (no Godot needed)

- **Mac:** [TheHorizonProtocol.dmg](https://github.com/TanmayKN/horizon-protocol/raw/main/downloads/TheHorizonProtocol.dmg). Open it, drag the game into Applications, then right-click the game and choose **Open** the first time.
- **Windows:** [TheHorizonProtocol-Windows.zip](https://github.com/TanmayKN/horizon-protocol/raw/main/downloads/TheHorizonProtocol-Windows.zip). Unzip it and run `TheHorizonProtocol.exe`. If SmartScreen warns you, click **More info** then **Run anyway**.

## How to play it

1. Install **Godot 4.7** (free) from [godotengine.org](https://godotengine.org/download).
2. Download this repo: click **Code → Download ZIP** and unzip it, or run
   `git clone https://github.com/TanmayKN/horizon-protocol.git`
3. Open Godot, click **Import**, and choose the `project.godot` file in the folder.
4. Press **Play** (F5, or Cmd+B on Mac). The first launch takes a minute while Godot imports the models and textures.

## What's inside

```
scenes/         main scene
scripts/        all game code (player, weapons, enemy AI, HUD, mission/story)
scripts/world/  the five levels, terrain, ladders, power lines
shaders/        terrain, water, clouds, vehicle paint
assets/models/  3D models (.glb) made in Blender: soldiers, Raskov, truck,
                technicals, helicopter, rifle, transformer, buildings, props
assets/textures/ realistic PBR textures (albedo / normal / roughness)
tools/          scripts that make the models and textures
```

The whole world is built in code, so there are no big hand-made scene files.

### Remaking the models and textures (optional)

You only need this if you want to change the art. Playing the game doesn't need it.

- **Models:** run `tools/blender_assets.py` with Blender's Python (Blender 4.5):
  `python tools/blender_assets.py soldier supply_truck` (or leave out the names to build all of them). The `.glb` files are written to `assets/models/`.
- **Textures:** `python tools/gen_textures.py` (needs `numpy` and `Pillow`).

## Credits

Game design, story and direction: **Tanmay (TanmayKN)**
Built with Godot Engine, Jolt Physics and Blender.
Voices generated with the Piper text-to-speech engine (LibriTTS voice, CC BY 4.0). Sound effects, music and textures are generated from code in `tools/`.

© 2026 Tanmay. All rights reserved.
