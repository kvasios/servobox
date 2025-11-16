# GeoIK Visual Servoing

<div style="text-align: center; margin: 2rem 0;">
  <img src="../../assets/images/geoik-velctrl-demo.gif" alt="GeoIK velocity control demo" style="max-width: 100%; border-radius: 8px;">
</div>

Geometric IK-based velocity control with eye-in-hand visual servoing for Franka Emika robots. Track ArUco markers in real-time and maintain desired end-effector-to-marker poses.

## Quick Start

### 1. Install and Run C++ Velocity Server

```bash
servobox pkg-install geoik-velctrl
servobox run geoik-velctrl <robot-ip> false vs
```

### 2. Install Python Marker Tracking

Create environment with micromamba (or conda/mamba):

```bash
micromamba create -n marker-track python=3.10
micromamba activate marker-track
pip install -r requirements.txt
```

### 3. Run Marker Tracker

```bash
python3 scripts/marker_track.py --config markers/board_4x4_4x4_50.yaml
```

Press `t` to start/stop tracking. The robot maintains the locked end-effector-to-marker pose as you move the marker.

## Resources

- GitHub repository: [kvasios/geoik-velctrl](https://github.com/kvasios/geoik-velctrl)
- Full documentation and custom build instructions in project README

