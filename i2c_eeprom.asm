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
;
; Obsługa pamięci EEPROM na magistrali I2C
; Bazuje na niskopoziomowych procedurach z i2c.asm

;===========================================================
; API

;-----------------------------------------------------------
; Inicuje odczyt z EEPROM spod adresu w B
; Niszczy A, C, R7
; Zwraca C=1 jeśli wystąpił błąd; wówczas magistrala I2C jest pozostawiona w stanie wolnym
; (wołający nie musi już nic z nią robić).
; Zwraca C=0 po sukcesie; wówczas magistrala I2C pozostaje w stanie wybranego czujnika.
; Wołający powinien zrobić i2c_read. Następnie:
; - jeśli chce odczytać następny bajt: i2c_ack i powrót do i2c_read
; - jeśli chce zakończyć: i2c_nak i i2c_stop
eeprom_read_start:
	acall i2c_start
	jc eeprom_read_from_ret
	mov A, #I2C_EEPROM_WR
	acall i2c_shout
	jc i2c_stop
	mov A, B
	acall i2c_shout
	jc i2c_stop
	acall i2c_start
	jc i2c_stop
	mov A, #(I2C_EEPROM_WR or 1)
	acall i2c_shout
	jc i2c_stop
eeprom_read_from_ret:
	ret

;-----------------------------------------------------------
; Kończy odczyt z EEPROM po udanym wywołaniu eeprom_read_start
; (tj. gdy C=0) i po odczytaniu co najmniej jednego bajtu
eeprom_read_stop:
	acall i2c_NAK
	ajmp i2c_stop

;-----------------------------------------------------------
; Czyta jeden bajt z EEPROM spod adresu w B
; Niszczy A, C, R7
; Zwraca C=1, jeśli wystąpił błąd, a C=0 po sukcesie - wówczas
; odczytany bajt jest w A.
; Magistrala I2C jest wolna.
eeprom_read_byte_at:
	acall eeprom_read_start
	jc eeprom_read_byte_at_ret
	acall i2c_shin
	acall eeprom_read_stop
	clr C
eeprom_read_byte_at_ret:
	ret
