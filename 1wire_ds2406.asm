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
; Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2020 Aleksander Mazur
;
; Obsługa układów DS2406 na magistrali 1-wire
; Bazuje na niskopoziomowych procedurach z 1wire.asm

;===========================================================
; Stałe

; komendy 1-wire układów DS2406
ds_channel_access	equ	0F5h

;===========================================================
; Procedury

;-----------------------------------------------------------
; Kasuje lacie wszystkim układom DS2406
; Niszczy A, B, C, R6, R7
owhl_clear_latches_ds2406:
	; kasujemy lacie wszystkim układom DS2406
	; wysyłamy SKIP ROM - CHANNEL ACCESS
	; zakładamy, że reszta urządzeń na magistrali zignoruje komendę
	acall ow_reset
	jc owhl_ret
	mov DPTR, #owhl_clear_latches_ds2406_seq
	mov B, #owhl_clear_latches_ds2406_seq_end - owhl_clear_latches_ds2406_seq
	ajmp ow_write_bytes
	;mov A, #ds_skip_rom
	;acall ow_write
	;mov A, #ds_channel_access
	;acall ow_write
	;mov A, #11000100b	; Channel Control Byte 1: Activity Latch Reset, read PIO-A
	;acall ow_write
	;mov A, #11111111b	; Channel Control Byte 2
	;ajmp ow_write
owhl_clear_latches_ds2406_seq:
	db ds_skip_rom
	db ds_channel_access
	db 11000100b	; Channel Control Byte 1: Activity Latch Reset, read PIO-A
	db 11111111b	; Channel Control Byte 2
owhl_clear_latches_ds2406_seq_end:

;-----------------------------------------------------------
; Odczytuje stan lacia układu DS2406 i wyrzuca go na port szeregowy.
; Na magistrali musi być już wybrany czujnik (przez SKIP ROM lub SEARCH ROM lub MATCH ROM)
; - procedura wysyła od razu rozkaz CHANNEL_ACCESS.
; Niszczy A, B, C, R6, R7
owhl_read_info_ds2406:
	; obsługa DS2406 jako wejście
	mov DPTR, #owhl_read_info_ds2406_seq
	mov B, #owhl_read_info_ds2406_seq_end - owhl_read_info_ds2406_seq
	acall ow_write_bytes
	;mov A, #ds_channel_access
	;acall ow_write
	;mov A, #01000100b	; Channel Control Byte 1: read PIO-A
	;acall ow_write
	;mov A, #11111111b	; Channel Control Byte 2
	;acall ow_write
	acall ow_read		; Channel Info Byte -> ACC
	; BIT 7 - Supply Indication (0 = no supply)
	; BIT 6 - Number of Channels (0 = channel A only)
	; BIT 5 - PIO-B Activity Latch
	; BIT 4 - PIO-A Activity Latch
	; BIT 3 - PIO-B Sensed Level
	; BIT 2 - PIO-A Sensed Level
	; BIT 1 - PIO-B Channel Flip-Flop Q
	; BIT 0 - PIO-A Channel Flip-Flop Q
	rlc A	; teraz mamy bit7 w C
	rlc A	; teraz mamy bit6 w C (flaga obecności PIO-B)
	; a interesujące nas bity 5,4,3,2 mamy w górnej połowie A (przesunięte w lewo o 2 bity)
	swap A	; a teraz w dolnej połowie A
	anl A, #00001111b
	; Teraz A zawiera stan układu:
	;  bit 0 - stan portu PIO-A
	;  bit 1 - stan portu PIO-B lub wartość nieokreślona, jeśli układ nie ma PIO-B
	;  bit 2 - stan lacia PIO-A
	;  bit 3 - stan lacia PIO-B lub wartość nieokreślona, jeśli układ nie ma PIO-B
	;  pozostałe bity wyzerowane
	; C określa, czy port PIO-B istnieje.
	;-----------------------------------------------------------
	; Wyjście: A[*][,B[*]]
	; gdzie: A to stan PIO-A, B to stan PIO-B (0 albo 1)
	;        gwiazdka oznacza, że lać był zatrzaśnięty
	; człon ,B[*] występuje gdy C=1
	; Niszczy A, B, C
	jnc write_info_ds2406_pio	; jeśli nie ma PIO-B, to obsługujemy tylko PIO-A
	push ACC
	acall write_info_ds2406_pio
	mov A, #','	; oddzielamy przecinkiem stan PIO-A od PIO-B
	acall write_char
	pop ACC
	; przerabiamy status tak, żeby dane o PIO-B były w miejscach danych o PIO-A
	rr A
write_info_ds2406_pio:
	mov B, A
	; wypisujemy info o PIO dostępną w miejscach przeznaczonych na PIO-A
	; liczą się tylko bity 0 i 2 z A
	; wypisujemy stan portu - bit 0
	anl A, #1
	add A, #'0'
	acall write_char
	; jeśli lać był zatrzaśnięty, piszemy np. gwiazdkę
	jnb B.2, owhl_ret
	mov A, #'*'
	ajmp write_char
owhl_read_info_ds2406_seq:
	db ds_channel_access
	db 01000100b	; Channel Control Byte 1: read PIO-A
	db 11111111b	; Channel Control Byte 2
owhl_read_info_ds2406_seq_end:
