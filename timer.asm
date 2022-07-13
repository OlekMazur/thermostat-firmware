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
; Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2022 Aleksander Mazur
;
; Przerwanie timera obsługujące zegar czasu rzeczywistego

;===========================================================

; Procedura wywoływana z przerwania timera.
; Zadanie: aktualizować global_rtc_buf.
; Przy kwarcu 22118400 Hz przepełnienie 16-bitowego timera następuje
; z częstotliwością ; 22118400/12/(2^16)=28 1/8 Hz,
; tj. 225 razy co 8 sekund.
; Będziemy co "implus" dekrementować global_rtc_timer0, z tym, że
; zamiast robić pełne 8*32=256 cykli, skrócimy 7 obrotów o 4 cykle
; (z 32 do 28), a ostatni, ósmy obrót - o 3 cykle (z 32 do 29).
; W ten sposób eliminujemy 7*4+1*3=31 cykli z 256, zostawiając ich 225.
; Dzielimy więc bajt na starszą część 3-bitową i młodszą 5-bitową.
timer0_interrupt:
	push PSW
	push ACC
	push B
	; odliczamy czas pomiaru
	jnb flag_measuring, timer0_interrupt_not_measuring
	djnz global_measure, timer0_interrupt_not_measuring
	setb flag_measuring_timeout
timer0_interrupt_not_measuring:
	; sprawdzamy, czy (global_rtc_timer0 & 0x1F) + !(global_rtc_timer0 & 0xE0) - 4 == 0
	mov A, global_rtc_timer0
	cjne A, #20h, timer0_interrupt_cont
timer0_interrupt_cont:
	; C=1, jeśli jesteśmy w ostatnim (ósmym) obrocie bardziej znaczącej
	; 3-bitowej części; czyli C = !(global_rtc_timer0 & 0xE0)
	anl A, #1Fh
	addc A, #-4	; w każdym z pierwszych 7 cykli starszej 3-bitowej części licznika (gdy C=0) odejmujemy 4, a w ostatnim, 8 cyklu (gdy C=1) odejmujemy 3
	jnz timer0_ret
	; minęła sekunda (około); zerujemy młodszą część licznika
	anl global_rtc_timer0, #0E0h
	; przy okazji sprawdzamy, czy cały licznik się właśnie nie przekręca
	mov A, global_rtc_timer0
	jnz timer0_dont_set_flag
	; jeśli tak, to ustawiamy flagę (raz na dokładnie 8 sekund)
	jbc flag_timer_skip_once, timer0_dont_set_flag
	setb flag_timer
timer0_dont_set_flag:
	mov A, R0	; nie można użyć ARx, bo nie wiemy, który bank rejestrów jest w użyciu
	push ACC
	mov R0, #global_rtc_seconds
timer0_inc_loop:
	; inkrementujemy licznik na bieżącej pozycji, wynik zachowujemy na razie w B
	mov A, @R0
	add A, #1	; add w przeciwieństwie do inc ustawia flagi potrzebne dla da
	da A
	mov B, A
	mov @R0, A
timer0_bcd_ok:
	; pobieramy graniczną wartość dla tej pozycji
	mov A, R0
	add A, #timer0_rtc_limits-timer0_rtc_limits_rel-global_rtc_buf
	movc A, @A + PC	; w momencie sumowania PC pokazuje na timer0_rtc_limits_rel
timer0_rtc_limits_rel:
	; czy osiągnęliśmy graniczną wartość?
	cjne A, B, timer0_inc_loop_end	; jeśli nie, to na tej pozycji kończymy
	; bieżąca pozycja się przekręciła - zerujemy ją i przechodzimy do następnej (bardziej znaczącej)
	mov @R0, #0
	dec R0
	cjne R0, #global_rtc_weekday, timer0_not_weekday
	; skoro zmienia się doba, to zapominamy indeks ostatnio użytej pozycji w dobowym programie zegarowym
	mov global_clock_settings_index, #0
timer0_not_weekday:
	; jeśli to najbardziej znacząca pozycja się przekręciła, to kończymy
	cjne R0, #global_rtc_buf-1, timer0_inc_loop
timer0_inc_loop_end:
	pop ACC
	mov R0, A
timer0_ret:
	dec global_rtc_timer0
	pop B
	pop ACC
	pop PSW
	reti
timer0_rtc_limits:	db 07h, 24h, 60h, 60h
