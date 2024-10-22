###################################################
#   RICOH as65c assembler remake
#      by MrL314
#
#        [ Aug.24, 2021 ]
###################################################


import argparse
import assembler
import util


if __name__ == "__main__":
	parser = argparse.ArgumentParser(description="Assemble a .asm file into a .rel file")

	parser.add_argument("file", metavar="file", type=str, help="Name of file to assemble")

	parser.add_argument("-f", dest="force_assemble", action="store_true", help="Force file to be assembled")

	parser.add_argument("-v", dest="p_verbose", action="store_true", help="Print debugging information")

	parser.add_argument("-w", dest="WARG", action="store_true", help="unknown as of this time")

	parser.add_argument("-d", dest="asm_vars", type=str, nargs="*", action="append", default=[], help="Extra variables to pass in to the assembler.")    

	parser.add_argument("-lw", dest="LWARG", action="store_true", help="unknown as of this time")
	
	parser.add_argument("-l", dest="LARG", action="store_true", help="unknown as of this time")
	



	KNOWN_ARGS, EXTRA_ARGS = parser.parse_known_args()


	ARGS = vars(KNOWN_ARGS)
	

	ASM_ARGS = EXTRA_ARGS

	optional_args = {}
	'''
	for ARG in ASM_ARGS:
		sp = ARG.split("=")
		if len(sp) != 2:
			raise Exception("Invalid option format " + str(ARG))

		try:
			if sp[0][0] != "-":
				raise Exception("Invalid option format " + str(ARG))
			optional_args[sp[0][1:]] = int(sp[1])
		except ValueError:
			raise Exception("Invalid option format " + str(ARG))
	'''




	for ARG in util.flatten_list(ARGS["asm_vars"]):

		sp = ARG.split("=")
		if len(sp) != 2:
			raise Exception("Invalid option format " + str(ARG))

		try:
			optional_args[sp[0]] = int(sp[1], 16)
		except ValueError:
			raise Exception("Invalid option format " + str(ARG))


	#print(optional_args)
		

	force_assembly = False

	if ARGS["force_assemble"] == True:
		force_assembly = True


	FILE = ARGS["file"]
	if FILE[-4:].lower() == ".rel":
		FILE = FILE[:-4] + ".asm"

	print_verbose = False
	if ARGS["p_verbose"] == True:
		print_verbose = True



	
	assembler.assembleFile(FILE, optional_args, force_assemble=force_assembly, print_verbose=print_verbose)