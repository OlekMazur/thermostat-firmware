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
; Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2021, 2022 Aleksander Mazur
;
; Obsługa przerwania portu szeregowego

;===========================================================

; Nie wywoływać stąd procedur niekompatybilnych z naszym trzecim bankiem rejestrów!
; np. 1wire_HL.asm

using	3

; ostatnio używany adres w RAM - ustawiany komendą 'b'
rx_cmd_addr	equ	R0
; miejsce na argument komendy wyparsowywany z wejścia
rx_cmd_arg	equ R2	; (dawniej uart_arg @39h)
; kod bieżącej komendy (jeśli global_rx_state > 0)
rx_cmd_proc	equ R3	; (dawniej uart_proc @37h, był to indeks w tablicy znanych komend)

;===========================================================
; API

;-----------------------------------------------------------
; Obsługuje otrzymanie znaku z portu szeregowego
; Musi być włączony bank rejestrów przeznaczony na wyłączność tego modułu
; Znak wejściowy należy przekazać w B
; Niszczy wszelkie rejestry
rx_char:
	mov A, global_rx_state
	jnz rx_cmd_continue
	; nowa komenda - kod jest w B, zapamiętujemy
	mov rx_cmd_proc, B
rx_cmd_continue:
	; kontynuacja rozpoczętej komendy
	; w każdym przypadku (niezależnie od global_rx_state) wpisujemy do A kod aktualnie wykonywanej komendy
	mov A, rx_cmd_proc

;===========================================================
; Obsługa komend - łańcuch cjne
; Kod bieżącej komendy musi być w A
; (niezależnie od global_rx_state)
; w B ma być aktualnie otrzymany znak, interpretowany zależnie od global_rx_state

;-----------------------------------------------------------
; Komendy I2C: START
	cjne A, #'I', rx_cmd_i2c_start_mismatch
	acall i2c_start
	sjmp rx_cmd_i2c_check_error

rx_cmd_i2c_start_mismatch:
;-----------------------------------------------------------
; Komendy I2C: STOP
	cjne A, #'S', rx_cmd_i2c_stop_mismatch
	acall i2c_stop
	sjmp rx_cmd_success

rx_cmd_i2c_stop_mismatch:
;-----------------------------------------------------------
; Komendy I2C: ACK
	cjne A, #'A', rx_cmd_i2c_ack_mismatch
	acall i2c_ACK
	sjmp rx_cmd_success

rx_cmd_i2c_ack_mismatch:
;-----------------------------------------------------------
; Komendy I2C: NAK
	cjne A, #'N', rx_cmd_i2c_nak_mismatch
	acall i2c_NAK
	sjmp rx_cmd_success

rx_cmd_i2c_nak_mismatch:
;-----------------------------------------------------------
; Komendy I2C: zapis bajtu
	cjne A, #'W', rx_cmd_i2c_write_mismatch
	acall rx_cmd_collect_arg
	; mamy bajt do wysłania na I2C w A
	acall i2c_shout
	sjmp rx_cmd_i2c_check_error

rx_cmd_i2c_write_mismatch:
;-----------------------------------------------------------
; Komendy I2C: odczyt bajtu
	cjne A, #'R', rx_cmd_i2c_read_mismatch
	acall i2c_shin
	sjmp rx_cmd_write_byte_and_finish

rx_cmd_i2c_read_mismatch:
;-----------------------------------------------------------
; Komendy 1-wire: RESET
	cjne A, #'i', rx_cmd_ow_reset_mismatch
	acall ow_reset
rx_cmd_ow_C_error:
	jc rx_cmd_error
	sjmp rx_cmd_success

rx_cmd_ow_reset_mismatch:
;-----------------------------------------------------------
; Komendy 1-wire: zapis bajtu
	cjne A, #'w', rx_cmd_ow_write_mismatch
	acall rx_cmd_collect_arg
	; mamy bajt do wysłania na 1-wire w A
	acall ow_write
	sjmp rx_cmd_success

rx_cmd_ow_write_mismatch:
;-----------------------------------------------------------
; Komendy 1-wire: odczyt bajtu
	cjne A, #'r', rx_cmd_ow_read_mismatch
	acall ow_read
	sjmp rx_cmd_write_byte_and_finish

rx_cmd_ow_read_mismatch:
;-----------------------------------------------------------
ifndef	OW_PARASITE
ifndef	SKIP_DS1821
; Komendy 1-wire: przywrócenie trybu 1-wire w DS1821 - 16 szybkich impulsów
; niszczy R7
	cjne A, #'t', rx_cmd_ow_ds1821_mismatch
	; C=0
	setb OW_DQ
	clr OW_PWR
	mov R7, #32
rx_cmd_ow_ds1821_loop:
	cpl OW_DQ
	djnz R7, rx_cmd_ow_ds1821_loop
	setb OW_PWR
	orl C, /OW_DQ
	sjmp rx_cmd_ow_C_error

rx_cmd_ow_ds1821_mismatch:
endif
endif
;-----------------------------------------------------------
; Ręczne sterowanie wyjściami (przekaźnikami): wyłączanie
	cjne A, #'&', rx_cmd_relay_and_mismatch
	acall rx_cmd_collect_arg
	; mamy zera w A na pozycjach przekaźników do wyłączenia
ifdef	CONTROL_NEGATIVE
	cpl A
	orl RELAY_PORT, A
else
	anl RELAY_PORT, A
endif
	sjmp rx_cmd_success

rx_cmd_relay_and_mismatch:
;-----------------------------------------------------------
; Ręczne sterowanie wyjściami (przekaźnikami): włączanie
	cjne A, #'|', rx_cmd_relay_or_mismatch
	acall rx_cmd_collect_arg
	; mamy jedynki w A na pozycjach przekaźników do włączenia
ifdef	CONTROL_NEGATIVE
	cpl A
	anl RELAY_PORT, A
else
	orl RELAY_PORT, A
endif
	sjmp rx_cmd_success

;-----------------------------------------------------------
; Wtręt dla bliskości skoków >>>>>>>>>>>>>

rx_cmd_i2c_check_error:
	jnc rx_cmd_success
	acall i2c_stop
rx_cmd_error:
	mov A, #'!'
	sjmp rx_cmd_write_char_and_finish
rx_cmd_success:
	mov A, #'@'
rx_cmd_write_char_and_finish:
	acall write_char
	sjmp rx_cmd_finish
rx_cmd_write_byte_and_finish:
	acall write_hex_byte
rx_cmd_finish:
	mov global_rx_state, #0
	ret

; <<<<<<<<<<<<<<<<<
rx_cmd_relay_or_mismatch:

ifdef	CLOCK_COMMANDS
;-----------------------------------------------------------
; Nastawianie zegara: dzień tygodnia
	cjne A, #'d', rx_cmd_set_clock_weekday_mismatch
	; skoro zmienia się doba, to zapominamy indeks ostatnio użytej pozycji w dobowym programie zegarowym
	; robimy to nawet, jeśli nowy dzień tygodnia jest taki sam jak był
	; bo po co ktoś nam wysłał polecenie przestawienia?
	mov global_clock_settings_index, #0
	mov rx_cmd_addr, #global_rtc_weekday
	sjmp rx_cmd_write_to_memory

rx_cmd_set_clock_weekday_mismatch:
;-----------------------------------------------------------
; Nastawianie zegara: godziny
	cjne A, #'h', rx_cmd_set_clock_hours_mismatch
	mov rx_cmd_addr, #global_rtc_hours
	sjmp rx_cmd_write_to_memory

rx_cmd_set_clock_hours_mismatch:
;-----------------------------------------------------------
; Nastawianie zegara: minuty
	cjne A, #'m', rx_cmd_set_clock_minutes_mismatch
	mov rx_cmd_addr, #global_rtc_minutes
	sjmp rx_cmd_write_to_memory

rx_cmd_set_clock_minutes_mismatch:
;-----------------------------------------------------------
; Nastawianie zegara: sekundy
	cjne A, #'s', rx_cmd_set_clock_seconds_mismatch
	mov rx_cmd_addr, #global_rtc_seconds
	sjmp rx_cmd_write_to_memory

rx_cmd_set_clock_seconds_mismatch:
endif

;-----------------------------------------------------------
; Budzenie (wymuszenie pomiaru)
	cjne A, #'!', rx_cmd_wake_up_mismatch
	mov global_timer_skip, #0
	setb flag_timer
	setb flag_timer_skip_once
	sjmp rx_cmd_finish

rx_cmd_wake_up_mismatch:
;-----------------------------------------------------------
; Kasowanie watchdoga
	cjne A, #' ', rx_cmd_reset_watchdog_mismatch
	; procedura obsługi przerwania UART już zresetowała watchdoga, więc tutaj nie musimy znowu tego robić
	; na spację odpowiadamy spacją - taki ping-pong
	; i nie blokujemy pętli głównej
	; ale też jej nie przyspieszamy, jak w rx_cmd_wake_up
	mov global_timer_skip, #0
	mov global_wdc, #WATCHDOG_MAX
	;mov A, #' '
	sjmp rx_cmd_write_char_and_finish

rx_cmd_reset_watchdog_mismatch:
;-----------------------------------------------------------
; Dostęp do pamięci RAM: odczyt bajtu
; aktualizuje rx_cmd_addr, które musi przetrwać do wywołania komendy 'B'
	cjne A, #'b', rx_cmd_ram_read_mismatch
	acall rx_cmd_collect_arg
	; mamy adres w A, ale też w rx_cmd_arg
	mov rx_cmd_addr, A
	mov A, @rx_cmd_addr
	sjmp rx_cmd_write_byte_and_finish

rx_cmd_ram_read_mismatch:
;-----------------------------------------------------------
; Dostęp do pamięci RAM: zapis bajtu
	cjne A, #'B', rx_cmd_ram_write_mismatch
rx_cmd_write_to_memory:
	acall rx_cmd_collect_arg
	; mamy nastawę w A
	mov @rx_cmd_addr, A
	sjmp rx_cmd_success

rx_cmd_ram_write_mismatch:
;-----------------------------------------------------------
; Pobieranie zahardkodowanego adresu pamięci EEPROM
if	I2C_EEPROM_WR <> 0A0h
	cjne A, #'E', rx_cmd_get_eeprom_address_mismatch
	mov A, #I2C_EEPROM_WR
	sjmp rx_cmd_write_byte_and_finish

rx_cmd_get_eeprom_address_mismatch:
endif
;-----------------------------------------------------------
; Nieznana komenda
	mov A, #'?'
	sjmp rx_cmd_write_char_and_finish

;===========================================================
; Procedury

;-----------------------------------------------------------
; Zwraca w A wartość cyfry szesnastkowej przekazanej w kodzie ASCII w A
; C=0 jeśli sukces
hex_digit_value:
	cjne A, #'0', hex_digit_value_ne_0
hex_digit_value_ne_0:
	jc hex_digit_ret	; błąd (A < '0'), C ustawiony
	cjne A, #'9'+1, hex_digit_value_ne_9
hex_digit_value_ne_9:
	jnc hex_digit_over_9
	; między 0 a 9, C=1
	subb A, #'0'-1
	ret
hex_digit_over_9:
	cjne A, #'A', hex_digit_value_ne_A
hex_digit_value_ne_A:
	jc hex_digit_ret	; błąd (A > '9' i A < 'A'), C ustawiony
	cjne A, #'F'+1, hex_digit_value_ne_F
hex_digit_value_ne_F:
	cpl C
	jc hex_digit_ret	; błąd (A > 'F'), C ustawiony
	; między A a F, C=0
	subb A, #'A'-10
hex_digit_ret:
	ret

; Wczytuje z UART parametr - liczbę szestnastkową zapisaną w ASCII
; W B należy przekazać wczytany z UART znak
; Niszczy A, C; aktualizuje global_rx_state, rx_cmd_arg
; Wraca tylko, jeśli wczytano cały argument! Jest on wtedy zwrócony w A, ale dostępny również w rx_cmd_arg.
; Jeśli wystąpił błąd, skacze do rx_cmd_error.
; Jeśli argument nie jest jeszcze skompletowany, wraca poziom wyżej (odpowiednik 2 ret-ów stąd).
rx_cmd_collect_arg:
	mov A, global_rx_state
	; stany: 0 = inicjalizacja; 1 = wczytujemy starszą połówkę bajtu do młodszej połówki rx_cmd_arg; 2 = wczytujemy młodszą połówkę bajtu do rx_cmd_arg
	jnz rx_cmd_collect_arg_initialized
	mov rx_cmd_arg, #0	; zaczynamy kompletowanie od 0, potem będziemy or'ować
	sjmp rx_cmd_collect_arg_inc_state
rx_cmd_collect_arg_initialized:
	; obracamy połówki bajtu (młodsza połówka wczytana w poprzednim kroku wędruje do starszej, wyzerowana starsza idzie do młodszej)
	mov A, rx_cmd_arg
	swap A
	mov rx_cmd_arg, A
	; pobieramy wartość liczbową otrzymanej cyfry szesnastkowej (z kodu ASCII)
	mov A, B
	acall hex_digit_value
	jc rx_cmd_collect_arg_error	; C=1 - błąd
	; wartość otrzymanej cyfry umieszczamy w młodszej połówce bajtu
	orl A, rx_cmd_arg
	mov rx_cmd_arg, A
rx_cmd_collect_arg_inc_state:
	; zrobiliśmy kolejny krok
	inc global_rx_state
	mov A, global_rx_state
	cjne A, #3, rx_cmd_collect_arg_incomplete
	; to już był ostatni krok, zwracamy skompletowaną wartość
	mov A, rx_cmd_arg
rx_cmd_collect_arg_ret:
	ret
rx_cmd_collect_arg_incomplete:
	clr C
rx_cmd_collect_arg_error:
	; zdejmujemy ze stosu adres powrotu! (odwracamy skutki ACALL, które nas tu przywiodło)
	pop ACC
	pop ACC
	; wracamy z pominięciem bezpośredniego wołającego
	jnc rx_cmd_collect_arg_ret
	; obsługujemy błąd i wracamy z pominięciem bezpośredniego wołającego
	ajmp rx_cmd_error
