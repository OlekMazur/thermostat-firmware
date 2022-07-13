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

; Obsługa czujnika temperatury TMP75 na magistrali I2C
; Bazuje na niskopoziomowych procedurach z i2c.asm

;-----------------------------------------------------------
; Zleca pomiar temperatury czujnikowi wewnętrznemu (I2C)
; niszczy A, C, R6, R7
; Zwraca C=0, jeśli sukces; C=1, jeśli wystąpił błąd
int_sensor_start_measuring:
	bcall i2c_start
	jc int_sensor_start_measuring_ret
	mov A, #I2C_TEMP_WR
	bcall i2c_shout
	jc int_sensor_error
	; Pointer Register ma wskazywać na Configuration Register (1)
	mov A, #1
	bcall i2c_shout
	jc int_sensor_error
	; wpisujemy:
	; OS=1 (One Shot)
	; R=11 (Converter Resolution = 12-bit czyli 0.0625 st. C, czas pomiaru 220 ms typ.)
	; F=11 (Fault Queue = 6 kolejnych błędów zgłasza alarm - i tak tego nie używamy)
	; POL=0 (Polarity: pin alarmu aktywny zerem - i tak go nie używamy)
	; TM=0 (Thermostat Mode = Comparator Mode, a nie Interrupt Mode)
	; SD=1 (Shut Down po bieżącym pomiarze)
	mov A, #11111001b
	bcall i2c_shout
int_sensor_error:
	bcall i2c_stop
int_sensor_start_measuring_ret:
	ret

;-----------------------------------------------------------
; Odczytuje wynik pomiaru z czujnika wewnętrznego (I2C)
; niszczy A, C, local_temp_h, local_temp_l, R6, R7
; Zwraca C=0, jeśli sukces; C=1, jeśli wystąpił błąd
; Jeśli C=0, to wynik pomiaru jest zwracany w rejestrach local_temp_h:local_temp_l
; local_temp_h = część całkowita (przed przecinkiem)
; local_temp_l = licznik części ułamkowej (mianownik=256)
int_sensor_read_temp:
	bcall i2c_start
	jc int_sensor_read_temp_ret
	mov A, #I2C_TEMP_WR
	bcall i2c_shout
	jc int_sensor_read_temp_stop
	; Pointer Register ma wskazywać na Temperature Register (0)
	clr A
	bcall i2c_shout
	jc int_sensor_read_temp_stop
	bcall i2c_start
	jc int_sensor_read_temp_stop
	mov A, #(I2C_TEMP_WR or 1)
	bcall i2c_shout
	jc int_sensor_read_temp_stop
	bcall i2c_shin
	mov local_temp_h, A	; część całkowita
	bcall i2c_ACK_shin
	mov local_temp_l, A	; część ułamkowa
	bcall i2c_NAK
	clr C
int_sensor_read_temp_stop:
	bcall i2c_stop
int_sensor_read_temp_ret:
	ret
