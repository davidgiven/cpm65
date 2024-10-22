



class Error(Exception):
	"""Base class for other exceptions"""

	def __init__(self, msg=""):
		self.msg = msg

	def __str__(self):
		return self.msg



class LineException(Error):
	"""General exception for errors in asm code
	
	Attributes:
		line_num -- line number where error occured
		line_ind -- index of character in line where error occured
		msg -- error message
		file -- file that error occured in
	"""

	def __init__(self, line_num=-1, msg=None, file=None, line_ind=-1):
		self.line_num = line_num
		self.line_ind = line_ind
		self.msg = msg
		self.file = file
		self.err_msg = ""

		err_msg = "Error"

		if self.file != None:
			err_msg += " in " + self.file

		if self.line_num != -1:
			err_msg += " at line " + str(self.line_num)

			if self.line_ind != -1:
				err_msg += ", index " + str(self.line_ind)

		if self.msg != None:
			err_msg += ":\n"

			if self.line_num != -1:
				err_msg += str(self.line_num) + ":"

			err_msg += "\t" + str(self.msg).lstrip()

		#super().__init__(err_msg)
		self.err_msg = err_msg

	def __str__(self):
		return self.err_msg


class LineError(LineException):
	"""General error thrower for errors in asm code.

	Attributes:
		LINE_OBJ -- line object you want to throw an exception for
		REASON -- reason for exception being thrown
	"""

	def __init__(self, LINE_OBJ=None, REASON=""):
		if LINE_OBJ == None:
			super().__init__(line_num=-1, msg=str(REASON), file=None, line_ind=-1)
		else:
			super().__init__(line_num=LINE_OBJ.get_line_num(), msg=str(LINE_OBJ.get_raw()) + "\n\n" + str(REASON), file=LINE_OBJ.get_file_name(), line_ind=-1)


	

