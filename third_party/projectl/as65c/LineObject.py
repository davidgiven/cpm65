###################################################
#   Main "Line" object for as65c assembler
#      by MrL314
#
#        [ Nov.15, 2021 ]
###################################################


# standard imports
import traceback
import threading

# local imports
import util
from exceptions import LineException, LineError




UNSTABLE_SYMBOLS = {"+", "-", "(", "["}
BR_OPS1 = {"bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs"}
BR_OPS2 = {"bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs", "brl", "per"}
BR_OPS3 = {"brl", "per"}


class Line(object):
	"""Main "Line" Object. Holds all useful data/functions for assembling a line of code."""


	def __init__(self, raw_line, line_number=-1, file=None, include_level=0, macro_line=None):

		self._raw_line = raw_line          # raw line text
		self._line_number = line_number    # number of line in file
		self._file = file                  # raw file path
		self._file_name = None             # file name
		self._file_path = None             # relative file directory
		self._offset = 0                   # offset in current section (in bytes)
		self._data_bytes = []              # bytes after encoding line
		self._is_code = False              # indicates if line is a line of code
		self._include_lvl = include_level  # indicates level of include of file 
		self._already_included = False     # indicates that this line has not undergone the include process
		self._is_macro = False             # indicates that this line is a macro line, not to be included in the final build
		self._is_macro_def = False         # indicates that this line is a definition of a macro
		self._is_macro_end = False         # indicates that this line is the end of a macro
		self._uses_near_var = False        # indicates that this line uses the special near var operator
		self._is_end = False               # indicates that this line uses the END tag
		self._is_op = False                # indicates that this line uses an opcode
		self._show_lis = True              # indicates that this line will show in the lis and rel file
		self._force_lis = False            # indicates that this line is only for debugging purposes
		self._is_equ = False               # indicates that this line is an EQU line
		self._is_section = False           # indicates that this line begins a section
		self._is_include_line = False      # indicates that this line contains an INCLUDE instruction
		self._is_data_line = False         # indicates that this line contains data values



		self._clean_time = 0
		self._parse_time = 0

		#self._parse_lock = threading.Lock()
		self._parse_thread = None


		self._near_inds = []

		self._op_ind = -1

		if macro_line != None:
			self._raw_line = macro_line
			#print(line_number, macro_line, self.get_raw())

		# turn full file path into directory path and file name
		if self._file != None: 
			self._file = self._file.lstrip().rstrip()  # remove excess whitespace on ends of file path
			self.set_file_attr(self._file)             # set file name and directory


		_start = util.get_time()
		# whitespace cleaned, trimmed, and comment-removed line
		self._cleaned_line = self.clean_line(raw_line.replace(":",";").split(';')[0])
		self._clean_time = util.get_time() - _start

		_start = util.get_time()
		# line turned into its individual components
		self._parsed_line = self.parse_line(self._cleaned_line)
		self._parse_time = util.get_time() - _start





	def set_file_attr(self, file=None):
		"""Turn a file name into a file direrctory and file name"""

		if file == None:
			file = self._file

		# convert file path to Windows style file path
		file = file.replace("\\", "/")

		if not "/" in file:
			# file in same directory
			self._file_name = file
			self._file_path = ""
			return

		# split up path by directories
		split_path = file.split("/")


		# if file is not in the same directory
		self._file_path = "/".join(split_path[:-1]) + "/" # file directory is everything up until file name

		# file name is last part of file path
		self._file_name = split_path[-1]

		# if file path not present, set empty
		if self._file_path == None:
			self._file_path = ""





	def clean_line(self, raw_line=None):
		"""Turns all single/multi whitespace into spaces, trims line, and converts symbols to proper spacing"""

		if raw_line == None:
			raw_line = self._raw_line
		elif self._raw_line != raw_line:
			self._raw_line = raw_line

		if raw_line == "": return "" # break quickly, saves a bit of runtime

		RAW_IN = raw_line


		# parse quotes first
		quoted_texts = []
		curr_quote = ""
		quote_ind = 0
		HAS_QUOTES = False
		if "\"" in raw_line or "\'" in raw_line: HAS_QUOTES = True

		raw_copy = ""

		in_quote = False
		in_apo = False
		ind = 0
		if HAS_QUOTES:
			while ind < len(raw_line):
				if raw_line[ind] == "\"":
					if not in_apo:
						if in_quote:
							curr_quote += "\""
							quoted_texts.append(curr_quote)
							curr_quote = ""
							raw_copy += "ASCII_QUOTE_" + str(quote_ind)
							quote_ind += 1
							in_quote = False
						else:
							in_quote = True
							curr_quote += "\""
							#ind += 1

				elif raw_line[ind] == "\'":
					if not in_quote:
						if in_apo:
							curr_quote += "\'"
							quoted_texts.append(curr_quote)
							curr_quote = ""
							raw_copy += "ASCII_QUOTE_" + str(quote_ind)
							quote_ind += 1
							in_apo = False
						else:
							in_apo = True
							curr_quote += "\'"
							#ind += 1
				else:
					char = raw_line[ind]

					if in_apo or in_quote:
						if char == " ":
							char = "\x01"
						curr_quote += char
					else:
						raw_copy += char

				ind += 1 

			if in_apo or in_quote:
				raise LineException(self.get_line_num(), RAW_IN + "\n\nUnbalanced string identifiers.", self.get_file_name())

			raw_line = raw_copy


		raw_line = ' '.join(raw_line.split())      # clean whitespace

		raw_line = raw_line.replace("<<", util.BSL_CHAR).replace(">>", util.BSR_CHAR)   # convert bit shift operators to single chars 


		## convert address constant designators to raw value, while avoiding solo $'s
		#if len(raw_line) > 0:
		#	raw_line = raw_line[:-1].replace(" $", "") + raw_line[-1:]   


		# clean the expressions up, in order to parse by symbols later
		for sym in util.PARSING_SYMBOLS:
			if sym in raw_line:
				raw_line = raw_line.replace(sym.upper(), " " + sym.upper() + " ")           # space out parsing symbols (in uppercase)

				if sym.upper() != sym.lower():
					# if the symbol is a letter (for some reason)
					raw_line = raw_line.replace(sym.lower(), " " + sym.lower() + " ")       # space out parsing symbols (in lowercase)


		# convert bank and related symbols
		s = raw_line.split(" ")
		s_out = []
		for i in range(len(s)):
			item = s[i]
			i_lower = item.lower()
			#i1_lower = i_lower[1:]
			if i_lower == "bank":# or (item[1:].lower() == "bank" and item[0] in util.TYPE_SYMBOLS):
				s_out.append(util.BANK_CHAR)
			elif i_lower == "offset":# or (item[1:].lower() == "offset" and item[0] in util.TYPE_SYMBOLS):
				s_out.append(util.OFFSET_CHAR)
			elif i_lower == "high":# or (item[1:].lower() == "high" and item[0] in util.TYPE_SYMBOLS):
				s_out.append(util.HIGH_CHAR)
			elif i_lower == "low":# or (item[1:].lower() == "low" and item[0] in util.TYPE_SYMBOLS):
				s_out.append(util.LOW_CHAR)
			else:
				s_out.append(item)

		raw_line = ' '.join(s_out)




		# clean up data type symbols, but ONLY if they appear at beginning of item
		for sym in util.TYPE_SYMBOLS:
			raw_line = raw_line.replace(" " + sym.upper(), " " + sym.upper() + " ")     # space out type symbols (in uppercase)

			if sym.upper() != sym.lower():
				# if the symbol is a letter (for some reason)
				raw_line = raw_line.replace(" " + sym.lower(), " " + sym.lower() + " ")       # space out type symbols (in lowercase)


		#raw_line = ' '.join(raw_line.split())      # clean whitespace again just in case

		raw_line = raw_line.replace("\"", " \" ").replace("\'", " \' ")


		if HAS_QUOTES:

			for q in range(len(quoted_texts)):
				q_ind = (len(quoted_texts) - 1) - q
				quote = quoted_texts[q_ind]
				raw_line = raw_line.replace("ASCII_QUOTE_" + str(q_ind), quote)
				


		# parse ascii characters
		ind = 0
		raw_copy = ""
		in_quote = False
		in_apo = False
		item_is_first = True

		if HAS_QUOTES:
		
			while ind < len(raw_line):
				if raw_line[ind] == "\"":
					if not in_apo:
						if in_quote:
							in_quote = False
						else:
							in_quote = True
							item_is_first = True
							#ind += 1

				elif raw_line[ind] == "\'":
					if not in_quote:
						if in_apo:
							in_apo = False
						else:
							in_apo = True
							item_is_first = True
							#ind += 1
				else:
					
					if in_apo or in_quote:
						if not item_is_first:
							raw_copy += ","
						raw_copy += " \'"
					
					char = raw_line[ind]
					
					if char == " ":
						if in_apo or in_quote:
							char = "\x01"

					raw_copy += char

					if in_apo or in_quote:
						raw_copy += "\' "
					item_is_first = False


				ind += 1 

			raw_line = " ".join(raw_copy.split())
		else:
			raw_line = " ".join(raw_line.split())

		
		'''
		if "\'" in raw_line:
			print(raw_line)
			raise Exception() # just to compile quicker
		'''

		return raw_line





	def parse_line(self, cleaned_line=None, is_complete_line=True, pre_parsed=None):
		"""Turns a cleaned up line into its parsed components, ready for the assembler to handle"""

		#if self._parse_thread != None:
		#	self._parse_thread.join()
		#	self._parse_thread = None

		if pre_parsed == None:
			if cleaned_line == None: cleaned_line = self._cleaned_line
				
			if cleaned_line == "": return []
			
			LINE = cleaned_line.split(" ") # split into individual components
		else:
			LINE = pre_parsed

		LINE_LEN = len(LINE)


		# parsing stack
		parse_stack = []

		ind = 0

		if is_complete_line:
			# if not a reserved word at beginning of line, then it is a label

			item = LINE[0]

			L0_LOWER = item

			if item == item.lower() or item == item.upper():
				L0_LOWER = item.lower()

			if not L0_LOWER in util.RESERVED_FLAT:

				if LINE[0][-1] == "$":
					parse_stack.append({"type": util.DATA_TYPES.LABEL, "label": LINE[0], "varname": LINE[0], "is_near": True})   # indicate this is a label, so parser doesnt mess with item
				else:
					parse_stack.append({"type": util.DATA_TYPES.LABEL, "label": LINE[0], "varname": LINE[0]})   # indicate this is a label, so parser doesnt mess with item
				ind += 1

			elif L0_LOWER in util.CONDITIONAL_SYMBOLS:
				# is a conditional statement that affects assembler process

				if L0_LOWER == "if":
					

					sub_parsed = self.parse_line(pre_parsed=LINE[ind+1:], is_complete_line=False)


					eval_str = ""
					first = True
					for p in sub_parsed:

						if p["type"] == util.DATA_TYPES.VALUE:
							if not first: eval_str += " "
							first = False

							eval_str += str(p["value"])
						elif p["type"] == util.DATA_TYPES.OPERATOR:
							if not first: eval_str += " "
							first = False

							eval_str += str(p["operator"])

						elif p["type"] == util.DATA_TYPES.VARIABLE:
							if not first: eval_str += " "
							first = False

							eval_str += str(p["varname"])

						else:
							raise LineException(self.get_line_num(), self.get_raw() + "\n\nUnidentified parameter in IF statement.", self.get_file_name())


					#condition = {"type": util.DATA_TYPES.CONDITION, "eval_str": eval_str}


					parse_stack.append({"type": util.DATA_TYPES.CONDITIONAL_IF, "condition": eval_str})




					ind += 2
				elif L0_LOWER == "endif":
					parse_stack.append({"type": util.DATA_TYPES.CONDITIONAL_ENDIF})
					ind += 1
				elif L0_LOWER == "else":
					parse_stack.append({"type": util.DATA_TYPES.CONDITIONAL_ELSE})
					ind += 1

			elif L0_LOWER in util.INCLUDE_SYMBOLS:
				# is an include statement, so rest of line is a file

				filename = "".join(LINE[1:]).replace("\"", "").replace("\'", "")

				parse_stack.append({"type": util.DATA_TYPES.INCLUDE, "filename": filename})

				ind += LINE_LEN

				self._is_include_line = True

			elif L0_LOWER in util.GLOBAL_SYMBOLS:
				# is a global variable identifier


				#for item in LINE[1:]:
				for i in range(1, LINE_LEN):
					item = LINE[i]
					#if not (item.lower() in util.SEPARATOR_SYMBOLS):
					if not (item in util.SEPARATOR_SYMBOLS):
						parse_stack.append({"type": util.DATA_TYPES.GLOBAL, "varname": item})

				ind += LINE_LEN


			elif L0_LOWER in util.EXTERNAL_SYMBOLS:
				# is an external variable identifier

				#for item in LINE[1:]:
				for i in range(1, LINE_LEN):
					item = LINE[i]
					#if not (item.lower() in util.SEPARATOR_SYMBOLS):
					if not (item.lower() in util.SEPARATOR_SYMBOLS):
						parse_stack.append({"type": util.DATA_TYPES.EXTERNAL, "varname": item})

				ind += LINE_LEN

	



		else:
			#print("IN SUB LINE: " + cleaned_line)
			pass

		
		ignore_stack_reg = False


		while ind < LINE_LEN: # iterate through LINE to parse

			item = LINE[ind]

			item_lower = item

			if item.lower() == item or item.upper() == item:
				item_lower = item.lower()

			if not (item_lower in util.RESERVED_FLAT):


				if util.isValue(item):
					# item is a raw value, so turn it into one
					parse_stack.append({"type": util.DATA_TYPES.VALUE, "value": util.parseValue(item)})

				else:
					# item is a variable

					if item[-1] == "$":
						# "near" variable

						size = 2
						if parse_stack != []:
							if parse_stack[-1]["type"] == util.DATA_TYPES.OPCODE:
								if parse_stack[-1]["opcode"].lower() in BR_OPS1: #{"bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs"}:
									size = 1

							if parse_stack[-1]["type"] == util.DATA_TYPES.TYPE:
								size = 0

						parse_stack.append({"type": util.DATA_TYPES.VARIABLE, "varname": item, "label": item, "vartype": util.DATA_TYPES.NEARVAR, "size": size, "is_near": True})



					else:
						# normal variable name, possibly

						is_normal = True

						size = 0
						if parse_stack != []:
							if parse_stack[-1]["type"] == util.DATA_TYPES.OPCODE:
								if parse_stack[-1]["opcode"].lower() in BR_OPS2:#{"bcc", "blt", "bcs", "bge", "beq", "bmi", "bne", "bpl", "bra", "bvc", "bvs", "brl", "per"}:
									# "near" variable 
									is_normal = False

									size = 1

									if parse_stack[-1]["opcode"].lower() in BR_OPS3: #{"brl", "per"}
										size = 2

									if parse_stack[-1]["type"] == util.DATA_TYPES.TYPE:
										size = 0

									parse_stack.append({"type": util.DATA_TYPES.VARIABLE, "varname": item, "label": item, "vartype": util.DATA_TYPES.NEARVAR, "size": size, "is_near": True})


						if is_normal:
							if parse_stack != []:
								if parse_stack[-1]["type"] != util.DATA_TYPES.TYPE:
									size = 2
							parse_stack.append({"type": util.DATA_TYPES.VARIABLE, "varname": item, "label": item, "vartype": util.DATA_TYPES.NORMALVAR, "size": size})
							

			elif item_lower in util.OPCODE_SYMBOLS:
				# item is an opode mnemonic
				parse_stack.append({"type": util.DATA_TYPES.OPCODE, "opcode": item_lower, "size": 1, "reg": util.OPCODE_REGS[item_lower]})
				self._is_op = True
				self._op_ind = ind


			elif item_lower in UNSTABLE_SYMBOLS:
				# if unsure about status of symbol


				if item_lower =="(" or item_lower == "[":
					# if ambiguous separator

					#print("STACK BEFORE: " + str(parse_stack))
					#if parse_stack == []:
					#	raise LineException(self.get_line_num(), "Ambiguous parenthesis\n"+ self.get_raw(), self.get_file_name())


					if (not is_complete_line and parse_stack == []) or (parse_stack[-1]["type"] == util.DATA_TYPES.OPCODE or parse_stack[-1]["type"] == util.DATA_TYPES.EQU):

						was_op = False
						if parse_stack != [] and parse_stack[-1]["type"] == util.DATA_TYPES.OPCODE:
							was_op = True

						off = 1
						numparens = 1
						ended = False
						#LINE_LEN = len(LINE)

						# parse where end of this paren is
						while ind+off < LINE_LEN:

							if item_lower == "(":
								if LINE[ind+off] == "(":
									numparens += 1
								elif LINE[ind+off] == ")":
									numparens -= 1

							elif item_lower == "[":
								if LINE[ind+off] == "[":
									numparens += 1
								elif LINE[ind+off] == "]":
									numparens -= 1

							if numparens == 0:
								ended = True
								break

							off += 1

						# unbalanced parens
						if not ended:
							raise LineException(self.get_line_num(), self.get_raw() + "\n\nUnbalanced parentheses", self.get_file_name())

						#print("STACK: " + str(parse_stack))

						sub_parsed = self.parse_line(pre_parsed=LINE[ind+1:ind+off], is_complete_line=False)

						
						
						if was_op:
							if item_lower == "(":
								parse_stack.append({"type": util.DATA_TYPES.INDIRECT_START})
							elif item_lower == "[":
								parse_stack.append({"type": util.DATA_TYPES.INDIRECT_LONG_START})
						else:
							parse_stack.append({"type": util.DATA_TYPES.OPERATOR, "operator": "("})
							


						
						for p in sub_parsed:
							parse_stack.append(p)


						if was_op:
							if item_lower == "(":
								parse_stack.append({"type": util.DATA_TYPES.INDIRECT_END})
							elif item_lower == "[":
								parse_stack.append({"type": util.DATA_TYPES.INDIRECT_LONG_END})
						else:
							parse_stack.append({"type": util.DATA_TYPES.OPERATOR, "operator": ")"})

						#print("AFTER: " + str(parse_stack))




						ind += off
						



					else:
						# just a priority paren
						parse_stack.append({"type": util.DATA_TYPES.OPERATOR, "operator": "("})


				elif item_lower == "+" or item_lower == "-":

					isarith = True # default is arithetic symbol unless conditions met

					if item_lower == "-" or item_lower == "+":
						# check to see if this is a pos/neg or if it is an arithmetic +/-

						# is pos/neg iff :
						# #1. next item is a value
						# 2. prev item is NOT a value, variable, expression
						# 3. if prev item is an operator, must not be closed paren
						# or if start of expression
						####if ind != len(LINE)-1 and ind != 0:
						if ind != LINE_LEN-1 and ind != 0:
							#if util.isValue(LINE[ind+1]): # next item is value 
							if parse_stack[-1]["type"] != util.DATA_TYPES.VALUE:  # prev item not value
								if parse_stack[-1]["type"] != util.DATA_TYPES.VARIABLE:  # prev item not variable
									if parse_stack[-1]["type"] != util.DATA_TYPES.EXPRESSION:  # prev item not expression
										# fits all criterion to be pos/neg
										isarith = False

										if parse_stack[-1]["type"] == util.DATA_TYPES.OPERATOR:
											# prev item is an operator, check if it is a closed parenthesis

											if parse_stack[-1]["operator"] == ")":
												# if prev item is closed paren, must be an operator
												isarith = True

											if parse_stack[-1]["operator"] == "]":
												# if prev item is closed paren, must be an operator
												isarith = True

										

						else:
							isarith = False






						if not isarith:
							'''
							# base value is next 
							if util.isValue(LINE[ind+1]):
								val = util.parseValue(LINE[ind+1])

								if item == "-": 
									# if pos, no change is needed
									# however, if neg, need to turn to negative value 
									val = -1*val


								parse_stack.append({"type": util.DATA_TYPES.VALUE, "value": val})

								ind += 1 # skip over next item
							else:
								# negative of a variable, so push -1 * variable
								parse_stack.append({"type": util.DATA_TYPES.VALUE, "value": -1})
								parse_stack.append({"type": util.DATA_TYPES.OPERATOR, "operator": "*"})
							'''

							if item_lower == "-":
								parse_stack.append({"type": util.DATA_TYPES.VALUE, "value": -1})
								parse_stack.append({"type": util.DATA_TYPES.OPERATOR, "operator": "*"})
							elif item_lower == "+":
								parse_stack.append({"type": util.DATA_TYPES.VALUE, "value": 1})
								parse_stack.append({"type": util.DATA_TYPES.OPERATOR, "operator": "*"})

						else:
							# is an arithmetic op
							parse_stack.append({"type": util.DATA_TYPES.OPERATOR, "operator": item})






			elif item_lower in util.ARITHMETIC_SYMBOLS:
				# item is an operator
				parse_stack.append({"type": util.DATA_TYPES.OPERATOR, "operator": item})


			elif item_lower in util.EQU_SYMBOLS:
				# item is an identifier for an EQU identifier
				try:
					var = parse_stack.pop()["varname"]
					parse_stack.append({"type": util.DATA_TYPES.EQU, "varname": var, "label": var})
				except:
					raise LineException(self.get_line_num(), self.get_raw() + "\n\nEQU prev does not have varname.", self.get_file_name())

				self._is_equ = True

				#print(str(LINE), str(parse_stack))


			elif item_lower in util.DATA_SYMBOLS:
				# item is an identifier for byte data


				if item_lower in util.HEX_LIST_SYMBOLS:
					#LINE_LEN = len(LINE)
					for x in range(ind+1, LINE_LEN):
						if LINE[x] != ',':
							bad_data = False

							# is only good data if it is a hex literal. If cannot be interpreted this way, bad data.
							try:
								L = LINE[x]
								if LINE[x][-1].lower() == 'h':
									L = L[:-1]
								int(L, 16)
							except ValueError:
								bad_data = True


							if bad_data:
								if util.isValue(LINE[x], WARN=False):
									bad_data = False

							if not bad_data:
								# just convert the value into one without the designator to make it easier.
								if LINE[x][-1].lower() == 'h':
									LINE[x] = LINE[x][:-1]


							else:
								raise LineException(self.get_line_num(), self.get_raw() + "\n\nInvalid HEX literal: " + str(LINE[x]) + "\nIf using a variable, use BYTE list instead.", self.get_file_name())

							# if hex literal, convert into byte list format
							if LINE_LEN > 2 and int(LINE[x], 16) > 255:
								print("[DEBUG]: HEX LINE ITEM LARGER THAN BYTE \n", LINE)
							LINE[x] = "0" + LINE[x] + "h"

					# for now, I have not seen any format that uses a different 
					# case other than hex as byte sized. Update this if that
					# changes.
					LINE[0] = "BYTE"

					datatype = util.DATA_TYPES.DBYTE


				elif item_lower in util.BIN_LIST_SYMBOLS:
					#LINE_LEN = len(LINE)
					for x in range(ind+1, LINE_LEN):
						if LINE[x] != ',':
							bad_data = False

							# is only good data if it is a hex literal. If cannot be interpreted this way, bad data.
							try:
								L = LINE[x]
								if LINE[x][-1].lower() == 'b':
									L = L[:-1]
								int(L, 2)
							except ValueError:
								bad_data = True
							
							if bad_data:
								if util.isValue(LINE[x], WARN=False):
									bad_data = False
								#elif util.isValue("0" + LINE[x]): # dont need this
								#	bad_data = False

							if not bad_data:
								# just convert the value into one without the designator to make it easier.
								if LINE[x][-1].lower() == 'b':
									LINE[x] = LINE[x][:-1]


							else:
								raise LineException(self.get_line_num(), self.get_raw() + "\n\nInvalid BIN literal: " + str(LINE[x]) + "\nIf using a variable, use BYTE list instead.", self.get_file_name())

							# if hex literal, convert into byte list format
							if LINE_LEN > 8 and int(LINE[x], 2) > 255:
								print("[DEBUG]: BIN LINE ITEM LARGER THAN BYTE \n", LINE)
							LINE[x] = "0" + LINE[x] + "b"

					# for now, I have not seen any format that uses a different 
					# case other than bin as byte sized. Update this if that
					# changes.
					LINE[0] = "BYTE"

					datatype = util.DATA_TYPES.DBYTE


				elif item_lower in util.BYTE_SYMBOLS:
					datatype = util.DATA_TYPES.DBYTE
				elif item_lower in util.WORD_SYMBOLS:
					datatype = util.DATA_TYPES.DWORD
				elif item_lower in util.LONG_SYMBOLS:
					datatype = util.DATA_TYPES.DLONG

				self._is_data_line = True

				parse_stack.append({"type": datatype})


			
			elif item_lower in util.REGISTER_SYMBOLS: # and (not ignore_stack_reg):
				# item is a register

				reg = util.NONE
				if item_lower in util.REGA_SYMBOLS:
					reg = "a"
				elif item_lower in util.REGX_SYMBOLS:
					reg = "x"
				elif item_lower in util.REGY_SYMBOLS:
					reg = "y"
				elif item_lower in util.REGS_SYMBOLS:
					reg = "s"

				
				if reg == "s":
					if len(parse_stack) >= 4 and (parse_stack[-4]["type"] == util.DATA_TYPES.OPCODE or parse_stack[-4]["type"] == util.DATA_TYPES.INDIRECT_START):
						# if this is a register designator for the stack
						
						if parse_stack[-3]["type"] == util.DATA_TYPES.TYPE and parse_stack[-3]["valtype"] == "dp":
							parse_stack[-3] = {"type": util.DATA_TYPES.TYPE, "valtype": "sr", "size": 1}
						else:
							parse_stack.insert(len(parse_stack) - 3, {"type": util.DATA_TYPES.TYPE, "valtype": "sr", "size": 1})

					elif len(parse_stack) >= 3 and parse_stack[-3]["type"] == util.DATA_TYPES.OPCODE:
						if parse_stack[-2]["type"] == util.DATA_TYPES.TYPE and parse_stack[-2]["valtype"] == "dp":
							parse_stack[-2] = {"type": util.DATA_TYPES.TYPE, "valtype": "sr", "size": 1}
						else:
							parse_stack.insert(len(parse_stack) - 2, {"type": util.DATA_TYPES.TYPE, "valtype": "sr", "size": 1})

					else:
						raise LineException(self.get_line_num(), self.get_raw() + "\n\nStack register is a reserved value.", self.get_file_name())

				if reg != util.NONE:
					parse_stack.append({"type": util.DATA_TYPES.REGISTER, "register": reg})





			elif item_lower in util.PROCESSOR_SYMBOLS:
				# item is an identifier for a processor flag
				parse_stack.append({"type": util.DATA_TYPES.PFLAG, "flag": item_lower})

			elif item_lower in util.TYPE_SYMBOLS:
				# item is a designator for a type

				itemtype = util.NONE
				func_char = False

				if item_lower == "<":
					itemtype = "dp"
					size = 1
				elif item_lower == "!":
					itemtype = "addr"
					size = 2
				elif item_lower == ">":
					itemtype = "long"
					size = 3
				elif item_lower == "#":
					itemtype = "const"
					size = None

				elif item_lower == util.BANK_CHAR:
					itemtype = "bank"
					size = None #2
					func_char = True
				elif item_lower == util.OFFSET_CHAR:
					itemtype = "offset"
					size = None #2
					func_char = True
				elif item_lower == util.HIGH_CHAR:
					itemtype = "high"
					size = None #1
					func_char = True
				elif item_lower == util.LOW_CHAR:
					itemtype = "low"
					size = None #1
					func_char = True
				elif item_lower == "$":
					itemtype = "constaddr"
					size = None


				#if func_char and parse_stack != []:
				#	if parse_stack[-1]["type"] == util.DATA_TYPES.TYPE: parse_stack.pop()
				

				#if item_lower in {util.BANK_CHAR, util.OFFSET_CHAR, util.HIGH_CHAR, util.LOW_CHAR}:

				


				'''
				is_equ = False
				if itemtype == "constaddr":
					if parse_stack != []:
						if parse_stack[-1]["type"] == util.DATA_TYPES.EQU:
							top = parse_stack.pop()
							if parse_stack != []:
								if parse_stack[-1] == top:
									parse_stack = parse_stack[:-1]

							parse_stack.append({"type": util.DATA_TYPES.LABEL, "varname": top["varname"], "label": top["varname"], "is_near": True})
							is_equ = True

						elif parse_stack[-1]["type"] == util.DATA_TYPES.ORG:
							itemtype = None
				'''
				 
				'''
				if not is_equ:
					if itemtype != util.NONE:
						if itemtype != "constaddr":
							parse_stack.append({"type": util.DATA_TYPES.TYPE, "valtype": itemtype, "size": size})
						else:
							#near_label = "NEAR_VAR" + str(self.get_line_num()) + "$"
							near_label = "_NEAR_VAR" + str(self.get_line_num()) + "LEVEL" + str(self.get_include_level())


							self._uses_near_var = True


							LINE[ind] = near_label

							ind -= 1
				'''

				if itemtype != util.NONE:
					if itemtype != "constaddr":
						parse_stack.append({"type": util.DATA_TYPES.TYPE, "valtype": itemtype, "size": size})
					else:
						#near_label = "NEAR_VAR" + str(self.get_line_num()) + "$"
						#near_label = "FILE_" + str(self._file_num) + "_NEAR_VAR" + str(self.get_line_num()) + "LEVEL" + str(self.get_include_level())


						self._uses_near_var = True

						self._force_lis = True

						#self._near_ind = ind


						LINE[ind] = "#NEAR_VAR$"

						ind -= 1


			elif item_lower in util.SEPARATOR_SYMBOLS:
				# item is a separator, pretty simple
				parse_stack.append({"type": util.DATA_TYPES.SEPARATOR})

			elif item_lower in util.GLOBAL_SYMBOLS:
				# item is an identifier for a global variable
				parse_stack.append({"type": util.DATA_TYPES.GLOBAL})

			elif item_lower in util.EXTERNAL_SYMBOLS:
				# item is an identifier for an external variable
				parse_stack.append({"type": util.DATA_TYPES.EXTERNAL})

			elif item_lower in util.INCLUDE_SYMBOLS:
				# item is an identifier for an included file
				parse_stack.append({"type": util.DATA_TYPES.INCLUDE})

			elif item_lower in util.MACRO_SYMBOLS:
				# item is an identifier for a macro

				if parse_stack == []:
					raise LineException(self.get_line_num(), self.get_raw() + "\n\nMacro is not named.", self.get_file_name())

				if not (parse_stack[-1]["type"] in (util.DATA_TYPES.LABEL, util.DATA_TYPES.VARIABLE)):
					#print(parse_stack)
					raise LineException(self.get_line_num(), self.get_raw() + "\n\nImproper format for macro.", self.get_file_name())

				top = parse_stack[-1]
				parse_stack = parse_stack[:-1]
				parse_stack.append({"type": util.DATA_TYPES.MACRO, "varname": top["varname"], "label": top["label"]})

				# item means line is a definition of a macro
				self._is_macro_def = True

			elif item_lower in util.MACRO_LOCAL_SYMBOLS:
				# item is an identifier for an list of local macro variables
				parse_stack.append({"type": util.DATA_TYPES.MACRO_LOCAL})
				self._is_macro = True

			elif item_lower in util.END_MACRO_SYMBOLS:
				# item is an identifier for an ENDM instruction
				parse_stack.append({"type": util.DATA_TYPES.END_MACRO})
				self._is_macro_end = True

			elif item_lower in util.SECTION_SYMBOLS:
				# item is an identifier for a section
				parse_stack.append({"type": util.DATA_TYPES.SECTION})

				if ind+1 < LINE_LEN:
					parse_stack[-1]["SECTION_CLASS"] = LINE[ind+1]

					ind += 1
				else:
					parse_stack[-1]["SECTION_CLASS"] = "REL"

				self._is_section = True

			elif item_lower in util.COMN_SYMBOLS:
				# item is an identifier for a COMN section
				lbl = "COMN"
				parse_stack.append({"type": util.DATA_TYPES.LABEL, "label": lbl, "varname": lbl})
				parse_stack.append({"type": util.DATA_TYPES.SECTION})

				if ind+1 < LINE_LEN:
					parse_stack[-1]["SECTION_CLASS"] = LINE[ind+1]

					ind += 1
				else:
					parse_stack[-1]["SECTION_CLASS"] = "REL"

				self._is_section = True

			elif item_lower in util.GROUP_SYMBOLS:
				# item is an identifier for a group
				parse_stack.append({"type": util.DATA_TYPES.GROUP})

				if ind+1 < LINE_LEN:
					parse_stack[-1]["SECTION_GROUP"] = LINE[ind+1]

					ind += 1

			elif item_lower in util.ORG_SYMBOLS:
				# item is an identifier for an org specifier
				lbl = self._file_name.split(".")[0]
				parse_stack.append({"type": util.DATA_TYPES.LABEL, "label": lbl, "varname": lbl})
				parse_stack.append({"type": util.DATA_TYPES.ORG})

				if LINE[ind+1].lower() == "$":
					ind += 1

				self._is_section = True


				#parse_stack[-1]["offset"] = util.parseValue(LINE[ind+1].replace("h", "").replace("H", "") + "h")
				#ind += 1

			elif item_lower in util.DBANK_SYMBOLS:
				# item is an identifier for a dbank instruction
				parse_stack.append({"type": util.DATA_TYPES.DATA_BANK})

				'''
				sub_parsed = self.parse_line(" ".join(LINE[ind+1:]), is_complete_line=False)

				parse_stack[-1]["bank"] = []

				for p in sub_parsed:
					parse_stack[-1]["bank"].append(p)

				ind += len(sub_parsed)
				'''

			elif item_lower in util.DPAGE_SYMBOLS:
				# item is an identifier for a dpage instruction
				parse_stack.append({"type": util.DATA_TYPES.DATA_PAGE})

				'''
				sub_parsed = self.parse_line(" ".join(LINE[ind+1:]), is_complete_line=False)

				parse_stack[-1]["page"] = []

				for p in sub_parsed:
					parse_stack[-1]["page"].append(p)

				ind += len(sub_parsed)
				'''

			elif item_lower in util.END_SYMBOLS:
				# item is an identifier for an END instruction
				parse_stack.append({"type": util.DATA_TYPES.END})
				self._is_end = True

			elif item_lower in util.PSEG_SYMBOLS:
				# item is an identifier for a PROGRAM section
				lbl = "P" + self._file_name.split(".")[0]
				parse_stack.append({"type": util.DATA_TYPES.LABEL, "label": lbl, "varname": lbl})
				parse_stack.append({"type": util.DATA_TYPES.SECTION})

				if ind+1 < LINE_LEN:
					parse_stack[-1]["SECTION_CLASS"] = LINE[ind+1]

					ind += 1
				else:
					parse_stack[-1]["SECTION_CLASS"] = "REL"

				self._is_section = True

			elif item_lower in util.DSEG_SYMBOLS:
				# item is an identifier for a DATA section
				lbl = "D" + self._file_name.split(".")[0]
				parse_stack.append({"type": util.DATA_TYPES.LABEL, "label": lbl, "varname": lbl})
				parse_stack.append({"type": util.DATA_TYPES.SECTION})

				if ind+1 < LINE_LEN:
					parse_stack[-1]["SECTION_CLASS"] = LINE[ind+1]

					ind += 1
				else:
					parse_stack[-1]["SECTION_CLASS"] = "REL"

				self._is_section = True

			elif item_lower in util.STORAGE_DIRECTIVE_SYMBOLS:
				# item is a storage directive identifier

				try:
					var = parse_stack.pop()["varname"]
					parse_stack.append({"type": util.DATA_TYPES.STORAGE_DIRECTIVE, "storage_size": 0, "varname": var, "label": var})
				except:
					raise LineException(self.get_line_num(), self.get_raw() + "\n\nStorage Directive prev does not have varname.", self.get_file_name())

			elif item_lower in util.OTHER_SYMBOLS:
				# item is a known but unimplemented instruction
				pass
			else:
				raise LineException(self.get_line_num(), self.get_raw() + "\n\nUnimplemented symbol: '" + str(item) + "'.", self.get_file_name())






			# mercy its over thank god
			ind += 1
			ignore_stack_reg = False


		ind = 0
		ps_len = len(parse_stack)
		while ind < ps_len:
			if not ("size" in parse_stack[ind]):
				parse_stack[ind]["size"] = 0

			if self._uses_near_var and parse_stack[ind]["type"] == util.DATA_TYPES.VARIABLE:
				if is_complete_line:
					if parse_stack[ind]["varname"] == "#NEAR_VAR$":
						#if ind in self._near_inds: raise LineException(self.get_line_num(), "MULTIPLE NEAR INDS. CAREFUL!\n" + self.get_raw(), self.get_file_name())
						self._near_inds.append(ind)

			elif parse_stack[ind]["type"] == util.DATA_TYPES.LABEL:
				if not "is_near" in parse_stack[ind]:
					parse_stack[ind]["is_near"] = False

			elif parse_stack[ind]["type"] == util.DATA_TYPES.STORAGE_DIRECTIVE:
				for i in range(ind+1, len(parse_stack)):
					parse_stack[i]["size"] = 0

			elif parse_stack[ind]["type"] == util.DATA_TYPES.ORG:
				failed = False
				try: parse_stack[ind+1]["size"] = 0
				except: failed = True

				if failed: raise LineException(self.get_line_num(), self.get_raw() + "\n\nORG symbol has no offset.", self.get_file_name())

			ind += 1

		'''
		if self._uses_near_var:
			ind = 0
			for p in parse_stack:
				if p["type"] == util.DATA_TYPES.VARIABLE:
					if p["varname"] == "#NEAR_VAR$":
						self._near_ind = ind
						break
				ind += 1
		'''





		#if self.get_file_name() == "BGMove.asm" and self.get_line_num() == 198:
		#	print(parse_stack)
		
		#if is_complete_line: self._parse_lock.release()

		return parse_stack


	def get_parsed(self):
		if self._parse_thread != None:
			self._parse_thread.join()
			self._parse_thread = None

		return self._parsed_line
		
	
	def set_parsed(self, P):
		#self._parsed_line = [p for p in P]

		if self._parse_thread != None:
			self._parse_thread.join()
			self._parse_thread = None

		self._parsed_line = P

		self.ensure_size()
		#self._parse_thread = threading.Thread(target=self.ensure_size, args=())
		#self._parse_thread.start()

	def ensure_size(self):
		for p in range(len(self._parsed_line)):
			if not ("size" in self._parsed_line[p]):
				self._parsed_line[p]["size"] = 0



		



	def get_file_path(self):
		return self._file_path

	def get_file_name(self):
		return self._file_name

	def get_line_num(self):
		return self._line_number

	def set_offset(self, o):
		self._offset = o

	def get_offset(self):
		return self._offset

	def get_raw(self):
		return self._raw_line.replace(":",";").split(";")[0]

	def get_clean_line(self):
		return self._cleaned_line.replace(":",";").split(";")[0]

	def set_bytes(self, b):
		self._data_bytes = b

	def get_bytes(self):
		return self._data_bytes


	def set_is_not_code(self):
		self._is_code = False

	def set_is_code(self):
		self._is_code = True

	def is_code(self):
		return self._is_code


	def set_include_level(self, level):
		self._include_lvl = level

	def get_include_level(self):
		return self._include_lvl

	def is_included(self):
		if self._include_lvl > 0:
			return True
		else:
			return False

	def set_already_included(self):
		self._already_included = True

	def already_included(self):
		return self._already_included

	def is_macro(self, is_macro_line):
		self._is_macro = is_macro_line

	def get_is_macro(self):
		return self._is_macro

	def is_macro_def(self, is_macro_def_line):
		self._is_macro_def = is_macro_def_line

	def get_is_macro_def(self):
		return self._is_macro_def

	def is_macro_end(self, is_macro_end_line):
		self._is_macro_end = is_macro_end_line

	def get_is_macro_end(self):
		return self._is_macro_end

	def get_uses_near_var(self):
		return self._uses_near_var

	def get_is_end(self):
		return self._is_end

	def is_op(self):
		return self._is_op

	def get_op_ind(self):
		return self._op_ind

	def set_hide_lis(self):
		self._show_lis = False

	def set_show_lis(self):
		self._show_lis = True

	def get_is_hidden(self):
		return not self._show_lis

	def set_force_lis(self):
		self._force_lis = True

	def get_force_lis(self):
		return self._force_lis

	def get_file_num(self):
		return self._file_num

	def get_near_inds(self):
		return self._near_inds

	def get_is_equ(self):
		return self._is_equ

	def get_is_section(self):
		return self._is_section

	def is_include_line(self):
		return self._is_include_line

	def is_data(self):
		return self._is_data_line








