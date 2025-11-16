# GeoIK Visual Servoing

<div style="text-align: center; margin: 2rem 0;">
  <img src="../../assets/images/geoik-velctrl-demo.gif" alt="GeoIK velocity control demo" style="max-width: 100%; border-radius: 8px;">
</div>

Geometric IK-based velocity control with eye-in-hand visual servoing for Franka Emika robots. Track ArUco markers in real-time and maintain a locked end-effector-to-marker pose.

## Quick Start

### 1. Install and Run C++ Velocity Server (inside ServoBox VM)

```bash
servobox pkg-install geoik-velctrl
servobox run geoik-velctrl
```

### 2. Clone geoik-velctrl on the host PC

```bash
git clone https://github.com/kvasios/geoik-velctrl.git
cd geoik-velctrl
```

### 3. Install Python Marker Tracking (host PC)

Create environment with micromamba (or conda/mamba):

```bash
micromamba create -n marker-track python=3.10
micromamba activate marker-track
pip install -r requirements.txt
```

### 4. Run Marker Tracker (host PC)

```bash
python3 scripts/marker_track.py
```

Press `t` to start/stop tracking. The robot maintains the locked end-effector-to-marker pose as you move the marker.

## Resources

- GitHub repository: [kvasios/geoik-velctrl](https://github.com/kvasios/geoik-velctrl)
- Full documentation and custom build instructions in project README

