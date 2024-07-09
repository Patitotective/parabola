# grado
This website implements 2D cinematic simulations using `matter-js`.

## Features
- You can change the canon's initial velocity and angle with the mouse or keyboard
- You can see the total time and height in real time
- You can see the position, velocity and time of any point in the trajectory as well as the first, highest and last point
- You can see the velocity magnitude with arrows in real time

## Building
To build the frontend, run:
```
nimble frontend
```
It will generate a `frontend.js` file in `public/js`.

To build the backend, run:
```
nimble build
```
It will generate a binary `app` (or `app.exe`) that will host the page locally.

If you want to build and run the backend, run:
```
nimble run
```

