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
; Procedury niszczą A, C, R6, R7

;-----------------------------------------------------------
; opóźnienie
load_delay	macro delay
ifdef	TUNE_1WIRE
	mov R7, delay		; 24 cykle
else
	mov R7, #delay&_def	; 12 cykli
endif
endm

;-----------------------------------------------------------
; RESET - zwraca C=1 jeśli wystąpił błąd (nie ma żadnego czujnika)
; niszczy C, R7
ow_reset:
	clr EA
	clr OW_DQ		; reset pulse min. 480 µs
	mov R7, #221	; 12 cykli; łącznie impuls potrwa 480,69 µs
	setb C			; 12 cykli
ow_reset_pulse:
	nop				; 12 cykli
	nop				; 12 cykli
	;inc DPTR		; 24 cykle, a tylko 1 bajt
	djnz R7, ow_reset_pulse	; 24*221=5304 cykli
	setb OW_DQ		; 12 cykli; DS18B20 waits 15-60 µs
	mov R7, #14		; 12 cykli; łącznie poczekamy 15,73 µs
	djnz R7, $		; 24*14=336 cykli
	load_delay ow_tRST
ow_reset_check_present:
	jnb OW_DQ, ow_reset_presence_pulse	; 24 cykle
	djnz R7, ow_reset_check_present		; 24 cykle
	sjmp ow_reset_return
ow_reset_presence_pulse:
	mov R7, #22		; presence pulse musi trwać jeszcze co najmniej 47,74 µs
ow_reset_check_present2:
	jb OW_DQ, ow_reset_return			; 24 cykle
	djnz R7, ow_reset_check_present2	; 24 cykle
	mov R7, #112	; presence pulse może trwać jeszcze co najwyżej 243 µs
ow_reset_check_present3:
	jb OW_DQ, ow_reset_presence_finished	; 24 cykle
	djnz R7, ow_reset_check_present3		; 24 cykle
	sjmp ow_reset_return	; błąd - za długi presence pulse
ow_reset_presence_finished:
	; poczekajmy jeszcze co najmniej tyle, ile w najgorszym przypadku
	; musi pozostać czasu do zakończenia resetu, czyli > 480-15-60=405 µs
	mov R7, #0		; 416,7 µs
ow_reset_sustain:
	nop
	djnz R7, ow_reset_sustain
	clr C
ow_reset_return:
	setb EA
	ret

;-----------------------------------------------------------
; początek cyklu zapisu/odczytu bitu na 1-wire
; 96+24*ow_tLOW cykli, min. 5,4 µs
; C = bit do wystawienia po impulsie 0
; długość impulsu 0 = (ow_tLOW+1)*24 cykle
; ow_tLOW > 0
; ow_tLOW=1  ->  2,17 µs
; ow_tLOW=12 -> 14,1  µs
; niszczy R7
ow_start_cycle:
	load_delay ow_tLOW
	clr EA			; 12 cykli
	clr OW_DQ		; 12 cykli; start write time slot
	djnz R7, $		; ow_tLOW*24 cykle
	mov OW_DQ, C	; 24 cykle
	ret				; 24 cykle

;-----------------------------------------------------------
; wysłanie bitu z C na 1-wire
; 192+24*(ow_tLOW+ow_tWR) cykli
; niszczy R7
ow_write_bit:
	acall ow_start_cycle	; 24+96+24*ow_tLOW cykli
	; slave sampluje linię między 15 µs a 60 µs od początku slotu
	; cały slot trwa co najmniej 60 µs, max. 120 µs jeśli wysyłamy 0
	load_delay ow_tWR
	djnz R7, $		; ow_tWR*24 cykle
	setb OW_DQ		; 12 cykli; end write time slot
	; od clr OW_DQ w ow_start_cycle do teraz minęło (czyli cykl 1-wire trwał)
	; 84 + 24 * (ow_tLOW + ow_tWR) cykli
	; zatem dla przepisowych >60 µs -> ow_tLOW + ow_tWR = 52
	setb EA			; 12 cykli
	ret				; 24 cykle

;-----------------------------------------------------------
; odczyt bitu z 1-wire do C
; 228+24*(ow_tLOW+ow_tDSO+ow_tRD) cykli
; niszczy C, R7
ow_read_bit:
	setb C			; 12 cykli
	acall ow_start_cycle	; 24+96+24*ow_tLOW cykli
	load_delay ow_tDSO
	djnz R7, $		; ow_tDSO*24 cykle
	; master sampluje linię tuż przed upływem 15 µs od rozpoczęcia slotu
	mov C, OW_DQ	; 12 cykli
	; od clr OW_DQ w ow_start_cycle do teraz minęło
	; 84 + 24 * (ow_tLOW + ow_tDSO) cykli
	; zatem dla przepisowych <15 µs -> ow_tLOW + ow_tDSO = 10
	load_delay ow_tRD
	djnz R7, $		; ow_tRD*24 cykle
	; od clr OW_DQ w ow_start_cycle do teraz minęło (czyli cykl 1-wire trwał)
	; 108 + 24 * (ow_tLOW + ow_tDSO + ow_tRD) cykli
	; zatem dla przepisowych >60 µs -> ow_tLOW + ow_tDSO + ow_tRD = 51
	setb EA			; 12 cykli
	ret				; 24 cykle

;-----------------------------------------------------------
; odczyt bajtu z 1-wire do akumulatora
; niszczy A, C, R6, R7
ow_read:
	mov R6, #8				; 12 cykli
ow_read_loop:
	acall ow_read_bit		; 24 cykle + 2712 cykli
	rrc A					; 12 cykli
	djnz R6, ow_read_loop	; 24 cykle
	ret						; 24 cykle

;-----------------------------------------------------------
; wysłanie bajtu z akumulatora na 1-wire
; niszczy A, C, R6, R7
ow_write:
	mov R6, #8				; 12 cykli
ow_write_loop:
	rrc A					; 12 cykli; bit do wysłania wysunięty do C
	acall ow_write_bit		; 24 cykle + 2760 cykli
	djnz R6, ow_write_loop	; 24 cykle
	ret						; 24 cykle

;-----------------------------------------------------------
; nakładka na ow_write
; wypisuje B bajtów spod DPTR
; niszczy A, B, C, R6, R7, DPTR
ow_write_bytes_next:
	inc DPTR
ow_write_bytes:
	clr A
	movc A, @A + DPTR
	acall ow_write
	djnz B, ow_write_bytes_next
	ret
