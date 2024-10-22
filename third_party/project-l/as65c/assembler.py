###################################################
#   Main as65c assembler program
#      by MrL314
#
#        [ Nov.15, 2021 ]
###################################################



# standard imports
import traceback
import sys, os
import math
from datetime import date, datetime
import argparse
import hashlib
import time
import threading

# local imports
import LineObject
import util
from exceptions import LineException, LineError




# stupid fix because python didnt want to keep this as the working directory
#abspath = os.path.abspath(__file__)
#dname = os.path.dirname(abspath)
os.chdir(os.getcwd())
#os.chdir("..")
#os.chdir("..")
#print(os.getcwd())





# temp variable indicator symbols, change later to impossible symbols
TEMP_LEFT = "<" # "◄"
TEMP_RIGHT = ">" # "►"



#SYMBOLS_FILE = "SYMBOLS.txt"


EXTERNAL_SYMBOLS = {}



def get_symbols(file):

	global EXTERNAL_SYMBOLS


	for var, vartype, varval in util.get_symbols(file):
		EXTERNAL_SYMBOLS[var] = (vartype, varval)



def set_symbols(file):

	global EXTERNAL_SYMBOLS


	util.set_symbols(EXTERNAL_SYMBOLS, file)




def add_hash(filename, curr_hash):

	file_hash = hashlib.sha256(filename.encode())

	util.add_hash(file_hash, curr_hash)


def get_hash(filename):
	file_hash = hashlib.sha256(filename.encode())

	return util.get_hash(file_hash)









def read_file(filename):

	lines = []

	with open(filename, "r", encoding="utf-8", errors="ignore") as file:
		for line in file:
			lines.append(line.replace("\n", ""))


	return lines



def read_bin_file(filename):

	lines = []
	with open(filename, "rb") as file:

		data = file.read()

		ind = 0

		# parse each 16 bytes as a data line
		while ind < len(data):
			data_line = data[ind:ind+16]
			ind += 16

			line = "\t\tdb\t" # match format of regular code

			for d in range(len(data_line)):
				if d != 0:
					line += ", "
				line += format(data_line, "02x") + "h"

			lines.append(line)

	return lines





def getsecind(s):
	if s > 1:
		return s + 1
	else:
		return s





def get_formats(op):
	return util.get_formats(op.upper())






def parse_format(LINE):
	
	out_form = []

	for el in LINE:

		if el["type"] in util.PARSE_TYPES:
			f = util.PARSE_TYPES[el["type"]]

			if f == "TYPE" and el["valtype"].lower() in util.CONVERT_DATA_TYPE:
				f = util.CONVERT_DATA_TYPE[el["valtype"].lower()]
			elif f == "REGISTER" and el["register"].lower() in util.CONVERT_REGISTER:
				f = util.CONVERT_REGISTER[el["register"].lower()]

			out_form.append(f)
		else:
			raise Exception("INVALID TYPE:", el["type"])

	return " ".join(out_form)


	




def parse_instruction(LINE, instruction, LINE_OBJ, attempt_dp=False):
	global data_page

	opcode = -1



	if attempt_dp:
		for L in range(len(LINE)):
			if LINE[L]["type"] == util.DATA_TYPES.TYPE:
				if LINE[L]["valtype"] == "addr":
					if LINE[L]["size"] == 2:
						try:
							if LINE[L]["value"]["value"] - data_page < 0x100:
								LINE[L]["size"] = 1
								LINE[L]["value"]["size"] = 1
								LINE[L]["value"]["value"] = LINE[L]["value"]["value"] - data_page
								LINE[L]["valtype"] = "dp"
						except:
							pass
	
	#L_FORM = None	
	try:
		L_FORM = parse_format(LINE[1:])
	except:
		#raise LineError(LINE_OBJ, "Cannot encode instruction " + instruction + ". Improper format.\n" + str(LINE))
		raise LineError(LINE_OBJ, "Cannot encode instruction " + instruction + ". Improper format.")

	FORMATS = get_formats(instruction.upper())



	if L_FORM in FORMATS:
		opcode = FORMATS[L_FORM]

	

	if opcode == -1 and not attempt_dp:
		opcode = parse_instruction(LINE, instruction, LINE_OBJ, attempt_dp = True)


	if opcode == -1:
		possible_formats = [(instruction + " " + ''.join(str(f).split(" "))) for f in FORMATS]
		#raise LineException(LINE_OBJ.get_line_num(), "Cannot encode instruction " + instruction + ". Improper format. \n\t" + str(LINE_OBJ.get_raw()) + "\nProper formats include:\n\t" + "\n\t".join(possible_formats), LINE_OBJ.get_file_name())
		raise LineError(LINE_OBJ, "Cannot encode instruction " + instruction + ". Improper format. Proper formats include:\n\t" + "\n\t".join(possible_formats))


	return opcode




def make_length_bytes(L):

	size_bytes = []

	while L != 0:
		size_bytes.append(L % 256)

		L = L // 256

	if len(size_bytes) == 1:
		if size_bytes[0] < 0x80:
			size_bytes[0] = size_bytes[0] | 0x80
		else:
			size_bytes.append(1)
	else:
		size_bytes.append(len(size_bytes))

	return [x for x in reversed(size_bytes)]




def get_file_attrs(file):
	filename = path = ""

	file = os.path.abspath(file)

	# convert file path to Windows style file path
	file = file.replace("\\", "/")

	# split up path by directories
	split_path = file.split("/")


	if file.rfind("/") != -1:
		# if file is not in the same directory
		path = "/".join(split_path[:-1]) + "/" # file directory is everything up until file name

	# file name is last part of file path
	filename = split_path[-1]

	return (path, filename)



def file_hash(filename):
	h = hashlib.sha256()

	with open(filename, "rb") as file:
		chunk = 0
		while chunk != b'':
			chunk = file.read(8192)
			h.update(chunk)

	return h.hexdigest()



def get_file_include_text(filename):

	path, file = get_file_attrs(filename)

	FILE_LINES = []

	try:
		with open(filename, "r", encoding="utf-8", errors="ignore") as f:
			for line in f:
				FILE_LINES.append(line.encode("utf-8"))

				if "include" in line.lower():
					LOBJ = LineObject.Line(line)

					prsd = LOBJ.get_parsed()

					for i in range(len(prsd)):
						chunk = prsd[i]
						if chunk["type"] == util.DATA_TYPES.INCLUDE:
							sub_file = chunk["filename"]

							for sub_line in get_file_include_text(path + sub_file):
								FILE_LINES.append(sub_line)
	except:
		FILE_LINES = [filename.encode("utf-8")]

	return FILE_LINES






def HASH_CHECK(filename, asmvars={}):

	util.load_hashes()

	FILE_LINES = get_file_include_text(filename)

	curr_hash = hashlib.sha256()

	for l in FILE_LINES:
		curr_hash.update(l)

	for var in asmvars:
		var_l = str(var) + "=" + str(asmvars[var])
		curr_hash.update(var_l.encode("utf-8"))

	updated = False
	if curr_hash.hexdigest() != get_hash(filename): updated = True

	return (updated, curr_hash)






from queue import Queue
	

class ASM_FILE(object):

	def __init__(self, ext_vars={}):
		self._INCLUDED_FILES = set()
		self._ext_vars = ext_vars or {}
		self._ASM_LINES = []
		

	def GET_INCLUDED_FILES(self):
		return self._INCLUDED_FILES


	#def make_line_object(self, line, file=None, line_number=None, include_level=None):
	#	return LineObject.Line(line, file=file, line_number=line_number, include_level=include_level)


	def MAKE_ASM_LINES(self, filename, include_level=0):

		'''
		No_set_line_num = True
		if line_number == None:
			No_set_line_num = False
			line_number = 1
		'''

		self._INCLUDED_FILES.add(os.path.abspath(filename))

		line_number = 1

		ASM_LINES = read_file(filename)


		#LINES = []
		ended = False
		if_condition = True
		IF_LAYER = 0

		#defined_vars = {}
		NUM_LINES = len(ASM_LINES)

		in_macro = False




		line_number = 1


		IF_CONDS = [True]

		for line in ASM_LINES:


			

			L_OBJ = LineObject.Line(line, file=filename, line_number=line_number, include_level=include_level)

			if L_OBJ.get_is_end():
				self._ASM_LINES.append(L_OBJ)
				break


			LINE = L_OBJ.get_parsed()

			if_condition = IF_CONDS[-1]

			if LINE != []:

				# handle if conditions
				if LINE[0]["type"] == util.DATA_TYPES.CONDITIONAL_IF:
					IF_LAYER += 1

					condition = LINE[0]["condition"]

					cond_str = ""
					first = True
					for s in condition.split(" "):
						if not first: cond_str += " "
						first = False

						if s in util.ARITHMETIC_SYMBOLS:
							cond_str += s
						else:
							is_int = True
							try:
								int(s)
							except:
								is_int = False

							if is_int: cond_str += s
							else:
								# is a variable. Check if external var
								if s in self._ext_vars:
									cond_str += str(self._ext_vars[s])
								else:
									#raise LineException(L_OBJ.get_line_num(), str(s) + " not found in assembler variables.\n" + L_OBJ.get_raw(), L_OBJ.get_file_name())
									raise LineError(L_OBJ, str(s) + " not found in assembler variables.")


					if_cond = util.evaluateExpression(cond_str)

					if if_cond != 0: if_cond = True
					if if_cond == 0: if_cond = False
					
					IF_CONDS.append(if_cond)


				elif LINE[0]["type"] == util.DATA_TYPES.CONDITIONAL_ENDIF:
					IF_CONDS.pop()
					IF_LAYER -= 1

				elif LINE[0]["type"] == util.DATA_TYPES.CONDITIONAL_ELSE:
					if IF_LAYER == 0: 
						#raise LineException(L_OBJ.get_line_num(), "Cannot parse ELSE without IF statement.\n" + L_OBJ.get_raw(), L_OBJ.get_file_name())
						raise LineError(L_OBJ, "Cannot parse ELSE without IF statement.")

					if_condition = not IF_CONDS.pop()
					IF_CONDS.append(if_condition)

				else:

					if IF_LAYER == 0 or if_condition:
						self._ASM_LINES.append(L_OBJ)


						if L_OBJ.is_include_line():
							if in_macro:
								raise LineError(L_OBJ, "'INCLUDE' statement inside macro is not yet currently supported.")

							for chunk in LINE:

								if chunk["type"] == util.DATA_TYPES.INCLUDE:

									if not L_OBJ.already_included():
										# if not already undergone the include process
										L_OBJ.set_already_included() # so include doesnt happen again

										file = chunk["filename"]     # include file
										path = L_OBJ.get_file_path() # file path relative to source file

										real_path = os.path.abspath(path + file)

										if not (real_path in self._INCLUDED_FILES):

											self.MAKE_ASM_LINES(path + file, include_level=include_level+1)

											break


						elif L_OBJ.get_is_macro_def():
							in_macro = True

						elif L_OBJ.get_is_macro_end():
							in_macro = False



					


			#if not No_set_line_num:
			#	line_number += 1
			line_number += 1



		


		return self._ASM_LINES














def assembleFile(filename, ext_vars={}, force_assemble=False, check_hash=False, print_verbose=False):

	global EXTERNAL_SYMBOLS
	global data_page
	global data_bank


	#INCLUDED_FILES = set(os.path.abspath(filename))

	#print(ext_vars)

	ASM_START = util.get_time()

	TIMING_DEBUG = False

	if print_verbose:
		TIMING_DEBUG = True

	try:

		start = util.get_time()

		

		#get_symbols(SYMBOLS_FILE)

		#FILE_NAME = filename.split("/")[-1]
		#FILE_PATH = "/".join(filename.split("/")[:-1]) + "/"

		FILE_PATH, FILE_NAME = get_file_attrs(filename)

		succeeded = False
		hash_text = ""
		curr_hash = None

		

		file_updated, curr_hash = HASH_CHECK(filename, ext_vars)   # check hash data against last successful assembly 

		if (not force_assemble) and file_updated: force_assemble = True

		if not force_assemble:
			try:
				f = open(FILE_PATH + FILE_NAME.split(".")[0] + ".rel")

				f.close()
			except:
				force_assemble = True

		#if TIMING_DEBUG: print("\n  hash load time: ", format(util.get_time()-start, " 10.5f"))

		if not force_assemble:
			succeeded = True
			print("[INFO] No changes to " + FILE_NAME + " detected. Skipping re-assembly.")
			raise EOFError() # this is ONLY so assembly process doesnt run if file is not changed


		if TIMING_DEBUG: print("\n  hash load time: ", format(util.get_time()-start, " 10.5f"))

		macros = {}

	

		#ASM_LINES = read_file(filename)

		FILE_NUM = 0

		NV_IND = 0

		start = util.get_time()
		#start2 = util.get_time()
		#lnum = 1
		LINES = []
		#ended = False
		hash_lines = []


		ASM_LINES_OBJ = ASM_FILE(ext_vars=ext_vars)


		#LINES, INCLUDED_FILES = MAKE_ASM_LINES(filename, ext_vars=ext_vars)

		LINES = ASM_LINES_OBJ.MAKE_ASM_LINES(filename)

		INCLUDED_FILES = ASM_LINES_OBJ.GET_INCLUDED_FILES()
		



		tempvar = 0 # temp variable indicator number


		localvars = [
			{"name": "   ", "value": 0, "offset": None, "section": None, "type": "exact", "is_temp": True}, 
			{"name": "REL", "value": 0, "offset": None, "section": None, "type": "exact", "is_temp": True}
		]
		VAR_LINE_USES = {}
		globalvars = [""]
		externalvars = [""]

		if TIMING_DEBUG: print("  include time: ", format(util.get_time()-start, " 10.5f"))








		
		total_clean = 0
		total_parse = 0
		#total_lines = 0

		for L in LINES:
			total_clean += L._clean_time
			total_parse += L._parse_time

		if TIMING_DEBUG: print("    - total time cleaning: ", format(total_clean, " 10.5f"))
		if TIMING_DEBUG: print("    - total time parsing : ", format(total_parse, " 10.5f"))


		






		start = util.get_time()
		# step 1.5: create macros and replace where necessary

		line_ind = 0
		in_macro = False
		curr_macro_vars = []
		macro_var_ind = 0
		curr_macro_name = ""
		curr_macro_lines = []
		curr_macro_raw_lines = []
		macro_vars_by_length = []
		#macro_locals_by_length = []
		curr_macro_locals = []
		NUM_LINES = len(LINES)
		curr_macro_start_line = 0


		#macro_lvl = 0   # current depth of nested macros


		while line_ind < NUM_LINES:
			LINE_OBJ = LINES[line_ind]



			LINE = LINE_OBJ.get_parsed()
			#lnum = LINE_OBJ.get_line_num()

			LINE_LEN = len(LINE)

			cind = 0

			if in_macro:
				# parse macro line


				if LINES[line_ind].get_is_macro_def():
					raise LineError(LINE_OBJ, "Cannot nest macro defines. Perhaps you forgot to end the previous macro: '" + str(curr_macro_name) + "'?")

				LINES[line_ind].is_macro(True)

				raw_line = LINE_OBJ.get_raw()
				real_raw = raw_line

				pre_raw = raw_line

				if LINE_LEN > 0 and (LINE[0]["type"] == util.DATA_TYPES.MACRO_LOCAL):
					raw_line = ""
				else:
					for var in macro_vars_by_length:
						vind = curr_macro_vars.index(var)

						# some macros use & to indicate local variable. maybe find a better way?
						raw_line = raw_line.replace("&" + var, str(util.M_VAR_CHAR_A) + str(vind) + str(util.M_VAR_CHAR_B))

						# some macros will allow the use of a direct substitution
						raw_line = raw_line.replace(str(util.M_SUB_CHAR_A) + var + str(util.M_SUB_CHAR_B), str(util.M_VAR_CHAR_A) + str(vind) + str(util.M_VAR_CHAR_B))


						raw_line = raw_line.replace(var, str(util.M_VAR_CHAR_A) + str(vind) + str(util.M_VAR_CHAR_B))



					#for var in macro_locals_by_length:
					#	vind = curr_macro_locals.index(var)
					#
					#	# some macros use & to indicate local variable. maybe find a better way?
					#	raw_line = raw_line.replace("&" + var, curr_macro_name + str(util.MACROVAR_SYMBOL) + str(vind))
					#
					#	raw_line = raw_line.replace(var, curr_macro_name + str(util.MACROVAR_SYMBOL) + str(vind))



				#if raw_line != pre_raw:
				#	print("Line changed! \n\t" + pre_raw + "\nto\n\t" + raw_line + "\n")

				curr_macro_lines.append(raw_line)
				curr_macro_raw_lines.append(real_raw)






			
			while cind < LINE_LEN:


				if LINE[cind]["type"] == util.DATA_TYPES.MACRO:
					LINES[line_ind].is_macro(True)
					in_macro = True
					curr_macro_name = LINE[cind]["varname"]

					if curr_macro_name in macros:
						#raise LineException(LINE_OBJ.get_line_num(), "Redefinition of macro '" + str(curr_macro_name) + "'.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
						raise LineError(LINE_OBJ, "Redefinition of macro '" + str(curr_macro_name) + "'.")
					vind = 1
					while cind + vind < LINE_LEN:
						chunk = LINE[cind + vind]
						if chunk["type"] == util.DATA_TYPES.VARIABLE:
							curr_macro_vars.append(chunk["varname"])

						vind += 1

					macro_vars_by_length = sorted(curr_macro_vars, key=len, reverse=True)

					cind = LINE_LEN

				elif LINE[cind]["type"] == util.DATA_TYPES.END_MACRO:
					curr_macro_lines = curr_macro_lines
					LINES[line_ind].is_macro(True)
					in_macro = False
					macros[curr_macro_name] = {
						"name": curr_macro_name,
						"macro_lines": curr_macro_lines,
						"macro_vars": curr_macro_vars,
						"raw_lines": curr_macro_raw_lines,
						"local_vars": curr_macro_locals,#sorted(curr_macro_locals, key=len, reverse=True)
						"times_called": 0
					}
					cind = LINE_LEN
					curr_macro_lines = []
					curr_macro_raw_lines = []
					curr_macro_vars = []
					macro_var_ind = []
					curr_macro_name = ""
					macro_vars_by_length = []
					#macro_locals_by_length = []
					curr_macro_locals = []


				elif LINE[cind]["type"] == util.DATA_TYPES.MACRO_LOCAL:
					# designates a local variable for the macro

					vind = 1
					#print(LINE)
					while cind + vind < LINE_LEN:
						chunk = LINE[cind + vind]
						if chunk["type"] == util.DATA_TYPES.VARIABLE:
							if not (chunk["varname"] in curr_macro_locals):
								curr_macro_locals.append(chunk["varname"])

						vind += 1

					#macro_locals_by_length = sorted(curr_macro_locals, key=len, reverse=True)

					cind += vind

				cind += 1 


			line_ind += 1


			LINE_OBJ.set_parsed(LINE)


		#print(macros)

		TEMP_LINES = []

		line_ind = 0

		NUM_LINES = len(LINES)
		while line_ind < NUM_LINES:

			LINE_OBJ = LINES[line_ind]

			LINE = LINE_OBJ.get_parsed()
			

			cind = 0

			TEMP_LINES.append(LINE_OBJ)

			#if not LINE_OBJ.get_is_macro():
			#	line_ind += 1
			#	continue

			#if LINE_OBJ.get_is_macro_def() == True:
			#	print(LINE_OBJ.get_line_num(), LINE_OBJ.get_raw())

			#if LINE_OBJ.get_is_macro_end() == True:
			#	print(LINE_OBJ.get_line_num(), LINE_OBJ.get_raw())

			#if LINE_OBJ.get_is_macro() == True:
			#	print(LINE_OBJ.get_line_num(), LINE_OBJ.get_raw())

			LINE_LEN = len(LINE)
			while cind < LINE_LEN:


				if LINE[cind]["type"] in {util.DATA_TYPES.LABEL, util.DATA_TYPES.VARIABLE}:

					if LINE[cind]["varname"] in macros:

						lnum = LINE_OBJ.get_line_num()
						RAW = LINE_OBJ.get_raw()
						CLEAN = LINE_OBJ.get_clean_line()

						#print(lnum, CLEAN)

						m_name = LINE[cind]["varname"]

						MACRO = macros[LINE[cind]["varname"]]

						variable_vals = []

						split = (" " + CLEAN + " ").split(" " + m_name + " ")

						args = (" " + m_name + " ").join(split[1:])


						for var in args.split(" , "):
							if var != '':
								variable_vals.append(var.lstrip().rstrip())


						if len(variable_vals) != len(MACRO["macro_vars"]):
							#print(LINE_OBJ.get_parsed())
							#print("variable vals:", variable_vals)
							#raise LineException(LINE_OBJ.get_line_num(), "Incorrect number of arguments for macro \'" + LINE[cind]["varname"] + "\'.\n\tRequired " + str(len(MACRO["macro_vars"])) + ", Given: " + str(len(variable_vals)) + ".\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
							raise LineError(LINE_OBJ, "Incorrect number of arguments for macro \'" + LINE[cind]["varname"] + "\'.\n\tRequired " + str(len(MACRO["macro_vars"])) + ", Given: " + str(len(variable_vals)) + ".")



						#LINES[line_ind] = LineObject.Line(";", line_number=LINE_OBJ.get_line_num(), file=LINE_OBJ.get_file_path() + LINE_OBJ.get_file_name(), include_level=LINE_OBJ.get_include_level()+1)
						
						# last working version:
						TEMP_LINES[-1] = LineObject.Line(";", line_number=LINE_OBJ.get_line_num(), file=LINE_OBJ.get_file_path() + LINE_OBJ.get_file_name(), include_level=LINE_OBJ.get_include_level())
						#TEMP_LINES[-1].set_parsed(LINE[:cind])




						'''
						CLEAN = split[0].lstrip().rstrip()
						CLEAN = " ".join((CLEAN + " " + MACRO["macro_lines"][0]).split())


						FUNC_LINE = CLEAN
						vind = 0
						for var in variable_vals:
							FUNC_LINE = FUNC_LINE.replace(MACRO["name"] + str(util.MACROVAR_SYMBOL) + str(vind), var)
							vind += 1

						print(FUNC_LINE)
						'''
						



						lind = 0
						for macro_line in MACRO["macro_lines"][:-1]:
							FUNC_LINE = macro_line
							FUNC_BEFORE = FUNC_LINE

							#print(FUNC_LINE)

							vind = 0
							for var in variable_vals:
								FUNC_LINE = FUNC_LINE.replace(str(util.M_VAR_CHAR_A) + str(vind) + str(util.M_VAR_CHAR_B), var)
								vind += 1

							for var in MACRO["local_vars"]:
								#FUNC_LINE = FUNC_LINE.replace(var, MACRO["name"] + "_call_" + str(MACRO["times_called"]) + "_LOCAL_" + var)    #  
								FUNC_LINE = FUNC_LINE.replace(var, var + "@" + MACRO["name"] + "˜" + str(MACRO["times_called"]))    #  ˜ = ALT + 0152

							#print(FUNC_LINE)

							#if FUNC_LINE != FUNC_BEFORE:
							#	print("Line changed! \n\t" + FUNC_BEFORE + "\nto\n\t" + FUNC_LINE + "\n")

							mac_line = 'MACRO ' + MACRO["name"]
							mac_line = mac_line + " "*(8-len(mac_line)) + "\t… "		# … = ALT + 0133


							# preserve label at beginning of line for macro call if needed
							if lind == 0:
								pre_mac = split[0].lstrip().rstrip()
								if pre_mac != "": 
									if FUNC_LINE.lstrip() == FUNC_LINE: pre_mac += "\t"
									FUNC_LINE = pre_mac + FUNC_LINE


							M_LINE = LineObject.Line(FUNC_LINE, line_number=LINE_OBJ.get_line_num(), file=LINE_OBJ.get_file_path() + LINE_OBJ.get_file_name(), include_level=LINE_OBJ.get_include_level()+1, macro_line=mac_line + FUNC_LINE)

							#print("FUNC_LINE: ", FUNC_LINE, "\nM_LINE:    ", M_LINE.get_raw(), "\n")


							#LINES.insert(line_ind + lind + 1, M_LINE)
							TEMP_LINES.append(M_LINE)

							#print(M_LINE.get_raw())

							lind += 1

						

						#LINES.insert(line_ind + lind + 1, LineObject.Line(MACRO["macro_lines"][-1], line_number=LINE_OBJ.get_line_num(), file=LINE_OBJ.get_file_path() + LINE_OBJ.get_file_name(), include_level=LINE_OBJ.get_include_level()+1, macro_line='MACRO ' + MACRO["name"] + ':\t\t' + MACRO["raw_lines"][-1]))
	
						cind = LINE_LEN

						macros[m_name]["times_called"] = macros[m_name]["times_called"] + 1

				cind += 1

			line_ind += 1


		if TIMING_DEBUG: print("  macros time: ", format(util.get_time()-start, " 10.5f"))




		start = util.get_time()

		NUM_LINES = len(TEMP_LINES)
		L_IND = 0

		#BASE_LINES = LINES
		LINES = []


		for LOBJ in TEMP_LINES:

			if LOBJ.get_uses_near_var():
				p = LOBJ.get_parsed()
				for ind in LOBJ.get_near_inds():
					
					p[ind]["label"] = "_NEAR_VAR" + str(NV_IND)
					p[ind]["varname"] = "_NEAR_VAR" + str(NV_IND)
					

					NEW_LINE = LineObject.Line("_NEAR_VAR" + str(NV_IND), file=LOBJ.get_file_path() + LOBJ.get_file_name(), line_number=LOBJ.get_line_num(), include_level=LOBJ.get_include_level())
					NEW_LINE.set_hide_lis()
					#NEW_LINE.set_uses_near_var()

					LINES.append(NEW_LINE)
					NV_IND += 1

				LOBJ.set_parsed(p)

			LINES.append(LOBJ)


		if TIMING_DEBUG: print("  near-var lines time: ", format(util.get_time()-start, " 10.5f"))




		start = util.get_time()
		# step 2: combine expressions into a single piece, and label external variables as such
		lv_len = len(localvars)
		for LINE_OBJ in LINES:

			LINE = LINE_OBJ.get_parsed()

			
			if LINE != [] and LINE[0]["type"] == util.DATA_TYPES.LABEL:
				is_base_label = True

				if "is_near" in LINE[0] and LINE[0]["is_near"] == True: is_base_label = False

				if LINE_OBJ.get_is_hidden(): is_base_label = False

				if is_base_label:
					CURR_LABEL = LINE[0]["varname"]
			

			if LINE_OBJ.get_is_macro():
				continue



			cind = 0
			while cind < len(LINE):
				chunk = LINE[cind]

				
				adjust_label = False
				if chunk["type"] == util.DATA_TYPES.LABEL:
					if "is_near" in chunk and chunk["is_near"] == True:
						if not "varname" in chunk:
							chunk["varname"] = chunk["label"]
						adjust_label = True

				if chunk["type"] == util.DATA_TYPES.VARIABLE:
					if "is_near" in chunk and chunk["is_near"] == True:
						if not "label" in chunk:
							chunk["label"] = chunk["varname"]
						adjust_label = True

				if adjust_label:

					if chunk["varname"][-1] == "$":

						#print("IS A SUB LABEL: " + str(chunk["varname"]))
						new_name = CURR_LABEL + "#" + chunk["varname"][:-1]
						chunk["varname"] = new_name
						chunk["label"] = new_name
						chunk["is_near"] = False


					LINE[cind] = chunk				
					
				



				if chunk["type"] == util.DATA_TYPES.GLOBAL:
					if not (chunk["varname"] in globalvars):
						globalvars.append(chunk["varname"])

					vind = 0
					
					while vind < lv_len:
						var = localvars[vind]
						
						if var["name"] == chunk["varname"]:
							#localvars = localvars[:vind] + localvars[vind+1:]
							localvars.pop(vind)
							lv_len -= 1
							vind -= 1

						vind += 1

					if chunk["varname"] in externalvars:
						externalvars.remove(chunk["varname"])

				elif chunk["type"] == util.DATA_TYPES.EXTERNAL:
					#print(chunk["varname"])
					if not (chunk["varname"] in externalvars):
						externalvars.append(chunk["varname"])
					if not (chunk["varname"] in globalvars):
						globalvars.append(chunk["varname"])

				cind += 1

			LINE_OBJ.set_parsed(LINE)

		EXTERNALVARS_SET = set(externalvars)


		if TIMING_DEBUG: print("  external label time: ", format(util.get_time()-start, " 10.5f"))


		LOCAL_EXTERNAL = set()
		

		start = util.get_time()
		# expression combine

		ALL_USED_VARS = set()

		external_calls = 0

		for LINE_OBJ in LINES:

			LINE = LINE_OBJ.get_parsed()

			if LINE_OBJ.get_is_macro():
				continue

			cind = 0


			while cind < len(LINE):
				chunk = LINE[cind]

				type_2 = False
				type_3 = False


				if chunk["type"] == util.DATA_TYPES.TYPE and chunk["valtype"] in {"bank", "offset", "high", "low"}:
					if cind > 0:
						if LINE[cind-1]["type"] == util.DATA_TYPES.TYPE:
							type_2 = True

					if cind + 1 < len(LINE):
						if LINE[cind+1]["type"] == util.DATA_TYPES.VARIABLE:
							if LINE[cind+1]["varname"] in externalvars:
								type_3 = True
							elif cind+2 >= len(LINE):
								type_3 = True
								LOCAL_EXTERNAL.add(LINE[cind+1]["varname"])
							elif LINE[cind+2]["type"] != util.DATA_TYPES.OPERATOR:
								type_3 = True
								LOCAL_EXTERNAL.add(LINE[cind+1]["varname"])


				if type_2:
					#print("NO POP", LINE)
					LINE.pop(cind-1)
					cind -= 1
					#print("AFTER POP", LINE)
					#pass
					type_2 = False

				elif type_3:
					pass

				elif chunk["type"] == util.DATA_TYPES.OPERATOR or (chunk["type"] == util.DATA_TYPES.TYPE and chunk["valtype"] in {"bank", "offset", "high", "low"}):
					ind = 0
					ended = False
					prev_was_operator = True
					while (not ended) and (cind + ind < len(LINE)):

						if LINE[cind+ind]["type"] == util.DATA_TYPES.OPERATOR or (LINE[cind+ind]["type"] == util.DATA_TYPES.TYPE and LINE[cind+ind]["valtype"] in {"bank", "offset", "high", "low"}):
							prev_was_operator = True
						else:
							if LINE[cind+ind]["type"] == util.DATA_TYPES.SEPARATOR:
								ended = True
								break

							if not prev_was_operator:
								ended = True
								break
							prev_was_operator = False

						ind += 1



					# turn into an expression string
					prev_off = 1
					'''
					if LINE[cind-1]["type"] == util.DATA_TYPES.EQU:
						prev_off = 0
					if LINE[cind-1]["type"] == util.DATA_TYPES.TYPE:
						prev_off = 0
					'''
					'''
					if cind+ind < len(LINE):
						if LINE[cind+ind]["type"] == util.DATA_TYPES.SEPARATOR:
							ind -= 1 
					'''

					if "operator" in LINE[cind] and LINE[cind]["operator"] == "(":
						prev_off = 0
					elif LINE[cind]["type"] == util.DATA_TYPES.TYPE and LINE[cind]["valtype"] in {"bank", "offset", "high", "low"}:
						prev_off = 0

					expression_data = LINE[cind-prev_off:cind+ind]
					line_data = [LINE[:cind-prev_off], LINE[cind+ind:]]

					expression = ""
					expression_vars = [] # keep track of variables used


					ex_check = 0
					
					# pre-check to make sure external labels dont get parsed incorrectly
					if expression_data[0]["type"] == util.DATA_TYPES.VARIABLE:
						# external label expression MUST start with external label
						var_name = expression_data[0]["varname"]
						
						if var_name in externalvars:
							# must be an imported symbol

							#print(LINE)
							#print(expression_data)

		
							if expression_data[1]["type"] == util.DATA_TYPES.OPERATOR and (expression_data[1]["operator"] == "+" or expression_data[1]["operator"] == "-"):
								neg_off = False
								if expression_data[1]["operator"] == "-": neg_off = True

								line_data.insert(1, {"type": util.DATA_TYPES.VARIABLE, "varname": var_name, "label": var_name, "is_external_label": True, "external_offset": 0, "negative_offset": neg_off})

								'''
								if expression_data[1]["operator"] == "-":
									expression_data = [
												{"type": util.DATA_TYPES.VALUE, "value": -1}, 
												{"type": util.DATA_TYPES.OPERATOR, "operator": "*"}, 
												{"type": util.DATA_TYPES.OPERATOR, "operator": "("}] + expression_data[2:] + [{"type": util.DATA_TYPES.OPERATOR, "operator": ")"}]
								else:
								'''
								expression_data = expression_data[2:] # skip over addition symbol 
							else:
								#raise LineException(LINE_OBJ.get_line_num(), "External label offsets can only be expressed as positive offsets from that label.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
								#raise LineException(LINE_OBJ.get_line_num(), "Error parsing external label with offset.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
								raise LineError(LINE_OBJ, "Error parsing external label with offset.")
					


					




					ind = 0
					for e in expression_data:
						expression += " "

						if e["type"] == util.DATA_TYPES.VARIABLE:
							
							expression += str(e["varname"])
							expression_vars.append(e["varname"])
					
							if e["varname"] in externalvars:
								#external variable used in an expression, not at the begining. I will *NOT* allow this
								#raise LineException(LINE_OBJ.get_line_num(), "External labels with offset MUST be used at front of calculation.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
								if ind != 0:
									#raise LineException(LINE_OBJ.get_line_num(), "External labels with offset MUST be used at front of calculation.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "External labels with offset MUST be used at front of calculation.")
									#print("[WARNING] External labels with offset should be used at front of calculation. At line", LINE_OBJ.get_line_num(), "\n", LINE_OBJ.get_raw())




						elif e["type"] == util.DATA_TYPES.LABEL:
							expression += str(e["varname"])
							expression_vars.append(e["varname"])

						elif e["type"] == util.DATA_TYPES.VALUE:
							expression += str(e["value"])

						elif e["type"] == util.DATA_TYPES.OPERATOR:
							expression += str(e["operator"])

						elif e["type"] == util.DATA_TYPES.TYPE:
							ch = e["valtype"]
							#if e["valtype"]   == "bank":   ch = util.BANK_CHAR
							#elif e["valtype"] == "offset": ch = util.OFFSET_CHAR
							#elif e["valtype"] == "high":   ch = util.HIGH_CHAR
							#elif e["valtype"] == "low":    ch = util.LOW_CHAR

							expression += str(ch)

						#elif e["type"] == 

						ind += 1

					USES_NEAR = False
					if LINE_OBJ.get_uses_near_var(): 
						USES_NEAR = True



					line_data.insert(len(line_data) - 1, {"type": util.DATA_TYPES.EXPRESSION, "expression": expression, "expression_vars": expression_vars, "uses_near": USES_NEAR})

					line_data = util.flatten_list(line_data)

					LINE = line_data

					#for v in expression_vars:
					#	ALL_USED_VARS.add(v)

					#if USES_NEAR:
					#	print("USES NEAR: ", LINE)

				cind += 1

			LINE_OBJ.set_parsed(LINE)


		if TIMING_DEBUG: print("  expression time: ", format(util.get_time()-start, " 10.5f"))





		start = util.get_time()

		# step 3: set EQU values, labels, and processor offsets

		var_uses = {}
		STORAGE_LABELS = set()

		section = "P" + FILE_NAME.split(".")[0]
		data_bank = 0
		data_page = 0

		mem = 16
		idx = 16


		ORGANIZATION_TAGS = ["sect", "org", "rel"]


		groups = ["", "PROG", "DATA"]
		group_sections = {}

		section_offsets = {
			"P" + FILE_NAME.split(".")[0]: 0,
			"D" + FILE_NAME.split(".")[0]: 0}

		
		section_storage = {
			"P" + FILE_NAME.split(".")[0]: 0,
			"D" + FILE_NAME.split(".")[0]: 0}
		

		sections = [
			{"secname": None, "group": None, "code_data": [], "type": None, "offset": None, "size": 0}, 
			{"secname": "P" + FILE_NAME.split(".")[0], "group": "PROG", "code_data": [], "type": util.DATA_TYPES.SECTION, "offset": None, "size": 0}
			]
		processor_flags = []
		sec_ind = 1
		sec_len = 0
		org_ind = 1
		CURR_LABEL = "_"
		for LINE_OBJ in LINES:

			LINE = LINE_OBJ.get_parsed()

			if LINE_OBJ.get_is_macro():
				continue

			cind = 0



			while cind < len(LINE):
				chunk = LINE[cind]


				# refine section data

				if chunk["type"] == util.DATA_TYPES.SECTION or chunk["type"] == util.DATA_TYPES.ORG: # add others later
					#sec_ind += 1 
					


					section = LINE[cind-1]["varname"]

					if chunk["type"] == util.DATA_TYPES.ORG:
						section = "A" + str(org_ind) + section
						org_ind += 1

					if not (section in section_offsets):
						section_offsets[section] = 0

					if not (section in section_storage):
						section_storage[section] = 0

					sections[-1]["size"] = sec_len

					sec_len = 0

					if chunk["type"] == util.DATA_TYPES.SECTION:
						# section
						group = section
						if section.lower() == "comn":
							group = "PROG" 
						sections.append({"secname": section, "group": group, "code_data": [], "type": util.DATA_TYPES.SECTION, "offset": None, "size": 0})

					elif chunk["type"] == util.DATA_TYPES.ORG:
						# org
						offs = -1
						if cind+1 < len(LINE):
							offs = LINE[cind+1]

						if offs["type"] == util.DATA_TYPES.EXPRESSION:
							# temporary variable to be evaluated later. its easier this way
							varname = TEMP_LEFT + "TEMPVAR" + str(tempvar) + TEMP_RIGHT
							localvars.append({"name": varname, "value": "( " + offs["expression"] + " )", "offset": None, "section": getsecind(sec_ind + 1), "type": util.DATA_TYPES.EXPRESSION, "expression": offs["expression"], "expression_vars": offs["expression_vars"], "is_temp": True})
							if not varname in var_uses:
								var_uses[varname] = []
							var_uses[varname].append(LINE_OBJ.get_line_num())
							#ALL_USED_VARS.add(varname)
							#print("TYPE_X: " + varname)
							offs = {"type": util.DATA_TYPES.VARIABLE, "varname": varname, "label": varname, "size": 0, "uses_near": offs["uses_near"]}

							tempvar += 1

						cind += 1

						sections.append({"secname": section, "group": section, "code_data": [], "type": util.DATA_TYPES.ORG, "offset": offs, "size": 0})


						#LINE = LINE[:cind-1] + LINE[cind:]

						#cind -= 1




					if chunk["type"] == util.DATA_TYPES.SECTION:
						sect_class = chunk["SECTION_CLASS"]

						if not (sect_class in ORGANIZATION_TAGS):
							ORGANIZATION_TAGS.append(sect_class)
						
						if not (section in ORGANIZATION_TAGS):
							ORGANIZATION_TAGS.append(section)

					sec_ind += 1 

					#print(section, section_offsets[section])


				elif chunk["type"] == util.DATA_TYPES.GROUP:

					group = LINE[cind-1]["varname"]

					if not group in groups:
						groups.append(group)

					secname = chunk["SECTION_GROUP"]

					if not (section in ORGANIZATION_TAGS):
						ORGANIZATION_TAGS.append(secname)

					group_sections[secname] = group



				elif chunk["type"] == util.DATA_TYPES.EXPRESSION:

					#print("NON-EQU EXPRESSION BEFOR:", LINE)

					# temporary variable to be evaluated later. its easier this way
					varname = TEMP_LEFT + "TEMPVAR" + str(tempvar) + TEMP_RIGHT
					localvars.append({"name": varname, "value": "( " + chunk["expression"] + " )", "offset": None, "section": getsecind(sec_ind), "type": util.DATA_TYPES.EXPRESSION, "expression": chunk["expression"], "expression_vars": chunk["expression_vars"], "is_temp": True})
					if not varname in var_uses:
						var_uses[varname] = []
					var_uses[varname].append(LINE_OBJ.get_line_num())
					#ALL_USED_VARS.add(varname)
					#print("TYPE_X: " + varname)
					LINE[cind] = {"type": util.DATA_TYPES.VARIABLE, "varname": varname, "label": varname, "size": 0, "uses_near": chunk["uses_near"]}


					
					if LINE[cind-1]["type"] != util.DATA_TYPES.TYPE and LINE[cind-1]["type"] != util.DATA_TYPES.EQU:
						#LINE.insert(cind-1, {"type": util.DATA_TYPES.TYPE, "valtype": "addr", "size": 2})
						LINE[cind]["size"] = 2
						
						if LINE[cind-1]["type"] == util.DATA_TYPES.OPCODE:
							if LINE[cind-1]["opcode"] in {"bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs"}:
								LINE[cind]["size"] = 1

						#cind += 1

					tempvar += 1

					#print("NON-EQU EXPRESSION AFTER:", LINE)
					#if chunk["uses_near"]:
					#	print("NON-EQU: USES NEAR: ", LINE[cind])
					


				elif chunk["type"] == util.DATA_TYPES.EQU:



					variable_name = chunk["varname"]

					if cind+1 < len(LINE):
						if LINE[cind+1]["type"] == util.DATA_TYPES.VALUE:
							value = LINE[cind+1]["value"]
							#print("TYPE_B: " + variable_name)
							localvars.append({"name": variable_name, "value": value, "offset": None, "section": getsecind(sec_ind), "type": "exact"})
							if not variable_name in var_uses:
								var_uses[variable_name] = []
							var_uses[variable_name].append(LINE_OBJ.get_line_num())
							#ALL_USED_VARS.add(variable_name)

						elif LINE[cind+1]["type"] == util.DATA_TYPES.EXPRESSION:

							varname = TEMP_LEFT + "TEMPVAR" + str(tempvar) + TEMP_RIGHT
							localvars.append({"name": varname, "value": "( " + LINE[cind+1]["expression"] + " )", "offset": None, "section": getsecind(sec_ind), "type": util.DATA_TYPES.EXPRESSION, "expression": LINE[cind+1]["expression"], "expression_vars": LINE[cind+1]["expression_vars"], "is_temp": True, "is_equ": True})
							if not varname in var_uses:
								var_uses[varname] = []
							var_uses[varname].append(LINE_OBJ.get_line_num())
							#ALL_USED_VARS.add(varname)
							#print("TYPE_XV: " + varname)
							#LINE[cind+1] = {"type": util.DATA_TYPES.VARIABLE, "varname": varname, "label": varname, "size": 0, "is_equ": True, "section": getsecind(sec_ind)}
							LINE[cind+1] = {"type": util.DATA_TYPES.VARIABLE, "varname": varname, "label": varname, "size": 0, "is_equ": True, "uses_near": LINE[cind+1]["uses_near"]}
							#print("TYPE_VX: " + variable_name)
							localvars.append({"name": variable_name, "value": varname, "label": varname, "type": util.DATA_TYPES.EXPRESSION, "offset": None, "section": getsecind(sec_ind), "expression": varname, "expression_vars": [varname], "is_equ": True})
							if not variable_name in var_uses:
								var_uses[variable_name] = []
							var_uses[variable_name].append(LINE_OBJ.get_line_num())
							#ALL_USED_VARS.add(variable_name)
							tempvar += 1

						elif LINE[cind+1]["type"] == util.DATA_TYPES.VARIABLE:
							try:
								if not (LINE[cind+1]["varname"] in ORGANIZATION_TAGS):
									#print("TYPE_V: " + variable_name)
									localvars.append({"name": variable_name, "value": "( " + LINE[cind+1]["varname"] + " )", "offset": None, "section": getsecind(sec_ind), "type": util.DATA_TYPES.EXPRESSION, "expression": LINE[cind+1]["varname"], "expression_vars": [LINE[cind+1]["varname"]], "is_equ": True})
									if not variable_name in var_uses:
										var_uses[variable_name] = []
									var_uses[variable_name].append(LINE_OBJ.get_line_num())
									#ALL_USED_VARS.add(variable_name)
							except:
								pass
					else:
						#raise LineException(LINE_OBJ.get_line_num(), "Unexpected end of EQU, " + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
						raise LineError(LINE_OBJ, "Unexpected end of EQU.")



					#if FILE_NAME.split(".")[0].lower() == "pause":
					#	print(LINE)


				elif chunk["type"] == util.DATA_TYPES.STORAGE_DIRECTIVE:

					variable_name = chunk["varname"]

					if cind+1 < len(LINE):
						if LINE[cind+1]["type"] == util.DATA_TYPES.VALUE:
							STORAGE_LABELS.add(variable_name)
							value = LINE[cind+1]["value"]
							
							SD_TABLE = [{"type": util.DATA_TYPES.LABEL, "label": variable_name, "varname": variable_name, "is_near": False, "size": 0}, {"type": util.DATA_TYPES.DBYTE, "size": 0}]

							for x in range(value):
								if x != 0: SD_TABLE.append({"type": util.DATA_TYPES.SEPARATOR, "size": 0})
								SD_TABLE.append({"type": util.DATA_TYPES.VALUE, "value": 0})



							LINE = LINE[:cind] + SD_TABLE + LINE[cind+2:]

							#if FILE_NAME.split(".")[0].lower() == "result":
							#	print(section_storage[section], section, LINE)



							#LINE[cind]["storage_size"] = value
							#LINE = LINE[:cind+1] + LINE[cind+2:]

							cind -= 1

						else:
							#raise LineException(LINE_OBJ.get_line_num(), "Storage directive size must be a constant integer." + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
							raise LineError(LINE_OBJ, "Storage directive size must be a constant integer.")

					else:
						#raise LineException(LINE_OBJ.get_line_num(), "Size of storage directive not specified: " + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
						raise LineError(LINE_OBJ, "Size of storage directive not specified.")

				elif chunk["type"] == util.DATA_TYPES.OPCODE:

					op = chunk["opcode"].lower()

					if op in {"jmp", "jml", "jsr"}:
						if LINE[cind+1]["type"] in {util.DATA_TYPES.INDIRECT_START, util.DATA_TYPES.INDIRECT_LONG_START}:

							if LINE[cind+2]["type"] != util.DATA_TYPES.TYPE:
								LINE[cind+2]["size"] = 2


					elif op in {"adc", "and", "cmp", "eor", "lda", "ora", "sbc", "sta"}:
						try:
							if LINE[cind+1]["type"] == util.DATA_TYPES.INDIRECT_LONG_START:
								if LINE[cind+3]["type"] == util.DATA_TYPES.INDIRECT_LONG_END:
									LINE[cind+2]["size"] = 1

							elif LINE[cind+1]["type"] == util.DATA_TYPES.INDIRECT_START:
								if LINE[cind+3]["type"] == util.DATA_TYPES.INDIRECT_END:
									LINE[cind+2]["size"] = 1
								elif LINE[cind+2]["type"] != util.DATA_TYPES.TYPE:
									xind = cind+1
									while xind < len(LINE):
										if LINE[xind]["type"] == util.DATA_TYPES.SEPARATOR: break
										xind += 1

									if xind < len(LINE):
										if LINE[xind+1]["type"] == util.DATA_TYPES.REGISTER and LINE[xind+2]["type"] == util.DATA_TYPES.INDIRECT_END:
											LINE[cind+2]["size"] = 1

						except:
							pass


				elif chunk["type"] == util.DATA_TYPES.VARIABLE:   # FOR DEBUGGING
					if "is_external_label" in chunk:
						if chunk["is_external_label"]:
							#print(str(LINE))
							pass

					if not (LINE_OBJ.get_is_hidden() and not LINE_OBJ.get_force_lis()):
						ALL_USED_VARS.add(chunk["varname"])



						


				cind += 1

			




			if LINE != []:
				if LINE[0]["type"] in {util.DATA_TYPES.LABEL, util.DATA_TYPES.OPCODE, util.DATA_TYPES.DBYTE, util.DATA_TYPES.DWORD, util.DATA_TYPES.DLONG, util.DATA_TYPES.DATA_BANK, util.DATA_TYPES.DATA_PAGE, util.DATA_TYPES.PFLAG}: 
					# code line
					LINE_LEN = len(LINE)

					LINE_OBJ.set_is_code()
					'''
					for cind in range(len(LINE)):
						if
					''' 
					if LINE[0]["type"] in {util.DATA_TYPES.DATA_BANK, util.DATA_TYPES.DATA_PAGE, util.DATA_TYPES.PFLAG}:
						LINE_OBJ.set_is_not_code()

					#LINE_OBJ.set_parsed(LINE)
					LINE_OBJ.set_offset(section_offsets[section])
					sections[-1]["code_data"].append(LINE_OBJ)

					if LINE[0]["type"] == util.DATA_TYPES.LABEL:
						is_label = True
						if LINE_LEN > 1:
							if LINE[1]["type"] in {util.DATA_TYPES.SECTION, util.DATA_TYPES.GROUP, util.DATA_TYPES.ORG}:
								is_label = False
						if is_label:
							#print("TYPE_L: " + LINE[0]["label"])
							localvars.append({"name": LINE[0]["label"], "value": None, "offset": section_offsets[section], "section": getsecind(sec_ind), "type": "label", "is_external": False, "is_near": LINE[0]["is_near"]})
							if not LINE[0]["label"] in var_uses:
								var_uses[LINE[0]["label"]] = []
							var_uses[LINE[0]["label"]].append(LINE_OBJ.get_line_num())

					# format data in tables as correct size
					IND = 0
					
					while IND < LINE_LEN:

						#if "is_external_label" in LINE[IND] and LINE[IND]["is_external_label"]:
						#	print(LINE)


						if LINE[IND]["type"] in {util.DATA_TYPES.DBYTE, util.DATA_TYPES.DWORD, util.DATA_TYPES.DLONG}:

							'''
							data_chunks = []
							curr_chunk = []
							for cind in range(IND + 1, len(LINE)):
								if LINE[cind]["type"] == util.DATA_TYPES.SEPARATOR:
									data_chunks.append(curr_chunk)
									curr_chunk = []
								else:
									curr_chunk.append(LINE[cind])

							data_chunks.append(curr_chunk)

							LINE = LINE[:IND+1]


							first_chunk = True
							for chunk in data_chunks:

								chunk_ind = 0
								check_ind = 0

								if chunk == []:
									raise LineException(LINE_OBJ.get_line_num(), "Improper format for data table.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())

								if first_chunk: first_chunk = False
								else: LINE.append({"type": util.DATA_TYPES.SEPARATOR, "size": 0})

								while not (chunk[chunk_ind]["type"] in {util.DATA_TYPES.VALUE, util.DATA_TYPES.EXPRESSION, util.DATA_TYPES.VARIABLE}):
									LINE.append(chunk[chunk_ind])
									chunk_ind += 1
									check_ind += 1

								LINE.append(chunk[chunk_ind])
								check_ind += 1

								if "is_external_label" in chunk[chunk_ind] and chunk[chunk_ind]["is_external_label"]:
									if len(chunk) > 1:
										LINE.append(chunk[chunk_ind + 1])
										check_ind += 1
									else:
										raise LineException(LINE_OBJ.get_line_num(), "External offset malfunction in data table.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())

								if check_ind < len(chunk):
									break

							'''
							#LINE_LEN = len(LINE)

							was_sep = True
							was_type = False
							x_ind = IND+1
							while x_ind < LINE_LEN:
								tp = LINE[x_ind]["type"]
								if was_sep:
									if tp == util.DATA_TYPES.SEPARATOR: 
										#raise LineException(LINE_OBJ.get_line_num(), "Improper format for data table.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
										raise LineError(LINE_OBJ, "Improper format for data table.")

									elif tp in {util.DATA_TYPES.VALUE, util.DATA_TYPES.EXPRESSION, util.DATA_TYPES.VARIABLE}:
										was_sep = False

										if "is_external_label" in LINE[x_ind] and LINE[x_ind]["is_external_label"]:
											x_ind += 1
											if LINE[x_ind]["type"] == util.DATA_TYPES.SEPARATOR:
												#raise LineException(LINE_OBJ.get_line_num(), "External offset malfunction in data table.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
												raise LineError(LINE_OBJ, "External offset malfunction in data table.")

									elif tp == util.DATA_TYPES.TYPE:
										was_sep = False
										was_type = True
										if not LINE[x_ind+1]["type"] in {util.DATA_TYPES.VALUE, util.DATA_TYPES.EXPRESSION, util.DATA_TYPES.VARIABLE}:
											#raise LineException(LINE_OBJ.get_line_num(), "Improper format for data table.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
											raise LineError(LINE_OBJ, "Improper format for data table.")
										x_ind -= 1
											
									else:
										#raise LineException(LINE_OBJ.get_line_num(), "Improper format for data table.\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
										raise LineError(LINE_OBJ, "Improper format for data table.")
								
								elif was_type:
									was_sep = True

								else:
									# previous wasnt separator
									
									if LINE[x_ind]["type"] != util.DATA_TYPES.SEPARATOR: break
									was_sep = True

								x_ind += 1

							if x_ind != LINE_LEN:
								LINE = LINE[:x_ind]
								LINE_LEN = x_ind

							




							for cind in range(IND + 1, LINE_LEN):

								if LINE[cind]["type"] in {util.DATA_TYPES.VALUE, util.DATA_TYPES.EXPRESSION, util.DATA_TYPES.VARIABLE}:


									if LINE[IND]["type"] == util.DATA_TYPES.DBYTE:
										LINE[cind]["size"] = 1
									elif LINE[IND]["type"] == util.DATA_TYPES.DWORD:
										LINE[cind]["size"] = 2
									elif LINE[IND]["type"] == util.DATA_TYPES.DLONG:
										LINE[cind]["size"] = 3

								elif not (LINE[cind]["type"] in {util.DATA_TYPES.SEPARATOR, util.DATA_TYPES.TYPE}):
									#raise LineException(LINE_OBJ.get_line_num(), "invalid data in data table", LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "Invalid data in data table.")

							break

						IND += 1


					is_move = False
					is_op = False
					op = None
					ORG = False
					for cind in range(LINE_LEN):
						chunk = LINE[cind]

						if chunk["type"] == util.DATA_TYPES.OPCODE:
							is_op = True
							op = chunk["opcode"].lower()

						elif chunk["type"] == util.DATA_TYPES.PFLAG:
							# processor flag

							basic_flag = True

							if chunk["flag"].lower() == "mem8":
								#print("mem8")
								mem = 8
							elif chunk["flag"].lower() == "mem16":
								#print("mem16")
								mem = 16
							elif chunk["flag"].lower() == "idx8":
								#print("idx8")
								idx = 8
							elif chunk["flag"].lower() == "idx16":
								#print("idx16")
								idx = 16
							else:
								basic_flag = False

							if basic_flag:
								processor_flags.append({"type": chunk["flag"].lower(), "offset": section_offsets[section], "section": getsecind(sec_ind)})
							
							else:

								
								if chunk["flag"].lower() == "emulation":
									mem = 8
									idx = 8
									processor_flags.append({"type": "mem8", "offset": section_offsets[section], "section": getsecind(sec_ind)})
									processor_flags.append({"type": "idx8", "offset": section_offsets[section], "section": getsecind(sec_ind)})

								if chunk["flag"].lower() == "native":
									# don't do anything really...
									pass

						elif chunk["type"] == util.DATA_TYPES.VALUE:
							if is_op:
								if cind > 0:
									if LINE[cind-1]["type"] != util.DATA_TYPES.TYPE:
										LINE[cind]["size"] = 2

										if LINE[cind-1]["type"] == util.DATA_TYPES.OPCODE:
											if LINE[cind-1]["opcode"].lower() in {"cop", "rep", "sep", "brk", "wdm"}:
												LINE[cind]["size"] = 1


										if cind+1 < LINE_LEN:
											if LINE[cind+1]["type"] == util.DATA_TYPES.SEPARATOR:
												if cind+2 < LINE_LEN:
													if LINE[cind+2]["type"] == util.DATA_TYPES.REGISTER:
														if LINE[cind+2]["register"] == "s":
															LINE[cind]["size"] = 1

						chunk = LINE[cind]

						#if LINE_OBJ.get_line_num() == 392:
						#	print(LINE)



						if chunk["size"] != None:
							if chunk["type"] == util.DATA_TYPES.VARIABLE:
								if chunk["varname"].lower() in ORGANIZATION_TAGS:	# change to "if not in rel group names"
									LINE[cind]["size"] = 0
									chunk = LINE[cind]



								if cind > 0:
									if LINE[cind-1]["type"] in {util.DATA_TYPES.DATA_PAGE, util.DATA_TYPES.DATA_BANK, util.DATA_TYPES.ORG}:
										LINE[cind]["size"] = 0
										chunk = LINE[cind]
										#print("sizenone VAR:", LINE)

									#elif chunk["size"] == 0 and LINE_OBJ.is_op() and LINE[cind-1]["type"] != util.DATA_TYPES.TYPE:
									#	LINE[cind]["size"] = 2
									#	chunk = LINE[cind]
									elif LINE[cind-1]["type"] != util.DATA_TYPES.TYPE:
										
										if op in {"cop", "rep", "sep", "brk", "wdm"}:
											LINE[cind]["size"] = 1




								if "is_external_label" in chunk and chunk["is_external_label"]:
									if cind+1 < LINE_LEN:
										if LINE[cind+1]["type"] == util.DATA_TYPES.VARIABLE:
											LINE[cind+1]["size"] = 0

									if chunk["size"] == 0 and LINE_OBJ.is_op() and LINE[cind-1]["type"] != util.DATA_TYPES.TYPE:
										LINE[cind]["size"] = 2
										chunk = LINE[cind]

								


							elif chunk["type"] == util.DATA_TYPES.VALUE:
								if cind > 0 and LINE[cind-1]["type"] in {util.DATA_TYPES.DATA_PAGE, util.DATA_TYPES.DATA_BANK, util.DATA_TYPES.ORG}:
									LINE[cind]["size"] = 0
									chunk = LINE[cind]								
									#print("sizenone VAL:", LINE)



							elif chunk["type"] == util.DATA_TYPES.OPCODE:
								if chunk["opcode"].lower() in {"mvn", "mvp"}:
									is_move = True
									#print(LINE)

							elif chunk["type"] == util.DATA_TYPES.ORG:
								ORG = True


							chunk = LINE[cind]

							section_offsets[section] += chunk["size"]
							sec_len += chunk["size"]




						else:
							# base off of processor size

							
							if is_move:
								section_offsets[section] += 1
								LINE[cind]["size"] = 1
								sec_len += 1
								continue







							if "reg" in LINE[cind-1]:


								if LINE[cind-1]["reg"].lower() == "a":
									section_offsets[section] += mem//8
									LINE[cind]["size"] = mem//8
									sec_len += mem//8
								elif LINE[cind-1]["reg"].lower() == "x" or LINE[cind-1]["reg"].lower() == "y":
									section_offsets[section] += idx//8
									LINE[cind]["size"] = idx//8
									sec_len += idx//8
								elif LINE[cind-1]["reg"].lower() == "p":
									section_offsets[section] += 1
									LINE[cind]["size"] = 1
									sec_len += 1
								elif LINE[cind-1]["reg"].lower() == "s":
									section_offsets[section] += 2
									LINE[cind]["size"] = 2
									sec_len += 2

								else:
									#raise LineException(LINE_OBJ.get_line_num(), "Error with offset counting..." + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "Error with offset counting...")
							else:
								if LINE[cind]["type"] == util.DATA_TYPES.TYPE:
									if LINE[cind]["valtype"] == "bank":
										LINE[cind]["size"] = 1
									elif LINE[cind]["valtype"] == "offset":
										LINE[cind]["size"] = 2
									elif LINE[cind]["valtype"] == "high":
										LINE[cind]["size"] = 1
									elif LINE[cind]["valtype"] == "low":
										LINE[cind]["size"] = 1



				else:



					if LINE[0]["type"] == util.DATA_TYPES.PFLAG:
						# processor flag
						'''
						if LINE[0]["flag"].lower() == "mem8":
							mem = 8
						elif LINE[0]["flag"].lower() == "mem16":
							mem = 16
						elif LINE[0]["flag"].lower() == "idx8":
							idx = 8
						elif LINE[0]["flag"].lower() == "idx16":
							idx = 16

						processor_flags.append({"type": LINE[0]["flag"].lower(), "offset": section_offsets[section], "section": getsecind(sec_ind)})
						'''

					elif LINE[0]["type"] == util.DATA_TYPES.DATA_BANK:
						pass

					elif LINE[0]["type"] == util.DATA_TYPES.DATA_PAGE:
						LINE[cind]["size"] = 0
						LINE[cind + 1]["size"] = 0
						pass


					if LINE_OBJ.get_force_lis():
						LINE_OBJ.set_parsed(LINE)
						LINE_OBJ.set_offset(section_offsets[section])
						sections[-1]["code_data"].append(LINE_OBJ)




			LINE_OBJ.set_parsed(LINE)
			# TO DO: data bank + page fixing


		sections[-1]["size"] = sec_len



		sections.insert(2, {"secname": "D" + FILE_NAME.split(".")[0], "group": "DATA", "code_data": [], "type": util.DATA_TYPES.SECTION, "offset": None, "size": 0})


		for s in range(len(sections)):
			secname = sections[s]["secname"]
			if secname in group_sections:
				sections[s]["group"] = group_sections[secname]


		#for s in sections:
		#	print("SECTION NAME -", s["secname"], "  GROUP NAME -", s["group"])

		if TIMING_DEBUG: print("  formatting time: ", format(util.get_time()-start, " 10.5f"))

		#for s in sections:
		#	print(s["secname"])



		###############################################################################################

		###############################################################################################


		start = util.get_time()
		# step 4: expression evaluation for variables
		

		# ensure that all external vars are handled as such
		for vind in range(len(localvars)):
			var = localvars[vind]

			if not "is_external" in localvars[vind]:
				localvars[vind]["is_external"] = False

			if var["name"] in EXTERNALVARS_SET:
				localvars[vind]["is_external"] = True
			

			var = localvars[vind]

			if var["is_external"]:


				if not var["name"] in EXTERNALVARS_SET: localvars[vind]["name"] = "   "

			

			if not ("is_equ" in localvars[vind]):
				localvars[vind]["is_equ"] = False


		if TIMING_DEBUG: print("  external check time: ", format(util.get_time()-start, " 10.5f"))






		
		start = util.get_time()
		# evaluate expressions in variables

		# MAKE THIS WAY FASTER PLEASE!!!!!!!!!!!
		# Possibly do a tree structure so this doesn't take O(M N^2) time, dingus.


		EXP_DICT = {}

		EXPS = []


		var_dict = {}

		for vind in range(1, len(localvars)):
			v_name = localvars[vind]["name"]
			if v_name in var_dict:
				raise LineException(-1, "Multiple instances of variable \"" + str(v_name) + "\"")
			var_dict[v_name] = vind

			var = localvars[vind]

			if not ("is_temp" in var):
				localvars[vind]["is_temp"] = False


			if var["type"] == util.DATA_TYPES.EXPRESSION:

				if not "is_label_expression" in localvars[vind]:
					localvars[vind]["is_label_expression"] = False

				if not "is_label_relative" in localvars[vind]:
					localvars[vind]["is_label_relative"] = False

				EXP_DICT[var["name"]] = var["expression_vars"]






		num_exps = 0
		for e in EXP_DICT:
			#print((e, EXP_DICT[e], localvars[var_dict[e]]["expression"]))
			EXPS.append((e, EXP_DICT[e]))
			num_exps = num_exps + 1



		p_num_exps = num_exps
		while num_exps > 0:

			i = 0

			while i < num_exps:
				try:

					vd = var_dict[EXPS[i][0]]

					EXP = localvars[vd]


					#var_type = "exact"
					#var_is_equ = False
					#var_section = ""

					is_evaluable = True

					

					for name in EXP["expression_vars"]:
						nd = var_dict[name]
						

						if localvars[nd]["type"] == util.DATA_TYPES.EXPRESSION:
							is_evaluable = False

					


					if is_evaluable:

						#is_mult = False
						#if len(EXP["expression_vars"]) > 1:
						#	is_mult = True
						#	print(EXP["expression_vars"])


						j = len(EXP["expression_vars"]) - 1
						while j > -1:

							name = EXP["expression_vars"][j]
							nd = var_dict[name]

							var = localvars[nd]



							if var["type"] == "exact":
								val = var["value"]
							elif var["type"] == "label":
								val = var["offset"] + 0x99000000


							EXP["expression_vars"].remove(name)
							# remove name from expression pool
							EXP["expression"] = (" " + EXP["expression"] + " ").replace(" " + name + " ", " " + str(val) + " ").lstrip().rstrip()

							localvars[vd]["expression_vars"] = EXP["expression_vars"]
							localvars[vd]["expression"] = EXP["expression"]



							if var["type"] == "label":
								if localvars[vd]["is_label_expression"]:
									localvars[vd]["is_label_relative"] = False
								else:
									localvars[vd]["is_label_relative"] = True
								localvars[vd]["is_label_expression"] = True

								localvars[vd]["section"] = var["section"]


							j -= 1



						#if is_mult:
						#	print(localvars[vd]["expression"], localvars[vd]["expression_vars"])






						#	if len(localvars[vd]["expression_vars"]) == 0:
						try:


							VAR_TYPE = "label"
							#if var_type == "label":
							#	VAR_TYPE = "label"

							#if var_is_equ:
							#	VAR_TYPE = "exact"


							if not localvars[vd]["is_label_relative"]:
								VAR_TYPE = "exact"

							


							VAL = util.evaluateExpression(localvars[vd]["expression"])                                  #  this if vind doesnt work for some stupid reason
							if -0x98000000 < VAL and VAL < 0x98000000:
								VAR_TYPE = "exact"

							if VAL >= 0x98000000 or VAL <= -0x98000000:
								VAR_TYPE = "label"

							while VAL >= 0x99000000:
								VAL -= 0x99000000

							while VAL <= -0x99000000:
								VAL += 0x99000000



							#localvars[ind] = {"name": localvars[ind]["name"], "value": VAL, "offset": VAL, "section": localvars[ind]["section"], "type": VAR_TYPE, "is_temp": localvars[ind]["is_temp"], "is_external": localvars[ind]["is_external"], "is_equ": localvars[ind]["is_equ"]}
							localvars[vd] = {"name": localvars[vd]["name"], "value": VAL, "offset": VAL, "section": localvars[vd]["section"], "type": VAR_TYPE, "is_temp": localvars[vd]["is_temp"], "is_external": localvars[vd]["is_external"], "is_equ": localvars[vd]["is_equ"]}


							#if FILE_NAME.split(".")[0].lower() == "pause":
							#	print(str(localvars[ind]))

							num_exps -= 1

							EXPS.pop(i)
							i -= 1
						except Exception as e:
							raise Exception("Error during parsing of " + localvars[vd]["name"] + " : " + localvars[vd]["expression"] + ", \n" + traceback.format_exc())
					

					i += 1
				except Exception as e:
					v = localvars[vd]["name"]


					raise Exception("Error during parsing of " + localvars[vd]["name"] + " : " + localvars[vd]["expression"] + ", \nPossible causes of error:\n" + "\n".join([str(x) for x in var_uses[v]]) + "\n" + traceback.format_exc())


			if num_exps == p_num_exps:
				break

			p_num_exps = num_exps

		#if FILE_NAME.lower() == "bgmove.asm":
		#	print(localvars[var_dict["<TEMPVAR73>"]])

		if TIMING_DEBUG: print("  expression parsing time: ", format(util.get_time()-start, " 10.5f"))
			




				









		

		start = util.get_time()

		# check to see if all expressions evaluated
		for var in localvars[1:]:
			if var["type"] in ("expression"):
				raise Exception("Variable " + var["name"] + " is not evaluateable.   " + var["expression"] + "   vars: " + ", ".join(var["expression_vars"]))

			'''
			if var["type"] == "exact":
				#print(var["name"], var["value"])
				pass
			elif var["type"] == "label":
				#print(var["name"], var["offset"])
				pass
			'''

			#if FILE_NAME.split(".")[0].lower() == "pause":
			#	print(str(var))


		# ensure that "is_external" is set for all variables
		ext_dict = {}
		for var in externalvars:
			ext_dict[var] = 0
			# dict access is way faster

		for vind in range(len(localvars)):
			var = localvars[vind]
			if not "is_external" in localvars[vind]:
				localvars[vind]["is_external"] = False

			if var["name"] in ext_dict:
				localvars[vind]["is_external"] = True


			var = localvars[vind]


			if var["is_external"]:

				if not var["name"] in ext_dict:
					localvars[vind]["name"] = "   "


		if TIMING_DEBUG: print("  variable check time: ", format(util.get_time()-start, " 10.5f"))




		###############################################################################################

		###############################################################################################



		start = util.get_time()

		# step 5: gather all "near" variables, and convert branch instructions to near labels
		for ind in range(len(localvars)):

			if ind > 0:
				var = localvars[ind]

				if var["name"][-1] == "$":
					# if "near" variable

					localvars[ind]["is_temp"] = True

				var = localvars[ind]

				if not var["is_external"]:
					if var["type"] == "label":
						
						sec_ind = var["section"]

						section = sections[sec_ind]["secname"]
						'''
						off = 0

						for s in range(1, sec_ind):
							if sections[s]["secname"] == section:
								off += sections[s]["size"]

						'''

						#print(var)


					
						localvars[ind] = {"name": var["name"], "type": "label", "value": None, "offset": var["offset"], "section": section, "is_temp": var["is_temp"], "is_external": False}


			vind = ind
			if not ("is_near" in localvars[vind]):
				localvars[vind]["is_near"] = False

			if not ("is_equ" in localvars[vind]):
				localvars[vind]["is_equ"] = False


			if localvars[vind]["is_equ"]:
				#print(str(localvars[vind]))
				if localvars[vind]["type"] == "label":
					localvars[vind]["type"] = "exact"
					localvars[vind]["value"] = localvars[vind]["offset"]




		if TIMING_DEBUG: print("  near var time: ", format(util.get_time()-start, " 10.5f"))



		start = util.get_time()

		# convert variables in code into variable values
		
		FILE_TAG = "~FILE_" + str(FILE_NAME) + "~"
		FILE_TAG_LEN = len(FILE_TAG)

		NEW_IND = len(localvars)

		for sec_ind in range(1, len(sections)):

			sec = sections[sec_ind]


			# set org offset
			if sec["type"] == util.DATA_TYPES.ORG:
				offs = sec["offset"]

				

				if offs == -1:
					raise Exception("Org section has no offset...")

				if offs["type"] == util.DATA_TYPES.VARIABLE:
					
					if not offs["varname"] in var_dict:
						raise Exception("org section offset variable not found: " + str(offs["varname"]))

					var = localvars[var_dict[offs["varname"]]]

					val = None
					if var["type"] == "label":
						val = var["offset"]
					elif var["type"] == "exact":
						val = var["value"]

					offs = {"type": util.DATA_TYPES.VALUE, "value": val}


				sections[sec_ind]["offset"] = offs["value"]

				






			lnum = 0
			for LINE_OBJ in sec["code_data"]:

				LINE = LINE_OBJ.get_parsed()

				if LINE_OBJ.get_is_macro():
					continue

				if LINE_OBJ.get_force_lis() and LINE_OBJ.get_is_equ():
					lnum += 1
					continue



				for ind in range(len(LINE)):
					chunk = LINE[ind]


					#if chunk["type"] == util.DATA_TYPES.VARIABLE and chunk["varname"] in LOCAL_EXTERNAL:
					#	chunk["is_external_label"] = True



					if chunk["type"] == util.DATA_TYPES.VARIABLE and ((not ("is_external_label" in chunk)) or chunk["is_external_label"] == False):

						if not ("vartype" in chunk):
							chunk["vartype"] = util.DATA_TYPES.NORMALVAR

						do_near = False

						if LINE_OBJ.is_op() and LINE[LINE_OBJ.get_op_ind()]["opcode"] in {"bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs", "brl", "per"}:
							do_near = True

						else:

							if chunk["vartype"] == util.DATA_TYPES.NORMALVAR: do_near = False

						#if "uses_near" in chunk and chunk["uses_near"]: 
						#	print("USES NEAR: ", LINE)


						


						if not do_near:
							# if actual label, and not near label

							if ind != 0:
								fnd = False
								v = None
								#print("\n\n\n")
								if chunk["varname"] in var_dict: 
									fnd = True
									v = localvars[var_dict[chunk["varname"]]]

								if not fnd:

									if chunk["varname"] in ext_dict: fnd = True
									

									if not fnd:
										#raise LineException(LINE_OBJ.get_line_num(), "Could not find variable \"" + str(chunk["varname"]) + "\"", LINE_OBJ.get_file_name())
										raise LineError(LINE_OBJ, "Could not find variable \"" + str(chunk["varname"]) + "\"")

									LINE[ind] = {"type": util.DATA_TYPES.EXTERNAL, "varname": chunk["varname"], "label": chunk["varname"]}

								else:
									try:
										if v["is_external"]:
											LINE[ind] = {"type": util.DATA_TYPES.EXTERNAL, "varname": chunk["varname"], "label": chunk["varname"]}
										else:

											if v["type"] == "exact":
												if not v["name"].lower() in ORGANIZATION_TAGS:	# change to "if not in rel group names"
													LINE[ind] = {"type": util.DATA_TYPES.VALUE, "value": v["value"]}



											elif v["type"] == "label":
												if v["name"] in LOCAL_EXTERNAL:
													v_name = v["name"]

													
													LOCEXT_TAG = FILE_TAG

													#if len(v_name) >= FILE_TAG_LEN and v_name[:FILE_TAG_LEN] == FILE_TAG:
													#	print("[ WARNING!!!! ] LOCEXT IS ABOUT TO MESS UP HERE! at line", LINE_OBJ.get_line_num(), ":\n", LINE_OBJ.get_raw(), "\nwith variable: ", v_name)


													NEW_NAME = LOCEXT_TAG + chunk["varname"]

													LINE[ind] = {"type": util.DATA_TYPES.EXTERNAL, "varname": NEW_NAME, "label": NEW_NAME}

													new_v = {}
													for key in v:
														new_v[key] = v[key]

													new_v["name"] = NEW_NAME

													LOCAL_EXTERNAL.add(NEW_NAME)
													localvars.append(new_v)
													var_dict[NEW_NAME] = NEW_IND
													NEW_IND += 1




												else:
													LINE[ind] = {"type": util.DATA_TYPES.VARIABLE, "varname": v["name"], "label": v["name"], "section": v["section"], "offset": v["offset"]}
									
									except Exception as e:
										print(v)
										raise e


								if LINE[ind-1]["type"] != util.DATA_TYPES.TYPE:
									LINE[ind]["size"] = 2


						else:
							# if near label


							if ind != 0:

								

								'''
								if LINE_OBJ.is_op(): 
									op = None
									for ind2 in range(ind):
										if LINE[ind2]["type"] == util.DATA_TYPES.OPCODE:
											op = LINE[ind2]["opcode"]
									if op != None:
										if op in {"bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs", "brl", "per", "jsr"}:
											do_near = True
									#LINE[ind-1]["type"] == util.DATA_TYPES.OPCODE and LINE[ind-1]["opcode"] in ("bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs", "brl", "per", "jsr")
								'''
									

								if do_near:

									if chunk["vartype"] != util.DATA_TYPES.NORMALVAR:
										if not (chunk["varname"] in var_dict):
											#raise LineException(LINE_OBJ.get_line_num(), "No label \"" + str(chunk["varname"]) + "\" found to branch to.  " + str(format(LINE_OBJ.get_offset(), "04x")), LINE_OBJ.get_file_name())
											raise LineError(LINE_OBJ, "No label \"" + str(chunk["varname"]) + "\" found to branch to.  (offset: " + str(format(LINE_OBJ.get_offset(), "04x")) + ")")


									var = localvars[var_dict[chunk["varname"]]]


									if chunk["size"] == 1:
										# regular branch

										OFFS = var["offset"]

										
										if "uses_near" in chunk and chunk["uses_near"]: 
											OFFS += 2

											#print("BRANCH USES NEAR: ", LINE)
											#print("  VAR = ", localvars[var_dict[chunk["varname"]]])
											#print("  RAW = ", LINE_OBJ.get_raw())
										


										dist = OFFS - (LINE_OBJ.get_offset() + 2)

										if dist < -0x80 or dist > 0x7f:
											#raise LineException(LINE_OBJ.get_line_num(), "Label not near enough to branch from this instruction. LABEL = " + str(chunk["varname"]) + "\n" + str(LINE_OBJ.get_raw()) + "\n" + "Cannot branch distance of " + format(dist, "04x") + "h. Must be between [-80h, 7Fh].", LINE_OBJ.get_file_name())
											raise LineError(LINE_OBJ, "Label not near enough to branch from this instruction. LABEL = " + str(chunk["varname"]) + "\n" + "Cannot branch distance of " + format(dist, "04x") + "h. Must be between [-80h, 7Fh].")
										

										LINE[ind] = {"type": util.DATA_TYPES.VALUE, "value": dist, "size": 1}


									elif chunk["size"] == 2:
										# brl and per

										OFFS = var["offset"]

										
										if "uses_near" in chunk and chunk["uses_near"]: 
											OFFS += 3
										

										dist = OFFS - (LINE_OBJ.get_offset() + 3)
										
										if dist < -0x8000 or dist > 0x7fff:
											#raise LineException(LINE_OBJ.get_line_num(), "Label not near enough to branch from this instruction. LABEL = " + str(chunk["varname"]) + "\n" + str(LINE_OBJ.get_raw()) + "\n" + "Cannot branch distance of " + format(dist, "04x") + "h. Must be between [-8000h, 7FFFh].", LINE_OBJ.get_file_name())
											raise LineError(LINE_OBJ, "Label not near enough to branch from this instruction. LABEL = " + str(chunk["varname"]) + "\n" + "Cannot branch distance of " + format(dist, "04x") + "h. Must be between [-8000h, 7FFFh].")

										LINE[ind] = {"type": util.DATA_TYPES.VALUE, "value": dist, "size": 2}

										


								else:
									fnd = False
									v = None
									demi_v = None

									c_dist = 0xffffff
									demi_dist = 0xffffff


									print_debug = False
									print_size = "04x"

									debug_files = ("")

									#raise LineException(LINE_OBJ.get_line_num(), "THIS WAS UNDERSTOOD WRONG. FIX THIS!!! ('NEAR VAR' ISSUE)\n" + str(LINE_OBJ.get_raw()), LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "UNSPECIFIED 'NEAR VAR' ISSUE (error code n001)")
									








				sections[sec_ind]["code_data"][lnum].set_parsed(LINE)

				lnum += 1

		if TIMING_DEBUG: print("  variable parsing time: ", format(util.get_time()-start, " 10.5f"))


		start = util.get_time()

		# set external variables to have correct tags, external labels have correct offset
		for sec_ind in range(1, len(sections)):

			sec = sections[sec_ind]

			lnum = 0
			for LINE_OBJ in sec["code_data"]:

				LINE = LINE_OBJ.get_parsed()

				if LINE_OBJ.get_is_macro():
					continue

				if LINE_OBJ.get_force_lis() and LINE_OBJ.get_is_equ():
					continue


				ind = 0
				while ind < len(LINE):

					if LINE[ind]["type"] == util.DATA_TYPES.VARIABLE:

						if not "external_offset" in LINE[ind]:
							LINE[ind]["external_offset"] = 0


						if ("is_external_label" in LINE[ind]) and LINE[ind]["is_external_label"]:

							if not "external_offset" in LINE[ind]:
								LINE[ind]["external_offset"] = 0


							if ind+1 < len(LINE):

								if LINE[ind+1]["type"] == util.DATA_TYPES.VALUE:
									VAL = LINE[ind+1]["value"]

									if "negative_offset" in LINE[ind] and LINE[ind]["negative_offset"]: VAL = VAL * -1

									LINE[ind]["external_offset"] = VAL
									LINE[ind]["type"] = util.DATA_TYPES.EXTERNAL

									# parse rest of line
									LINE = LINE[:ind+1] + LINE[ind+2:]

								else:

									#raise LineException(LINE_OBJ.get_line_num(), "Error parsing external label offset...:\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "Error parsing external label offset...")




					ind += 1


				LINE_OBJ.set_parsed(LINE)



		if TIMING_DEBUG: print("  external tag time: ", format(util.get_time()-start, " 10.5f"))


		start = util.get_time()

		# parse branch nearlabel labels as such
		for sec in sections[1:]:

			lnum = 0
			for LINE_OBJ in sec["code_data"]:

				LINE = LINE_OBJ.get_parsed()

				if LINE_OBJ.get_is_macro():
					continue

				if LINE_OBJ.get_force_lis() and LINE_OBJ.get_is_equ():
					continue

				for ind in range(len(LINE)):
					chunk = LINE[ind]

					if chunk["type"] == util.DATA_TYPES.OPCODE:
						op = chunk["opcode"].lower()

						if op in {"bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs", "brl", "per"}:
							if LINE[ind+1]["type"] == util.DATA_TYPES.VARIABLE:

								fnd = False
								v = None
								for var in localvars[1:]:
									if var["name"] == LINE[ind+1]["varname"]:
										fnd = True
										v = var

								if v["type"] == "label":
									LINE[ind+1] = {"type": util.DATA_TYPES.VALUE, "value": var["offset"] - (LINE_OBJ.get_offset() + 2), "size": 1}

									if op in {"brl", "per"}:
										LINE[ind+1]["size"] = 2
										LINE[ind+1]["value"] -= 1

							'''
							elif LINE[ind+1]["type"] == util.DATA_TYPES.VALUE:
								LINE[ind+1]["value"] -= 2

								if op in ("brl", "per"):
									LINE[ind+1]["value"] -= 1
							'''
				LINE_OBJ.set_parsed(LINE)

		if TIMING_DEBUG: print("  branch near time: ", format(util.get_time()-start, " 10.5f"))



		start = util.get_time()
		# convert data types into a parseable format
		'''
		sec_ind = 1
		for sec in sections[1:]:


			for LINE_OBJ in sec["code_data"]:
				LINE = LINE_OBJ.get_parsed()

				if LINE_OBJ.get_is_macro():
					continue

				try:
					ind = 0
					while ind < len(LINE):
						if LINE[ind]["type"] == util.DATA_TYPES.TYPE:
							LINE[ind]["value"] = LINE[ind+1]

							LINE = LINE[:ind+1] + LINE[ind+2:]

						ind += 1
				except Exception as e:
					raise LineException(LINE_OBJ.get_line_num(), "Error: \n" + str(e) + "\n" + str(LINE_OBJ.get_parsed()), LINE_OBJ.get_file_name())

				LINE_OBJ.set_parsed(LINE)
		'''


		#TODO: CHECK THAT THIS DIDN'T MESS ANYTHING UP

		sec_ind = 1
		for SEC_NUM in range(1, len(sections)):

			sec = sections[SEC_NUM]

			sec_l = 0
			CODE_DATA_LEN = len(sec["code_data"]) 
			while sec_l < CODE_DATA_LEN:
				LINE_OBJ = sec["code_data"][sec_l]
				LINE = LINE_OBJ.get_parsed()

				if LINE_OBJ.get_is_macro():
					sec_l += 1
					continue

				if LINE_OBJ.get_force_lis() and LINE_OBJ.get_is_equ():
					sec_l += 1
					continue



				is_byte_list = False
				is_word_list = False
				is_long_list = False

				try:

					ind = 0

					LINE_LEN = len(LINE)
					while ind < LINE_LEN:

						if LINE[ind]["type"] == util.DATA_TYPES.TYPE:
							if ind+1 >= LINE_LEN:
								#raise LineException(LINE_OBJ.get_line_num(), "Improper format for type: \n" + str(LINE_OBJ.get_raw()) + "\n", LINE_OBJ.get_file_name())
								raise LineError(LINE_OBJ, "Improper format for type.")


							if LINE[ind]["valtype"] == "dp": 
								LINE[ind]["real_dp"] = True

							LINE[ind]["value"] = LINE[ind+1]

							#LINE = LINE[:ind+1] + LINE[ind+2:]
							LINE.pop(ind+1)
							LINE_LEN -= 1

							LINE_OBJ.set_parsed(LINE)







						if LINE[ind]["type"] == util.DATA_TYPES.VALUE:

							if LINE[ind-1]["type"] == util.DATA_TYPES.INDIRECT_LONG_START:
								if ind+1 < len(LINE):
									if LINE[ind+1]["type"] == util.DATA_TYPES.INDIRECT_LONG_END:
										if ind-2 >= 0:
											if LINE[ind-2]["type"] == util.DATA_TYPES.OPCODE:
												if LINE[ind-2]["opcode"] in {"jmp", "jml", "jsr", }:
													LINE[ind]["size"] = 2
												else:
													LINE[ind]["size"] = 1

							
							valtype = "const"
							#valtype = "addr"
							size = LINE[ind]["size"]

							if LINE[ind]["size"] == 1:
								valtype = "dp"
							elif LINE[ind]["size"] == 2:
								valtype = "addr"
							elif LINE[ind]["size"] == 3:
								valtype = "long"
							elif LINE[ind]["size"] == 0:
								valtype = "const"

							if is_byte_list:
								valtype = "const"
								size = 1
							elif is_word_list:
								valtype = "const"
								size = 2
							elif is_long_list:
								valtype = "const"
								size = 3


							LINE[ind] = {"type": util.DATA_TYPES.TYPE, "valtype": valtype, "size": size, "value": LINE[ind]}


						elif LINE[ind]["type"] == util.DATA_TYPES.VARIABLE:



							if not LINE[ind]["varname"].lower() in ORGANIZATION_TAGS:	# change to "if not in rel group names"

								if LINE[ind]["offset"] != None:

									ctype = "const"
									#ctype = "addr"
									size = LINE[ind]["size"]

									if LINE[ind]["size"] == 1:
										ctype = "dp"
									elif LINE[ind]["size"] == 2:
										ctype = "addr"
									elif LINE[ind]["size"] == 3:
										ctype = "long"
									elif LINE[ind]["size"] == 0:
										ctype = "const"


									if is_byte_list:
										ctype = "const"
										size = 1
									elif is_word_list:
										ctype = "const"
										size = 2
									elif is_long_list:
										ctype = "const"
										size = 3


									LINE[ind] = {"type": util.DATA_TYPES.TYPE, "valtype": ctype, "size": size, "value": LINE[ind]}

								else:
									ctype = "const"
									size = LINE[ind]["size"]

									if is_byte_list:
										ctype = "const"
										size = 1
									elif is_word_list:
										ctype = "const"
										size = 2
									elif is_long_list:
										ctype = "const"
										size = 3
									LINE[ind] = {"type": util.DATA_TYPES.TYPE, "valtype": ctype, "size": size, "value": LINE[ind]}	

						elif LINE[ind]["type"] == util.DATA_TYPES.EXTERNAL:
							size = 2
							valtype = "addr"

							if is_byte_list: 
								size = 1
								valtype = "dp"
							elif is_word_list: 
								size = 2
								valtype = "addr"
							elif is_long_list: 
								size = 3
								valtype = "long"

							LINE[ind] = {"type": util.DATA_TYPES.TYPE, "valtype": valtype, "size": size, "value": LINE[ind]}


						elif LINE[ind]["type"] == util.DATA_TYPES.DBYTE:
							is_byte_list = True

						elif LINE[ind]["type"] == util.DATA_TYPES.DWORD:
							is_word_list = True

						elif LINE[ind]["type"] == util.DATA_TYPES.DLONG:
							is_long_list = True



						ind += 1
				except LineException:
					raise
				except Exception as e:
					#raise LineException(LINE_OBJ.get_line_num(), "Error parsing line: \n" + str(e) + "\n" + str(LINE_OBJ.get_raw()), LINE_OBJ.get_file_name())
					raise LineError(LINE_OBJ, "Error parsing line: \n\n" + str(e))



				LINE_OBJ.set_parsed(LINE)

				sec["code_data"][sec_l] = LINE_OBJ

				sec_l += 1




		if TIMING_DEBUG: print("  format data types time: ", format(util.get_time()-start, " 10.5f"))




		###############################################################################################

		###############################################################################################


		start = util.get_time()
		# convert opcode mnemonics into opcodes, and values into correct hex 


		sec_ind = 1
		for SEC_NUM in range(1, len(sections)):

			sec = sections[SEC_NUM]

			for LINE_OBJ in sec["code_data"]:
				LINE = LINE_OBJ.get_parsed()


				if LINE_OBJ.get_is_macro():
					continue

				if LINE_OBJ.get_force_lis() and LINE_OBJ.get_is_equ():
					continue




				first_attempt = True
				ind = 0
				while ind < len(LINE):

					if LINE[ind]["type"] == util.DATA_TYPES.DATA_PAGE:
						#print(LINE)
						try:
							data_page = LINE[ind+1]["value"]["value"]
						except:
							data_page = LINE[ind+1]["value"]
						LINE[ind+1]["size"] = 0



					elif LINE[ind]["type"] == util.DATA_TYPES.OPCODE:
						# convert each individual opcode based on the most matched type


						op = LINE[ind]["opcode"].lower()

						

						try:
							if op == "adc":
								# 

								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "and":
								# 

								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "asl":
								# 

								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "bcc":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x90], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "blt":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x90], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "bcs":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xb0], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "bge":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xb0], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "beq":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xf0], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "bit":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "bmi":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x30], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "bne":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xd0], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "bpl":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x10], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "bra":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x80], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "brk":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x00], "size": 1}
								if ind+1 <= len(LINE):
									LINE.append({"type": util.DATA_TYPES.TYPE, "valtype": "const", "size": 1, "value": {"type": util.DATA_TYPES.VALUE, "value": 0, "size": 1}}) 
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "brl":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x82], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 2

							elif op == "bvc":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x50], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "bvs":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x70], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "clc":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x18], "size": 1}

							elif op == "cld":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xd8], "size": 1}

							elif op == "cli":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x58], "size": 1}

							elif op == "clv":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xb8], "size": 1}

							elif op == "cmp":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "cop":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x02], "size": 1}
								if ind+1 > len(LINE):
									LINE.append({"type": util.DATA_TYPES.TYPE, "valtype": "const", "size": 1, "value": {"type": util.DATA_TYPES.VALUE, "value": 0, "size": 1}}) 
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "cpx":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "cpy":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "dea":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x3a], "size": 1}

							elif op == "dec":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "dex":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xca], "size": 1}

							elif op == "dey":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x88], "size": 1}

							elif op == "eor":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "ina":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x1a], "size": 1}

							elif op == "inc":
								#
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "inx":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xe8], "size": 1}

							elif op == "iny":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xc8], "size": 1}

							elif op == "jmp":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "jml":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}
								LINE[ind+1]["size"] = 3

							elif op == "jsr":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "jsl":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}
								LINE[ind+1]["size"] = 3

							elif op == "lda":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "ldx":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "ldy":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "lsr":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "mvn":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x54], "size": 1}

								
								c_ind = 1
								while ind + c_ind < len(LINE):
									LINE[ind+c_ind]["size"] = 1
									try:
										LINE[ind+c_ind]["value"]["size"] = 1
									except:
										c_ind = c_ind # dummy pass
									c_ind += 1

								

								LINE = LINE[:ind+1] + [x for x in reversed(LINE[ind+1:])]
								LINE_OBJ.set_parsed(LINE)

								

							elif op == "mvp":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x44], "size": 1}

								c_ind = 1
								while ind + c_ind < len(LINE):
									LINE[ind+c_ind]["size"] = 1
									try:
										LINE[ind+c_ind]["value"]["size"] = 1
									except:
										c_ind = c_ind # dummy pass
									c_ind += 1

								
								LINE = LINE[:ind+1] + [x for x in reversed(LINE[ind+1:])]
								LINE_OBJ.set_parsed(LINE)

								

							elif op == "nop":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xea], "size": 1}

							elif op == "ora":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "pea":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xf4], "size": 1}

							elif op == "pei":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xd4], "size": 1}

							elif op == "per":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x62], "size": 1}
								LINE[ind+1]["size"] = 2

							elif op == "pha":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x48], "size": 1}

							elif op == "phb":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x8b], "size": 1}

							elif op == "phd":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x0b], "size": 1}

							elif op == "phk":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x4b], "size": 1}

							elif op == "php":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x08], "size": 1}

							elif op == "phx":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xda], "size": 1}

							elif op == "phy":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x5a], "size": 1}

							elif op == "pla":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x68], "size": 1}

							elif op == "plb":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xab], "size": 1}

							elif op == "pld":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x2b], "size": 1}

							elif op == "plp":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x28], "size": 1}

							elif op == "plx":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xfa], "size": 1}

							elif op == "ply":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x7a], "size": 1}

							elif op == "rep":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xc2], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "rol":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "ror":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "rti":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x40], "size": 1}

							elif op == "rtl":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x6b], "size": 1}

							elif op == "rts":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x60], "size": 1}

							elif op == "sbc":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "sec":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x38], "size": 1}

							elif op == "sed":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xf8], "size": 1}

							elif op == "sei":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x78], "size": 1}

							elif op == "sep":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xe2], "size": 1}
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "sta":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "stp":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xdb], "size": 1}

							elif op == "stx":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "sty":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "stz":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "tax":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xaa], "size": 1}

							elif op == "tay":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xa8], "size": 1}

							elif op == "tcd":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x5b], "size": 1}

							elif op == "tcs":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x1b], "size": 1}

							elif op == "tdc":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x7b], "size": 1}

							elif op == "trb":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "tsb":
								# 
								
								opcode = parse_instruction(LINE[ind:], op.upper(), LINE_OBJ)
								
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [opcode], "size": 1}

							elif op == "tsc":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x3b], "size": 1}

							elif op == "tsx":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xba], "size": 1}

							elif op == "txa":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x8a], "size": 1}

							elif op == "txs":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x9a], "size": 1}

							elif op == "txy":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x9b], "size": 1}

							elif op == "tya":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x98], "size": 1}

							elif op == "tyx":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xbb], "size": 1}

							elif op == "wai":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xcb], "size": 1}

							elif op == "wdm":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0x42], "size": 1}
								if ind+1 > len(LINE):
									LINE.append({"type": util.DATA_TYPES.TYPE, "valtype": "const", "size": 1, "value": {"type": util.DATA_TYPES.VALUE, "value": 0, "size": 1}}) 
								if ind+1 <= len(LINE):
									LINE[ind+1]["size"] = 1

							elif op == "xba":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xeb], "size": 1}

							elif op == "xce":
								# 
								LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [0xfb], "size": 1}

						except Exception as e:

							if first_attempt:
								f_ind = ind
								while f_ind < len(LINE):

									if LINE[f_ind]["type"] == util.DATA_TYPES.TYPE:
										if LINE[f_ind]["valtype"] == "const":
											LINE[f_ind]["valtype"] = "addr"

									f_ind += 1

								ind -= 1
								first_attempt = False

							else:
								raise e
					
					# do encoding of data bvtes??? nah
						
						
						

						

					ind += 1
				LINE_OBJ.set_parsed(LINE)




			sec_ind += 1


		if TIMING_DEBUG: print("  opcode parsing time: ", format(util.get_time()-start, " 10.5f"))



		start = util.get_time()
		# convert all hard data and variables back into respective types

		data_page = 0

		sec_ind = 1
		for SEC_NUM in range(1, len(sections)):


			for LINE_OBJ in sections[SEC_NUM]["code_data"]:

				if LINE_OBJ.get_is_macro():
					continue

				if LINE_OBJ.get_force_lis() and LINE_OBJ.get_is_equ():
					continue


				LINE = LINE_OBJ.get_parsed()
				

				is_byte_list = False
				is_word_list = False
				is_long_list = False

				ind = 0
				is_op = False
				LINE_LEN = len(LINE)
				while ind < LINE_LEN:

					is_bank = False
					is_offs = False
					is_high = False
					is_low  = False

					do_dp = False



					if not (LINE[ind]["type"] in {util.DATA_TYPES.DATA_PAGE, util.DATA_TYPES.DBYTE, util.DATA_TYPES.DWORD, util.DATA_TYPES.DLONG, util.DATA_TYPES.TYPE, util.DATA_TYPES.VALUE}):
						ind += 1
						continue
					

					if LINE[ind]["type"] == util.DATA_TYPES.DATA_PAGE:
						#print(LINE)
						try:
							data_page = LINE[ind+1]["value"]["value"]
							#print("DATA PAGE IS NOW: ", format(data_page, "04x"))
						except:
							data_page = LINE[ind+1]["value"]
						#LINE[ind+1]["size"] = 0


					elif LINE[ind]["type"] == util.DATA_TYPES.DBYTE:
						is_byte_list = True

					elif LINE[ind]["type"] == util.DATA_TYPES.DWORD:
						is_word_list = True

					elif LINE[ind]["type"] == util.DATA_TYPES.DLONG:
						is_long_list = True

					elif LINE[ind]["type"] == util.DATA_TYPES.TYPE:
						valtype = LINE[ind]["valtype"]

						if valtype == "dp" and "real_dp" in LINE[ind] and LINE[ind]["real_dp"]: do_dp = True

						if LINE[ind]["size"] == 0:
							if valtype == "dp":
								LINE[ind]["size"] = 1
							elif valtype == "addr":
								LINE[ind]["size"] = 2
							elif valtype == "long":
								LINE[ind]["size"] = 3


						size = LINE[ind]["size"]
						LINE[ind] = LINE[ind]["value"]
						LINE[ind]["size"] = size

						if valtype == "bank":
							LINE[ind]["bank_type"] = "bank"
							is_bank = True
						elif valtype == "offset":
							LINE[ind]["bank_type"] = "offset"
							is_offs = True
						elif valtype == "high":
							LINE[ind]["bank_type"] = "high"
							is_high = True
						elif valtype == "low":
							LINE[ind]["bank_type"] = "low"
							is_low = True
						else:
							LINE[ind]["bank_type"] = "NONE"


						if is_byte_list or is_word_list or is_long_list:
							if LINE[ind]["bank_type"] != "NONE" and (LINE[ind]["type"] == util.DATA_TYPES.VARIABLE or LINE[ind]["type"] == util.DATA_TYPES.EXTERNAL):
								l_size = 0
								if is_byte_list: l_size = 1
								elif is_word_list: l_size = 2
								elif is_long_list: l_size = 3

								LINE[ind]["size"] = l_size



					

					if LINE[ind]["type"] == util.DATA_TYPES.VALUE:
						use_value = True
						if ind > 0 and LINE[ind-1]["type"] in {util.DATA_TYPES.DATA_PAGE, util.DATA_TYPES.DATA_BANK, util.DATA_TYPES.ORG}:
							use_value = False

						if use_value:

							data = []
							val = LINE[ind]["value"]

							if do_dp:
								
								
								val = (val - data_page) & 0xff # this... will cause issues if not used properly, but it is how as65c does it...


								# it SHOULD be this:
								# ---------------------
								#if val >= data_page and (val - data_page) < 0x100:
								#	val = val - data_page
								#else:
								#	print("Value not within used data page.\n" + str(LINE_OBJ.get_raw()) + "\n\tDATA PAGE: " + format(data_page, "04x").upper() + "\n\tVALUE: " + format(val, "04x"))



							SIZE = LINE[ind]["size"]

							if val < 0:
								val = val + 0x1000000

							if is_bank:
								val = (val // 0x10000) & 0xffff
								#SIZE = 2

							if is_offs:
								val = val & 0xffff
								#SIZE = 2

							if is_high:
								val = (val // 0x100) & 0xff

							if is_low:
								val = val & 0xff


							if is_byte_list: SIZE = 1
							elif is_word_list: SIZE = 2
							elif is_long_list: SIZE = 3




							for i in range(LINE[ind]["size"]):
								data.append(val % 256)
								val = val // 256

							if len(data) != SIZE:
								for _ in range(SIZE - LINE[ind]["size"]):
									data.append(0)


							LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": data, "size": SIZE} 

						else:
							LINE[ind] = {"type": util.DATA_TYPES.RAW_BYTES, "bytes": [], "size": 0} 


					ind += 1

				#if FILE_NAME == "runed.asm":
				#	print(LINE)

				LINE_OBJ.set_parsed(LINE)

			sec_ind += 1


		#print(globalvars)

		if TIMING_DEBUG: print("  variable conversion time: ", format(util.get_time()-start, " 10.5f"))




		###############################################################################################

		###############################################################################################

		VARIABLES_TO_RELIFY = set()


		start = util.get_time()

		sections_to_indexes = {}

		#s_ind = 0
		sec_ind = 0
		#sec_dict = {}
		for sec in sections:

			if not (sec["secname"] in sections_to_indexes):
				sections_to_indexes[sec["secname"]] = sec_ind
				sec_ind += 1


			'''	
			for s in range(len(sections)):
				if sections[s]["secname"] == sec["secname"]:
					if s == s_ind:
						sections_to_indexes[sec["secname"]] = sec_ind
						sec_ind += 1
					break
			'''

			




		for x in LOCAL_EXTERNAL:
			if localvars[var_dict[x]]["type"] == "label":
				#EXTERNALVARS_SET.add(x)

				if len(x) >= FILE_TAG_LEN and x[:FILE_TAG_LEN] == FILE_TAG:
					globalvars.append(x)
					externalvars.append(x)



		GLOBALVARS_DICT = {}
		for g in range(1, len(globalvars)): GLOBALVARS_DICT[str(globalvars[g])] = g


		#set([globalvars[x] for x in range(1, len(globalvars))])
		# convert section code into bytes per line

		sec_ind = 1
		for SEC_NUM in range(1, len(sections)):

			sec = sections[SEC_NUM]

			for LINE_OBJ in sec["code_data"]:
				LINE = LINE_OBJ.get_parsed()

				if LINE_OBJ.get_is_macro():
					continue

				if LINE_OBJ.get_is_hidden():
					continue

				LINE_BYTES = [0x57]


				# add line number
				LINE_NUM = LINE_OBJ.get_line_num()
				LINE_BYTES.append((LINE_NUM // 256) % 256)
				LINE_BYTES.append(LINE_NUM % 256)


				if LINE_OBJ.get_force_lis() and LINE_OBJ.get_is_equ():
					LINE_OBJ.set_bytes(LINE_BYTES)
					LINE_OBJ.set_parsed(LINE)
					continue


				final_consecutive_bytes = []


				LINE_LEN = len(LINE)



				ind = 0
				while ind < LINE_LEN + 1:
					end_consec = True

					if ind < LINE_LEN:
						chunk = LINE[ind]
						end_consec = True


						if chunk["type"] == util.DATA_TYPES.RAW_BYTES:
							end_consec = False
						elif chunk["type"] == util.DATA_TYPES.VARIABLE or chunk["type"] == util.DATA_TYPES.EXTERNAL:
							pass
						elif chunk["type"] == util.DATA_TYPES.STORAGE_DIRECTIVE:
							pass
						else:
							end_consec = False


					# patch in bytes BEFORE the next variable data
					if end_consec:

						size = len(final_consecutive_bytes)

						if size > 0:

							LINE_BYTES.append(0x11) # raw data 

							size_bytes = make_length_bytes(size)

							for b in size_bytes:
								LINE_BYTES.append(b)

							for b in final_consecutive_bytes:
								LINE_BYTES.append(b)

						final_consecutive_bytes = []



					if ind < LINE_LEN:


						if chunk["type"] == util.DATA_TYPES.RAW_BYTES:
							for b in chunk["bytes"]:
								final_consecutive_bytes.append(b)

							end_consec = False

						elif chunk["type"] == util.DATA_TYPES.VARIABLE or chunk["type"] == util.DATA_TYPES.EXTERNAL:
							# variable type

							if chunk["type"] == util.DATA_TYPES.VARIABLE and ind == 0:
								break

							if chunk["varname"].lower() in ORGANIZATION_TAGS:	# change to "if not in rel group names"
								break

							var_bytes = [0x12]

							size = chunk["size"]

							if size == 1:
								var_bytes.append(0x11) # byte

							elif size == 2:
								var_bytes.append(0x12) # word

							elif size == 3:
								var_bytes.append(0x13) # long

							if not "bank_type" in chunk:
								LINE[ind]["bank_type"] = "NONE"
								chunk = LINE[ind]

							var_type = 0

							# variable reference type
							if chunk["bank_type"] == "NONE":
								pass

							elif chunk["bank_type"] == "bank":
								# bank of variable
								var_type |= 0b01001000  # bank

							elif chunk["bank_type"] == "offset":
								# offset of variable
								var_type |= 0b01100000  # offset

							elif chunk["bank_type"] == "high":
								# high byte of variable
								var_type |= 0b01000000  # high

							elif chunk["bank_type"] == "low":
								# low byte of variable
								var_type |= 0b00111000  # low



							if chunk["type"] == util.DATA_TYPES.VARIABLE:
								var_type |= 0b00000001  # local variable

								var_bytes.append(var_type) # variable type

								v = chunk["varname"]

								'''
								INDEX = -1
								v_ind = 0
								for var in localvars:

									if var["name"] == v:
										INDEX = v_ind 
										break

									v_ind += 1

								if INDEX == -1:
								'''

								if not v in var_dict:
									#raise LineException(LINE_OBJ.get_line_num(), "Error converting variable: " + str(chunk), LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "Error converting variable: " + str(chunk))


								if not localvars[var_dict[v]]["is_near"]:
									VARIABLES_TO_RELIFY.add(v)
									

								#VAR = localvars[INDEX]
								VAR = chunk
								try:
									section = VAR["section"]
								except:
									#raise LineException(LINE_OBJ.get_line_num(), "Error getting variable section: " + str(chunk) + "\n" + LINE_OBJ.get_raw(), LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "Error getting variable section: " + str(chunk))

								s_ind = sections_to_indexes[section]


								

								var_bytes.append((s_ind // 256) % 256)   # section number
								var_bytes.append(s_ind % 256)

								offset = VAR["offset"]
								offset_bytes = []
								for _ in range(4):
									offset_bytes.append(offset % 256)
									offset = offset // 256

								for b in reversed(offset_bytes):
									var_bytes.append(b)  # section offset



							elif chunk["type"] == util.DATA_TYPES.EXTERNAL:
								var_type |= 0b00000000  # external variable

								var_bytes.append(var_type) # variable type


								v = chunk["varname"]

								'''
								INDEX = -1
								v_ind = 0
								for var in globalvars:
									if var == v:
										INDEX = v_ind 
										break

									v_ind += 1

								if INDEX == -1:
									raise LineException(LINE_OBJ.get_line_num(), "Error converting variable: " + str(chunk), LINE_OBJ.get_file_name())
								'''
								
								if not (v in GLOBALVARS_DICT):
									#raise LineException(LINE_OBJ.get_line_num(), "Error converting variable: " + str(chunk), LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "Error converting variable: " + str(chunk))

								INDEX = GLOBALVARS_DICT[v]

								var_bytes.append((INDEX // 256) % 256)  # variable offset
								var_bytes.append(INDEX % 256)
								



								label_offset = 0
								label_offset_bytes = []

								if "is_external_label" in chunk:
									label_offset = chunk["external_offset"]

								if label_offset < 0:
									label_offset += 0x100000000

								for _ in range(4):
									label_offset_bytes.append(label_offset % 256)
									label_offset = label_offset // 256


								for b in reversed(label_offset_bytes):
									var_bytes.append(b)  # external label offset bytes


							for v in var_bytes:
								LINE_BYTES.append(v)

						elif chunk["type"] == util.DATA_TYPES.STORAGE_DIRECTIVE:
							# storage directive
							pass

						else:

							end_consec = False



					

					ind += 1

				LINE_OBJ.set_bytes(LINE_BYTES)
				LINE_OBJ.set_parsed(LINE)



			sec_ind += 1


		for v in localvars:
			if v["type"] == "label" and not v["is_near"]:
				VARIABLES_TO_RELIFY.add(v["name"])


		if TIMING_DEBUG: print("  rel lines conversion time: ", format(util.get_time()-start, " 10.5f"))





		################################################################################################################

		# write .lis file


		def WRITE_LIS():
			lstart = util.get_time()
			# section testing
			REAL_OFFS = 0
			TEST_OFFS = 0
			P_TEST_OFFS = 0
			PREV_LINE = 0
			with open(FILE_PATH + FILE_NAME.split(".")[0] + ".lis", "w") as LIS_FILE:
				for S in sections:
					PREV_LINE = 0
					L_IND = -1
					REAL_OFFS = 0
					TEST_OFFS = 0
					for LINE in S["code_data"]:
						#print(LINE._raw_line.encode("utf-8"))
						L_IND += 1

						TEST_OFFS = LINE.get_offset()

						if LINE.get_is_hidden() and not (LINE.get_force_lis()):
							continue

						if LINE.get_is_section(): 
							REAL_OFFS = TEST_OFFS


						if REAL_OFFS != TEST_OFFS:
							print("[WARN] ISSUE DETECTED AROUND " + format(S["code_data"][PREV_LINE].get_offset(), "04x") + ": " + str(S["code_data"][PREV_LINE].get_raw()))
							print("[WARN] -- Should be " + format(TEST_OFFS, "04x") + ", is " + format(REAL_OFFS, "04x"))
							REAL_OFFS = TEST_OFFS

						bts = LINE.get_bytes()

						BYTES = bts[3:]
						BL = len(BYTES)
						idx = 0
						if BYTES != []:
							while idx < BL:
								if BYTES[idx] == 0x11:
									L = BYTES[idx + 1] & 0x7f
									idx += L + 2
									REAL_OFFS += L

								
								elif BYTES[idx] == 0x12:
									dL = BYTES[idx+1] & 0x0f
									REAL_OFFS += dL
									idx += 9

								else:
									#raise LineException(LINE_OBJ.get_line_num(), "Error converting to rel line: \n" + LINE_OBJ.get_raw() + "\n@ offset " + format(TEST_OFFS, "04x") + "\n", LINE_OBJ.get_file_name())
									raise LineError(LINE_OBJ, "Error converting to rel line @ offset " + format(TEST_OFFS, "04x"))



						text = ""

						curr_l = format(LINE.get_offset(), "04x") + "    "
						
						i = 0
						printed_code = False
						for x in bts:
							if i % 16 == 0 and i != 0:
								printed_code = True
								text += (curr_l + "…").ljust(64) + str(LINE.get_raw()).rstrip() + "\n" 
								curr_l = "      … "

							curr_l += format(x, "02x") + " "


							i += 1

						if not printed_code:
							curr_l = curr_l.ljust(64) + str(LINE.get_raw()).rstrip()

						text += curr_l 
						

						#print(LINE.get_bytes(), str(LINE.get_raw()))

						

						#print("")
						LIS_FILE.write(text + "\n")
						PREV_LINE = L_IND
						
						P_TEST_OFFS = TEST_OFFS

			if TIMING_DEBUG: print("  lis write time: ", format(util.get_time()-lstart, " 10.5f"))


		#LIS_THREAD = threading.Thread(target=WRITE_LIS, args=())
		#LIS_THREAD.start()

		WRITE_LIS()


		###############################################################################################

		###############################################################################################


		start = util.get_time()
		# populate section code with code bytes
		
		#
		sec_ind = 0
		for sec in sections:

			sec_bytes = []

			for LINE_OBJ in sec["code_data"]:
				if LINE_OBJ.get_is_macro():
					continue



				for b in LINE_OBJ.get_bytes():
					sec_bytes.append(b)

			sections[sec_ind]["REL_DATA"] = sec_bytes

			sec_ind += 1




		ASSEMBLED_CODE = []

		sec_ind = 0
		for sec in sections:
			#print(sec["secname"], sec["size"])

			if sec["group"] != "DATA" or (sec["group"] == "DATA" and sec["REL_DATA"] != []):

				INDEX = -1
				i = 0
				for s in sections:
					if s["secname"] == sec["secname"]:
						INDEX = i
						break
					i += 1

				if INDEX > 0:
					ASSEMBLED_CODE.append(0x01)
					ASSEMBLED_CODE.append(0x00)
					ASSEMBLED_CODE.append(sections_to_indexes[sections[INDEX]["secname"]])

				if INDEX != sec_ind:
					sections[INDEX]["size"] += sec["size"]

				for b in sec["REL_DATA"]:
					ASSEMBLED_CODE.append(b)

					if INDEX != sec_ind:
						sections[INDEX]["REL_DATA"].append(b)

			sec_ind += 1





		final_sections = []

		sec_ind = 0
		for sec in sections:

			#print(sec["secname"])

			INDEX = -1
			i = 0
			for s in sections:
				if s["secname"] == sec["secname"]:
					INDEX = i
					break
				i += 1

			if INDEX == sec_ind:
				final_sections.append(sec)

			sec_ind += 1


		'''
		sections_to_indexes = {}

		print("")

		ind = 0
		for s in final_sections:
			sections_to_indexes[s["secname"]] = ind
			ind += 1
			print(s["secname"])
		'''
		
		if TIMING_DEBUG: print("  rel section build time: ", format(util.get_time()-start, " 10.5f"))


		###############################################################################################

		###############################################################################################

		start = util.get_time()
		# step 6: convert into REL file format

		REL_DATA = []

		###############################################################################################

		# REL file header

		REL_DATA.append(0x33)
		REL_DATA.append(0x61)  # REL header
		REL_DATA.append(0x01)

		REL_DATA.append(0x00)  # ?? data
		REL_DATA.append(0x00)


		# compilation date
		today = date.today()
		year, month, day = tuple([int(d) for d in today.strftime("%y/%m/%d").split("/")])
		weekday = today.isoweekday()%7

		REL_DATA.append(year%100)
		REL_DATA.append(month)
		REL_DATA.append(day)
		REL_DATA.append(weekday)

		# compilation time
		now = datetime.now()
		hours, minutes, seconds = tuple([int(d) for d in now.strftime("%H:%M:%S").split(":")])

		REL_DATA.append(hours)
		REL_DATA.append(minutes)
		REL_DATA.append(seconds)



		REL_DATA.append(len("65C816 V2.11"))
		for b in "65C816 V2.11":
			REL_DATA.append(ord(b))

		for _ in range(7):
			REL_DATA.append(0x00)


		###############################################################################################


		# group data
		GROUP_DATA = []



		for g_num in range(1, len(groups)):
			g = groups[g_num]
			GROUP_DATA.append(len(g))

			for b in g:
				GROUP_DATA.append(ord(b))

			for _ in range(8):
				GROUP_DATA.append(0x00) # still no idea what this is

			GROUP_DATA.append(0x00) # to end section????????



		len_bytes = make_length_bytes(len(GROUP_DATA) + 1)


		for b in len_bytes:
			REL_DATA.append(b)

		for b in GROUP_DATA:
			REL_DATA.append(b)

		REL_DATA.append(0x00) # end group data



		###############################################################################################

		# section data

		SECTION_DATA = []


		for SEC_NUM in range(1, len(final_sections)):

			s = final_sections[SEC_NUM]
			SECTION_DATA.append(len(s["secname"]))

			for b in s["secname"]:
				SECTION_DATA.append(ord(b))

			group_ind = 0

			for g in range(len(groups)):
				if groups[g].lower() == s["group"].lower():
					group_ind = g

			#print("SECTION:", s["secname"], " GROUP:", s["group"])


			if s["type"] == util.DATA_TYPES.ORG:
				# org section
				SECTION_DATA.append(0x02) # org

				SECTION_DATA.append(0x00) # technically should be full "group" index, but Im lazy and this is a prototype
				SECTION_DATA.append(0x00)
				SECTION_DATA.append(group_ind)
				SECTION_DATA.append(0x08)
				for _ in range(4):
					SECTION_DATA.append(0x00)


				SECTION_DATA.append(0x18)

				for _ in range(18):
					SECTION_DATA.append(0x00)

				location_bytes = []
				loc = s["offset"]

				for _ in range(4):
					location_bytes.append(loc % 256)
					loc = loc // 256

				for b in reversed(location_bytes):
					SECTION_DATA.append(b)



			else:

				if s["secname"].lower() == "comn":
					# COMN section
					SECTION_DATA.append(0x00) # comn

					SECTION_DATA.append(0x00) # technically should be full "group" index, but Im lazy and this is a prototype
					SECTION_DATA.append(0x00)
					SECTION_DATA.append(group_ind)
					SECTION_DATA.append(0x08)
					for _ in range(4):
						SECTION_DATA.append(0x00)

					SECTION_DATA.append(0x18)

					for _ in range(18):
						SECTION_DATA.append(0x00)

					for _ in range(4):
						SECTION_DATA.append(0x00)

				else:
					# regular section
					SECTION_DATA.append(0x01) # section

					SECTION_DATA.append(0x00) # technically should be full "group" index, but Im lazy and this is a prototype
					SECTION_DATA.append(0x00)
					SECTION_DATA.append(group_ind)
					SECTION_DATA.append(0x08)
					for _ in range(4):
						SECTION_DATA.append(0x00)

					SECTION_DATA.append(0x18)

					for _ in range(18):
						SECTION_DATA.append(0x00)

					for _ in range(4):
						SECTION_DATA.append(0x00)


			size = s["size"]
			size_bytes = []

			for _ in range(4):
				size_bytes.append(size % 256)
				size = size // 256

			for b in reversed(size_bytes):
				SECTION_DATA.append(b)

		len_bytes = make_length_bytes(len(SECTION_DATA) + 1)


		for b in len_bytes:
			REL_DATA.append(b)

		for b in SECTION_DATA:
			REL_DATA.append(b)

		REL_DATA.append(0x00)  # end section data block 




		###############################################################################################


		# global var data

		GLOBAL_DATA = []


		for g_num in range(1, len(globalvars)): #range(1, len(globalvars)):
			g = globalvars[g_num]

			GLOBAL_DATA.append(len(g))

			for b in g:
				GLOBAL_DATA.append(ord(b))


			is_global = True

			#if g in externalvars: is_global = False  # use this later to speed up?

			if g in EXTERNALVARS_SET: is_global = False
			'''
			for e in externalvars:
				if g == e:
					is_global = False
					break
			'''

			if not is_global:
				GLOBAL_DATA.append(0x04) # external variable

				for _ in range(8):
					GLOBAL_DATA.append(0x00)



			else:
				var = None
				'''
				for v in localvars:
					if v["name"] == g:
						var = v

						val = -1
						if v["type"] == "label":
							val = v["offset"]
						elif v["type"] == "exact":
							val = v["value"]

						EXTERNAL_SYMBOLS[v["name"]] = (v["type"], val)

						break

				if var == None:
					raise Exception("Global isnt local: " + g)
				'''

				if g in var_dict:
					v = var = localvars[var_dict[g]]

					val = -1

					if v["type"] == "label":
						val = v["offset"]
					elif v["type"] == "exact":
						val = v["value"]

					EXTERNAL_SYMBOLS[v["name"]] = (v["type"], val)


				else:
					raise Exception("Error setting global value. Variable not found: " + g)




				if var["type"] == "label":
					GLOBAL_DATA.append(0x05) # label value

					section_bytes = []
					sec = sections_to_indexes[var["section"]]

					for _ in range(4):
						section_bytes.append(sec % 256)
						sec = sec // 256

					for b in reversed(section_bytes):
						GLOBAL_DATA.append(b)

					offset_bytes = []
					offset = var["offset"]

					for _ in range(4):
						offset_bytes.append(offset % 256)
						offset = offset // 256

					for b in reversed(offset_bytes):
						GLOBAL_DATA.append(b)


				elif var["type"] == "exact":
					GLOBAL_DATA.append(0x06) # exact value


					val_bytes = []
					val = var["value"]

					for _ in range(8):
						val_bytes.append(val % 256)
						val = val // 256

					for b in reversed(val_bytes):
						GLOBAL_DATA.append(b)



		len_bytes = make_length_bytes(len(GLOBAL_DATA) + 1)

		for b in len_bytes:
			REL_DATA.append(b)

		for b in GLOBAL_DATA:
			REL_DATA.append(b)

		REL_DATA.append(0x00)  # end global vars block 



		###############################################################################################



		# processor status data
		PROCESSOR_DATA = []


		for p in reversed(processor_flags):
			PROCESSOR_DATA.append(0x00)

			if p["type"] == "idx8":
				PROCESSOR_DATA.append(0x01)
			elif p["type"] == "idx16":
				PROCESSOR_DATA.append(0x02)
			elif p["type"] == "mem8":
				PROCESSOR_DATA.append(0x03)
			elif p["type"] == "mem16":
				PROCESSOR_DATA.append(0x04)

			PROCESSOR_DATA.append(0x01) # dont know... but needed


			section_bytes = []
			sec = sections_to_indexes[sections[p["section"]]["secname"]]

			for _ in range(4):
				section_bytes.append(sec % 256)
				sec = sec // 256

			for b in reversed(section_bytes):
				PROCESSOR_DATA.append(b)


			offset_bytes = []
			offset = p["offset"]

			for _ in range(4):
				offset_bytes.append(offset % 256)
				offset = offset // 256

			for b in reversed(offset_bytes):
				PROCESSOR_DATA.append(b)



		len_bytes = make_length_bytes(len(PROCESSOR_DATA) + 2)

		for b in len_bytes:
			REL_DATA.append(b)

		for b in PROCESSOR_DATA:
			REL_DATA.append(b)


		REL_DATA.append(0x00)
		REL_DATA.append(0x00)  # end processor data block 




		###############################################################################################


		# file name data????????
		REL_DATA.append(len(FILE_NAME))

		for b in FILE_NAME:
			REL_DATA.append(ord(b))


		###############################################################################################


		# local variable data
		LOCAL_DATA = []

		'''
		for var in localvars: # for var in ALL_USED_VARS

			if not (var["name"] in VARIABLES_TO_RELIFY): continue
		'''

		for REL_VAR in VARIABLES_TO_RELIFY:

			var = localvars[var_dict[REL_VAR]]
			
			if not ("is_temp" in var and var["is_temp"]) and not ("is_near" in var and var["is_near"]):

				if var["name"] in STORAGE_LABELS: continue

				if var["name"][:9] == "_NEAR_VAR": continue


				LOCAL_DATA.append(len(var["name"]))

				for b in var["name"]:
					LOCAL_DATA.append(ord(b))


				if var["type"] == "label":
					LOCAL_DATA.append(0x01) # label


					section_bytes = []
					sec = sections_to_indexes[var["section"]]

					for _ in range(4):
						section_bytes.append(sec % 256)
						sec = sec // 256

					for b in reversed(section_bytes):
						LOCAL_DATA.append(b)


					offset_bytes = []
					offset = var["offset"]

					for _ in range(4):
						offset_bytes.append(offset % 256)
						offset = offset // 256

					for b in reversed(offset_bytes):
						LOCAL_DATA.append(b)


				elif var["type"] == "exact":
					LOCAL_DATA.append(0x02) # equ


					val_bytes = []
					val = var["value"]

					for _ in range(8):
						val_bytes.append(val % 256)
						val = val // 256

					for b in reversed(val_bytes):
						LOCAL_DATA.append(b)




		len_bytes = make_length_bytes(len(LOCAL_DATA) + 1)

		for b in len_bytes:
			REL_DATA.append(b)

		for b in LOCAL_DATA:
			REL_DATA.append(b)


		REL_DATA.append(0x00)  # end local variable data


		###############################################################################################


		# finally, code data


		for b in ASSEMBLED_CODE:
			REL_DATA.append(b)


		REL_DATA.append(0x00)  # end code data
		REL_DATA.append(0x00)




		###############################################################################################

		###############################################################################################

		# output REL formatted assembled code
		if TIMING_DEBUG: print("  rel build time: ", format(util.get_time()-start, " 10.5f"))


		#set_symbols(SYMBOLS_FILE)


		


		start = util.get_time()

		with open(FILE_PATH + FILE_NAME.split(".")[0] + ".rel", "wb") as REL_FILE:
			L = len(REL_DATA)
			out_bytes = []
			for ind in range(L):
				b = REL_DATA[ind]

				if b == 0x0d:
					if ind < L - 1 and REL_DATA[ind+1] == 0x0a:
						out_bytes.append(b)

				out_bytes.append(b)
			
			REL_FILE.write(bytes(out_bytes))


		
		if TIMING_DEBUG: print("  rel write time: ", format(util.get_time()-start, " 10.5f"))

		#LIS_THREAD.join()

		succeeded = True

	except Exception as e:

		if not succeeded:
			print("\n[ERROR] Error during assembly of " + FILE_NAME)

			traceback.print_exc()

			print("\n[WARNING] Could not assemble " + FILE_NAME + "\n\n")

		succeeded = False



	if succeeded:

		# add hash to memory
		if curr_hash != None:
			add_hash(filename, curr_hash)



		print("[INFO] Finished assembling " + FILE_NAME.split(".")[0] + ".rel", end="")

		print(" after " + format(util.get_time()-ASM_START, " 10.5f").lstrip() + "s.")
		#print(curr_hash.hexdigest())
		#print(curr_hash)


