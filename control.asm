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
; Copyright (c) 2018, 2021, 2022 Aleksander Mazur
;
; Logika sterowania przekaźnikami
; Używa procedur obsługi EEPROM z i2c_eeprom.asm
; Procedury używają zmiennych control_*
;
; Schemat wywołań:
; control_init_rtc
; control_watchdog
; control_temperature
; control_temperature
; control_temperature
; control_temperature
; ...
; control_missing
; control_indirect_masks
; control_apply_direct_masks

;===========================================================

; Stałe opisujące strukturę nastaw w EEPROM
ctl_offset_watchdog		equ	7	; bajt z maską przekaźników sterowanych przez watchdoga
ctl_offset_count		equ 8	; bajt z liczbą zdefiniowanych funkcji (młodsze pół) i formuł (starsze pół). Funkcje zaczynają się zaraz za
ctl_offset_functions	equ 9	; offset definicji pierwszej funkcji - zaraz za ctl_offset_count
ctl_offset_f_flags		equ 7	; offset bajtu z flagami względem początku funkcji
ctl_offset_f_daily		equ 9	; offset tablicy offsetów programów dobowych na każdy dzień tygodnia (7 bajtów)
; Flagi funkcji w EEPROM
ctl_flag_cooling		equ 80h	; flaga oznaczająca, że program służy do chłodzenia, a nie grzania
ctl_flag_critical		equ 40h	; flaga oznaczająca, że w przypadku braku (awarii) czujnika należy włączyć przekaźniki sterowane bezpośrednio
ctl_flag_display		equ 20h	; flaga oznaczająca, że temperaturę należy wyświetlać na wyświetlaczu
ctl_flag_formula		equ 08h	; flaga oznaczająca, że w 3 najmłodszych bitach jest numer wynikowego bitu sterowania pośredniego

;===========================================================
; API

;-----------------------------------------------------------
; Obsługuje przekaźniki watchdoga
; Wejście: flaga F0 określa, czy watchdog wyexpirował (wtedy włączamy przekaźniki)
; Zwraca C=1, jeśli wystąpił błąd odczytu z pamięci EEPROM; C=0, jeśli sukces
; Niszczy A, B, C, R7
control_watchdog:
	mov B, #ctl_offset_watchdog
	acall eeprom_read_byte_at
	jc control_watchdog_ret
	; maska przekaźników watchdoga jest w A
	orl control_mask_all_used, A
	; jeśli przekaźniki mają zostać wyłączone, to po prostu nie ruszamy masek innych niż global_mask_all_used
	jb F0, control_turn_on
control_watchdog_ret:
	ret

;-----------------------------------------------------------
; Inicjalizuje maski sterowania i realizuje program zegarowy
; Niszczy A, B, C, R1, R6, R7, F0
control_init_rtc:
ifdef	I2C_SPI_DISPLAY
	clr flag_display_used
	clr flag_display_found_idx
	jnb flag_display_on, control_skip_display
	; szukamy funkcji z włączoną flagą ctl_flag_display
	; o numerze większym lub równym display_func_idx
	acall control_iterate_functions
	setb C
	subb A, display_func_idx
	jc control_skip_display
	inc A
	mov R0, A		; R0 = liczba pozostałych funkcji w EEPROM (> 0)
	mov R3, display_func_idx	; R3 = bieżący indeks funkcji liczony od 0
control_find_display_loop:
	acall control_read_flags
	jc control_skip_display
	acall i2c_shin
	; A = flagi
	acall eeprom_read_stop
	jnb ACC.5, control_find_display_next	; ACC.5 = ctl_flag_display
	; znaleźliśmy
	mov display_func_idx, R3
	setb flag_display_found_idx
	sjmp control_skip_display
control_find_display_next:
	inc R3
	djnz R0, control_find_display_loop
control_skip_display:
endif	;I2C_SPI_DISPLAY
	; zerujemy maski sterowania
	clr A
	mov R1, #control_mask_start
control_init_loop:
	mov @R1, A
	inc R1
	cjne R1, #control_mask_end, control_init_loop
;control_rtc:
	; offset 7 offsetów programu zegarowego = 0
	clr A
	acall control_read_daily_program
	jc control_ret
	; mamy wczytany control_settings_block,
	; a w B mamy indeks pozycji użytego programu dobowego
	; do porównania z, a następnie do umieszczenia w
	; global_clock_settings_index
	mov R1, #control_settings_block
	mov A, @R1
	; pierwszy bajt nastaw - maska przekaźników do załączenia
	acall control_turn_on
control_rtc_loop:
	mov A, @R1
	; drugi bajt nastaw - maska przekaźników do wyłączenia
	orl control_mask_all_used, A
	inc R1
	cjne R1, #control_settings_block + 3, control_rtc_loop
	; trzeci bajt nastaw - maska przekaźników do chwilowego załączenia
	xch A, B
	cjne A, global_clock_settings_index, control_rtc_switch_on
	; A musiało być równe global_clock_settings_index, więc C=0
control_ret:
	ret
control_rtc_switch_on:
	; A = nowy global_clock_settings_index
	; B = maska do załączenia
	mov global_clock_settings_index, A
	xch A, B
	;clr C	; tak naprawdę nie potrzebujemy wyniku w C
	;ajmp control_turn_on
;-----------------------------------------------------------
; Aplikuje maskę przekaźników (podaną w A) w celu załączenia
control_turn_on:
	orl control_mask_direct_or, A
ifdef	CONSERVATIVE_CONTROL
	orl control_mask_prev_or, A
endif
; Aplikuje maskę przekaźników (podaną w A) w celu pozostawienia obecnego stanu bez zmian (tj. anuluje wyłączanie)
control_turn_neutral:
	orl control_mask_direct_and, A
ifdef	CONSERVATIVE_CONTROL
	orl control_mask_prev_and, A
endif
control_ret2:
	ret
; Jeśli celem jest wyłączenie przekaźników, to nie trzeba nic wołać,
; bo taki jest domyślny stan po control_init. Trzeba tylko pamiętać
; (w każdym z 3 przypadków) o zor'owaniu maski z control_mask_all_used.
; Aplikacja masek wg programu zegarowego i watchdoga musi pomijać
; CONSERVATIVE_CONTROL

;-----------------------------------------------------------
; Realizuje programy, których czujniki nie zostały odnalezione.
; W przypadku programu krytycznego włączamy jego przekaźniki,
; a niekrytycznego - wyłączamy (tj. w każdym przypadku dołączamy maskę
; do control_mask_all_used). Aktualizujemy też flagi sterowania pośredniego.
; Niszczy A, B, C, R0, R1, R2(CRC), R3, R6, R7
control_missing:
	acall control_iterate_functions
	jz control_missing2	; nie ma żadnych funkcji w EEPROM lub wystąpił błąd
	mov R0, A		; R0 = liczba funkcji w EEPROM (>0)
	mov R3, #0		; R3 = bieżący indeks funkcji liczony od 0
control_missing_loop:
	acall control_get_used_ptr
	anl A, @R1
	; 0 - funkcja nie została użyta
	jnz control_missing_next
	; czytamy flagi
	acall control_read_flags
	jc control_missing_next
	acall i2c_shin
	; A = flagi
	mov R2, A
	acall i2c_ACK_shin	; zakładamy, że ctl_offset_f_flags + 1 = ctl_offset_f_relays
	mov R6, A		; R6 = maska bezpośredniego sterowania przekaźnikami
	orl control_mask_all_used, A	; nie powinno zaszkodzić nawet, jeśli funkcja była użyta
	acall eeprom_read_stop
	mov A, R2
	mov C, ACC.6	; C = ACC.6 (ctl_flag_critical)
	; obliczamy maskę sterowania pośredniego
	acall control_calc_direct_mask
	mov R7, A		; R7 = maska sterowania pośredniego
	; wyznaczamy akcję do wykonania na maskach - kompatybilną z
	; control_calc_direct, właściwą dla control_apply_action,
	; czyli:
	; - jeśli funkcja jest krytyczna -> -1 - należy załączyć przekaźniki
	; - w przeciwnym przypadku -> 0 - należy wyłączyć przekaźniki
	; flaga ctl_flag_critical jest w C
	clr A
	subb A, #0
	; wykonujemy akcję
	acall control_apply_action
control_missing_next:
	inc R3
	djnz R0, control_missing_loop
control_missing2:
ifdef	I2C_SPI_DISPLAY
	jb flag_display_on, control_display_cont
	; następnym razem zegar, na razie wyświetlacz wyłączony
	mov display_func_idx, #-1
	ret
control_display_cont:
	jnb flag_display_found_idx, control_display_clock
	; flag_display_found_idx ustawiona -> temperatura na wyświetlaczu
	inc display_func_idx
	jb flag_display_used, control_display_finish
	; lub informujemy, że temperatury nie ma
	bcall display_missing
control_display_finish:
	; opóźnienie między rozkazami wysyłanymi do wyświetlacza (R0 = 0)
	djnz R0, $
	; zapalamy wyświetlacz na pół gwizdka
ifdef	TUNE_1WIRE
	mov A, display_intensity
else
	mov A, #display_intensity_def
endif
	bjmp display_dim
control_display_clock:
	; flag_display_found_idx wyczyszczona -> zegar na wyświetlaczu
	bcall display_clock
	mov display_func_idx, #0
	sjmp control_display_finish
else
	ret
endif	;I2C_SPI_DISPLAY

ifndef	SKIP_CTRL_TEMP
;-----------------------------------------------------------
; Realizuje programy przypisane do czujnika o ID w global_ow_id
; Jego temperatura ma być dana w local_temp_h:local_temp_l
; Zapalamy odpowiednie bity w control_missing_sensors.
; Niszczy A, B, C, F0, R0, R1, R2(CRC), R3, R4(local_temp_h), R5(local_temp_l), R6, R7
; Niszczy też local_scratchpad1 i local_scratchpad2 oraz control_settings_block.
control_temperature:
	acall control_iterate_functions
	jz control_ret2	; nie ma żadnych funkcji w EEPROM lub wystąpił błąd
	; zachowujemy temperaturę, bo programy różnicowe ją niszczą
	mov local_scratchpad1 + 0, local_temp_h
	mov local_scratchpad1 + 1, local_temp_l
	mov R0, A		; R0 = liczba funkcji w EEPROM (>0)
	mov R3, #0		; R3 = bieżący indeks funkcji liczony od 0
control_temperature_loop:
	; sprawdzamy, czy funkcja pod indeksem R3 jest zdefiniowana dla czujnika, którego ID mamy w global_ow_id
	acall control_get_function_address
	mov B, A
	acall eeprom_read_start
	jc control_temperature_next
	; w EEPROM ma pasować 6 bajtów poczynając od drugiego w global_ow_id (tj. środek, bez family code i CRC8)
	mov R1, #(global_ow_id + 1)
control_temperature_match:
	acall i2c_shin
	mov B, A
	mov A, @R1
	cjne A, B, control_temperature_stop
	acall i2c_ACK
	inc R1
	cjne R1, #(global_ow_id + 7), control_temperature_match
	; cały ID pasuje; następny i2c_shin odczyta bajt spod ctl_offset_f_diff
	; czytamy zatem bajt diff
	acall i2c_shin
	jnz control_temperature_diff
control_temperature_abs:
	acall i2c_ACK
	; odtwarzamy zachowaną temperaturę
	; (jakiś program różnicowy mógł ją zniszczyć w poprzedniej iteracji)
	mov local_temp_h, local_scratchpad1 + 0
	mov local_temp_l, local_scratchpad1 + 1
	sjmp control_temperature_known
control_temperature_diff:
	; program różnicowy - funkcja wymaga różnicy temperatur 2 czujników
	; odjemną już mamy, odjemnik musimy pobrać z czujnika
	acall eeprom_read_stop
	mov B, A	; B = adres ID czujnika, którego temperaturę musimy odjąć od local_temp
	acall eeprom_read_start
	jc control_temperature_next
	; zainicjowaliśmy odczyt z EEPROM, możemy pobrać scratchpad z czujnika
	acall owhl_read_second_scratchpad
	; odczyt z EEPROM jest zatrzymany
	jc control_temperature_next
	; odejmujemy temperatury
	acall control_temp_diff
	jc control_temperature_next
	; zaczynamy odczyt z EEPROM od miejsca, w którym przerwaliśmy
	acall control_read_flags
	jc control_temperature_next
control_temperature_known:
	; tutaj wchodzimy w stanie po ACK lub po zainicjowaniu odczytu
	; w tym bloku (od control_temperature_known do control_temperature_next)
	; używamy rejestrów R2 i R6, więc nie używamy procedur obsługi 1-wire
	; (które też ich używają)
	acall i2c_shin
	mov R2, A	; R2 = flagi
	acall i2c_ACK_shin
	push ACC	; maska bezpośredniego sterowania przekaźnikami - na stos
	; musimy przerwać odczyt, żeby pobrać dane z właściwego programu dobowego
	acall eeprom_read_stop
ifdef	I2C_SPI_DISPLAY
	jnb flag_display_on, control_display_handled
	mov A, R2
	jnb ACC.5, control_display_handled	; ctl_flag_display
	bcall display_temperature
control_display_handled:
endif	;I2C_SPI_DISPLAY
	acall control_get_function_address
	add A, #ctl_offset_f_daily
	acall control_read_daily_program
	pop ACC
	jc control_temperature_next
	; mamy nastawioną temperaturę w control_settings_block
	; pierwsze 2 bajty to wartość nadająca się od razu do porównania z local_temp_h:local_temp_l
	; trzeci bajt to histereza: starsza połówka to wartość całkowita, a młodsza - po przecinku
	; bierzemy odpowiedzialność za wykonanie funkcji - oznaczymy ją
	; jako użytą (przez ustawienie bitu w control_missing_sensors),
	; więc control_missing nic już z nią nie zrobi
	mov R6, A		; R6 = maska bezpośredniego sterowania przekaźnikami
	orl control_mask_all_used, A
	; obliczamy maskę sterowania pośredniego
	mov A, R2
	acall control_calc_direct_mask
	mov R7, A		; R7 = maska sterowania pośredniego
	; wyznaczamy akcję do wykonania na maskach
	acall control_calc_direct
	; wykonujemy akcję
	acall control_apply_action
	; oznaczamy funkcję jako użytą
	acall control_get_used_ptr
	orl A, @R1
	mov @R1, A
control_temperature_next:
	inc R3
	djnz R0, control_temperature_loop
	ret
control_temperature_stop:
	acall eeprom_read_stop
	sjmp control_temperature_next

endif	;SKIP_CTRL_TEMP

;-----------------------------------------------------------
; Przelicza maski sterowania pośredniego (control_mask_indirect_*)
; przy pomocy formuł w EEPROM i aktualizuje maski bezpośrednio
; sterujące przekaźnikami (control_mask_direct_*)
; Niszczy A, B, C, R0, R1, R6, R7
control_indirect_masks:
	acall control_iterate_functions
	; A może być 0, ale tutaj to nie problem, natomiast w razie C=1 R0 jest niezdefiniowane
	jc control_ret3
	; mamy "count" w R0, liczba funkcji jest w starszej połówce, a liczba formuł - w młodszej
	; w A mamy liczbę funkcji
	swap A
	add A, #ctl_offset_functions
	mov B, A		; B = adres pierwszego bajtu za definicjami funkcji, czyli początek formuł
	mov A, R0
	anl A, #00001111b
	jz control_ret3	; nie ma żadnych formuł
	mov R0, A		; R0 = liczba formuł (> 0)
	; teraz czytamy R0 3-bajtowych bloków z EEPROM poczynając od adresu w B
	acall eeprom_read_start
	jnc control_indirect_formula_no_ack
control_ret3:
	ret
	; nie możemy zacząć od ACK, ale przed każdym następnym odczytem musimy potwierdzić poprzedni
	; ale ostatniego znowu nie możemy potwierdzić, bo zamiast tego musimy wysłać NAK (robi to eeprom_read_stop)
control_indirect_formula:
	acall i2c_ACK
control_indirect_formula_no_ack:
	; czytamy 3 bajty definicji formuły do control_settings_block
	acall control_read_settings_block
	; formuła w control_settings_block; kolejne bajty to:
	; 0: maska warunku (do zastosowania do control_mask_indirect_{and,or})
	; 1: maska sterowania pośredniego (sterowanie pośrednie kaskadowe)
	; 2: maska sterowania bezpośredniego (sterowanych przekaźników)
	; w A mamy gratis trzeci bajt formuły, czyli maskę sterowanych przekaźników
	orl control_mask_all_used, A
	mov R6, A							; R6 = maska bezpośredniego sterowania przekaźnikami
	clr A	; 0 -> akcja = wyłącz
	mov R7, A
	mov R1, #control_mask_indirect_or	; control_mask_indirect_or musi być tuż przed control_mask_indirect_and!
control_indirect_formula_loop:
	; w pierwszym przebiegu pętli R1=control_mask_indirect_or i C=0 (po control_read_settings_block)
	;  i wtedy ewentualnie akcja = włącz (czyli A|=-1)
	; w drugim przebiegu pętli R1=control_mask_indirect_and i C=1 (po cjne niżej)
	;  i wtedy ewentualnie akcja = zostaw (czyli A|=+1)
	; czy w control_mask_indirect_{and,or} na pozycjach maskowanych przez warunek formuły są same jedynki?
	mov A, control_settings_block
	cpl A
	orl A, @R1
	; A = control_mask_indirect_{and,or} OR NOT control_settings_block
	inc A
	; A=0 -> są same jedynki
	jnz control_indirect_skip
	; A=0; musimy zamienić C=0 na -1 a C=1 na +1
	rlc A
	rl A
	dec A
	; i orujemy z akcją w R7
	orl A, R7
	mov R7, A
control_indirect_skip:
	inc R1
	cjne R1, #control_mask_indirect_or + 2, control_indirect_formula_loop
	mov A, R7
	mov R7, control_settings_block + 1	; R7 = maska sterowania pośredniego
	acall control_apply_action
	djnz R0, control_indirect_formula
	; koniec
	ajmp eeprom_read_stop

;-----------------------------------------------------------
; Aplikuje obliczone maski bezpośrednio sterujące przekaźnikami
; (control_mask_direct_*)
; Niszczy A
control_apply_direct_masks:
	; RELAY_PORT &= control_mask_direct_and | ~control_mask_all_used | control_mask_direct_or [| control_mask_prev_and]
	mov A, control_mask_all_used
	cpl A
	orl A, control_mask_direct_and
	orl A, control_mask_direct_or
ifdef	CONSERVATIVE_CONTROL
	; wyłączamy tylko to, co i poprzednio chcieliśmy wyłączyć
	orl A, control_mask_prev_and
endif
	; zera na pozycjach, które należy wyłączyć
ifdef	CONTROL_NEGATIVE
	cpl A
	orl RELAY_PORT, A
else
	anl RELAY_PORT, A
endif
	; RELAY_PORT |= control_mask_direct_or & control_mask_all_used [& control_mask_prev_or]
	mov A, control_mask_all_used
	anl A, control_mask_direct_or
ifdef	CONSERVATIVE_CONTROL
	; włączamy tylko to, co i poprzednio chcieliśmy włączyć
	anl A, control_mask_prev_or
endif
	; jedynki na pozycjach, które należy włączyć
ifdef	CONTROL_NEGATIVE
	cpl A
	anl RELAY_PORT, A
else
	orl RELAY_PORT, A
endif
ifdef	CONSERVATIVE_CONTROL
	mov control_mask_prev_or, control_mask_direct_or
	mov control_mask_prev_and, control_mask_direct_and
endif
	; koniec
	ret

;===========================================================
; Procedury wewnętrzne

ifndef	SKIP_CTRL_TEMP
;-----------------------------------------------------------
; Wyznacza akcję do wykonania w wyniku porównania bieżącej temperatury
; z local_temp_h:local_temp_l z nastawioną temperaturą podaną
; w control_settings_block (odczytaną z programu temperaturowego)
; przy uwzględnieniu flagi chłodzenia podanej w najstarszym bicie R2.
; Zwraca w A:
; -1 - należy załączyć przekaźniki
; +1 - należy zostawić przekaźniki w obecnym stanie
;  0 - należy wyłączyć przekaźniki
; Niszczy A, B, C
control_calc_direct:
	; najpierw obliczymy wynik, jak gdyby to był program ogrzewania, a potem ewentualnie go zanegujemy
	; obliczamy T_bieżąca - T_nastawiona
	clr C
	mov A, local_temp_l
	subb A, control_settings_block + 1
	mov B, A
	; B = LSB wyniku
	mov A, local_temp_h
	subb A, control_settings_block + 0
	; A = MSB wyniku
	mov C, ACC.7	; teraz C=0, jeśli wyszła liczba nieujemna, czyli T_bieżąca - T_nastawiona >= 0
	jnc control_calc_direct_heat_on_off
	; teraz dodamy do (ujemnego) wyniku histerezę i jeśli zostanie na minusie, to T_bieżąca >= T_nastawiona - T_histereza
	; histereza jest zapisana na jednym bajcie, fixed point 4.4
	push ACC
	mov A, control_settings_block + 2
	swap A
	anl A, #11110000b
	add A, B	; interesuje nas tylko bit przeniesienia z LSB
	mov A, control_settings_block + 2
	swap A
	anl A, #00001111b
	pop B
	addc A, B
	rlc A	; teraz C=0, jeśli wyszła liczba nieujemna, czyli T_bieżąca - T_nastawiona + T_histereza >= 0
	jc control_calc_direct_heat_on_off
	; pozycja neutralna
	mov A, #1
	; w tym przypadku negowanie nie ma znaczenia, nie musimy więc sprawdzać flagi chłodzenia
	ret
control_calc_direct_heat_on_off:
	; C=0 -> wyłączamy ogrzewanie
	; C=1 -> załączamy ogrzewanie
	clr A
	subb A, #0
	; w A mamy 0 albo -1
	; sprawdzamy, czy to może jednak program chłodzenia
	mov B, R2
	jnb B.7, control_ret4	; ctl_flag_cooling
	; negujemy wynik
	cpl A	; -1 -> 0, 0 -> -1
control_ret4:
	ret

endif	;SKIP_CTRL_TEMP

;-----------------------------------------------------------
; Aplikuje akcję zwróconą przez control_calc_direct (w A) na maskach
; sterowania bezpośredniego (w R6) i pośredniego (w R7).
control_apply_action:
	; 0 - wyłączamy przekaźniki - nie trzeba nic więcej robić
	jz control_ret5
	; -1 - należy załączyć przekaźniki
	; +1 - należy zostawić przekaźniki w obecnym stanie
	rlc A		; rozróżniamy po najstarszym bicie A
	; C=1 - należy załączyć przekaźniki
	; C=0 - należy zostawić przekaźniki w obecnym stanie
	; blokujemy wyłączenie
	mov A, R6
	orl control_mask_direct_and, A
	mov A, R7
	orl control_mask_indirect_and, A
	jnc control_ret5
	; wymuszamy załączenie
	mov A, R6
	orl control_mask_direct_or, A
	mov A, R7
	orl control_mask_indirect_or, A
control_ret5:
	ret

;-----------------------------------------------------------
; Wczytuje z EEPROM 3-bajtowy blok nastaw programu dobowego właściwych
;  dla aktualnego czasu zegarowego.
; Wejście: A - offset (w EEPROM) początku 7-bajtowej tablicy offsetów
;  programów na każdy dzień tygodnia.
; Zwraca C=0, gdy udało się wczytać parametry do control_settings_block.
;  Wówczas zwraca też indeks pozycji w użytym programie dobowym (w B).
; Zwraca C=1, gdy wystąpił błąd komunikacji z EEPROM lub nie ma bloku
;  nastaw właściwego dla bieżącego czasu.
; Zostawia magistralę I2C w stanie wolnym.
; Niszczy A, B, C, R1, R6, R7, F0
control_read_daily_program:
	add A, global_rtc_weekday
	; w A jest adres offsetu programu na bieżący dzień tygodnia
	mov B, A
	acall eeprom_read_byte_at
	jc control_ret6
	; w A jest offset programu na bieżący dzień tygodnia
	; albo 0, jeśli takowy nie jest określony
	jnz control_read_daily_program_not_empty
	setb C
control_ret6:
	ret
control_read_daily_program_not_empty:
	mov B, A
	acall eeprom_read_start
	jc control_ret6
	; jesteśmy w bloku godzin/minut BCD (po 2 bajty) zakończonego
	; terminatorem - pojedyncznym bajtem FF
	setb F0		; faza pętli: 1 - szukamy indeksu po godzinie; 0 - szukamy końca programu (nie zwiększamy już R6)
	clr A
	mov R1, A	; indeks elementu programu, aktualizowany aż do końca
	mov R6, A	; indeks elementu programu właściwego dla bieżącej godziny i minuty
control_read_daily_program_entry:
	; wczytujemy godzinę (z flagą końca na najstarszym bicie) i minutę początkową elementu programu
	acall i2c_shin		; A = godzina (z flagą)
	; zachowujemy godziny (z flagą) i odczytujemy minuty
	mov B, A
	acall i2c_ACK_shin	; A = minuta
	; jesteśmy na kolejnej pozycji programu (liczona od 1)
	inc R1
	; jeśli znaleźliśmy już właściwą pozycję, to teraz tylko pomijamy pozostałe
	jnb F0, control_read_daily_program_dont_cmp
	; odejmujemy od czasu podanego na bieżącej pozycji programu bieżący czas zegarowy
	setb C	; dzięki ustawionemu tutaj bitowi pożyczki, końcowo flaga będzie ustawiona również przy czasach równych sobie
	clr EA	; blokujemy przerwania, żeby stan zegara nie zmienił się w trakcie
	subb A, global_rtc_minutes
	mov A, B			; A = godzina
	anl A, #00111111b	; dziesiątkom godzin wystarczy zakres 0-3
	subb A, global_rtc_hours
	setb EA	; zegarek może sobie chodzić dalej
	; jeśli C=1, to bieżący czas jest równy lub późniejszy niż czas początkowy bieżącego elementu programu
	; jeśli C=0, to właśnie przejechaliśmy właściwy element programu; zostawimy R6 = R1 - 1, a R1 pojedzie dalej
	mov F0, C
control_read_daily_program_dont_cmp:
	jnb F0, control_read_daily_program_leave_pos
	inc R6
control_read_daily_program_leave_pos:
	jb B.7, control_read_daily_program_end	; flaga końca oznacza, że przetworzyliśmy ostatnią pozycję z czasem
	acall i2c_ACK		; potwierdzamy odczyt bajtu z minutami, będziemy czytać bajt z godzinami z następnej pozycji
	sjmp control_read_daily_program_entry
control_read_daily_program_end:
	; jesteśmy w stanie przed i2c_ACK/NAK
	; R1 = liczba pozycji programu (na pewno > 0)
	; R6 = indeks pozycji programu, której powinniśmy użyć, liczony od 1
	mov A, R6
	jnz control_read_daily_program_start
	; jeśli mamy użyć pozycji 0, to znaczy, że na pierwszej pozycji już była za późna godzina; w takim wypadku użyjemy ostatniej pozycji
	mov A, R1
	; w A jest indeks pozycji programu, której mamy użyć, liczony od 1
	; czyli tyle 3-bajtowych bloków musimy wczytać, zapamiętując tylko ostatni z nich
	mov R6, A
control_read_daily_program_start:
	; w R6, ale też w A jest indeks pozycji w programie liczony od 1
	; zachowujemy go w B
	mov B, A
control_read_daily_program_block:
	; w każdym kroku pętli jesteśmy w stanie przed i2c_ACK/NAK
	; w R6 jest liczba pozostałych obrotów pętli
	; czytamy 3 bajty pod local_settings_block
	acall i2c_ACK
	acall control_read_settings_block
	djnz R6, control_read_daily_program_block
	; sukces
	clr C
	ajmp eeprom_read_stop

;-----------------------------------------------------------
; Pobiera liczbę definicji funkcji w EEPROM do A.
; W razie niepowodzenia zwraca A=0 i C=1.
; W razie powodzenia zwraca też cały bajt spod ctl_offset_count w R0.
; Niszczy A, B, C, R0, R7
control_iterate_functions:
	mov B, #ctl_offset_count
	acall eeprom_read_byte_at
	jc control_ret0
	; mamy "count" w A, liczba funkcji jest w starszej połówce
	mov R0, A
	swap A
	anl A, #00001111b
	ret
control_ret0:
	clr A
	ret

;-----------------------------------------------------------
; Oblicza adres w EEPROM funkcji pod indeksem danym w R3.
; Zwraca go w A.
control_get_function_address:
	; A = R3 * 0x10 + offset początku funkcji
	mov A, R3
	swap A
	add A, #ctl_offset_functions
	ret

;-----------------------------------------------------------
; Oblicza wskaźnik na bit informujący o tym, czy funkcja o indeksie
; danym w R3 została użyta.
; Zwraca:
;  R1 - wskaźnik na bajt, gdzie jest przechowywany owy bit
;   A - maska w w/w bajcie wyłuskująca owy bit
; Niszczy A, B, C, R1
control_get_used_ptr:
	mov A, R3
	mov B, #8
	div AB
	; A = indeks bajtu
	; B = indeks bitu w ramach bajtu
	add A, #control_missing_sensors
	mov R1, A
; Oblicza maskę, która ma zapalony tylko jeden bit.
; Wejście: B = indeks bitu do zapalenia jako jedyny w masce
; Wyjście: A = maska
; Niszczy A, B
control_get_mask_1bit:
	; przerabiamy indeks bitu na maskę
	mov A, #1
	; obracamy jedynkę w lewo o jeden raz więcej, niż trzeba (od 1 do 8 obrotów)
	;inc B	; równie dobrze możemy obrócić akumulator 256 razy zamiast 0
control_get_mask_1bit_loop:
	rl A
	djnz B, control_get_mask_1bit_loop
	; cofamy ostatni nadmiarowy obrót
	;rr A
	ret

;-----------------------------------------------------------
; Oblicza maskę sterowania pośredniego na podstawie bajtu flag (ctl_offset_f_flags)
; Wejście: A = wartość bajtu spod ctl_offset_f_flags danej funkcji
; Wyjście: A = maska (z jednym bitem lub cała wyzerowana)
; Niszczy A, B
control_calc_direct_mask:
	jnb ACC.3, control_ret0	; ctl_flag_formula
	; najmłodsze 3 bity akumulatora to numer bitu w masce
	anl A, #00000111b
	mov B, A
	; obliczamy właściwą maskę
	sjmp control_get_mask_1bit

;-----------------------------------------------------------
; Inicjuje odczyt bajtu z flagami funkcji o indeksie danym w R3.
; Niszczy A, B, C, R7
control_read_flags:
	acall control_get_function_address
	add A, #ctl_offset_f_flags
	mov B, A
	ajmp eeprom_read_start

ifndef	SKIP_CTRL_TEMP
;-----------------------------------------------------------
; Dekoduje temperaturę z local_scratchpad2, odejmuje ją od temperatury
; trzymanej w 2 pierwszych bajtach local_scratchpad1 (MSB, potem LSB),
; a wynik umieszcza w local_temp_h:local_temp_l.
; Niszczy A, C, R1
; Zwraca C=0, jeśli sukces, a C=1, jeśli wystąpił błąd dekodowania
; temperatury z local_scratchpad2.
control_temp_diff:
	mov R1, #local_scratchpad2
	acall owhl_get_temperature_from_scratchpad	; nadpisuje l_temp_{h:l}
	jc control_ret7
	;mov A, #'-'
	;acall write_char
	;acall write_temperature
	; odejmujemy temperatury: stara minus nowa
	mov A, local_scratchpad1 + 1	; stara temp_l
	clr C
	subb A, local_temp_l
	mov local_temp_l, A
	mov A, local_scratchpad1 + 0	; stara temp_h
	subb A, local_temp_h
	mov local_temp_h, A
	;mov A, #'='
	;acall write_char
	;acall write_temperature
	clr C
control_ret7:
	ret

endif	;SKIP_CTRL_TEMP

;-----------------------------------------------------------
; Odczytuje z EEPROM 3 bajty do control_settings_block
; używając sekwencji i2c_shin, i2c_ACK, i2c_shin, i2c_ACK, i2c_shin
; Niszczy A, C, R1, R7
; Zwraca w A ostatnio wczytany bajt (tj. control_settings_block + 2)
; Zwraca C=0
control_read_settings_block:
	mov R1, #control_settings_block
	sjmp control_read_settings_no_ack
control_read_settings_byte:
	; potwierdzamy odczyt poprzedniego bajtu i czytamy następny bajt pod @R1
	acall i2c_ACK
control_read_settings_no_ack:
	acall i2c_shin
	mov @R1, A
	inc R1
	cjne R1, #(control_settings_block + 3), control_read_settings_byte
	; w ostatnim kroku liczby są równe, więc C=0
	ret
