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
; Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2021, 2022 Aleksander Mazur
;
; Procedury wypisywania danych na port szeregowy
;
; Procedury niszczą A, B, C, R1, R7

;===========================================================

; Wypisuje liczbę z A dziesiętnie na UART0
; niszczy A, B, C
write_decimal:
	; odkładamy na stos znacznik końca - wartość, która po dodaniu do '0' da 0
	; jest to wartość niemożliwa do uzyskania jako reszta z dzielenia przez 10
	mov B, #0 - '0'
	push B
	; odkładamy na stosie dziesiętne rozwinięcie liczby (od końca)
write_decimal_div_loop:
	mov B, #10
	div AB	; A=wynik; B=reszta (musi być mniejsza od 10)
	push B
	jnz write_decimal_div_loop
	; wysyłamy dziesiętne rozwinięcie liczby na UART
write_decimal_pop_loop:
	pop ACC
	add A, #'0'
	jz write_ret1
	acall write_char
	sjmp write_decimal_pop_loop

;-----------------------------------------------------------
; Wypisuje zegar, kończąc średnikiem
; Wejście: aktualny czas w global_rtc_buf
; Niszczy A, B, C, R1, R7
write_clock:
	mov R1, #global_rtc_buf
	mov R7, #10011111b	; od lewej do prawej: jedynka=średnik, zero=dwukropek po danej pozycji w rtc_buf
write_clock_loop:
	mov A, @R1
	acall write_hex_byte
	mov A, R7
	rlc A
	mov R7, A
	clr A
	addc A, #':'	; dwukropek ma kod ASCII 0x3A, a średnik 0x3B
	acall write_char
	inc R1
	cjne R1, #global_rtc_timer0, write_clock_loop
write_ret1:
	ret

;-----------------------------------------------------------
; Przesyła heksadecymalnie bajt podany w A na UART0
; niszczy A, B, C
write_hex_byte:
	mov B, A
	swap A
	acall write_hex_digit
	mov A, B
;	sjmp write_hex_digit
; bezpośrednio za musi być write_hex_digit!

;-----------------------------------------------------------
; Przesyła na UART pojedynczą cyfrę heksadecymalną podaną w dolnej połówce A
; niszczy A, C
write_hex_digit:
	anl A, #00001111b	; teraz w A jest starsza część bajtu przesunięta w dół
	cjne A, #10, write_hex_digit_cont
write_hex_digit_cont:	; teraz C=1 gdy A < 10
	jc write_hex_digit_less_than_10
	add A, #('A' - 10 - '0')
write_hex_digit_less_than_10:
	add A, #'0'
;	sjmp write_char
; bezpośrednio za musi być write_char!

;-----------------------------------------------------------
; Wysyła znak z A na UART0
write_char:
	jnb flag_tx_busy, write_char_cont
	orl PCON, #00000001b	; idle (setb IDL) - flaga może się zczyścić tylko w przerwaniu z UART
	sjmp write_char
write_char_cont:
	setb flag_tx_busy
	mov SBUF, A
	ret

;-----------------------------------------------------------
; Przesyła heksadecymalnie R7 bajtów spod adresu R1 na UART0
; niszczy A, B, C, R1, R7
write_hex_bytes:
	mov A, @R1
	inc R1
	acall write_hex_byte
	djnz R7, write_hex_bytes
	ret

;-----------------------------------------------------------
; Wypisuje informacje o stanie masek sterowania
; niszczy A, B, C
write_control_masks:
	mov A, control_mask_all_used
	acall write_hex_byte
	mov A, #'&'
	acall write_char
	mov A, control_mask_direct_and
	acall write_hex_byte
	mov A, #'|'
	acall write_char
	mov A, control_mask_direct_or
	ajmp write_hex_byte

;-----------------------------------------------------------
; Wypisuje informację o stanie portu przekaźników, kończy średnikiem
; niszczy A, B, C
write_relay_port:
	acall write_equals
	mov A, RELAY_PORT
ifdef	CONTROL_NEGATIVE
	cpl A
endif
	acall write_hex_byte
	;sjmp write_semicolon
; bezpośrednio za musi być write_semicolon!

;-----------------------------------------------------------
; Wypisuje średnik
; Niszczy A
write_semicolon:
	mov A, #';'
	sjmp write_char

;-----------------------------------------------------------
; Wypisuje wykrzyknik
; Niszczy A
write_exclamation:
	mov A, #'!'
	sjmp write_char

;-----------------------------------------------------------
; Wypisuje kropkę
; Niszczy A
write_dot:
	mov A, #'.'
	sjmp write_char

;-----------------------------------------------------------
; Wypisuje znak równości
; Niszczy A
write_equals:
	mov A, #'='
	sjmp write_char

;-----------------------------------------------------------
; Wypisuje liczbę 16-bitową, stałoprzecinkową z przecinkiem na 8 bicie, ze znakiem
; wejście: R4:R5
; niszczy A, B, C
write_temperature:
	mov A, R4
	;anl A, #10000000b
	;jz dont_negate
	rlc A
	jnc dont_negate
	mov A, #'-'
	acall write_char
	; negujemy
	clr A
	clr C
	subb A, R5
	push ACC
	clr A
	subb A, R4
	acall write_decimal
	pop ACC
	sjmp write_fraction
dont_negate:
	mov A, R4
	acall write_decimal
	mov A, R5
;	sjmp write_fraction
; bezpośrednio za musi być write_fraction!

;-----------------------------------------------------------
; Wypisuje liczbę ułamkową (część po przecinku) z A dziesiętnie na UART0 (np. 80h -> .5)
; niszczy A, B, C
write_fraction:
	jz write_ret
	; zachowujemy A, zaczynamy od kropki
	mov B, A
	acall write_dot
	mov A, B
write_fraction_loop:
	mov B, #10
	mul AB
	xch A, B
	add A, #'0'
	acall write_char
	xch A, B
	jnz write_fraction_loop
write_ret:
	ret
