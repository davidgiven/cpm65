import os, sys

os.chdir(os.getcwd())



global SEC_TYPE_SECT
global SEC_TYPE_ORG
global SEC_TYPE_COMN
global CODE_TYPE_FINALIZED_BYTES
global CODE_TYPE_SECTION_OFFSET
global CODE_TYPE_EXTERNAL_VAR
global ADDR_TYPE_BANK
global ADDR_TYPE_OFFSET
global ADDR_TYPE_HIGH
global ADDR_TYPE_LOW
global ADDR_TYPE_NONE
global CODE_TYPE_VARIABLE
global processor_flags



SEC_TYPE_SECT = "sect"
SEC_TYPE_ORG = "org"
SEC_TYPE_COMN = "comn"


CODE_TYPE_FINALIZED_BYTES = "final_bytes"
CODE_TYPE_SECTION_OFFSET = "section_offset"
CODE_TYPE_EXTERNAL_VAR = "external_var"
ADDR_TYPE_BANK = "addr_bank"
ADDR_TYPE_OFFSET = "addr_offset"
ADDR_TYPE_HIGH = "addr_high"
ADDR_TYPE_LOW = "addr_low"
ADDR_TYPE_NONE = "addr_none"

CODE_TYPE_VARIABLE = "var"




processor_flags = ["     ", "idx8 ", "idx16", "mem8 ", "mem16"]


def list_to_string(l):
	return " ".join([format(h, "02x") for h in l])


def list_to_text(l):
	return "".join([chr(h) for h in l])



def list_to_int(l, reverse=False, signed=False):

	v = 0
	LIST = [b for b in l]

	if not reverse: # as in opposite endian
		LIST = [b for b in reversed(LIST)]

	for i in range(len(LIST)):
		v += LIST[i] * (256**i)

	if signed:
		if v >= 0x80000000:
			v -= 0x100000000

	return v



def parse_chunk_size(DATA):
	size_of_length = DATA.get_bytes(1)

	if size_of_length & 0x80 != 0:
		section_len = size_of_length & 0x7f
		return (section_len, DATA)
	else:
		section_len = 0

		for i in range(size_of_length):
			power = (size_of_length-i)-1
			section_len += DATA.get_bytes(1) * (256 ** power)


		return (section_len, DATA)

'''
def get_bytes(buf, n, reverse=False, force_list=False):

		out_buf = []
		out_n = 0
		read_size = 0
		
		while out_n < n and read_size < len(buf):
			#if LEGACY_MODE:
			#	if buf[read_size] == 0x0d:
			#		if read_size < len(buf)-1 and buf[read_size+1] == 0x0a:
			#			read_size += 1
			out_buf.append(buf[read_size])
			out_n += 1
			read_size += 1

		if out_n < n:
			raise IndexError("Cannot read past end of buffer.")
		

		if n == 1 and (not force_list):
			out_buf = int(out_buf[0])
		else:
			out_buf = bytes(out_buf)

		return buf[read_size:], out_buf
'''


MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]




class DATA_BUFFER(object):

	def __init__(self, buf_data):
		self._buffer = buf_data
		self._BUFF_IND = 0
		self._BUFF_LEN = len(buf_data)


	def get_bytes(self, n, reverse=False, force_list=False):

		out_buf = []
		out_n = 0
		read_size = 0

		while out_n < n and read_size + self._BUFF_IND < self._BUFF_LEN:

			ind = read_size + self._BUFF_IND

			if self._buffer[ind] == 0x0d:
				if ind < self._BUFF_LEN - 1 and self._buffer[ind+1] == 0x0a:
					read_size += 1
					ind += 1

			out_buf.append(self._buffer[ind])
			out_n += 1
			read_size += 1

		if out_n < n:
			raise IndexError("Cannot read past end of buffer.")

		if n == 1 and (not force_list):
			out_buf = int(out_buf[0])
		else:
			out_buf = bytes(out_buf)

		self._BUFF_IND += read_size

		return out_buf


	def check_byte(self, n):

		return self._buffer[n + self._BUFF_IND]

	def get_len(self):

		return self._BUFF_LEN - self._BUFF_IND




class REL_FILE(object):



	def __init__(self, REL_DATA):
		#rd = [b for b in REL_DATA]
		self._REL_DATA = DATA_BUFFER(REL_DATA)
		self._raw_data = DATA_BUFFER(REL_DATA)

		self._header_data = {}
		self._groups = ["", ]
		self._sections = [{}]
		self._external_vars = [{}]
		self._global_vars = [{}]
		self._all_globals = [{}]
		self._local_vars = {}
		self._labels = {}

		self._processor_statuses = {}

		self._file_name = ""

		#self._code_data = []

		self.decode_rel_data()




	def decode_rel_data(self):
		try:

			#print(self._REL_DATA.get_len())
			# header data
			#print(self._REL_DATA.check_byte(0))
			self._REL_DATA = self.decode_header(self._REL_DATA)

			#print(self._REL_DATA.get_len())

			# section data
			#print(self._REL_DATA.check_byte(0))
			section_len, self._REL_DATA = parse_chunk_size(self._REL_DATA)

			#print("slen", section_len)


			self._REL_DATA = self.decode_section_names(self._REL_DATA)

			#print(self._REL_DATA.get_len())

			#print("passed sec names")



			# global var data
			section_len, self._REL_DATA = parse_chunk_size(self._REL_DATA)
			#dat = self._REL_DATA[:section_len]
			#self._REL_DATA = self._REL_DATA[section_len:]

			self._REL_DATA = self.decode_global_vars(self._REL_DATA)

			#print("passed global vars")


			# processor status data
			section_len, self._REL_DATA = parse_chunk_size(self._REL_DATA)
			#dat = self._REL_DATA[:section_len]
			#self._REL_DATA = self._REL_DATA[section_len:]

			self._REL_DATA = self.decode_processor_status(self._REL_DATA)


			#print("passed processor")



			# file name
			LEN = self._REL_DATA.get_bytes(1)
			self._file_name = list_to_text(self._REL_DATA.get_bytes(LEN))
			#self._REL_DATA = self._REL_DATA[LEN+1:]



			# local var data
			section_len, self._REL_DATA = parse_chunk_size(self._REL_DATA)
			#dat = self._REL_DATA[:section_len]
			#self._REL_DATA = self._REL_DATA[section_len:]

			self._REL_DATA = self.decode_local_vars(self._REL_DATA)

			#print("got to code")



			# code
			self._REL_DATA = self.decode_code(self._REL_DATA)

			#print("got past code")



			for i in range(len(self._sections)):
				if i > 0:
					if "code_data" not in self._sections[i]:
						self._sections[i]["code_data"] = []


		except Exception as e:
			raise e





	def get_section(self, s):
		if type(s) == type(bytes([1])):
			s = list(s)

		if type(s) == type([]):
			sec_num = list_to_int(s[-2:])

			return self._sections[sec_num]
		elif type(s) == type("s"):
			for S in self._sections:
				if "sec_name" in S:
					if S["sec_name"] == s:
						return S

			raise KeyError("No section with name " + str(s))

		else:
			raise TypeError("Cannot find section based on type " + str(type(s)))




	def decode_header(self, DATA):

		#DATA = [b for b in dat]


		header_bytes = DATA.get_bytes(3)
		#DATA = DATA[3:]

		null_bytes = DATA.get_bytes(2)
		#DATA = DATA[2:]

		# date of compilation
		date = DATA.get_bytes(4)
		self._header_data["comp_date"] = "/".join([format(int(b), "02d") for b in date])
		#print("DATE: " + "/".join([format(int(b), "02d") for b in date_bytes]))
		#DATA = DATA[4:]


		# time of compilation
		comp_time = DATA.get_bytes(3)
		self._header_data["comp_time"] = ":".join([format(int(b), "02d") for b in comp_time])
		#print("TIME: " + ":".join([format(int(b), "02d") for b in time_bytes]))
		#DATA = DATA[3:]

		




		
		# compiler name
		comp_name_len = DATA.get_bytes(1)
		#DATA = DATA[1:]
		comp_name = DATA.get_bytes(comp_name_len)
		#DATA = DATA[comp_name_len:]
		self._header_data["compiler"] = {"name": list_to_text(comp_name), "data": list_to_string(DATA.get_bytes(8))}
		#print(list_to_text(name))
		#print(list_to_string(DATA[:8]))
		#DATA = DATA[8:]


	
		while DATA.get_len() > 0 and DATA.check_byte(0) != 0:

			name_len = DATA.get_bytes(1)
			#DATA = DATA[1:]
			name = list_to_text(DATA.get_bytes(name_len))
			#DATA = DATA[name_len:]

			self._header_data[name] = {"name": name, "data": list_to_string(DATA.get_bytes(8))}
			self._groups.append(name)
			#DATA = DATA[8:]


			while DATA.get_len() > 0 and DATA.check_byte(0) != 0:
				some_len = DATA.get_bytes(1)
				#DATA = DATA[1:]

			DATA.get_bytes(1)
			#DATA = DATA[1:]
		




		'''
		# PROG block
		prog_name_len = DATA[0]
		DATA = DATA[1:]
		prog_name = DATA[:prog_name_len]
		DATA = DATA[prog_name_len:]
		self._header_data["PROG"] = {"text": list_to_text(prog_name), "other": list_to_string(DATA[:8])}
		#print(list_to_text(prog_name))
		#print(list_to_string(DATA[:8]))
		DATA = DATA[8:]
		#print("; end PROG block data,", list_to_string(DATA[:1]))
		DATA = DATA[1:]


		# DATA block
		data_name_len = DATA[0]
		DATA = DATA[1:]

		data_name = DATA[:data_name_len]
		DATA = DATA[data_name_len:]

		#print(list_to_text(data_name))
		#print(list_to_string(DATA[:8]))
		DATA = DATA[8:]
		#print("; end DATA block data,", list_to_string(DATA[:1]))
		DATA = DATA[1:]
		'''


		# end header ??
		if DATA.check_byte(0) == 0:
			#print("; end header data,", list_to_string(DATA[:1]))
			#DATA = DATA[1:]
			DATA.get_bytes(1)
		else:
			
			raise IndexError("did not finish header")


		return DATA



	def decode_section_names(self, dat):

		sec_ind = 1
		while dat.get_len() != 0 and dat.check_byte(0) != 0:
			name_len = dat.get_bytes(1)
			name = list_to_text(dat.get_bytes(name_len))

			TYPE = dat.get_bytes(1)


			data1 = dat.get_bytes(8)

			group = list_to_int(data1[:3])

			dat.get_bytes(1) # dummy

			dat.get_bytes(18) # dummy

			location = dat.get_bytes(4)

			size = dat.get_bytes(4)


			if TYPE == 1:

				


				group_name = name
				if group > 0:
					group_name = self._groups[group]

				#print("sect", name.ljust(15), list_to_string(data1), "  {weird 18 thing}  ; ", "offset ", list_to_string(offset).replace(" ", ""))
				#print("sect", name.ljust(15), list_to_string(data1), " ; ", "size =", list_to_string(size).replace(" ", ""))
				self._sections.append({"sec_name": name, "sec_type": SEC_TYPE_SECT, "sec_size": list_to_int(size), "sec_addr": -1, "sec_ind": sec_ind, "sec_group": group_name})
				sec_ind += 1

			elif TYPE == 2:


				group_name = name
				if group > 0:
					group_name = self._groups[group]



				#print("org ", name.ljust(15), list_to_string(data1), "  addr ", list_to_string(location).replace(" ", "") , "     ; size =", list_to_string(size).replace(" ", ""))
				self._sections.append({"sec_name": name, "sec_type": SEC_TYPE_ORG, "sec_size": list_to_int(size), "sec_addr": list_to_int(location), "sec_ind": sec_ind, "sec_group": "ASEG"})
				sec_ind += 1

			elif TYPE == 0:


				group_name = name
				if group > 0:
					group_name = self._groups[group]
				#print("comn", name.ljust(15), list_to_string(data1), "  {weird 18 thing}  ; ", "offset ", list_to_string(offset).replace(" ", ""))

				#print("comn", name.ljust(15), list_to_string(data1), " ; ", "size =", list_to_string(size).replace(" ", ""))
				self._sections.append({"sec_name": name, "sec_type": SEC_TYPE_COMN, "sec_size": list_to_int(size), "sec_addr": 0, "sec_ind": sec_ind, "sec_group": group_name})
				sec_ind += 1

			else:
				print(TYPE)
				raise KeyError("type " + str(TYPE) + " encountered")
				break


		if dat.check_byte(0) == 0:
			#print("; end of section data, 00")
			dat.get_bytes(1) # skip this 0 byte
			pass
		else:
			raise IndexError("Did not reach end of section data")


		return dat



	def decode_global_vars(self, dat):


		while dat.get_len() != 0 and dat.check_byte(0) != 0:

			LEN = dat.get_bytes(1)

			NAME = list_to_text(dat.get_bytes(LEN))
			
			TYPE = dat.get_bytes(1)
			#ind += 1

			#print(str(LEN), NAME, str(TYPE))
			#print(str(LEN), NAME)
			#print(NAME)


			if TYPE == 4:
				#external

				#print("External Value   " + list_to_string(dat[ind:ind+8]).replace(" ", ""))
				#print("EXT   ", NAME)

				self._external_vars.append({"name": NAME, "value": -1})
				self._all_globals.append({"name": NAME, "value": -1})
				#ind += 8
				dat.get_bytes(8)


			elif TYPE == 5:
				#global value

				section = dat.get_bytes(4)

				offset = dat.get_bytes(4)


				#print("GLB value:\n   data1: " + list_to_string(data1) + "\n   offset: " + list_to_string(offset).replace(" ","")) 
				#print("GLB   ", NAME.ljust(20), "     ; ", get_section_name(section) + "::" + list_to_string(offset).replace(" ",""))

				sec = self.get_section(section)

				self._global_vars.append({"name": NAME, "section": sec["sec_name"], "offset": list_to_int(offset, signed=True), "value": -1})
				self._all_globals.append({"name": NAME, "section": sec["sec_name"], "offset": list_to_int(offset, signed=True), "value": -1})
				#self._labels[NAME] = {"section": sec["sec_name"], "offset": list_to_int(offset, signed=True)}

			elif TYPE == 6:
				val = dat.get_bytes(8)

				self._global_vars.append({"name": NAME, "value": list_to_int(val)})
				self._all_globals.append({"name": NAME, "value": list_to_int(val)})
				#ind += 8

			else:
				print(NAME)
				raise KeyError("HIT UNEVALUATED " + format(TYPE, "02x") + " INSTRUCTION")
				break


			#print("")

		if dat.check_byte(0) == 0:
			#print("; end data, 00")
			dat.get_bytes(1) # skip this 0 byte
			pass
		else:
			raise IndexError("Did not reach end of global vars")


		return dat




	def decode_processor_status(self, dat):

		while not (dat.check_byte(0) == 0 and dat.check_byte(1) == 0):

			# 04 = mem16
			# 03 = mem8
			# 02 = idx16
			# 01 = idx8

			fg = dat.get_bytes(2)

			flag = processor_flags[fg[0]*256 + fg[1]]

			data1 = dat.get_bytes(1, force_list=True)  # 01 to tell what type of data this is?
			section = self.get_section(dat.get_bytes(4))
			offset = list_to_int(dat.get_bytes(4), signed=True)

			if not section["sec_name"] in self._processor_statuses:
				self._processor_statuses[section["sec_name"]] = []


			self._processor_statuses[section["sec_name"]].append({"offset": offset, "status": flag})




			#print(flag,  " @  ", get_section_name(section), ", offset", list_to_string(offset).replace(" ", ""))
			#print(list_to_string(dat[:11]))
			#dat = dat[11:]

		#print(list_to_string(dat[:2]).replace(" ", ""))
		#print("; end processor data 00 00") #last 2 bytes 00

		dat.get_bytes(2) # dummy, exit last part of this

		return dat




	def decode_local_vars(self, dat):

		#ind = 0

		while dat.get_len() != 0 and dat.check_byte(0) != 0:


			LEN = dat.get_bytes(1)

			NAME = list_to_text(dat.get_bytes(LEN))

			TYPE = dat.get_bytes(1)
			
			#print(str(LEN), NAME, str(TYPE))
			#print(str(LEN), NAME)
			#print(NAME)


			if TYPE == 0:
				print(NAME)
				raise KeyError("hit 00 instruction")
				break

			elif TYPE == 1:
				section = dat.get_bytes(4)
				
				offset = dat.get_bytes(4)

				#print("GLB value:\n   data1: " + list_to_string(data1) + "\n   offset: " + list_to_string(offset).replace(" ","")) 
				#print("label ", NAME.ljust(25), "; " + get_section_name(section) + ":" + list_to_string(offset[1:]).replace(" ","").upper())
				sec = self.get_section(section)

				self._labels[NAME] = {"section": sec["sec_name"], "offset": list_to_int(offset, signed=True)}


			elif TYPE == 2:
				#exact value

				#print("Exact Value: " + list_to_string(dat[ind:ind+8]).replace(" ", ""))
				#print(NAME.ljust(20), "  EQU  ", list_to_string(dat[ind:ind+8]).replace(" ", "")[-6:])

				self._local_vars[NAME] = {"value": list_to_int(dat.get_bytes(8))}

				#ind += 8




			else:
				print(NAME)
				raise KeyError("HIT UNEVALUATED " + format(TYPE, "02x") + " INSTRUCTION")
				break


			#print("")

		if dat.check_byte(0) == 0:
			#print("; end data, 00")
			dat.get_bytes(1)
		else:
			raise IndexError("did not reach end of local vars")


		return dat





	def decode_code(self, dat):

		new_line = True
		is_list = False

		curr_section = None
		sec_ind = -1

		curr_code = []

		while dat.get_len() != 0 and dat.check_byte(0) != 0:

			TYPE = dat.check_byte(0)


			if TYPE == 1:
				#section starter

				if curr_section != None:
					#self.get_section(self._sections[sec_ind]["sec_name"])["code_data"] = curr_code
					SECTION_INDEX = self.get_section(self._sections[sec_ind]["sec_name"])["sec_ind"]
					if not "code_data" in self._sections[SECTION_INDEX]:
						self._sections[SECTION_INDEX]["code_data"] = []

					for c in curr_code:
						self._sections[SECTION_INDEX]["code_data"].append(c)
					#self._sections[sec_ind]["code_data"] = curr_code

				section = self.get_section(dat.get_bytes(3))
				section_name = section["sec_name"]

				#dat = dat[3:]
				#print("\n")
				#print("SECTION ", section_name)

				
				curr_section = section
				sec_ind = section["sec_ind"]

				curr_code = []

				#new_line = True
				#is_list = False

			elif TYPE == 0x57:
				#new line of code
				dat.get_bytes(1) # dummy
				line_num = list_to_string(dat.get_bytes(2)).replace(" ", "")
				#dat = dat[3:]

				#print("")
				#print(line_num + ": ", end="")
				#new_line = True
				#is_list = False

			elif TYPE == 0x10:
				# storage directive

				'''
				if dat[1] & 0x80 > 0:
					dir_size = dat[1] & 0x7f
					dat = dat[2:]
				else:
					num_len = dat[1]
					dir_size = list_to_int(dat[2:2+num_len])

					dat = dat[2+num_len:]
				'''

				dat.get_bytes(1) # dummy

				#dat = dat[1:]

				dir_size, dat = parse_chunk_size(dat)

				curr_code.append({"type": CODE_TYPE_FINALIZED_BYTES, "data": [0 for b in range(dir_size)], "size": dir_size})


			elif TYPE == 0x11:
				#finalized bytes

				'''
				if dat[1] & 0x80 > 0:
					num_finalized = dat[1] & 0x7f

					finalized_bytes = dat[2:2+num_finalized]

					dat = dat[2+num_finalized:]
				else:
					num_len = dat[1]
					num_finalized = list_to_int(dat[2:2+num_len])

					dat = dat[2+num_len:]

					finalized_bytes = dat[:num_finalized]

					dat = dat[num_finalized:]
				'''

				dat.get_bytes(1) # dummy
				num_finalized, dat = parse_chunk_size(dat)
				finalized_bytes = dat.get_bytes(num_finalized, force_list=True)
				



				
				curr_code.append({"type": CODE_TYPE_FINALIZED_BYTES, "data": list(finalized_bytes), "size": num_finalized})


				

				#is_list = False



			elif TYPE == 0x12:
				#variable data

				dat.get_bytes(1) # dummy

				variable_type = dat.get_bytes(1)
				#dat = dat[2:]

				sec = dat.get_bytes(3)
				#dat = dat[3:]
				offset = dat.get_bytes(4)
				#dat = dat[4:]

				#if is_list:
				#	print(", ", end="")

				'''
				if sec[0] & 0xf != 0:
					#section with offset
					#print(get_section_name(section) + "::" + list_to_string(offset[1:]).replace(" ", "").upper(), end="")
					if sec[0] & 0x60 == 0:
						curr_code.append({"type": CODE_TYPE_SECTION_OFFSET, "section": self.get_section(sec[-2:])["sec_name"], "offset": list_to_int(offset)})
					elif sec[0] & 0x20 == 0:
						curr_code.append({"type": CODE_TYPE_BANK_VAL, "section": self.get_section(sec[-2:])["sec_name"], "offset": list_to_int(offset)})
					else:
						curr_code.append({"type": CODE_TYPE_OFFSET_VAL, "section": self.get_section(sec[-2:])["sec_name"], "offset": list_to_int(offset)})

				else:
					#external variable
					#print("ext_" + list_to_string(section[1:]).replace(" ", "").upper(), end="")
					curr_code.append({"type": CODE_TYPE_EXTERNAL_VAR, "var_num": list_to_int(sec)})
				'''

				curr_code.append({"type": CODE_TYPE_VARIABLE})

				if sec[0] & 0x07 > 0:
					# local variable
					curr_code[-1]["local"] = True
					curr_code[-1]["var_num"] = -1
					curr_code[-1]["section"] = self.get_section(sec[1:])["sec_name"]
				else:
					#print("GLOBAL w/ data ", variable_type, sec, offset)
					# global variable
					curr_code[-1]["local"] = False
					curr_code[-1]["var_num"] = list_to_int(sec[1:])
					curr_code[-1]["section"] = None


				curr_code[-1]["offset"] = list_to_int(offset, signed=True)


				if sec[0] & 0x78 != 0:
					# address of variable
					if sec[0] & 0x78 == 0x48:
						# bank
						curr_code[-1]["addr_type"] = ADDR_TYPE_BANK
					elif sec[0] & 0x78 == 0x60:
						# offset
						curr_code[-1]["addr_type"] = ADDR_TYPE_OFFSET
					elif sec[0] & 0x78 == 0x40:
						# high
						curr_code[-1]["addr_type"] = ADDR_TYPE_HIGH
					elif sec[0] & 0x78 == 0x38:
						# low
						curr_code[-1]["addr_type"] = ADDR_TYPE_LOW

				else:
					# not address of variable
					curr_code[-1]["addr_type"] = ADDR_TYPE_NONE



				if variable_type == 0x11:
					curr_code[-1]["size"] = 1
				elif variable_type == 0x12:
					curr_code[-1]["size"] = 2
				elif variable_type == 0x13:
					curr_code[-1]["size"] = 3
				else:
					pass

				#is_list = True

			else:
				print("")
				raise KeyError("Unintentionally hit " + format(TYPE, "02x"))
				break


		if dat.check_byte(0) == 0:
			dat.get_bytes(1)
			#print("\n; end of code segment, 00 00")
			if curr_section != None:
				SECTION_INDEX = self.get_section(self._sections[sec_ind]["sec_name"])["sec_ind"]

				if not "code_data" in self._sections[SECTION_INDEX]:
					self._sections[SECTION_INDEX]["code_data"] = []

				for c in curr_code:
					self._sections[SECTION_INDEX]["code_data"].append(c)

		else:
			raise IndexError("did not reach end of code")


		return dat







