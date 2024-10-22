import linker
import argparse






def flatten(L):

	if type(L) == type(list()) or type(L) == type(tuple()):
		out = []

		for x in L:
			for el in flatten(x):
				out.append(el)

		return out
	else:
		return [L]



if __name__ == "__main__":

	rel_args = None


	parser = argparse.ArgumentParser(description="Link .rel files into a code ROM.")

	parser.add_argument("rel_files", nargs="+", action="append", default=[], help="REL files to link")

	parser.add_argument("-r", dest="rel_args", type=str, nargs="+", action="append", default=[], help="REL section offsets.", required=True)

	parser.add_argument("-o", dest="outputfile", type=str, help="Output file.", required=True)

	parser.add_argument("-ls", dest="mapfile", type=str, help="Map file.")


	KNOWN_ARGS, EXTRA_ARGS = parser.parse_known_args()


	REL_OPTIONS = []

	ARGS = vars(KNOWN_ARGS)



	r_args = ",".join(flatten(ARGS["rel_args"]))
	for a in ("".join(r_args.split())).split(","):
		REL_OPTIONS.append(a)


	
	


	#ROM_SIZE = ARGS["rom_size"]


	#print(ARGS["rel_files"][0])



	linker.DO_LINK({
		"rel_files": ARGS["rel_files"][0],
		"-r": ",".join(REL_OPTIONS),
		"outputfile": ARGS["outputfile"],
		#"ROM_SIZE": ROM_SIZE,
		"map_file": ARGS["mapfile"]
		})