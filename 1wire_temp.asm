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
; Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2021 Aleksander Mazur
;
; Obsługa czujników temperatury na magistrali 1-wire
; Bazuje na niskopoziomowych procedurach z 1wire.asm

;===========================================================
; Stałe

; komendy 1-wire czujników temperatury DS18B20, DS18S20, DS1820
ds_convert_t		equ 044h
ds_read_scratchpad	equ 0BEh
ds_write_scratchpad	equ 04Eh

;===========================================================
; Procedury

;-----------------------------------------------------------
; Zleca pomiar temperatury czujnikom zewnętrznym (1-wire)
; niszczy A, B, C, R6, R7
; Zwraca C=0, jeśli sukces; C=1, jeśli wystąpił błąd
; Jeśli sukces, to:
;  jeśli OW_PARASITE, to linia 1-wire zostaje w stanie silnej jedynki;
;   wołający musi odliczyć OW_PARASITE przerwań zegarowych i wyłączyć silną jedynkę,
;   zanim zacznie używać magistrali
;  jeśli nie OW_PARASITE, to linia 1-wire zostaje z włączonym zasilaniem;
;   wołający musi wyłączyć zasilanie, jak skończy używać magistrali
owhl_start_measuring:
	; wyłączamy silną jedynkę (gdyby tak była włączona) - bo będziemy gadać po 1-wire
	; albo włączamy zasilanie 1-wire
	setb OW_PWR
	; wysyłamy SKIP ROM - WRITE SCRATCHPAD
	acall ow_reset
	jc start_measuring_1wire_ret
	;mov A, #ds_skip_rom
	;acall ow_write
	;mov A, #ds_write_scratchpad
	;acall ow_write
	;clr A
	;acall ow_write	; wysyłamy T_H
	;acall ow_write	; wysyłamy T_L
	;mov A, #01111111b	; configuration register
	; dociera do DS18B20; DS18S20 przyjmuje tylko 2 bajty;
	; zakładamy, że reszta urządzeń na magistrali zignoruje komendę
	;acall ow_write
	mov DPTR, #owhl_temp_setup_seq
	mov B, #owhl_temp_setup_seq_end - owhl_temp_setup_seq
	acall ow_write_bytes
	; wysyłamy SKIP ROM - CONVERT T
	acall ow_reset
	jc start_measuring_1wire_ret
	mov A, #ds_skip_rom
	acall ow_write
	mov A, #ds_convert_t
	acall ow_write
	;mov DPTR, #owhl_temp_convert_seq
	;mov B, #owhl_temp_convert_seq_end - owhl_temp_convert_seq
	;acall ow_write_bytes
ifdef	OW_PARASITE
	clr OW_PWR	; włączamy silną jedynkę na 1-wire
endif
	clr C
start_measuring_1wire_ret:
	ret
owhl_temp_setup_seq:
	db ds_skip_rom
	db ds_write_scratchpad
	db 0	; T_H
	db 0	; T_L
	db 01111111b	; configuration register
owhl_temp_setup_seq_end:
;owhl_temp_convert_seq:
;	db ds_skip_rom
;	db ds_convert_t
;owhl_temp_convert_seq_end:

;-----------------------------------------------------------
; Odczytuje scratchpad z czujnika temperatury 1-wire.
; Na magistrali musi być już wybrany czujnik (przez SKIP ROM lub SEARCH ROM lub MATCH ROM)
; - procedura wysyła od razu rozkaz READ SCRATCHPAD.
; Wejście: R1 - miejsce na scratchpad (o rozmiarze ds_scratchpad_size).
; Procedura wypełnia podaną tablicę pod R1 i ustawia A (0=OK, nie-0=błąd). A, nie C.
; Niszczy A, B, C, R1, CRC, R6, R7.
owhl_read_scratchpad:
	mov A, #ds_read_scratchpad
	acall ow_write
	mov CRC, #0
	mov B, #ds_scratchpad_size
owhl_read_scratchpad_byte:
	acall ow_read
	mov @R1, A
	acall do_CRC8
	inc R1
	djnz B, owhl_read_scratchpad_byte
	mov A, CRC
	ret

;-----------------------------------------------------------
; Wyłuskuje temperaturę z odczytanego scratchpadu czujnika 1-wire.
; Wejście: global_ow_id - family code, R1 - początek odczytanego scratchpadu.
; Procedura ustawia local_temp_h:local_temp_l oraz C (0=OK, 1=błąd).
; Niszczy A, B, C, R1.
; Jest to czysto obliczeniowa procedura - nie robi żadnych operacji
; na magistrali 1-wire.
owhl_get_temperature_from_scratchpad:
	mov A, global_ow_id
ifndef	SKIP_DS18S20
	cjne A, #10h, owhl_get_temperature_not_ds18s20
	; DS18S20 lub DS1820 - T MSB|LSB ma 1 bit po przecinku, większa precyzja przy pomocy COUNT REMAIN
	inc R1	; T MSB
	mov A, @R1
	rrc A	; teraz mamy bit znaku w C
	dec R1	; T LSB
	mov A, @R1
	rrc A	; w A mamy część całkowitą temperatury
	mov local_temp_h, A
	clr A
	rrc A
	mov local_temp_l, A
	mov A, R1
	add A, #7	; COUNT PER C
	mov R1, A
	mov A, @R1
	cjne A, #10h, owhl_get_temperature_temp_success	; COUNT PER C miał być zahardkodowany jako 10h
	;mov A, #10h
	dec R1	; COUNT REMAIN
	clr C
	subb A, @R1
	mov B, #16
	mul AB	; zeruje C
	subb A, #40h		; -0.25 stopnia C
	mov local_temp_l, A
	mov A, local_temp_h
	subb A, #0
	add A, B
	sjmp owhl_get_temperature_temp_finish
owhl_get_temperature_not_ds18s20:
endif
	cjne A, #28h, owhl_get_temperature_not_ds18b20
	; DS18B20 - T MSB|LSB ma 4 bity po przecinku
	mov A, @R1	; T LSB
	anl A, #00001111b
	swap A
	mov local_temp_l, A
	mov A, @R1	; T LSB
	swap A
	anl A, #00001111b
	mov B, A
	inc R1
	mov A, @R1	; T MSB
	swap A
	anl A, #11110000b
	orl A, B
owhl_get_temperature_temp_finish:
	mov local_temp_h, A	; dla DS18S20: l_temp_h + B - C
owhl_get_temperature_temp_success:
	clr C
	ret
owhl_get_temperature_not_ds18b20:
	setb C
owhl_ret:
	ret
