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
; Copyright (c) 2021, 2024 Aleksander Mazur
;
; Obsługa modułu wyświetlacza HT1628 zgodnego z TM1628
; na płytce HT-2261LED-V1.0
;
; komenda #4 - wysłanie 0x88+X włącza wyświetlacz i ustawia jasność:
; X - dimming quantity settings (pulse width) - prąd przy wszystkich segmentach świecących
; 0 - 1/16 - 8,9 mA
; 1 - 2/16 - 16,3 mA
; 2 - 4/16 - 27,8 mA
; 3 - 10/16 - 49,1 mA
; 4 - 11/16 - 51,5 mA
; 5 - 12/16 - 53,7 mA
; 6 - 13/16 - 55,8 mA
; 7 - 14/16 - 57,7 mA
; 0x80 wyłącza wyświetlacz pozostawiając skanowanie klawiszy
;
; komenda #3 - wysłanie 0xC0+offset zaczyna zapis pamięci segmentów
; (potem można bez podnoszenia STB wysyłać kolejne bajty)
; offset - cyfra
; 0 - #1
; 2 - #2
; 4 - #3
; 6 - #4
; 8 - 0x20 włącza dwukropek
; kolejne bity 0-6 to kolejne segmenty a-f
;
; max:
; (+8F)(+C0+FF+FF+FF+FF+FF+FF+FF+FF+FF)

;-----------------------------------------------------------
; Przerabia cyfrę na kod układu segmentów wyświetlacza
convert_digit:
	add A, #charset - display_ret
	movc A, @A + PC	; w momencie sumowania PC pokazuje na display_ret
display_ret:
	ret

;-----------------------------------------------------------
; Wyświetla temperaturę przekazaną w local_temp_h:local_temp_l (tylko część całkowita)
; o ile w R3 jest właściwy numer funkcji (równy display_func_idx).
; Wtedy też ustawia flag_display_used.
; local_temp_h - przed przecinkiem
; local_temp_l - po przecinku (tu ignorujemy, bo nie wyświetlacz nie ma kropek)
; w kodzie uzupełnieniowym do dwóch.
; Niszczy: A, B, C, R1, R6, R7
display_temperature:
	jnb flag_display_found_idx, display_ret
	mov A, R3
	cjne A, display_func_idx, display_ret
display_temperature_unconditional:
	setb flag_display_used
	mov A, local_temp_h
	mov R1, #0	; dla liczb dodatnich
	jnb ACC.7, display_temp2
	mov R1, #MYSLNIK	; dla liczb ujemnych
	; negujemy local_temp_h:local_temp_l
	clr A
	clr C
	subb A, local_temp_l
	; zlewamy część po przecinku, ale zaokrąglamy część przed przecinkiem zawsze w stronę zera (np. -0.5 to będzie -0 a nie -1)
	clr A
	subb A, local_temp_h
display_temp2:
	; w A jest liczba do wyświetlenia - bez znaku
	; w R1 jest maska do zor'owania przed pierwszą znaczącą cyfrą - właściwa dla znaku liczby (tj. z maską minusa dla liczb ujemnych)
	; odkładamy na stos 3 cyfry
	mov R6, #3
display_temp_loop1:
	mov B, #10
	div AB
	mov R7, A
	mov A, B
	jnz display_temp_show
	cjne R7, #0, display_temp_show
	cjne R6, #3, display_temp_empty
display_temp_show:
	acall convert_digit
	sjmp display_temp_cont
display_temp_empty:
	; zero nieznaczące
	clr A
	xch A, R1	; A=znak liczby jeśli jeszcze nie pokazaliśmy, R1=pusto
display_temp_cont:
	cjne R6, #1, display_temp_cont2
	; ostatnia szansa na pokazanie minusa
	orl A, R1
display_temp_cont2:
	push ACC
	mov A, R7
	djnz R6, display_temp_loop1
	; mamy na stos odłożone układy segmentów do zaświecenia na trzech kolejnych cyfrach
	acall spi_start
	mov A, #0C0h
	acall spi_shout
	; pierwsza cyfra - numer funkcji liczony od 1
	mov A, R3
	inc A
	anl A, #00001111b
	acall convert_digit
	acall spi_shout
	acall spi_shout	; pomiń nieparzysty adres, który na nic nie wpływa
	mov R6, #3
display_temp_loop2:
	pop ACC
	acall spi_shout
	acall spi_shout	; pomiń nieparzysty adres, który na nic nie wpływa
	djnz R6, display_temp_loop2
	; kasujemy dwukropek
	clr A
	sjmp spi_shout_stop

;-----------------------------------------------------------
; Informuje o braku czujnika/temperatury (same myślniki)
; Niszczy A, B, C, R7, R6
display_missing:
	acall spi_start
	mov A, #0C0h
	acall spi_shout
	mov R6, #9
display_missing_loop:
	mov A, #MYSLNIK
	acall spi_shout
	djnz R6, display_missing_loop
	sjmp spi_stop

;-----------------------------------------------------------
; Ustawia jasność wyświetlacza na podaną w A (0-8)
; 0 wyłącza wyświetlacz, 1-8 włącza i ustawia jasność
; Niszczy A, B, C, R7
; Zwraca C=1 w razie błędu, C=0 po sukcesie
display_dim:
	acall spi_start
	jz display_dim_dark
	dec A	; 0-7
	orl A, #08h	; Display ON
display_dim_dark:
	orl A, #80h	; Command #4 - Display Control
	sjmp spi_shout_stop

;-----------------------------------------------------------
; Wyświetla zegarek
; Niszczy A, B, C, R1, R7
display_clock:
	acall spi_start
	mov A, #0C0h
	acall spi_shout
	mov R1, #global_rtc_hours
display_clock_loop:
	; @R1 - BCD na 2 cyfry
	mov A, @R1
	swap A
	anl A, #00001111b
	acall convert_digit
	acall spi_shout
	acall spi_shout	; pomiń nieparzysty adres, który na nic nie wpływa
	mov A, @R1
	anl A, #00001111b
	acall convert_digit
	acall spi_shout
	acall spi_shout	; pomiń nieparzysty adres, który na nic nie wpływa
	inc R1
	cjne R1, #global_rtc_minutes+1, display_clock_loop
	; pod adresem C8 bit 5 steruje dwukropkiem
	mov A, #20h
	ajmp spi_shout_stop

charset:
$include (font.asm)
