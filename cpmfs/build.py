from tools.build import unixtocpm

for f in ["asm", "atbasic", "bedit", "pasc"]:
    unixtocpm(name="%s_txt_cpm" % f, src="./%s.txt" % f)

unixtocpm(name="demo_sub_cpm", src="./demo.sub")
unixtocpm(name="hello_asm_cpm", src="./hello.asm")
unixtocpm(name="hello_pas_cpm", src="./hello.pas")
unixtocpm(name="triangle_frt_cpm", src="./triangle.frt")
