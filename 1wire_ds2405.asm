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
; Copyright (c) 2018, 2020, 2021 Aleksander Mazur
;
; Obsługa układów DS2405 na magistrali 1-wire
; Bazuje na niskopoziomowych procedurach z 1wire.asm

;-----------------------------------------------------------
; Odczytuje stan układu DS2405 i wyrzuca go na port szeregowy.
; Na magistrali musi być już wybrany czujnik - przez SEARCH ROM lub MATCH ROM,
; przy czym SEARCH ROM nie zmienia stanu wyjścia (otwarty dren tranzystora z kanałem N),
; a MATCH ROM przełącza na przeciwny niż był.
; Procedura generuje kilka slotów odczytu 1-wire.
; Niszczy A, B, C, R6, R7
owhl_read_info_ds2405:
	acall ow_read
	; same jedynki -> 1, w przeciwnym razie -> 0
	add A, #1
	; jeśli były same jedynki, to dodanie 1 przekręca akumulator i ustawia bit przeniesienia (C)
	clr A
	addc A, #'0'
	ajmp write_char
