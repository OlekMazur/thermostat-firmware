; This file is part of Thermostat Firmware.
;
; Thermostat Firmware is free software: you can redistribute it and/or
; modify it under the terms of the GNU General Public License as
; published by the Free Software Foundation, either version 3 of the
; License, or (at your option) any later version.
;
; Thermostat Firmware is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
; General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with Thermostat Firmware. If not, see <https://www.gnu.org/licenses/>.
;
; Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018 Aleksander Mazur

$include (header.asm)

; sterowanie konserwatywne - z uwzględnieniem poprzednio wyliczonych masek sterujących przekaźnikami
CONSERVATIVE_CONTROL	equ 1

; przekaźniki
RELAY_PORT		equ P1

; 1-wire
OW_PWR			equ P1.0	; One Wire Power Key - 0 włącza zasilanie 1W
OW_PARASITE		equ 21		; One Wire Parasite Power - jeśli zdefiniowane, to jest to czas pomiaru temp. na 1-wire w cyklach pętli głównej (8/225 s), a 0 na OW_PWR włącza silną jedynkę na linii danych magistrali 1W zamiast +5V na trzecim przewodzie zasilającym urządzenia magistrali 1-wire
OW_DQ			equ P3.7	; One Wire DQ - linia danych magistrali 1W

; I2C
SDA				equ P3.5
SCL				equ P3.4
; EEPROM - AT24C02 na I2C
; adres 000 -> A0, A1
I2C_EEPROM_WR	equ	10100000b
; czujnik temperatury wewnętrznej - TMP75 na I2C
; adres 000 -> 90, 91
I2C_TEMP_WR		equ	10010000b
; wyświetlacz Philips I2C 4*7seg
;I2C_DISPLAY_WR	equ 76h

;SKIP_DS18S20	equ	1
;SKIP_DS2406	equ	1
;SKIP_DS2405	equ	1
;SKIP_DS1821	equ	1
;SKIP_CTRL_TEMP	equ 1
TUNE_1WIRE		equ 1
;AT89C4051		equ	1	; mamy 2kB ROMu

$include (main.asm)
