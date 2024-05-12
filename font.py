#!/usr/bin/env python
# -*- coding: utf-8 -*-
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
# Copyright (c) 2013, 2017, 2021, 2024 Aleksander Mazur
#
# Generator fontu dla wyświetlacza 7-segmentowego

font = \
'XXX|  X|XXX|XXX|X X|XXX|XXX|XXX|XXX|XXX|XXX|X  |XXX|  X|XXX|XXX|' \
'X X|  X|  X|  X|X X|X  |X  |  X|X X|X X|X X|X  |X  |  X|X  |X  |' \
'X X|  X|XXX|XXX|XXX|XXX|XXX|  X|XXX|XXX|XXX|XXX|X  |XXX|XXX|XXX|' \
'X X|  X|X  |  X|  X|  X|X X|  X|X X|  X|X X|X X|X  |X X|X  |X  |' \
'XXX|  X|XXX|XXX|  X|XXX|XXX|  X|XXX|XXX|X X|XXX|XXX|XXX|XXX|X  |'
rowlen = 16 * 4

# segmenty:
#  a
# f b
#  g
# e c
#  d

# offsety znaków odpowiadających segmentom w foncie powyżej
seg_ofs = {
	'a' : 0*rowlen+1,
	'b' : 1*rowlen+2,
	'c' : 3*rowlen+2,
	'd' : 4*rowlen+1,
	'e' : 3*rowlen+0,
	'f' : 1*rowlen+0,
	'g' : 2*rowlen+1
}

# przypisanie segmentów do bitów - cecha układu
# (sposobu podłączenia linii wyświetlacza do portu mikroprocesora)
#map_bit_to_seg = [# Philips
#	'.',	#bit7
#	'g',	#bit6
#	'a',	#bit5
#	'f',	#bit4
#	'b',	#bit3
#	'e',	#bit2
#	'c',	#bit1
#	'd'		#bit0
#]
map_bit_to_seg = [# HT-2261LED-V1.0
	'',		#bit7
	'g',	#bit6
	'f',	#bit5
	'e',	#bit4
	'd',	#bit3
	'c',	#bit2
	'b',	#bit1
	'a'		#bit0
]

#aktywnosc = "10"	# segmenty włączane zerem
aktywnosc = "01"	# segmenty włączane jedynką

for i in range(0, 16):
	x_ofs = i * 4
	result = ''
	for m in map_bit_to_seg:
		if m in seg_ofs:
			r = aktywnosc[int(font[x_ofs + seg_ofs[m]] != ' ')]
		else:
			r = aktywnosc[0]
		result = result + r
	print('db\t%sb' % result)

print()

equs = {
	'.': 'KROPKA',
	'g': 'MYSLNIK',
}

for (seg, equ) in equs.items():
	try:
		x = 1 << (7 - map_bit_to_seg.index(seg))
		print('%s\tequ\t0%02Xh' % (equ, x))
	except:
		pass
