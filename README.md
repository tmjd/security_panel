This is the arduino code for my home built security system.
It was built to talk serially to another arduino (I used a Mega for the
extra serial ports) which would talk to a python script which was the real
brains of the system.  There is nothing too special here, just monitored
a keypad, talked over the serial line, monitored a motion sensor, and wrote
to an 4x20 LCD screen.
