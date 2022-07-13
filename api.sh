#!/bin/sh
#
# This file is part of Thermostat Firmware.
#
# Thermostat Firmware is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# Thermostat Firmware is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Thermostat Firmware. If not, see <https://www.gnu.org/licenses/>.
#
# Copyright (c) 2022 Aleksander Mazur
#
# Ekstraktor API sterownika

API_H=firmware.h

[ -f $API_H ] && cp $API_H /tmp/api0.$$.h
for f in `egrep -L '^SKIP_UART\s+NUMBER\s+[0]*1\s+' firmware_*.lst`; do
	awk '/; \/API\// { gsub(":", "", $6); print "#define\tAPI_" $6 "\t0x" $3; }' "$f" > /tmp/api1.$$.h
	if [ -f /tmp/api0.$$.h ]; then
		diff -u /tmp/api0.$$.h /tmp/api1.$$.h || exit 1
	fi
	mv /tmp/api1.$$.h /tmp/api0.$$.h
done
if [ -f $API_H ]; then
	echo API OK
	rm /tmp/api0.$$.h
else
	mv /tmp/api0.$$.h $API_H
fi
