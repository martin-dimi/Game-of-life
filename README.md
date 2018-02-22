# Game-of-life

## Introduction
This is Conway's version of Game of life. Made as an assignment for Concurrent Computing.  
The simulation is designed to work on xCORE-200 eXplorerKIT.

## Functionality
**The simulation is written in XC.**  
There are 6 available boards/pictures - **16x16, 64x64, 128x128, 512x512 and 1024x1024**.  
Upon F13 button press, the program will distribute the the board within **4 or 8 "workers"** working on  
**different threads**.
It includes:
* Button Listener 
* Orientation Listener
* LED trigger
* Synchronised thread communication using channels

## Examples
<img src="images/64x64.png" height="128" width="128"> **-----**64x64, 100 Iterations, Time taken:6020 miliseconds**---->** <img src="images/64out.png" height="128" width="128">  
<img src="images/128x128.png" height="128" width="128"> **---**128x128, 100 Iterations, Time taken:17935 miliseconds**--->** <img src="images/128out.png" height="128" width="128">  

## Analysis
Beneficial factors:
* Direct parallel communication between workers, so that they don’t trigger a deadlock.
* Packing of 8 cells into a single byte (bit packing) within DataInStream()
* Minimal data transfer across the workers and the distributor
* Workers working synchronized
  
Limitations:
* The number of tiles: with more tiles we could have more workers processing in parallel
* The need for data transfer between distributor and workers whenever a data export is requested

