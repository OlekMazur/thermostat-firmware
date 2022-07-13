Multi-channel differential thermostat and time controller
=========================================================

This is a firmware for AT89C4051-based on-off controller with up to 8 relay outputs.
It periodically measures temperature on all digital thermometers connected to
1-wire network (DS18B20 & DS18S20, parasite power supported), reports found
sensors along with their temperatures via UART and applies them to formulas
held in EEPROM (AT24C02) in order to calculate output state.

It works in a weekly cycle and allows flexible configuration.
It can be used for HVAC, (solar) water heating, as a time controller
(e.g. starting washing machine cycle),
as watchdog for supervisor device (e.g. a router), all at once.

Supported peripheral devices
----------------------------

| Bus    | Device  | Support |
| ------ | ------- | ------- |
| 1-wire | DS18B20 | Detection, temperature measurement & reporting, output control |
| 1-wire | DS18S20 | Detection, temperature measurement & reporting, output control |
| 1-wire | DS1820  | Detection, temperature measurement & reporting, output control |
| 1-wire | DS2405  | Detection, GPIO state reporting |
| 1-wire | DS2406  | Detection, GPIO state reporting |
| I²C    | AT24C02 | Configuration storage |
| I²C    | TMP75   | Temperature measurement & reporting |
| I²C    | [7-seg 4-digit LED display module] | Clock & temperature display |

Principle of operation
----------------------

When not interrupted (or not connected to supervisor), the controller
wakes up each 8 seconds and performs following operations (simplified):
1. Initialize temperature measurement by internal sensor TMP75 on the I²C bus.
2. Initialize temperature measurement by all sensors on the 1-wire bus.
3. Clear control masks.
4. Execute time control settings suitable for current day/time
   (turn on, off, or toggle on/off configured relays).
5. Wait until all sensors finish their measurements.
6. Read temperature of internal sensor and report it.
7. Enumerate all 1-wire devices using SEARCH ROM routine and for each found device:
 - if family code is 28h (DS18B20) or 10h (DS18S20, DS1820) -- read its scratchpad
   and continue as described below under *Proceed with thermometer*.
 - if family code is 12h (DS2406) -- read and report PIO level and latch status of channel A and B, if present.
 - if family code is 05h (DS2405) -- read PIO level 8 times and report 1 if all ones, 0 otherwise.
8. Check if watchdog has just expired and switch relays configured as
   watchdog on or off, accordingly.
9. Iterate over all sensors configured in EEPROM and for each sensor
   missing on the 1-wire bus during step 7:
 - either turn on configured relays if marked as *critical*,
 - or turn off configured relays if not marked as *critical*.
10. Iterate over all formulas configured in EEPROM and apply results
    to relay control masks.
11. Apply relay control masks to the relay output port.

### Proceed with thermometer

For each enumerated 1-wire thermal sensor, after reading its scratchpad
successfully, the controller proceeds as follows:
1. Decode temperature out of scratchpad bytes and report it.
2. Enumerate all sensor-related settings in EEPROM matching given sensor
   and for each match:
 - if it refers to another sensor (differential control) -- select the
   other sensor using MATCH ROM, read its scratchpad, decode temperature
   and subtract it from decoded temperature of the basic sensor;
   use subtracted temperature instead of absolute one in further computations.
 - find temperature threshold and hysteresis appropriate for current day/time.
 - compare actual temperature (absolute or differential) agaist the threshold
   and threshold minus hysteresis and establish required action according
   to heating/colling flag, that is: whether to switch relays on, off or
   leave them alone (within hysteresis).
 - apply action to direct (relays) and indirect (intermediate) control masks.
 - mark entry as used (sensor present) so that it is not treated as
   missing in step 9 above.

### Logic

The same relays may be refered to by many setting blocks. There even
may be many setting blocks for the same sensor. The controller uses
separate masks for switching relays on and off. In case of a conflict,
switching on takes precedence over switching off. So by default it
applies OR function. In order to use AND function there is a separate
pair of indirect control masks which refer to 8 virtual relays.
Each sensor-related block of settings can control both a mask of relays
and one particular virtual relay. During step 10 (above) each block
of indirect control formulas performs AND on all masked virtual relays
and forwards result to relay control masks.

Configuration in EEPROM
-----------------------

Structure of configuration data in EEPROM (max. 256 B) follows.

| Address | Bytes  | Description |
| -------:| ------:| ----------- |
| 0       | 1      | Address of timer daily program for Sunday |
| 1       | 1      | Address of timer daily program for Monday |
| 2       | 1      | Address of timer daily program for Tuesday |
| 3       | 1      | Address of timer daily program for Wednesday |
| 4       | 1      | Address of timer daily program for Thursday |
| 5       | 1      | Address of timer daily program for Friday |
| 6       | 1      | Address of timer daily program for Saturday |
| 7       | 1      | Watchdog relays mask |
| 8       | 1      | mn = count of *functions* (high nibble, m) and *formulas* (low nibble, n) |
| 9       | m*16   | *Functions* |
| 9+m*16  | n*3    | *Formulas* |
| 9+m*16+n*3 | 0    | End |

### Function structure

| Offset  | Bytes  | Description |
| -------:| ------:| ----------- |
| 0       | 6      | Middle part of 1-wire sensor ID (no family code, no CRC-8) to match |
| 6       | 1      | 0 for absolute temperature control, otherwise -- in case of differential control -- address of middle part of related 1-wire sensor ID (the temperature of which should be subtracted from this one) |
| 7       | 1      | Flags (see below) |
| 8       | 1      | Relay mask |
| 9       | 1      | Address of thermal daily program for Sunday |
| 10      | 1      | Address of thermal daily program for Monday |
| 11      | 1      | Address of thermal daily program for Tuesday |
| 12      | 1      | Address of thermal daily program for Wednesday |
| 13      | 1      | Address of thermal daily program for Thursday |
| 14      | 1      | Address of thermal daily program for Friday |
| 15      | 1      | Address of thermal daily program for Saturday |

#### Function flags

| Bit | Description |
| ---:| ----------- |
| 7   | Cooling (1) or heating (0) |
| 6   | Critical function -- if set and no matching sensor is present, relays will be switched on |
| 5   | Display flag -- if set, temperature will be shown on attached display module |
| 4   | Reserved |
| 3   | Indirect control -- if set, bits 2-0 contain index of virtual relay to control (along with relay mask) |
| 2-0 | Number of virtual relay, meaningful if bit 3 is set |

### Formula structure

| Offset  | Bytes  | Description |
| -------:| ------:| ----------- |
| 0       | 1      | Mask of virtual relays to check |
| 1       | 1      | Mask of virtual relays to control (cascade) |
| 2       | 1      | Mask of actual relays to control |

If all masked virtual relays (from mask @ 0) are to be turned on,
virtual relays from mask @ 1 and actual relays from mask @ 2 will be turned on.

If all masked virtual relays (from mask @ 0) are to be turned off,
virtual relays from mask @ 1 and actual relays from mask @ 2 will be turned off.

### Daily program

Daily programs are divided into 2 parts. First part contains a list of
time ranges. Each range is given by its beginning: hour and minute in BCD
(2 bytes). The last range has additionally the most significant bit of
hour (first byte) set, so it must be masked out. Ranges must be sorted
in ascending order. Beginning of next range is the end of previous range.
Beginning of the first range is the end of the last range.

Immediately after the first part goes the second part which contains
3-byte long control block for each range present in the first part.
Format of these control blocks differ between timer and thermal programs.

#### Control block of timer program

| Offset  | Bytes  | Description |
| -------:| ------:| ----------- |
| 0       | 1      | Mask of relays to switch on |
| 1       | 1      | Mask of relays to switch off |
| 2       | 1      | Mask of relays to toggle on/off once |

#### Control block of thermal program

| Offset  | Bytes  | Description | Format |
| -------:| ------:| ----------- | ------ |
| 0       | 2      | Temperature in °C | fixed-point 8.8 bits |
| 2       | 1      | Hysteresis to be subtracted from temperature | fixed-point 4.4 bits |

## Example

Assume we have just 3 sensors and 4 devices:
* Room temperature sensor (ID FF0F31641408), which should control central heating system (relay #1)
* Temperature sensor at one of solar panel collectors (ID FF0318C11708)
* Temperature sensor inside potable water tank (ID FFAF44B31608)
* A pump which pumps a heat transfer fluid through panels and heat exchanger inside the storage tank (relay #4)
* A buzzer (output #7)
* Watchdog reset output (relay #2, normally closed)

For simplicity let's use the same settings for all days of the week.

First we'll set up a timer program to turn off all unused outputs (and used ones too).
It will have just 1 time range starting at 00:00 and turning off everything but output #0
(because P1.0 serves as 1-wire parasite power control):
```
80 00 00 FE 00
```

Now let's create a thermal program for central heating.

| From  | Temperature | Hysteresis |
| ----- | -----------:| ----------:|
| 07:00 | 20.5 °C     | 0.5 °C     |
| 07:30 | 18.5 °C     | 0.5 °C     |
| 19:30 | 19.5 °C     | 0.5 °C     |
| 21:30 | 20.5 °C     | 0.5 °C     |
| 22:00 | 19.5 °C     | 0.5 °C     |
```
07 00 07 30 19 30 21 30 A2 00
14 80 08 12 80 08 13 80 08 14 80 08 13 80 08
```

We want to run the solar water heating pump when:
- difference between panels and tank is more than 12 °C,
  but only when panels exceed 40 °C,
- or when panels exceed 96 °C,
- or when stored water exceeds 96 °C.

For this purpose we need next 3 thermal programs: for detecting whether
12 °C, 40 °C and 96 °C is exceeded. Let's use 2 °C of hysteresis in each case.
```
80 00 0C 00 20
80 00 28 00 20
80 00 60 00 20
```

Now 5 *functions*.
First goes the heating configuration: ID of room sensor, 00 for absolute
temperature control, all flags zeroed (heating program, not critical, no display,
no indirect control), relays mask = 02 (output #1), xx need to be replaced
with the address of appropriate thermal program shown above.
```
FF0F31641408 00 00 02 xxxxxxxxxxxxxx
```
Next one checks if solar panels have more than 40 °C.
This alone is not enough for switching on any device, so relay mask is 00,
but we use virtual relay #0.
Note that this (and all remaining thermal programs) will be cooling,
not heating (we're cooling the panels, not heating the tank).
```
FF0318C11708 00 88 00 xxxxxxxxxxxxxx
```
Next one is monitoring if the difference between solar panels and water in the tank
is more than 12 °C.
Let's use next free virtual relay (#1).
yy needs to be replaced with the address of a *function* where ID
of the sensor in the storage tank is given.
```
FF0318C11708 yy 89 00 xxxxxxxxxxxxxx
```
Next one is a safety measure against heat transfer fluid exceeding 96 °C.
This one switches the pump (and a buzzer) on directly (mask 90).
Let it be a critical function so the pump and buzzer are switched on
also when the sensor is broken or unreachable.
```
FF0318C11708 00 C0 90 xxxxxxxxxxxxxx
```
Now similar safety measure, but against water in the tank exceeding 96 °C.
Let's additionally set the display flag so a display module shows
the temperature of potable hot water (only).
```
FFAF44B31608 00 E0 90 xxxxxxxxxxxxxx
```

In order to actually switch the pump on under normal conditions we need
one *formula* to combine the state of virtual relays #0 and #1 (mask 03)
in order to control the pump at output #4 (mask 10).
```
03 00 10
```

Put it all together and we get 137 B to write into EEPROM:
```
61 61 61 61 61 61 61 04 51 FF 0F 31 64 14 08 00
00 02 6B 6B 6B 6B 6B 6B 6B FF 03 18 C1 17 08 00
88 00 66 66 66 66 66 66 66 FF 03 18 C1 17 08 49
89 00 84 84 84 84 84 84 84 FF 03 18 C1 17 08 00
C0 90 5C 5C 5C 5C 5C 5C 5C FF AF 44 B3 16 08 00
E0 90 5C 5C 5C 5C 5C 5C 5C 03 00 10 80 00 60 00
20 80 00 00 FE 00 80 00 28 00 20 07 00 07 30 19
30 21 30 A2 00 14 80 08 12 80 08 13 80 08 14 80
08 13 80 08 80 00 0C 00 20
```

Supervisor interface (UART)
---------------------------

The controller uses UART (9600-8-N-1) for 2-way communication with a supervisor.

### Output (controller -> supervisor)

The controller periodically sends reports to supervisor.

Examples:
```
02;14:00:00;T=21.5;28FF04053716004E=18.0625;28FFC4718316002D=18.3125;28FF0018C11700A8=47.3125;28FF581964140095=17.25;28FF0031641400C1=22.25;28FFA844B316000A=33.625;28FF000F3716004E=18.0625;FE&10|10=11;
01;13:59:59;T=21.9375;28FFBF71B316042D!18;28FF0F71B316042D!20;28FF040F3716044E=18.3125;28FFAF44B316080A=!;28FF0018C11700A8=85;28FF581964140095=13.875;28FFC4718316002D=14.25;28FF0031641400C1=20.125;FE&10|00=11;
```
Syntax:
```
<CR><wd>;<hh>:<mm>:<ss>;(<device>(=<temp>)?;)*(E;)?<automask>&<offmask>|<onmask>=<outmask>;<LF>
```
Where:
| Part        | Meaning |
| ----------- | ------- |
| \<CR>       | Carriage Return = ASCII #13. |
| \<wd>       | Day of the week (00 = Sunday, 06 = Saturday). |
| \<hh>       | Hour (00-23). |
| \<mm>       | Minute (00-59). |
| \<ss>       | Second (00-59). |
| \<device>   | ID of a device. For TMP75 this is just **T**. In other cases it is a 64-bit serial number of found 1-wire device, using byte order as discovered by SEARCH ROM routine (family code first, CRC-8 last). In case of SEARCH ROM error the ID is terminated with exclamation **!** followed by number of correctly discovered bits so far. Note that in case of EEPROM failure **E** is reported; it looks like a device with ID = **E** without value. |
| \<temp>     | Temperature in °C, or exclamation **!** in case of an error (e.g. failed to read scratchpad). |
| \<automask> | Mask of all relays controlled automatically (= encountered in the configuration EEPROM). |
| \<offmask>  | Mask of relays to be switched off (0 = switch off, 1 = don't switch off). |
| \<onmask>   | Mask of relays to be switched on (1 = switch on, 0 = don't switch on). |
| \<outmask>  | Final state of relay outputs (after applying computed off & on masks). |
| \<LF>       | Line Feed = ASCII #10. |

### Input (supervisor -> controller)

Supervisor can send any of the following commands to the controller
anytime between \<LF> and \<CR> (that is, when the controller is idle).
In case a command is received during sending report from the controller
to supervisor, the controller continues to send its report, and then
sends a dot (.) as a notification that a command has been skipped.
Supervisor must wait for response before issuing next command.

| Command | Description | Result |
| ------- | ----------- | ------ |
| I       | Send I²C *START* | @ on success, ! on error |
| S       | Send I²C *STOP* | @ |
| A       | Send I²C *ACK* | @ |
| N       | Send I²C *NAK* | @ |
| Wxx     | Send byte xx (hex) to I²C | @ if acknowledged, ! on error |
| R       | Receive a byte from I²C | xx (received byte in hex) |
| i       | Do 1-wire *RESET* | @ on success, ! on error |
| wxx     | Send byte xx (hex) over 1-wire bus | @ |
| r       | Receive a byte from 1-wire bus | xx (received byte in hex) |
| t       | Restore 1-wire mode of DS1821 (16 pulses with power down) | @ on success, ! on error |
| &xx     | Switch off relays which have 0 in given mask xx (hex) | @ |
| \|xx    | Switch on relays which have 1 in given mask xx (hex) | @ |
| !       | Wake up and perform next measuring/reporting/control cycle | a report |
| \<space> | Reset watchdog | \<space> |
| bxx     | Read RAM byte at xx (hex) | yy (byte from RAM, hex) |
| Bxx     | Write byte xx (hex) to RAM at the address last used with **b** command (above) | @ |
| E       | Get address of configuration EEPROM on the I²C bus | xx (value of I2C_EEPROM_WR), or **!** if it's just A0 = the default |

It is recommended that supervisor resets watchdog by sending space
after each incoming report. Not doing this for `WATCHDOG_MAX` = 22 times
in a row (normally ~3 minutes) causes toggling relays configured in
EEPROM as watchdog.

**b** and **B** commands are intended for reading and/or writing selected
variables. Their locations in RAM are extracted from assembly listing
at the end of the build process and provided in *firmware.h* header file.

| Variable                 | Example address | Description       |
| ------------------------ | ---------------:| ----------------- |
| API_global_rtcwd_weekday | 0x22            | Watchdog time - day of week (00-06) |
| API_global_rtcwd_hours   | 0x23            | Watchdog time - hour (00-23) |
| API_global_rtcwd_minutes | 0x24            | Watchdog time - minute (00-59) |
| API_global_rtcwd_seconds | 0x25            | Watchdog time - second (00-59) |
| API_global_rtc_weekday   | 0x26            | Current time - day of week (00-06) |
| API_global_rtc_hours     | 0x27            | Current time - hour (00-23) |
| API_global_rtc_minutes   | 0x28            | Current time - minute (00-59) |
| API_global_rtc_seconds   | 0x29            | Current time - second (00-59) |
| API_global_clock_settings_index | 0x2B     | Clock settings index |

*Current time* is used in reports sent to UART and for applying
appropriate part of configuration held in EEPROM. Supervisor should
monitor time in reports received from UART and set *current time*
variables accordingly as soon as it detects significant skew.

If most significant bit of `API_global_rtcwd_weekday` is set, it means
that watchdog was activated, and *watchdog time* holds a copy of
*current time* made at that moment.
When watchdog fires, the controller overwrites *watchdog time* and sets
its most significant bit to 1 **only** if that bit was cleared.
It is the responsibility of supervisor to clear that bit after reading
*watchdog time*.

Note that variables related to time use BCD format, so despite **b**
and **B** commands use hexadecimal values, they look like decimal.

*Clock settings index* is the address of part of settings in EEPROM
which were applied last time for time control. This is used for
switching on or off relays configured as "toggle" (i.e. start cycle of
a washing machine). Supervisor needs to zero this byte whenever it changes
`API_global_rtc_weekday`.

## Examples

Read scratchpad of 1-wire sensor with ID 28971DA80000000F:
```
iw55w28w97w1DwA8w00w00w00w0FwBErrrrrrrr
```
Write 4E,7F,7F,7F to its scratchpad:
```
iw55w28w97w1DwA8w00w00w00w0Fw4Ew7Fw7Fw7F
```
Read ROM -- makes sense when there is only 1 sensor on the 1-wire bus:
```
iw33rrrrrrrr
```

DS2406 - Channel Access (F5), read PIO-A, reset alarm, CRC-16
```
iw55w12w8Ew6Aw45w00w00w00wB5wF5wC5wFFr
```

Restore 1-wire mode of DS1821 (alone on the bus) persistently:
```
tiw0Cw41
```
Measure temperature with DS1821:
```
iwEEiwAAriwA0rriw41iwA0rr
```
The above reads 3 values: TEMP_READ, COUNT_REMAIN and COUNT_PER_C.

temperature = TEMP_READ - 0.5 + (COUNT_PER_C - COUNT_REMAIN) / COUNT_PER_C

Read 8 bytes from the beginning of AT24C02 (address A0 on the I²C bus):
```
IWA0W00IWA1RARARARARARARARNS
```

Write the 137 B of example configuration (above) to EEPROM
(assuming I²C address A0):
```
IWA0W00W61W61W61W61W61W61W61W04S
IWA0W08W51WFFW0FW31W64W14W08W00S
IWA0W10W00W02W6BW6BW6BW6BW6BW6BS
IWA0W18W6BWFFW03W18WC1W17W08W00S
IWA0W20W88W00W66W66W66W66W66W66S
IWA0W28W66WFFW03W18WC1W17W08W49S
IWA0W30W89W00W84W84W84W84W84W84S
IWA0W38W84WFFW03W18WC1W17W08W00S
IWA0W40WC0W90W5CW5CW5CW5CW5CW5CS
IWA0W48W5CWFFWAFW44WB3W16W08W00S
IWA0W50WE0W90W5CW5CW5CW5CW5CW5CS
IWA0W58W5CW03W00W10W80W00W60W00S
IWA0W60W20W80W00W00WFEW00W80W00S
IWA0W68W28W00W20W07W00W07W30W19S
IWA0W70W30W21W30WA2W00W14W80W08S
IWA0W78W12W80W08W13W80W08W14W80S
IWA0W80W08W13W80W08W80W00W0CW00S
IWA0W88W20S
```
Note that the controller just gives access to low-level I²C communications
so supervisor is responsible for conformance with AT24C02 specifications,
like writing each page of 8 bytes separately. Also, after sending each
*STOP*, supervisor needs either to sleep for the time required by the EEPROM
to finish programming the page (5 ms) or use acknowledge polling --
**WA0** command will fail (return **!** instead of @) until internal
write cycle is complete.

Test [7-seg 4-digit LED display module]:
```
IW76W09S
```

Set RTC to Wednesday (3) noon (12:00) and reset *clock settings index*
(assuming RAM locations as in the *Example address* above):
```
b26B03b27B12b28B00b29B00b2BB00
```

Build-time options
------------------

The firmware can be assembled using [asem-51].

There are several options for defining how the peripherals are connected
to the microcontroller and what features should be included in the firmware.

### SDA, SCL
Ports where I²C bus is connected to (with external pull-ups).
If undefined, there is no I²C bus support.

### I2C_EEPROM_WR
Address (for writing = with least significat bit cleared) of AT24C02 on the I²C bus.

### I2C_TEMP_WR
Address (for writing) of TMP75 on the I²C bus.
If undefined, there is no TMP75 support, what saves 97 B.

### I2C_DISPLAY_WR
Address (for writing) of [7-seg 4-digit LED display module] on the I²C bus.

![Display]

If undefined, there is no display module support, what saves 201 B.

### OW_PARASITE
If defined, then 1-wire bus is parasite-powered
(OW_PWR=0 enables strong pull-up on the bus).

If undefined, 1-wire devices are powered independently from the data line
(OW_PWR=1 turns on separate power supply for 1-wire devices).

Value is the time of temperature measurement in 8/225 s. Set it to 21 for ~750 ms.

### OW_PWR
Port which controls power of 1-wire devices; see OW_PARASITE.

### OW_DQ
Data line of the 1-wire bus.

### RELAY_PORT
8-bit port which controls relays.

### CONTROL_NEGATIVE
If defined, 0 switches on a relay, otherwise (by default) 1 switches on a relay.

Note that this affects only the interface between the controller and a relay;
it doesn't affect neither the UART API nor configuration in EEPROM,
where 1 is always on and 0 is always off.

### AT89C4051
Whether we have 4kB of program memory. If defined, wider jump instructions are used.

### SKIP_DS18S20
If defined, cuts off DS18S20 support, what saves 43 B.

### SKIP_DS1821
If defined, cuts off support for 't' command specific for DS1821, what saves 19 B.

Meaningless when OW_PARASITE is defined.

### SKIP_DS2406
If defined, cuts off DS2406 support, what saves 72 B.

### SKIP_CTRL_TEMP
If defined, cuts off temperature control, what saves 179 B.

Watchdog and time control remains, but thermostat works as if all thermometers are missing on the bus.

### SKIP_UART
If defined, cuts off UART support (both input & output), what saves 506 B.

### TUNE_1WIRE
If defined, enables run-time tuning of delays used by 1-wire master, what takes 24 B more.

The following parameters may be tuned (with the help of **b** and **B** commands):

| Parameter | Default value | Description |
| --------- | -------------:| ----------- |
| t<sub>RST</sub> | 24 | Timeout after pulling line low in order to reset and waiting 15 µs before presence pulse from devices on the bus |
| t<sub>LOW</sub> | 1  | Time of pulling the line low by us in order to start a read or write cycle |
| t<sub>WR</sub>  | 51 | Delay after sending value of a bit during write cycle |
| t<sub>DSO</sub> | 9  | Delay after pulling the line low before sampling the line |
| t<sub>RD</sub>  | 41 | Delay after sampling the line |
| `SEARCH_DELAY`  | 0  | Extra delay before read/write cycles during SEARCH ROM routine |

This is experimental feature, so addresses of these parameters are not part the API and actual addresses in RAM must be checked in the listing.

| Constraint | Reason |
| ---------- | ------ |
| t<sub>LOW</sub> + t<sub>WR</sub> = 52 | Write cycle taking at least 60 µs |
| t<sub>LOW</sub> + t<sub>DSO</sub> + t<sub>RD</sub> = 51 | Read cycle taking at least 60 µs |
| t<sub>LOW</sub> + t<sub>DSO</sub> = 10 | Sampling the line before 15 µs |

Values are in DJNZ execution times, that is 24 / 22118400 Hz = 1.085 µs.

### CONSERVATIVE_CONTROL
If defined, output control masks (both for switching relays on and off)
are combined with values computed previously, before application to actual output ports.

This avoids switching off (or on) devices unnecessarily in case of glitches
on the 1-wire bus (or unstable bus) at the price of extended response time.

### MATCH_ON_SEARCH_FAILURE
If defined, in case of SEARCH ROM error (unstable 1-wire bus)
the controller tries to read temperatures of known sensors
using IDs stored in EEPROM, with MATCH ROM command instead.

This workaround works for DS18B20 only because family code is not held
in EEPROM so a hardcoded 28h is used.

This extra routine takes 64 B.

Hardware variants
-----------------

### Example 1

Let's say we want to connect:
- a typical opto-isolated 4-channel relay module (using inverted logic,
  so we need CONTROL_NEGATIVE) to P1.7-4,
- a buzzer -- directly to P1.3,
- AT24C02 & TMP75 to P3.5 (SDA) and P3.4 (SCL),
- a network of DS18B20 & DS18S20 parasite-powered thermometers to P3.7,
  with BC557-keyed strong pull-up controlled via P3.2.

![Relays] ![PCB top] ![PCB bottom]

```
CONSERVATIVE_CONTROL equ	1
CONTROL_NEGATIVE     equ	1
RELAY_PORT           equ	P1
OW_PWR               equ	P3.2
OW_PARASITE          equ	21
OW_DQ                equ	P3.7
SDA                  equ	P3.5
SCL                  equ	P3.4
I2C_EEPROM_WR        equ	10100000b
I2C_TEMP_WR          equ	10010000b
```

This creates 2046 B of firmware, so it even fits AT89C2051, but note
that contrary to AT89C4051 that part misses brown-out reset.

### Example 2

Instead of opto-isolated relay module we may use ULN2003 + up to 7 relays.

![PCB2] ![PCB3] ![PCB4] ![PCB5]

```
CONSERVATIVE_CONTROL equ	1
RELAY_PORT           equ	P1
OW_PWR               equ	P1.0
OW_PARASITE          equ	21
OW_DQ                equ	P3.7
SDA                  equ	P3.5
SCL                  equ	P3.4
I2C_EEPROM_WR        equ	10100000b
I2C_TEMP_WR          equ	10010000b
TUNE_1WIRE           equ	1
```

2041 B this time.

### Example 3

No parasite power, but capable of resetting DS1821 to 1-wire mode
from standalone thermostat mode (using **t** command).
Both I²C and 1-wire buses on P1, so single resistor ladder provides
all the pull-ups.

```
CONSERVATIVE_CONTROL equ	1
RELAY_PORT           equ	P1
OW_PWR               equ	P1.0
OW_DQ                equ	P1.1
SDA                  equ	P1.2
SCL                  equ	P1.3
I2C_EEPROM_WR        equ	10100000b
I2C_TEMP_WR          equ	10010000b
```

2027 B.

License
=======

This file is part of Thermostat Firmware.

Thermostat Firmware is free software: you can redistribute it and/or
modify it under the terms of the GNU General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

Thermostat Firmware is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the [GNU General Public License]
along with Thermostat Firmware. If not, see <https://www.gnu.org/licenses/>.

[7-seg 4-digit LED display module]: https://www.elektroda.pl/rtvforum/topic117391.html
[Display]: img/LED_module.jpg
[PCB top]: img/PCB_A.jpg
[PCB bottom]: img/PCB_R.jpg
[Relays]: img/relays.jpg
[PCB2]: img/PCB2_A.jpg
[PCB3]: img/PCB3_A.jpg
[PCB4]: img/PCB4_A.jpg
[PCB5]: img/PCB5_A.jpg
[GNU General Public License]: LICENSE.md
[asem-51]: http://plit.de/asem-51
