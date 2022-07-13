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
; Copyright (c) 2022 Aleksander Mazur
;
; Obsługa nastaw w pamięci programu zamiast w EEPROM na I2C
; Alternatywa dla i2c_eeprom.asm i i2c.asm
; W firmware_*.asm używającym niniejszej alternatywy należy umieścić
;  blok nastaw pod etykietą rom_data

;===========================================================
; API

;-----------------------------------------------------------
; Inicuje odczyt nastaw spod adresu w B
; Niszczy A, C, R7
; Zwraca C=0 czyli sukces.
eeprom_read_start:
	; DPTR = #rom_data + B
	mov A, #rom_data and 0FFh
	add A, B
	mov DPL, A
	clr A
	addc A, #rom_data shr 8
	mov DPH, A
eeprom_read_stop:
	ret

;-----------------------------------------------------------
; Czyta jeden bajt z EEPROM spod adresu w B
; Zwraca C=0 i odczytany bajt w A.
eeprom_read_byte_at:
	acall eeprom_read_start
i2c_ACK_shin:
i2c_shin:
	clr A
	movc A, @A + DPTR
	inc DPTR
i2c_ACK:
	ret
