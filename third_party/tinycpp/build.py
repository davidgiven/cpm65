from build.c import cprogram

cprogram(
    name="tinycpp",
    srcs=[
        "./cppmain.c",
        "./preproc.c",
        "./preproc.h",
        "./tokenizer.c",
        "./tokenizer.h",
    ],
    deps=["third_party/libulz"],
)
