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
; Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2021, 2022, 2024 Aleksander Mazur

;===========================================================
; Stałe

ifdef	I2C_DISPLAY_WR
I2C_SPI_DISPLAY	equ	1
endif
ifdef	DISPLAY_TM1628
I2C_SPI_DISPLAY	equ	1
endif

; Rozmiar scratchpadu czujników DS18B20/DS18S20/DS1820
ds_scratchpad_size	equ 9
; rozmiar pełnego ID czujnika (family code na początku, 6 bajtów GUID i CRC8)
ow_id_size			equ 8

WATCHDOG_MAX		equ 22	; czas (w 8-sekundowych cyklach), po którym nadzorca zostanie zresetowany (przez odłączenie zasilania na 1 cykl = 8 sekund), jeśli nie przyśle nic na UART

;===========================================================
; Flagi

bseg
; wszystko musi się mieścić w zakresie zarezerwowanym w dseg (bit_addresable)

ifndef	SKIP_UART
; czy trwa wysyłanie bajtu na UART
; ustawiana po wpisaniu do SBUF
; zerowana w przerwaniu UART, jeśli TI
flag_tx_busy:			dbit 1
; czy odebrano bajt z UART do global_rx
; zerowana po pobraniu go
; ustawiana w przerwaniu UART, jeśli RI
flag_rx_busy:			dbit 1
; czy odebrano bajt z UART, podczas gdy była wciąż ustawiona flaga flag_rx_busy (i bajt przepadł)
flag_rx_overrun:		dbit 1
endif	;SKIP_UART
; flaga ustawiana w przerwaniu zegarowym co 8 sekund oraz komendą '!'
flag_timer:				dbit 1
; flaga jednokrotnie wstrzymująca ustawienie flag_timer z timera po użyciu komendy '!'
flag_timer_skip_once:	dbit 1
; czy trwa pomiar (= czy odliczamy global_measure do zera)
flag_measuring:			dbit 1
; czy minął czas pomiaru określony w global_measure
flag_measuring_timeout:	dbit 1
; czy wystąpił błąd podczas inicjalizacji pomiaru przez zewnętrzne czujniki temperatury (1-wire)
flag_no_ext_sensors:	dbit 1
; czy ponowić raz operację w razie błędu
flag_retry:				dbit 1
ifdef	I2C_TEMP_WR
; czy wystąpił błąd podczas inicjalizacji pomiaru przez wewnętrzny czujnik temperatury (TMP75 na I2C)
flag_no_int_sensor:		dbit 1
endif	;I2C_TEMP_WR
ifdef	I2C_SPI_DISPLAY
; czy w ogóle włączyć wyświetlacz w tym cyklu
flag_display_on:		dbit 1
; czy wyświetlono temperaturę na wyświetlaczu
flag_display_used:		dbit 1
; czy znaleźliśmy numer funkcji, której temperaturę wejściową pokażemy na wyświetlaczu
; (jeśli tak, to jest w display_func_idx)
flag_display_found_idx:	dbit 1
endif	;I2C_SPI_DISPLAY
ifdef	MATCH_ON_SEARCH_FAILURE
; czy owhl_match_rom_from_eeprom ma nadpisać global_ow_id odczytanym z EEPROM
flag_overwrite_ow_id:	dbit 1
endif	;MATCH_ON_SEARCH_FAILURE
; etykieta, której adres określa koniec używanego miejsca na flagi
flag_end:

;===========================================================
; Zmienne

dseg

; miejsce zarezerwowane na banki rejestrów R0-R7
register_bank_0:	ds 8
register_bank_1:	ds 8
register_bank_2:	ds 8
register_bank_3:	ds 8
; miejsce zarezerwowane na flagi (zmienne adresowalne bitowo)
bit_addresable:		ds (flag_end+7)/8

;-----------------------------------------------------------

; stan zegarka z momentu wyexpirowania watchdoga
global_rtcwd_weekday:	ds 1	; /API/ ; ustawiony najstarszy bit oznacza, że jest tu skopiowany czas
global_rtcwd_hours:		ds 1	; /API/
global_rtcwd_minutes:	ds 1	; /API/
global_rtcwd_seconds:	ds 1	; /API/
global_rtcwd_end:
global_rtcwd_buf		data global_rtcwd_weekday
global_rtcwd_len		equ (global_rtcwd_end-global_rtcwd_weekday)
; zegarek
global_rtc_weekday:	ds 1	; /API/ ; w razie zmiany wyzerować global_clock_settings_index
global_rtc_hours:	ds 1	; /API/
global_rtc_minutes:	ds 1	; /API/
global_rtc_seconds:	ds 1	; /API/
global_rtc_timer0:	ds 1
global_rtc_buf		data global_rtc_weekday

; indeks w ramach ostatnio stosowanego programu dobowego, liczony od 1
; używany głównie przez control_rtc
; oprócz tego należy ustawiać na 0 zawsze, gdy zmienił się program dobowy
; - podczas inicjalizacji (robi to pętla bzero_loop)
; - gdy zmieni się dzień tygodnia (timer0_interrupt)
; - gdy użytkownik przestawi dzień tygodnia (rx_cmd_set_clock_weekday)
global_clock_settings_index:	ds 1	; /API/

; bajt odebrany z UART; ważny, gdy flag_rx_busy
global_rx:			ds 1
; stan odbioru komendy z UART, używany wewnętrznie przez input.asm, ale zerowany tutaj w razie otrzymania danych w złym momencie albo za szybko (flag_rx_overrun)
global_rx_state:	ds 1
; ile razy jeszcze pominąć obsługę 8-sekundowego timera
global_timer_skip:	ds 1
; licznik watchdoga (liczący w dół od WATCHDOG_MAX do 0)
global_wdc:			ds 1
; stan "koprocedury" enumeracji czujników 1-wire
global_ow_diffpos:	ds 1

ifdef	CONSERVATIVE_CONTROL
; poprzednio wyliczone maski bezpośrednio sterujące przekaźnikami
; na początku inicjowane na zero, czyli nic nie włączamy, ale
; wszystko wyłączamy
control_mask_prev_or:		ds 1
control_mask_prev_and:		ds 1
endif

ifdef	I2C_SPI_DISPLAY
; Indeks funkcji, której należy użyć do wyświetlania temperatury.
; Przed wejściem do control_init_rtc jest to minimalny indeks, od którego
; należy rozpocząć poszukiwanie funkcji z ustawioną flagą ctl_flag_display.
; Po wyjściu z control_init_rtc, jeśli flaga flag_display_found_idx jest ustawiona,
; jest tu indeks funkcji, której należy użyć. Jeśli flaga jest wyczyszczona,
; należy pokazać zegarek.
display_func_idx:	ds 1
endif	;I2C_SPI_DISPLAY

;-----------------------------------------------------------
uninitialized:	; początek bloku zmiennych, których nie trzeba inicjować na 0 (tj. albo wcale nie trzeba, albo trzeba, ale na inną wartość)

; ile przerwań zegarowych ma jeszcze trwać pomiar (ważne, gdy flag_measuring)
global_measure:		ds 1
; liczba pozostałych funkcji do sprawdzenia przez MATCH ROM
global_ow_match_loop:	ds 1

; Parametry czasowe 1-wire
; Wszystkie opóźnienia muszą być większe od 0 (są licznikami DJNZ)
; Żeby cykl zapisu trwał co najmniej wymagane 60 µs:
;  ow_tLOW + ow_tWR = 52
; Żeby cykl odczytu trwał co najmniej wymagane 60 µs:
;  ow_tLOW + ow_tDSO + ow_tRD = 51
; Żeby samplowanie odbyło się przed wymaganymi 15 µs:
;  ow_tLOW + ow_tDSO = 10
; Czas po wysłaniu zera resetu i po odczekaniu 15 µs, w jakim musi się pojawić presence pulse
ow_tRST_def	equ 24
; Czas zera rozpoczynającego cykl zapisu/odczytu bitu
ow_tLOW_def	equ	1
; Czas po ustawieniu wyjścia 1-wire wartością wysyłanego bitu
ow_tWR_def	equ	51
; Czas po wysłaniu zera, a przed samplowaniem wejścia 1-wire
ow_tDSO_def	equ 9
; Czas po samplowaniu wejścia 1-wire
ow_tRD_def	equ 41
; Dodatkowe opóźnienie przed cyklami odczytu/zapisu w procedurze wyszukiwania
ow_SEARCH_DELAY_def	equ 0
ifdef	DISPLAY_TM1628
; Jasność wyświetlacza (0-8)
display_intensity_def	equ 4	; -> 8Bh = pulse width 10/16
else
; Jasność wyświetlacza (0-4)
display_intensity_def	equ 2
endif

ifdef	TUNE_1WIRE
ow_tune_start:
ow_tRST:	ds 1
ow_tLOW:	ds 1
ow_tWR:		ds 1
ow_tDSO:	ds 1
ow_tRD:		ds 1
ow_SEARCH_DELAY:	ds 1
display_intensity:	ds 1
ow_tune_end:

ow_tune_defaults_here macro
; Kolejność musi odpowiadać zmiennym w bloku ow_tune!
ow_tune_start_def:
	db ow_tRST_def
	db ow_tLOW_def
	db ow_tWR_def
	db ow_tDSO_def
	db ow_tRD_def
	db ow_SEARCH_DELAY_def
	db display_intensity_def
ow_tune_end_def:
endm

endif

; zmienne do użytku w control.asm
; ciągły blok masek sterowania
control_mask_start:
; maski bezpośrednio sterujące przekaźnikami
control_mask_direct_or:		ds 1
control_mask_direct_and:	ds 1
; maski sterowania pośredniego, do przeliczenia przez formuły
control_mask_indirect_or:	ds 1
control_mask_indirect_and:	ds 1
; maska używanych przekaźników (suma masek występujących w EEPROM)
control_mask_all_used:		ds 1
; 16 bitów, z których każdy odpowiada n-temu programowi w EEPROM; 0 oznacza, że nie został wykonany (czyli był problem z powiązanym czujnikiem)
; pierwszy bajt jest młodszy, tj. dotyczy programów 0-7
control_missing_sensors:	ds 2
; koniec ciągłego bloku masek sterowania
control_mask_end:
; blok nastaw - musi być pod offsetem control_mask_end! dzięki temu control_init_rtc jest krótsze o kolejny bajt
control_settings_block:		ds 3

; ID czujnika 1-wire
global_ow_id:		ds ow_id_size

local_scratchpad1:	ds ds_scratchpad_size
local_scratchpad2:	ds ds_scratchpad_size

;-----------------------------------------------------------
stack:	; miejsce na stos - stąd do końca RAMu

;===========================================================

cseg

;-----------------------------------------------------------
; Opóźnienie adekwatne do szybkości działania I2C
i2c_delay	macro
	nop
	nop
endm

bcall	macro where
ifdef	AT89C4051
	call where
else
	acall where
endif
endm

bjmp	macro where
ifdef	AT89C4051
	jmp where
else
	ajmp where
endif
endm

;-----------------------------------------------------------

org RESET
	sjmp start

ifndef	SKIP_UART
; bo jest tu 9 bajtów miejsca do TIMER0 (0Bh)
serial_received:
	; UART skończył odbierać znak
	jb flag_rx_busy, serial_overrun
	mov global_rx, SBUF
	setb flag_rx_busy
	reti
endif	;SKIP_UART

org EXTI0

org TIMER0
	bjmp timer0_interrupt

; a tu są 22 bajty do org SINT (23h)
; w sam raz na jakąś procedurę
ifdef	SDA
;-----------------------------------------------------------
; ACK i odczyt bajtu z I2C do akumulatora
; niszczy A, C, R7
i2c_ACK_shin:
	acall i2c_ACK
	;ajmp i2c_shin
	; tutaj musi być i2c_shin!
;-----------------------------------------------------------
; Odbiera bajt z I2C do akumulatora
; niszczy A, C, R7
i2c_shin:
	setb SDA
	mov R7, #8
i2c_shin_bit:
	i2c_delay
	setb SCL
	i2c_delay
	mov C, SDA
	rlc A
	clr SCL
	djnz R7, i2c_shin_bit
	ret
endif	;SDA

ifndef	SKIP_UART
org EXTI1

org TIMER1

org SINT
	jbc TI, serial_sent
serial_cont:
	jbc RI, serial_received
	reti
serial_sent:
	; UART skończył wysyłać znak
	clr flag_tx_busy
	sjmp serial_cont
serial_overrun:
	; UART odebrał znak, chociaż pętla główna nie obsłużyła jeszcze poprzedniego
	setb flag_rx_overrun
	reti
endif	;SKIP_UART

;===========================================================
; START

start:
	mov SP, #(stack-1)
	mov IE, #00010010b	; włączenie przerwań z UART0 i z timera 0, ale globalnie na razie przerwania wyłączone
	; inicjalizacja stanu portów; przekaźników nie przełączamy niepotrzebnie
	; inicjacja timerów 0 i 1 (1 na potrzeby UART0)
	mov TMOD, #00100001b	; tryb 2 (8-bitowy z autoreloadem) dla timera 1 i tryb 1 (16-bitowy) dla timera 0
	;mov TL1, #0FFh		; dla 57600 bodów
	;mov TH1, #0FFh
	mov TL1, #0FAh		; dla 9600 bodów
	mov TH1, #0FAh
	;mov TL1, #0E8h		; dla 2400 bodów
	;mov TH1, #0E8h
	mov TCON, #01010000b	; uruchomienie timerów 0 i 1
	; inicjacja portu UART - tryb 1 (8-bitowy UART z baudatem sterowanym timerem 1); włączenie odbioru
	mov SCON, #01010000b

	; zerowanie rejestrów R0-R7 we wszystkich bankach, wszystkich flag i zmiennych, które trzeba inicjować
	;mov R0, #(uninitialized-1)
	; zerowanie całego RAMu
	clr A
	mov R0, A
zero_loop:
	mov @R0, A
	djnz R0, zero_loop	; 24 cykle

	; inicjalizacja tych zmiennych i flag, które nie mają być wyzerowane
	setb flag_timer	; zaczynamy od natychmiastowego pomiaru
	mov global_wdc, #WATCHDOG_MAX
ifdef	I2C_SPI_DISPLAY
ifndef	DISPLAY_SWITCH_PORT
	setb flag_display_on	; włączamy raz, potem przez port szeregowy ewentualnie można zmienić
endif	;DISPLAY_SWITCH_PORT
endif	;I2C_SPI_DISPLAY

ifdef	TUNE_1WIRE
	; kopiujemy ow_tune_start_def do ow_tune_start i tak dalej
	mov R0, #ow_tune_start
ow_tune_copy_loop:
	mov A, R0
	add A, #ow_tune_start_def - ow_tune_rel - ow_tune_start
	movc A, @A + PC	; w momencie sumowania PC pokazuje na ow_tune_rel
ow_tune_rel:
	mov @R0, A
	inc R0
	cjne R0, #ow_tune_end, ow_tune_copy_loop
endif

	; inicjacja stanu
	setb EA			; włączenie przerwań

;===========================================================
; W tym bloku nie możemy polegać na tym, który bank rejestrów jest akurat włączony

main_pre_loop:
ifndef	SKIP_UART
	; przechodzimy na odbiór
	mov A, #10
	acall write_char
	; jeśli w międzyczasie coś dostaliśmy, to jeszcze wypiszemy kropkę nienawiści
	jnb flag_rx_overrun, main_rx_reset

;-----------------------------------------------------------
; Tu wchodzimy, gdy wystąpił overrun na wejściu z UART
main_rx_overrun:
	; Dostaliśmy niespodziewanie jakieś dane
	acall write_dot
; Zerujemy stan wejścia z UART, odblokowujemy odbiór i wracamy do pętli głównej
main_rx_reset:
	mov global_rx_state, #0	; reset stanu odbioru komendy
	clr flag_rx_overrun
	clr flag_rx_busy
endif	;SKIP_UART

;-----------------------------------------------------------
; Pętla główna
main_loop:
	jb flag_measuring_timeout, main_measuring_timeout
	jb flag_measuring, main_sleep	; podczas pomiaru nie robimy nic innego
	jbc flag_timer, main_timer
ifndef	SKIP_UART
	jb flag_rx_overrun, main_rx_overrun
	jb flag_rx_busy, main_rx_ok
endif	;SKIP_UART
main_sleep:
	orl PCON, #00000001b	; idle (setb IDL)
	sjmp main_loop

ifdef	TUNE_1WIRE
	ow_tune_defaults_here

	if	(ow_tune_end_def - ow_tune_start_def) <> (ow_tune_end - ow_tune_start)
		$error(ow_tune size mismatch)
	endif
endif

;-----------------------------------------------------------
; Tu wchodzimy raz na 8-sekundowy cykl (wg flag_timer)
main_timer:
	mov A, global_timer_skip
	jz main_timer_proceed
main_timer_skip:
	dec global_timer_skip
	sjmp main_sleep

;===========================================================
; W tym bloku wymuszamy użycie ostatniego banku rejestrów (#3)

ifndef	SKIP_UART
;-----------------------------------------------------------
; Tu wchodzimy, gdy bajt odebrany z UART czeka w global_rx
main_rx_ok:
	mov B, global_rx
	clr flag_rx_busy
	orl PSW, #00011000b	; przełączenie na 3 bank rejestrów (setb RS1,RS0)
	mov global_timer_skip, #2
	acall rx_char
	ajmp main_loop
endif	;SKIP_UART

;===========================================================
; W tym bloku wymuszamy użycie pierwszego (#0), ewentualnie drugiego (#1) banku rejestrów

CRC				equ R2
local_temp_h	equ R4
local_temp_l	equ R5

;-----------------------------------------------------------
; Tu wchodzimy raz na 8-sekundowy cykl (wg flag_timer)
; kiedy cykle nie są zablokowane przez global_timer_skip.
; Tutaj blokujemy wejście z UART i rozpoczynamy pomiary.
; flag_measuring i flag_measuring_timeout muszą być wyzerowane.
main_timer_proceed:
ifndef	SKIP_UART
	setb flag_rx_busy		; blokada wejścia z UART
endif	;SKIP_UART
	anl PSW, #11100111b		; przełączenie na #0 bank rejestrów (clr RS1,RS0)
ifndef	SKIP_UART
	; zaczynamy pisanie meldunku - jest to też informacja, że teraz nie przyjmujemy komend
	mov A, #13
	acall write_char
endif	;SKIP_UART
ifdef	I2C_SPI_DISPLAY
	; wygaszamy wyświetlacz
	; - mignięcie na czas pomiaru sygnalizuje, że coś się zmienia
	; - zmniejszamy pobór prądu, który jest potrzebny czujnikom
	clr A
	bcall display_dim
ifdef	DISPLAY_SWITCH_PORT
	mov C, DISPLAY_SWITCH_PORT
ifdef	DISPLAY_SWITCH_NEGATIVE
	cpl C
endif	;DISPLAY_SWITCH_NEGATIVE
	mov flag_display_on, C
endif	;DISPLAY_SWITCH_PORT
endif	;I2C_SPI_DISPLAY
ifdef	I2C_TEMP_WR
	; inicjujemy pomiar z czujnika wewnętrznego
	bcall int_sensor_start_measuring
	mov flag_no_int_sensor, C
	jc main_no_int_sensor
	setb flag_measuring
	;clr flag_measuring_timeout
	mov global_measure, #7	; typowo 220 ms, tu 10*8/225 s = 249 ms
endif
main_no_int_sensor:
	; inicjujemy pomiar z czujników zewnętrznych
	acall owhl_start_measuring
	mov flag_no_ext_sensors, C
	jc main_no_ext_sensors
ifdef	OW_PARASITE
	; podbijamy czas pomiaru do 750 ms
	mov global_measure, #OW_PARASITE	; 21*8/225 s = 747 ms
	; ten czas musi być większy niż czas pomiaru czujnika wewnętrznego, albo trzeba zamienić miejscami inicjalizację pomiaru, żeby dłuższy był później
else
ifdef	I2C_TEMP_WR
	; jeśli udało się wystartować pomiar czujnika wewnętrznego, to na
	; niego czekamy (flag_measuring_timeout ustawi się po upłynięciu
	; global_measure); jeśli nie, to musimy sami ustawić tę flagę
	jb flag_measuring, main_no_timeout_yet
endif
	setb flag_measuring_timeout	; jeśli nie chcemy czekać (nie ustawiamy global_measure), to musimy ustawić tą flagę
main_no_timeout_yet:
endif
	setb flag_measuring
main_no_ext_sensors:
ifndef	SKIP_UART
	acall write_clock
endif	;SKIP_UART
	; inicjujemy wykonywanie obliczeń i wykonujemy program zegarowy
	acall control_init_rtc
	jb flag_measuring, main_sleep
	; nie udało się zainicjować żadnego pomiaru - możemy od razu przejść do obliczeń
	sjmp main_measured

;-----------------------------------------------------------
; Tu wchodzimy, kiedy flag_measuring i minie czas określony w global_measure (lub w ogóle go nie było)
main_measuring_timeout:
	anl PSW, #11100111b	; przełączenie na #0 bank rejestrów (clr RS1,RS0)
ifdef	OW_PARASITE
	setb OW_PWR	; koniec pomiaru - wyłączamy silną jedynkę
else
	; czujniki, które wciąż mierzą, wysyłają 0
	acall ow_read_bit
	jnc main_sleep	; wracamy do pętli - flag_measuring_timeout pozostaje ustawione, bo czas minął, ale my nadal czekamy
endif
	; koniec pomiaru
	clr flag_measuring
	clr flag_measuring_timeout

;-----------------------------------------------------------
; Tu wchodzimy, gdy skończyły się pomiary lub żadnego nie udało się rozpocząć
; Pierwszy (#0) bank rejestrów jest już włączony
main_measured:
ifdef	I2C_TEMP_WR
	jb flag_no_int_sensor, main_measured_no_int_sensor
	; czytamy wynik pomiaru z czujnika wewnętrznego
	mov A, #'T'
	acall write_char
	bcall int_sensor_read_temp
	jnc main_measured_int_sensor
	; wystąpił błąd
	acall write_exclamation
	sjmp main_measured_int_sensor_end
main_measured_int_sensor:
	acall write_equals
	acall write_temperature
main_measured_int_sensor_end:
	acall write_semicolon
main_measured_no_int_sensor:
endif	;I2C_TEMP_WR
	jb flag_no_ext_sensors, main_measured_no_ext_sensors
main_loop_ext_sensors:
	setb flag_retry
main_loop_ext_sensors_retry:
	; szukamy czujników zewnętrznych
	acall ow_reset
	jnc main_loop_ext_sensor_reset
	; jeśli nie udał się już reset, to piszemy tylko !;
ifndef	SKIP_UART
	acall write_exclamation
endif	;SKIP_UART
	sjmp main_loop_ext_sensor_error_finish
main_loop_ext_sensor_reset:
	;setb RS0	; przełączenie na #1 bank rejestrów - najszybszy sposób alokacji 8 bajtów na lokalne zmienne
	acall owhl_enum_next
	; jeśli C=1, to w R4 mamy liczbę bitów ID, które udało się ustalić, nie możemy więc zniszczyć R4
	;clr RS0	; przełączenie spowrotem na #0 bank rejestrów
ifndef	SKIP_UART
	mov F0, C	; przechowujemy wartość C w takiej tam fladze w PSW
	acall main_write_ow_id
	jnb F0, main_handle_ext_sensor_fwd
else
	jnc main_handle_ext_sensor_fwd
endif	;SKIP_UART
main_loop_ext_sensor_error:
	; wystąpił błąd
ifndef	SKIP_UART
	acall write_exclamation
	; w R4 powinna tu dotrwać liczba bitów ID, które udało się ustalić (zwrócona przez owhl_enum_next)
	mov A, R4
	acall write_decimal
endif	;SKIP_UART
main_loop_ext_sensor_error_finish:
ifndef	SKIP_UART
	acall write_semicolon
endif	;SKIP_UART
	; raz się mogło nie udać
	jbc flag_retry, main_loop_ext_sensors_retry
	; nie możemy kontynuować enumeracji
	mov global_ow_diffpos, #0
main_match_missing_ext_sensors:
ifdef	MATCH_ON_SEARCH_FAILURE
	; sprawdźmy, czy czujniki, których ID mamy w EEPROM,
	; a których nie znaleźliśmy przez SEARCH ROM,
	; odpowiedzą na MATCH ROM
	acall control_iterate_functions
	jz main_finish_ext_sensors
	; tu wchodzimy tylko jeśli A>0
	mov global_ow_match_loop, A
	mov global_ow_id, #28h	; no cóż, tylko DS18B20
main_match_ext_sensors_loop:
	; w global_ow_match_loop jest liczba pozostałych funkcji, z których czujnikami powinniśmy zagadać przez MATCH ROM
	mov R3, global_ow_match_loop
	dec R3	; R3=indeks
	acall control_get_used_ptr
	anl A, @R1
	; 0 - funkcja nie została użyta
	jnz main_match_ext_sensors_next
	mov A, global_ow_match_loop
	dec A	; A=indeks
	acall control_get_function_address
	mov B, A
	acall eeprom_read_start
	jc main_match_ext_sensors_next
	; wybieramy czujnik na magistrali i pobieramy ID do global_ow_id
	setb flag_overwrite_ow_id
	acall owhl_match_rom_from_eeprom
	jc main_match_ext_sensors_next
	; czytamy jego scratchpad - jeśli się nie uda, milcząco go pomijamy
	; (bez sensu byłoby wypisywać ID czujników z EEPROM z wykrzyknikiem)
	mov R1, #local_scratchpad1
	acall owhl_read_scratchpad
	jnz main_match_ext_sensors_next
	; mały całe 8 bajtów ID poszukiwanego czujnika w global_ow_id oraz wczytany scratchpad
	; dopiero teraz wypisujemy ID czujnika
ifndef	SKIP_UART
	acall main_write_ow_id
	acall write_equals
endif
	; i obsługujemy scratchpad zakładając, że to czujnik temperatury
	acall main_handle_ext_temp_sensor_scratchpad_ok
ifndef	SKIP_UART
	acall write_semicolon
endif
main_match_ext_sensors_next:
	djnz global_ow_match_loop, main_match_ext_sensors_loop
endif	;MATCH_ON_SEARCH_FAILURE
; zaraz po endif musi być main_finish_ext_sensors, bo jeśli nie jest
; zdefiniowane MATCH_ON_SEARCH_FAILURE, to main_match_missing_ext_sensors
; musi od razu przechodzić do main_finish_ext_sensors
main_finish_ext_sensors:
	; deinicjalizacja magistrali 1-wire
ifdef	OW_PARASITE
	; silna jedynka już powinna być wyłączona od czasu przejścia przez main_measuring_timeout
	;setb OW_PWR
else
	clr OW_PWR	; wyłączamy zasilanie 1-wire
endif
;-----------------------------------------------------------
; Tu wchodzimy, gdy zakończyliśmy pomiary i możemy podsumować wyniki
main_measured_no_ext_sensors:
	; domyślnie wyłączamy przekaźniki skonfigurowane w EEPROM jako watchdog
	clr F0
	; no chyba, że watchdog wyexpirował
	djnz global_wdc, main_timer_cont
	; watchdog wyexpirował
	mov global_wdc, #WATCHDOG_MAX
	jb global_rtcwd_weekday.7, dont_overwrite_wd_exp
	; zapamiętujemy, kiedy pierwszy raz watchdog wyexpirował
	;mov global_rtcwd_weekday, global_rtc_weekday
	;mov global_rtcwd_hours, global_rtc_hours
	;mov global_rtcwd_minutes, global_rtc_minutes
	;mov global_rtcwd_seconds, global_rtc_seconds
	mov R0, #global_rtc_seconds+1
	mov R1, #global_rtcwd_seconds+1
main_wd_expired_loop:
	dec R0
	dec R1
	mov A, @R0
	mov @R1, A
	cjne R0, #global_rtc_weekday, main_wd_expired_loop
	setb global_rtcwd_weekday.7
dont_overwrite_wd_exp:
	; załączamy przekaźniki skonfigurowane w EEPROM jako watchdog
	setb F0
main_timer_cont:
	acall control_watchdog
ifndef	SKIP_UART
	jnc main_eeprom_ok
	; informujemy o awarii EEPROM
	mov A, #'E'
	acall write_char
	acall write_semicolon
main_eeprom_ok:
endif	;SKIP_UART
	acall control_missing
	acall control_indirect_masks
ifndef	SKIP_UART
	acall write_control_masks
endif	;SKIP_UART
	acall control_apply_direct_masks
ifndef	SKIP_UART
	acall write_relay_port
endif	;SKIP_UART
	ajmp main_pre_loop

main_handle_ext_sensor_fwd:
	; mamy ID czujnika w global_ow_id, a czujnik jest wybrany na magistrali 1-wire
	acall main_handle_ext_sensor

; bezpośrednio za musi być main_loop_ext_sensors_next!

main_loop_ext_sensors_next:
	; zrobiliśmy, co było można dla bieżącego czujnika
ifndef	SKIP_UART
	acall write_semicolon
endif	;SKIP_UART
	; jeśli to nie był ostatni czujnik, to wracamy do pętli enumeracji czujników 1-wire
	mov A, global_ow_diffpos
	jz main_loop_ext_sensors_success
	ajmp main_loop_ext_sensors

main_loop_ext_sensors_success:
	; skończyliśmy enumerować czujniki bez błędu - tylko wtedy kasujemy lacie
ifndef	SKIP_DS2406
	; kasujemy lacie wszystkim układom DS2406
	acall owhl_clear_latches_ds2406
endif
	sjmp main_match_missing_ext_sensors

;-----------------------------------------------------------
; Obsługuje czujnik o ID wczytanym do global_ow_id
; który jest już wybrany na magistrali 1-wire
main_handle_ext_sensor:
	; czy to czujnik temperatury?
	mov A, global_ow_id
ifndef	SKIP_DS18S20
	cjne A, #10h, family_code_not_10	; 10h = ds18s20 family code
	sjmp main_handle_ext_temp_sensor
family_code_not_10:
endif
	cjne A, #28h, family_code_not_28	; 28h = ds18b20 family code
	; znaleźliśmy cały numer seryjny czujnika temperatury, z którego umiemy odczytać temperaturę
main_handle_ext_temp_sensor:
ifndef	SKIP_UART
	acall write_equals
endif	;SKIP_UART
	mov R1, #local_scratchpad1
	acall owhl_read_scratchpad
	jz main_handle_ext_temp_sensor_scratchpad_ok
	; wystąpił błąd przy odczycie scratchpada
ifndef	SKIP_UART
	acall write_exclamation
endif	;SKIP_UART
	ret
family_code_not_28:
ifndef	SKIP_DS2406
	; obsługa DS2406 jako wejście
	cjne A, #12h, family_code_not_12	; 12h = DS2406 family code
	acall write_equals
	acall owhl_read_info_ds2406
endif
family_code_not_12:
ifndef	SKIP_DS2405
	; obsługa DS2405 jako wejście
	cjne A, #05h, family_code_not_05	; 05h = DS2405 family code
	acall write_equals
	acall owhl_read_info_ds2405
endif
family_code_not_05:
	ret
main_handle_ext_temp_sensor_scratchpad_ok:
	; mamy wczytany cały poprawny scratchpad
	mov R1, #local_scratchpad1
	acall owhl_get_temperature_from_scratchpad
	jnc main_handle_ext_temp_sensor_temp_ok
	; wystąpił błąd przy odczycie temperatury ze scratchpada
ifndef	SKIP_UART
	mov A, #'?'
	acall write_char
endif	;SKIP_UART
	ret
main_handle_ext_temp_sensor_temp_ok:
	; w tym miejscu local_temp_h:local_temp_l ma zawierać temperaturę w kodzie uzupełnieniowym do 2
	; przecinek jest między local_temp_h:local_temp_l
ifndef	SKIP_UART
	acall write_temperature
endif	;SKIP_UART
ifndef	SKIP_CTRL_TEMP
	ajmp control_temperature
else	;SKIP_CTRL_TEMP
	ret
endif	;SKIP_CTRL_TEMP

ifndef	SKIP_UART
; Wypisuje ID czujnika z global_ow_id na UART
main_write_ow_id:
	mov R1, #global_ow_id
	mov R7, #ow_id_size
	ajmp write_hex_bytes
endif

;===========================================================
; Moduły

$include (control.asm)
ifndef	SKIP_UART
$include (input.asm)
$include (output.asm)
endif	;SKIP_UART
$include (crc8.asm)
$include (1wire.asm)
$include (1wire_temp.asm)
ifndef	SKIP_DS2406
$include (1wire_ds2406.asm)
endif	;SKIP_DS2406
ifndef	SKIP_DS2405
$include (1wire_ds2405.asm)
endif	;SKIP_DS2405
$include (1wire_HL.asm)
ifdef	SDA
$include (i2c_eeprom.asm)
$include (i2c.asm)
else
$include (rom_data.asm)
endif	;SDA
ifdef	I2C_DISPLAY_WR
$include (i2c_display.asm)
endif	;I2C_DISPLAY_WR
ifdef	I2C_TEMP_WR
$include (i2c_tmp75.asm)
endif	;I2C_TEMP_WR
ifdef	SPI_STB
$include (spi.asm)
ifdef	DISPLAY_TM1628
$include (display_tm1628.asm)
endif	;DISPLAY_TM1628
endif	;SPI_STB
$include (timer.asm)

ifdef	AT89C4051
db	13,10,'Copyright ',0C2h,0A9h,' 2013-2024 Aleksander Mazur',13,10
endif	;AT89C4051

ifdef	SDA
END
endif	;SDA
