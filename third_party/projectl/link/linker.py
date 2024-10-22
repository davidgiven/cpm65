
import rel_to_class as RTC
import argparse


import os, sys, traceback

os.chdir(os.getcwd())

FILES = []


OFFSETS = {}
START_OFFS = {}


def make_offset_vars(VARS):

	global OFFSETS
	global START_OFFS

	vals = VARS.split(",")

	for v in vals:
		try:
			var,val = tuple(v.split("="))
		except:
			var,val = v,"00"

		OFFSETS[var.upper()] = int("0x" + val, 16)


	for O in OFFSETS:
		START_OFFS[O] = OFFSETS[O]


# delete later
def get_rel_files(f):
	#global FILES
	with open(f, "r") as file:
		for line in file:
			FILES.append(line.replace("\\", "").replace("\n", ""))

	return FILES




def get_file_path(p):
	basepath = os.path.dirname(__file__)
	for f in p.split("/"):
		basepath = os.path.abspath(os.path.join(basepath, f))
	return basepath


def clean_file_paths(files):

	#base_dir = files[0].replace("\\", "/")
	#b = base_dir.split("/")

	b = []
	cleaned = []

	first = True

	for f in files:
		f = f.replace("\\", "/")

		s = f.split("/")


		ind = 0

		real_dir = False

		while ind < len(s):
			if s[ind] == "..":
				if real_dir:
					s.pop(ind)
					s.pop(ind-1)
					ind -= 1
			else:
				real_dir = True

			ind += 1



		if first:
			b = s
			first = False


		s_ind = 0
		l = min(len(b), len(s))
		while s_ind < l:
			if s[s_ind] != b[s_ind]:
				b = b[:s_ind]
				break

			s_ind += 1


		cleaned.append(s)



	out = []
	for c in cleaned:
		s_ind = 0
		l = min(len(b), len(c))
		while s_ind < l:
			if c[s_ind] != b[s_ind]:
				break
			s_ind += 1

		out.append("/".join(c[s_ind:]))

	return ("/".join(b), out)







	




def DO_LINK(L_ARGS):

	
	try:
		rel_files = L_ARGS["rel_files"]
		outputfile = L_ARGS["outputfile"]
		#ROM_SIZE = L_ARGS["ROM_SIZE"]
		rel_offsets = L_ARGS["-r"] or []
		map_file = L_ARGS["map_file"] or "out.map"


		FILES = rel_files
		BASE_DIR, clean_files = clean_file_paths(FILES)

		REL_FILES = []
		GLOBALS = {}

		NO_ERRORS = True

		make_offset_vars(rel_offsets)



		



		for F in FILES:
			try:
				#with open(get_file_path(F), "rb") as f:
				with open(F, "rb") as f:

					file = F.replace("\\", "/").split("/")[-1]
					
					print("[INFO] Parsing " + str(file) + ".")

					try:
						RF = RTC.REL_FILE(f.read())
						f = RF._file_name.replace(".asm", "")

						REL_FILES.append((f, RF))

					except Exception as e:
						traceback.print_exc()
						print("[ERROR] Error while parsing " + str(F) + ".")
						NO_ERRORS = False

			except FileNotFoundError:
				print("[ERROR] Missing " + str(F) + ".")
				NO_ERRORS = False





		print("[INFO] LINKING FILES\n")

		#print(OFFSETS)

		# step 1: section offsets
		for f_name, R in REL_FILES:

			for S in R._sections[1:]:
				NAME = S["sec_group"].replace(f_name, "").upper()
				if NAME != "COMN":
					if S["sec_addr"] == -1:
						if not NAME in OFFSETS:
							OFFSETS[NAME] = 0
							#print("NOT IN OFFSETS: ", NAME)
						R.get_section(S["sec_name"])["sec_addr"] = OFFSETS[NAME]

						size = 0
						for c in S["code_data"]:
							size += c["size"]

						R.get_section(S["sec_name"])["sec_size"] = size
						OFFSETS[NAME] += size

					'''else:
						if not NAME in START_OFFS:
							START_OFFS[NAME] = S["sec_addr"]
					'''

		print("[INFO] Generating Labels.")
		CODE_LABELS = {}
		F_GLOBAL_LABELS = {}

		# step 2: set global vars
		for f_name, R in REL_FILES:
			F_GLOBAL_LABELS[f_name] = set()
			for G in R._global_vars[1:]:
				if G["value"] == -1:
					v = R.get_section(G["section"])["sec_addr"] + G["offset"]
					GLOBALS[G["name"]] = v
					#CODE_LABELS[G["name"]] = v
					F_GLOBAL_LABELS[f_name].add(G["name"])

				else:
					GLOBALS[G["name"]] = G["value"]


		
		# step 2.5: get all labels for debugging output
		for f_name, R in REL_FILES:
			for LBL in R._labels:
				L = R._labels[LBL]
				sec = R.get_section(L["section"])
				v = sec["sec_addr"] + L["offset"]
				is_glb = "     "
				if LBL in F_GLOBAL_LABELS[f_name]: is_glb = "(GLB)"
				CODE_LABELS[f_name + "\x00" + sec['sec_name'] + "\x00" + LBL + "\x00" + is_glb] = v



		print("[INFO] Converting offsets.")
		# step 3: get local offsets and external values 
		for f_name, R in REL_FILES:
			for S in R._sections[1:]:
				ind = 0
				for c in S["code_data"]:


					if c["type"] == RTC.CODE_TYPE_VARIABLE:
						try:
							val = 0
							'''
							if c["local"]:
								# local variable offset
								val = R.get_section(c["section"])["sec_addr"] + c["offset"]
							else:
								# global variable offset
								val = GLOBALS[R._all_globals[c["var_num"]]["name"]]
								val += c["offset"] # just in case

							list_data = [0, 0, 0]

							if c["addr_type"] == RTC.ADDR_TYPE_NONE or c["addr_type"] == RTC.ADDR_TYPE_OFFSET:
								list_data = [val & 0xff, (val & 0xff00) >> 8, (val & 0xff0000) >> 16]

							elif c["addr_type"] == RTC.ADDR_TYPE_BANK:
								list_data = [(val & 0xff0000) >> 16]

								while len(list_data) < c["size"]:
									list_data.append(0)

							elif c["addr_type"] == RTC.ADDR_TYPE_HIGH:
								list_data = [(val & 0xff00) >> 8]

								while len(list_data) < c["size"]:
									list_data.append(0)

							elif c["addr_type"] == RTC.ADDR_TYPE_LOW:
								list_data = [(val & 0xff)]

								while len(list_data) < c["size"]:
									list_data.append(0)
							

							R.get_section(S["sec_name"])["code_data"][ind] = {"type": RTC.CODE_TYPE_FINALIZED_BYTES, "size": c["size"], "data": list_data[:c["size"]]}
							'''

							
							if c["local"]:
								# local variable offset
								val = R.get_section(c["section"])["sec_addr"] + c["offset"]
							else:
								# global variable offset
								val = GLOBALS[R._all_globals[c["var_num"]]["name"]]
								

							list_data = [0, 0, 0]


							

							if c["addr_type"] == RTC.ADDR_TYPE_BANK:
								val = ((val & 0xff0000) >> 16) & 0xff
							elif c["addr_type"] == RTC.ADDR_TYPE_OFFSET:
								val = val & 0xffff
							elif c["addr_type"] == RTC.ADDR_TYPE_HIGH:
								val = ((val & 0xff00) >> 8) & 0xff
							elif c["addr_type"] == RTC.ADDR_TYPE_LOW:
								val = val & 0xff


							if not c["local"]: val += c["offset"]

							list_data = [val & 0xff, (val & 0xff00) >> 8, (val & 0xff0000) >> 16]


							'''
							if c["addr_type"] == RTC.ADDR_TYPE_BANK: list_data = list_data[:1]
							elif c["addr_type"] == RTC.ADDR_TYPE_OFFSET: list_data = list_data[:2]
							elif c["addr_type"] == RTC.ADDR_TYPE_HIGH: list_data = list_data[:1]
							elif c["addr_type"] == RTC.ADDR_TYPE_LOW: list_data = list_data[:1]

							while len(list_data) < c["size"]:
								list_data.append(0)
							'''

							R.get_section(S["sec_name"])["code_data"][ind] = {"type": RTC.CODE_TYPE_FINALIZED_BYTES, "size": c["size"], "data": list_data[:c["size"]]}
							

						except Exception as e:
							raise Exception(f_name + "::" + S["sec_name"] + str(c))
							NO_ERRORS = False



					ind += 1



		def fresh_data(ind):
			if ind % 0x40 > 0x1f:
				return 0x00
			else:
				return 0xff

		print("[INFO] Writing Hex blocks.")

		CODE_BLOCKS = []

		with open(map_file, "w") as F:

			if BASE_DIR != "": F.write("BASE_DIRECTORY=\"" + BASE_DIR + "\"\n")


			F.write("\n" + " ".join(["FILE NAME".ljust(40), "MODULE".ljust(30), "SECTION".ljust(15), "START".ljust(12), "END".ljust(15), "SIZE".ljust(8), ";   ERRORS"]) + "\n")

			f_ind = 0
			for f_name, R in REL_FILES:
				for S in R._sections[1:]:
					if S["sec_size"] > 0:

						err_msg = ";"

						ind = S["sec_addr"]


						RAM_SEC = False

						if ind >= 0x7E0000 and ind < 0x800000:
							RAM_SEC = True

						s_addr = ind
						e_addr = ind + S["sec_size"] - 1


						#sect_name =  S["sec_name"].replace(f_name, "")
						sect_name =  S["sec_group"].replace(f_name, "")
						if sect_name == "P": sect_name = "PSEG"
						if sect_name == "D": sect_name = "DSEG"
						if sect_name == "PROG": sect_name = "PSEG"
						if sect_name == "DATA": sect_name = "DSEG"

						try:
							if sect_name[0] == "A" and int(sect_name[1]) > 0: sect_name = "ASEG"
						except:
							pass


						s_n = sect_name

						if sect_name == "PSEG": s_n = "PROG"
						if sect_name == "DSEG": s_n = "DATA"

						if s_n != "ASEG":
							try:
								s_offs = START_OFFS[s_n.upper()] & 0x7FFFFF
							except:
								s_offs = 0
						else:
							s_offs = ind & 0x7FFFFF

						e_offs = e_addr & 0x7FFFFF

						if (s_offs & 0x7F0000) != (e_offs & 0x7F0000):
							print("[WARNING] File '" + f_name + ".rel', section '" + S["sec_name"] + "' crosses a bank boundary. Code may not work as intended.")
							err_msg = "; [WARNING] CROSSES BANK BOUNDARY!!"
							NO_ERRORS = False
							
						for sec in START_OFFS:
							o = START_OFFS[sec] & 0x7FFFFF
							if s_offs < o and e_offs >= o:
								print("[ERROR] File '" + f_name + ".rel', section '" + S["sec_name"] + "' overwrites data in section '" + sec + "'.")
								err_msg = "; [ERROR] OVERWRITES SECTION '" + sec + "'!!"
								NO_ERRORS = False
								break



						start_addr = format(s_addr, "06x")
						end_addr = format(e_addr, "06x")
						F_NAME = clean_files[f_ind]



						
						F.write(" ".join([F_NAME.ljust(40), f_name.ljust(30), sect_name.ljust(15), (start_addr[:2] + ":" + start_addr[2:]).ljust(12), (end_addr[:2] + ":" + end_addr[2:]).ljust(15), format(S["sec_size"], "04x").ljust(8), err_msg]) + "\n")
						



						if not RAM_SEC:

							# here is the step we need.
							FIRST_LINE = True

							try:
								for c in S["code_data"]:
									if c["type"] != RTC.CODE_TYPE_FINALIZED_BYTES:
										raise TypeError("Code did not all convert, in " + f_name + " @ byte " + format(ind, "04x"))

									if FIRST_LINE:
										CODE_BLOCKS.append([ind, [], 0])
										FIRST_LINE = False

									DATA = c["data"]
									DATA_LEN = len(DATA)

									if CODE_BLOCKS[-1][0] == ind: #same section
										for b in DATA:
											CODE_BLOCKS[-1][1].append(b)

										CODE_BLOCKS[-1][2] += DATA_LEN

									else:

										CODE_BLOCKS.append((ind, DATA, len(DATA)))

									#for b in range(c["size"]):
									#	offset = ind & 0x0fffff
									#	for DB in range(len(HEX_DATA) // 0x100000):
									#		HEX_DATA[offset + 0x100000*DB] = c["data"][b]
									#	ind += 1
							except Exception as e:
								print(e)
								NO_ERRORS = False

								raise Exception("Section = " + f_name + "::" + S["sec_name"] + ", " + str(c))





				f_ind += 1

		CODE_BLOCKS.append([-2, [0], 1])


		# TEMPORARY
		#with open("LOG.txt", "w") as f:
		#	for x in CODE_BLOCKS:
		#		f.write("(" + format(x[0], "06x").upper() + ", [" + ", ".join([format(b, "02x").upper() for b in x[1]]) + "], " + format(x[2], "04x").upper() + ")\n")





		def checksum(data):
			ck = 0
			for b in data:
				ck = (ck + b) & 0xff

			return (~ck + 1) & 0xff


		

		def byte_line(ADDR, DATA):
			LDATA = []

			if len(DATA) != 0:

				CHUNK_ADDR = (ADDR - len(DATA)) & 0xFFFF

				LDATA.append(len(DATA))
				LDATA.append((CHUNK_ADDR // 0x100) & 0xff)
				LDATA.append(CHUNK_ADDR & 0xff)
				LDATA.append(0) # raw data

				for b in DATA:
					LDATA.append(b)

				LDATA.append(checksum(LDATA))

			return LDATA


		def bank_line(BANK):

			BANK_ADDR = (BANK * 0x1000)

			DATA = []
			DATA.append(3) # bank data length
			DATA.append(0) # null
			DATA.append(0) # null
			DATA.append(2) # specify bank command


			bank_data = []
			bank_data.append((BANK_ADDR // 0x10000) & 0xff)
			bank_data.append((BANK_ADDR // 0x100) & 0xff)
			bank_data.append(BANK_ADDR & 0xff)

			for b in bank_data:
				DATA.append(b)

			DATA.append(checksum(DATA))

			return DATA


		print("[INFO] Creating Intel-Hex file.")

		I_HEX_DATA = []

		P_BANK = 0
		P_LEN = 0

		line_len = 0
		last_addr = -1

		line_data = []

		break_line = False

		FIRST_LINE = True

		temp_data = []
		P_OFFS = -1

		full_line = False

		SEC_IND = 0

		new_bank = False

		for SEC_ADDR, CODE, LEN in CODE_BLOCKS:

			CHUNK_ADDR = ADDR = SEC_ADDR


			BANK = (SEC_ADDR // 0x10000) & 0xFF
			OFFS = SEC_ADDR & 0xFFFF

			if FIRST_LINE:
				P_OFFS = OFFS
				FIRST_LINE = False


			if BANK != P_BANK: 
				#print("[SEC: " + format(SEC_IND, "02x").upper() + "]: Mismatched banks. P_BANK: " + format(P_BANK & 0xff, "02x").upper() + " BANK: " + format(BANK & 0xff, "02x").upper())
				
				if not full_line:
					I_HEX_DATA.append(byte_line(P_OFFS + P_LEN, line_data))
					line_data = []
					line_len = 0
					full_line = True

				I_HEX_DATA.append(bank_line(BANK))
				P_BANK = BANK

			if OFFS & 0xFFFF != (P_OFFS + P_LEN) & 0xFFFF:
				#print("[SEC: " + format(SEC_IND, "02x").upper() + "]: Mismatched offsets. P_OFFS: " + format((P_OFFS + P_LEN) & 0xFFFF, "04x").upper() + " OFFS: " + format(OFFS, "04x").upper()) 
				if not full_line:		
					I_HEX_DATA.append(byte_line(P_OFFS + P_LEN, line_data))
					line_data = []
					line_len = 0
					P_OFFS = OFFS
					P_LEN = LEN

			


			

			P_OFFS = OFFS
			P_BANK = BANK

			CODE_LEN = len(CODE)
			
			for c in range(CODE_LEN):

				ADDR += 1
				line_len += 1

				full_line = False

				line_data.append(CODE[c])

				if ADDR & 0xFFFF == 0:
					I_HEX_DATA.append(byte_line(ADDR, line_data))
					line_data = []
					line_len = 0
					full_line = True
					if c != CODE_LEN-1:
						P_BANK = BANK
						BANK = (ADDR // 0x10000) & 0xFF
						I_HEX_DATA.append(bank_line(BANK))
						#print("[SEC: " + format(SEC_IND, "02x").upper() + "]: Crossing banks. P_BANK: " + format(P_BANK & 0xff, "02x").upper() + " BANK: " + format(BANK & 0xff, "02x").upper())


				elif line_len == 0x20:
					#line_data.append(CODE[c])
					I_HEX_DATA.append(byte_line(ADDR, line_data))
					line_data = []
					line_len = 0
					full_line = True
				
				else:
					#line_data.append(CODE[c])
					pass




			#P_OFFS = (SEC_ADDR + LEN) & 0xFFFF

			#if P_OFFS == 0 and LEN > 0:
			#	P_BANK = ((SEC_ADDR + LEN - 1) // 0x10000) & 0xFF
			#else:
			#	P_BANK = ((SEC_ADDR + LEN) // 0x10000) & 0xFF

			P_ADDR = ADDR
			P_LEN = LEN
			#P_BANK = BANK
			P_OFFS = OFFS

			SEC_IND += 1

		if I_HEX_DATA[-1][3] == 0x02:
			I_HEX_DATA.pop()


		I_HEX_DATA.append([0, 0, 0, 1, 0xFF])


		with open(outputfile, "wb") as outf:
			for HUNK in I_HEX_DATA:
				if len(HUNK) > 0:
					outf.write((":" + "".join([format(x, "02x").upper() for x in HUNK]) + "\x0a").encode("utf-8"))
					#outf.write(bytes([0x0a]))


		"""
		ROM_DATA = []

		ROM_TYPE = "LoROM"


		if ROM_TYPE == "LoROM":
			'''
			HEADER = HEX_DATA[0xff70:0x10000]
			for i in range(0x10000 - 0xff70):
				HEX_DATA[0x80ff70+i] = HEADER[i]
			'''

			for i in range(0x80000):
				ROM_DATA.append(HEX_DATA[0x800000 + i])

		elif ROM_TYPE == "HiROM":
			pass
		"""

		print("[INFO] Writing label map file.")

		SORTED_LABELS = sorted(CODE_LABELS.items(), key=lambda kv: kv[1] & 0x7FFFFF)


		def addr_to_hex(a):
			s = format(a, "06x").upper()
			return "$" + s[:-4] + ":" + s[-4:]

		with open("labels.map", 'w') as f:

			p_f_name = "\x00"
			p_s_name = "\x00"

			FIRST = True

			for name, addr in SORTED_LABELS:
				f_name, s_name, lbl, is_glb = name.split("\x00")

				if addr & 0xFFFF < 0x8000: continue

				#if addr & 0x7FFFFF >= 0x400000: continue

				if lbl[0] == "~": continue
				
				if '#' in lbl:
					lbl = "  " + lbl.split("#")[-1] + "$"

				if f_name != p_f_name or s_name != p_s_name:
					p_f_name = f_name
					p_s_name = s_name

					if FIRST: FIRST = False
					else:     f.write("\n")

					f.write(("FILE: " + f_name + ".asm").ljust(30) + "SECTION: " + s_name + "\n")

				f.write(("   " + addr_to_hex(addr) + "  " + is_glb).ljust(20) + lbl + "\n")






		#with open(outputfile, "wb") as outf:
		#	outf.write(bytes(HEX_DATA[:ROM_SIZE * 0x400]))

		if NO_ERRORS: 
			print("\n[INFO] Successfully linked to " + str(outputfile) + ".\n\n")
		else:
			print("\n[WARNING] Warnings or Errors occured during linking stage. Please look over errors.")
			print("[INFO] Linked to " + str(outputfile) + ".\n\n")

	except Exception as e:

		traceback.print_exc()

		print("\n[ERROR] Link failed.\n\n")



if __name__ == "__main__":


	parser = argparse.ArgumentParser(description="Link .rel files into a code ROM.")

	parser.add_argument("inputfile", metavar="inputfile", type=str, help="Name of file containing locations of .rel files to link.", default="")

	parser.add_argument("optionsfile", metavar="optionsfile", type=str, help="Name of file containing linker options.", default="")

	parser.add_argument("outputfile", metavar="outputfile", type=str, help="Name of output ROM file to create.", default="")

	#parser.add_argument("--rom_size", dest="rom_size", default=512, type=int, help="Set output rom size (in KB)")



	ARGS = vars(parser.parse_args())



	if ARGS["inputfile"] != "":
		inputfile = ARGS["inputfile"]

	if ARGS["optionsfile"] != "":
		optionsfile = ARGS["optionsfile"]

	if ARGS["outputfile"] != "":
		outputfile = ARGS["outputfile"]

	#ROM_SIZE = ARGS["rom_size"]

	REL_OPTIONS = []
	with open(optionsfile, "r") as r:
		for line in r:
			REL_OPTIONS.append(line)

	rel_files = get_rel_files(inputfile)


	rel_opts = []

	for line in REL_OPTIONS:
		rel_opts.append(line.replace("\n", ""))


	DO_LINK({
		"rel_files": rel_files,
		"-r": rel_opts[0],
		"outputfile": outputfile,
		#"ROM_SIZE": ROM_SIZE,
		"map_file": "out.map"
		})