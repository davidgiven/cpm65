from build.c import cprogram

cprogram(
    name="cc0",
    srcs=["./frontend.c"],
)

cprogram(
    name="cc1",
    srcs=[
        "./body.c",
        "./declaration.c",
        "./enum.c",
        "./error.c",
        "./expression.c",
        "./header.c",
        "./idxdata.c",
        "./initializer.c",
        "./label.c",
        "./lex.c",
        "./main.c",
        "./primary.c",
        "./stackframe.c",
        "./storage.c",
        "./struct.c",
        "./switch.c",
        "./symbol.c",
        "./target-6502.c",
        "./tree.c",
        "./type.c",
        "./type_iterator.c",
    ])

cprogram(
    name="cc2",
    srcs=[
        "./backend.c",
        "./backend-6502.c",
    ])
