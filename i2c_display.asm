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
; Copyright (c) 2021 Aleksander Mazur
;
; Obsługa modułu wyświetlacza Philips 3118 108 5218.1
; SW V1.5 Wk:235.4 BPM T10794V 0 311910334571
; schemat: https://www.elektroda.pl/rtvforum/topic117391.html
;
; adres: 0x76
; zapis:
; 0, 0x15, 0x25: pokaż godzinę 21:37 z migającym dwukropkiem
; 1, 0x15, 0x25: pokaż godzinę 21:37 ze świecącym dwukropkiem
; 2, 0x4F, 0x4C, 0x4F, 0x80: wyświetl podane znaki ASCII (z obsługiwanego podzbioru); 0x80 = flaga kropki
; 3, 0xFF, 0xFF, 0xFF, 0xFF: zaświeć segmenty, które mają _jedynkę_
; 5, 1: zaświeć czerwoną diodę
; 5, 0: zgaś czerwoną diodę
; 6, 0: piskaj po 5 razy w kółko
; 6, 1: piśnij raz krótko
; 6, 2: piszcz ciągle
; 8, 0: ustaw jasność na 0% (2.4 mA)
; 8, 1: ustaw jasność na 25% (27 mA)
; 8, 2: ustaw jasność na 50% (55 mA)
; 8, 3: ustaw jasność na 75% (82 mA)
; 8, 4: ustaw jasność na 100% (104 mA)
; 9: testuj wyświetlacz (L11.5, potem wszystko świeci i piszczy)
; (jasność dotyczy też czerwonej diody obok wyświetlacza)
;
; Wyświetlacz nie reaguje na ustawianie jasności wysyłane od razu po innym rozkazie,
; ale po 5/12 ms już daje sobie radę.

I2C_DISPLAY_TIME	equ 0
I2C_DISPLAY_ASCII	equ	2
I2C_DISPLAY_SEG		equ	3
I2C_DISPLAY_BUZZ	equ	6
I2C_DISPLAY_DIM		equ	8

ifdef	USE_DISPLAY_SEG
;-----------------------------------------------------------
; Wysyła na I2C kod fontu reprezentujący cyfrę przekazaną w A.
; Jeśli R6 = 1, to dodatkowo zapala kropkę dziesiętną po cyfrze.
; Zwraca C=0 jeśli sukces, C=1 jeśli wystąpił błąd na magistrali I2C.
; Niszczy A, C, R7
display_digit:
	add A, #charset - display_digit_rel
	movc A, @A + PC	; w momencie sumowania PC pokazuje na display_digit_rel
display_digit_rel:
	cjne R6, #1, display_digit_cont
	orl A, #KROPKA
display_digit_cont:
	sjmp i2c_shout

charset:
$include (font.asm)

I2C_DISPLAY_DIGIT	equ	I2C_DISPLAY_SEG

else

KROPKA	equ	80h
MYSLNIK	equ	'-'

;-----------------------------------------------------------
; Wysyła na I2C kod ASCII cyfry przekazanej w A.
; Jeśli R6 = 1, to dodatkowo zapala kropkę dziesiętną po cyfrze.
; Zwraca C=0 jeśli sukces, C=1 jeśli wystąpił błąd na magistrali I2C.
; Niszczy A, C, R7
display_digit:
	orl A, #30h
	cjne R6, #1, display_digit_cont
	orl A, #KROPKA
display_digit_cont:
	sjmp i2c_shout

I2C_DISPLAY_DIGIT	equ	I2C_DISPLAY_ASCII

endif

;-----------------------------------------------------------
; Wyświetla temperaturę przekazaną w local_temp_h:local_temp_l
; o ile w R3 jest właściwy numer funkcji (równy display_func_idx).
; Wtedy też ustawia flag_display_used.
; local_temp_h - przed przecinkiem
; local_temp_l - po przecinku
; w kodzie uzupełnieniowym do dwóch.
; Niszczy: A, B, C, R6, R7
display_temperature:
	jnb flag_display_found_idx, display_ret
	mov A, R3
	cjne A, display_func_idx, display_ret
display_temperature_unconditional:
	setb flag_display_used
	mov B, #I2C_DISPLAY_DIGIT
	bcall display_start
	jc display_ret
	; zaczynamy
	mov A, local_temp_h
	jnb ACC.7, display_temp2
	; minus
	mov A, #MYSLNIK
	bcall i2c_shout
	jc display_i2c_stop
	; negujemy local_temp_h:local_temp_l
	clr A
	clr C
	subb A, local_temp_l
	push ACC	; zanegowaną część po przecinku odkładamy na stos - tylko, jeśli liczba jest ujemna
	clr A
	subb A, local_temp_h
display_temp2:
	; w A jest liczba do wyświetlenia - bez znaku
	mov R6, #0
display_temp_loop1:
	; odkładamy na stos cyfry rozwinięcia dziesiętnego liczby z A (od końca)
	mov B, #10
	div AB
	push B
	inc R6
	jnz display_temp_loop1
	; R6 = liczba cyfr odłożonych na stos
	mov B, R6
display_temp_loop2:
	pop ACC
	bcall display_digit
	;jc display_i2c_stop	; stąd nie ma wyjścia - musimy zdjąć ze stosu wszystko odłożone w loop1
	djnz R6, display_temp_loop2
	; R6 = 0
	; B = zapamiętana liczba cyfr odłożonych na stos przez loop1
	;     i zdjętych przez loop2
	mov R6, B
	mov B, local_temp_l
	mov A, local_temp_h
	jnb ACC.7, display_temp3
	pop B	; zdejmujemy ze stosu bezwzględną wartość liczby po przecinku
	inc R6	; bo wypisaliśmy wcześniej minusa
display_temp3:
	; R6 = liczba użytych cyfr wyświetlacza
	; B = liczba po przecinku do wyświetlenia - bez znaku
display_temp_loop3:
	cjne R6, #4, display_temp_loop3_cont
	sjmp display_i2c_stop
display_temp_loop3_cont:
	mov A, #10
	mul AB
	; B = cyfra do pokazania
	; A = reszta do obsługi w kolejnej iteracji
	xch A, B
	inc R6	; R6 > 1
	bcall display_digit
	jc display_i2c_stop	; to możnaby pominąć
	sjmp display_temp_loop3

;-----------------------------------------------------------
; Zaczyna gadać z wyświetlaczem: wysyła adres i bajt podany w B
; Niszczy A, C, R7
; Jeśli C=0, to się udało i trzeba wysłać następne bajty, a potem stop
; Jeśli C=1, to wystąpił błąd (i jest już po stopie)
display_start:
	bcall i2c_start
	jc display_ret
	mov A, #I2C_DISPLAY_WR
	bcall i2c_shout
	jc display_i2c_stop	; to możnaby pominąć
	mov A, B
	bcall i2c_shout
	jc display_i2c_stop
display_ret:
	ret

;-----------------------------------------------------------
; Informuje o braku czujnika/temperatury
; Niszczy A, B, C, R7, R6
display_missing:
ifdef	USE_DISPLAY_BUZZER
	; Piszczy raz
	mov B, #I2C_DISPLAY_BUZZ
	bcall display_start
	jc display_ret
	mov A, #1
	bcall i2c_shout
else
	; Same myślniki
	mov B, #I2C_DISPLAY_DIGIT
	bcall display_start
	jc display_ret
	mov R6, #4
display_missing_loop:
	mov A, #MYSLNIK
	bcall i2c_shout
	djnz R6, display_missing_loop
endif
	sjmp display_i2c_stop

;-----------------------------------------------------------
; Ustawia jasność wyświetlacza na podaną w A (0-4)
; Niszczy A, B, C, R7
; Zwraca C=1 w razie błędu, C=0 po sukcesie
display_dim:
	push ACC
	mov B, #I2C_DISPLAY_DIM
	bcall display_start
	pop ACC
	jc display_ret
	bcall i2c_shout
display_i2c_stop:
	bjmp i2c_stop

;-----------------------------------------------------------
; Wyświetla zegarek
; Niszczy A, B, C, R1, R7
display_clock:
	mov B, #I2C_DISPLAY_TIME
	bcall display_start
	jc display_ret
	mov R1, #global_rtc_hours
display_clock_loop:
	; @R1 z kodu BCD na zwykłą liczbę
	mov A, @R1
	swap A
	anl A, #00001111b
	mov B, #10
	mul AB
	mov R7, A
	mov A, @R1
	anl A, #00001111b
	add A, R7
	bcall i2c_shout
	jc display_i2c_stop
	inc R1
	cjne R1, #global_rtc_minutes+1, display_clock_loop
	bjmp i2c_stop
