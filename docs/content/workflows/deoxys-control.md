# Deoxys Control

<div style="text-align: center; margin: 2rem 0;">
  <div style="position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden; max-width: 100%; margin: 0 auto;">
    <iframe 
      style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;" 
      src="https://www.youtube.com/embed/EWkQHdm_uto?si=qQz0mVsXja7nM4f8" 
      title="YouTube video player" 
      frameborder="0" 
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" 
      referrerpolicy="strict-origin-when-cross-origin" 
      allowfullscreen>
    </iframe>
  </div>
</div>

## ServoBox Setup

1. Install ServoBox and configure host PC → see [Installation](../getting-started/installation.md)

2. Set up network bridging for VM to ethernet port:
   ```bash
   servobox network-setup
   ```

3. Install deoxys-control package:
   ```bash
   servobox pkg-install deoxys-control
   ```

4. Boot RT-VM:
   ```bash
   servobox start
   ```

5. Run deoxys-control:
   ```bash
   servobox run deoxys-control
   ```

## Host PC Deoxys Client

1. Clone the repository:
   ```bash
   git clone git@github.com:kvasios/deoxys_control.git
   ```

2. Follow installation instructions in `README.md` (we recommend a virtual environment with micromamba)

3. Activate the created environment and run an example:
   ```bash
   micromamba activate deoxys
   python examples/run_deoxys_with_space_mouse.py
   ```

Enjoy!

