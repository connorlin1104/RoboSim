# RoboSim

A VEX Robotics Simulator built with **RealityKit** and **SwiftUI** for iOS / iPadOS / macOS.

## Overview

RoboSim simulates a VEX robot driving on a regulation-sized field. The robot is a rigid-body physics object you control with on-screen twin joysticks, and you can switch between a stationary third-person view and a follow-cam first-person view.

## Features

- 12' × 12' (3.65m) field with a static physics floor
- Cube robot proxy (0.3m) with dynamic `PhysicsBodyComponent`
- Twin on-screen joysticks
  - Left stick → forward / reverse (linear impulse)
  - Right stick → turning (angular impulse)
- Two camera modes
  - **3rd Person** — fixed perspective camera at `(0, 5, 4)` with orbit controls
  - **1st Person** — RealityKit `System` updates the camera every frame to follow 0.6m behind and 0.3m above the robot
- Upright stabilization via a corrective angular impulse (`cross(currentUp, worldUp)`) so the robot resists tipping without freezing yaw velocity
- Auto-respawn when the robot falls below the field

## Architecture

All code currently lives in `RoboSim/ContentView.swift` and uses:

- `RealityView` with `make` / `update` closures
- A custom `FollowCameraSystem` and `FollowCameraComponent` (RealityKit ECS) for the follow cam
- A `DriveInput` reference type bridging SwiftUI joystick state into a `SceneEvents.Update` subscription that applies impulses each frame

## Requirements

- Xcode 15+
- iOS 18 / iPadOS 18 / macOS 15 (or newer) deployment targets
- Swift 5.9+

## Build & Run

1. Open `RoboSim.xcodeproj` in Xcode
2. Select a simulator or device
3. Press **Cmd-R**

## Roadmap

- [ ] Tune drive feel — cap max linear/angular speed
- [ ] Replace cube proxy with a real VEX robot model
- [ ] Add field elements (goals, game pieces)
- [ ] Scoring / autonomous routine support
- [ ] Multiplayer / replay

## License

TBD
