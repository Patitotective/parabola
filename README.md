# Parabola
A static projectile motion simulator and calculator website built with Nim.

![image](https://github.com/user-attachments/assets/8888a276-4ceb-478a-bd7c-572e0d2770c8)

It uses [matter-js](https://github.com/liabru/matter-js/) for the physics engine, [KaTex](https://github.com/KaTeX/KaTeX) to render the math equations, [Karax](https://github.com/karaxnim/karax/) as a frontend framework, [Sass](https://sass-lang.com/), [Spectre.css](https://github.com/picturepan2/spectre) as a CSS framework and [ni18n](https://github.com/heinthanth/ni18n) to manage translations (internationalization).

## Features
- Includes the real-time equations with the procedures for the time of flight, maximum height, maximum range, velocity components and the position and velocity of any point in the trajectory.
- You can change the initial speed, height and angle of the canon, as well as the gravity of the simulation.
- Includes the gravity of the solar system planets including Pluto and the moon as presets.
- You can add up to 16 different trajectories that can have different initial speed, height, angle and gravity.
- You can pause and restart the simulation.
- You can drag any bullet or block in the simulation.
- English and Spanish translations.
- You can slow down and speed up the simulation from the settings.
- You can limit the amount of bullets there can be in screen from the settings.
- You can hide the equations' solutions and procedures from the settings.
- You can lock the settings by switching to Student Mode from the settings, this is useful if you want to lend your computer to your students but hide the equations' solutions and/or procedures.

![image](https://github.com/user-attachments/assets/3ba3ebac-781f-4079-9ae0-3d9afffe2054)

## Building From Source
To build the website yourself first clone this repository:
```sh
git clone https://github.com/Patitotective/parabola
cd parabola
```
Install the dependencies:
```sh
git submodule update --init # Initialize submodules
nimble install -d -y
```
And finally build the CSS and Javascript with the following command:
```sh
nimble htmlpage # Use rhtmlpage for a release version
```
You will now have a `dist` folder containing everything necessary for this static website, meaning all the resources (including the JS libraries) are in that folder. You won't need internet connection!

## Post Processing
These tools can be used in the final files to shrink the file size and provide backward compatibility with older Javascript:
1. Babel Formatter with https://codifyformatter.org/babel-formatter.
2. JS Minifier with https://www.toptal.com/developers/javascript-minifier.
3. HTML Minfier with https://codebeautify.org/minify-html

## About
- GitHub: https://github.com/Patitotective/parabola.
- Discord: https://discord.gg/U23ZQMsvwc.
- Live Website: [https://patitotective.github.io/kdl-nim/](https://patitotective.github.io/parabola/).

Contact me:
- Discord: **Patitotective#0127**.
- Email: **cristobalriaga@gmail.com**.
